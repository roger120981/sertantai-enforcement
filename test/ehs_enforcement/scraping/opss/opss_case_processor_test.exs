defmodule EhsEnforcement.Scraping.Opss.OpssCaseProcessorTest do
  @moduledoc """
  Tests for OPSS case (prosecution) processing pipeline.
  """

  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Opss.OpssCaseProcessor
  alias EhsEnforcement.Scraping.Opss.OpssCaseProcessor.ProcessedCase
  alias EhsEnforcement.Scraping.Opss.OpssEnforcementScraper.ScrapedAction

  require Ash.Query

  describe "process_case/1" do
    test "processes a prosecution action with fine" do
      scraped = %ScrapedAction{
        business_name: "Dangerous Toys Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Children's toys with excessive lead paint",
        breached_regulations: "General Product Safety Regulations 2005",
        detail: "Company sold toys exceeding lead limits",
        fine: 50000,
        costs: 12500,
        confiscation: nil,
        court: "Manchester Crown Court",
        imprisonment: nil,
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      assert {:ok, %ProcessedCase{} = processed} = OpssCaseProcessor.process_case(scraped)
      assert processed.agency_code == :opss
      assert processed.offence_action_type == "OPSS Prosecution"
      assert processed.offence_hearing_date == ~D[2024-06-15]
      assert processed.offence_fine == 50000
      assert processed.offence_costs == 12500
      assert String.contains?(processed.offence_result, "Children's toys")
      assert String.contains?(processed.offence_breaches, "General Product Safety Regulations")
    end

    test "processes a prosecution with imprisonment" do
      scraped = %ScrapedAction{
        business_name: "Reckless Importer Inc",
        action_type: "Prosecution",
        action_date: ~D[2024-03-20],
        category: "Product Safety",
        products: "Unsafe electrical appliances",
        breached_regulations: "Electrical Equipment (Safety) Regulations 2016",
        detail: "Director knowingly imported and sold dangerous appliances",
        fine: 100_000,
        costs: 25000,
        confiscation: 75000,
        court: "Southwark Crown Court",
        imprisonment: "18 months suspended",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-january-2024"
      }

      assert {:ok, %ProcessedCase{} = processed} = OpssCaseProcessor.process_case(scraped)
      assert processed.offence_fine == 100_000
      assert processed.offence_costs == 25000
      assert String.contains?(processed.offence_result, "18 months suspended")
      assert String.contains?(processed.offence_result, "Confiscation: 75000")
    end

    test "processes a prosecution with confiscation order" do
      scraped = %ScrapedAction{
        business_name: "Counterfeit Goods Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-01-10],
        category: "Product Safety",
        products: "Counterfeit electronics",
        breached_regulations: "General Product Safety Regulations 2005",
        detail: "Selling counterfeit products online",
        fine: 30000,
        costs: 8000,
        confiscation: 150_000,
        court: "Birmingham Crown Court",
        imprisonment: nil,
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-january-2024"
      }

      assert {:ok, %ProcessedCase{} = processed} = OpssCaseProcessor.process_case(scraped)
      assert String.contains?(processed.offence_result, "Confiscation: 150000")
    end

    test "generates deterministic regulator_id" do
      scraped = %ScrapedAction{
        business_name: "ID Test Company",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "Test detail",
        fine: 10000,
        costs: 5000,
        confiscation: nil,
        court: "Test Court",
        imprisonment: nil,
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed1} = OpssCaseProcessor.process_case(scraped)
      {:ok, processed2} = OpssCaseProcessor.process_case(scraped)

      assert processed1.regulator_id == processed2.regulator_id
      assert String.starts_with?(processed1.regulator_id, "opss_prosecution_")
    end

    test "builds offender attributes correctly" do
      scraped = %ScrapedAction{
        business_name: "Offender Test Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        fine: 5000,
        costs: 1000,
        confiscation: nil,
        court: "Test Court",
        imprisonment: nil,
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed} = OpssCaseProcessor.process_case(scraped)

      assert processed.offender_attrs.name == "Offender Test Ltd"
      assert processed.offender_attrs.country == "United Kingdom"
    end

    test "builds offence result with all relevant information" do
      scraped = %ScrapedAction{
        business_name: "Full Result Test Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Dangerous product A, Dangerous product B",
        breached_regulations: "Regulation 1, Regulation 2",
        detail: "Detailed information about the prosecution case",
        fine: 75000,
        costs: 15000,
        confiscation: 50000,
        court: "Crown Court",
        imprisonment: "12 months suspended",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed} = OpssCaseProcessor.process_case(scraped)

      assert String.contains?(processed.offence_result, "Dangerous product A")
      assert String.contains?(processed.offence_result, "Detailed information")
      assert String.contains?(processed.offence_result, "12 months suspended")
      assert String.contains?(processed.offence_result, "Confiscation: 50000")
    end

    test "includes court in offence_breaches" do
      scraped = %ScrapedAction{
        business_name: "Court Test Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "General Product Safety Regulations 2005",
        detail: "",
        fine: 5000,
        costs: 1000,
        confiscation: nil,
        court: "Liverpool Crown Court",
        imprisonment: nil,
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed} = OpssCaseProcessor.process_case(scraped)

      assert String.contains?(processed.offence_breaches, "Liverpool Crown Court")
      assert String.contains?(processed.offence_breaches, "General Product Safety Regulations")
    end

    test "includes source metadata" do
      scraped = %ScrapedAction{
        business_name: "Metadata Test Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        fine: 5000,
        costs: 1000,
        confiscation: nil,
        court: "Test Court",
        imprisonment: nil,
        scrape_timestamp: ~U[2024-06-20 10:30:00Z],
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed} = OpssCaseProcessor.process_case(scraped)

      assert processed.source_metadata.scraped_at == ~U[2024-06-20 10:30:00Z]
      assert processed.source_metadata.source == "gov.uk"
      assert processed.source_metadata.category == "Product Safety"
      assert processed.source_metadata.court == "Test Court"

      assert processed.source_metadata.period ==
               "opss-enforcement-actions-1-april-2024-to-30-september-2024"
    end

    test "handles missing date gracefully" do
      scraped = %ScrapedAction{
        business_name: "No Date Ltd",
        action_type: "Prosecution",
        action_date: nil,
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        fine: 5000,
        costs: 1000,
        confiscation: nil,
        court: "Test Court",
        imprisonment: nil,
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed} = OpssCaseProcessor.process_case(scraped)

      assert processed.offence_hearing_date == nil
      assert processed.offence_action_date == nil
    end

    test "handles missing fine gracefully" do
      scraped = %ScrapedAction{
        business_name: "No Fine Ltd",
        action_type: "Prosecution",
        action_date: ~D[2024-06-15],
        category: "Product Safety",
        products: "Test product",
        breached_regulations: "Test regulation",
        detail: "",
        fine: nil,
        costs: nil,
        confiscation: nil,
        court: "Test Court",
        imprisonment: "6 months suspended",
        scrape_timestamp: DateTime.utc_now(),
        period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
      }

      {:ok, processed} = OpssCaseProcessor.process_case(scraped)

      assert processed.offence_fine == nil
      assert processed.offence_costs == nil
      assert String.contains?(processed.offence_result, "6 months suspended")
    end
  end

  describe "process_cases/1" do
    test "processes multiple prosecutions" do
      scraped_cases = [
        %ScrapedAction{
          business_name: "Company A",
          action_type: "Prosecution",
          action_date: ~D[2024-06-15],
          category: "Product Safety",
          products: "Product A",
          breached_regulations: "Regulation A",
          detail: "",
          fine: 10000,
          costs: 2000,
          confiscation: nil,
          court: "Court A",
          imprisonment: nil,
          scrape_timestamp: DateTime.utc_now(),
          period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
        },
        %ScrapedAction{
          business_name: "Company B",
          action_type: "Prosecution",
          action_date: ~D[2024-06-16],
          category: "Construction Products",
          products: "Product B",
          breached_regulations: "Regulation B",
          detail: "",
          fine: 20000,
          costs: 4000,
          confiscation: nil,
          court: "Court B",
          imprisonment: nil,
          scrape_timestamp: DateTime.utc_now(),
          period: "opss-enforcement-actions-1-april-2024-to-30-september-2024"
        }
      ]

      assert {:ok, processed_list} = OpssCaseProcessor.process_cases(scraped_cases)
      assert length(processed_list) == 2

      [first, second] = processed_list
      assert first.offender_attrs.name == "Company A"
      assert second.offender_attrs.name == "Company B"
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = OpssCaseProcessor.process_cases([])
    end

    test "filters out non-prosecution actions" do
      actions = [
        %ScrapedAction{
          business_name: "Prosecution Company",
          action_type: "Prosecution",
          action_date: ~D[2024-06-15],
          category: "Product Safety",
          products: "Product",
          breached_regulations: "Regulation",
          detail: "",
          fine: 50000,
          costs: 10000,
          confiscation: nil,
          court: "Crown Court",
          imprisonment: nil,
          scrape_timestamp: DateTime.utc_now(),
          period: "test-period"
        },
        %ScrapedAction{
          business_name: "Notice Company",
          action_type: "Stop Notice",
          action_date: ~D[2024-06-16],
          category: "Product Safety",
          products: "Product",
          breached_regulations: "Regulation",
          detail: "",
          fine: nil,
          costs: nil,
          confiscation: nil,
          court: nil,
          imprisonment: nil,
          scrape_timestamp: DateTime.utc_now(),
          period: "test-period"
        }
      ]

      {:ok, processed_list} = OpssCaseProcessor.process_cases(actions)

      assert length(processed_list) == 1
      assert hd(processed_list).offender_attrs.name == "Prosecution Company"
    end
  end

  describe "is_prosecution?/1" do
    test "returns true for prosecution type" do
      assert OpssCaseProcessor.is_prosecution?("Prosecution") == true
    end

    test "returns false for notice types" do
      assert OpssCaseProcessor.is_prosecution?("Stop Notice") == false
      assert OpssCaseProcessor.is_prosecution?("Prohibition Notice") == false
      assert OpssCaseProcessor.is_prosecution?("Recall Notice") == false
      assert OpssCaseProcessor.is_prosecution?("Withdrawal Notice") == false
      assert OpssCaseProcessor.is_prosecution?("Compliance Notice") == false
      assert OpssCaseProcessor.is_prosecution?("Seizure Notice") == false
    end

    test "returns false for unknown types" do
      assert OpssCaseProcessor.is_prosecution?("Unknown") == false
    end
  end

  describe "filter_prosecutions/1" do
    test "filters to only prosecution actions" do
      actions = [
        %ScrapedAction{
          business_name: "Notice Company",
          action_type: "Stop Notice",
          action_date: ~D[2024-06-15],
          category: "Product Safety",
          products: "Product",
          breached_regulations: "Regulation",
          detail: "",
          fine: nil,
          costs: nil,
          confiscation: nil,
          court: nil,
          imprisonment: nil,
          scrape_timestamp: DateTime.utc_now(),
          period: "test-period"
        },
        %ScrapedAction{
          business_name: "Prosecution Company",
          action_type: "Prosecution",
          action_date: ~D[2024-06-16],
          category: "Product Safety",
          products: "Product",
          breached_regulations: "Regulation",
          detail: "",
          fine: 50000,
          costs: 10000,
          confiscation: nil,
          court: "Crown Court",
          imprisonment: nil,
          scrape_timestamp: DateTime.utc_now(),
          period: "test-period"
        }
      ]

      prosecutions = OpssCaseProcessor.filter_prosecutions(actions)

      assert length(prosecutions) == 1
      assert hd(prosecutions).action_type == "Prosecution"
    end
  end
end
