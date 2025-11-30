defmodule EhsEnforcement.Scraping.Nrw.IntegrationTest do
  @moduledoc """
  Integration tests for NRW case scraping.

  Tests the full pipeline from scraped/parsed data to database persistence,
  verifying that all tables (cases, offenders) are properly populated.
  """
  use EhsEnforcement.DataCase, async: false

  require Ash.Query

  alias EhsEnforcement.Enforcement.{Case, Offender, Agency}
  alias EhsEnforcement.Scraping.Nrw.NrwAiArticleParser.ParsedCase
  alias EhsEnforcement.Scraping.Nrw.NrwCaseProcessor

  setup do
    # Create NRW agency for tests
    {:ok, agency} =
      Ash.create(Agency, %{
        name: "Natural Resources Wales",
        code: :nrw,
        base_url: "https://naturalresources.wales"
      })

    %{agency: agency}
  end

  describe "process_and_create_case/2" do
    test "creates case in database", %{agency: agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Integration Test Ltd",
          offender_location: "Cardiff, CF10 1AA",
          fine_amount: Decimal.new("10000")
        })

      assert {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Verify case was persisted
      assert {:ok, [db_case]} =
               Case
               |> Ash.Query.filter(id == ^case_record.id)
               |> Ash.read()

      assert db_case.agency_id == agency.id
      assert Decimal.equal?(db_case.offence_fine, Decimal.new("10000"))
      assert String.starts_with?(db_case.regulator_id, "nrw_")
    end

    test "creates offender in database", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "New Offender Company Ltd",
          offender_location: "Swansea, SA1 1AB"
        })

      assert {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Verify offender was created
      assert {:ok, [offender]} =
               Offender
               |> Ash.Query.filter(id == ^case_record.offender_id)
               |> Ash.read()

      assert offender.name == "New Offender Company Ltd"
      assert offender.country == "Wales"
      assert offender.address == "Swansea, SA1 1AB"
    end

    test "reuses existing offender with same name", %{agency: _agency} do
      # Create first case for this offender
      parsed1 =
        build_parsed_case(%{
          offender_name: "Repeat Offender Ltd",
          offender_location: "Newport, NP10 1CD",
          hearing_date: ~D[2024-03-15],
          fine_amount: Decimal.new("5000")
        })

      {:ok, case1} = NrwCaseProcessor.process_and_create_case(parsed1, nil)

      # Create second case for same offender (different date)
      parsed2 =
        build_parsed_case(%{
          offender_name: "Repeat Offender Ltd",
          offender_location: "Newport, NP10 1CD",
          hearing_date: ~D[2024-04-20],
          fine_amount: Decimal.new("3000")
        })

      {:ok, case2} = NrwCaseProcessor.process_and_create_case(parsed2, nil)

      # Should use same offender
      assert case1.offender_id == case2.offender_id

      # Verify only one offender exists with this name
      {:ok, offenders} =
        Offender
        |> Ash.Query.filter(name == "Repeat Offender Ltd")
        |> Ash.read()

      assert length(offenders) == 1
    end

    test "prevents duplicate cases via regulator_id", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Duplicate Test Ltd",
          hearing_date: ~D[2024-03-15],
          fine_amount: Decimal.new("10000")
        })

      # First creation should succeed
      {:ok, case1} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Second creation with same data should fail (duplicate regulator_id)
      result = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Should get an error due to unique constraint
      assert match?({:error, _}, result)

      # Verify only one case exists
      {:ok, cases} =
        Case
        |> Ash.Query.filter(regulator_id == ^case1.regulator_id)
        |> Ash.read()

      assert length(cases) == 1
    end

    test "stores fine_amount correctly for different amounts", %{agency: _agency} do
      test_cases = [
        {"2000", Decimal.new("2000")},
        {"10000", Decimal.new("10000")},
        {"250000", Decimal.new("250000")},
        {"500.50", Decimal.new("500.50")}
      ]

      for {{amount_str, expected_amount}, index} <- Enum.with_index(test_cases) do
        parsed =
          build_parsed_case(%{
            offender_name: "Amount Test #{index} Ltd",
            hearing_date: Date.add(~D[2024-03-10], index),
            fine_amount: Decimal.new(amount_str)
          })

        {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

        assert Decimal.equal?(case_record.offence_fine, expected_amount)
      end
    end

    test "combines costs and surcharge into offence_costs", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Costs Test Ltd",
          fine_amount: Decimal.new("5000"),
          costs_amount: Decimal.new("3000"),
          surcharge_amount: Decimal.new("500")
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Costs should be combined
      assert Decimal.equal?(case_record.offence_costs, Decimal.new("3500"))
    end

    test "stores POCA amount as fine when no regular fine", %{agency: _agency} do
      parsed = %ParsedCase{
        offender_name: "POCA Test",
        offender_type: :individual,
        offender_location: "Pontypool",
        hearing_date: ~D[2024-06-14],
        fine_amount: nil,
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: Decimal.new("78614"),
        offence_description: "Illegal tree felling",
        offence_result: "POCA confiscation order",
        legislation: "Forestry Act 1967",
        article_url: "https://naturalresources.wales/test",
        article_title: "POCA Case",
        article_date: ~D[2024-06-14]
      }

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert Decimal.equal?(case_record.offence_fine, Decimal.new("78614"))
      assert case_record.offence_action_type == "NRW POCA Confiscation"
    end

    test "stores legislation in offence_breaches", %{agency: _agency} do
      legislation = "Environmental Permitting (England and Wales) Regulations 2016"

      parsed =
        build_parsed_case(%{
          offender_name: "Legislation Test Ltd",
          legislation: legislation
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert case_record.offence_breaches == legislation
    end

    test "stores article URL in url field", %{agency: _agency} do
      article_url = "https://naturalresources.wales/news/test-article/?lang=en"

      parsed =
        build_parsed_case(%{
          offender_name: "URL Test Ltd",
          article_url: article_url
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert case_record.url == article_url
    end
  end

  describe "offender data integrity" do
    test "all offenders get Wales as country", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Welsh Company",
          offender_location: "Aberystwyth"
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      {:ok, [offender]} =
        Offender
        |> Ash.Query.filter(id == ^case_record.offender_id)
        |> Ash.read()

      assert offender.country == "Wales"
    end

    test "stores offender location in address field", %{agency: _agency} do
      location = "Llwyn Farm, Llandrindod Wells, Powys"

      parsed =
        build_parsed_case(%{
          offender_name: "Address Test Person",
          offender_location: location
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      {:ok, [offender]} =
        Offender
        |> Ash.Query.filter(id == ^case_record.offender_id)
        |> Ash.read()

      assert offender.address == location
    end

    test "handles nil location", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "No Location Company",
          offender_location: nil
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      {:ok, [offender]} =
        Offender
        |> Ash.Query.filter(id == ^case_record.offender_id)
        |> Ash.read()

      assert offender.name == "No Location Company"
      assert is_nil(offender.address)
    end
  end

  describe "case-agency relationship" do
    test "case is associated with NRW agency", %{agency: agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Agency Test Ltd"
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Load agency relationship
      {:ok, case_with_agency} = Ash.load(case_record, :agency)

      assert case_with_agency.agency.id == agency.id
      assert case_with_agency.agency.code == :nrw
      assert case_with_agency.agency.name == "Natural Resources Wales"
    end
  end

  describe "date handling" do
    test "stores hearing date correctly", %{agency: _agency} do
      test_cases = [
        ~D[2024-03-21],
        ~D[2025-01-09],
        ~D[2024-12-31],
        ~D[2025-06-14]
      ]

      for {date, index} <- Enum.with_index(test_cases) do
        parsed =
          build_parsed_case(%{
            offender_name: "Date Test #{index}",
            hearing_date: date
          })

        {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

        assert case_record.offence_hearing_date == date,
               "Expected #{date}, got #{case_record.offence_hearing_date}"
      end
    end

    test "does not use article date as action date (article published after court)", %{
      agency: _agency
    } do
      # Article date is when NRW published the news (AFTER the court case),
      # so it should NOT be used as offence_action_date.
      # Action date is set to nil for NRW court cases since we don't know
      # when the offence originally occurred.
      article_date = ~D[2024-03-21]

      parsed =
        build_parsed_case(%{
          offender_name: "Action Date Test",
          article_date: article_date
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert case_record.offence_action_date == nil
    end
  end

  describe "action type determination" do
    test "classifies major prosecution for large fines", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Major Fine Company",
          fine_amount: Decimal.new("250000")
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert case_record.offence_action_type == "NRW Prosecution (Major)"
    end

    test "classifies significant prosecution for medium fines", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Significant Fine Company",
          fine_amount: Decimal.new("40000")
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert case_record.offence_action_type == "NRW Prosecution (Significant)"
    end

    test "classifies standard prosecution for small fines", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Small Fine Person",
          fine_amount: Decimal.new("2000")
        })

      {:ok, case_record} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      assert case_record.offence_action_type == "NRW Prosecution"
    end
  end

  describe "regulator_id generation" do
    test "generates deterministic regulator_id", %{agency: _agency} do
      parsed =
        build_parsed_case(%{
          offender_name: "Deterministic Test Ltd",
          hearing_date: ~D[2024-03-21]
        })

      {:ok, case1} = NrwCaseProcessor.process_and_create_case(parsed, nil)

      # Same input should produce same regulator_id
      # (second creation will fail due to unique constraint, but we can check format)
      assert String.starts_with?(case1.regulator_id, "nrw_20240321_")
      assert String.length(case1.regulator_id) == 21
    end
  end

  # Helper function to build a parsed case with defaults
  # Note: article_date (action date) must be <= hearing_date due to DB constraint
  defp build_parsed_case(overrides \\ %{}) do
    # Get hearing_date from overrides or use default
    hearing_date = Map.get(overrides, :hearing_date, ~D[2024-03-21])
    # Article date defaults to 7 days before hearing (respects constraint)
    article_date = Map.get(overrides, :article_date, Date.add(hearing_date, -7))

    defaults = %{
      offender_name: "Default Company Ltd",
      offender_type: :company,
      offender_location: "Cardiff, CF10 1AA",
      hearing_date: hearing_date,
      fine_amount: Decimal.new("10000"),
      costs_amount: nil,
      surcharge_amount: nil,
      total_amount: nil,
      poca_amount: nil,
      offence_description: "Operating without permit",
      offence_result: "Fined",
      legislation: "Environmental Permitting Regulations 2016",
      article_url: "https://naturalresources.wales/test-article",
      article_title: "Test Article",
      article_date: article_date
    }

    struct(ParsedCase, Map.merge(defaults, overrides))
  end
end
