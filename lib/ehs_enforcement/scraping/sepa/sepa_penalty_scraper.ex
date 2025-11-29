defmodule EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper do
  @moduledoc """
  SEPA penalty scraping service.

  Scrapes enforcement data from the Scottish Environment Protection Agency:
  - Fixed Monetary Penalties (FMP) - £300, £600, £1,000
  - Variable Monetary Penalties (VMP) - discretionary amounts
  - Enforcement Undertakings - voluntary compliance agreements
  - Costs Recovery Notices - recovery of enforcement costs

  Data source: https://beta.sepa.scot/regulation/enforcement/penalties-and-undertakings/

  Unlike HSE/EA, SEPA publishes all data on a single page organized by year
  in Bootstrap accordion sections. No pagination is needed.
  """

  require Logger

  @base_url "https://beta.sepa.scot/regulation/enforcement/penalties-and-undertakings/"
  @max_retries 3
  @retry_delay_ms 1000

  defmodule ScrapedPenalty do
    @moduledoc "Struct representing a scraped SEPA penalty before processing"

    @derive Jason.Encoder
    defstruct [
      :penalty_type,
      :name_and_address,
      :date,
      :offence_details,
      :penalty_amount,
      :documentation_url,
      :legislation_breached,
      :year,
      :section_type,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all SEPA penalties and undertakings from the enforcement page.

  Returns {:ok, [%ScrapedPenalty{}]} or {:error, reason}

  Options:
  - :section - Filter by section type: :penalties, :undertakings, :costs_recovery, or :all (default)
  - :year - Filter by year (e.g., 2024)
  """
  def scrape_all(opts \\ []) do
    section_filter = Keyword.get(opts, :section, :all)
    year_filter = Keyword.get(opts, :year)

    Logger.info("SEPA: Scraping enforcement data",
      section: section_filter,
      year: year_filter
    )

    with {:ok, html} <- fetch_page_html(),
         {:ok, all_records} <- parse_all_sections(html) do
      # Apply filters
      filtered_records =
        all_records
        |> filter_by_section(section_filter)
        |> filter_by_year(year_filter)

      Logger.info("SEPA: Successfully scraped #{length(filtered_records)} records")
      {:ok, filtered_records}
    else
      {:error, reason} = error ->
        Logger.error("SEPA: Failed to scrape penalties: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Scrape only penalties (FMP and VMP).

  Returns {:ok, [%ScrapedPenalty{}]} or {:error, reason}
  """
  def scrape_penalties(opts \\ []) do
    scrape_all(Keyword.put(opts, :section, :penalties))
  end

  @doc """
  Scrape only enforcement undertakings.

  Returns {:ok, [%ScrapedPenalty{}]} or {:error, reason}
  """
  def scrape_undertakings(opts \\ []) do
    scrape_all(Keyword.put(opts, :section, :undertakings))
  end

  @doc """
  Scrape only costs recovery notices.

  Returns {:ok, [%ScrapedPenalty{}]} or {:error, reason}
  """
  def scrape_costs_recovery(opts \\ []) do
    scrape_all(Keyword.put(opts, :section, :costs_recovery))
  end

  # Private functions

  defp fetch_page_html do
    fetch_with_retry(@base_url, @max_retries)
  end

  defp fetch_with_retry(url, retries) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} when status >= 500 ->
        Logger.warning("SEPA: Server error HTTP #{status}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("SEPA: HTTP error: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  defp parse_all_sections(html) do
    try do
      {:ok, document} = Floki.parse_document(html)
      timestamp = DateTime.utc_now()

      # Parse each section
      penalties = parse_penalties_section(document, timestamp)
      undertakings = parse_undertakings_section(document, timestamp)
      costs_recovery = parse_costs_recovery_section(document, timestamp)

      all_records = penalties ++ undertakings ++ costs_recovery

      Logger.info(
        "SEPA: Parsed #{length(penalties)} penalties, #{length(undertakings)} undertakings, #{length(costs_recovery)} costs recovery notices"
      )

      {:ok, all_records}
    rescue
      error ->
        Logger.error("SEPA: Failed to parse HTML: #{inspect(error)}")
        {:error, {:parse_error, error}}
    end
  end

  defp parse_penalties_section(document, timestamp) do
    # Find the "Penalties imposed by year" section
    # The section starts with h2#anchor-penaltiesimposedbyyear
    # Tables are inside accordion items following that h2

    document
    |> find_section_tables("anchor-penaltiesimposedbyyear")
    |> Enum.flat_map(fn {year, table} ->
      parse_penalty_table(table, year, :penalties, timestamp)
    end)
  end

  defp parse_undertakings_section(document, timestamp) do
    # Find the "Undertakings by year" section
    document
    |> find_section_tables("anchor-undertakingsbyyear")
    |> Enum.flat_map(fn {year, table} ->
      parse_undertaking_table(table, year, timestamp)
    end)
  end

  defp parse_costs_recovery_section(document, timestamp) do
    # Find the "Costs Recovery Notices issued by year" section
    document
    |> find_section_tables("anchor-costsrecoverynoticesissuedbyyear")
    |> Enum.flat_map(fn {year, table} ->
      parse_costs_recovery_table(table, year, timestamp)
    end)
  end

  defp find_section_tables(document, anchor_id) do
    # Find the h2 with the anchor ID, then find the accordion following it
    # Each accordion-item contains a year button and a table

    # Strategy: Find all accordion-items that follow the h2 with this anchor
    # The page structure is: h2#anchor -> div.accordion -> div.accordion-item*

    # Find the accordion that follows the h2 with this ID
    # We'll look for accordion divs and match based on proximity to the anchor

    document
    |> Floki.find(
      "h2[id='#{anchor_id}'] + .accordion .accordion-item, h2##{anchor_id} + .accordion .accordion-item"
    )
    |> Enum.map(fn accordion_item ->
      # Extract year from button text
      year =
        accordion_item
        |> Floki.find(".accordion-button")
        |> Floki.text()
        |> String.trim()
        |> parse_year()

      # Extract the table from the accordion body
      table = Floki.find(accordion_item, "table")

      {year, table}
    end)
    |> Enum.reject(fn {year, table} -> is_nil(year) or table == [] end)
  end

  defp parse_year(text) do
    case Integer.parse(text) do
      {year, _} when year >= 2000 and year <= 2100 -> year
      _ -> nil
    end
  end

  defp parse_penalty_table(table, year, section_type, timestamp) do
    # Penalty table columns:
    # 0: Type of penalty
    # 1: Name and address
    # 2: Date of penalty
    # 3: Details of offence/breach
    # 4: Penalty amount
    # 5: Penalty documentation

    table
    |> Floki.find("tbody tr")
    |> Enum.map(fn row ->
      cells = Floki.find(row, "td")

      if length(cells) >= 5 do
        %ScrapedPenalty{
          penalty_type: get_cell_text(cells, 0),
          name_and_address: get_cell_text(cells, 1),
          date: get_cell_text(cells, 2),
          offence_details: get_cell_text(cells, 3),
          penalty_amount: parse_penalty_amount(get_cell_text(cells, 4)),
          documentation_url: get_cell_link(cells, 5),
          legislation_breached: nil,
          year: year,
          section_type: section_type,
          scrape_timestamp: timestamp
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_undertaking_table(table, year, timestamp) do
    # Undertaking table columns:
    # 0: Type of undertaking
    # 1: Name and address
    # 2: Date undertaking accepted by SEPA
    # 3: Details of offence
    # 4: Legislation breached
    # 5: Enforcement undertaking documentation

    table
    |> Floki.find("tbody tr")
    |> Enum.map(fn row ->
      cells = Floki.find(row, "td")

      if length(cells) >= 5 do
        %ScrapedPenalty{
          penalty_type: get_cell_text(cells, 0),
          name_and_address: get_cell_text(cells, 1),
          date: get_cell_text(cells, 2),
          offence_details: get_cell_text(cells, 3),
          legislation_breached: get_cell_text(cells, 4),
          documentation_url: get_cell_link(cells, 5),
          penalty_amount: nil,
          year: year,
          section_type: :undertakings,
          scrape_timestamp: timestamp
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_costs_recovery_table(table, year, timestamp) do
    # Costs Recovery table columns:
    # 0: Action
    # 1: Name and address
    # 2: Costs Recovery Notice Issue Date
    # 3: Costs Recovery Amount

    table
    |> Floki.find("tbody tr")
    |> Enum.map(fn row ->
      cells = Floki.find(row, "td")

      if length(cells) >= 4 do
        %ScrapedPenalty{
          penalty_type: get_cell_text(cells, 0),
          name_and_address: get_cell_text(cells, 1),
          date: get_cell_text(cells, 2),
          penalty_amount: parse_penalty_amount(get_cell_text(cells, 3)),
          offence_details: nil,
          legislation_breached: nil,
          documentation_url: nil,
          year: year,
          section_type: :costs_recovery,
          scrape_timestamp: timestamp
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_cell_text(cells, index) do
    case Enum.at(cells, index) do
      nil -> nil
      cell -> cell |> Floki.text() |> String.trim() |> normalize_text()
    end
  end

  defp get_cell_link(cells, index) do
    case Enum.at(cells, index) do
      nil ->
        nil

      cell ->
        case Floki.find(cell, "a") do
          [] -> nil
          [{"a", attrs, _} | _] -> Enum.find_value(attrs, fn {k, v} -> if k == "href", do: v end)
          _ -> nil
        end
    end
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

  defp parse_penalty_amount(nil), do: nil
  defp parse_penalty_amount(""), do: nil

  defp parse_penalty_amount(text) do
    # Parse amounts like "£600", "£2,642.01", etc.
    case Regex.run(~r/£([\d,]+(?:\.\d{2})?)/, text) do
      [_, amount_str] ->
        amount_str
        |> String.replace(",", "")
        |> Decimal.parse()
        |> case do
          {decimal, _} -> decimal
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp filter_by_section(records, :all), do: records

  defp filter_by_section(records, :penalties),
    do: Enum.filter(records, &(&1.section_type == :penalties))

  defp filter_by_section(records, :undertakings),
    do: Enum.filter(records, &(&1.section_type == :undertakings))

  defp filter_by_section(records, :costs_recovery),
    do: Enum.filter(records, &(&1.section_type == :costs_recovery))

  defp filter_by_year(records, nil), do: records
  defp filter_by_year(records, year), do: Enum.filter(records, &(&1.year == year))
end
