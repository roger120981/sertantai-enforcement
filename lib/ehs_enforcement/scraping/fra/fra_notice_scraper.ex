defmodule EhsEnforcement.Scraping.Fra.FraNoticeScraper do
  @moduledoc """
  Fire and Rescue Authorities (FRA) notice scraping service.

  Scrapes enforcement data from the NFCC (National Fire Chiefs Council) register:
  - Prohibition Notices - prohibit use of premises until fire safety issues resolved
  - Enforcement Notices - require specific improvements within timeframe
  - Alterations Notices - require notification before changes affecting fire safety

  Data source: https://nfcc.org.uk/our-services/enforcement-register/

  The NFCC register uses wpDataTables with server-side processing. Data is fetched
  via AJAX API calls with pagination support. Total records: ~7,700 notices from
  47 Fire & Rescue Authorities across England and Wales.

  Legal basis: Regulatory Reform (Fire Safety) Order 2005, Articles 29-31
  """

  require Logger

  @page_url "https://nfcc.org.uk/our-services/enforcement-register/"
  @ajax_url "https://nfcc.org.uk/wp-admin/admin-ajax.php?action=get_wdtable&table_id=6"
  @max_retries 3
  @retry_delay_ms 1000
  @default_page_size 100

  # Column indices from wpDataTables configuration
  @col_uprn 0
  @col_frs 1
  @col_issue_date 2
  @col_notice_type 3
  @col_premises_type 4
  @col_status 5
  @col_address 6
  @col_responsible_person 7
  @col_date_complied_with 8
  @col_reasons 9
  @col_additional_info 10

  defmodule ScrapedNotice do
    @moduledoc "Struct representing a scraped FRA notice before processing"

    @derive Jason.Encoder
    defstruct [
      :uprn,
      :frs,
      :issue_date,
      :notice_type,
      :premises_type,
      :status,
      :address,
      :responsible_person,
      :date_complied_with,
      :reasons,
      :additional_information,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all FRA notices from the NFCC enforcement register.

  Returns {:ok, [%ScrapedNotice{}]} or {:error, reason}

  Options:
  - :notice_type - Filter by notice type: "PROHIBITION", "ENFORCEMENT", "ALTERATIONS", or nil (all)
  - :frs - Filter by Fire & Rescue Service name
  - :status - Filter by status: "IN FORCE", "COMPLIED", etc.
  - :page_size - Records per page (default: 100)
  - :max_pages - Maximum pages to fetch (default: all)
  """
  def scrape_all(opts \\ []) do
    notice_type_filter = Keyword.get(opts, :notice_type)
    frs_filter = Keyword.get(opts, :frs)
    status_filter = Keyword.get(opts, :status)
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    max_pages = Keyword.get(opts, :max_pages)

    Logger.info("FRA: Scraping enforcement notices",
      notice_type: notice_type_filter,
      frs: frs_filter,
      status: status_filter,
      page_size: page_size
    )

    # First, get the nonce from the main page
    with {:ok, nonce} <- fetch_nonce(),
         {:ok, all_notices} <-
           fetch_all_pages(nonce, page_size, max_pages, %{
             notice_type: notice_type_filter,
             frs: frs_filter,
             status: status_filter
           }) do
      Logger.info("FRA: Successfully scraped #{length(all_notices)} notices")
      {:ok, all_notices}
    else
      {:error, reason} = error ->
        Logger.error("FRA: Failed to scrape notices: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Scrape only Prohibition notices.
  """
  def scrape_prohibition_notices(opts \\ []) do
    scrape_all(Keyword.put(opts, :notice_type, "PROHIBITION"))
  end

  @doc """
  Scrape only Enforcement notices.
  """
  def scrape_enforcement_notices(opts \\ []) do
    scrape_all(Keyword.put(opts, :notice_type, "ENFORCEMENT"))
  end

  @doc """
  Scrape only Alterations notices.
  """
  def scrape_alterations_notices(opts \\ []) do
    scrape_all(Keyword.put(opts, :notice_type, "ALTERATIONS"))
  end

  @doc """
  Get the total count of records without fetching all data.

  Returns {:ok, count} or {:error, reason}
  """
  def get_total_count do
    with {:ok, nonce} <- fetch_nonce(),
         {:ok, %{"recordsTotal" => total}} <- fetch_page(nonce, 0, 1, %{}) do
      {:ok, String.to_integer(total)}
    end
  end

  # Private functions

  defp fetch_nonce do
    Logger.debug("FRA: Fetching wpDataTables nonce from page")

    case fetch_with_retry(@page_url, @max_retries) do
      {:ok, html} ->
        # Extract nonce: wdtNonceFrontendServerSide_6" value="5ecb12f2d6"
        case Regex.run(~r/wdtNonceFrontendServerSide_6"\s+value="([^"]+)"/, html) do
          [_, nonce] ->
            Logger.debug("FRA: Got nonce: #{nonce}")
            {:ok, nonce}

          nil ->
            Logger.error("FRA: Could not find wpDataTables nonce in page")
            {:error, :nonce_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_pages(nonce, page_size, max_pages, filters) do
    timestamp = DateTime.utc_now()

    # First request to get total count
    case fetch_page(nonce, 0, page_size, filters) do
      {:ok,
       %{"recordsTotal" => total_str, "recordsFiltered" => filtered_str, "data" => first_data}} ->
        total = String.to_integer(total_str)
        filtered = String.to_integer(filtered_str)

        Logger.info("FRA: Total records: #{total}, Filtered: #{filtered}")

        # Calculate number of pages needed
        total_pages = ceil(filtered / page_size)

        pages_to_fetch =
          if max_pages, do: min(total_pages, max_pages), else: total_pages

        Logger.info("FRA: Fetching #{pages_to_fetch} pages of #{page_size} records each")

        # Parse first page
        first_notices = parse_data_rows(first_data, timestamp)

        # Fetch remaining pages if needed
        if pages_to_fetch > 1 do
          remaining_notices =
            2..pages_to_fetch
            |> Enum.reduce_while([], fn page_num, acc ->
              start = (page_num - 1) * page_size

              Logger.debug("FRA: Fetching page #{page_num}/#{pages_to_fetch} (start: #{start})")

              case fetch_page(nonce, start, page_size, filters) do
                {:ok, %{"data" => data}} ->
                  notices = parse_data_rows(data, timestamp)
                  {:cont, acc ++ notices}

                {:error, reason} ->
                  Logger.error("FRA: Failed to fetch page #{page_num}: #{inspect(reason)}")
                  {:halt, {:error, reason}}
              end
            end)

          case remaining_notices do
            {:error, _} = error -> error
            notices when is_list(notices) -> {:ok, first_notices ++ notices}
          end
        else
          {:ok, first_notices}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_page(nonce, start, length, filters) do
    body = build_request_body(nonce, start, length, filters)

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Referer", @page_url},
      {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}
    ]

    case Req.post(@ajax_url, body: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp build_request_body(nonce, start, length, filters) do
    # Build column parameters
    columns =
      [
        {"columns[0][data]", "0"},
        {"columns[0][name]", "uprn"},
        {"columns[0][searchable]", "true"},
        {"columns[0][orderable]", "true"},
        {"columns[1][data]", "1"},
        {"columns[1][name]", "FRS"},
        {"columns[1][searchable]", "true"},
        {"columns[1][orderable]", "true"},
        {"columns[2][data]", "2"},
        {"columns[2][name]", "issue_date"},
        {"columns[2][searchable]", "true"},
        {"columns[2][orderable]", "true"},
        {"columns[3][data]", "3"},
        {"columns[3][name]", "notice_type"},
        {"columns[3][searchable]", "true"},
        {"columns[3][orderable]", "true"},
        {"columns[4][data]", "4"},
        {"columns[4][name]", "premises_type"},
        {"columns[4][searchable]", "true"},
        {"columns[4][orderable]", "true"},
        {"columns[5][data]", "5"},
        {"columns[5][name]", "status"},
        {"columns[5][searchable]", "true"},
        {"columns[5][orderable]", "true"},
        {"columns[6][data]", "6"},
        {"columns[6][name]", "address_label"},
        {"columns[6][searchable]", "true"},
        {"columns[6][orderable]", "true"},
        {"columns[7][data]", "7"},
        {"columns[7][name]", "responsible_person"},
        {"columns[7][searchable]", "true"},
        {"columns[7][orderable]", "true"},
        {"columns[8][data]", "8"},
        {"columns[8][name]", "date_complied_with"},
        {"columns[8][searchable]", "true"},
        {"columns[8][orderable]", "true"},
        {"columns[9][data]", "9"},
        {"columns[9][name]", "reasons"},
        {"columns[9][searchable]", "true"},
        {"columns[9][orderable]", "true"},
        {"columns[10][data]", "10"},
        {"columns[10][name]", "Additional Information"},
        {"columns[10][searchable]", "true"},
        {"columns[10][orderable]", "true"}
      ]

    # Base parameters
    base_params = [
      {"draw", "1"},
      {"start", Integer.to_string(start)},
      {"length", Integer.to_string(length)},
      {"wdtNonce", nonce},
      {"order[0][column]", "2"},
      {"order[0][dir]", "desc"}
    ]

    # Add column search filters if provided
    filter_params = build_filter_params(filters)

    # Combine all parameters
    all_params = base_params ++ columns ++ filter_params

    # URL encode
    URI.encode_query(all_params)
  end

  defp build_filter_params(filters) do
    []
    |> maybe_add_filter(3, filters[:notice_type])
    |> maybe_add_filter(1, filters[:frs])
    |> maybe_add_filter(5, filters[:status])
  end

  defp maybe_add_filter(params, _col, nil), do: params

  defp maybe_add_filter(params, col, value) do
    params ++
      [
        {"columns[#{col}][search][value]", value},
        {"columns[#{col}][search][regex]", "false"}
      ]
  end

  defp fetch_with_retry(url, retries) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} when status >= 500 ->
        Logger.warning("FRA: Server error HTTP #{status}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("FRA: HTTP error: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  defp parse_data_rows(rows, timestamp) when is_list(rows) do
    Enum.map(rows, fn row ->
      %ScrapedNotice{
        uprn: get_cell(row, @col_uprn),
        frs: get_cell(row, @col_frs),
        issue_date: get_cell(row, @col_issue_date),
        notice_type: get_cell(row, @col_notice_type),
        premises_type: get_cell(row, @col_premises_type),
        status: get_cell(row, @col_status),
        address: get_cell(row, @col_address) |> normalize_address(),
        responsible_person: get_cell(row, @col_responsible_person),
        date_complied_with: get_cell(row, @col_date_complied_with),
        reasons: get_cell(row, @col_reasons) |> normalize_text(),
        additional_information: get_cell(row, @col_additional_info) |> normalize_text(),
        scrape_timestamp: timestamp
      }
    end)
  end

  defp get_cell(row, index) when is_list(row) do
    case Enum.at(row, index) do
      nil -> nil
      "" -> nil
      value when is_binary(value) -> String.trim(value)
      value -> value
    end
  end

  defp normalize_address(nil), do: nil

  defp normalize_address(address) do
    address
    |> String.replace("\r\n", ", ")
    |> String.replace("\n", ", ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/,\s*,/, ",")
    |> String.trim()
    |> String.trim_trailing(",")
  end

  defp normalize_text(nil), do: nil
  defp normalize_text(""), do: nil

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end
end
