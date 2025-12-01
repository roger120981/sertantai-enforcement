defmodule EhsEnforcement.Scraping.Orr.OrrProsecutionScraper do
  @moduledoc """
  Office of Rail and Road (ORR) prosecution scraping service.

  Scrapes prosecution data from ORR's enforcement pages:
  - Court cases against rail companies, operators, and contractors
  - Sentences including fines and costs

  Data source: https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions

  ## Available Data

  - **2016-present**: Prosecutions in HTML accordion format on single page
  - **2006-2015**: Historical prosecutions available as PDF links
  - ORR took over rail safety regulation from HSE on 1 April 2006

  ## HTML Structure

  The page uses accordion elements with:
  - Year sections: `<h2>Prosecutions in YYYY</h2>`
  - Case headers: `<h2 class="accordion__title"><span>Company (Location), sentenced DATE</span></h2>`
  - Content: `<div class="accordion__content">` containing `<h3>Field</h3><p>Value</p>` pairs

  ## Legislation

  Common citations include:
  - Health and Safety at Work etc Act 1974
  - Railways and Other Guided Transport Systems (Safety) Regulations 2006
  - Work at Height Regulations 2005
  """

  require Logger

  @prosecutions_url "https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions"
  @max_retries 3
  @retry_delay_ms 1000

  defmodule ScrapedProsecution do
    @moduledoc "Struct representing a scraped ORR prosecution before processing"

    @derive Jason.Encoder
    defstruct [
      :year,
      :company,
      :summary,
      :breaches_involved,
      :date_of_offence,
      :plea,
      :result,
      :court,
      :sentencing_date,
      :penalty,
      :penalty_amount,
      :costs,
      :costs_amount,
      :location,
      :orr_details,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all ORR prosecutions from the main prosecutions page.

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}

  Options:
  - :years - List of years to include (default: all years)
  """
  def scrape_all(opts \\ []) do
    filter_years = Keyword.get(opts, :years, nil)

    Logger.info("ORR: Scraping prosecutions from #{@prosecutions_url}")

    timestamp = DateTime.utc_now()

    case fetch_with_retry(@prosecutions_url, @max_retries) do
      {:ok, html} ->
        prosecutions = parse_html(html, timestamp)

        # Filter by years if specified
        filtered =
          if filter_years do
            Enum.filter(prosecutions, fn p -> p.year in filter_years end)
          else
            prosecutions
          end

        Logger.info("ORR: Successfully scraped #{length(filtered)} prosecutions")
        {:ok, filtered}

      {:error, reason} ->
        Logger.error("ORR: Failed to scrape prosecutions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Scrape prosecutions for a specific year.

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}
  """
  def scrape_year(year) when is_integer(year) do
    scrape_all(years: [year])
  end

  @doc """
  Get the prosecutions page URL.
  """
  def prosecutions_url, do: @prosecutions_url

  @doc """
  Parse HTML content and extract prosecutions.

  This is the main parsing function, exposed for testing with fixtures.
  """
  def parse_html(html, timestamp) do
    {:ok, document} = Floki.parse_document(html)

    # Build a map of year -> prosecution content by finding year headers and following accordions
    year_map = build_year_map(html)

    # Find all accordion content sections
    accordion_contents = Floki.find(document, ".accordion__content")

    Logger.debug("ORR: Found #{length(accordion_contents)} accordion sections")

    # Parse each accordion section and assign year
    prosecutions =
      accordion_contents
      |> Enum.map(fn content ->
        parse_accordion_content(content, year_map, timestamp)
      end)
      |> Enum.reject(&is_nil/1)

    prosecutions
  end

  @doc """
  Parse penalty amount from text.

  Handles formats:
  - "£500,000" -> 500000
  - "£78,444.19" -> 78444.19
  - "£1 million" -> 1000000
  - "£3.75 million" -> 3750000
  """
  def parse_penalty_amount(nil), do: nil

  def parse_penalty_amount(penalty_text) do
    cond do
      # Million format: "£3.75 million" or "£1 million"
      Regex.match?(~r/£([\d,.]+)\s*million/i, penalty_text) ->
        case Regex.run(~r/£([\d,.]+)\s*million/i, penalty_text) do
          [_, amount] ->
            amount
            |> String.replace(",", "")
            |> parse_decimal()
            |> multiply_if_not_nil(1_000_000)

          _ ->
            nil
        end

      # Standard format: "£500,000" or "£78,444.19"
      Regex.match?(~r/£([\d,]+(?:\.\d+)?)/i, penalty_text) ->
        case Regex.run(~r/£([\d,]+(?:\.\d+)?)/i, penalty_text) do
          [_, amount] ->
            amount
            |> String.replace(",", "")
            |> parse_decimal()

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  # Private functions

  defp fetch_with_retry(url, retries) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, {:not_found, url}}

      {:ok, %{status: status}} when status >= 500 ->
        Logger.warning("ORR: Server error HTTP #{status} for #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("ORR: Network error for #{url}: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  defp build_year_map(html) do
    # Find all "Prosecutions in YYYY" markers and their positions
    year_pattern = ~r/Prosecutions?\s+in\s+(\d{4})/i

    year_matches =
      Regex.scan(year_pattern, html, return: :index)
      |> Enum.zip(Regex.scan(year_pattern, html))
      |> Enum.map(fn {[{pos, _len} | _], [_, year]} ->
        {pos, String.to_integer(year)}
      end)
      |> Enum.sort_by(fn {pos, _} -> pos end)

    # Create a map for looking up year by position
    year_matches
  end

  defp parse_accordion_content(content_element, _year_map, timestamp) do
    html = Floki.raw_html(content_element)

    # Extract company - this is the key field
    company = extract_h3_field(html, "Company")

    # Skip if no company found (this might be a year header accordion)
    if is_nil(company) || String.length(company) < 3 do
      nil
    else
      # Extract year from sentencing date or content
      year = extract_year_from_content(html)

      # Extract all other fields
      summary = extract_h3_field(html, "Summary")
      breaches = extract_h3_field(html, "Breaches involved") || extract_h3_field(html, "Breaches")

      date_of_offence =
        extract_h3_field(html, "Date(s) of offence") || extract_h3_field(html, "Date")

      plea = extract_h3_field(html, "Plea")
      result = extract_h3_field(html, "Result")
      court = extract_h3_field(html, "Court")
      sentencing_date = extract_h3_field(html, "Sentencing date")
      penalty = extract_h3_field(html, "Penalty")
      costs = extract_h3_field(html, "Costs")

      location =
        extract_h3_field(html, "Location of offence") || extract_h3_field(html, "Location")

      orr_details = extract_h3_field(html, "ORR details") || extract_h3_field(html, "ORR")

      # Parse monetary amounts
      penalty_amount = parse_penalty_amount(penalty)
      costs_amount = parse_penalty_amount(costs)

      %ScrapedProsecution{
        year: year,
        company: company,
        summary: summary,
        breaches_involved: breaches,
        date_of_offence: date_of_offence,
        plea: plea,
        result: result,
        court: court,
        sentencing_date: sentencing_date,
        penalty: penalty,
        penalty_amount: penalty_amount,
        costs: costs,
        costs_amount: costs_amount,
        location: location,
        orr_details: orr_details,
        scrape_timestamp: timestamp
      }
    end
  end

  defp extract_h3_field(html, field_name) do
    # Pattern: <h3>Field Name&nbsp;</h3> followed by content until next <h3> or end
    # The field name may have &nbsp; or other whitespace after it

    escaped_name = Regex.escape(field_name)

    # Match h3 tag with field name, then capture everything until next h3 or closing tags
    pattern = ~r/<h3[^>]*>\s*#{escaped_name}[^<]*<\/h3>\s*(.+?)(?=<h3|<\/div>|$)/is

    case Regex.run(pattern, html) do
      [_, content] ->
        extract_text_content(content)

      nil ->
        nil
    end
  end

  defp extract_text_content(html) do
    # Parse the HTML fragment and extract text
    case Floki.parse_fragment(html) do
      {:ok, elements} ->
        text =
          elements
          |> Floki.text(sep: " ")
          |> clean_text()

        if String.length(text) > 0, do: text, else: nil

      _ ->
        # Fallback: strip tags manually
        html
        |> String.replace(~r/<[^>]+>/, " ")
        |> clean_text()
    end
  end

  defp clean_text(text) do
    text
    |> String.replace(~r/&nbsp;/i, " ")
    |> String.replace(~r/&amp;/i, "&")
    |> String.replace(~r/&[a-z]+;/i, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_year_from_content(html) do
    # Try to find year in sentencing date field first
    case Regex.run(~r/Sentencing date[^<]*<\/h3>\s*<p>([^<]+)/i, html) do
      [_, date_text] ->
        case Regex.run(~r/(\d{4})/, date_text) do
          [_, year] -> String.to_integer(year)
          nil -> extract_year_fallback(html)
        end

      nil ->
        extract_year_fallback(html)
    end
  end

  defp extract_year_fallback(html) do
    # Look for any year in common date patterns
    case Regex.run(~r/(?:sentenced|date)[^<]*(\d{4})/i, html) do
      [_, year] ->
        String.to_integer(year)

      nil ->
        # Last resort: find any recent year
        case Regex.run(~r/\b(202[0-5]|201[6-9])\b/, html) do
          [_, year] -> String.to_integer(year)
          nil -> nil
        end
    end
  end

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp multiply_if_not_nil(nil, _), do: nil
  defp multiply_if_not_nil(decimal, multiplier), do: Decimal.mult(decimal, multiplier)
end
