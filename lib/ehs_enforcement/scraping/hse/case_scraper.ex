defmodule EhsEnforcement.Scraping.Hse.CaseScraper do
  @moduledoc """
  HSE case scraping service - PostgreSQL-first implementation.

  Handles HTTP scraping of HSE court case data with:
  - Clean interface for fetching cases by page or ID
  - Proper error handling and retry logic
  - Built-in duplicate detection via Ash resources
  - Rate limiting compliance
  """

  require Logger

  alias EhsEnforcement.Scraping.RateLimiter
  alias EhsEnforcement.Scraping.Shared.MonetaryParser
  alias EhsEnforcement.Utility

  @default_database "convictions"
  @base_url_template "https://resources.hse.gov.uk/%{database}/case/"
  @max_retries 3
  @retry_delay_ms 1000

  defmodule ScrapedCase do
    @moduledoc "Struct representing a scraped HSE case before processing"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :offender_name,
      :offence_action_date,
      :offender_local_authority,
      :offender_main_activity,
      :offender_industry,
      :offence_result,
      :offence_fine,
      :offence_costs,
      :offence_hearing_date,
      :offence_breaches,
      :offence_number,
      :regulator_function,
      :related_cases,
      :page_number,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape HSE cases by page number (basic info only - legacy pattern).

  Returns {:ok, [%ScrapedCase{}]} with basic case info only.
  Call scrape_case_details/2 for each case to get full details.
  """
  def scrape_page_basic(page_number, opts \\ []) do
    database = Keyword.get(opts, :database, @default_database)

    Logger.info("Scraping HSE cases (basic) - page #{page_number}, database: #{database}")

    with {:ok, html} <- fetch_page_html(page_number, database, opts),
         {:ok, cases} <- parse_cases_from_html(html, page_number) do
      Logger.info("Successfully scraped #{length(cases)} basic cases from page #{page_number}")
      {:ok, cases}
    else
      {:error, reason} = error ->
        Logger.error("Failed to scrape basic cases from page #{page_number}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Scrape HSE cases by page number (fully enriched).

  Returns {:ok, [%ScrapedCase{}]} or {:error, reason}
  """
  def scrape_page(page_number, opts \\ []) do
    database = Keyword.get(opts, :database, @default_database)

    Logger.info("Scraping HSE cases - page #{page_number}, database: #{database}")

    with {:ok, html} <- fetch_page_html(page_number, database, opts),
         {:ok, cases} <- parse_cases_from_html(html, page_number),
         {:ok, enriched_cases} <- enrich_cases_with_details(cases, database, opts) do
      Logger.info("Successfully scraped #{length(enriched_cases)} cases from page #{page_number}")
      {:ok, enriched_cases}
    else
      {:error, reason} = error ->
        Logger.error("Failed to scrape page #{page_number}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Get detailed case information for a specific case (legacy pattern).

  Returns {:ok, %ScrapedCase{}} with additional details or {:error, reason}
  """
  def scrape_case_details(regulator_id, database) do
    scrape_case_details(regulator_id, database, [])
  end

  def scrape_case_details(regulator_id, database, opts) do
    Logger.debug("Fetching case details for #{regulator_id}")

    case fetch_case_details(regulator_id, database, opts) do
      {:ok, details} ->
        {:ok, details}

      {:error, reason} = error ->
        Logger.error("Failed to fetch case details for #{regulator_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Scrape a specific HSE case by regulator ID.

  Returns {:ok, %ScrapedCase{}} or {:error, reason}
  """
  def scrape_case_by_id(regulator_id, opts \\ []) do
    database = Keyword.get(opts, :database, @default_database)

    Logger.info("Scraping HSE case by ID: #{regulator_id}")

    with {:ok, html} <- fetch_case_html_by_id(regulator_id, database, opts),
         {:ok, cases} <- parse_cases_from_html(html, nil),
         [case] <- cases,
         {:ok, [enriched_case]} <- enrich_cases_with_details([case], database, opts) do
      Logger.info("Successfully scraped case #{regulator_id}")
      {:ok, enriched_case}
    else
      [] ->
        {:error, :case_not_found}

      {:error, reason} = error ->
        Logger.error("Failed to scrape case #{regulator_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Check if a case already exists in the database via Ash.

  Returns {:ok, boolean} or {:error, reason}
  """
  def case_exists?(regulator_id) do
    alias EhsEnforcement.Enforcement.Case
    require Ash.Query

    query =
      Case
      |> Ash.Query.filter(regulator_id == ^regulator_id)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, []} -> {:ok, false}
      {:ok, [_case]} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Batch check if multiple cases exist in the database.

  Returns {:ok, %{regulator_id => boolean}} or {:error, reason}
  """
  def cases_exist?(regulator_ids) when is_list(regulator_ids) do
    try do
      results =
        Enum.reduce(regulator_ids, %{}, fn regulator_id, acc ->
          case case_exists?(regulator_id) do
            {:ok, exists?} -> Map.put(acc, regulator_id, exists?)
            # Assume doesn't exist on error
            {:error, _} -> Map.put(acc, regulator_id, false)
          end
        end)

      {:ok, results}
    rescue
      error -> {:error, error}
    end
  end

  # Private functions

  defp fetch_page_html(page_number, database, opts) do
    url = build_page_url(page_number, database)
    fetch_with_retry(url, @max_retries, opts)
  end

  defp fetch_case_html_by_id(regulator_id, database, opts) do
    url = build_case_url_by_id(regulator_id, database)
    fetch_with_retry(url, @max_retries, opts)
  end

  defp build_page_url(page_number, database) do
    base_url = String.replace(@base_url_template, "%{database}", database)
    query = "case_list.asp?PN=#{page_number}&ST=C&EO=LIKE&SN=F&SF=DN&SV=&SO=DODS"
    base_url <> query
  end

  defp build_case_url_by_id(regulator_id, database) do
    base_url = String.replace(@base_url_template, "%{database}", database)
    query = "case_list.asp?ST=C&EO=LIKE&SN=F&SF=CN&SV=#{regulator_id}"
    base_url <> query
  end

  defp fetch_with_retry(url, retries, opts) do
    case RateLimiter.rate_limited_request(url, opts) do
      {:ok, body} ->
        {:ok, body}

      {:error, :rate_limited} ->
        Logger.warning("Rate limit exceeded, waiting before retry")

        if retries > 0 do
          # Wait longer for rate limit retries
          Process.sleep(@retry_delay_ms * 3)
          fetch_with_retry(url, retries - 1, opts)
        else
          {:error, :rate_limited}
        end

      {:error, {:http_error, status}} when status >= 500 ->
        Logger.warning("Server error HTTP #{status} for URL: #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1, opts)
        else
          {:error, {:http_error, status}}
        end

      {:error, {:network_timeout, _}} ->
        Logger.warning("Network timeout for URL: #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1, opts)
        else
          {:error, {:network_timeout, url}}
        end

      {:error, reason} ->
        Logger.warning("HTTP error for URL #{url}: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1, opts)
        else
          {:error, reason}
        end
    end
  end

  defp parse_cases_from_html(html, page_number) do
    try do
      {:ok, document} = Floki.parse_document(html)

      cases =
        document
        |> Floki.find("tr")
        |> extract_table_data()
        |> parse_case_rows(page_number)

      {:ok, cases}
    rescue
      error ->
        Logger.error("Failed to parse HTML: #{inspect(error)}")
        {:error, {:parse_error, error}}
    end
  end

  defp extract_table_data(tr_elements) do
    Enum.reduce(tr_elements, [], fn
      {"tr", [], cells}, acc -> [cells | acc]
      _, acc -> acc
    end)
  end

  defp parse_case_rows(rows, page_number) do
    timestamp = DateTime.utc_now()

    Enum.reduce(rows, [], fn
      [
        {"td", _, regulator_id_content},
        {"td", _, offender_name_content},
        {"td", _, offence_action_date_content},
        {"td", _, offender_local_authority_content},
        {"td", _, offender_main_activity_content}
      ],
      acc ->
        case_data = %ScrapedCase{
          regulator_id: Floki.text(regulator_id_content) |> String.trim(),
          offender_name: Floki.text(offender_name_content) |> String.trim(),
          offence_action_date: Utility.iso_date(Floki.text(offence_action_date_content)),
          offender_local_authority: Floki.text(offender_local_authority_content) |> String.trim(),
          offender_main_activity: Floki.text(offender_main_activity_content) |> String.trim(),
          page_number: page_number,
          scrape_timestamp: timestamp
        }

        [case_data | acc]

      _, acc ->
        acc
    end)
  end

  defp enrich_cases_with_details(cases, database, opts) do
    try do
      enriched =
        Enum.map(cases, fn case_data ->
          case fetch_case_details(case_data.regulator_id, database, opts) do
            {:ok, details} -> Map.merge(case_data, details)
            # Return base case if details fail
            {:error, _} -> case_data
          end
        end)

      {:ok, enriched}
    rescue
      error -> {:error, {:enrichment_error, error}}
    end
  end

  defp fetch_case_details(regulator_id, database, opts) do
    url = build_case_details_url(regulator_id, database)

    with {:ok, html} <- fetch_with_retry(url, @max_retries, opts),
         {:ok, details} <- parse_case_details(html, database) do
      {:ok, details}
    else
      error -> error
    end
  end

  defp build_case_details_url(regulator_id, database) do
    base_url = String.replace(@base_url_template, "%{database}", database)
    query = "case_details.asp?SF=CN&SV=#{regulator_id}"
    base_url <> query
  end

  defp parse_case_details(html, database) do
    try do
      {:ok, document} = Floki.parse_document(html)

      details =
        document
        |> Floki.find("tr")
        |> extract_table_data()
        |> extract_case_details_from_rows(database)

      {:ok, details}
    rescue
      error -> {:error, {:parse_details_error, error}}
    end
  end

  defp extract_case_details_from_rows(rows, database) do
    Enum.reduce(rows, %{}, fn
      # 4-column patterns
      [
        {"td", _, cell1_content},
        {"td", _, cell2_content},
        {"td", _, cell3_content},
        {"td", _, cell4_content}
      ],
      acc ->
        # Extract text from all cells
        text1 = Floki.text(cell1_content) |> String.trim()
        text2 = Floki.text(cell2_content) |> String.trim()
        text3 = Floki.text(cell3_content) |> String.trim()
        text4 = Floki.text(cell4_content) |> String.trim()

        # Check if this is a label-value pair in columns 3-4 (cells 1-2 are empty/other)
        case {text3, text4} do
          {"HSE Directorate", value} ->
            Map.put(acc, :regulator_function, Utility.upcase_first_from_upcase_phrase(value))

          _ ->
            # Check if this is two label-value pairs (all 4 cells used)
            case {text1, text3} do
              {"Total Fine", "Total Costs Awarded to HSE"} ->
                Map.merge(acc, %{
                  offence_fine: parse_monetary_amount(text2),
                  offence_costs: parse_monetary_amount(text4)
                })

              _ ->
                # Unknown 4-column pattern, ignore
                acc
            end
        end

      # 2-column patterns (Main Activity, Industry, Local Authority)
      [{"td", _, label_content}, {"td", _, value_content}], acc ->
        label = Floki.text(label_content) |> String.trim()
        value = Floki.text(value_content) |> String.trim()

        case label do
          "Main Activity" ->
            Map.put(acc, :offender_main_activity, value)

          "Industry" ->
            Map.put(acc, :offender_industry, value)

          "Local Authority" ->
            Map.put(acc, :offender_local_authority, value)

          _ ->
            # Unknown 2-column pattern, ignore
            acc
        end

      # Single breach link
      [
        {"td", _, [{"a", [{"href", breach_url}], ["Breach involved in this Case"]} | _]}
      ],
      acc ->
        case fetch_breach_details(String.trim_leading(breach_url, "../"), database) do
          {:ok, breach_data} -> Map.merge(acc, breach_data)
          {:error, _} -> acc
        end

      # Multiple breaches link
      [
        {"td", _, [{"a", [{"href", breaches_url}], ["Breaches involved in this Case"]} | _]}
      ],
      acc ->
        case fetch_breaches_details(String.trim_leading(breaches_url, "../"), database) do
          {:ok, breaches_data} -> Map.merge(acc, breaches_data)
          {:error, _} -> acc
        end

      # Breach + Related cases
      [
        {"td", _,
         [
           {"a", [{"href", breach_url}], ["Breach involved in this Case"]},
           _,
           {"a", [{"href", related_url}], ["Related Cases"]},
           _
         ]}
      ],
      acc ->
        breach_data =
          case fetch_breach_details(String.trim_leading(breach_url, "../"), database) do
            {:ok, data} -> data
            {:error, _} -> %{}
          end

        related_data =
          case fetch_related_cases(String.trim_leading(related_url, "../"), database) do
            {:ok, cases} -> %{related_cases: cases}
            {:error, _} -> %{}
          end

        Map.merge(acc, Map.merge(breach_data, related_data))

      # Breaches + Related cases
      [
        {"td", _,
         [
           {"a", [{"href", breaches_url}], ["Breaches involved in this Case"]},
           _,
           {"a", [{"href", related_url}], ["Related Cases"]},
           _
         ]}
      ],
      acc ->
        breaches_data =
          case fetch_breaches_details(String.trim_leading(breaches_url, "../"), database) do
            {:ok, data} -> data
            {:error, _} -> %{}
          end

        related_data =
          case fetch_related_cases(String.trim_leading(related_url, "../"), database) do
            {:ok, cases} -> %{related_cases: cases}
            {:error, _} -> %{}
          end

        Map.merge(acc, Map.merge(breaches_data, related_data))

      _, acc ->
        acc
    end)
  end

  defp parse_monetary_amount(amount_str) do
    MonetaryParser.parse_monetary_amount(amount_str)
  end

  # New functions for breach and related cases scraping

  defp fetch_breach_details("breach/breach_details.asp?SF=BID&SV=" <> case_number, database) do
    url =
      "search/search.asp?ST=B&SN=F&EO=%3D&SF=CN&SV=" <> Regex.replace(~r/\d{3}$/, case_number, "")

    fetch_breaches_details(url, database)
  end

  defp fetch_breaches_details(
         "search/search.asp?ST=B&SN=F&EO=%3D&SF=CN&SV=" <> case_number,
         database
       ) do
    base_url = String.replace(@base_url_template, "%{database}", database)
    breach_base_url = String.replace(base_url, "/case/", "/breach/")
    url = breach_base_url <> "breach_list.asp?ST=B&SN=F&EO=%3D&SF=CN&SV=#{case_number}"

    with {:ok, html} <- fetch_with_retry(url, @max_retries, []),
         {:ok, breach_data} <- parse_breach_list(html) do
      {:ok, breach_data}
    else
      error -> error
    end
  end

  defp parse_breach_list(html) do
    try do
      {:ok, document} = Floki.parse_document(html)

      rows =
        document
        |> Floki.find("tr")
        |> extract_table_data()

      breach_data =
        Enum.reduce(rows, %{offence_number: 0, offence_breaches: []}, fn
          [
            {"td", _, _},
            {"td", _, _},
            {"td", _, hearing_date_content},
            {"td", _, result_content},
            {"td", _, _},
            {"td", _, breach_content}
          ],
          acc ->
            %{
              offence_number: acc.offence_number + 1,
              offence_result: Floki.text(result_content) |> String.trim(),
              offence_breaches:
                acc.offence_breaches ++ [Floki.text(breach_content) |> String.trim()],
              offence_hearing_date: Utility.iso_date(Floki.text(hearing_date_content))
            }

          _, acc ->
            acc
        end)

      # Convert breach list to string for database storage
      breach_data =
        Map.put(breach_data, :offence_breaches, Enum.join(breach_data.offence_breaches, "; "))

      {:ok, breach_data}
    rescue
      error -> {:error, {:parse_breach_error, error}}
    end
  end

  defp fetch_related_cases(
         "search/search.asp?ST=C&SN=R&EO=%3D&SF=RCN&SV=" <> case_number,
         database
       ) do
    fetch_related_cases_by_number(case_number, database)
  end

  defp fetch_related_cases_by_number(case_number, database) do
    base_url = String.replace(@base_url_template, "%{database}", database)
    url = base_url <> "case_list.asp?ST=C&SN=R&EO=%3D&SF=RCN&SV=#{case_number}"

    with {:ok, html} <- fetch_with_retry(url, @max_retries, []),
         {:ok, related_cases} <- parse_related_cases_list(html) do
      {:ok, related_cases}
    else
      error -> error
    end
  end

  defp parse_related_cases_list(html) do
    try do
      {:ok, document} = Floki.parse_document(html)

      rows =
        document
        |> Floki.find("tr")
        |> extract_table_data()

      related_cases =
        Enum.reduce(rows, [], fn
          [
            {"td", _, case_number_content},
            {"td", _, _},
            {"td", _, _},
            {"td", _, _},
            {"td", _, _}
          ],
          acc ->
            # Extract text from first cell (case number with link)
            case_number = Floki.text(case_number_content) |> String.trim()

            if case_number != "" do
              ["HSE_" <> case_number | acc]
            else
              acc
            end

          _, acc ->
            acc
        end)
        |> Enum.join(",")

      {:ok, related_cases}
    rescue
      error -> {:error, {:parse_related_cases_error, error}}
    end
  end
end
