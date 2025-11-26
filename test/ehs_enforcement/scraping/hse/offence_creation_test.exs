defmodule EhsEnforcement.Scraping.Hse.OffenceCreationTest do
  use EhsEnforcement.DataCase

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Scraping.Hse.CaseProcessor
  alias EhsEnforcement.Scraping.Hse.CaseScraper.ScrapedCase

  setup do
    # Create test agency
    {:ok, agency} =
      Enforcement.create_agency(%{
        name: "Health and Safety Executive",
        code: :hse,
        base_url: "https://hse.gov.uk"
      })

    %{agency: agency}
  end

  describe "create_case_offences/3 with single breach" do
    test "creates offence from single breach text", %{agency: agency} do
      # Create case first
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE001",
          offence_action_date: ~D[2023-01-15]
        })

      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1)"

      assert {:ok, offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      assert length(offences_data) == 1

      # Verify offence was created in database
      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert length(offences) == 1

      offence = List.first(offences)
      assert offence.case_id == case_record.id
      assert offence.offence_description == breach_text
      assert offence.legislation_part == "Section 2(1)"
      assert offence.sequence_number == 1

      # Verify legislation was created and linked
      assert offence.legislation_id != nil
      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)
      assert legislation.legislation_title == "Health and Safety at Work etc. Act 1974"
      assert legislation.legislation_year == 1974
    end

    test "handles breach with fine in text", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE002"
        })

      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1). Fine: £5,000"

      assert {:ok, _offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      assert Decimal.equal?(offence.fine, Decimal.new("5000"))
    end

    test "reuses existing legislation when matching breach", %{agency: agency} do
      # Pre-create legislation
      {:ok, existing_legislation} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act 1974",
          legislation_year: 1974,
          legislation_type: :act
        })

      # Create case and offence
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE003"
        })

      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1)"

      assert {:ok, _offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      # Verify offence links to existing legislation
      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      offence = List.first(offences)
      assert offence.legislation_id == existing_legislation.id

      # Verify no duplicate legislation was created
      query =
        Ash.Query.filter(
          Enforcement.Legislation,
          legislation_title == "Health and Safety at Work etc. Act 1974"
        )

      {:ok, legislations} = Ash.read(query)
      assert length(legislations) == 1
    end
  end

  describe "create_case_offences/3 with semicolon-separated breaches" do
    test "creates multiple offences from semicolon-separated breach text", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE004"
        })

      breach_text =
        "Health and Safety at Work etc Act 1974, Section 2(1); Construction (Design and Management) Regulations 2015, Regulation 13(1)"

      assert {:ok, offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      assert length(offences_data) == 2

      # Verify offences were created in database
      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(case_id == ^case_record.id)
        |> Ash.Query.sort(sequence_number: :asc)
        |> Ash.read()

      assert length(offences) == 2

      [first_offence, second_offence] = offences

      # First offence
      assert first_offence.legislation_part == "Section 2(1)"
      assert first_offence.sequence_number == 1
      {:ok, first_leg} = Ash.get(Enforcement.Legislation, first_offence.legislation_id)
      assert first_leg.legislation_year == 1974

      # Second offence
      assert second_offence.legislation_part == "Regulation 13(1)"
      assert second_offence.sequence_number == 2
      {:ok, second_leg} = Ash.get(Enforcement.Legislation, second_offence.legislation_id)
      assert second_leg.legislation_year == 2015
    end

    test "handles three breaches with different legislation types", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE005"
        })

      breach_text =
        "Health and Safety at Work etc Act 1974, Section 2(1); Work at Height Regulations 2005, Regulation 4(1); Provision and Use of Work Equipment Regulations 1998, Regulation 5"

      assert {:ok, offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      assert length(offences_data) == 3

      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(case_id == ^case_record.id)
        |> Ash.Query.sort(sequence_number: :asc)
        |> Ash.read()

      assert length(offences) == 3
      assert Enum.at(offences, 0).sequence_number == 1
      assert Enum.at(offences, 1).sequence_number == 2
      assert Enum.at(offences, 2).sequence_number == 3
    end
  end

  describe "create_case_offences/3 with list of breaches" do
    test "creates offences from list of breach texts", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE006"
        })

      breach_list = [
        "Health and Safety at Work etc Act 1974, Section 2(1)",
        "Construction (Design and Management) Regulations 2015, Regulation 13(1)"
      ]

      assert {:ok, offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_list)

      assert length(offences_data) == 2

      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(case_id == ^case_record.id)
        |> Ash.Query.sort(sequence_number: :asc)
        |> Ash.read()

      assert length(offences) == 2
    end
  end

  describe "create_case_offences/3 edge cases" do
    test "handles nil breach data gracefully", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE007"
        })

      assert {:ok, []} = CaseProcessor.create_case_offences(case_record, nil)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert offences == []
    end

    test "handles empty string breach data", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE008"
        })

      assert {:ok, []} = CaseProcessor.create_case_offences(case_record, "")

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert offences == []
    end

    test "handles empty list breach data", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE009"
        })

      assert {:ok, []} = CaseProcessor.create_case_offences(case_record, [])

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert offences == []
    end

    test "handles breach without legislation reference", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE010"
        })

      breach_text = "Some general violation without legislation reference"

      # Should return empty list since offences without legislation are skipped
      assert {:ok, offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      assert length(offences_data) == 0

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      # No offences should be created for breaches without legislation
      assert offences == []
    end
  end

  describe "process_and_create_case/2 integration" do
    test "creates case with offences in one operation", %{agency: agency} do
      scraped_case = %ScrapedCase{
        regulator_id: "HSE_INTEGRATION_001",
        offender_name: "Integration Test Company Ltd",
        offence_action_date: ~D[2023-01-15],
        offender_local_authority: "Manchester",
        offence_fine: Decimal.new("5000.00"),
        offence_breaches:
          "Health and Safety at Work etc Act 1974, Section 2(1); Work at Height Regulations 2005, Regulation 4(1)",
        scrape_timestamp: DateTime.utc_now(),
        page_number: 1
      }

      assert {:ok, case_record} = CaseProcessor.process_and_create_case(scraped_case)

      # Verify case was created
      assert case_record.regulator_id == "HSE_INTEGRATION_001"

      # Verify offences were created
      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(case_id == ^case_record.id)
        |> Ash.Query.sort(sequence_number: :asc)
        |> Ash.read()

      assert length(offences) == 2

      # Verify legislation records were created
      assert Enum.at(offences, 0).legislation_id != nil
      assert Enum.at(offences, 1).legislation_id != nil

      {:ok, first_leg} = Ash.get(Enforcement.Legislation, Enum.at(offences, 0).legislation_id)
      {:ok, second_leg} = Ash.get(Enforcement.Legislation, Enum.at(offences, 1).legislation_id)

      assert first_leg.legislation_year == 1974
      assert second_leg.legislation_year == 2005
    end

    test "handles case with single breach", %{agency: agency} do
      scraped_case = %ScrapedCase{
        regulator_id: "HSE_INTEGRATION_002",
        offender_name: "Single Breach Company Ltd",
        offence_action_date: ~D[2023-02-20],
        offence_breaches: "Health and Safety at Work etc Act 1974, Section 3(1)",
        scrape_timestamp: DateTime.utc_now(),
        page_number: 1
      }

      assert {:ok, case_record} = CaseProcessor.process_and_create_case(scraped_case)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      assert length(offences) == 1
      assert List.first(offences).legislation_part == "Section 3(1)"
    end

    test "handles case with no breach data", %{agency: agency} do
      scraped_case = %ScrapedCase{
        regulator_id: "HSE_INTEGRATION_003",
        offender_name: "No Breach Company Ltd",
        offence_action_date: ~D[2023-03-10],
        offence_breaches: nil,
        scrape_timestamp: DateTime.utc_now(),
        page_number: 1
      }

      assert {:ok, case_record} = CaseProcessor.process_and_create_case(scraped_case)

      {:ok, offences} =
        Enforcement.Offence |> Ash.Query.filter(case_id == ^case_record.id) |> Ash.read()

      # Should still create case successfully, just with no offences
      assert offences == []
    end
  end

  describe "bulk offence creation with same legislation" do
    test "reuses legislation across multiple offences in same case", %{agency: agency} do
      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_code: :hse,
          offender_attrs: %{name: "Test Company Ltd"},
          regulator_id: "HSE011"
        })

      # Multiple breaches referencing same Act but different sections
      breach_text =
        "Health and Safety at Work etc Act 1974, Section 2(1); Health and Safety at Work etc Act 1974, Section 3(1); Health and Safety at Work etc Act 1974, Section 7"

      assert {:ok, _offences_data} =
               CaseProcessor.create_case_offences(case_record, breach_text)

      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(case_id == ^case_record.id)
        |> Ash.Query.sort(sequence_number: :asc)
        |> Ash.read()

      assert length(offences) == 3

      # All should reference the same legislation
      [first, second, third] = offences
      assert first.legislation_id == second.legislation_id
      assert second.legislation_id == third.legislation_id

      # But different sections
      assert first.legislation_part == "Section 2(1)"
      assert second.legislation_part == "Section 3(1)"
      assert third.legislation_part == "Section 7"

      # Verify only one Legislation record was created
      query =
        Ash.Query.filter(
          Enforcement.Legislation,
          legislation_title == "Health and Safety at Work etc. Act 1974"
        )

      {:ok, legislations} = Ash.read(query)
      assert length(legislations) == 1
    end
  end
end
