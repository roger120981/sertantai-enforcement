defmodule EhsEnforcement.Scraping.Sepa.IntegrationTest do
  @moduledoc """
  Integration tests for SEPA penalty scraping.

  Tests the full pipeline from scraped data to database persistence,
  verifying that all tables (notices, offenders) are properly populated.
  """
  use EhsEnforcement.DataCase

  require Ash.Query
  import Ash.Expr

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.{Notice, Offender, Agency}
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper.ScrapedPenalty
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyProcessor

  setup do
    # Create SEPA agency for tests
    {:ok, agency} =
      Ash.create(Agency, %{
        name: "Scottish Environment Protection Agency",
        code: :sepa,
        base_url: "https://beta.sepa.scot"
      })

    %{agency: agency}
  end

  describe "process_and_create_penalty/2" do
    test "creates notice in database", %{agency: agency} do
      scraped =
        build_scraped_penalty(%{
          name_and_address: "Integration Test Ltd, Edinburgh, EH1 1AA",
          penalty_amount: Decimal.new("600")
        })

      assert {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      # Verify notice was persisted
      assert {:ok, [db_notice]} =
               Notice
               |> Ash.Query.filter(id == ^notice.id)
               |> Ash.read()

      assert db_notice.agency_id == agency.id
      assert db_notice.penalty_amount == Decimal.new("600")
      assert db_notice.offence_action_type == "SEPA FMP £600"
      assert String.starts_with?(db_notice.regulator_id, "sepa_")
    end

    test "creates offender in database", %{agency: _agency} do
      scraped =
        build_scraped_penalty(%{
          name_and_address: "New Offender Company, Glasgow, G1 2AB"
        })

      assert {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      # Verify offender was created
      assert {:ok, [offender]} =
               Offender
               |> Ash.Query.filter(id == ^notice.offender_id)
               |> Ash.read()

      assert offender.name == "New Offender Company"
      assert offender.country == "Scotland"
      assert offender.postcode == "G1 2AB"
    end

    test "reuses existing offender with same name", %{agency: _agency} do
      # Create first penalty for this offender
      scraped1 =
        build_scraped_penalty(%{
          name_and_address: "Repeat Offender Ltd, Aberdeen, AB10 1CD",
          date: "15 March 2025",
          penalty_amount: Decimal.new("600")
        })

      {:ok, notice1} = SepaPenaltyProcessor.process_and_create_penalty(scraped1, nil)

      # Create second penalty for same offender (different date)
      scraped2 =
        build_scraped_penalty(%{
          name_and_address: "Repeat Offender Ltd, Aberdeen, AB10 1CD",
          date: "20 April 2025",
          penalty_amount: Decimal.new("300")
        })

      {:ok, notice2} = SepaPenaltyProcessor.process_and_create_penalty(scraped2, nil)

      # Should use same offender
      assert notice1.offender_id == notice2.offender_id

      # Verify only one offender exists with this name
      {:ok, offenders} =
        Offender
        |> Ash.Query.filter(name == "Repeat Offender Ltd")
        |> Ash.read()

      assert length(offenders) == 1
    end

    test "prevents duplicate notices via regulator_id", %{agency: _agency} do
      scraped =
        build_scraped_penalty(%{
          name_and_address: "Duplicate Test Ltd, Edinburgh, EH1",
          date: "15 March 2025",
          penalty_amount: Decimal.new("600")
        })

      # First creation should succeed
      {:ok, notice1} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      # Second creation with same data should fail (duplicate regulator_id)
      result = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      # Should get an error due to unique constraint
      assert match?({:error, _}, result)

      # Verify only one notice exists
      {:ok, notices} =
        Notice
        |> Ash.Query.filter(regulator_id == ^notice1.regulator_id)
        |> Ash.read()

      assert length(notices) == 1
    end

    test "stores penalty_amount correctly for different amounts", %{agency: _agency} do
      test_cases = [
        {"300", Decimal.new("300")},
        {"600", Decimal.new("600")},
        {"1000", Decimal.new("1000")},
        {"2500.50", Decimal.new("2500.50")}
      ]

      for {{amount_str, expected_amount}, index} <- Enum.with_index(test_cases) do
        scraped =
          build_scraped_penalty(%{
            name_and_address: "Amount Test #{index}, Location, AB#{index}",
            date: "#{10 + index} March 2025",
            penalty_amount: Decimal.new(amount_str)
          })

        {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

        assert notice.penalty_amount == expected_amount
      end
    end

    test "stores nil penalty_amount for undertakings", %{agency: _agency} do
      scraped = %ScrapedPenalty{
        penalty_type: "Enforcement undertaking",
        name_and_address: "Undertaking Company, Inverness, IV1",
        date: "1 April 2025",
        offence_details: "Failed to comply with permit conditions",
        penalty_amount: nil,
        documentation_url: "https://example.com/doc.pdf",
        legislation_breached: "The Pollution Prevention and Control (Scotland) Regulations 2012",
        year: 2025,
        section_type: :undertakings,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      assert is_nil(notice.penalty_amount)
      assert notice.offence_action_type == "SEPA Undertaking"

      assert notice.offence_breaches ==
               "The Pollution Prevention and Control (Scotland) Regulations 2012"
    end

    test "stores offence details in notice_body", %{agency: _agency} do
      offence_text =
        "Environmental Protection Act 1990. Section 33 - Deposit of controlled waste without an authorisation."

      scraped =
        build_scraped_penalty(%{
          name_and_address: "Body Test Ltd, Perth, PH1",
          offence_details: offence_text
        })

      {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      assert notice.notice_body == offence_text
    end

    test "stores URL when documentation link is present", %{agency: _agency} do
      scraped =
        build_scraped_penalty(%{
          name_and_address: "URL Test Ltd, Dundee, DD1",
          documentation_url: "https://example.com/penalty-doc.pdf"
        })

      {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      assert notice.url == "https://example.com/penalty-doc.pdf"
    end
  end

  describe "offender data integrity" do
    test "extracts postcode from address correctly", %{agency: _agency} do
      test_cases = [
        {"Company A, Edinburgh, EH1 1AA", "EH1 1AA"},
        {"Company B, Glasgow, G1 2AB", "G1 2AB"},
        {"Company C, Aberdeen, AB10", "AB10"},
        {"Company D, Dundee, DD1 4EF", "DD1 4EF"}
      ]

      for {{name_address, expected_postcode}, index} <- Enum.with_index(test_cases) do
        scraped =
          build_scraped_penalty(%{
            name_and_address: name_address,
            date: "#{10 + index} March 2025"
          })

        {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

        {:ok, [offender]} =
          Offender
          |> Ash.Query.filter(id == ^notice.offender_id)
          |> Ash.read()

        assert offender.postcode == expected_postcode,
               "Expected postcode #{expected_postcode} for #{name_address}, got #{offender.postcode}"
      end
    end

    test "all offenders get Scotland as country", %{agency: _agency} do
      scraped =
        build_scraped_penalty(%{
          name_and_address: "Scottish Company, Inverness, IV1"
        })

      {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      {:ok, [offender]} =
        Offender
        |> Ash.Query.filter(id == ^notice.offender_id)
        |> Ash.read()

      assert offender.country == "Scotland"
    end
  end

  describe "notice-agency relationship" do
    test "notice is associated with SEPA agency", %{agency: agency} do
      scraped =
        build_scraped_penalty(%{
          name_and_address: "Agency Test Ltd, Edinburgh, EH1"
        })

      {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

      # Load agency relationship
      {:ok, notice_with_agency} = Ash.load(notice, :agency)

      assert notice_with_agency.agency.id == agency.id
      assert notice_with_agency.agency.code == :sepa
      assert notice_with_agency.agency.name == "Scottish Environment Protection Agency"
    end
  end

  describe "date handling" do
    test "stores notice_date correctly for various date formats", %{agency: _agency} do
      test_cases = [
        {"16 July 2025", ~D[2025-07-16]},
        {"9 January 2025", ~D[2025-01-09]},
        {"1 April 2025", ~D[2025-04-01]},
        {"31 December 2024", ~D[2024-12-31]}
      ]

      for {{date_str, expected_date}, index} <- Enum.with_index(test_cases) do
        scraped =
          build_scraped_penalty(%{
            name_and_address: "Date Test #{index}, Location, AB#{index}",
            date: date_str
          })

        {:ok, notice} = SepaPenaltyProcessor.process_and_create_penalty(scraped, nil)

        assert notice.notice_date == expected_date,
               "Expected #{expected_date} for '#{date_str}', got #{notice.notice_date}"
      end
    end
  end

  # Helper function to build a scraped penalty with defaults
  defp build_scraped_penalty(overrides \\ %{}) do
    defaults = %{
      penalty_type: "Fixed monetary penalty",
      name_and_address: "Default Company Ltd, Edinburgh, EH1 1AA",
      date: "15 March 2025",
      offence_details: "Environmental Protection Act 1990. Section 33 - Test offence.",
      penalty_amount: Decimal.new("600"),
      documentation_url: nil,
      legislation_breached: nil,
      year: 2025,
      section_type: :penalties,
      scrape_timestamp: DateTime.utc_now()
    }

    struct(ScrapedPenalty, Map.merge(defaults, overrides))
  end
end
