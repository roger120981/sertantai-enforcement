defmodule EhsEnforcementWeb.NLQueryController do
  use EhsEnforcementWeb, :controller
  require Logger

  @doc """
  Translate natural language query to TableKit filter configuration.

  POST /api/nl-query
  Body: {"query": "Show me HSE cases with fines over £50,000"}

  Response:
  {
    "filters": [...],
    "sort": {...},
    "raw_response": "..." (optional, for debugging)
  }
  """
  def translate(conn, %{"query" => user_query}) do
    Logger.info("NL Query translation request: #{user_query}")

    case call_ollama(user_query) do
      {:ok, parsed_json} ->
        json(conn, parsed_json)

      {:error, :parse_error, raw_response} ->
        Logger.error("Failed to parse AI response: #{raw_response}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Could not parse AI response",
          raw_response: raw_response,
          suggestion: "Try rephrasing your query"
        })

      {:error, reason} ->
        Logger.error("Ollama request failed: #{inspect(reason)}")

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "AI service unavailable", details: inspect(reason)})
    end
  end

  @doc """
  Test endpoint to try different prompts easily.

  POST /api/nl-query/test
  Body: {
    "query": "HSE cases over 50k",
    "prompt_version": "v1" (optional, defaults to "v1")
  }
  """
  def test(conn, %{"query" => user_query} = params) do
    prompt_version = Map.get(params, "prompt_version", "v1")
    prompt = build_prompt(user_query, prompt_version)

    case call_ollama_raw(prompt) do
      {:ok, response} ->
        # Try to parse
        case parse_ai_response(response) do
          {:ok, parsed} ->
            json(conn, %{
              success: true,
              prompt_version: prompt_version,
              parsed: parsed,
              raw: response
            })

          {:error, :parse_error, raw} ->
            json(conn, %{
              success: false,
              prompt_version: prompt_version,
              raw: raw,
              parse_error: "Could not extract valid JSON"
            })
        end

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "AI service unavailable", details: inspect(reason)})
    end
  end

  # Private functions

  defp call_ollama(user_query) do
    prompt = build_prompt(user_query, "v5")

    case call_ollama_raw(prompt) do
      {:ok, response} -> parse_ai_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_ollama_raw(prompt) do
    url = ollama_url() <> "/api/generate"

    body =
      Jason.encode!(%{
        model: "phi3",
        prompt: prompt,
        stream: false
      })

    case Req.post(url, body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: 200, body: %{"response" => response}}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ai_response(response) do
    # Strip markdown code blocks
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\s*/m, "")
      |> String.replace(~r/^```\s*/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, parsed} when is_map(parsed) ->
        # Ensure it has the filters key
        if Map.has_key?(parsed, "filters") do
          {:ok, parsed}
        else
          # If it's just an array, wrap it
          {:ok, %{"filters" => parsed, "sort" => nil}}
        end

      {:ok, parsed} when is_list(parsed) ->
        # Array response - wrap in filters
        {:ok, %{"filters" => parsed, "sort" => nil}}

      {:error, _} ->
        {:error, :parse_error, response}
    end
  end

  defp build_prompt(user_query, "v1") do
    """
    Convert to JSON filter config.

    Available fields:
    - record_type: "case" or "notice"
    - regulator_id: "hse", "sepa", "ea", "nrw"
    - offence_fine: number (GBP)
    - offence_action_date: date YYYY-MM-DD
    - offender_name: string
    - case_reference: string

    Operators:
    - String: equals, contains
    - Numeric: greater_than, less_than, greater_or_equal, less_or_equal

    Output JSON structure:
    {
      "filters": [
        {"id": "f1", "field": "regulator_id", "operator": "equals", "value": "hse"}
      ],
      "sort": {"columnId": "offence_fine", "direction": "desc"}
    }

    Query: #{user_query}

    Output JSON only, no explanation:
    """
  end

  defp build_prompt(user_query, "v2") do
    """
    JSON filter generator.

    Schema: {"filters": [{"id": "ID", "field": "FIELD", "operator": "OP", "value": VALUE}], "sort": {"columnId": "FIELD", "direction": "asc|desc"}}

    Fields: record_type, regulator_id, offence_fine, offence_action_date, offender_name

    Example input: "HSE cases over £50,000"
    Example output: {"filters": [{"id": "f1", "field": "regulator_id", "operator": "equals", "value": "hse"}, {"id": "f2", "field": "record_type", "operator": "equals", "value": "case"}, {"id": "f3", "field": "offence_fine", "operator": "greater_than", "value": 50000}], "sort": {"columnId": "offence_fine", "direction": "desc"}}

    Input: #{user_query}
    Output:
    """
  end

  defp build_prompt(user_query, "v3") do
    """
    Generate JSON. Use this EXACT structure: {"filters":[{"id":"STRING","field":"FIELD_NAME","operator":"OPERATOR","value":VALUE}],"sort":{"columnId":"STRING","direction":"asc|desc"}}

    Fields: record_type (case/notice), regulator_id (hse/sepa/ea/nrw), offence_fine (number), offence_action_date (YYYY-MM-DD), offender_name (string)

    Query: #{user_query}

    JSON:
    """
  end

  defp build_prompt(user_query, "v5") do
    """
    Convert natural language to JSON configuration for table display.

    Available fields:
    - case_reference: Case/notice reference number
    - offence_action_date: Date of enforcement action (YYYY-MM-DD)
    - offence_result: Outcome (e.g., "Convicted", "Fine imposed")
    - offence_action_type: Type of action (e.g., "Prosecution", "Enforcement Notice")
    - offence_fine: Fine amount in GBP (number)
    - offence_costs: Associated costs in GBP (number)
    - offence_breaches: Description of violations (string)
    - offender_name: Name of offender/company (string)
    - agency_code: Regulatory agency code ("hse", "ea", "onr", "orr")
    - agency_name: Full agency name (e.g., "Health and Safety Executive")
    - record_type: Type ("case" or "notice")

    Operators:
    - String: equals, contains, starts_with, ends_with
    - Number: greater_than, less_than, greater_or_equal, less_or_equal

    Output structure:
    {
      "viewType": "unified",
      "filters": [{"id": "f1", "field": "field_name", "operator": "operator", "value": value}],
      "sort": {"columnId": "field_name", "direction": "asc|desc"},
      "columns": ["field1", "field2", ...],
      "columnOrder": ["field1", "field2", ...]
    }

    Column selection rules:
    - If user specifies columns (e.g., "show me case ref and fine"), include only those: ["case_reference", "offence_fine"]
    - If user doesn't specify, include relevant columns based on query context
    - Always include identifying columns first (case_reference, offence_action_date)
    - columnOrder should match the logical importance for the query

    Examples:

    Query: "Show me HSE cases with fines over £50,000"
    Output: {"viewType": "unified", "filters": [{"id": "f1", "field": "agency_code", "operator": "equals", "value": "hse"}, {"id": "f2", "field": "record_type", "operator": "equals", "value": "case"}, {"id": "f3", "field": "offence_fine", "operator": "greater_than", "value": 50000}], "sort": {"columnId": "offence_fine", "direction": "desc"}, "columns": ["case_reference", "offence_action_date", "offence_fine", "offence_result", "offender_name"], "columnOrder": ["offence_fine", "case_reference", "offender_name", "offence_action_date", "offence_result"]}

    Query: "Show me just the case reference and fine amount for EA prosecutions"
    Output: {"viewType": "unified", "filters": [{"id": "f1", "field": "agency_code", "operator": "equals", "value": "ea"}, {"id": "f2", "field": "offence_action_type", "operator": "contains", "value": "prosecution"}], "sort": {"columnId": "offence_fine", "direction": "desc"}, "columns": ["case_reference", "offence_fine"], "columnOrder": ["case_reference", "offence_fine"]}

    User query: #{user_query}

    Output JSON only, no explanation:
    """
  end

  defp ollama_url do
    Application.get_env(
      :ehs_enforcement,
      :ollama_url,
      "https://u3nu19jne57pqq-11434.proxy.runpod.net"
    )
  end
end
