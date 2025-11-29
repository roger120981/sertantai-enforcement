defmodule EhsEnforcement.AI.EnrichmentServiceTest do
  @moduledoc """
  Tests for the AI Enrichment Service.

  Uses the mock AI client to test enrichment generation and persistence
  without making actual API calls.
  """

  use EhsEnforcement.DataCase, async: true

  alias EhsEnforcement.AI.EnrichmentService
  alias EhsEnforcement.AI.Client.Mock, as: MockClient
  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.{Case, Notice, Enrichment}

  require Ash.Query
  import Ash.Expr

  # Test fixtures
  @valid_enrichment_json Jason.encode!(%{
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
                             "A company was fined for not keeping workers safe on site.",
                           professional_summary:
                             "Breach of HSWA 1974 Section 2(1). Failure to implement adequate risk controls.",
                           auto_tags: [
                             "workplace_safety",
                             "construction",
                             "fall_from_height"
                           ],
                           confidence_scores: %{
                             regulation_links: 0.92,
                             benchmark_analysis: 0.78,
                             pattern_detection: 0.65,
                             summaries: 0.88,
                             tags: 0.91
                           }
                         })

  setup do
    # Get or create agency - handle both nil and NotFound error cases
    {:ok, agency} =
      case Enforcement.get_agency_by_code(:hse) do
        {:ok, nil} ->
          Ash.create(Enforcement.Agency, %{code: :hse, name: "Health and Safety Executive"},
            domain: Enforcement
          )

        {:ok, agency} ->
          {:ok, agency}

        {:error, %Ash.Error.Invalid{}} ->
          # Agency not found, create it
          Ash.create(Enforcement.Agency, %{code: :hse, name: "Health and Safety Executive"},
            domain: Enforcement
          )
      end

    # Create test offender
    unique_id = System.unique_integer([:positive])

    {:ok, offender} =
      Ash.create(
        Enforcement.Offender,
        %{
          name: "Test Company #{unique_id}",
          business_type: :limited_company
        },
        domain: Enforcement
      )

    # Create test case
    {:ok, test_case} =
      Ash.create(
        Case,
        %{
          regulator_id: "TEST-CASE-#{unique_id}",
          offence_result: "Guilty - Fine imposed",
          offence_fine: Decimal.new("50000"),
          offence_costs: Decimal.new("5000"),
          offence_action_date: ~D[2024-06-15],
          offence_hearing_date: ~D[2024-07-20],
          offence_action_type: "Court Case",
          offence_breaches: "Failed to ensure safety of employees working at height",
          agency_id: agency.id,
          offender_id: offender.id
        },
        domain: Enforcement
      )

    # Create test notice
    {:ok, test_notice} =
      Ash.create(
        Notice,
        %{
          regulator_id: "TEST-NOTICE-#{unique_id}",
          notice_date: ~D[2024-05-01],
          operative_date: ~D[2024-05-08],
          compliance_date: ~D[2024-06-01],
          offence_action_type: "Improvement Notice",
          notice_body: "Improve workplace safety measures for work at height",
          offence_breaches: "Inadequate edge protection on scaffolding",
          agency_id: agency.id,
          offender_id: offender.id
        },
        domain: Enforcement
      )

    # Load offender relationship
    {:ok, test_case} = Ash.load(test_case, :offender, domain: Enforcement)
    {:ok, test_notice} = Ash.load(test_notice, :offender, domain: Enforcement)

    %{
      agency: agency,
      offender: offender,
      test_case: test_case,
      test_notice: test_notice
    }
  end

  describe "health_check/0" do
    test "returns ok with mock client" do
      assert {:ok, %{status: :available, provider: :mock}} = EnrichmentService.health_check()
    end
  end

  describe "enrich_case/2" do
    test "generates enrichment for a case", %{test_case: test_case} do
      # Use custom mock response
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      assert {:ok, enrichment} = EnrichmentService.enrich_case(test_case)

      # Verify enrichment was created
      assert enrichment.id != nil
      assert enrichment.case_id == test_case.id
      assert enrichment.notice_id == nil

      # Verify content
      assert enrichment.model_version == "mock-model-v1"
      assert enrichment.layperson_summary =~ "company was fined"
      assert enrichment.professional_summary =~ "HSWA 1974"
      assert "workplace_safety" in enrichment.auto_tags
      assert enrichment.confidence_scores["regulation_links"] == 0.92
    after
      Process.delete(:ai_mock_response)
    end

    test "saves enrichment to database by default", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment} = EnrichmentService.enrich_case(test_case)

      # Verify it's persisted
      {:ok, found} = Enforcement.get_enrichment_by_case(test_case.id)
      assert found.id == enrichment.id
    after
      Process.delete(:ai_mock_response)
    end

    test "does not save when save: false option provided", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment_data} = EnrichmentService.enrich_case(test_case, save: false)

      # Should return data but not persist
      assert enrichment_data.case_id == test_case.id
      assert enrichment_data.layperson_summary =~ "company was fined"

      # Verify not saved to database (returns error or nil)
      result = Enforcement.get_enrichment_by_case(test_case.id)
      assert result == {:ok, nil} or match?({:error, %Ash.Error.Invalid{}}, result)
    after
      Process.delete(:ai_mock_response)
    end

    test "handles AI client errors gracefully", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:error, {:http_error, 500, "Server error"}})

      assert {:error, {:http_error, 500, "Server error"}} =
               EnrichmentService.enrich_case(test_case)
    after
      Process.delete(:ai_mock_response)
    end

    test "tracks processing time", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment} = EnrichmentService.enrich_case(test_case)

      # processing_time_ms is tracked (may be 0 with fast mock responses)
      assert enrichment.processing_time_ms >= 0
    after
      Process.delete(:ai_mock_response)
    end
  end

  describe "enrich_notice/2" do
    test "generates enrichment for a notice", %{test_notice: test_notice} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      assert {:ok, enrichment} = EnrichmentService.enrich_notice(test_notice)

      # Verify enrichment was created
      assert enrichment.id != nil
      assert enrichment.notice_id == test_notice.id
      assert enrichment.case_id == nil

      # Verify content
      assert enrichment.model_version == "mock-model-v1"
      assert enrichment.layperson_summary =~ "company was fined"
    after
      Process.delete(:ai_mock_response)
    end

    test "saves enrichment to database by default", %{test_notice: test_notice} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment} = EnrichmentService.enrich_notice(test_notice)

      # Verify it's persisted
      {:ok, found} = Enforcement.get_enrichment_by_notice(test_notice.id)
      assert found.id == enrichment.id
    after
      Process.delete(:ai_mock_response)
    end

    test "does not save when save: false option provided", %{test_notice: test_notice} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment_data} = EnrichmentService.enrich_notice(test_notice, save: false)

      # Should return data but not persist
      assert enrichment_data.notice_id == test_notice.id

      # Verify not saved to database (returns error or nil)
      result = Enforcement.get_enrichment_by_notice(test_notice.id)
      assert result == {:ok, nil} or match?({:error, %Ash.Error.Invalid{}}, result)
    after
      Process.delete(:ai_mock_response)
    end
  end

  describe "generate_enrichment/1" do
    test "works with Case struct", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment_data} = EnrichmentService.generate_enrichment(test_case)

      assert enrichment_data.case_id == test_case.id
      # Should not be saved (generate_enrichment doesn't save)
      result = Enforcement.get_enrichment_by_case(test_case.id)
      assert result == {:ok, nil} or match?({:error, %Ash.Error.Invalid{}}, result)
    after
      Process.delete(:ai_mock_response)
    end

    test "works with Notice struct", %{test_notice: test_notice} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment_data} = EnrichmentService.generate_enrichment(test_notice)

      assert enrichment_data.notice_id == test_notice.id
      # Should not be saved (returns error or nil)
      result = Enforcement.get_enrichment_by_notice(test_notice.id)
      assert result == {:ok, nil} or match?({:error, %Ash.Error.Invalid{}}, result)
    after
      Process.delete(:ai_mock_response)
    end
  end

  describe "JSON parsing" do
    test "handles malformed JSON response", %{test_case: test_case} do
      Process.put(
        :ai_mock_response,
        {:ok,
         %{
           content: "This is not valid JSON",
           model: "test-model",
           usage: %{prompt_tokens: 100, completion_tokens: 50, total_tokens: 150},
           latency_ms: 100
         }}
      )

      assert {:error, {:json_parse_error, _}} = EnrichmentService.enrich_case(test_case)
    after
      Process.delete(:ai_mock_response)
    end
  end

  describe "enrichment content validation" do
    test "parses regulation links correctly", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment} = EnrichmentService.enrich_case(test_case)

      # regulation_links is flattened to array with type field
      assert is_list(enrichment.regulation_links)
      primary = Enum.find(enrichment.regulation_links, &(&1["type"] == "primary"))
      assert primary["title"] == "Health and Safety at Work Act 1974"
      assert primary["section"] == "Section 2(1)"
    after
      Process.delete(:ai_mock_response)
    end

    test "parses benchmark analysis correctly", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment} = EnrichmentService.enrich_case(test_case)

      assert enrichment.benchmark_analysis["fine_percentile"] == 65
      assert enrichment.benchmark_analysis["similar_cases_count"] == 23
      assert enrichment.benchmark_analysis["severity_assessment"] == "above average"
    after
      Process.delete(:ai_mock_response)
    end

    test "parses pattern detection correctly", %{test_case: test_case} do
      Process.put(:ai_mock_response, {:ok, mock_ai_response(@valid_enrichment_json)})

      {:ok, enrichment} = EnrichmentService.enrich_case(test_case)

      assert enrichment.pattern_detection["industry_pattern"] =~ "Construction"
      assert enrichment.pattern_detection["recurring_violation"] =~ "height"
    after
      Process.delete(:ai_mock_response)
    end
  end

  # Helper to create mock AI response
  defp mock_ai_response(json_content) do
    %{
      content: json_content,
      model: "mock-model-v1",
      usage: %{
        prompt_tokens: 500,
        completion_tokens: 800,
        total_tokens: 1300
      },
      latency_ms: 150
    }
  end
end
