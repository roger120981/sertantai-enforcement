defmodule EhsEnforcement.Scraping.Mca.McaAiPdfParser do
  @moduledoc """
  AI-powered parser for MCA prosecution PDF documents.

  Uses LLM to extract structured enforcement case data from unstructured
  narrative PDF text. This approach handles:
  - Variable PDF layouts across different years (2010-2019)
  - Narrative prose format vs structured tables
  - Multi-defendant cases with correct penalty attribution
  - Maritime-specific legislation and offence types

  ## Usage

      alias EhsEnforcement.Scraping.Mca.McaAiPdfParser

      # Parse raw PDF text
      {:ok, cases} = McaAiPdfParser.parse_pdf_text(pdf_text, 2019)

      # Parse from PDF URL
      {:ok, cases} = McaAiPdfParser.parse_pdf_url(url, 2019)

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
    @moduledoc "Struct representing a parsed MCA prosecution case from a PDF"

    @derive Jason.Encoder
    defstruct [
      :defendant_name,
      :defendant_type,
      :defendant_location,
      :defendant_age,
      :vessel_name,
      :hearing_date,
      :court_name,
      :fine_amount,
      :costs_amount,
      :surcharge_amount,
      :total_amount,
      :custodial_sentence,
      :community_service_hours,
      :offence_description,
      :offence_result,
      :legislation,
      :year,
      :case_title
    ]
  end

  @doc """
  Parse PDF text using AI to extract prosecution case details.

  Returns {:ok, [%ParsedCase{}]} or {:error, reason}
  """
  def parse_pdf_text(pdf_text, year) when is_binary(pdf_text) and is_integer(year) do
    Logger.info("MCA AI: Parsing PDF text for year #{year} (#{String.length(pdf_text)} chars)")

    client = Client.get_client()
    messages = build_extraction_messages(pdf_text, year)

    case client.complete(messages, json_mode: true, temperature: 0.1, max_tokens: 8192) do
      {:ok, %{content: content, model: model, latency_ms: latency}} ->
        Logger.debug("MCA AI: Response received in #{latency}ms using #{model}")
        parse_ai_response(content, year)

      {:error, reason} = error ->
        Logger.error("MCA AI: Failed to parse PDF: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Download and parse a PDF from URL.

  Requires `pdftotext` (poppler-utils) to be installed.
  Returns {:ok, [%ParsedCase{}]} or {:error, reason}
  """
  def parse_pdf_url(url, year) when is_binary(url) and is_integer(year) do
    Logger.info("MCA AI: Downloading PDF from #{url}")

    with {:ok, pdf_path} <- download_pdf(url, year),
         {:ok, pdf_text} <- extract_pdf_text(pdf_path) do
      # Clean up temp file
      _ = File.rm(pdf_path)
      parse_pdf_text(pdf_text, year)
    end
  end

  # Private functions

  defp download_pdf(url, year) do
    temp_path = "/tmp/mca_prosecutions_#{year}_#{:erlang.unique_integer([:positive])}.pdf"

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
        Extract all prosecution cases from this Maritime and Coastguard Agency (MCA) PDF document for year #{year}.

        ## PDF Content

        #{pdf_text}

        ---

        Extract ALL defendants/offenders mentioned with their specific penalties. Return the data in the specified JSON format.
        """
      }
    ]
  end

  defp extraction_system_prompt do
    """
    You are an expert at extracting structured data from UK maritime enforcement prosecution documents.

    Your task is to parse Maritime and Coastguard Agency (MCA) prosecution reports and extract case details for each defendant.

    ## Required Output Format (JSON)

    You MUST respond with valid JSON in this exact structure:

    {
      "cases": [
        {
          "defendant_name": "Full name of individual or company",
          "defendant_type": "individual" or "company",
          "defendant_location": "Location/address if mentioned, or null",
          "defendant_age": <age as number or null>,
          "vessel_name": "Name of the vessel involved, or null",
          "hearing_date": "YYYY-MM-DD format or null if not found",
          "court_name": "Name of the court, e.g. 'Hull Magistrates Court'",
          "fine_amount": <fine in GBP as number or null>,
          "costs_amount": <prosecution costs in GBP as number or null>,
          "surcharge_amount": <victim surcharge in GBP as number or null>,
          "total_amount": <total ordered to pay if stated, or null>,
          "custodial_sentence": "Description of any prison/suspended sentence, or null",
          "community_service_hours": <hours of unpaid work as number or null>,
          "offence_description": "Brief description of what the offender did wrong",
          "offence_result": "The full sentence/outcome",
          "legislation": ["Array of legislation breached, e.g. 'Merchant Shipping Act 1995', 'Merchant Shipping (ISM Code) Regulations 2014'"],
          "case_title": "A brief descriptive title for the case"
        }
      ],
      "extraction_notes": "Any relevant notes about the extraction"
    }

    ## Extraction Rules

    1. **Multiple Defendants**: Create a SEPARATE case entry for EACH defendant (individual or company)
    2. **Company and Master**: A shipping company and its master/captain are SEPARATE defendants
    3. **Vessel Names**: Extract vessel names like "MV Example", "FV Fishing Boat", "Tecoil Polaris"
    4. **Courts**: Common courts include Magistrates Courts and Crown Courts in port cities
    5. **Dates**: Extract the court/hearing date, NOT the offence date. Format as YYYY-MM-DD
    6. **Fines vs Costs**:
       - Regular fines go in `fine_amount`
       - Prosecution costs go in `costs_amount`
       - Victim surcharge goes in `surcharge_amount`
    7. **Custodial Sentences**: Include details like "18 weeks suspended for 12 months"
    8. **Community Service**: Extract hours of unpaid work/community service
    9. **Null Values**: Use null (not 0) for amounts/values not mentioned

    ## Common Maritime Legislation

    - Merchant Shipping Act 1995
    - Merchant Shipping (ISM Code) Regulations 2014
    - Merchant Shipping (Distress Signals and Prevention of Collisions) Regulations 1996
    - Fishing Vessels (Codes of Practice) Regulations 2017
    - Merchant Shipping and Fishing Vessels (Health and Safety at Work) Regulations 1997
    - MS (Safe Manning, Hours of Work and Watchkeeping) Regulations

    ## Common Offence Types

    - Failure to maintain proper lookout
    - Failure to proceed at safe speed
    - Breaching International Safety Management (ISM) Code
    - Operating without valid safety certificates
    - Crew competency/manning violations
    - Failure to report incidents
    - Obstruction of MCA inspectors

    ## Important

    - Return an EMPTY cases array [] if no prosecutions are described
    - Do NOT include MCA officers, investigators, or quoted officials as defendants
    - Only extract actual defendants who received penalties or court orders
    - If a company pays costs and its employee/master pays fines, these are SEPARATE entries
    """
  end

  defp parse_ai_response(content, year) do
    case Jason.decode(content) do
      {:ok, %{"cases" => cases}} when is_list(cases) ->
        parsed_cases =
          cases
          |> Enum.map(fn case_data -> build_parsed_case(case_data, year) end)
          |> Enum.reject(&is_nil/1)

        Logger.info("MCA AI: Extracted #{length(parsed_cases)} cases from PDF")
        {:ok, parsed_cases}

      {:ok, %{"cases" => nil}} ->
        Logger.warning("MCA AI: No cases found in PDF")
        {:ok, []}

      # Handle alternative response format (defendants instead of cases)
      {:ok, %{"defendants" => defendants}} when is_list(defendants) ->
        Logger.warning("MCA AI: Received 'defendants' format instead of 'cases', converting...")

        parsed_cases =
          defendants
          |> Enum.map(fn defendant_data ->
            build_parsed_case_from_defendant(defendant_data, year)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.defendant_name)

        Logger.info(
          "MCA AI: Extracted #{length(parsed_cases)} cases from PDF (converted from defendants)"
        )

        {:ok, parsed_cases}

      {:ok, other} ->
        Logger.error("MCA AI: Unexpected response structure: #{inspect(other)}")
        {:error, {:invalid_response_structure, other}}

      {:error, reason} ->
        Logger.error("MCA AI: Failed to parse JSON response: #{inspect(reason)}")
        Logger.debug("MCA AI: Raw content: #{content}")
        {:error, {:json_parse_error, reason}}
    end
  end

  # Handle simplified defendant format from LLM
  defp build_parsed_case_from_defendant(defendant_data, year) when is_map(defendant_data) do
    name = defendant_data["name"]

    if is_nil(name) or name == "" do
      nil
    else
      # Parse penalty string to extract fine and costs
      penalty_str = defendant_data["penalty"] || ""
      {fine, costs} = parse_penalty_string(penalty_str)

      %ParsedCase{
        defendant_name: name,
        defendant_type: :unknown,
        defendant_location: nil,
        defendant_age: nil,
        vessel_name: nil,
        hearing_date: nil,
        court_name: nil,
        fine_amount: fine,
        costs_amount: costs,
        surcharge_amount: nil,
        total_amount: nil,
        custodial_sentence: nil,
        community_service_hours: nil,
        offence_description: penalty_str,
        offence_result: penalty_str,
        legislation: [],
        year: year,
        case_title: "#{name} (#{year})"
      }
    end
  end

  defp build_parsed_case_from_defendant(_, _), do: nil

  defp parse_penalty_string(penalty_str) do
    # Try to extract fine amount
    fine =
      case Regex.run(~r/fined?\s*£?([\d,]+)/i, penalty_str) do
        [_, amount] -> parse_decimal(amount)
        nil -> nil
      end

    # Try to extract costs
    costs =
      case Regex.run(~r/costs?\s*(?:of\s*)?£?([\d,]+)/i, penalty_str) do
        [_, amount] -> parse_decimal(amount)
        nil -> nil
      end

    {fine, costs}
  end

  defp build_parsed_case(case_data, year) when is_map(case_data) do
    defendant_name = case_data["defendant_name"]

    if is_nil(defendant_name) or defendant_name == "" do
      nil
    else
      %ParsedCase{
        defendant_name: defendant_name,
        defendant_type: parse_defendant_type(case_data["defendant_type"]),
        defendant_location: case_data["defendant_location"],
        defendant_age: case_data["defendant_age"],
        vessel_name: case_data["vessel_name"],
        hearing_date: parse_date(case_data["hearing_date"]),
        court_name: case_data["court_name"],
        fine_amount: parse_decimal(case_data["fine_amount"]),
        costs_amount: parse_decimal(case_data["costs_amount"]),
        surcharge_amount: parse_decimal(case_data["surcharge_amount"]),
        total_amount: parse_decimal(case_data["total_amount"]),
        custodial_sentence: case_data["custodial_sentence"],
        community_service_hours: case_data["community_service_hours"],
        offence_description: case_data["offence_description"],
        offence_result: case_data["offence_result"],
        legislation: parse_legislation_list(case_data["legislation"]),
        year: year,
        case_title: case_data["case_title"] || generate_case_title(defendant_name, year)
      }
    end
  end

  defp build_parsed_case(_, _), do: nil

  defp parse_defendant_type("company"), do: :company
  defp parse_defendant_type("individual"), do: :individual
  defp parse_defendant_type(_), do: :unknown

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

  defp parse_legislation_list(nil), do: []
  defp parse_legislation_list(list) when is_list(list), do: list
  defp parse_legislation_list(str) when is_binary(str), do: [str]
  defp parse_legislation_list(_), do: []

  defp generate_case_title(defendant_name, year) do
    "#{defendant_name} (#{year})"
  end
end
