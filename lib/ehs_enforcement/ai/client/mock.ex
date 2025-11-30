defmodule EhsEnforcement.AI.Client.Mock do
  @moduledoc """
  Mock AI client for testing and development.

  Returns realistic enrichment responses without making actual API calls.
  Useful for:
  - Local development without API credentials
  - Unit testing
  - CI/CD pipelines

  ## Configuration

      config :ehs_enforcement, :ai_enrichment,
        provider: :mock

  ## Customizing Mock Responses

  You can override mock responses in tests using process dictionary:

      # In your test
      Process.put(:ai_mock_response, {:ok, %{content: "custom response", ...}})
  """

  @behaviour EhsEnforcement.AI.Client

  require Logger

  @impl true
  def complete(messages, opts \\ []) do
    # Check for custom mock response in process dictionary (for tests)
    case Process.get(:ai_mock_response) do
      nil ->
        generate_mock_response(messages, opts)

      {:ok, _} = response ->
        response

      {:error, _} = error ->
        error

      custom_fn when is_function(custom_fn, 2) ->
        custom_fn.(messages, opts)
    end
  end

  @impl true
  def health_check do
    {:ok, %{status: :available, model: "mock-model-v1", provider: :mock}}
  end

  # Generate realistic mock enrichment responses based on message content
  defp generate_mock_response(messages, opts) do
    # Simulate some latency
    latency = Enum.random(100..500)
    Process.sleep(div(latency, 10))

    # Determine response type based on system message content
    system_message =
      Enum.find(messages, fn msg ->
        msg[:role] == "system" || msg["role"] == "system"
      end)

    content = generate_content_for_task(system_message, opts)

    {:ok,
     %{
       content: content,
       model: "mock-model-v1",
       usage: %{
         prompt_tokens: estimate_tokens(messages),
         completion_tokens: estimate_tokens(content),
         total_tokens: estimate_tokens(messages) + estimate_tokens(content)
       },
       latency_ms: latency
     }}
  end

  defp generate_content_for_task(system_message, opts) do
    content = get_message_content(system_message)

    cond do
      # NRW article extraction
      String.contains?(content || "", "Natural Resources Wales") or
          String.contains?(content || "", "NRW") ->
        generate_nrw_extraction_response()

      String.contains?(content || "", "regulation") ->
        generate_regulation_links_response()

      String.contains?(content || "", "benchmark") ->
        generate_benchmark_response()

      String.contains?(content || "", "pattern") ->
        generate_pattern_response()

      String.contains?(content || "", "layperson") or String.contains?(content || "", "summary") ->
        generate_summary_response(content)

      String.contains?(content || "", "tag") ->
        generate_tags_response()

      Keyword.get(opts, :json_mode, false) ->
        generate_full_enrichment_response()

      true ->
        generate_full_enrichment_response()
    end
  end

  defp get_message_content(nil), do: ""
  defp get_message_content(%{content: content}), do: content
  defp get_message_content(%{"content" => content}), do: content
  defp get_message_content(_), do: ""

  defp generate_regulation_links_response do
    Jason.encode!(%{
      primary_regulations: [
        %{
          title: "Health and Safety at Work Act 1974",
          section: "Section 2(1)",
          relevance: "General duty of employer to ensure health and safety of employees"
        },
        %{
          title: "Management of Health and Safety at Work Regulations 1999",
          section: "Regulation 3",
          relevance: "Risk assessment requirements"
        }
      ],
      related_regulations: [
        %{
          title: "Work at Height Regulations 2005",
          section: "Regulation 4",
          relevance: "Organization and planning of work at height"
        }
      ]
    })
  end

  defp generate_benchmark_response do
    Jason.encode!(%{
      fine_percentile: Enum.random(25..95),
      similar_cases_count: Enum.random(5..50),
      average_fine_similar: Enum.random(10_000..200_000),
      median_fine_similar: Enum.random(8_000..150_000),
      severity_assessment: Enum.random(["below average", "average", "above average", "severe"]),
      industry_context:
        "This fine is typical for similar workplace safety violations in the construction sector."
    })
  end

  defp generate_pattern_response do
    Jason.encode!(%{
      industry_pattern: "Construction sector - fall from height incidents",
      recurring_violation: "Inadequate edge protection and scaffolding inspection failures",
      trend_analysis: "Increasing enforcement in Q3-Q4 2024",
      similar_case_count: Enum.random(3..15),
      repeat_offender: false,
      pattern_confidence: Float.round(0.7 + :rand.uniform() * 0.25, 2)
    })
  end

  defp generate_summary_response(content) do
    if String.contains?(content || "", "professional") do
      """
      This enforcement action relates to a breach of the Health and Safety at Work Act 1974, \
      specifically Section 2(1) concerning the general duty of care owed by employers to employees. \
      The prosecution followed an HSE investigation into working practices at height, which identified \
      systemic failures in risk assessment and control measures. The fine reflects the severity of \
      the breach and the potential for serious injury. The defendant company has been required to \
      implement improved safety management systems and provide additional training to supervisory staff.
      """
    else
      """
      A company was fined for failing to keep workers safe on a construction site. \
      The Health and Safety Executive (HSE) found that proper safety measures were not in place \
      when workers were doing jobs at height. This put workers at risk of falling and being seriously hurt. \
      The company must now make sure they have better safety rules and that all workers are properly trained.
      """
    end
  end

  defp generate_tags_response do
    tags =
      Enum.take_random(
        [
          "workplace_safety",
          "construction",
          "fall_from_height",
          "section_2_breach",
          "risk_assessment",
          "ppe_failure",
          "training_deficiency",
          "machinery_safety",
          "chemical_exposure",
          "fire_safety",
          "manual_handling"
        ],
        Enum.random(3..6)
      )

    Jason.encode!(tags)
  end

  defp generate_nrw_extraction_response do
    Jason.encode!(%{
      cases: [
        %{
          offender_name: "Benji and Co Limited",
          offender_type: "company",
          offender_location: "Powys",
          hearing_date: "2025-10-14",
          fine_amount: 40000,
          costs_amount: 15000,
          surcharge_amount: 2000,
          total_amount: 57000,
          poca_amount: nil,
          offence_description:
            "Operating a waste site without required environmental permit and depositing waste tyres without valid permit",
          offence_result:
            "Fined £10,000 for each of four offences, totalling £40,000, plus £15,000 prosecution costs and £2,000 victim surcharge",
          legislation:
            "Environmental Permitting (England and Wales) Regulations 2016; Environmental Protection Act 1990"
        },
        %{
          offender_name: "Peter Rees",
          offender_type: "individual",
          offender_location: nil,
          hearing_date: "2025-10-14",
          fine_amount: 10000,
          costs_amount: nil,
          surcharge_amount: 2000,
          total_amount: 12000,
          poca_amount: nil,
          offence_description:
            "As company director, consenting to, being complicit in, or neglecting duties in connection with the company's unlawful activity",
          offence_result: "Fined £10,000 and ordered to pay £2,000 victim surcharge",
          legislation: "Environmental Protection Act 1990"
        }
      ],
      extraction_notes:
        "Two defendants - company and director - prosecuted together with separate penalties"
    })
  end

  defp generate_full_enrichment_response do
    Jason.encode!(%{
      regulation_links: %{
        primary_regulations: [
          %{
            title: "Health and Safety at Work Act 1974",
            section: "Section 2(1)",
            relevance: "General duty of employer"
          }
        ],
        related_regulations: []
      },
      benchmark_analysis: %{
        fine_percentile: 65,
        similar_cases_count: 23,
        average_fine_similar: 45_000,
        severity_assessment: "above average"
      },
      pattern_detection: %{
        industry_pattern: "Construction sector safety violations",
        recurring_violation: "Work at height failures",
        similar_case_count: 8
      },
      layperson_summary:
        "A company was fined for not keeping workers safe on site. They failed to follow proper safety rules.",
      professional_summary:
        "Breach of HSWA 1974 Section 2(1). Failure to implement adequate risk controls for work at height activities.",
      auto_tags: ["workplace_safety", "construction", "fall_from_height", "section_2_breach"],
      confidence_scores: %{
        regulation_links: 0.92,
        benchmark_analysis: 0.78,
        pattern_detection: 0.65,
        summaries: 0.88,
        tags: 0.91
      }
    })
  end

  defp estimate_tokens(messages) when is_list(messages) do
    messages
    |> Enum.map(&get_message_content/1)
    |> Enum.join(" ")
    |> estimate_tokens()
  end

  defp estimate_tokens(text) when is_binary(text) do
    # Rough estimate: ~4 characters per token
    div(String.length(text), 4)
  end

  defp estimate_tokens(_), do: 0
end
