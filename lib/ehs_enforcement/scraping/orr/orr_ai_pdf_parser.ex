defmodule EhsEnforcement.Scraping.Orr.OrrAiPdfParser do
  @moduledoc """
  AI-powered parser for ORR prosecution PDF documents.

  Uses LLM to extract structured enforcement case data from unstructured
  PDF text. This approach handles:
  - Variable PDF layouts across different years (2006-2021)
  - Single-case PDF summaries with structured fields
  - Rail-specific legislation and offence types

  ## Usage

      alias EhsEnforcement.Scraping.Orr.OrrAiPdfParser

      # Parse raw PDF text
      {:ok, cases} = OrrAiPdfParser.parse_pdf_text(pdf_text, 2019)

      # Parse from PDF URL
      {:ok, cases} = OrrAiPdfParser.parse_pdf_url(url, 2019)

  ## Configuration

  Uses the same AI client configuration as the enrichment service:

      config :ehs_enforcement, :ai_enrichment,
        provider: :runpod,
        runpod_api_key: System.get_env("RUNPOD_API_KEY"),
        runpod_endpoint: System.get_env("RUNPOD_ENDPOINT")
  """

  alias EhsEnforcement.AI.Client

  require Logger

  defmodule ParsedCase do
    @moduledoc "Struct representing a parsed ORR prosecution case from a PDF"

    @derive Jason.Encoder
    defstruct [
      :company_name,
      :company_type,
      :location,
      :incident_date,
      :sentencing_date,
      :court_name,
      :fine_amount,
      :costs_amount,
      :total_amount,
      :plea,
      :result,
      :offence_description,
      :breaches,
      :legislation,
      :year,
      :case_title,
      :source_url
    ]
  end

  # Known PDF URLs for historical prosecutions (2006-2021)
  # These are cases that exist only as PDFs on the ORR website
  # Organized by sentencing year
  @pdf_urls %{
    2021 => [
      "/sites/default/files/2022-05/prosecution-summary-daventry-2021-07-30.pdf",
      "/sites/default/files/2021-12/prosecution-summary-market-harborough.pdf",
      "/sites/default/files/2021-06/prosecution-summary-nexus-south-gosforth.pdf",
      "/sites/default/files/2021-06/2021-04-14-godinton-prosecution-orr-v-network-rail_0.pdf",
      "/sites/default/files/2021-05/prosecution-summary-qts-group-lamberton.pdf",
      "/sites/default/files/2021-05/prosecution-summary-dollands-moor.pdf"
    ],
    2020 => [
      "/sites/default/files/2021-05/prosecution-summary-network-rail-musselburgh.pdf",
      "/sites/default/files/2021-05/prosecution-summary-network-rail-lamington-viaduct.pdf",
      "/sites/default/files/2020-10/prosecution-summary-renown.pdf",
      "/sites/default/files/2020-10/prosecution-summary-bescot-yard-db-cargo-2020-01-09.pdf"
    ],
    2019 => [
      "/sites/default/files/2025-09/prosecution-summary-lanes-group.pdf",
      "/sites/default/files/2020-10/prosecution-summary-gatwick-express-gtr-2019-07-17.pdf",
      "/sites/default/files/2020-10/prosecution-summary-tyne-yard-db-cargo-s20.pdf",
      "/sites/default/files/2020-10/prosecution-summary-tyne-yard-db-cargo.pdf"
    ],
    2018 => [
      "/sites/default/files/2022-02/prosecution-summary-east-farleigh_0.pdf",
      "/sites/default/files/2022-02/prosecution-summary-whitechapel.pdf",
      "/sites/default/files/2022-02/prosecution-summary-maerdy-bridge.pdf",
      "/sites/default/files/2022-02/prosecution-summary-south-devon-railway-trust.pdf",
      "/sites/default/files/2022-02/prosecution-summary-east-croydon.pdf",
      "/sites/default/files/2022-02/prosecution-summary-gloucester_0.pdf"
    ],
    2017 => [
      "/sites/default/files/om/west-marina-prosecution-2017-11-17.pdf",
      "/sites/default/files/om/2017-01-09-redhill-prosecution.pdf"
    ],
    2016 => [
      "/sites/default/files/om/2014-09-22-south-kentish-town.pdf",
      "/sites/default/files/om/2016-09-21-network-rail-infrastructure-at-gipsy-lane.pdf",
      "/sites/default/files/om/2016-08-01-network-rail-infrastructure-at-androssan-south-beach.pdf",
      "/sites/default/files/om/2014-02-22-network-rail-prosecution.pdf",
      "/sites/default/files/2025-11/2016-07-27-west-coast-railway-wootton-bassett-prosecution.pdf",
      "/sites/default/files/om/2016-02-05-babcock-rail-prosecution.pdf",
      "/sites/default/files/om/prosecution-of-carillion-construction-limited-2016-01-11.pdf"
    ],
    2015 => [
      "/sites/default/files/om/2015-12-21-xervon-palmers-prosecution.pdf",
      "/sites/default/files/om/berkhampstead-station-prosecution.pdf",
      "/sites/default/files/om/pouparts-bridge-website-form.pdf",
      "/sites/default/files/om/annick-water-viaduct-website-form.pdf"
    ],
    2014 => [
      "/sites/default/files/om/cricklewood-website-form.pdf",
      "/sites/default/files/om/margaretting-website-form.pdf",
      "/sites/default/files/om/river-gowy-bridge-web-form.pdf",
      "/sites/default/files/om/fcc-website-form.pdf"
    ],
    2013 => [
      "/sites/default/files/om/wrights-crossing-prosecution-2013-06-27.pdf",
      "/sites/default/files/om/winchester-prosecution-2013-05-31.pdf",
      "/sites/default/files/om/whitemoor-prosecution-2013-04-19.pdf",
      "/sites/default/files/om/stoneblower-prosecution-2013-03-22.pdf",
      "/sites/default/files/om/northern-line-prosecution-2013-02-28.pdf",
      "/sites/default/files/om/cheshunt-prosecution-2013-02-26.pdf"
    ],
    2012 => [
      "/sites/default/files/om/prosecution-allerton.pdf",
      "/sites/default/files/om/prosecution-wensleydale.pdf",
      "/sites/default/files/om/prosecution-telford-100712.pdf",
      "/sites/default/files/om/prosecution-stonegate-060712.pdf",
      "/sites/default/files/om/prosecution-wiltshire-120612.pdf",
      "/sites/default/files/om/prosecution-thamesvalley-250512.pdf",
      "/sites/default/files/om/prosecution-grayrigg-040412.pdf",
      "/sites/default/files/om/prosecution-elsenham-150312.pdf"
    ],
    2009 => [
      "/sites/default/files/om/prosecution-new-barn-040509.pdf",
      "/sites/default/files/om/prosecution-kirkdale-300609.pdf",
      "/sites/default/files/om/prosecution-nr-180909.pdf",
      "/sites/default/files/om/prosecution-lul-210909.pdf",
      "/sites/default/files/om/prosecution-swt-010609.pdf",
      "/sites/default/files/om/prosecution-lul-151109.pdf",
      "/sites/default/files/om/pros-nril_croxtonlc_190709.pdf",
      "/sites/default/files/om/pros-maintrain_140109.pdf"
    ],
    2008 => [
      "/sites/default/files/om/prosecution-acton-west-240608.pdf",
      "/sites/default/files/om/prosecution-barrow-010208.pdf",
      "/sites/default/files/om/pros-amey-290508.pdf",
      "/sites/default/files/om/pros-BalfB_090508.pdf",
      "/sites/default/files/om/pros-GTRail_090508.pdf",
      "/sites/default/files/om/pros-Elec-Track_090508.pdf"
    ],
    2007 => [
      "/sites/default/files/om/prosecution-serco-020407.pdf",
      "/sites/default/files/om/pros-ccl_050207_chadhth.pdf",
      "/sites/default/files/om/pros-nril_050207_chadhth.pdf",
      "/sites/default/files/om/pros-balfourb-190207.pdf",
      "/sites/default/files/om/pros-jarvis-4074329.pdf",
      "/sites/default/files/om/pros-nril-4074310.pdf",
      "/sites/default/files/om/pros-MWhitham_LHAcTech.pdf",
      "/sites/default/files/om/pros-MWhitham_BorderRl.pdf"
    ],
    2006 => [
      "/sites/default/files/om/pros-ews-110106.pdf",
      "/sites/default/files/om/pros-kier190306.pdf",
      "/sites/default/files/om/pros-nr-131106.pdf",
      "/sites/default/files/om/pros-scotweld-131106.pdf",
      "/sites/default/files/om/pros-amey-120906.pdf",
      "/sites/default/files/om/pros-nr-120906.pdf",
      "/sites/default/files/om/pros-grant-110506.pdf"
    ],
    # Earlier case - Potters Bar was in 2002
    2002 => [
      "/sites/default/files/om/prosecution-potters-bar-100502.pdf",
      "/sites/default/files/om/prosecution_nr_220108.pdf"
    ]
  }

  @base_url "https://www.orr.gov.uk"

  @doc """
  Get the list of known PDF URLs for a specific year.

  Returns a list of full URLs for the given year, or empty list if none known.
  """
  def pdf_urls_for_year(year) when is_integer(year) do
    @pdf_urls
    |> Map.get(year, [])
    |> Enum.map(&(@base_url <> &1))
  end

  @doc """
  Get all known PDF URLs across all years.

  Returns a map of year => [urls].
  """
  def all_pdf_urls do
    @pdf_urls
    |> Enum.map(fn {year, paths} ->
      {year, Enum.map(paths, &(@base_url <> &1))}
    end)
    |> Map.new()
  end

  @doc """
  Parse PDF text using AI to extract prosecution case details.

  Returns {:ok, [%ParsedCase{}]} or {:error, reason}
  """
  def parse_pdf_text(pdf_text, year, opts \\ []) when is_binary(pdf_text) and is_integer(year) do
    Logger.info("ORR AI: Parsing PDF text for year #{year} (#{String.length(pdf_text)} chars)")

    source_url = Keyword.get(opts, :source_url)
    client = Client.get_client()
    messages = build_extraction_messages(pdf_text, year)

    case client.complete(messages, json_mode: true, temperature: 0.1, max_tokens: 4096) do
      {:ok, %{content: content, model: model, latency_ms: latency}} ->
        Logger.debug("ORR AI: Response received in #{latency}ms using #{model}")
        parse_ai_response(content, year, source_url)

      {:error, reason} = error ->
        Logger.error("ORR AI: Failed to parse PDF: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Download and parse a PDF from URL.

  Requires `pdftotext` (poppler-utils) to be installed.
  Returns {:ok, [%ParsedCase{}]} or {:error, reason}
  """
  def parse_pdf_url(url, year) when is_binary(url) and is_integer(year) do
    Logger.info("ORR AI: Downloading PDF from #{url}")

    with {:ok, pdf_path} <- download_pdf(url, year),
         {:ok, pdf_text} <- extract_pdf_text(pdf_path) do
      # Clean up temp file
      _ = File.rm(pdf_path)
      parse_pdf_text(pdf_text, year, source_url: url)
    end
  end

  @doc """
  Scrape all PDF prosecutions for a given year.

  Downloads each PDF, extracts text, and uses AI to parse case details.
  Returns {:ok, [%ParsedCase{}]} or {:error, reason}
  """
  def scrape_pdf_year(year) when is_integer(year) do
    urls = pdf_urls_for_year(year)

    if Enum.empty?(urls) do
      Logger.info("ORR AI: No PDF URLs known for year #{year}")
      {:ok, []}
    else
      Logger.info("ORR AI: Scraping #{length(urls)} PDFs for year #{year}")

      results =
        urls
        |> Enum.map(fn url ->
          case parse_pdf_url(url, year) do
            {:ok, cases} ->
              cases

            {:error, reason} ->
              Logger.warning("ORR AI: Failed to parse #{url}: #{inspect(reason)}")
              []
          end
        end)
        |> List.flatten()

      Logger.info("ORR AI: Extracted #{length(results)} cases from #{length(urls)} PDFs")
      {:ok, results}
    end
  end

  @doc """
  Scrape all PDF prosecutions across all known years.

  Returns {:ok, [%ParsedCase{}], errors: [{year, reason}]} or {:error, reason}
  """
  def scrape_all_pdfs do
    years = Map.keys(@pdf_urls) |> Enum.sort(:desc)
    Logger.info("ORR AI: Scraping PDFs for years: #{inspect(years)}")

    # scrape_pdf_year always returns {:ok, cases}, so we can simplify
    all_cases =
      Enum.flat_map(years, fn year ->
        {:ok, year_cases} = scrape_pdf_year(year)
        year_cases
      end)

    Logger.info("ORR AI: Successfully scraped #{length(all_cases)} total prosecutions from PDFs")

    {:ok, all_cases}
  end

  # Private functions

  defp download_pdf(url, year) do
    temp_path = "/tmp/orr_prosecutions_#{year}_#{:erlang.unique_integer([:positive])}.pdf"

    case Req.get(url, into: File.stream!(temp_path), receive_timeout: 60_000) do
      {:ok, %{status: 200}} ->
        {:ok, temp_path}

      {:ok, %{status: status}} ->
        _ = File.rm(temp_path)
        {:error, {:http_error, status}}

      {:error, reason} ->
        _ = File.rm(temp_path)
        {:error, {:download_error, reason}}
    end
  end

  defp extract_pdf_text(pdf_path) do
    case System.cmd("pdftotext", ["-layout", pdf_path, "-"], stderr_to_stdout: true) do
      {text, 0} ->
        {:ok, text}

      {error, _} ->
        {:error, {:pdftotext_error, error}}
    end
  end

  defp build_extraction_messages(pdf_text, year) do
    [
      %{
        role: "system",
        content: extraction_system_prompt()
      },
      %{
        role: "user",
        content: """
        Extract the prosecution case details from this Office of Rail and Road (ORR) PDF document for year #{year}.

        ## PDF Content

        #{pdf_text}

        ---

        Extract ALL defendants/companies mentioned with their specific penalties. Return the data in the specified JSON format.
        """
      }
    ]
  end

  defp extraction_system_prompt do
    """
    You are an expert at extracting structured data from UK rail safety enforcement prosecution documents.

    Your task is to parse Office of Rail and Road (ORR) prosecution summary PDFs and extract case details.

    CRITICAL: You MUST respond with ONLY valid JSON. No markdown, no explanations, no text before or after the JSON.

    ## Required Output Format

    Respond with EXACTLY this JSON structure (and nothing else):

    {"cases":[{"company_name":"Full company name","company_type":"rail_operator","location":"Location","incident_date":"2012-04-15","sentencing_date":"2012-06-20","court_name":"Bristol Crown Court","fine_amount":4000000,"costs_amount":215000,"total_amount":4215000,"plea":"Guilty","result":"Convicted under Section 3(1) HSWA","offence_description":"Failed to ensure safety","breaches":["Section 3(1) HSWA 1974"],"legislation":["Health and Safety at Work etc Act 1974"],"case_title":"Network Rail (Grayrigg)"}],"extraction_notes":""}

    ## Field Specifications

    - company_name: STRING - Full legal name of the defendant company
    - company_type: STRING - One of: "rail_operator", "infrastructure_manager", "contractor", "other"
    - location: STRING or null - Location of incident
    - incident_date: STRING "YYYY-MM-DD" or null - When the incident occurred
    - sentencing_date: STRING "YYYY-MM-DD" or null - When sentence was passed
    - court_name: STRING or null - Name of the court
    - fine_amount: NUMBER or null - Fine in GBP (convert "£4 million" to 4000000)
    - costs_amount: NUMBER or null - Costs in GBP
    - total_amount: NUMBER or null - Total amount ordered
    - plea: STRING or null - "Guilty" or "Not Guilty"
    - result: STRING - Sentence/outcome description
    - offence_description: STRING - Brief description of the offence
    - breaches: ARRAY of STRINGS - Specific breaches e.g. ["Section 3(1) HSWA 1974"]
    - legislation: ARRAY of STRINGS - Full legislation names e.g. ["Health and Safety at Work etc Act 1974"]
    - case_title: STRING - Brief case title

    ## Company Type Classification

    - rail_operator: Train operating companies (Great Western Railway, Virgin Trains, heritage railways)
    - infrastructure_manager: Network Rail, HS1, Crossrail, London Underground
    - contractor: Balfour Beatty, Amey, Carillion, maintenance companies
    - other: Any other type

    ## Financial Amount Conversion

    - "£4,000,000" → 4000000
    - "£4 million" → 4000000
    - "£1.5 million" → 1500000
    - "£215,000" → 215000
    - "£78,444.19" → 78444.19

    ## Common ORR Legislation

    - Health and Safety at Work etc Act 1974 (HSWA) - Sections 2, 3, 33
    - Railways and Other Guided Transport Systems (Safety) Regulations 2006 (ROGS)
    - Work at Height Regulations 2005
    - RIDDOR (Reporting of Injuries, Diseases and Dangerous Occurrences Regulations)

    ## Rules

    1. Extract ALL defendants - if multiple companies prosecuted, create separate case entries
    2. Most PDFs have ONE case, but some have multiple defendants
    3. If no prosecution data found, return: {"cases":[],"extraction_notes":"No prosecution data found"}
    4. Do NOT include ORR officials or investigators as defendants
    5. ONLY output valid JSON - no markdown code blocks, no explanations
    """
  end

  defp parse_ai_response(content, year, source_url) do
    case Jason.decode(content) do
      {:ok, %{"cases" => cases}} when is_list(cases) ->
        parsed_cases =
          cases
          |> Enum.map(fn case_data -> build_parsed_case(case_data, year, source_url) end)
          |> Enum.reject(&is_nil/1)

        Logger.info("ORR AI: Extracted #{length(parsed_cases)} cases from PDF")
        {:ok, parsed_cases}

      {:ok, %{"cases" => nil}} ->
        Logger.warning("ORR AI: No cases found in PDF")
        {:ok, []}

      {:ok, other} ->
        Logger.error("ORR AI: Unexpected response structure: #{inspect(other)}")
        {:error, {:invalid_response_structure, other}}

      {:error, reason} ->
        Logger.error("ORR AI: Failed to parse JSON response: #{inspect(reason)}")
        Logger.debug("ORR AI: Raw content: #{content}")
        {:error, {:json_parse_error, reason}}
    end
  end

  defp build_parsed_case(case_data, year, source_url) when is_map(case_data) do
    company_name = case_data["company_name"]

    if is_nil(company_name) or company_name == "" do
      nil
    else
      %ParsedCase{
        company_name: company_name,
        company_type: parse_company_type(case_data["company_type"]),
        location: case_data["location"],
        incident_date: parse_date(case_data["incident_date"]),
        sentencing_date: parse_date(case_data["sentencing_date"]),
        court_name: case_data["court_name"],
        fine_amount: parse_decimal(case_data["fine_amount"]),
        costs_amount: parse_decimal(case_data["costs_amount"]),
        total_amount: parse_decimal(case_data["total_amount"]),
        plea: case_data["plea"],
        result: case_data["result"],
        offence_description: case_data["offence_description"],
        breaches: parse_list(case_data["breaches"]),
        legislation: parse_list(case_data["legislation"]),
        year: year,
        case_title: case_data["case_title"] || generate_case_title(company_name, year),
        source_url: source_url
      }
    end
  end

  defp build_parsed_case(_, _, _), do: nil

  defp parse_company_type("rail_operator"), do: :rail_operator
  defp parse_company_type("infrastructure_manager"), do: :infrastructure_manager
  defp parse_company_type("contractor"), do: :contractor
  defp parse_company_type(_), do: :other

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        date

      {:error, _} ->
        parse_uk_date(date_string)
    end
  end

  defp parse_date(_), do: nil

  defp parse_uk_date(date_string) do
    case Regex.run(
           ~r/(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/i,
           date_string
         ) do
      [_, day, month, year] ->
        month_num = month_to_number(month)

        case Date.new(String.to_integer(year), month_num, String.to_integer(day)) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp month_to_number(month) do
    month
    |> String.downcase()
    |> case do
      "january" -> 1
      "february" -> 2
      "march" -> 3
      "april" -> 4
      "may" -> 5
      "june" -> 6
      "july" -> 7
      "august" -> 8
      "september" -> 9
      "october" -> 10
      "november" -> 11
      "december" -> 12
      _ -> 1
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp parse_decimal(value) when is_binary(value) do
    value
    |> String.replace(",", "")
    |> String.replace("£", "")
    |> String.trim()
    |> case do
      "" ->
        nil

      str ->
        case Decimal.parse(str) do
          {decimal, _} -> decimal
          :error -> nil
        end
    end
  end

  defp parse_decimal(_), do: nil

  defp parse_list(nil), do: []
  defp parse_list(list) when is_list(list), do: list
  defp parse_list(str) when is_binary(str), do: [str]
  defp parse_list(_), do: []

  defp generate_case_title(company_name, year) do
    "#{company_name} (#{year})"
  end
end
