defmodule EhsEnforcement.Scraping.Caa.CaaAiPdfParser do
  @moduledoc """
  AI-powered parser for CAA prosecution PDF documents.

  Uses LLM to extract structured enforcement case data from unstructured
  PDF text. This approach handles the legacy (pre-2023) spatial table format
  that cannot be reliably parsed with regex.

  ## Usage

      alias EhsEnforcement.Scraping.Caa.CaaAiPdfParser

      # Parse raw PDF text
      {:ok, prosecutions} = CaaAiPdfParser.parse_pdf_text(pdf_text, "2021-2022")

  ## Configuration

  Uses the AI client configuration from `config/runtime.exs`:

      config :ehs_enforcement, :ai_enrichment,
        provider: :runpod,
        runpod_api_key: System.get_env("RUNPOD_API_KEY"),
        runpod_endpoint: System.get_env("RUNPOD_ENDPOINT")

  ## PDF Format Handled

  Legacy CAA prosecution PDFs (2017-2022) use a spatial table layout:
  - Column headers: DEFENDANT, BRIEF DESCRIPTION, DATE, COURT, SENTENCE
  - Content spans multiple rows within table cells
  - Court names split across lines (location + type)
  - Sentences may include fines, imprisonment, community orders
  """

  alias EhsEnforcement.AI.Client

  require Logger

  defmodule ParsedProsecution do
    @moduledoc """
    Struct representing a parsed CAA prosecution from AI extraction.

    Contains all fields that can be extracted from CAA prosecution PDFs,
    with support for various sentence types (fines, imprisonment, community orders).
    """

    @derive Jason.Encoder
    defstruct [
      :defendant_name,
      :defendant_type,
      :hearing_date,
      :court_name,
      :fine_amount,
      :imprisonment_months,
      :suspended_months,
      :community_order_months,
      :unpaid_work_hours,
      :offence_description,
      :offence_outcome,
      :legislation,
      :fiscal_year,
      :case_title
    ]

    @type t :: %__MODULE__{
            defendant_name: String.t() | nil,
            defendant_type: :individual | :company | :unknown,
            hearing_date: Date.t() | nil,
            court_name: String.t() | nil,
            fine_amount: Decimal.t() | nil,
            imprisonment_months: integer() | nil,
            suspended_months: integer() | nil,
            community_order_months: integer() | nil,
            unpaid_work_hours: integer() | nil,
            offence_description: String.t() | nil,
            offence_outcome: String.t() | nil,
            legislation: [String.t()],
            fiscal_year: String.t() | nil,
            case_title: String.t() | nil
          }
  end

  @doc """
  Parse PDF text using AI to extract prosecution case details.

  ## Parameters

  - `pdf_text` - Raw text extracted from PDF via pdftotext
  - `fiscal_year` - The fiscal year of the PDF (e.g., "2021-2022")

  ## Returns

  - `{:ok, [%ParsedProsecution{}]}` on success
  - `{:error, reason}` on failure
  """
  @spec parse_pdf_text(String.t(), String.t()) ::
          {:ok, [ParsedProsecution.t()]} | {:error, term()}
  def parse_pdf_text(pdf_text, fiscal_year)
      when is_binary(pdf_text) and is_binary(fiscal_year) do
    Logger.info(
      "CAA AI Parser: Parsing PDF text for #{fiscal_year} (#{String.length(pdf_text)} chars)"
    )

    client = Client.get_client()
    messages = build_extraction_messages(pdf_text, fiscal_year)

    case client.complete(messages, json_mode: true, temperature: 0.1, max_tokens: 8192) do
      {:ok, %{content: content, model: model, latency_ms: latency}} ->
        Logger.debug("CAA AI Parser: Response received in #{latency}ms using #{model}")
        parse_ai_response(content, fiscal_year)

      {:error, reason} = error ->
        Logger.error("CAA AI Parser: Failed to parse PDF: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Check if AI parsing is available (client is configured and healthy).
  """
  @spec available?() :: boolean()
  def available? do
    client = Client.get_client()

    case client.health_check() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Build the messages for the AI extraction request
  defp build_extraction_messages(pdf_text, fiscal_year) do
    [
      %{
        role: "system",
        content: extraction_system_prompt()
      },
      %{
        role: "user",
        content: """
        Extract all prosecution cases from this Civil Aviation Authority (CAA) PDF document for fiscal year #{fiscal_year}.

        ## PDF Content

        #{pdf_text}

        ---

        Extract ALL defendants/offenders mentioned with their specific penalties.
        Return the data in the specified JSON format.
        """
      }
    ]
  end

  defp extraction_system_prompt do
    """
    You are an expert at extracting structured data from UK Civil Aviation Authority (CAA) prosecution documents.

    Your task is to parse CAA prosecution reports and extract case details for each defendant.

    ## Required Output Format (JSON)

    You MUST respond with valid JSON in this exact structure:

    {
      "prosecutions": [
        {
          "defendant_name": "Full name of individual or company",
          "defendant_type": "individual" or "company",
          "hearing_date": "YYYY-MM-DD format or null if not found",
          "court_name": "Full court name, e.g. 'Guildford Magistrates' Court'",
          "fine_amount": <fine in GBP as number or null>,
          "imprisonment_months": <months of imprisonment or null>,
          "suspended_months": <suspension period in months or null>,
          "community_order_months": <community order duration in months or null>,
          "unpaid_work_hours": <hours of unpaid work or null>,
          "offence_description": "Brief description of what the offender did wrong",
          "offence_outcome": "The full sentence/outcome description",
          "legislation": ["Array of legislation breached"],
          "case_title": "A brief descriptive title for the case"
        }
      ],
      "extraction_notes": "Any relevant notes about the extraction"
    }

    ## Extraction Rules

    1. **Multiple Defendants**: Create a SEPARATE case entry for EACH defendant
    2. **Defendant Types**:
       - "individual" for natural persons (e.g., "DAREN SALMON", "David Henderson")
       - "company" for legal entities (e.g., "BLUE AIR AVIATION SA", companies with Ltd/PLC/SA)
    3. **Dates**: Extract the court/hearing/sentencing date, NOT the offence date. Format as YYYY-MM-DD
    4. **Court Names**: Include both location and type, e.g., "Guildford Magistrates' Court", "Cardiff Crown Court"
    5. **Sentence Parsing**:
       - Regular fines go in `fine_amount` (numbers only, no £ symbol)
       - Prison sentences: extract months into `imprisonment_months`
       - Suspended sentences: extract suspension period into `suspended_months`
       - Community orders: extract duration into `community_order_months`
       - Unpaid work: extract hours into `unpaid_work_hours`
    6. **Null Values**: Use null (not 0 or empty string) for values not mentioned
    7. **Name Formatting**: Preserve names as they appear (may be ALL CAPS or mixed case)

    ## Common Aviation Offences

    - Low flying over congested areas
    - Flying without valid licence/rating
    - Flying in controlled airspace without clearance
    - Organising flying display without CAA permission
    - Forging aviation documents/certificates/training records
    - Negligently endangering aircraft
    - Failing to maintain radio communication
    - COVID-19 passenger regulation breaches (PLF, pre-departure tests)
    - Fraud by false representation (pilot qualifications)

    ## Common Legislation

    - Civil Aviation Act 1982
    - Air Navigation Order 2016
    - EU Regulation 261/2004 (UK261)
    - The Health Protection (Coronavirus, International Travel) (England) Regulations

    ## Important

    - Return an EMPTY prosecutions array [] if no prosecutions are described
    - Do NOT include CAA officials, investigators, or quoted witnesses as defendants
    - Only extract actual defendants who received penalties or court orders
    - The document may span multiple pages with repeated headers - ignore duplicates
    """
  end

  # Parse the AI response JSON into ParsedProsecution structs
  defp parse_ai_response(content, fiscal_year) do
    case Jason.decode(content) do
      {:ok, %{"prosecutions" => prosecutions}} when is_list(prosecutions) ->
        parsed =
          prosecutions
          |> Enum.map(fn data -> build_parsed_prosecution(data, fiscal_year) end)
          |> Enum.reject(&is_nil/1)

        Logger.info("CAA AI Parser: Extracted #{length(parsed)} prosecutions from PDF")
        {:ok, parsed}

      {:ok, %{"prosecutions" => nil}} ->
        Logger.warning("CAA AI Parser: No prosecutions found in PDF")
        {:ok, []}

      # Handle alternative response formats the LLM might use
      {:ok, %{"cases" => cases}} when is_list(cases) ->
        Logger.warning("CAA AI Parser: Received 'cases' format instead of 'prosecutions'")

        parsed =
          cases
          |> Enum.map(fn data -> build_parsed_prosecution(data, fiscal_year) end)
          |> Enum.reject(&is_nil/1)

        {:ok, parsed}

      # Handle "defendants" format which uses different field names
      {:ok, %{"defendants" => defendants}} when is_list(defendants) ->
        Logger.warning("CAA AI Parser: Received 'defendants' format instead of 'prosecutions'")

        parsed =
          defendants
          |> Enum.map(fn data -> build_parsed_prosecution_from_defendants(data, fiscal_year) end)
          |> Enum.reject(&is_nil/1)

        Logger.info(
          "CAA AI Parser: Extracted #{length(parsed)} prosecutions from defendants format"
        )

        {:ok, parsed}

      {:ok, other} ->
        Logger.error("CAA AI Parser: Unexpected response structure: #{inspect(other)}")
        {:error, {:invalid_response_structure, other}}

      {:error, reason} ->
        Logger.error("CAA AI Parser: Failed to parse JSON response: #{inspect(reason)}")
        Logger.debug("CAA AI Parser: Raw content: #{content}")
        {:error, {:json_parse_error, reason}}
    end
  end

  # Build a ParsedProsecution struct from the AI response data
  defp build_parsed_prosecution(data, fiscal_year) when is_map(data) do
    defendant_name = data["defendant_name"]

    if is_nil(defendant_name) or defendant_name == "" do
      nil
    else
      %ParsedProsecution{
        defendant_name: defendant_name,
        defendant_type: parse_defendant_type(data["defendant_type"]),
        hearing_date: parse_date(data["hearing_date"]),
        court_name: data["court_name"],
        fine_amount: parse_decimal(data["fine_amount"]),
        imprisonment_months: parse_integer(data["imprisonment_months"]),
        suspended_months: parse_integer(data["suspended_months"]),
        community_order_months: parse_integer(data["community_order_months"]),
        unpaid_work_hours: parse_integer(data["unpaid_work_hours"]),
        offence_description: data["offence_description"],
        offence_outcome: data["offence_outcome"],
        legislation: parse_legislation_list(data["legislation"]),
        fiscal_year: fiscal_year,
        case_title: data["case_title"] || generate_case_title(defendant_name, fiscal_year)
      }
    end
  end

  defp build_parsed_prosecution(_, _), do: nil

  # Build a ParsedProsecution from the alternative "defendants" format
  # This format uses different field names: name, offences, penalty, court, date
  defp build_parsed_prosecution_from_defendants(data, fiscal_year) when is_map(data) do
    # The defendants format uses "name" instead of "defendant_name"
    defendant_name = data["name"] || data["defendant_name"]

    if is_nil(defendant_name) or defendant_name == "" do
      nil
    else
      # Parse penalty string into components
      penalty = data["penalty"] || data["sentence"] || ""

      {fine, imprisonment, suspended, community_order, unpaid_work} =
        parse_penalty_string(penalty)

      # Parse offences - may be a list or string
      offence_desc = parse_offences_field(data["offences"] || data["offence_description"])

      %ParsedProsecution{
        defendant_name: defendant_name,
        defendant_type: infer_defendant_type(defendant_name, data["defendant_type"]),
        hearing_date: parse_date(data["date"] || data["hearing_date"] || data["court_date"]),
        court_name: data["court"] || data["court_name"],
        fine_amount: fine,
        imprisonment_months: imprisonment,
        suspended_months: suspended,
        community_order_months: community_order,
        unpaid_work_hours: unpaid_work,
        offence_description: offence_desc,
        offence_outcome: penalty,
        legislation: parse_legislation_list(data["legislation"]),
        fiscal_year: fiscal_year,
        case_title: data["case_title"] || generate_case_title(defendant_name, fiscal_year)
      }
    end
  end

  defp build_parsed_prosecution_from_defendants(_, _), do: nil

  # Parse a penalty string like "£5,000 fine" or "12 months imprisonment, suspended for 24 months"
  defp parse_penalty_string(nil), do: {nil, nil, nil, nil, nil}
  defp parse_penalty_string(""), do: {nil, nil, nil, nil, nil}

  defp parse_penalty_string(penalty) when is_binary(penalty) do
    fine = extract_fine_from_penalty(penalty)
    imprisonment = extract_imprisonment_months(penalty)
    suspended = extract_suspended_months(penalty)
    community_order = extract_community_order_months(penalty)
    unpaid_work = extract_unpaid_work_hours(penalty)

    {fine, imprisonment, suspended, community_order, unpaid_work}
  end

  defp parse_penalty_string(_), do: {nil, nil, nil, nil, nil}

  # Extract fine amount from penalty string
  defp extract_fine_from_penalty(penalty) do
    case Regex.run(~r/£([\d,]+)/i, penalty) do
      [_, amount] ->
        amount
        |> String.replace(",", "")
        |> Decimal.parse()
        |> case do
          {decimal, _} -> decimal
          :error -> nil
        end

      nil ->
        nil
    end
  end

  # Extract imprisonment months from penalty
  defp extract_imprisonment_months(penalty) do
    cond do
      result = Regex.run(~r/(\d+)\s*months?\s*(?:imprisonment|prison|custody)/i, penalty) ->
        [_, months] = result
        String.to_integer(months)

      result = Regex.run(~r/(\d+)\s*years?\s*(?:imprisonment|prison|custody)/i, penalty) ->
        [_, years] = result
        String.to_integer(years) * 12

      true ->
        nil
    end
  end

  # Extract suspended sentence period
  defp extract_suspended_months(penalty) do
    cond do
      result = Regex.run(~r/suspended\s*(?:for)?\s*(\d+)\s*months?/i, penalty) ->
        [_, months] = result
        String.to_integer(months)

      result = Regex.run(~r/suspended\s*(?:for)?\s*(\d+)\s*years?/i, penalty) ->
        [_, years] = result
        String.to_integer(years) * 12

      true ->
        nil
    end
  end

  # Extract community order months
  defp extract_community_order_months(penalty) do
    cond do
      result = Regex.run(~r/community\s*order\s*(?:for)?\s*(\d+)\s*months?/i, penalty) ->
        [_, months] = result
        String.to_integer(months)

      result = Regex.run(~r/(\d+)\s*months?\s*community\s*order/i, penalty) ->
        [_, months] = result
        String.to_integer(months)

      true ->
        nil
    end
  end

  # Extract unpaid work hours
  defp extract_unpaid_work_hours(penalty) do
    case Regex.run(~r/(\d+)\s*hours?\s*(?:unpaid\s*work|community\s*service)/i, penalty) do
      [_, hours] -> String.to_integer(hours)
      nil -> nil
    end
  end

  # Parse offences field which may be a list or string
  defp parse_offences_field(nil), do: nil
  defp parse_offences_field(offences) when is_binary(offences), do: offences

  defp parse_offences_field(offences) when is_list(offences) do
    offences
    |> Enum.map(fn
      item when is_binary(item) -> item
      item when is_map(item) -> item["description"] || item["offence"] || inspect(item)
      item -> inspect(item)
    end)
    |> Enum.join("; ")
  end

  defp parse_offences_field(_), do: nil

  # Infer defendant type from name if not explicitly provided
  defp infer_defendant_type(name, explicit_type) do
    case explicit_type do
      "company" -> :company
      "individual" -> :individual
      _ -> infer_type_from_name(name)
    end
  end

  defp infer_type_from_name(name) when is_binary(name) do
    company_indicators = ~r/(Ltd|Limited|PLC|SA|Inc|Corp|GmbH|BV|SRL|LLC|LP|LLP)\b/i

    if Regex.match?(company_indicators, name) do
      :company
    else
      :individual
    end
  end

  defp infer_type_from_name(_), do: :unknown

  # Type conversion helpers

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
        # Try parsing UK format DD/MM/YYYY
        parse_uk_date(date_string)
    end
  end

  defp parse_date(_), do: nil

  defp parse_uk_date(date_string) do
    case Regex.run(~r/(\d{1,2})\/(\d{1,2})\/(\d{4})/, date_string) do
      [_, day, month, year] ->
        case Date.new(
               String.to_integer(year),
               String.to_integer(month),
               String.to_integer(day)
             ) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        # Try parsing text month format
        parse_text_month_date(date_string)
    end
  end

  defp parse_text_month_date(date_string) do
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
    case String.downcase(month) do
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

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_float(value) do
    round(value)
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp parse_legislation_list(nil), do: []
  defp parse_legislation_list(list) when is_list(list), do: list
  defp parse_legislation_list(str) when is_binary(str), do: [str]
  defp parse_legislation_list(_), do: []

  defp generate_case_title(defendant_name, fiscal_year) do
    "#{defendant_name} (#{fiscal_year})"
  end
end
