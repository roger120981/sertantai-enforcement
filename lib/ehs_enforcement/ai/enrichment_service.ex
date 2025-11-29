defmodule EhsEnforcement.AI.EnrichmentService do
  @moduledoc """
  AI-powered enrichment service for enforcement actions (Cases and Notices).

  This service generates contextual intelligence for enforcement data including:
  - Regulation cross-references and legislation analysis
  - Industry benchmark comparisons
  - Historical pattern detection
  - Plain language summaries (layperson and professional)
  - Auto-generated tags and classifications
  - Confidence scores for AI-generated content

  ## Usage

      # Enrich a case
      {:ok, enrichment_data} = EnrichmentService.enrich_case(case)

      # Enrich a notice
      {:ok, enrichment_data} = EnrichmentService.enrich_notice(notice)

  ## Configuration

  Configure the AI provider in `config/runtime.exs`:

      config :ehs_enforcement, :ai_enrichment,
        provider: :runpod,  # or :openai, :mock
        runpod_api_key: System.get_env("RUNPOD_API_KEY"),
        runpod_endpoint: System.get_env("RUNPOD_ENDPOINT"),
        timeout_ms: 60_000,
        max_retries: 3
  """

  alias EhsEnforcement.AI.Client
  alias EhsEnforcement.Enforcement.{Case, Notice, Enrichment}

  require Logger

  @type enrichment_data :: %{
          regulation_links: map() | nil,
          benchmark_analysis: map() | nil,
          pattern_detection: map() | nil,
          layperson_summary: String.t() | nil,
          professional_summary: String.t() | nil,
          auto_tags: [String.t()],
          confidence_scores: map(),
          model_version: String.t(),
          processing_time_ms: non_neg_integer()
        }

  @doc """
  Enrich a case with AI-generated context.

  Generates comprehensive enrichment data for an enforcement case including
  regulation links, benchmarks, patterns, and summaries.

  ## Parameters

  - `case` - An `EhsEnforcement.Enforcement.Case` struct (must have offender loaded)
  - `opts` - Optional parameters:
    - `:save` - Whether to save the enrichment to the database (default: true)

  ## Returns

  - `{:ok, enrichment_data}` on success
  - `{:error, reason}` on failure
  """
  @spec enrich_case(Case.t(), keyword()) :: {:ok, enrichment_data()} | {:error, term()}
  def enrich_case(%Case{} = case_record, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, case_with_offender} <- ensure_offender_loaded(case_record),
         {:ok, enrichment_result} <- generate_case_enrichment(case_with_offender) do
      processing_time = System.monotonic_time(:millisecond) - start_time

      enrichment_data =
        enrichment_result
        |> Map.put(:processing_time_ms, processing_time)
        |> Map.put(:case_id, case_record.id)

      if Keyword.get(opts, :save, true) do
        save_enrichment(enrichment_data)
      else
        {:ok, enrichment_data}
      end
    end
  end

  @doc """
  Enrich a notice with AI-generated context.

  Generates comprehensive enrichment data for an enforcement notice.

  ## Parameters

  - `notice` - An `EhsEnforcement.Enforcement.Notice` struct (must have offender loaded)
  - `opts` - Optional parameters:
    - `:save` - Whether to save the enrichment to the database (default: true)

  ## Returns

  - `{:ok, enrichment_data}` on success
  - `{:error, reason}` on failure
  """
  @spec enrich_notice(Notice.t(), keyword()) :: {:ok, enrichment_data()} | {:error, term()}
  def enrich_notice(%Notice{} = notice, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, notice_with_offender} <- ensure_offender_loaded(notice),
         {:ok, enrichment_result} <- generate_notice_enrichment(notice_with_offender) do
      processing_time = System.monotonic_time(:millisecond) - start_time

      enrichment_data =
        enrichment_result
        |> Map.put(:processing_time_ms, processing_time)
        |> Map.put(:notice_id, notice.id)

      if Keyword.get(opts, :save, true) do
        save_enrichment(enrichment_data)
      else
        {:ok, enrichment_data}
      end
    end
  end

  @doc """
  Generate enrichment data without saving to database.

  Useful for previewing enrichment or batch processing.
  """
  @spec generate_enrichment(Case.t() | Notice.t()) :: {:ok, enrichment_data()} | {:error, term()}
  def generate_enrichment(%Case{} = case_record), do: enrich_case(case_record, save: false)
  def generate_enrichment(%Notice{} = notice), do: enrich_notice(notice, save: false)

  @doc """
  Check if the AI service is available and properly configured.
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    client = Client.get_client()
    client.health_check()
  end

  # Private functions

  defp generate_case_enrichment(case_record) do
    client = Client.get_client()

    # Build the enrichment prompt for cases
    messages = build_case_enrichment_messages(case_record)

    case client.complete(messages, json_mode: true, temperature: 0.3, max_tokens: 4096) do
      {:ok, %{content: content, model: model}} ->
        parse_enrichment_response(content, model)

      {:error, reason} = error ->
        Logger.error("Failed to generate case enrichment: #{inspect(reason)}")
        error
    end
  end

  defp generate_notice_enrichment(notice) do
    client = Client.get_client()

    # Build the enrichment prompt for notices
    messages = build_notice_enrichment_messages(notice)

    case client.complete(messages, json_mode: true, temperature: 0.3, max_tokens: 4096) do
      {:ok, %{content: content, model: model}} ->
        parse_enrichment_response(content, model)

      {:error, reason} = error ->
        Logger.error("Failed to generate notice enrichment: #{inspect(reason)}")
        error
    end
  end

  defp build_case_enrichment_messages(case_record) do
    offender_name = get_offender_name(case_record)

    [
      %{
        role: "system",
        content: case_system_prompt()
      },
      %{
        role: "user",
        content: """
        Analyze this UK enforcement case and provide comprehensive enrichment data.

        ## Case Details

        **Offender**: #{offender_name}
        **Case Reference**: #{case_record.case_reference || "N/A"}
        **Action Type**: #{case_record.offence_action_type || "Court Case"}
        **Action Date**: #{format_date(case_record.offence_action_date)}
        **Hearing Date**: #{format_date(case_record.offence_hearing_date)}
        **Result**: #{case_record.offence_result || "N/A"}
        **Fine**: #{format_currency(case_record.offence_fine)}
        **Costs**: #{format_currency(case_record.offence_costs)}
        **Breaches/Violations**: #{case_record.offence_breaches || "Not specified"}

        Please provide your analysis in the specified JSON format.
        """
      }
    ]
  end

  defp build_notice_enrichment_messages(notice) do
    offender_name = get_offender_name(notice)

    [
      %{
        role: "system",
        content: notice_system_prompt()
      },
      %{
        role: "user",
        content: """
        Analyze this UK enforcement notice and provide comprehensive enrichment data.

        ## Notice Details

        **Offender**: #{offender_name}
        **Notice Reference**: #{notice.regulator_ref_number || notice.regulator_id || "N/A"}
        **Notice Type**: #{notice.offence_action_type || "Enforcement Notice"}
        **Notice Date**: #{format_date(notice.notice_date)}
        **Operative Date**: #{format_date(notice.operative_date)}
        **Compliance Date**: #{format_date(notice.compliance_date)}
        **Notice Body**: #{notice.notice_body || "Not specified"}
        **Breaches/Requirements**: #{notice.offence_breaches || "Not specified"}
        **Legal Act**: #{notice.legal_act || "N/A"}
        **Legal Section**: #{notice.legal_section || "N/A"}

        Please provide your analysis in the specified JSON format.
        """
      }
    ]
  end

  defp case_system_prompt do
    """
    You are a UK environmental, health, and safety compliance expert specializing in enforcement action analysis.

    Your task is to analyze enforcement cases (court prosecutions) and provide structured enrichment data.

    ## Required Output Format (JSON)

    You MUST respond with valid JSON in this exact structure:

    {
      "regulation_links": {
        "primary_regulations": [
          {
            "title": "Full regulation/act title",
            "section": "Specific section reference",
            "relevance": "Brief explanation of how this regulation was breached"
          }
        ],
        "related_regulations": [
          {
            "title": "Related regulation title",
            "section": "Section if applicable",
            "relevance": "Why this is related"
          }
        ]
      },
      "benchmark_analysis": {
        "fine_percentile": <number 1-100>,
        "similar_cases_count": <estimated number>,
        "average_fine_similar": <amount in GBP>,
        "severity_assessment": "<below average|average|above average|severe>",
        "industry_context": "Brief context about typical fines in this industry/violation type"
      },
      "pattern_detection": {
        "industry_pattern": "Description of common industry pattern this fits",
        "recurring_violation": "Type of recurring violation if applicable",
        "trend_analysis": "Brief analysis of enforcement trends",
        "repeat_offender": <true|false>,
        "pattern_confidence": <0.0-1.0>
      },
      "layperson_summary": "150-300 word plain English summary explaining what happened and why it matters, suitable for someone without legal or technical background",
      "professional_summary": "200-400 word technical summary for compliance professionals, including legal citations and regulatory context",
      "auto_tags": ["tag1", "tag2", "tag3"],
      "confidence_scores": {
        "regulation_links": <0.0-1.0>,
        "benchmark_analysis": <0.0-1.0>,
        "pattern_detection": <0.0-1.0>,
        "summaries": <0.0-1.0>,
        "tags": <0.0-1.0>
      }
    }

    ## Guidelines

    1. **Regulation Links**: Identify specific UK legislation violated (HSWA 1974, MHSWR 1999, specific industry regulations)
    2. **Benchmark Analysis**: Compare to typical fines for similar violations in the UK
    3. **Pattern Detection**: Identify common patterns (industry sector, violation type, geographical)
    4. **Summaries**: Layperson summary should be accessible; Professional summary should be technically precise
    5. **Tags**: Use lowercase, underscore-separated tags (e.g., "workplace_safety", "fall_from_height")
    6. **Confidence Scores**: Be honest about uncertainty - lower scores when information is limited
    """
  end

  defp notice_system_prompt do
    """
    You are a UK environmental, health, and safety compliance expert specializing in enforcement notice analysis.

    Your task is to analyze enforcement notices (improvement/prohibition notices, compliance orders) and provide structured enrichment data.

    ## Required Output Format (JSON)

    You MUST respond with valid JSON in this exact structure:

    {
      "regulation_links": {
        "primary_regulations": [
          {
            "title": "Full regulation/act title",
            "section": "Specific section reference",
            "relevance": "Brief explanation of the compliance requirement"
          }
        ],
        "related_regulations": [
          {
            "title": "Related regulation title",
            "section": "Section if applicable",
            "relevance": "Why this is related"
          }
        ]
      },
      "benchmark_analysis": {
        "typical_compliance_period": "Typical timeframe for similar notices",
        "escalation_likelihood": "<low|medium|high>",
        "similar_notices_count": <estimated number>,
        "industry_context": "Brief context about notice frequency in this industry"
      },
      "pattern_detection": {
        "industry_pattern": "Description of common industry pattern this fits",
        "recurring_requirement": "Type of recurring compliance requirement",
        "trend_analysis": "Brief analysis of notice trends",
        "repeat_recipient": <true|false>,
        "pattern_confidence": <0.0-1.0>
      },
      "layperson_summary": "150-300 word plain English summary explaining what the notice requires and why, suitable for someone without legal or technical background",
      "professional_summary": "200-400 word technical summary for compliance professionals, including specific compliance requirements and regulatory context",
      "auto_tags": ["tag1", "tag2", "tag3"],
      "confidence_scores": {
        "regulation_links": <0.0-1.0>,
        "benchmark_analysis": <0.0-1.0>,
        "pattern_detection": <0.0-1.0>,
        "summaries": <0.0-1.0>,
        "tags": <0.0-1.0>
      }
    }

    ## Guidelines

    1. **Regulation Links**: Identify the specific regulations requiring compliance
    2. **Benchmark Analysis**: Focus on compliance timelines and escalation patterns
    3. **Pattern Detection**: Identify common patterns in notice types and industries
    4. **Summaries**: Layperson summary should explain requirements clearly; Professional summary should detail compliance steps
    5. **Tags**: Use lowercase, underscore-separated tags (e.g., "improvement_notice", "fire_safety")
    6. **Confidence Scores**: Be honest about uncertainty - lower scores when information is limited
    """
  end

  defp parse_enrichment_response(content, model) do
    case Jason.decode(content) do
      {:ok, parsed} ->
        enrichment_data = %{
          regulation_links: flatten_regulation_links(parsed["regulation_links"]),
          benchmark_analysis: parsed["benchmark_analysis"],
          pattern_detection: parsed["pattern_detection"],
          layperson_summary: parsed["layperson_summary"],
          professional_summary: parsed["professional_summary"],
          auto_tags: parsed["auto_tags"] || [],
          confidence_scores: parsed["confidence_scores"] || %{},
          model_version: model,
          generated_at: DateTime.utc_now()
        }

        {:ok, enrichment_data}

      {:error, reason} ->
        Logger.error("Failed to parse AI response as JSON: #{inspect(reason)}")
        Logger.debug("Raw content: #{content}")
        {:error, {:json_parse_error, reason}}
    end
  end

  # Convert nested regulation_links structure to flat array
  # Input: %{"primary_regulations" => [...], "related_regulations" => [...]}
  # Output: [%{type: "primary", ...}, %{type: "related", ...}]
  defp flatten_regulation_links(nil), do: nil

  defp flatten_regulation_links(%{
         "primary_regulations" => primary,
         "related_regulations" => related
       }) do
    primary_with_type =
      (primary || [])
      |> Enum.map(&Map.put(&1, "type", "primary"))

    related_with_type =
      (related || [])
      |> Enum.map(&Map.put(&1, "type", "related"))

    primary_with_type ++ related_with_type
  end

  defp flatten_regulation_links(links) when is_list(links), do: links
  defp flatten_regulation_links(_), do: nil

  defp save_enrichment(enrichment_data) do
    case Ash.create(Enrichment, enrichment_data, domain: EhsEnforcement.Enforcement) do
      {:ok, enrichment} ->
        Logger.info("Created enrichment #{enrichment.id} for #{enrichment_type(enrichment_data)}")
        {:ok, enrichment}

      {:error, reason} = error ->
        Logger.error("Failed to save enrichment: #{inspect(reason)}")
        error
    end
  end

  defp enrichment_type(%{case_id: id}) when not is_nil(id), do: "case #{id}"
  defp enrichment_type(%{notice_id: id}) when not is_nil(id), do: "notice #{id}"
  defp enrichment_type(_), do: "unknown"

  defp ensure_offender_loaded(%Case{offender: %Ash.NotLoaded{}} = case_record) do
    Ash.load(case_record, :offender, domain: EhsEnforcement.Enforcement)
  end

  defp ensure_offender_loaded(%Notice{offender: %Ash.NotLoaded{}} = notice) do
    Ash.load(notice, :offender, domain: EhsEnforcement.Enforcement)
  end

  defp ensure_offender_loaded(record), do: {:ok, record}

  defp get_offender_name(%{offender: %{name: name}}) when is_binary(name), do: name
  defp get_offender_name(_), do: "Unknown"

  defp format_date(nil), do: "N/A"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d %B %Y")
  defp format_date(date), do: to_string(date)

  defp format_currency(nil), do: "N/A"
  defp format_currency(%Decimal{} = amount), do: "£#{Decimal.to_string(amount)}"
  defp format_currency(amount) when is_number(amount), do: "£#{amount}"
  defp format_currency(amount), do: "£#{amount}"
end
