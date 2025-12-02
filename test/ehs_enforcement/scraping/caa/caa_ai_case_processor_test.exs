defmodule EhsEnforcement.Scraping.Caa.CaaAiCaseProcessorTest do
  @moduledoc """
  Unit tests for CaaAiCaseProcessor module.

  Tests the processing of AI-parsed prosecution data into Ash database records.
  """
  use EhsEnforcement.DataCase, async: false

  require Ash.Query

  alias EhsEnforcement.Scraping.Caa.CaaAiCaseProcessor
  alias EhsEnforcement.Scraping.Caa.CaaAiPdfParser.ParsedProsecution

  describe "generate_regulator_id/1" do
    test "generates deterministic ID from parsed prosecution" do
      parsed = %ParsedProsecution{
        defendant_name: "John Smith",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-10-15]
      }

      result = CaaAiCaseProcessor.generate_regulator_id(parsed)

      assert result == "caa_ai_20212022_john_smith_20211015"
    end

    test "handles nil fiscal year" do
      parsed = %ParsedProsecution{
        defendant_name: "Test Company Ltd",
        fiscal_year: nil,
        hearing_date: ~D[2020-05-01]
      }

      result = CaaAiCaseProcessor.generate_regulator_id(parsed)

      assert result == "caa_ai_unknown_test_company_ltd_20200501"
    end

    test "handles nil hearing date" do
      parsed = %ParsedProsecution{
        defendant_name: "Jane Doe",
        fiscal_year: "2019-2020",
        hearing_date: nil
      }

      result = CaaAiCaseProcessor.generate_regulator_id(parsed)

      assert result == "caa_ai_20192020_jane_doe_00000000"
    end

    test "handles nil defendant name" do
      parsed = %ParsedProsecution{
        defendant_name: nil,
        fiscal_year: "2020-2021",
        hearing_date: ~D[2020-06-15]
      }

      result = CaaAiCaseProcessor.generate_regulator_id(parsed)

      assert result == "caa_ai_20202021_unknown_20200615"
    end

    test "sanitizes special characters in defendant name" do
      parsed = %ParsedProsecution{
        defendant_name: "O'Brien & Sons (UK) Ltd.",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-11-20]
      }

      result = CaaAiCaseProcessor.generate_regulator_id(parsed)

      assert result == "caa_ai_20212022_o_brien_sons_uk_ltd_20211120"
    end

    test "truncates very long defendant names" do
      long_name = String.duplicate("A", 100)

      parsed = %ParsedProsecution{
        defendant_name: long_name,
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-12-01]
      }

      result = CaaAiCaseProcessor.generate_regulator_id(parsed)

      # Should truncate defendant part to 40 chars
      assert String.length(result) <= 80
      assert String.starts_with?(result, "caa_ai_20212022_")
    end
  end

  describe "process_and_create_case/2" do
    setup do
      # Ensure CAA agency exists
      {:ok, agency} =
        EhsEnforcement.Enforcement.Agency
        |> Ash.Changeset.for_create(:create, %{
          code: :caa,
          name: "Civil Aviation Authority"
        })
        |> Ash.create()

      %{agency: agency}
    end

    test "creates case with valid parsed prosecution", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "Test Pilot Ltd",
        defendant_type: "Company",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-09-15],
        court_name: "Westminster Magistrates' Court",
        fine_amount: Decimal.new("5000"),
        offence_description: "Operating without valid licence",
        offence_outcome: "Guilty",
        legislation: ["Air Navigation Order 2016"]
      }

      result = CaaAiCaseProcessor.process_and_create_case(parsed)

      assert {:ok, case_record} = result
      assert case_record.regulator_id == "caa_ai_20212022_test_pilot_ltd_20210915"
      assert case_record.offence_fine == Decimal.new("5000")
      assert case_record.offence_action_type == "CAA Prosecution"
    end

    test "detects duplicate case on second creation", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "Duplicate Test Ltd",
        defendant_type: "Company",
        fiscal_year: "2020-2021",
        hearing_date: ~D[2020-07-20],
        court_name: "City of London Magistrates",
        fine_amount: Decimal.new("2500"),
        offence_description: "Unlicensed drone operation"
      }

      # First creation should succeed
      {:ok, _case_record} = CaaAiCaseProcessor.process_and_create_case(parsed)

      # Second creation should detect duplicate
      result = CaaAiCaseProcessor.process_and_create_case(parsed)

      assert {:ok, :duplicate} = result
    end

    test "creates offender for new defendant", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "New Offender Test Ltd",
        defendant_type: "Company",
        fiscal_year: "2019-2020",
        hearing_date: ~D[2019-12-10],
        court_name: "Southampton Magistrates",
        fine_amount: Decimal.new("1000")
      }

      {:ok, case_record} = CaaAiCaseProcessor.process_and_create_case(parsed)

      # Verify offender was created
      assert case_record.offender_id != nil

      {:ok, offender} =
        EhsEnforcement.Enforcement.Offender
        |> Ash.get(case_record.offender_id)

      assert offender.name == "New Offender Test Ltd"
      assert offender.country == "United Kingdom"
    end

    test "handles individual defendant", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "James Wilson",
        defendant_type: "Individual",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2022-01-05],
        court_name: "Manchester Crown Court",
        imprisonment_months: 6,
        suspended_months: 12,
        offence_description: "Reckless endangerment of aircraft"
      }

      {:ok, case_record} = CaaAiCaseProcessor.process_and_create_case(parsed)

      assert case_record.regulator_id =~ "james_wilson"
      assert case_record.offence_result =~ "Reckless endangerment"
      assert case_record.offence_result =~ "6 months imprisonment"
      assert case_record.offence_result =~ "suspended for 12 months"
    end
  end

  describe "process_prosecutions/2" do
    setup do
      # Ensure CAA agency exists
      {:ok, agency} =
        EhsEnforcement.Enforcement.Agency
        |> Ash.Changeset.for_create(:create, %{
          code: :caa,
          name: "Civil Aviation Authority"
        })
        |> Ash.create()

      %{agency: agency}
    end

    test "processes multiple prosecutions with mixed results", %{agency: _agency} do
      prosecutions = [
        %ParsedProsecution{
          defendant_name: "Batch Test One Ltd",
          fiscal_year: "2021-2022",
          hearing_date: ~D[2021-08-10],
          fine_amount: Decimal.new("3000")
        },
        %ParsedProsecution{
          defendant_name: "Batch Test Two Ltd",
          fiscal_year: "2021-2022",
          hearing_date: ~D[2021-09-15],
          fine_amount: Decimal.new("4000")
        }
      ]

      {:ok, results} = CaaAiCaseProcessor.process_prosecutions(prosecutions)

      assert length(results.created) == 2
      assert length(results.duplicates) == 0
      assert length(results.errors) == 0
    end

    test "returns empty results for empty list" do
      {:ok, results} = CaaAiCaseProcessor.process_prosecutions([])

      assert results.created == []
      assert results.duplicates == []
      assert results.errors == []
    end

    test "tracks duplicates in batch processing", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "Batch Duplicate Ltd",
        fiscal_year: "2020-2021",
        hearing_date: ~D[2020-11-01],
        fine_amount: Decimal.new("2000")
      }

      # Create the first one
      {:ok, _case} = CaaAiCaseProcessor.process_and_create_case(parsed)

      # Process batch with the same prosecution
      {:ok, results} = CaaAiCaseProcessor.process_prosecutions([parsed])

      assert length(results.created) == 0
      assert length(results.duplicates) == 1
    end
  end

  describe "offence result building" do
    setup do
      {:ok, agency} =
        EhsEnforcement.Enforcement.Agency
        |> Ash.Changeset.for_create(:create, %{
          code: :caa,
          name: "Civil Aviation Authority"
        })
        |> Ash.create()

      %{agency: agency}
    end

    test "builds offence result with fine", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "Fine Only Ltd",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-06-01],
        fine_amount: Decimal.new("7500"),
        offence_description: "Breach of air navigation regulations"
      }

      {:ok, case_record} = CaaAiCaseProcessor.process_and_create_case(parsed)

      assert case_record.offence_result =~ "Breach of air navigation regulations"
      assert case_record.offence_result =~ "Fine £7500"
    end

    test "builds offence result with community order", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "Community Order Person",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-07-15],
        community_order_months: 18,
        unpaid_work_hours: 200,
        offence_description: "Drone offence"
      }

      {:ok, case_record} = CaaAiCaseProcessor.process_and_create_case(parsed)

      assert case_record.offence_result =~ "Community order 18 months"
      assert case_record.offence_result =~ "200 hours unpaid work"
    end

    test "builds offence breaches with court and legislation", %{agency: _agency} do
      parsed = %ParsedProsecution{
        defendant_name: "Legislation Test Ltd",
        fiscal_year: "2021-2022",
        hearing_date: ~D[2021-05-20],
        court_name: "Southwark Crown Court",
        legislation: ["Air Navigation Order 2016", "Civil Aviation Act 1982"]
      }

      {:ok, case_record} = CaaAiCaseProcessor.process_and_create_case(parsed)

      assert case_record.offence_breaches =~ "Court: Southwark Crown Court"
      assert case_record.offence_breaches =~ "Legislation: Air Navigation Order 2016"
      assert case_record.offence_breaches =~ "Civil Aviation Act 1982"
    end
  end
end
