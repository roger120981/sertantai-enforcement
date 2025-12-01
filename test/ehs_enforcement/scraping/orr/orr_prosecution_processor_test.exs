defmodule EhsEnforcement.Scraping.Orr.OrrProsecutionProcessorTest do
  use EhsEnforcement.DataCase, async: true

  alias EhsEnforcement.Scraping.Orr.OrrProsecutionProcessor
  alias EhsEnforcement.Scraping.Orr.OrrProsecutionProcessor.ProcessedProsecution
  alias EhsEnforcement.Scraping.Orr.OrrProsecutionScraper.ScrapedProsecution

  describe "process_prosecution/1" do
    test "processes a scraped prosecution into ProcessedProsecution" do
      scraped = %ScrapedProsecution{
        year: 2025,
        company: "Network Rail Infrastructure Limited",
        summary: "Network Rail were fined £3.75 million for trackworker fatalities.",
        breaches_involved: "Health and Safety at Work etc Act 1974, Section 2(1)",
        date_of_offence: "3 July 2019",
        plea: "Guilty",
        result: "Convicted under Section 2(1)",
        court: "Swansea Crown Court",
        sentencing_date: "14 February 2025",
        penalty: "£3,750,000 (Very Large Organisation – High culpability/Harm Category 1)",
        penalty_amount: Decimal.new("3750000"),
        costs: "£175,000",
        costs_amount: Decimal.new("175000"),
        location: "Near Margam, South Wales",
        orr_details: "Railway Safety Directorate",
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert %ProcessedProsecution{} = processed
      assert processed.agency_code == :orr
      assert processed.offence_fine == Decimal.new("3750000")
      assert processed.offence_costs == Decimal.new("175000")
      assert processed.offence_hearing_date == ~D[2025-02-14]
      assert processed.offence_action_date == ~D[2019-07-03]
      assert processed.offence_action_type == "ORR Prosecution"

      # Check regulator_id format
      assert String.starts_with?(processed.regulator_id, "orr_2025_network_rail_")

      # Check offender attrs
      assert processed.offender_attrs.name == "Network Rail Infrastructure Limited"
      assert processed.offender_attrs.address == "Near Margam, South Wales"

      # Check result text includes summary
      assert String.contains?(processed.offence_result, "trackworker fatalities")

      # Check breaches includes court
      assert String.contains?(processed.offence_breaches, "Swansea Crown Court")
    end

    test "handles prosecution with minimal data" do
      scraped = %ScrapedProsecution{
        year: 2020,
        company: "Test Railway Ltd",
        summary: nil,
        breaches_involved: nil,
        date_of_offence: nil,
        plea: nil,
        result: nil,
        court: nil,
        sentencing_date: nil,
        penalty: nil,
        penalty_amount: nil,
        costs: nil,
        costs_amount: nil,
        location: nil,
        orr_details: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed.offender_attrs.name == "Test Railway Ltd"
      assert processed.offence_fine == nil
      assert processed.offence_costs == nil
      assert processed.offence_hearing_date == nil
    end

    test "generates unique regulator_id for different prosecutions" do
      base = %ScrapedProsecution{
        year: 2024,
        company: "Company A Ltd",
        sentencing_date: "1 March 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      other = %ScrapedProsecution{
        year: 2024,
        company: "Company B Ltd",
        sentencing_date: "1 March 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed1} = OrrProsecutionProcessor.process_prosecution(base)
      {:ok, processed2} = OrrProsecutionProcessor.process_prosecution(other)

      assert processed1.regulator_id != processed2.regulator_id
    end

    test "generates consistent regulator_id for same prosecution" do
      scraped = %ScrapedProsecution{
        year: 2024,
        company: "Consistent Company Ltd",
        sentencing_date: "15 June 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed1} = OrrProsecutionProcessor.process_prosecution(scraped)
      {:ok, processed2} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed1.regulator_id == processed2.regulator_id
    end
  end

  describe "process_prosecutions/1" do
    test "processes multiple prosecutions" do
      prosecutions = [
        %ScrapedProsecution{
          year: 2025,
          company: "Company One Ltd",
          sentencing_date: "1 January 2025",
          scrape_timestamp: DateTime.utc_now()
        },
        %ScrapedProsecution{
          year: 2024,
          company: "Company Two Ltd",
          sentencing_date: "1 June 2024",
          scrape_timestamp: DateTime.utc_now()
        }
      ]

      assert {:ok, processed_list} = OrrProsecutionProcessor.process_prosecutions(prosecutions)

      assert length(processed_list) == 2
      assert Enum.all?(processed_list, &match?(%ProcessedProsecution{}, &1))
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = OrrProsecutionProcessor.process_prosecutions([])
    end
  end

  describe "date parsing" do
    test "parses standard date format" do
      scraped = %ScrapedProsecution{
        year: 2025,
        company: "Test",
        sentencing_date: "14 February 2025",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_hearing_date == ~D[2025-02-14]
    end

    test "parses date with ordinal suffix" do
      scraped = %ScrapedProsecution{
        year: 2018,
        company: "Test",
        date_of_offence: "1st December 2018",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_action_date == ~D[2018-12-01]
    end

    test "parses date with 'On and before' prefix" do
      scraped = %ScrapedProsecution{
        year: 2018,
        company: "Test",
        date_of_offence: "On and before 1st December 2018",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_action_date == ~D[2018-12-01]
    end

    test "handles nil dates gracefully" do
      scraped = %ScrapedProsecution{
        year: 2020,
        company: "Test",
        sentencing_date: nil,
        date_of_offence: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_hearing_date == nil
      assert processed.offence_action_date == nil
    end

    test "handles invalid date strings gracefully" do
      scraped = %ScrapedProsecution{
        year: 2020,
        company: "Test",
        sentencing_date: "invalid date",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_hearing_date == nil
    end
  end

  describe "ProcessedProsecution struct" do
    test "has all expected fields" do
      processed = %ProcessedProsecution{
        regulator_id: "orr_2025_test_20250101",
        agency_code: :orr,
        offender_attrs: %{name: "Test", address: nil, country: "United Kingdom"},
        offence_hearing_date: ~D[2025-01-01],
        offence_action_date: ~D[2024-06-01],
        offence_fine: Decimal.new("100000"),
        offence_costs: Decimal.new("5000"),
        offence_result: "Test result",
        offence_breaches: "Test breaches",
        offence_action_type: "ORR Prosecution",
        url: "https://www.orr.gov.uk/...",
        source_metadata: %{year: 2025}
      }

      assert processed.regulator_id == "orr_2025_test_20250101"
      assert processed.agency_code == :orr
      assert processed.offence_fine == Decimal.new("100000")
    end

    test "is JSON encodable" do
      processed = %ProcessedProsecution{
        regulator_id: "orr_2025_test",
        agency_code: :orr,
        offender_attrs: %{name: "Test Company"},
        offence_action_type: "ORR Prosecution",
        source_metadata: %{year: 2025}
      }

      assert {:ok, json} = Jason.encode(processed)
      assert is_binary(json)
      assert String.contains?(json, "orr_2025_test")
    end
  end
end
