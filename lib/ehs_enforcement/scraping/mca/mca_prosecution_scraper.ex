defmodule EhsEnforcement.Scraping.Mca.McaProsecutionScraper do
  @moduledoc """
  Maritime and Coastguard Agency (MCA) prosecution scraping service.

  Scrapes prosecution data from GOV.UK MCA publications:
  - Court cases against vessel owners, companies, masters and officers
  - Sentences including fines, costs, imprisonment, community service

  Data source: https://www.gov.uk/government/collections/prosecutions-and-detentions-mca-enforcement-policy-and-information

  ## Available Years

  - **2020-2025**: HTML format (structured pages on GOV.UK)
  - **2010-2019**: PDF format (requires separate extraction)

  This scraper focuses on HTML pages (2020+). For PDF extraction, use the
  `scrape_pdf_year/1` function which requires system `pdftotext` utility.

  ## Data Volume

  Approximately 5-10 prosecutions per year (~50 total for HTML years).

  ## Legislation

  Common citations include:
  - Merchant Shipping Act 1995
  - Merchant Shipping (ISM Code) Regulations 2014
  - Fishing Vessels (Codes of Practice) Regulations 2017
  """

  require Logger

  @base_url "https://www.gov.uk"
  @collection_url "#{@base_url}/government/collections/prosecutions-and-detentions-mca-enforcement-policy-and-information"
  @max_retries 3
  @retry_delay_ms 1000

  # URL patterns for prosecution reports (HTML format)
  @html_year_urls %{
    2025 =>
      "/government/publications/regulatory-compliance-investigations-team-prosecutions-2025/prosecutions-report-2025",
    2024 =>
      "/government/publications/mca-enforcement-unit-prosecutions-2024/prosecutions-report-2024",
    2023 =>
      "/government/publications/mca-enforcement-unit-prosecutions-2023/prosecutions-report-2023",
    2022 =>
      "/government/publications/mca-enforcement-unit-prosecutions-2022/prosecutions-report-2022",
    2021 =>
      "/government/publications/mca-enforcement-unit-prosecutions-2021/prosecutions-report-2021",
    2020 => "/government/publications/mca-enforcement-unit-prosecutions-2020/prosecutions-2020"
  }

  defmodule ScrapedProsecution do
    @moduledoc "Struct representing a scraped MCA prosecution before processing"

    @derive Jason.Encoder
    defstruct [
      :year,
      :case_title,
      :defendant,
      :defendant_age,
      :defendant_location,
      :hearing_date,
      :court,
      :offences,
      :details,
      :fine,
      :costs,
      :victim_surcharge,
      :custodial_sentence,
      :community_service_hours,
      :total_penalty,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all MCA prosecutions from HTML pages (2020-2025).

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}

  Options:
  - :years - List of years to scrape (default: all available HTML years)
  - :include_pdf_years - Include PDF years 2010-2019 (default: false)
  """
  def scrape_all(opts \\ []) do
    years = Keyword.get(opts, :years, Map.keys(@html_year_urls))
    include_pdf = Keyword.get(opts, :include_pdf_years, false)

    Logger.info("MCA: Scraping prosecutions for years: #{inspect(years)}")

    timestamp = DateTime.utc_now()

    # Scrape HTML years
    html_results =
      years
      |> Enum.filter(&Map.has_key?(@html_year_urls, &1))
      |> Enum.reduce({[], []}, fn year, {all_cases, all_errors} ->
        case scrape_year(year, timestamp) do
          {:ok, cases} ->
            Logger.info("MCA: Scraped #{length(cases)} cases for #{year}")
            {all_cases ++ cases, all_errors}

          {:error, reason} ->
            Logger.warning("MCA: Failed to scrape #{year}: #{inspect(reason)}")
            {all_cases, [{year, reason} | all_errors]}
        end
      end)

    # Optionally include PDF years
    {html_cases, html_errors} = html_results

    {all_cases, all_errors} =
      if include_pdf do
        pdf_years = Enum.filter(2010..2019, &(&1 in years))

        Enum.reduce(pdf_years, {html_cases, html_errors}, fn year, {cases, errors} ->
          case scrape_pdf_year(year, timestamp) do
            {:ok, pdf_cases} ->
              {cases ++ pdf_cases, errors}

            {:error, reason} ->
              {cases, [{year, reason} | errors]}
          end
        end)
      else
        {html_cases, html_errors}
      end

    if all_errors == [] do
      Logger.info("MCA: Successfully scraped #{length(all_cases)} total prosecutions")
      {:ok, all_cases}
    else
      Logger.warning(
        "MCA: Scraped #{length(all_cases)} prosecutions with #{length(all_errors)} year errors"
      )

      {:ok, all_cases, errors: Enum.reverse(all_errors)}
    end
  end

  @doc """
  Scrape prosecutions for a specific year (HTML format).

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}
  """
  def scrape_year(year, timestamp \\ DateTime.utc_now())

  def scrape_year(year, _timestamp) when year < 2020 or year > 2025 do
    {:error, {:year_not_available, year}}
  end

  def scrape_year(year, timestamp) when year in 2020..2025 do
    url = Map.get(@html_year_urls, year)

    if url do
      full_url = @base_url <> url
      Logger.info("MCA: Scraping #{year} from #{full_url}")

      case fetch_with_retry(full_url, @max_retries) do
        {:ok, html} ->
          cases = parse_prosecution_page(html, year, timestamp)
          {:ok, cases}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:year_not_available, year}}
    end
  end

  @doc """
  Scrape prosecutions from PDF for historical years (2010-2019).

  Requires `pdftotext` (poppler-utils) to be installed on the system.

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}
  """
  def scrape_pdf_year(year, timestamp \\ DateTime.utc_now()) when year in 2010..2019 do
    Logger.info("MCA: PDF scraping for #{year} - checking pdftotext availability")

    # Check if pdftotext is available
    case System.cmd("which", ["pdftotext"], stderr_to_stdout: true) do
      {_, 0} ->
        fetch_and_parse_pdf(year, timestamp)

      {_, _} ->
        Logger.warning("MCA: pdftotext not available, skipping PDF year #{year}")
        {:error, {:pdftotext_not_available, "Install poppler-utils for PDF extraction"}}
    end
  end

  @doc """
  Get available years for HTML scraping.
  """
  def available_html_years, do: Map.keys(@html_year_urls) |> Enum.sort(:desc)

  @doc """
  Get the collection page URL.
  """
  def collection_url, do: @collection_url

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
        Logger.warning("MCA: Server error HTTP #{status} for #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("MCA: Network error for #{url}: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  defp parse_prosecution_page(html, year, timestamp) do
    # Parse HTML using Floki
    {:ok, document} = Floki.parse_document(html)

    # GOV.UK prosecution pages use numbered h2 elements for cases
    # Pattern: <h2 id="slug">N. Case Title</h2>
    # Cookie banner and other h2s don't match this pattern
    document
    |> Floki.find("h2[id]")
    |> Enum.filter(fn h2_element ->
      # Only include h2s that start with a number (case sections)
      text = Floki.text(h2_element) |> String.trim()
      Regex.match?(~r/^\d+\.\s+/, text)
    end)
    |> Enum.map(fn h2_element ->
      parse_case_section(h2_element, document, year, timestamp)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_case_section(h2_element, document, year, timestamp) do
    case_title_raw = Floki.text(h2_element) |> String.trim()

    # Remove the number prefix (e.g., "1. " -> "")
    case_title = Regex.replace(~r/^\d+\.\s*/, case_title_raw, "")

    # Get the h2's ID to find associated h3 sections
    h2_id = Floki.attribute(h2_element, "id") |> List.first()

    # Extract case number from title (e.g., "1" from "1. Boat owner...")
    case_num =
      case Regex.run(~r/^(\d+)\./, case_title_raw) do
        [_, num] -> num
        nil -> nil
      end

    if case_num do
      # Find h3 elements that belong to this case (e.g., "1.1 Defendant", "1.2 Date of hearing")
      # The h3 IDs have patterns like "defendant", "defendant-1", "defendant-2" etc.
      # But the text starts with "X.Y" matching the case number

      # Extract section content by finding h3s with matching case number prefix
      defendant_info = extract_section_by_pattern(document, case_num, ["defendant"])
      hearing_date_text = extract_section_by_pattern(document, case_num, ["date of hearing"])
      details = extract_section_by_pattern(document, case_num, ["details", "detail"])

      # Parse defendant info (name, age, location)
      {defendant_name, defendant_age, defendant_location} = parse_defendant(defendant_info)

      # Parse hearing date
      parsed_date = parse_hearing_date(hearing_date_text)

      # Extract court from details
      court = extract_court(details)

      # Extract penalties from details
      {fine, costs, victim_surcharge, custodial, community_hours, total} =
        extract_penalties(details)

      # Extract offences/legislation
      offences = extract_offences(details)

      %ScrapedProsecution{
        year: year,
        case_title: case_title,
        defendant: defendant_name,
        defendant_age: defendant_age,
        defendant_location: defendant_location,
        hearing_date: parsed_date,
        court: court,
        offences: offences,
        details: normalize_text(details),
        fine: fine,
        costs: costs,
        victim_surcharge: victim_surcharge,
        custodial_sentence: custodial,
        community_service_hours: community_hours,
        total_penalty: total,
        scrape_timestamp: timestamp
      }
    else
      Logger.warning("MCA: Could not parse case number from: #{case_title_raw}, h2_id: #{h2_id}")
      nil
    end
  end

  defp extract_section_by_pattern(document, case_num, section_keywords) do
    # Find h3 elements that match pattern "X.Y section_keyword" where X is the case number
    h3_elements = Floki.find(document, "h3")

    matching_h3 =
      Enum.find(h3_elements, fn h3 ->
        text = Floki.text(h3) |> String.downcase() |> String.trim()

        # Check if text starts with "X.Y" where X matches case_num
        case Regex.run(~r/^(\d+)\.\d+\s+(.+)/, text) do
          [_, num, rest] when num == case_num ->
            Enum.any?(section_keywords, fn kw ->
              String.contains?(rest, String.downcase(kw))
            end)

          _ ->
            false
        end
      end)

    if matching_h3 do
      # Get the h3's ID to find following paragraph(s)
      h3_id = Floki.attribute(matching_h3, "id") |> List.first()

      # Find all paragraphs that follow this h3 until the next h2 or h3
      # Use CSS selector to find sibling elements
      extract_paragraphs_after_h3(document, h3_id)
    else
      nil
    end
  end

  defp extract_paragraphs_after_h3(document, h3_id) when is_binary(h3_id) do
    # Get the raw HTML and find paragraphs between this h3 and the next h2/h3
    # This is a workaround since Floki doesn't have easy sibling traversal

    html = Floki.raw_html(document)

    # Find content between this h3 and the next h2 or h3
    pattern =
      ~r/<h3[^>]*id="#{Regex.escape(h3_id)}"[^>]*>.*?<\/h3>\s*(.*?)(?=<h[23]|<\/article|$)/is

    case Regex.run(pattern, html) do
      [_, content] ->
        # Parse the content and extract text from paragraphs
        {:ok, fragment} = Floki.parse_fragment(content)

        fragment
        |> Floki.find("p")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      nil ->
        nil
    end
  end

  defp extract_paragraphs_after_h3(_document, _h3_id), do: nil

  defp parse_defendant(nil), do: {nil, nil, nil}

  defp parse_defendant(defendant_text) do
    # Pattern: "Name, age X" or "Name (age X, Location)" or "Name, X, Location"
    text = String.trim(defendant_text)

    # Try pattern: "Name, age X"
    case Regex.run(~r/^(.+?),?\s*age[d]?\s*(\d+)/i, text) do
      [_, name, age] ->
        {String.trim(name), String.to_integer(age), extract_location(text)}

      nil ->
        # Try pattern: "Name (X, Location)" where X is age
        case Regex.run(~r/^(.+?)\s*\((\d+),?\s*(.+?)\)/i, text) do
          [_, name, age, location] ->
            {String.trim(name), String.to_integer(age), String.trim(location)}

          nil ->
            # Just use the whole text as name
            {text, nil, nil}
        end
    end
  end

  defp extract_location(text) do
    # Try to extract location from end of text
    case Regex.run(~r/,\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s*$/, text) do
      [_, location] -> location
      nil -> nil
    end
  end

  defp parse_hearing_date(nil), do: nil

  defp parse_hearing_date(date_text) do
    # Pattern: "DD Month YYYY" e.g., "14 February 2025"
    text = String.trim(date_text)

    case Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})/, text) do
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

  defp extract_court(nil), do: nil

  defp extract_court(details) do
    # Pattern: "at [Court Name] Court" or "[Court Name] Magistrates Court"
    patterns = [
      ~r/(?:at\s+)?(\w+(?:\s+\w+)*\s+(?:Crown|Magistrates['']?)\s+Court)/i,
      ~r/(Southampton|Portsmouth|Plymouth|Cardiff|Bristol|Liverpool|Manchester|Newcastle|Hull)\s+(?:Crown|Magistrates['']?)\s+Court/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, details) do
        [match | _] -> String.trim(match)
        nil -> nil
      end
    end)
  end

  defp extract_penalties(nil), do: {nil, nil, nil, nil, nil, nil}

  defp extract_penalties(details) do
    fine = extract_money_amount(details, ["fine", "fined"])
    costs = extract_money_amount(details, ["cost", "costs", "prosecution costs"])
    surcharge = extract_money_amount(details, ["victim surcharge", "surcharge"])

    custodial = extract_custodial_sentence(details)
    community_hours = extract_community_service(details)

    total =
      if fine || costs || surcharge do
        Decimal.add(
          fine || Decimal.new(0),
          Decimal.add(costs || Decimal.new(0), surcharge || Decimal.new(0))
        )
      else
        nil
      end

    {fine, costs, surcharge, custodial, community_hours, total}
  end

  defp extract_money_amount(text, keywords) do
    # Build pattern for each keyword
    patterns =
      Enum.map(keywords, fn keyword ->
        ~r/#{keyword}[^\d]*£([\d,]+(?:\.\d{2})?)/i
      end)

    # Also try pattern: "£X,XXX in [keyword]"
    reverse_patterns =
      Enum.map(keywords, fn keyword ->
        ~r/£([\d,]+(?:\.\d{2})?)\s*(?:in\s+)?#{keyword}/i
      end)

    all_patterns = patterns ++ reverse_patterns

    Enum.find_value(all_patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, amount_str] ->
          amount_str
          |> String.replace(",", "")
          |> Decimal.new()

        nil ->
          nil
      end
    end)
  end

  defp extract_custodial_sentence(text) do
    # Patterns: "X weeks/months in prison", "X weeks/months imprisonment", "X weeks suspended"
    patterns = [
      ~r/(\d+)\s+(weeks?|months?)\s+(?:in\s+)?(?:prison|imprisonment|jail)/i,
      ~r/(\d+)\s+(weeks?|months?)\s+(?:custody|custodial)/i,
      ~r/(\d+)\s+(weeks?|months?)\s+suspended/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [match | _] -> String.trim(match)
        nil -> nil
      end
    end)
  end

  defp extract_community_service(text) do
    # Pattern: "X hours of unpaid work" or "X hours community service"
    case Regex.run(~r/(\d+)\s+hours?\s+(?:of\s+)?(?:unpaid\s+work|community\s+service)/i, text) do
      [_, hours] -> String.to_integer(hours)
      nil -> nil
    end
  end

  defp extract_offences(nil), do: []

  defp extract_offences(details) do
    # Look for legislation citations
    patterns = [
      # "Section X of the Act Name YYYY"
      ~r/(Section\s+\d+[A-Za-z]?(?:\(\d+\))?)\s+(?:of\s+)?(?:the\s+)?(.+?(?:Act|Regulations?)\s+\d{4})/i,
      # "Regulation X of the Regulations YYYY"
      ~r/(Regulation\s+\d+[A-Za-z]?(?:\(\d+\))?)\s+(?:of\s+)?(?:the\s+)?(.+?Regulations?\s+\d{4})/i,
      # "contrary to Section X"
      ~r/contrary\s+to\s+(Section\s+\d+[A-Za-z]?(?:\(\d+\))?)\s+(?:of\s+)?(?:the\s+)?(.+?(?:Act|Regulations?)\s+\d{4})/i
    ]

    Enum.flat_map(patterns, fn pattern ->
      Regex.scan(pattern, details)
      |> Enum.map(fn
        [_full, section, legislation] ->
          %{
            section: String.trim(section),
            legislation: String.trim(legislation)
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.uniq()
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # PDF extraction functions

  defp fetch_and_parse_pdf(year, timestamp) do
    # First, get the PDF URL from the publication page
    pub_url = "#{@base_url}/government/publications/mca-enforcement-unit-prosecutions-#{year}"

    case fetch_with_retry(pub_url, @max_retries) do
      {:ok, html} ->
        case extract_pdf_url(html) do
          {:ok, pdf_url} ->
            download_and_parse_pdf(pdf_url, year, timestamp)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_pdf_url(html) do
    {:ok, document} = Floki.parse_document(html)

    # Find PDF links
    pdf_links =
      document
      |> Floki.find("a[href$='.pdf']")
      |> Enum.map(fn a -> Floki.attribute(a, "href") |> List.first() end)
      |> Enum.reject(&is_nil/1)

    case pdf_links do
      [pdf_url | _] ->
        full_url =
          if String.starts_with?(pdf_url, "http") do
            pdf_url
          else
            @base_url <> pdf_url
          end

        {:ok, full_url}

      [] ->
        {:error, :pdf_not_found}
    end
  end

  defp download_and_parse_pdf(pdf_url, year, timestamp) do
    Logger.info("MCA: Downloading PDF from #{pdf_url}")

    # Create temp file
    temp_path = "/tmp/mca_prosecutions_#{year}.pdf"

    case Req.get(pdf_url, into: File.stream!(temp_path)) do
      {:ok, %{status: 200}} ->
        # Extract text using pdftotext
        case System.cmd("pdftotext", ["-layout", temp_path, "-"], stderr_to_stdout: true) do
          {text, 0} ->
            _ = File.rm(temp_path)
            cases = parse_pdf_text(text, year, timestamp)
            {:ok, cases}

          {error, _} ->
            _ = File.rm(temp_path)
            {:error, {:pdftotext_error, error}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:download_error, reason}}
    end
  end

  defp parse_pdf_text(text, year, timestamp) do
    # PDF parsing is more complex - split by case markers
    # This is a simplified implementation
    Logger.info("MCA: Parsing PDF text for #{year} (#{String.length(text)} chars)")

    # Split by common case separators
    # PDF structure varies by year, so this is a best-effort approach
    text
    |> String.split(~r/(?=Defendant:|DEFENDANT:)/i)
    |> Enum.drop(1)
    |> Enum.map(fn case_text ->
      parse_pdf_case(case_text, year, timestamp)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_pdf_case(case_text, year, timestamp) do
    # Extract defendant
    defendant =
      case Regex.run(~r/Defendant[s]?:\s*(.+?)(?:\n|$)/i, case_text) do
        [_, name] -> String.trim(name)
        nil -> nil
      end

    if defendant do
      # Extract hearing date
      hearing_date =
        case Regex.run(~r/(?:Date of )?[Hh]earing[s]?:\s*(.+?)(?:\n|$)/i, case_text) do
          [_, date] -> parse_hearing_date(date)
          nil -> nil
        end

      # Extract details (everything after Details:)
      details =
        case Regex.run(~r/Details?:\s*(.+)/is, case_text) do
          [_, text] -> normalize_text(text)
          nil -> normalize_text(case_text)
        end

      {fine, costs, surcharge, custodial, community_hours, total} = extract_penalties(details)

      %ScrapedProsecution{
        year: year,
        case_title: "#{defendant} (#{year})",
        defendant: defendant,
        defendant_age: nil,
        defendant_location: nil,
        hearing_date: hearing_date,
        court: extract_court(details),
        offences: extract_offences(details),
        details: details,
        fine: fine,
        costs: costs,
        victim_surcharge: surcharge,
        custodial_sentence: custodial,
        community_service_hours: community_hours,
        total_penalty: total,
        scrape_timestamp: timestamp
      }
    else
      nil
    end
  end
end
