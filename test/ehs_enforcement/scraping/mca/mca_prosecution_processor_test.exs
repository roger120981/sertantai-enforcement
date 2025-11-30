defmodule EhsEnforcement.Scraping.Mca.McaProsecutionProcessorTest do
  use EhsEnforcement.DataCase, async: true

  alias EhsEnforcement.Scraping.Mca.McaProsecutionProcessor
  alias EhsEnforcement.Scraping.Mca.McaProsecutionProcessor.ProcessedProsecution
  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper.ScrapedProsecution

  require Ash.Query

  describe "process_prosecution/1" do
    test "transforms scraped prosecution to processed format" do
      scraped = build_scraped_prosecution()

      assert {:ok, %ProcessedProsecution{} = processed} =
               McaProsecutionProcessor.process_prosecution(scraped)

      assert processed.agency_code == :mca
      assert processed.regulator_id =~ ~r/^mca_2024_intrada_ships/
      assert processed.offence_hearing_date == ~D[2025-02-14]
      assert processed.offence_action_type == "MCA Prosecution"
      assert processed.offender_attrs.name == "Intrada Ships Management Ltd"
      assert Decimal.equal?(processed.offence_fine, Decimal.new("180000"))
      assert Decimal.equal?(processed.offence_costs, Decimal.new("500000"))
    end

    test "generates deterministic regulator_id" do
      scraped = build_scraped_prosecution()

      {:ok, processed1} = McaProsecutionProcessor.process_prosecution(scraped)
      {:ok, processed2} = McaProsecutionProcessor.process_prosecution(scraped)

      assert processed1.regulator_id == processed2.regulator_id
    end

    test "generates unique regulator_id for different defendants" do
      scraped1 = build_scraped_prosecution(%{defendant: "Company A Ltd"})
      scraped2 = build_scraped_prosecution(%{defendant: "Company B Ltd"})

      {:ok, processed1} = McaProsecutionProcessor.process_prosecution(scraped1)
      {:ok, processed2} = McaProsecutionProcessor.process_prosecution(scraped2)

      refute processed1.regulator_id == processed2.regulator_id
    end

    test "builds offence result with case details" do
      scraped =
        build_scraped_prosecution(%{
          case_title: "Company fined after collision",
          details: "A shipping company failed to ensure safe operation.",
          custodial_sentence: "8 months suspended",
          community_service_hours: 150,
          victim_surcharge: Decimal.new("190")
        })

      {:ok, processed} = McaProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_result =~ "Company fined after collision"
      assert processed.offence_result =~ "8 months suspended"
      assert processed.offence_result =~ "150 hours"
      assert processed.offence_result =~ "£190"
    end

    test "builds offence breaches with court and legislation" do
      scraped =
        build_scraped_prosecution(%{
          court: "Southampton Crown Court",
          offences: [
            %{section: "Section 100", legislation: "Merchant Shipping Act 1995"},
            %{section: "Regulation 7", legislation: "ISM Code Regulations 2014"}
          ]
        })

      {:ok, processed} = McaProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_breaches =~ "Southampton Crown Court"
      assert processed.offence_breaches =~ "Section 100 Merchant Shipping Act 1995"
      assert processed.offence_breaches =~ "Regulation 7 ISM Code Regulations 2014"
    end

    test "builds source URL based on year" do
      scraped_2025 = build_scraped_prosecution(%{year: 2025})
      scraped_2024 = build_scraped_prosecution(%{year: 2024})
      scraped_2019 = build_scraped_prosecution(%{year: 2019})

      {:ok, p2025} = McaProsecutionProcessor.process_prosecution(scraped_2025)
      {:ok, p2024} = McaProsecutionProcessor.process_prosecution(scraped_2024)
      {:ok, p2019} = McaProsecutionProcessor.process_prosecution(scraped_2019)

      assert p2025.url =~ "regulatory-compliance-investigations-team-prosecutions-2025"
      assert p2024.url =~ "mca-enforcement-unit-prosecutions-2024"
      assert p2019.url =~ "mca-enforcement-unit-prosecutions-2019"
    end

    test "stores offences for later Offence record creation" do
      scraped =
        build_scraped_prosecution(%{
          offences: [
            %{section: "Section 58", legislation: "Merchant Shipping Act 1995"},
            %{section: "Section 100", legislation: "Merchant Shipping Act 1995"}
          ]
        })

      {:ok, processed} = McaProsecutionProcessor.process_prosecution(scraped)

      assert is_list(processed.offences)
      assert length(processed.offences) == 2
    end

    test "handles nil fine and costs" do
      scraped = build_scraped_prosecution(%{fine: nil, costs: nil})

      {:ok, processed} = McaProsecutionProcessor.process_prosecution(scraped)

      assert is_nil(processed.offence_fine)
      assert is_nil(processed.offence_costs)
    end

    test "stores source metadata" do
      scraped = build_scraped_prosecution()

      {:ok, processed} = McaProsecutionProcessor.process_prosecution(scraped)

      assert processed.source_metadata.source == "gov.uk"
      assert processed.source_metadata.year == 2024
      assert processed.source_metadata.court == "Southampton Crown Court"
    end
  end

  describe "process_prosecutions/1" do
    test "processes multiple prosecutions" do
      prosecutions = [
        build_scraped_prosecution(%{defendant: "Company A"}),
        build_scraped_prosecution(%{defendant: "Company B"}),
        build_scraped_prosecution(%{defendant: "Company C"})
      ]

      assert {:ok, processed} = McaProsecutionProcessor.process_prosecutions(prosecutions)
      assert length(processed) == 3
    end

    test "returns errors separately" do
      # All valid prosecutions should process without errors
      prosecutions = [
        build_scraped_prosecution(%{defendant: "Valid Company"})
      ]

      {:ok, processed} = McaProsecutionProcessor.process_prosecutions(prosecutions)
      assert length(processed) == 1
    end
  end

  describe "process_and_create_prosecution/2" do
    setup do
      # Create MCA agency for tests
      {:ok, agency} =
        EhsEnforcement.Enforcement.Agency
        |> Ash.Changeset.for_create(:create, %{
          code: :mca,
          name: "Maritime and Coastguard Agency",
          base_url: "https://www.gov.uk/government/organisations/maritime-and-coastguard-agency",
          enabled: true
        })
        |> Ash.create()

      %{agency: agency}
    end

    test "creates case in database", %{agency: _agency} do
      defendant = "Test Company #{System.unique_integer([:positive])}"
      scraped = build_scraped_prosecution(%{defendant: defendant})

      assert {:ok, case_record} =
               McaProsecutionProcessor.process_and_create_prosecution(scraped, nil)

      assert case_record.regulator_id =~ ~r/^mca_2024_test_company/
      assert case_record.offence_action_type == "MCA Prosecution"
      assert case_record.agency_id != nil
      assert case_record.offender_id != nil
      assert Decimal.equal?(case_record.offence_fine, Decimal.new("180000"))
    end

    test "creates offender with correct attributes", %{agency: _agency} do
      defendant = "Maritime Safety Ltd #{System.unique_integer([:positive])}"

      scraped =
        build_scraped_prosecution(%{
          defendant: defendant,
          defendant_location: "Southampton"
        })

      {:ok, case_record} =
        McaProsecutionProcessor.process_and_create_prosecution(scraped, nil)

      # Load the offender
      {:ok, offender} = Ash.get(EhsEnforcement.Enforcement.Offender, case_record.offender_id)

      assert offender.name == defendant
      assert offender.country == "United Kingdom"
    end

    test "creates offence records for legislation citations", %{agency: _agency} do
      defendant = "Legislation Test Ltd #{System.unique_integer([:positive])}"

      scraped =
        build_scraped_prosecution(%{
          defendant: defendant,
          offences: [
            %{section: "Section 100", legislation: "Merchant Shipping Act 1995"},
            %{section: "Regulation 7", legislation: "ISM Code Regulations 2014"}
          ]
        })

      {:ok, case_record} =
        McaProsecutionProcessor.process_and_create_prosecution(scraped, nil)

      # Query for offences linked to this case
      {:ok, offences} =
        EhsEnforcement.Enforcement.Offence
        |> Ash.Query.filter(case_id == ^case_record.id)
        |> Ash.read()

      assert length(offences) == 2

      # Check legislation was created/linked
      Enum.each(offences, fn offence ->
        assert offence.legislation_id != nil
        assert offence.legislation_part != nil
      end)
    end

    test "rejects duplicate prosecutions", %{agency: _agency} do
      defendant = "Duplicate Test Ltd #{System.unique_integer([:positive])}"
      scraped = build_scraped_prosecution(%{defendant: defendant})

      # First creation should succeed
      assert {:ok, _case1} =
               McaProsecutionProcessor.process_and_create_prosecution(scraped, nil)

      # Second creation with same defendant/date should fail (duplicate regulator_id)
      assert {:error, _reason} =
               McaProsecutionProcessor.process_and_create_prosecution(scraped, nil)
    end
  end

  # Helper functions

  defp build_scraped_prosecution(overrides \\ %{}) do
    defaults = %{
      year: 2024,
      case_title: "Company fined after maritime incident",
      defendant: "Intrada Ships Management Ltd",
      defendant_age: nil,
      defendant_location: "London",
      hearing_date: ~D[2025-02-14],
      court: "Southampton Crown Court",
      offences: [
        %{section: "Section 100", legislation: "Merchant Shipping Act 1995"}
      ],
      details: "A shipping company was fined for failing to operate safely...",
      fine: Decimal.new("180000"),
      costs: Decimal.new("500000"),
      victim_surcharge: nil,
      custodial_sentence: nil,
      community_service_hours: nil,
      total_penalty: Decimal.new("680000"),
      scrape_timestamp: DateTime.utc_now()
    }

    merged = Map.merge(defaults, overrides)

    struct(ScrapedProsecution, merged)
  end
end
