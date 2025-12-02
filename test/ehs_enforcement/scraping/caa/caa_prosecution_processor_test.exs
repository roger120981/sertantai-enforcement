defmodule EhsEnforcement.Scraping.Caa.CaaProsecutionProcessorTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Caa.CaaProsecutionProcessor
  alias EhsEnforcement.Scraping.Caa.CaaProsecutionProcessor.ProcessedProsecution
  alias EhsEnforcement.Scraping.Caa.CaaProsecutionScraper.ScrapedProsecution

  describe "process_prosecution/1" do
    test "processes a scraped prosecution into correct format" do
      scraped = %ScrapedProsecution{
        fiscal_year: "2024-2025",
        defendant: "Barry SCOTT",
        brief_description:
          "Barry Scott was the pilot in command of Piper PA-28 aircraft. Mr Scott pleaded guilty to negligently endangering an aircraft.",
        date: "28/05/2024",
        court: "Reading Crown Court",
        sentence: "Fine £1,500",
        fine_amount: Decimal.new("1500"),
        scrape_timestamp: ~U[2025-12-02 12:00:00Z]
      }

      assert {:ok, processed} = CaaProsecutionProcessor.process_prosecution(scraped)

      assert %ProcessedProsecution{} = processed
      assert processed.agency_code == :caa
      assert processed.regulator_id == "caa_20242025_barry_scott_20240528"
      assert processed.offence_fine == Decimal.new("1500")
      assert processed.offence_hearing_date == ~D[2024-05-28]
      assert processed.offence_action_type == "CAA Prosecution"
      assert processed.offence_result =~ "Barry Scott was the pilot"
      assert processed.offence_breaches =~ "Reading Crown Court"
      assert processed.url =~ "caa.co.uk"
    end

    test "generates deterministic regulator_id" do
      scraped = %ScrapedProsecution{
        fiscal_year: "2024-2025",
        defendant: "Charles HUDSON",
        date: "29/08/2024",
        court: "Chelmsford Magistrates' Court",
        sentence: "Fine £4,000",
        fine_amount: Decimal.new("4000"),
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed1} = CaaProsecutionProcessor.process_prosecution(scraped)
      assert {:ok, processed2} = CaaProsecutionProcessor.process_prosecution(scraped)

      assert processed1.regulator_id == processed2.regulator_id
      assert processed1.regulator_id == "caa_20242025_charles_hudson_20240829"
    end

    test "handles missing date gracefully" do
      scraped = %ScrapedProsecution{
        fiscal_year: "2024-2025",
        defendant: "Test Person",
        date: nil,
        court: "Test Court",
        sentence: "Fine £500",
        fine_amount: Decimal.new("500"),
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = CaaProsecutionProcessor.process_prosecution(scraped)

      assert processed.offence_hearing_date == nil
      assert processed.regulator_id =~ "00000000"
    end

    test "builds offender attributes correctly" do
      scraped = %ScrapedProsecution{
        fiscal_year: "2024-2025",
        defendant: "Simon NICHOLLS",
        date: "06/03/2025",
        court: "Mansfield Magistrates' Court",
        sentence: "Fine £1,280",
        fine_amount: Decimal.new("1280"),
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = CaaProsecutionProcessor.process_prosecution(scraped)

      assert processed.offender_attrs.name == "Simon NICHOLLS"
      assert processed.offender_attrs.country == "United Kingdom"
    end
  end

  describe "process_prosecutions/1" do
    test "processes multiple prosecutions" do
      prosecutions = [
        %ScrapedProsecution{
          fiscal_year: "2024-2025",
          defendant: "Person A",
          date: "01/01/2024",
          court: "Court A",
          sentence: "Fine £100",
          fine_amount: Decimal.new("100"),
          scrape_timestamp: DateTime.utc_now()
        },
        %ScrapedProsecution{
          fiscal_year: "2024-2025",
          defendant: "Person B",
          date: "02/02/2024",
          court: "Court B",
          sentence: "Fine £200",
          fine_amount: Decimal.new("200"),
          scrape_timestamp: DateTime.utc_now()
        }
      ]

      assert {:ok, processed_list} = CaaProsecutionProcessor.process_prosecutions(prosecutions)

      assert length(processed_list) == 2
      assert Enum.all?(processed_list, &match?(%ProcessedProsecution{}, &1))
    end
  end

  describe "ProcessedProsecution struct" do
    test "is JSON encodable" do
      processed = %ProcessedProsecution{
        regulator_id: "caa_20242025_test_20240101",
        agency_code: :caa,
        offender_attrs: %{name: "Test", country: "United Kingdom"},
        offence_hearing_date: ~D[2024-01-01],
        offence_fine: Decimal.new("1000"),
        offence_result: "Test result",
        offence_breaches: "Test breaches",
        offence_action_type: "CAA Prosecution",
        url: "https://example.com"
      }

      assert {:ok, json} = Jason.encode(processed)
      assert is_binary(json)
    end
  end
end
