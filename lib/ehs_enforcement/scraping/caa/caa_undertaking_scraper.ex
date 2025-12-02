defmodule EhsEnforcement.Scraping.Caa.CaaUndertakingScraper do
  @moduledoc """
  Civil Aviation Authority (CAA) undertaking scraping service.

  Scrapes undertaking data from CAA's Table of Undertakings page:
  - Voluntary agreements under Part 8 of the Enterprise Act 2002
  - Commitments from airlines and airports to address consumer law concerns

  Data source: https://www.caa.co.uk/our-work/about-us/enforcement/table-of-undertakings/

  ## HTML Structure

  The page uses accordion elements with:
  - Accordion container: `.c-accordion.js-accordion`
  - Title: `.c-accordion__button-title a` (contains "Organisation - Date")
  - Content: `.c-accordion__content.c-rich-text`
  - Fields within content: `<h3>Field:</h3>` followed by `<p>Value</p>`

  ## Common Legislation

  - Regulation 261/2004 (EU261/UK261) - Passenger rights for flight delays/cancellations
  - Regulation 1107/2006 - Disabled persons and reduced mobility access
  - Consumer Protection from Unfair Trading Regulations 2008

  ## Legal Note

  Undertakings are provided voluntarily without admission of wrongdoing.
  Only a court can decide whether a breach has occurred.
  """

  require Logger

  @undertakings_url "https://www.caa.co.uk/our-work/about-us/enforcement/table-of-undertakings/"
  @max_retries 3
  @retry_delay_ms 1000

  defmodule ScrapedUndertaking do
    @moduledoc "Struct representing a scraped CAA undertaking before processing"

    @derive Jason.Encoder
    defstruct [
      :organisation,
      :date_provided,
      :date_provided_raw,
      :legislation,
      :commitments,
      :comments,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all CAA undertakings from the Table of Undertakings page.

  Returns {:ok, [%ScrapedUndertaking{}]} or {:error, reason}
  """
  def scrape_all(opts \\ []) do
    timestamp = DateTime.utc_now()

    Logger.info("CAA: Scraping undertakings from #{@undertakings_url}")

    case fetch_with_retry(@undertakings_url, @max_retries) do
      {:ok, html} ->
        undertakings = parse_html(html, timestamp)

        # Filter by organisation if specified
        filter_org = Keyword.get(opts, :organisation, nil)

        filtered =
          if filter_org do
            Enum.filter(undertakings, fn u ->
              String.contains?(String.downcase(u.organisation), String.downcase(filter_org))
            end)
          else
            undertakings
          end

        Logger.info("CAA: Successfully scraped #{length(filtered)} undertakings")
        {:ok, filtered}

      {:error, reason} ->
        Logger.error("CAA: Failed to scrape undertakings: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get the undertakings page URL.
  """
  def undertakings_url, do: @undertakings_url

  @doc """
  Parse HTML content and extract undertakings.

  This is the main parsing function, exposed for testing with fixtures.
  """
  def parse_html(html, timestamp) do
    {:ok, document} = Floki.parse_document(html)

    # Find all accordion elements
    accordions = Floki.find(document, ".c-accordion.js-accordion")

    Logger.debug("CAA: Found #{length(accordions)} accordion sections")

    # Parse each accordion
    accordions
    |> Enum.map(fn accordion -> parse_accordion(accordion, timestamp) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Parse a date string in various formats.

  Handles:
  - "26 July 2023"
  - "14 February 2018"
  - "1 December 2017"
  """
  def parse_date(nil), do: nil

  def parse_date(date_string) when is_binary(date_string) do
    # Clean up the string
    cleaned = String.trim(date_string)

    # Try to parse "DD Month YYYY" or "D Month YYYY"
    case Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})/, cleaned) do
      [_, day, month, year] ->
        month_num = month_to_number(month)

        if month_num do
          case Date.new(
                 String.to_integer(year),
                 month_num,
                 String.to_integer(day)
               ) do
            {:ok, date} -> date
            _ -> nil
          end
        else
          nil
        end

      nil ->
        nil
    end
  end

  def parse_date(_), do: nil

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
        Logger.warning("CAA: Server error HTTP #{status} for #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("CAA: Network error for #{url}: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  defp parse_accordion(accordion, timestamp) do
    # Extract title (contains "Organisation - Date")
    title_text =
      accordion
      |> Floki.find(".c-accordion__button-title a")
      |> Floki.text()
      |> String.trim()

    # Parse organisation and date from title
    {organisation, date_raw} = parse_title(title_text)

    # Skip if no valid organisation found (organisation is always a string from parse_title)
    if organisation == "" or String.length(organisation) < 2 do
      nil
    else
      # Extract content fields
      content = Floki.find(accordion, ".c-accordion__content")

      date_provided = extract_h3_field(content, "Date provided")
      legislation = extract_h3_field(content, "Legislation")
      commitments = extract_commitments(content)
      comments = extract_h3_field(content, "Comments")

      # Parse the date
      parsed_date = parse_date(date_provided) || parse_date(date_raw)

      %ScrapedUndertaking{
        organisation: organisation,
        date_provided: parsed_date,
        date_provided_raw: date_provided || date_raw,
        legislation: legislation,
        commitments: commitments,
        comments: comments,
        scrape_timestamp: timestamp
      }
    end
  end

  defp parse_title(title_text) do
    # Title format: "Organisation - Date" e.g., "Wizz Air - 26 July 2023"
    case Regex.run(~r/^(.+?)\s*-\s*(\d{1,2}\s+\w+\s+\d{4})$/, title_text) do
      [_, org, date] ->
        {String.trim(org), String.trim(date)}

      nil ->
        # Try without date pattern (some might not have date in title)
        {String.trim(title_text), nil}
    end
  end

  defp extract_h3_field(content, field_name) do
    # Find all h3 elements
    content
    |> Floki.find("h3")
    |> Enum.find_value(fn h3 ->
      h3_text = Floki.text(h3) |> String.trim() |> String.replace(":", "")

      if String.downcase(h3_text) == String.downcase(field_name) do
        # Find the next sibling p element(s)
        # Get the raw HTML and extract text after this h3
        extract_following_text(content, field_name)
      else
        nil
      end
    end)
  end

  defp extract_following_text(content, field_name) do
    # Get the raw HTML of the content
    html = Floki.raw_html(content)

    # Pattern to find h3 with field name and capture text until next h3 or end
    # Handles both <h3>Field:</h3> and <h3><a></a>Field:</h3> patterns
    pattern =
      ~r/<h3[^>]*>(?:<a[^>]*><\/a>)?\s*#{Regex.escape(field_name)}:?\s*<\/h3>\s*(.+?)(?=<h3|<a class="c-accordion__button|$)/is

    case Regex.run(pattern, html) do
      [_, captured] ->
        # Parse the captured HTML and extract text
        case Floki.parse_fragment(captured) do
          {:ok, elements} ->
            text =
              elements
              |> Floki.text(sep: " ")
              |> clean_text()

            if String.length(text) > 0, do: text, else: nil

          _ ->
            nil
        end

      nil ->
        nil
    end
  end

  defp extract_commitments(content) do
    # Commitments may span multiple paragraphs
    # Find the "Commitments" h3 and get all following p elements until next h3
    html = Floki.raw_html(content)

    # Pattern handles both <h3>Commitments:</h3> and <h3><a></a>Commitments:</h3>
    pattern =
      ~r/<h3[^>]*>(?:<a[^>]*><\/a>)?\s*Commitments:?\s*<\/h3>\s*(.+?)(?=<h3|<a class="c-accordion__button|$)/is

    result = extract_commitments_with_pattern(html, pattern)

    # If no commitments found, try fallback for malformed entries (like Manchester Airport)
    if is_nil(result) or String.length(result) == 0 do
      # Look for the last h3 followed by multiple p tags containing commitment-like text
      # This handles cases where "Commitments:" label is missing or mislabeled
      fallback_pattern =
        ~r/<h3[^>]*>[^<]*<\/h3>\s*((?:<p>To\s.+?<\/p>\s*)+)/is

      extract_commitments_with_pattern(html, fallback_pattern)
    else
      result
    end
  end

  defp extract_commitments_with_pattern(html, pattern) do
    case Regex.run(pattern, html) do
      [_, captured] ->
        case Floki.parse_fragment(captured) do
          {:ok, elements} ->
            # Extract text from each p element separately to preserve structure
            elements
            |> Floki.find("p")
            |> Enum.map(fn p -> Floki.text(p) |> clean_text() end)
            |> Enum.reject(&(String.length(&1) == 0))
            |> Enum.join("\n\n")

          _ ->
            nil
        end

      nil ->
        nil
    end
  end

  defp clean_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp month_to_number(month) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12
    }

    Map.get(months, String.downcase(month))
  end
end
