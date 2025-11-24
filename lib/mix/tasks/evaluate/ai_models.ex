defmodule Mix.Tasks.Evaluate.AiModels do
  @moduledoc """
  Evaluates AI models on RunPod for enforcement case enrichment.

  This task tests multiple AI models against a standardized test dataset,
  measuring accuracy, latency, cost, and reliability. Results are saved
  for comparison and decision-making.

  ## Prerequisites

  1. Create test dataset: `mix evaluate.create_test_dataset`
  2. Set RunPod API credentials in environment variables:
     - RUNPOD_API_KEY
     - RUNPOD_ENDPOINT_LLAMA_70B (optional, model-specific endpoints)
     - RUNPOD_ENDPOINT_QWEN_72B
     - RUNPOD_ENDPOINT_LLAMA_8B

  ## Usage

      # Evaluate all configured models
      mix evaluate.ai_models

      # Evaluate specific model only
      mix evaluate.ai_models --model llama-3.1-70b

      # Quick screening (first 5 cases only)
      mix evaluate.ai_models --quick

  ## Output

  Generates evaluation reports in `test/fixtures/ai_evaluation/results/`:
  - {model_name}_results.json - Raw enrichment outputs
  - {model_name}_metrics.json - Performance metrics
  - comparison_report.md - Summary comparison table
  """

  use Mix.Task
  require Logger

  @shortdoc "Evaluate AI models on RunPod for case enrichment"

  @test_dataset_path "test/fixtures/ai_evaluation/test_dataset.json"
  @results_dir "test/fixtures/ai_evaluation/results"
  # 60 seconds per enrichment
  @timeout 60_000

  # Model configurations
  # Update these endpoints after setting up RunPod pods
  @models [
    %{
      name: "llama-3.1-70b",
      endpoint: System.get_env("RUNPOD_ENDPOINT_LLAMA_70B"),
      description: "Meta Llama 3.1 70B Instruct - High accuracy, slower",
      enabled: true
    },
    %{
      name: "qwen-2.5-72b",
      endpoint: System.get_env("RUNPOD_ENDPOINT_QWEN_72B"),
      description: "Qwen 2.5 72B Instruct - Strong reasoning, balanced",
      enabled: true
    },
    %{
      name: "llama-3.1-8b",
      endpoint: System.get_env("RUNPOD_ENDPOINT_LLAMA_8B"),
      description: "Meta Llama 3.1 8B Instruct - Fast, cost-effective",
      enabled: true
    }
  ]

  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    Mix.shell().info("AI Model Evaluation for Enforcement Case Enrichment")
    Mix.shell().info("====================================================")
    Mix.shell().info("")

    # Ensure results directory exists
    File.mkdir_p!(@results_dir)

    # Load test dataset
    test_cases = load_test_dataset(opts)
    Mix.shell().info("Loaded #{length(test_cases)} test cases")
    Mix.shell().info("")

    # Filter models to evaluate
    models = filter_models(opts)

    if Enum.empty?(models) do
      Mix.shell().error("No models configured or enabled. Check environment variables.")
      Mix.shell().error("Required: RUNPOD_API_KEY and model endpoint URLs")
      exit(:normal)
    end

    Mix.shell().info("Evaluating #{length(models)} model(s):")

    Enum.each(models, fn model ->
      Mix.shell().info("  - #{model.name}: #{model.description}")
    end)

    Mix.shell().info("")

    # Evaluate each model
    results =
      Enum.map(models, fn model ->
        Mix.shell().info("Evaluating #{model.name}...")
        evaluate_model(model, test_cases, opts)
      end)

    # Generate comparison report
    generate_comparison_report(results)

    Mix.shell().info("")
    Mix.shell().info("✓ Evaluation complete!")
    Mix.shell().info("Results saved to: #{@results_dir}")
  end

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [model: :string, quick: :boolean],
        aliases: [m: :model, q: :quick]
      )

    opts
  end

  defp load_test_dataset(opts) do
    unless File.exists?(@test_dataset_path) do
      Mix.shell().error("Test dataset not found: #{@test_dataset_path}")
      Mix.shell().error("Run: mix evaluate.create_test_dataset")
      exit(:normal)
    end

    dataset = File.read!(@test_dataset_path) |> Jason.decode!()

    cases = dataset["cases"]

    if opts[:quick] do
      Mix.shell().info("Quick mode: using first 5 cases")
      Enum.take(cases, 5)
    else
      cases
    end
  end

  defp filter_models(opts) do
    models = Enum.filter(@models, & &1.enabled)

    if opts[:model] do
      Enum.filter(models, &(&1.name == opts[:model]))
    else
      models
    end
  end

  defp evaluate_model(model, test_cases, _opts) do
    if is_nil(model.endpoint) do
      Mix.shell().warn("Skipping #{model.name}: endpoint not configured")

      %{
        model: model,
        status: :skipped,
        reason: "Endpoint not configured"
      }
    else
      do_evaluate_model(model, test_cases)
    end
  end

  defp do_evaluate_model(model, test_cases) do
    start_time = System.monotonic_time(:millisecond)

    # Enrich all test cases
    enrichment_results =
      Enum.with_index(test_cases, 1)
      |> Enum.map(fn {case_data, idx} ->
        Mix.shell().info("  Case #{idx}/#{length(test_cases)}...")
        enrich_case(model, case_data)
      end)

    end_time = System.monotonic_time(:millisecond)
    total_time_ms = end_time - start_time

    # Calculate metrics
    metrics = calculate_metrics(enrichment_results, total_time_ms)

    # Save results
    save_results(model, enrichment_results, metrics)

    Mix.shell().info("✓ #{model.name} complete")
    Mix.shell().info("  Success rate: #{metrics.success_rate}%")
    Mix.shell().info("  Avg latency: #{metrics.avg_latency_ms}ms")
    Mix.shell().info("")

    %{
      model: model,
      status: :completed,
      metrics: metrics,
      enrichments: enrichment_results
    }
  end

  defp enrich_case(model, case_data) do
    case_start = System.monotonic_time(:millisecond)

    result =
      try do
        # Call RunPod API with enrichment prompt
        response = call_runpod_api(model, case_data)
        case_end = System.monotonic_time(:millisecond)

        %{
          case_id: case_data["id"],
          status: :success,
          enrichment: response,
          latency_ms: case_end - case_start,
          error: nil
        }
      rescue
        error ->
          case_end = System.monotonic_time(:millisecond)
          Logger.error("Enrichment failed: #{inspect(error)}")

          %{
            case_id: case_data["id"],
            status: :error,
            enrichment: nil,
            latency_ms: case_end - case_start,
            error: Exception.message(error)
          }
      end

    result
  end

  defp call_runpod_api(model, case_data) do
    # Build enrichment prompt
    prompt = build_enrichment_prompt(case_data)

    # Prepare request payload (OpenAI-compatible format)
    payload = %{
      "model" => model.name,
      "messages" => [
        %{"role" => "system", "content" => get_system_prompt()},
        %{"role" => "user", "content" => prompt}
      ],
      "temperature" => 0.3,
      "max_tokens" => 2000,
      "response_format" => %{"type" => "json_object"}
    }

    # Make HTTP request to RunPod endpoint
    api_key = System.get_env("RUNPOD_API_KEY")

    case Req.post(model.endpoint,
           json: payload,
           auth: {:bearer, api_key},
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"])
        Jason.decode!(content)

      {:ok, %{status: status_code, body: body}} ->
        raise "RunPod API error: HTTP #{status_code} - #{inspect(body)}"

      {:error, error} ->
        raise "HTTP request failed: #{inspect(error)}"
    end
  end

  defp get_system_prompt do
    """
    You are a UK environmental, health, and safety (EHS) compliance expert specializing in enforcement action analysis.

    Your task is to enrich enforcement case data with structured insights that help compliance professionals understand regulatory patterns, benchmark penalties, and identify relevant regulations.

    CRITICAL: You must respond with valid JSON only. No additional text before or after the JSON object.

    The JSON structure must include:
    - regulation_links: Array of relevant UK EHS regulations with sections
    - benchmark_analysis: Statistical comparison with similar cases
    - pattern_detection: Industry/violation patterns identified
    - layperson_summary: Plain English explanation (150-300 words)
    - professional_summary: Technical legal analysis (200-400 words)
    - auto_tags: Array of categorization tags
    - confidence_scores: Object with confidence levels (0.0-1.0) for each section
    """
  end

  defp build_enrichment_prompt(case_data) do
    """
    Analyze this UK enforcement case and provide comprehensive enrichment:

    Case Reference: #{case_data["case_reference"] || "Unknown"}
    Regulator ID: #{case_data["regulator_id"] || "Unknown"}
    Offence Result: #{case_data["offence_result"] || "Unknown"}
    Action Type: #{case_data["offence_action_type"] || "Unknown"}
    Fine: £#{format_decimal(case_data["offence_fine"])}
    Costs: £#{format_decimal(case_data["offence_costs"])}
    Action Date: #{case_data["offence_action_date"]}
    Breaches: #{case_data["offence_breaches"] || "Not specified"}
    Environmental Impact: #{case_data["environmental_impact"] || "Not specified"}

    Provide enrichment in the following JSON format:

    {
      "regulation_links": {
        "primary_regulations": [
          {"title": "Regulation name", "section": "Section reference", "relevance": "Why this applies"}
        ],
        "related_regulations": [...]
      },
      "benchmark_analysis": {
        "fine_percentile": 75,
        "severity_assessment": "Description of penalty severity",
        "notes": "Additional context"
      },
      "pattern_detection": {
        "industry_pattern": "Industry or sector pattern identified",
        "recurring_violation": "Common violation type",
        "notes": "Pattern analysis"
      },
      "layperson_summary": "Plain English summary here (150-300 words)",
      "professional_summary": "Technical legal analysis here (200-400 words)",
      "auto_tags": ["tag1", "tag2", "tag3"],
      "confidence_scores": {
        "regulation_links": 0.92,
        "benchmark_analysis": 0.78,
        "pattern_detection": 0.65,
        "summaries": 0.88,
        "tags": 0.91
      }
    }

    Ensure all fields are present and properly formatted as JSON.
    """
  end

  defp format_decimal(nil), do: "0.00"

  defp format_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> Decimal.to_string(decimal, :normal)
      :error -> "0.00"
    end
  end

  defp format_decimal(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp format_decimal(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 2)

  defp calculate_metrics(enrichment_results, total_time_ms) do
    total_cases = length(enrichment_results)
    successful = Enum.count(enrichment_results, &(&1.status == :success))
    failed = total_cases - successful

    success_rate =
      if total_cases > 0, do: Float.round(successful / total_cases * 100, 1), else: 0.0

    latencies = Enum.map(enrichment_results, & &1.latency_ms)
    avg_latency = if total_cases > 0, do: Enum.sum(latencies) / total_cases, else: 0.0
    p95_latency = percentile(latencies, 95)
    p99_latency = percentile(latencies, 99)

    %{
      total_cases: total_cases,
      successful: successful,
      failed: failed,
      success_rate: success_rate,
      total_time_ms: total_time_ms,
      avg_latency_ms: Float.round(avg_latency, 1),
      p95_latency_ms: p95_latency,
      p99_latency_ms: p99_latency,
      throughput_per_hour:
        if(total_time_ms > 0,
          do: Float.round(total_cases / (total_time_ms / 3_600_000), 1),
          else: 0.0
        )
    }
  end

  defp percentile([], _p), do: 0

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    index = ceil(length(sorted) * p / 100) - 1
    Enum.at(sorted, max(0, index), 0)
  end

  defp save_results(model, enrichment_results, metrics) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    results_file = Path.join(@results_dir, "#{model.name}_results.json")
    metrics_file = Path.join(@results_dir, "#{model.name}_metrics.json")

    # Save enrichment results
    results_data = %{
      model: model.name,
      timestamp: timestamp,
      enrichments: enrichment_results
    }

    File.write!(results_file, Jason.encode!(results_data, pretty: true))

    # Save metrics
    metrics_data = %{
      model: model.name,
      timestamp: timestamp,
      metrics: metrics
    }

    File.write!(metrics_file, Jason.encode!(metrics_data, pretty: true))
  end

  defp generate_comparison_report(results) do
    report_path = Path.join(@results_dir, "comparison_report.md")

    content = """
    # AI Model Evaluation Comparison Report

    **Generated**: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Summary

    Evaluated #{length(results)} model(s) for enforcement case enrichment.

    ## Performance Comparison

    | Model | Success Rate | Avg Latency (ms) | P95 Latency (ms) | Throughput (cases/hr) |
    |-------|--------------|------------------|------------------|-----------------------|
    #{generate_comparison_rows(results)}

    ## Model Details

    #{generate_model_details(results)}

    ## Recommendations

    ### Top Performer (Accuracy)
    *Manual review required - check enrichment quality in individual result files*

    ### Top Performer (Speed)
    #{identify_fastest_model(results)}

    ### Top Performer (Balance)
    *Consider success rate, latency, and manual quality review*

    ## Next Steps

    1. Review individual enrichment outputs in `results/` directory
    2. Manually validate regulation links and summaries for accuracy
    3. Calculate cost per enrichment based on RunPod pricing
    4. Select production model and update configuration
    5. Implement production AI service with selected model

    ## Files Generated

    #{list_result_files(results)}
    """

    File.write!(report_path, content)
    Mix.shell().info("Comparison report: #{report_path}")
  end

  defp generate_comparison_rows(results) do
    results
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.map(fn %{model: model, metrics: metrics} ->
      "| #{model.name} | #{metrics.success_rate}% | #{metrics.avg_latency_ms} | #{metrics.p95_latency_ms} | #{metrics.throughput_per_hour} |"
    end)
    |> Enum.join("\n")
  end

  defp generate_model_details(results) do
    results
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.map(fn %{model: model, metrics: metrics} ->
      """
      ### #{model.name}

      **Description**: #{model.description}

      **Performance**:
      - Total cases: #{metrics.total_cases}
      - Successful: #{metrics.successful}
      - Failed: #{metrics.failed}
      - Success rate: #{metrics.success_rate}%
      - Average latency: #{metrics.avg_latency_ms}ms
      - P95 latency: #{metrics.p95_latency_ms}ms
      - P99 latency: #{metrics.p99_latency_ms}ms
      - Throughput: #{metrics.throughput_per_hour} cases/hour
      - Total time: #{Float.round(metrics.total_time_ms / 1000, 1)}s

      **Status**: ✓ Evaluation complete
      """
    end)
    |> Enum.join("\n")
  end

  defp identify_fastest_model(results) do
    fastest =
      results
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.min_by(& &1.metrics.avg_latency_ms, fn -> nil end)

    case fastest do
      nil ->
        "*No models completed successfully*"

      %{model: model, metrics: metrics} ->
        "**#{model.name}** (#{metrics.avg_latency_ms}ms avg latency)"
    end
  end

  defp list_result_files(results) do
    results
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.map(fn %{model: model} ->
      "- `#{model.name}_results.json` - Raw enrichment outputs\n- `#{model.name}_metrics.json` - Performance metrics"
    end)
    |> Enum.join("\n")
  end
end
