defmodule EhsEnforcement.Scraping.Orr.OrrNoticeScraper do
  @moduledoc """
  Office of Rail and Road (ORR) notice scraping service.

  Scrapes improvement and prohibition notices from ORR's enforcement pages:
  - Improvement Notices - require safety improvements within timeframe
  - Prohibition Notices - prohibit activities until safety issues resolved

  Data sources:
  - Improvement: https://www.orr.gov.uk/.../improvement-notices
  - Prohibition: https://www.orr.gov.uk/.../prohibition-notices

  ## Available Data

  - **Improvement Notices**: 2012-present (~5-10 per year)
  - **Prohibition Notices**: 2012-present (~1-3 per year)

  ## URL Patterns

  - 2021-2025: `/improvement-notices/[YEAR]` or `/prohibition-notices/[YEAR]`
  - 2012-2020: Legacy URL format under `/rail/publications/enforcement-publications/`

  ## PDF Access

  Notice PDFs available at:
  `https://orrprdpubreg1.blob.core.windows.net/docs/[REFERENCE]-[company-slug]-[type]-notice.pdf`
  """

  require Logger

  @base_url "https://www.orr.gov.uk"
  @improvement_base "/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/improvement-notices"
  @prohibition_base "/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prohibition-notices"

  @max_retries 3
  @retry_delay_ms 1000

  # Years with available data
  @improvement_years 2012..2025 |> Enum.to_list()
  @prohibition_years [2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020, 2021, 2022, 2023]

  defmodule ScrapedNotice do
    @moduledoc "Struct representing a scraped ORR notice before processing"

    @derive Jason.Encoder
    defstruct [
      :notice_type,
      :year,
      :company,
      :reference,
      :issue_date,
      :compliance_date,
      :status,
      :description,
      :pdf_url,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all ORR notices (both improvement and prohibition).

  Returns {:ok, [%ScrapedNotice{}]} or {:error, reason}

  Options:
  - :notice_type - :improvement, :prohibition, or nil (both)
  - :years - List of years to scrape (default: all available)
  """
  def scrape_all(opts \\ []) do
    notice_type = Keyword.get(opts, :notice_type)
    filter_years = Keyword.get(opts, :years)

    timestamp = DateTime.utc_now()

    notices =
      case notice_type do
        :improvement ->
          scrape_improvement_notices(filter_years, timestamp)

        :prohibition ->
          scrape_prohibition_notices(filter_years, timestamp)

        nil ->
          improvement = scrape_improvement_notices(filter_years, timestamp)
          prohibition = scrape_prohibition_notices(filter_years, timestamp)
          improvement ++ prohibition
      end

    Logger.info("ORR: Successfully scraped #{length(notices)} notices")
    {:ok, notices}
  end

  @doc """
  Scrape improvement notices for specified years (or all available years).
  """
  def scrape_improvement_notices(filter_years \\ nil, timestamp \\ DateTime.utc_now()) do
    years = filter_years || @improvement_years

    Logger.info("ORR: Scraping improvement notices for years: #{inspect(years)}")

    years
    |> Enum.filter(&(&1 in @improvement_years))
    |> Enum.flat_map(fn year ->
      case scrape_improvement_year(year, timestamp) do
        {:ok, notices} ->
          Logger.debug("ORR: Scraped #{length(notices)} improvement notices for #{year}")
          notices

        {:error, reason} ->
          Logger.warning(
            "ORR: Failed to scrape improvement notices for #{year}: #{inspect(reason)}"
          )

          []
      end
    end)
  end

  @doc """
  Scrape prohibition notices for specified years (or all available years).
  """
  def scrape_prohibition_notices(filter_years \\ nil, timestamp \\ DateTime.utc_now()) do
    years = filter_years || @prohibition_years

    Logger.info("ORR: Scraping prohibition notices for years: #{inspect(years)}")

    years
    |> Enum.filter(&(&1 in @prohibition_years))
    |> Enum.flat_map(fn year ->
      case scrape_prohibition_year(year, timestamp) do
        {:ok, notices} ->
          Logger.debug("ORR: Scraped #{length(notices)} prohibition notices for #{year}")
          notices

        {:error, reason} ->
          Logger.warning(
            "ORR: Failed to scrape prohibition notices for #{year}: #{inspect(reason)}"
          )

          []
      end
    end)
  end

  @doc """
  Scrape improvement notices for a specific year.
  """
  def scrape_improvement_year(year, timestamp \\ DateTime.utc_now()) do
    url = build_year_url(:improvement, year)
    Logger.debug("ORR: Fetching improvement notices from #{url}")

    case fetch_with_retry(url, @max_retries) do
      {:ok, html} ->
        notices = parse_notices_page(html, :improvement, year, timestamp)
        {:ok, notices}

      {:error, {:not_found, _}} ->
        Logger.debug("ORR: No improvement notices page for #{year}")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Scrape prohibition notices for a specific year.
  """
  def scrape_prohibition_year(year, timestamp \\ DateTime.utc_now()) do
    url = build_year_url(:prohibition, year)
    Logger.debug("ORR: Fetching prohibition notices from #{url}")

    case fetch_with_retry(url, @max_retries) do
      {:ok, html} ->
        notices = parse_notices_page(html, :prohibition, year, timestamp)
        {:ok, notices}

      {:error, {:not_found, _}} ->
        Logger.debug("ORR: No prohibition notices page for #{year}")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get available years for improvement notices.
  """
  def improvement_years, do: @improvement_years

  @doc """
  Get available years for prohibition notices.
  """
  def prohibition_years, do: @prohibition_years

  # Public parsing function for testing

  @doc """
  Parse notices from HTML content.

  This function is public for testing purposes with fixtures.

  ## Parameters
  - html: Raw HTML string from the ORR notice page
  - notice_type: :improvement or :prohibition
  - year: The year being scraped
  - timestamp: DateTime when scraping occurred

  ## Returns
  List of %ScrapedNotice{} structs
  """
  def parse_notices_page(html, notice_type, year, timestamp) do
    {:ok, document} = Floki.parse_document(html)

    # Find all h2 elements that contain notice headings
    # Pattern: "Improvement Notice issued to [Company]" or "Prohibition Notice issued to [Company]"
    type_str = if notice_type == :improvement, do: "Improvement", else: "Prohibition"

    document
    |> Floki.find("h2")
    |> Enum.filter(fn h2 ->
      text = Floki.text(h2)
      String.contains?(text, "#{type_str} Notice issued to")
    end)
    |> Enum.map(fn h2 ->
      parse_notice_from_h2(document, h2, notice_type, year, timestamp)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_notice_from_h2(document, h2, notice_type, year, timestamp) do
    # Extract company name from h2 text
    h2_text = Floki.text(h2)
    type_str = if notice_type == :improvement, do: "Improvement", else: "Prohibition"

    company =
      case Regex.run(~r/#{type_str} Notice issued to (.+)/i, h2_text) do
        [_, company_name] -> String.trim(company_name)
        nil -> nil
      end

    if company do
      # Get the raw HTML to find sibling elements
      html = Floki.raw_html(document)

      # Find the position of this h2 in the document
      h2_html = Floki.raw_html(h2)

      # Extract the section between this h2 and the next h2 (or end)
      section_html = extract_section_after_h2(html, h2_html)

      # Parse metadata from the ul/li structure in this section
      {:ok, section_doc} = Floki.parse_document(section_html)

      metadata = extract_metadata_from_section(section_doc)
      description = extract_description_from_section(section_doc)

      %ScrapedNotice{
        notice_type: notice_type,
        year: year,
        company: company,
        reference: metadata[:reference],
        issue_date: metadata[:issue_date],
        compliance_date: metadata[:compliance_date],
        status: metadata[:status],
        description: description,
        pdf_url: build_pdf_url(metadata[:reference], company, notice_type),
        scrape_timestamp: timestamp
      }
    else
      nil
    end
  end

  defp extract_section_after_h2(html, h2_html) do
    # Split HTML at the h2 position and take content until next h2
    case String.split(html, h2_html, parts: 2) do
      [_, after_h2] ->
        # Take content until next h2 or end
        case Regex.run(~r/^(.*?)(?=<h2|$)/is, after_h2) do
          [_, section] -> section
          nil -> after_h2
        end

      _ ->
        ""
    end
  end

  defp extract_metadata_from_section(section_doc) do
    # Find all li elements and extract metadata
    li_elements = Floki.find(section_doc, "li")

    Enum.reduce(li_elements, %{}, fn li, acc ->
      text = Floki.text(li)

      cond do
        String.contains?(text, "Issue date:") ->
          date = extract_date_value(text, "Issue date:")
          Map.put(acc, :issue_date, date)

        String.contains?(text, "Compliance date:") ->
          date = extract_date_value(text, "Compliance date:")
          Map.put(acc, :compliance_date, date)

        String.contains?(text, "Status:") ->
          status = extract_field_value(text, "Status:")
          Map.put(acc, :status, status)

        String.contains?(text, "Public register ID:") ->
          # Reference is in an anchor tag within the li
          ref =
            li
            |> Floki.find("a")
            |> Floki.text()
            |> String.trim()

          if ref != "", do: Map.put(acc, :reference, ref), else: acc

        true ->
          acc
      end
    end)
  end

  defp extract_date_value(text, field_name) do
    text
    |> String.replace(field_name, "")
    |> String.trim()
  end

  defp extract_field_value(text, field_name) do
    text
    |> String.replace(field_name, "")
    |> String.trim()
  end

  defp extract_description_from_section(section_doc) do
    # Description is typically in a <p> tag after the <ul>
    section_doc
    |> Floki.find("p")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.at(0)
  end

  # Private functions

  defp build_year_url(notice_type, year) do
    base =
      case notice_type do
        :improvement -> @improvement_base
        :prohibition -> @prohibition_base
      end

    # URL pattern varies by year
    if year >= 2021 do
      "#{@base_url}#{base}/#{year}"
    else
      # Legacy URL format
      type_str = if notice_type == :improvement, do: "improvement", else: "prohibition"

      "#{@base_url}/rail/publications/enforcement-publications/#{type_str}-notices/#{type_str}-notices-#{year}"
    end
  end

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

  defp build_pdf_url(nil, _company, _notice_type), do: nil

  defp build_pdf_url(reference, company, notice_type) do
    # Convert reference to URL format
    # I/20241205/MDB/01 -> I-20241205-MDB-01
    ref_slug =
      reference
      |> String.replace("/", "-")
      |> String.replace(~r/[^a-zA-Z0-9\-]/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    # Create company slug
    company_slug =
      company
      |> String.replace(~r/[^a-zA-Z0-9\s]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 50)
      |> String.trim("-")

    type_str = if notice_type == :improvement, do: "improvement", else: "prohibition"

    "https://orrprdpubreg1.blob.core.windows.net/docs/#{ref_slug}-#{company_slug}-#{type_str}-notice.pdf"
  end
end
