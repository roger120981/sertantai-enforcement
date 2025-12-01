defmodule EhsEnforcement.Scraping.Opss.OpssNoticeProcessorTest do
  @moduledoc """
  Tests for OPSS notice processing pipeline.
  """

  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Opss.OpssNoticeProcessor
  alias EhsEnforcement.Scraping.Opss.OpssNoticeProcessor.ProcessedNotice
  alias EhsEnforcement.Scraping.Opss.OpssEnforcementScraper.ScrapedAction

  require Ash.Query

  describe "process_notice/1" do
    test "processes a Stop Notice action" do
      scraped = %ScrapedAction{
        business_name: "Test Business Ltd",
        action_type: "Stop Notice",
        action_date: ~D[2024-10-15],
        category: "Product Safety",
        products: "Electric scooter model X",
        breached_regulations: "General Product Safety Regulations 2005",
        detail: "Product failed safety testing",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
      }

      assert {:ok, %ProcessedNotice{} = processed} = OpssNoticeProcessor.process_notice(scraped)
      assert processed.agency_code == :opss
      assert processed.offence_action_type == "OPSS Stop Notice"
      assert processed.notice_date == ~D[2024-10-15]
      assert String.contains?(processed.notice_body, "Electric scooter model X")
      assert String.contains?(processed.notice_body, "General Product Safety Regulations")
    end

    test "processes a Prohibition Notice action" do
      scraped = %ScrapedAction{
        business_name: "Dangerous Goods Inc",
        action_type: "Prohibition Notice",
        action_date: ~D[2024-08-20],
        category: "Construction Products",
        products: "Unsafe scaffolding",
        breached_regulations: "Construction Products Regulations 2013",
        detail: "Did not meet EN standards",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      assert {:ok, %ProcessedNotice{} = processed} = OpssNoticeProcessor.process_notice(scraped)
      assert processed.offence_action_type == "OPSS Prohibition Notice"
      assert processed.notice_date == ~D[2024-08-20]
    end

    test "processes a Recall Notice action" do
      scraped = %ScrapedAction{
        business_name: "Consumer Products Co",
        action_type: "Recall Notice",
        action_date: ~D[2024-05-10],
        category: "Product Safety",
        products: "Children's toy with small parts",
        breached_regulations: "Toys (Safety) Regulations 2011",
        detail: "Choking hazard",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      assert {:ok, %ProcessedNotice{} = processed} = OpssNoticeProcessor.process_notice(scraped)
      assert processed.offence_action_type == "OPSS Recall Notice"
    end

    test "processes a Withdrawal Notice action" do
      scraped = %ScrapedAction{
        business_name: "Withdrawal Test Ltd",
        action_type: "Withdrawal Notice",
        action_date: ~D[2024-03-15],
        category: "Environmental Protection",
        products: "Non-compliant vacuum cleaner",
        breached_regulations: "Ecodesign for Energy-Related Products Regulations 2010",
        detail: "Energy efficiency below minimum standard",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-january-2024"
      }

      assert {:ok, %ProcessedNotice{} = processed} = OpssNoticeProcessor.process_notice(scraped)
      assert processed.offence_action_type == "OPSS Withdrawal Notice"
    end

    test "processes a Compliance Notice action" do
      scraped = %ScrapedAction{
        business_name: "Compliance Test Ltd",
        action_type: "Compliance Notice",
        action_date: ~D[2024-06-01],
        category: "Product Safety",
        products: "USB charger",
        breached_regulations: "Electrical Equipment (Safety) Regulations 2016",
        detail: "Missing CE marking",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      assert {:ok, %ProcessedNotice{} = processed} = OpssNoticeProcessor.process_notice(scraped)
      assert processed.offence_action_type == "OPSS Compliance Notice"
    end

    test "processes a Seizure Notice action" do
      scraped = %ScrapedAction{
        business_name: "Seized Goods Ltd",
        action_type: "Seizure Notice",
        action_date: ~D[2024-07-20],
        category: "Product Safety",
        products: "Counterfeit electronics",
        breached_regulations: "General Product Safety Regulations 2005",
        detail: "Seized at port of entry",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      assert {:ok, %ProcessedNotice{} = processed} = OpssNoticeProcessor.process_notice(scraped)
      assert processed.offence_action_type == "OPSS Seizure Notice"
    end

    test "generates deterministic regulator_id" do
      scraped = %ScrapedAction{
        business_name: "ID Test Company",
        action_type: "Stop Notice",
        action_date: ~D[2024-10-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "Test detail",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
      }

      {:ok, processed1} = OpssNoticeProcessor.process_notice(scraped)
      {:ok, processed2} = OpssNoticeProcessor.process_notice(scraped)

      assert processed1.regulator_id == processed2.regulator_id
      assert String.starts_with?(processed1.regulator_id, "opss_stop_")
    end

    test "builds offender attributes correctly" do
      scraped = %ScrapedAction{
        business_name: "Offender Test Ltd",
        action_type: "Stop Notice",
        action_date: ~D[2024-10-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
      }

      {:ok, processed} = OpssNoticeProcessor.process_notice(scraped)

      assert processed.offender_attrs.name == "Offender Test Ltd"
      assert processed.offender_attrs.country == "United Kingdom"
    end

    test "builds notice body with all relevant information" do
      scraped = %ScrapedAction{
        business_name: "Full Body Test Ltd",
        action_type: "Stop Notice",
        action_date: ~D[2024-10-15],
        category: "Product Safety",
        products: "Test product A, Test product B",
        breached_regulations: "Regulation 1, Regulation 2",
        detail: "Detailed information about the case",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
      }

      {:ok, processed} = OpssNoticeProcessor.process_notice(scraped)

      assert String.contains?(processed.notice_body, "Test product A, Test product B")
      assert String.contains?(processed.notice_body, "Regulation 1, Regulation 2")
      assert String.contains?(processed.notice_body, "Detailed information")
      assert String.contains?(processed.notice_body, "Product Safety")
    end

    test "includes source metadata" do
      scraped = %ScrapedAction{
        business_name: "Metadata Test Ltd",
        action_type: "Stop Notice",
        action_date: ~D[2024-10-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        scrape_timestamp: ~U[2024-10-20 10:30:00Z],
        period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
      }

      {:ok, processed} = OpssNoticeProcessor.process_notice(scraped)

      assert processed.source_metadata.scraped_at == ~U[2024-10-20 10:30:00Z]
      assert processed.source_metadata.source == "gov.uk"
      assert processed.source_metadata.category == "Product Safety"

      assert processed.source_metadata.period ==
               "opss-enforcement-actions-1-october-2024-to-31-march-2025"
    end

    test "handles missing date gracefully" do
      scraped = %ScrapedAction{
        business_name: "No Date Ltd",
        action_type: "Stop Notice",
        action_date: nil,
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
      }

      {:ok, processed} = OpssNoticeProcessor.process_notice(scraped)

      assert processed.notice_date == nil
      assert processed.offence_action_date == nil
    end
  end

  describe "process_notices/1" do
    test "processes multiple notices" do
      scraped_notices = [
        %ScrapedAction{
          business_name: "Company A",
          action_type: "Stop Notice",
          action_date: ~D[2024-10-15],
          category: "Product Safety",
          products: "Product A",
          breached_regulations: "Regulation A",
          detail: "",
          scrape_timestamp: DateTime.utc_now(),
          period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
        },
        %ScrapedAction{
          business_name: "Company B",
          action_type: "Prohibition Notice",
          action_date: ~D[2024-10-16],
          category: "Construction Products",
          products: "Product B",
          breached_regulations: "Regulation B",
          detail: "",
          scrape_timestamp: DateTime.utc_now(),
          period: "opss-enforcement-actions-1-october-2024-to-31-march-2025"
        }
      ]

      assert {:ok, processed_list} = OpssNoticeProcessor.process_notices(scraped_notices)
      assert length(processed_list) == 2

      [first, second] = processed_list
      assert first.offender_attrs.name == "Company A"
      assert second.offender_attrs.name == "Company B"
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = OpssNoticeProcessor.process_notices([])
    end
  end

  describe "is_notice?/1" do
    test "returns true for notice types" do
      assert OpssNoticeProcessor.is_notice?("Stop Notice") == true
      assert OpssNoticeProcessor.is_notice?("Prohibition Notice") == true
      assert OpssNoticeProcessor.is_notice?("Recall Notice") == true
      assert OpssNoticeProcessor.is_notice?("Withdrawal Notice") == true
      assert OpssNoticeProcessor.is_notice?("Compliance Notice") == true
      assert OpssNoticeProcessor.is_notice?("Seizure Notice") == true
    end

    test "returns false for prosecution" do
      assert OpssNoticeProcessor.is_notice?("Prosecution") == false
    end

    test "returns false for unknown types" do
      assert OpssNoticeProcessor.is_notice?("Unknown") == false
    end
  end

  describe "filter_notices/1" do
    test "filters out prosecution actions" do
      actions = [
        %ScrapedAction{
          business_name: "Notice Company",
          action_type: "Stop Notice",
          action_date: ~D[2024-10-15],
          category: "Product Safety",
          products: "Product",
          breached_regulations: "Regulation",
          detail: "",
          scrape_timestamp: DateTime.utc_now(),
          period: "test-period"
        },
        %ScrapedAction{
          business_name: "Prosecution Company",
          action_type: "Prosecution",
          action_date: ~D[2024-10-16],
          category: "Product Safety",
          products: "Product",
          breached_regulations: "Regulation",
          detail: "",
          fine: 50000,
          court: "Crown Court",
          scrape_timestamp: DateTime.utc_now(),
          period: "test-period"
        }
      ]

      notices = OpssNoticeProcessor.filter_notices(actions)

      assert length(notices) == 1
      assert hd(notices).action_type == "Stop Notice"
    end
  end
end
