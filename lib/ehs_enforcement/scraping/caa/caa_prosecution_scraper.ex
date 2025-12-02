defmodule EhsEnforcement.Scraping.Caa.CaaProsecutionScraper do
  @moduledoc """
  Civil Aviation Authority (CAA) prosecution scraping service.

  Scrapes prosecution data from CAA's annual PDF reports:
  - Criminal convictions for aviation offences
  - Fines and sentences imposed by courts

  Data source: https://www.caa.co.uk/our-work/about-us/enforcement/enforcement-and-prosecutions/

  ## Available Data

  - **2017-2025**: Annual prosecution reports in PDF format
  - Typically 5-10 prosecutions per year
  - PDF text is clean and extractable via pdftotext

  ## PDF Structure

  Each prosecution entry contains:
  - Defendant: Name of the convicted person
  - Brief Description: Narrative of the offence
  - Date: Sentencing/hearing date (DD/MM/YYYY)
  - Court: Name of the court
  - Sentence: Fine amount (e.g., "Fine £1,500")

  ## Offence Types

  Common aviation offences include:
  - Low flying over congested areas
  - Flying without valid licence/rating
  - Flying in controlled airspace without clearance
  - Organising flying display without permission
  - Failing to maintain radio communication
  - Negligently endangering aircraft
  """

  require Logger

  alias EhsEnforcement.Scraping.Caa.CaaAiPdfParser

  @prosecutions_page_url "https://www.caa.co.uk/our-work/about-us/enforcement/enforcement-and-prosecutions/"
  @base_url "https://www.caa.co.uk"
  @max_retries 3
  @retry_delay_ms 1000

  # Years that use modern format (regex-parseable)
  @modern_format_years ["2024-2025", "2023-2024"]
  # Years that use legacy format (require AI parsing)
  @legacy_format_years [
    "2022-2023",
    "2021-2022",
    "2020-2021",
    "2019-2020",
    "2018-2019",
    "2017-2018"
  ]

  # PDF URLs by fiscal year (April to March)
  @pdf_urls %{
    "2024-2025" => "/media/etyjyn35/caa-prosecutions-2024-2025.pdf",
    "2023-2024" => "/media/tnbb5cgd/caa-prosecutions-2023-2024.pdf",
    "2022-2023" => "/media/u5qjzyf4/caa-prosecutions-2022-2023.pdf",
    "2021-2022" => "/media/0fypuori/caa-prosecutions-2021-2022.pdf",
    "2020-2021" => "/media/5w1of1h3/caa-prosecutions-2020-2021.pdf",
    "2019-2020" => "/media/21jlpnif/caa-prosecutions-2019-2020.pdf",
    "2018-2019" => "/media/ez5otyz2/caa-prosecutions-2018-2019.pdf",
    "2017-2018" => "/media/502jda0o/caa-prosecutions-2017-2018.pdf"
  }

  defmodule ScrapedProsecution do
    @moduledoc "Struct representing a scraped CAA prosecution before processing"

    @derive Jason.Encoder
    defstruct [
      :fiscal_year,
      :defendant,
      :brief_description,
      :date,
      :court,
      :sentence,
      :fine_amount,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all CAA prosecutions from all available PDF reports.

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}

  Options:
  - :years - List of fiscal years to include (e.g., ["2024-2025", "2023-2024"])
             Default: all available years
  """
  def scrape_all(opts \\ []) do
    filter_years = Keyword.get(opts, :years, nil)
    timestamp = DateTime.utc_now()

    years_to_scrape =
      if filter_years do
        filter_years
      else
        Map.keys(@pdf_urls)
      end

    Logger.info("CAA: Scraping prosecutions for years: #{inspect(years_to_scrape)}")

    results =
      years_to_scrape
      |> Enum.map(fn year ->
        case scrape_year(year, timestamp) do
          {:ok, prosecutions} ->
            prosecutions

          {:error, reason} ->
            Logger.warning("CAA: Failed to scrape year #{year}: #{inspect(reason)}")
            []
        end
      end)
      |> List.flatten()

    Logger.info("CAA: Successfully scraped #{length(results)} prosecutions total")
    {:ok, results}
  end

  @doc """
  Scrape prosecutions for a specific fiscal year.

  Returns {:ok, [%ScrapedProsecution{}]} or {:error, reason}
  """
  def scrape_year(fiscal_year, timestamp \\ DateTime.utc_now()) do
    case Map.get(@pdf_urls, fiscal_year) do
      nil ->
        {:error, {:unknown_year, fiscal_year}}

      pdf_path ->
        url = @base_url <> pdf_path
        Logger.info("CAA: Scraping prosecutions from #{url}")

        with {:ok, pdf_binary} <- download_pdf(url),
             {:ok, text} <- extract_text_from_pdf(pdf_binary) do
          prosecutions = parse_pdf_text(text, fiscal_year, timestamp)
          Logger.info("CAA: Parsed #{length(prosecutions)} prosecutions from #{fiscal_year}")
          {:ok, prosecutions}
        end
    end
  end

  @doc """
  Get list of available fiscal years.
  """
  def available_years, do: Map.keys(@pdf_urls) |> Enum.sort(:desc)

  @doc """
  Get list of years that use modern format (regex-parseable).
  """
  def modern_format_years, do: @modern_format_years

  @doc """
  Get list of years that use legacy format (require AI parsing).
  """
  def legacy_format_years, do: @legacy_format_years

  @doc """
  Check if a fiscal year uses the legacy format.
  """
  def legacy_format_year?(fiscal_year), do: fiscal_year in @legacy_format_years

  @doc """
  Get the prosecutions page URL.
  """
  def prosecutions_page_url, do: @prosecutions_page_url

  @doc """
  Extract raw PDF text for a specific fiscal year.

  This is useful for AI parsing when you need the raw text content.
  Returns {:ok, text} or {:error, reason}
  """
  def extract_pdf_text(fiscal_year) do
    case Map.get(@pdf_urls, fiscal_year) do
      nil ->
        {:error, {:unknown_year, fiscal_year}}

      pdf_path ->
        url = @base_url <> pdf_path
        Logger.info("CAA: Extracting PDF text from #{url}")

        with {:ok, pdf_binary} <- download_pdf(url),
             {:ok, text} <- extract_text_from_pdf(pdf_binary) do
          {:ok, text}
        end
    end
  end

  @doc """
  Scrape a legacy format year using AI parsing.

  This function downloads the PDF, extracts text, and uses the AI parser
  to extract structured prosecution data.

  Returns {:ok, [%CaaAiPdfParser.ParsedProsecution{}]} or {:error, reason}
  """
  def scrape_legacy_year_with_ai(fiscal_year) do
    if not legacy_format_year?(fiscal_year) do
      Logger.warning(
        "CAA: Year #{fiscal_year} is not a legacy format year, using standard parser"
      )

      scrape_year(fiscal_year)
    else
      Logger.info("CAA: Using AI parser for legacy format year #{fiscal_year}")

      with {:ok, text} <- extract_pdf_text(fiscal_year),
           {:ok, parsed_prosecutions} <- CaaAiPdfParser.parse_pdf_text(text, fiscal_year) do
        Logger.info(
          "CAA: AI parser extracted #{length(parsed_prosecutions)} prosecutions from #{fiscal_year}"
        )

        {:ok, parsed_prosecutions}
      end
    end
  end

  @doc """
  Check if AI parsing is available (client configured).
  """
  def ai_parsing_available? do
    CaaAiPdfParser.available?()
  end

  @doc """
  Parse PDF text content and extract prosecutions.

  This is the main parsing function, exposed for testing with fixtures.
  Automatically detects whether the PDF uses the modern (2023+) or legacy (pre-2023) format.
  """
  def parse_pdf_text(text, fiscal_year, timestamp) do
    # Detect format based on presence of "Defendant" as a header label (modern format)
    # vs table-based layout with DEFENDANT column header (legacy format)
    if modern_format?(text) do
      parse_modern_format(text, fiscal_year, timestamp)
    else
      parse_legacy_format(text, fiscal_year, timestamp)
    end
  end

  @doc """
  Parse modern format PDF text (2023+).

  Modern format has labeled fields:
  ```
  Defendant
  Barry SCOTT
  Brief Description
  ...
  Date
  28/05/2024
  ```
  """
  def parse_modern_format(text, fiscal_year, timestamp) do
    entries = split_into_entries(text)

    entries
    |> Enum.map(fn entry -> parse_prosecution_entry(entry, fiscal_year, timestamp) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Parse legacy format PDF text (pre-2023).

  Legacy format uses a spatial table layout that cannot be reliably parsed with regex.
  This function returns an empty list - use CaaAiPdfParser for legacy format PDFs.

  See Phase 6 in the session document for details on the AI-powered approach.
  """
  def parse_legacy_format(_text, fiscal_year, _timestamp) do
    Logger.info(
      "CAA: Legacy format detected for #{fiscal_year} - requires AI parsing (not implemented yet)"
    )

    # Return empty list - legacy format requires AI parsing
    # TODO: Integrate with CaaAiPdfParser when implemented
    []
  end

  # Detect if text uses modern format (has "Defendant" as a label on its own line)
  # Keep this function - it's used by parse_pdf_text/3 for format detection
  defp modern_format?(text) do
    # Modern format has "Defendant\n<name>" pattern (may have leading whitespace)
    # Legacy format has "DEFENDANT" as column header followed by table rows
    has_modern_label = Regex.match?(~r/^\s*Defendant\s*$/m, text)
    has_legacy_header = Regex.match?(~r/DEFENDANT\s+BRIEF DESCRIPTION/m, text)

    has_modern_label and not has_legacy_header
  end

  @doc """
  Parse a fine amount from sentence text.

  Handles formats:
  - "Fine £1,500" -> 1500
  - "Fine £4,000" -> 4000
  - "Fine £78,444.19" -> 78444.19
  """
  def parse_fine_amount(nil), do: nil

  def parse_fine_amount(sentence_text) do
    case Regex.run(~r/(?:Fine\s+)?£([\d,]+(?:\.\d+)?)/i, sentence_text) do
      [_, amount] ->
        amount
        |> String.replace(",", "")
        |> parse_decimal()

      nil ->
        nil
    end
  end

  # Private functions

  defp download_pdf(url) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}
    ]

    case fetch_with_retry(url, headers, @max_retries) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:download_failed, reason}}
    end
  end

  defp fetch_with_retry(url, headers, retries) do
    case Req.get(url, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, {:not_found, url}}

      {:ok, %{status: status}} when status >= 500 ->
        Logger.warning("CAA: Server error HTTP #{status} for #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, headers, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("CAA: Network error for #{url}: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, headers, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  defp extract_text_from_pdf(pdf_binary) do
    # Write PDF to temp file
    temp_path =
      Path.join(System.tmp_dir!(), "caa_prosecution_#{:erlang.unique_integer([:positive])}.pdf")

    try do
      File.write!(temp_path, pdf_binary)

      # Use pdftotext to extract text
      case System.cmd("pdftotext", ["-layout", temp_path, "-"], stderr_to_stdout: true) do
        {text, 0} ->
          {:ok, text}

        {error, _code} ->
          Logger.error("CAA: pdftotext failed: #{error}")
          {:error, {:pdftotext_failed, error}}
      end
    after
      File.rm(temp_path)
    end
  end

  defp split_into_entries(text) do
    # Clean the text first - remove headers/footers
    cleaned =
      text
      |> String.replace(~r/OFFICIAL - Public.*?\n/i, "")
      |> String.replace(~r/CAA Successful Prosecutions\n/i, "")
      |> String.replace(~r/\d+ April \d{4} to \d+ March \d{4}\n/i, "")

    # Split by "Defendant" field - each prosecution starts with "Defendant" on its own line
    # Match "Defendant" with optional leading whitespace
    parts = String.split(cleaned, ~r/(?=^\s*Defendant\s*$)/m)

    # Filter out empty or header-only parts
    parts
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn part ->
      String.starts_with?(part, "Defendant") and String.length(part) > 50
    end)
  end

  defp parse_prosecution_entry(entry, fiscal_year, timestamp) do
    # Extract defendant name (line after "Defendant")
    # Fields have leading whitespace in the PDF layout
    defendant =
      extract_field(
        entry,
        ~r/Defendant\s*\n\s*(.+?)(?=\n\s*(?:Brief Description|Date|Court|$))/ms
      )

    # Skip if no defendant found
    if is_nil(defendant) or String.length(String.trim(defendant)) < 2 do
      nil
    else
      # Extract other fields - account for leading whitespace
      brief_description = extract_field(entry, ~r/Brief Description\s*\n(.+?)(?=\n\s*Date\b)/ms)
      date = extract_field(entry, ~r/Date\s*\n\s*(\d{2}\/\d{2}\/\d{4})/m)
      court = extract_field(entry, ~r/Court\s*\n\s*(.+?)(?=\n\s*(?:Sentence|Fine|$))/ms)
      sentence = extract_field(entry, ~r/(?:Sentence\s*\n\s*|^\s*)(Fine\s+£[\d,]+(?:\.\d+)?)/m)

      # Parse fine amount
      fine_amount = parse_fine_amount(sentence)

      %ScrapedProsecution{
        fiscal_year: fiscal_year,
        defendant: clean_text(defendant),
        brief_description: clean_text(brief_description),
        date: date,
        court: clean_text(court),
        sentence: clean_text(sentence),
        fine_amount: fine_amount,
        scrape_timestamp: timestamp
      }
    end
  end

  defp extract_field(text, pattern) do
    case Regex.run(pattern, text, capture: :all_but_first) do
      [match | _] -> String.trim(match)
      nil -> nil
    end
  end

  defp clean_text(nil), do: nil

  defp clean_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
end
