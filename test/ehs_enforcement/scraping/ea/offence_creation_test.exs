defmodule EhsEnforcement.Scraping.Ea.OffenceCreationTest do
  use EhsEnforcement.DataCase

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Scraping.Ea.CaseProcessor
  alias EhsEnforcement.Scraping.Ea.CaseScraper.EaDetailRecord

  setup do
    # Create test agency
    {:ok, agency} =
      Enforcement.create_agency(%{
        name: "Environment Agency",
        code: :ea,
        base_url: "https://environment.data.gov.uk"
      })

    %{agency: agency}
  end

  describe "create_case_violations/3 with single offence" do
    test "creates offence from EA detail record", %{agency: agency} do
      # Create case first
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "Test Environmental Company Ltd"},
          regulator_id: "EA001",
          offence_action_date: ~D[2023-01-15]
        })

      violations_data = [
        %{
          offence_description:
            "Environmental Permitting (england and Wales) Regulations 2016, Regulation 38(1)",
          legislation_part: "Regulation 38(1)",
          fine: Decimal.new("10000.00"),
          sequence_number: 1,
          legal_act: "Environmental Permitting (england and Wales) Regulations 2016",
          legal_section: "Regulation 38(1)"
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      # Verify offence was created
      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert length(offences) == 1

      offence = List.first(offences)
      assert offence.case_id == case_record.id
      assert offence.legislation_part == "Regulation 38(1)"
      assert Decimal.equal?(offence.fine, Decimal.new("10000.00"))
      assert offence.sequence_number == 1

      # Verify legislation was created and linked
      assert offence.legislation_id != nil
      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)

      assert legislation.legislation_title ==
               "Environmental Permitting (england and Wales) Regulations 2016"

      assert legislation.legislation_year == 2016
      assert legislation.legislation_type == :regulation
    end

    test "handles EA case with offence description and fine", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA002"
        })

      violations_data = [
        %{
          offence_description: "Water Resources Act 1991, Section 85(1)",
          legislation_part: "Section 85(1)",
          fine: Decimal.new("5000.00"),
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      assert offence.offence_description == "Water Resources Act 1991, Section 85(1)"
      assert Decimal.equal?(offence.fine, Decimal.new("5000.00"))
    end

    test "creates legislation from legal_act and legal_section fallback", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA003"
        })

      violations_data = [
        %{
          legislation_part: "Section 85(3)",
          fine: Decimal.new("8000.00"),
          sequence_number: 1,
          legal_act: "Water Resources Act 1991",
          legal_section: "Section 85(3)"
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      assert offence.legislation_id != nil

      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)
      assert legislation.legislation_title == "Water Resources Act 1991"
      assert legislation.legislation_year == 1991
    end
  end

  describe "create_case_violations/3 with no violations" do
    test "handles empty violations list gracefully", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA004"
        })

      assert {:ok, []} = CaseProcessor.create_case_violations(case_record, [])

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert offences == []
    end

    test "handles nil violations gracefully", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA005"
        })

      assert {:ok, []} = CaseProcessor.create_case_violations(case_record, nil)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert offences == []
    end
  end

  describe "process_and_create_case/2 integration" do
    test "creates case with offence from EA detail record", %{agency: agency} do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_INTEGRATION_001",
        offender_name: "Integration Test Environmental Ltd",
        action_date: ~D[2023-01-15],
        action_type: "Court Case",
        offence_description:
          "Environmental Permitting (england and Wales) Regulations 2016, Regulation 38(1)",
        act: "Environmental Permitting (england and Wales) Regulations 2016",
        section: "Regulation 38(1)",
        total_fine: Decimal.new("15000.00"),
        company_registration_number: "12345678",
        address: "123 Test Street",
        town: "London",
        postcode: "SW1A 1AA",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_INTEGRATION_001"
      }

      assert {:ok, case_record} = CaseProcessor.process_and_create_case(ea_detail)

      # Verify case was created
      assert case_record.regulator_id == "EA_INTEGRATION_001"

      # Verify offence was created
      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert length(offences) == 1

      offence = List.first(offences)
      assert offence.legislation_part == "Regulation 38(1)"
      assert Decimal.equal?(offence.fine, Decimal.new("15000.00"))

      # Verify legislation was created
      assert offence.legislation_id != nil
      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)

      assert legislation.legislation_title ==
               "Environmental Permitting (england and Wales) Regulations 2016"

      assert legislation.legislation_year == 2016
    end

    test "handles EA case with minimal offence information", %{agency: agency} do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_INTEGRATION_002",
        offender_name: "Minimal Info Company Ltd",
        action_date: ~D[2023-02-20],
        action_type: "Caution",
        act: "Water Resources Act 1991",
        section: "Section 85",
        total_fine: nil,
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_INTEGRATION_002"
      }

      assert {:ok, case_record} = CaseProcessor.process_and_create_case(ea_detail)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert length(offences) == 1

      offence = List.first(offences)
      # Should still create offence even without fine
      assert offence.fine == nil
      assert offence.legislation_id != nil
    end

    test "handles EA case without any offence information", %{agency: agency} do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_INTEGRATION_003",
        offender_name: "No Offence Info Company Ltd",
        action_date: ~D[2023-03-10],
        action_type: "Enforcement Notice",
        act: nil,
        section: nil,
        offence_description: nil,
        total_fine: nil,
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_INTEGRATION_003"
      }

      assert {:ok, case_record} = CaseProcessor.process_and_create_case(ea_detail)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      # Should create case successfully, just with no offences
      assert offences == []
    end
  end

  describe "legislation reuse across multiple EA cases" do
    test "reuses legislation for multiple cases with same Act", %{agency: agency} do
      # Create first case
      ea_detail_1 = %EaDetailRecord{
        ea_record_id: "EA_REUSE_001",
        offender_name: "First Company Ltd",
        action_date: ~D[2023-01-15],
        action_type: "Court Case",
        act: "Environmental Permitting (england and Wales) Regulations 2016",
        section: "Regulation 38(1)",
        total_fine: Decimal.new("5000.00"),
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_REUSE_001"
      }

      assert {:ok, case_1} = CaseProcessor.process_and_create_case(ea_detail_1)

      # Create second case with same Act but different section
      ea_detail_2 = %EaDetailRecord{
        ea_record_id: "EA_REUSE_002",
        offender_name: "Second Company Ltd",
        action_date: ~D[2023-02-20],
        action_type: "Court Case",
        act: "Environmental Permitting (england and Wales) Regulations 2016",
        section: "Regulation 12(1)",
        total_fine: Decimal.new("8000.00"),
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_REUSE_002"
      }

      assert {:ok, case_2} = CaseProcessor.process_and_create_case(ea_detail_2)

      # Get offences for both cases
      {:ok, offences_1} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_1.id) |> Ash.read()

      {:ok, offences_2} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_2.id) |> Ash.read()

      # Both should have offences
      assert length(offences_1) == 1
      assert length(offences_2) == 1

      offence_1 = List.first(offences_1)
      offence_2 = List.first(offences_2)

      # Should reference the same legislation
      assert offence_1.legislation_id == offence_2.legislation_id

      # But different sections
      assert offence_1.legislation_part == "Regulation 38(1)"
      assert offence_2.legislation_part == "Regulation 12(1)"

      # Verify only one Legislation record was created
      query =
        Ash.Query.filter(
          Enforcement.Legislation,
          legislation_title == "Environmental Permitting (england and Wales) Regulations 2016"
        )

      {:ok, legislations} = Ash.read(query)
      assert length(legislations) == 1
    end
  end

  describe "edge cases" do
    test "handles EA case with very long offence description", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA006"
        })

      long_description =
        "The Control of Major Accident Hazards Regulations 2015 (COMAH), Schedule 1, Part 1, Category E1 - Hazardous to the aquatic environment Category Acute 1 or Chronic 1"

      violations_data = [
        %{
          offence_description: long_description,
          legislation_part: "Schedule 1, Part 1, Category E1",
          fine: Decimal.new("20000.00"),
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      assert offence.offence_description == long_description
    end

    test "handles EA case with nil fine", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA007"
        })

      violations_data = [
        %{
          offence_description: "Water Resources Act 1991, Section 85(1)",
          legislation_part: "Section 85(1)",
          fine: nil,
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      assert offence.fine == nil
    end

    test "handles EA case where legislation cannot be extracted", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "EA Test Company Ltd"},
          regulator_id: "EA008"
        })

      violations_data = [
        %{
          offence_description: "Some general environmental violation",
          legislation_part: nil,
          fine: Decimal.new("3000.00"),
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      # Offences without legislation are skipped per resource validation (allow_nil?: false)
      assert offences == []
    end
  end

  describe "different EA legislation types" do
    test "handles Water Resources Act", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "Water Company Ltd"},
          regulator_id: "EA009"
        })

      violations_data = [
        %{
          offence_description: "Water Resources Act 1991, Section 85(1)",
          legislation_part: "Section 85(1)",
          fine: Decimal.new("12000.00"),
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)

      assert legislation.legislation_title == "Water Resources Act 1991"
      assert legislation.legislation_year == 1991
      assert legislation.legislation_type == :act
    end

    test "handles Environmental Protection Act", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "Protection Company Ltd"},
          regulator_id: "EA010"
        })

      violations_data = [
        %{
          offence_description: "Environmental Protection Act 1990, Section 33",
          legislation_part: "Section 33",
          fine: Decimal.new("18000.00"),
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)

      assert legislation.legislation_title == "Environmental Protection Act 1990"
      assert legislation.legislation_year == 1990
      assert legislation.legislation_type == :act
    end

    test "handles Waste Regulations", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :ea,
          offender_attrs: %{name: "Waste Company Ltd"},
          regulator_id: "EA011"
        })

      violations_data = [
        %{
          offence_description: "Waste (england and Wales) Regulations 2011, Regulation 35",
          legislation_part: "Regulation 35",
          fine: Decimal.new("7500.00"),
          sequence_number: 1
        }
      ]

      assert {:ok, _result} =
               CaseProcessor.create_case_violations(case_record, violations_data)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)

      assert legislation.legislation_title == "Waste (england and Wales) Regulations 2011"
      assert legislation.legislation_year == 2011
      assert legislation.legislation_type == :regulation
    end
  end
end
