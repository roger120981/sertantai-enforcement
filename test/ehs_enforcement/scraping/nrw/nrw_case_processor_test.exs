defmodule EhsEnforcement.Scraping.Nrw.NrwCaseProcessorTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Nrw.NrwCaseProcessor
  alias EhsEnforcement.Scraping.Nrw.NrwCaseProcessor.ProcessedCase
  alias EhsEnforcement.Scraping.Nrw.NrwAiArticleParser.ParsedCase

  describe "process_case/1" do
    test "processes a basic individual case" do
      parsed_case = %ParsedCase{
        offender_name: "John Davies",
        offender_type: :individual,
        offender_location: "Llwyn Farm, Llandrindod Wells",
        hearing_date: ~D[2024-03-21],
        fine_amount: Decimal.new("2000"),
        costs_amount: Decimal.new("5000"),
        surcharge_amount: Decimal.new("800"),
        total_amount: Decimal.new("7800"),
        poca_amount: nil,
        offence_description: "Illegal tree felling",
        offence_result: "Fined £2,000 and ordered to replant",
        legislation: "Forestry Act 1967",
        article_url: "https://naturalresources.wales/test",
        article_title: "Farmer fined",
        article_date: ~D[2024-03-21]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      assert %ProcessedCase{} = processed
      assert processed.agency_code == :nrw
      assert processed.offender_attrs.name == "John Davies"
      assert processed.offender_attrs.address == "Llwyn Farm, Llandrindod Wells"
      assert processed.offender_attrs.country == "Wales"
      assert processed.offence_hearing_date == ~D[2024-03-21]
      assert Decimal.equal?(processed.offence_fine, Decimal.new("2000"))
      # Costs + surcharge combined
      assert Decimal.equal?(processed.offence_costs, Decimal.new("5800"))
      assert processed.offence_result == "Fined £2,000 and ordered to replant"
      assert processed.offence_breaches == "Forestry Act 1967"
      assert processed.url == "https://naturalresources.wales/test"
    end

    test "processes a company case" do
      parsed_case = %ParsedCase{
        offender_name: "Benji and Co Limited",
        offender_type: :company,
        offender_location: "Welshpool",
        hearing_date: ~D[2025-10-14],
        fine_amount: Decimal.new("40000"),
        costs_amount: Decimal.new("15000"),
        surcharge_amount: Decimal.new("2000"),
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Operating without permit",
        offence_result: "Fined £40,000",
        legislation: "Environmental Permitting Regulations 2016",
        article_url: "https://naturalresources.wales/test",
        article_title: "Company fined",
        article_date: ~D[2025-10-14]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      assert processed.offender_attrs.name == "Benji and Co Limited"
      assert processed.offender_attrs.country == "Wales"
      assert Decimal.equal?(processed.offence_fine, Decimal.new("40000"))
      # Costs + surcharge
      assert Decimal.equal?(processed.offence_costs, Decimal.new("17000"))
    end

    test "processes POCA confiscation case" do
      parsed_case = %ParsedCase{
        offender_name: "Thomas Jeffrey Lane",
        offender_type: :individual,
        offender_location: "Pontypool",
        hearing_date: ~D[2024-06-14],
        fine_amount: nil,
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: Decimal.new("78614"),
        offence_description: "Illegal tree felling for profit",
        offence_result: "POCA confiscation order",
        legislation: "Forestry Act 1967",
        article_url: "https://naturalresources.wales/test",
        article_title: "POCA case",
        article_date: ~D[2024-06-14]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      # POCA amount used as fine when no regular fine
      assert Decimal.equal?(processed.offence_fine, Decimal.new("78614"))
      assert is_nil(processed.offence_costs)
      assert processed.offence_action_type == "NRW POCA Confiscation"
    end

    test "handles case with only costs (no surcharge)" do
      parsed_case = %ParsedCase{
        offender_name: "Test Company Ltd",
        offender_type: :company,
        offender_location: nil,
        hearing_date: ~D[2024-01-01],
        fine_amount: Decimal.new("10000"),
        costs_amount: Decimal.new("5000"),
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-01-01]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      # Only costs, no surcharge
      assert Decimal.equal?(processed.offence_costs, Decimal.new("5000"))
    end

    test "handles case with only surcharge (no costs)" do
      parsed_case = %ParsedCase{
        offender_name: "Test Person",
        offender_type: :individual,
        offender_location: nil,
        hearing_date: ~D[2024-01-01],
        fine_amount: Decimal.new("500"),
        costs_amount: nil,
        surcharge_amount: Decimal.new("200"),
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-01-01]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      # Only surcharge
      assert Decimal.equal?(processed.offence_costs, Decimal.new("200"))
    end

    test "handles case with no costs or surcharge" do
      parsed_case = %ParsedCase{
        offender_name: "Test",
        offender_type: :individual,
        offender_location: nil,
        hearing_date: ~D[2024-01-01],
        fine_amount: Decimal.new("1000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-01-01]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      assert is_nil(processed.offence_costs)
    end

    test "handles unknown offender name" do
      parsed_case = %ParsedCase{
        offender_name: nil,
        offender_type: :unknown,
        offender_location: nil,
        hearing_date: ~D[2024-01-01],
        fine_amount: Decimal.new("1000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-01-01]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      assert processed.offender_attrs.name == "[Unknown]"
    end
  end

  describe "regulator_id generation" do
    test "generates deterministic regulator_id from hearing date and name" do
      parsed_case = %ParsedCase{
        offender_name: "John Davies",
        offender_type: :individual,
        offender_location: nil,
        hearing_date: ~D[2024-03-21],
        fine_amount: Decimal.new("2000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-03-21]
      }

      {:ok, processed1} = NrwCaseProcessor.process_case(parsed_case)
      {:ok, processed2} = NrwCaseProcessor.process_case(parsed_case)

      # Same input should produce same regulator_id
      assert processed1.regulator_id == processed2.regulator_id

      # Should have correct format
      assert String.starts_with?(processed1.regulator_id, "nrw_20240321_")
      assert String.length(processed1.regulator_id) == 21
    end

    test "uses article date when hearing date is nil" do
      parsed_case = %ParsedCase{
        offender_name: "Test Company",
        offender_type: :company,
        offender_location: nil,
        hearing_date: nil,
        fine_amount: Decimal.new("1000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-05-15]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      assert String.starts_with?(processed.regulator_id, "nrw_20240515_")
    end

    test "generates different regulator_ids for different offenders" do
      base_case = %ParsedCase{
        offender_name: "Company A",
        offender_type: :company,
        offender_location: nil,
        hearing_date: ~D[2024-03-21],
        fine_amount: Decimal.new("1000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-03-21]
      }

      {:ok, processed_a} = NrwCaseProcessor.process_case(base_case)

      {:ok, processed_b} =
        NrwCaseProcessor.process_case(%{base_case | offender_name: "Company B"})

      # Different names should produce different IDs (same date prefix)
      refute processed_a.regulator_id == processed_b.regulator_id
      assert String.slice(processed_a.regulator_id, 0, 12) == "nrw_20240321"
      assert String.slice(processed_b.regulator_id, 0, 12) == "nrw_20240321"
    end
  end

  describe "action type determination" do
    test "determines major prosecution for fine >= £100,000" do
      parsed_case = build_test_case(fine: 100_000)
      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)
      assert processed.offence_action_type == "NRW Prosecution (Major)"

      parsed_case2 = build_test_case(fine: 250_000)
      {:ok, processed2} = NrwCaseProcessor.process_case(parsed_case2)
      assert processed2.offence_action_type == "NRW Prosecution (Major)"
    end

    test "determines significant prosecution for fine >= £10,000" do
      parsed_case = build_test_case(fine: 10_000)
      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)
      assert processed.offence_action_type == "NRW Prosecution (Significant)"

      parsed_case2 = build_test_case(fine: 40_000)
      {:ok, processed2} = NrwCaseProcessor.process_case(parsed_case2)
      assert processed2.offence_action_type == "NRW Prosecution (Significant)"
    end

    test "determines standard prosecution for fine < £10,000" do
      parsed_case = build_test_case(fine: 2_000)
      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)
      assert processed.offence_action_type == "NRW Prosecution"

      parsed_case2 = build_test_case(fine: 500)
      {:ok, processed2} = NrwCaseProcessor.process_case(parsed_case2)
      assert processed2.offence_action_type == "NRW Prosecution"
    end

    test "determines POCA confiscation when only POCA amount present" do
      parsed_case = %ParsedCase{
        offender_name: "Test",
        offender_type: :individual,
        offender_location: nil,
        hearing_date: ~D[2024-01-01],
        fine_amount: nil,
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: Decimal.new("50000"),
        offence_description: "Test",
        offence_result: "POCA order",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-01-01]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)
      assert processed.offence_action_type == "NRW POCA Confiscation"
    end

    test "determines community order prosecution" do
      parsed_case = %ParsedCase{
        offender_name: "Test",
        offender_type: :individual,
        offender_location: nil,
        hearing_date: ~D[2024-01-01],
        fine_amount: nil,
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "12-month community order and 200 hours unpaid work",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-01-01]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)
      assert processed.offence_action_type == "NRW Prosecution (Community Order)"
    end
  end

  describe "process_cases/1" do
    test "processes multiple cases" do
      cases = [
        build_test_case(name: "Company A", fine: 10_000),
        build_test_case(name: "Company B", fine: 20_000),
        build_test_case(name: "Person C", fine: 5_000)
      ]

      {:ok, processed_list} = NrwCaseProcessor.process_cases(cases)

      assert length(processed_list) == 3
      assert Enum.all?(processed_list, &match?(%ProcessedCase{}, &1))

      names = Enum.map(processed_list, & &1.offender_attrs.name)
      assert "Company A" in names
      assert "Company B" in names
      assert "Person C" in names
    end

    test "handles empty list" do
      {:ok, processed_list} = NrwCaseProcessor.process_cases([])
      assert processed_list == []
    end
  end

  describe "source_metadata" do
    test "includes article metadata" do
      parsed_case = %ParsedCase{
        offender_name: "Test",
        offender_type: :individual,
        offender_location: nil,
        hearing_date: ~D[2024-03-21],
        fine_amount: Decimal.new("1000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://naturalresources.wales/test-article",
        article_title: "Test Article Title",
        article_date: ~D[2024-03-21]
      }

      {:ok, processed} = NrwCaseProcessor.process_case(parsed_case)

      assert processed.source_metadata.article_url ==
               "https://naturalresources.wales/test-article"

      assert processed.source_metadata.article_title == "Test Article Title"
      assert processed.source_metadata.article_date == ~D[2024-03-21]
      assert processed.source_metadata.source == "naturalresources.wales"
      assert processed.source_metadata.scraper_version == "1.0"
    end
  end

  describe "ProcessedCase struct" do
    test "can be created with all fields" do
      processed = %ProcessedCase{
        regulator_id: "nrw_20240321_abc12345",
        agency_code: :nrw,
        offender_attrs: %{name: "Test", address: nil, country: "Wales"},
        offence_hearing_date: ~D[2024-03-21],
        offence_action_date: ~D[2024-03-21],
        offence_fine: Decimal.new("1000"),
        offence_costs: Decimal.new("500"),
        offence_result: "Fined",
        offence_breaches: "Test Act",
        offence_action_type: "NRW Prosecution",
        url: "https://example.com",
        source_metadata: %{source: "test"}
      }

      assert processed.regulator_id == "nrw_20240321_abc12345"
      assert processed.agency_code == :nrw
    end

    test "can encode to JSON" do
      processed = %ProcessedCase{
        regulator_id: "nrw_20240321_abc12345",
        agency_code: :nrw,
        offender_attrs: %{name: "Test", address: nil, country: "Wales"},
        offence_hearing_date: ~D[2024-03-21],
        offence_action_date: ~D[2024-03-21],
        offence_fine: Decimal.new("1000"),
        offence_costs: nil,
        offence_result: "Fined",
        offence_breaches: "Test Act",
        offence_action_type: "NRW Prosecution",
        url: "https://example.com",
        source_metadata: %{source: "test"}
      }

      assert {:ok, json} = Jason.encode(processed)
      assert String.contains?(json, "nrw_20240321_abc12345")
      assert String.contains?(json, "NRW Prosecution")
    end
  end

  # Helper to build test cases with defaults

  defp build_test_case(opts \\ []) do
    %ParsedCase{
      offender_name: Keyword.get(opts, :name, "Test Offender"),
      offender_type: Keyword.get(opts, :type, :company),
      offender_location: Keyword.get(opts, :location, nil),
      hearing_date: Keyword.get(opts, :hearing_date, ~D[2024-03-21]),
      fine_amount: opts |> Keyword.get(:fine, 1000) |> then(&Decimal.new(&1)),
      costs_amount: Keyword.get(opts, :costs) |> maybe_decimal(),
      surcharge_amount: Keyword.get(opts, :surcharge) |> maybe_decimal(),
      total_amount: nil,
      poca_amount: Keyword.get(opts, :poca) |> maybe_decimal(),
      offence_description: Keyword.get(opts, :description, "Test offence"),
      offence_result: Keyword.get(opts, :result, "Fined"),
      legislation: Keyword.get(opts, :legislation, "Test Act"),
      article_url: "https://example.com",
      article_title: "Test",
      article_date: ~D[2024-03-21]
    }
  end

  defp maybe_decimal(nil), do: nil
  defp maybe_decimal(value), do: Decimal.new(value)
end
