defmodule EhsEnforcement.Scraping.Sepa.SepaPenaltyProcessorTest do
  use EhsEnforcement.DataCase

  require Ash.Query
  import Ash.Expr

  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper.ScrapedPenalty
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyProcessor
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyProcessor.ProcessedPenalty

  describe "process_penalty/1" do
    test "processes a fixed monetary penalty correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company Ltd, Edinburgh, EH1 1AA",
        date: "15 March 2025",
        offence_details:
          "Environmental Protection Act 1990. Section 33 - Deposit of controlled waste.",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, %ProcessedPenalty{} = processed} =
               SepaPenaltyProcessor.process_penalty(scraped)

      # Check regulator_id format: sepa_YYYYMMDD_hash
      assert String.starts_with?(processed.regulator_id, "sepa_20250315_")
      # sepa_ (5) + date (8) + _ (1) + hash (8)
      assert String.length(processed.regulator_id) == 22

      assert processed.agency_code == :sepa
      assert processed.notice_date == ~D[2025-03-15]
      assert processed.offence_action_type == "SEPA FMP £600"
      assert processed.penalty_amount == Decimal.new("600")
      assert processed.offender_attrs.name == "Test Company Ltd"
      assert processed.offender_attrs.country == "Scotland"
    end

    test "processes a variable monetary penalty correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Variable monetary penalty",
        name_and_address: "XYZ Industries Ltd, Aberdeen, AB10 1CD",
        date: "5 January 2025",
        offence_details: "Knowingly causing controlled waste to be deposited.",
        penalty_amount: Decimal.new("2500.50"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, %ProcessedPenalty{} = processed} =
               SepaPenaltyProcessor.process_penalty(scraped)

      assert processed.offence_action_type == "SEPA VMP"
      assert processed.penalty_amount == Decimal.new("2500.50")
      assert processed.offender_attrs.name == "XYZ Industries Ltd"
      assert processed.offender_attrs.address == "Aberdeen, AB10 1CD"
    end

    test "processes an enforcement undertaking correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Enforcement undertaking",
        name_and_address: "Undertaking Corp, Inverness, IV1 1GH",
        date: "1 April 2025",
        offence_details: "Failure to comply with permit conditions.",
        penalty_amount: nil,
        documentation_url: "https://example.com/undertaking.pdf",
        legislation_breached: "The Pollution Prevention and Control (Scotland) Regulations 2012",
        year: 2025,
        section_type: :undertakings,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, %ProcessedPenalty{} = processed} =
               SepaPenaltyProcessor.process_penalty(scraped)

      assert processed.offence_action_type == "SEPA Undertaking"
      assert is_nil(processed.penalty_amount)

      assert processed.offence_breaches ==
               "The Pollution Prevention and Control (Scotland) Regulations 2012"

      assert processed.url == "https://example.com/undertaking.pdf"
    end

    test "processes a costs recovery notice correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Costs recovery",
        name_and_address: "Costs Recovery Ltd, Perth, PH1 1IJ",
        date: "20 May 2025",
        offence_details: nil,
        penalty_amount: Decimal.new("1500.00"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :costs_recovery,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, %ProcessedPenalty{} = processed} =
               SepaPenaltyProcessor.process_penalty(scraped)

      assert processed.offence_action_type == "SEPA Costs Recovery"
      assert processed.penalty_amount == Decimal.new("1500.00")
    end

    test "parses name and address with postcode correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address:
          "Patersons of Greenoakhill Limited, Gartsherrie Road, Coatbridge, ML5 2EU",
        date: "10 February 2025",
        offence_details: "Test offence",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, %ProcessedPenalty{} = processed} =
               SepaPenaltyProcessor.process_penalty(scraped)

      assert processed.offender_attrs.name == "Patersons of Greenoakhill Limited"
      assert processed.offender_attrs.address == "Gartsherrie Road, Coatbridge, ML5 2EU"
      assert processed.offender_attrs.postcode == "ML5 2EU"
      assert processed.offender_attrs.country == "Scotland"
    end

    test "handles 'Information not published' name" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Information not published",
        date: "10 February 2025",
        offence_details: "Test offence",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, %ProcessedPenalty{} = processed} =
               SepaPenaltyProcessor.process_penalty(scraped)

      assert processed.offender_attrs.name == "[Name withheld]"
    end

    test "generates deterministic regulator_id for same record" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company Ltd, Edinburgh, EH1",
        date: "15 March 2025",
        offence_details: "Test offence",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed1} = SepaPenaltyProcessor.process_penalty(scraped)
      {:ok, processed2} = SepaPenaltyProcessor.process_penalty(scraped)

      # Same input should produce same regulator_id (deterministic)
      assert processed1.regulator_id == processed2.regulator_id
    end

    test "generates different regulator_id for different records" do
      scraped1 = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Company A, Edinburgh, EH1",
        date: "15 March 2025",
        offence_details: "Test offence",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      scraped2 = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Company B, Glasgow, G1",
        date: "15 March 2025",
        offence_details: "Test offence",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed1} = SepaPenaltyProcessor.process_penalty(scraped1)
      {:ok, processed2} = SepaPenaltyProcessor.process_penalty(scraped2)

      # Different names should produce different regulator_ids
      assert processed1.regulator_id != processed2.regulator_id
    end
  end

  describe "process_penalties/1 batch processing" do
    test "processes multiple penalties successfully" do
      scraped_list = [
        %ScrapedPenalty{
          penalty_type: "Fixed monetary penalty",
          name_and_address: "Company A, Edinburgh, EH1",
          date: "15 March 2025",
          offence_details: "Test offence A",
          penalty_amount: Decimal.new("600"),
          documentation_url: nil,
          legislation_breached: nil,
          year: 2025,
          section_type: :penalties,
          scrape_timestamp: DateTime.utc_now()
        },
        %ScrapedPenalty{
          penalty_type: "Variable monetary penalty",
          name_and_address: "Company B, Glasgow, G1",
          date: "10 February 2025",
          offence_details: "Test offence B",
          penalty_amount: Decimal.new("2500"),
          documentation_url: nil,
          legislation_breached: nil,
          year: 2025,
          section_type: :penalties,
          scrape_timestamp: DateTime.utc_now()
        }
      ]

      assert {:ok, processed_list} = SepaPenaltyProcessor.process_penalties(scraped_list)

      assert length(processed_list) == 2
      assert Enum.all?(processed_list, &match?(%ProcessedPenalty{}, &1))

      [first, second] = processed_list
      assert first.offender_attrs.name == "Company A"
      assert second.offender_attrs.name == "Company B"
    end
  end

  describe "date parsing" do
    test "parses long date format (DD Month YYYY)" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company, Location, AB1",
        date: "16 July 2025",
        offence_details: "Test",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
      assert processed.notice_date == ~D[2025-07-16]
    end

    test "parses single digit day (D Month YYYY)" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company, Location, AB1",
        date: "9 January 2025",
        offence_details: "Test",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
      assert processed.notice_date == ~D[2025-01-09]
    end

    test "handles invalid date gracefully" do
      scraped = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company, Location, AB1",
        date: "invalid date",
        offence_details: "Test",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
      assert is_nil(processed.notice_date)
    end
  end

  describe "offence_action_type mapping" do
    test "maps FMP with amount correctly" do
      for {amount, expected} <- [
            {Decimal.new("300"), "SEPA FMP £300"},
            {Decimal.new("600"), "SEPA FMP £600"},
            {Decimal.new("1000"), "SEPA FMP £1000"}
          ] do
        scraped = %ScrapedPenalty{
          penalty_type: "Fixed monetary penalty",
          name_and_address: "Test, Location, AB1",
          date: "15 March 2025",
          offence_details: "Test",
          penalty_amount: amount,
          documentation_url: nil,
          legislation_breached: nil,
          year: 2025,
          section_type: :penalties,
          scrape_timestamp: DateTime.utc_now()
        }

        {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
        assert processed.offence_action_type == expected
      end
    end

    test "maps VMP correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Variable monetary penalty",
        name_and_address: "Test, Location, AB1",
        date: "15 March 2025",
        offence_details: "Test",
        penalty_amount: Decimal.new("5000"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
      assert processed.offence_action_type == "SEPA VMP"
    end

    test "maps undertaking correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Enforcement undertaking",
        name_and_address: "Test, Location, AB1",
        date: "15 March 2025",
        offence_details: "Test",
        penalty_amount: nil,
        documentation_url: nil,
        legislation_breached: "Some Act",
        year: 2025,
        section_type: :undertakings,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
      assert processed.offence_action_type == "SEPA Undertaking"
    end

    test "maps costs recovery correctly" do
      scraped = %ScrapedPenalty{
        penalty_type: "Costs recovery",
        name_and_address: "Test, Location, AB1",
        date: "15 March 2025",
        offence_details: nil,
        penalty_amount: Decimal.new("1500"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :costs_recovery,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = SepaPenaltyProcessor.process_penalty(scraped)
      assert processed.offence_action_type == "SEPA Costs Recovery"
    end
  end
end
