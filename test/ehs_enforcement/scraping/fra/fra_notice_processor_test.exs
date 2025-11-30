defmodule EhsEnforcement.Scraping.Fra.FraNoticeProcessorTest do
  use EhsEnforcement.DataCase, async: true

  alias EhsEnforcement.Scraping.Fra.FraNoticeProcessor
  alias EhsEnforcement.Scraping.Fra.FraNoticeProcessor.ProcessedNotice
  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper.ScrapedNotice

  require Ash.Query

  describe "process_notice/1" do
    test "transforms scraped notice to processed format" do
      scraped = build_scraped_notice()

      assert {:ok, %ProcessedNotice{} = processed} = FraNoticeProcessor.process_notice(scraped)

      assert processed.agency_code == :fra
      assert processed.regulator_id =~ ~r/^fra_\d+_\d{8}_E$/
      assert processed.notice_date == ~D[2025-11-06]
      assert processed.offence_action_type == "FRA Enforcement Notice"
      assert processed.offender_attrs.name == "Usman Ahmed T/A F1 Tyres"
      assert processed.offender_attrs.country == "England"
    end

    test "generates deterministic regulator_id using UPRN" do
      scraped = build_scraped_notice(%{uprn: "12345678"})

      {:ok, processed1} = FraNoticeProcessor.process_notice(scraped)
      {:ok, processed2} = FraNoticeProcessor.process_notice(scraped)

      assert processed1.regulator_id == processed2.regulator_id
      assert processed1.regulator_id == "fra_12345678_20251106_E"
    end

    test "maps notice types correctly" do
      prohibition = build_scraped_notice(%{notice_type: "PROHIBITION"})
      enforcement = build_scraped_notice(%{notice_type: "ENFORCEMENT"})
      alterations = build_scraped_notice(%{notice_type: "ALTERATIONS"})

      {:ok, p1} = FraNoticeProcessor.process_notice(prohibition)
      {:ok, p2} = FraNoticeProcessor.process_notice(enforcement)
      {:ok, p3} = FraNoticeProcessor.process_notice(alterations)

      assert p1.offence_action_type == "FRA Prohibition Notice"
      assert p2.offence_action_type == "FRA Enforcement Notice"
      assert p3.offence_action_type == "FRA Alterations Notice"
      assert p1.regulator_id =~ ~r/_P$/
      assert p2.regulator_id =~ ~r/_E$/
      assert p3.regulator_id =~ ~r/_A$/
    end

    test "determines country from FRS name - Welsh services" do
      welsh_frs = [
        "Mid and West Wales",
        "North Wales",
        "South Wales"
      ]

      for frs <- welsh_frs do
        scraped = build_scraped_notice(%{frs: frs})
        {:ok, processed} = FraNoticeProcessor.process_notice(scraped)
        assert processed.offender_attrs.country == "Wales", "Expected Wales for #{frs}"
      end
    end

    test "determines country from FRS name - English services" do
      english_frs = [
        "West Yorkshire",
        "London Fire Brigade",
        "Greater Manchester",
        "Dorset and Wiltshire"
      ]

      for frs <- english_frs do
        scraped = build_scraped_notice(%{frs: frs})
        {:ok, processed} = FraNoticeProcessor.process_notice(scraped)
        assert processed.offender_attrs.country == "England", "Expected England for #{frs}"
      end
    end

    test "extracts postcode from address" do
      scraped =
        build_scraped_notice(%{
          address: "123 High Street, Leeds, LS1 2AB"
        })

      {:ok, processed} = FraNoticeProcessor.process_notice(scraped)
      assert processed.offender_attrs.postcode == "LS1 2AB"
    end

    test "handles missing postcode" do
      scraped =
        build_scraped_notice(%{
          address: "Unknown Location, Somewhere"
        })

      {:ok, processed} = FraNoticeProcessor.process_notice(scraped)
      assert is_nil(processed.offender_attrs.postcode)
    end

    test "builds notice body from reasons and metadata" do
      scraped =
        build_scraped_notice(%{
          reasons: "Fire exits blocked. No fire alarm.",
          status: "IN FORCE",
          premises_type: "SHOP"
        })

      {:ok, processed} = FraNoticeProcessor.process_notice(scraped)

      assert processed.notice_body =~ "Fire exits blocked"
      assert processed.notice_body =~ "[Status: IN FORCE]"
      assert processed.notice_body =~ "[Premises: SHOP]"
    end

    test "parses DD/MM/YYYY date format" do
      scraped = build_scraped_notice(%{issue_date: "25/12/2024"})

      {:ok, processed} = FraNoticeProcessor.process_notice(scraped)
      assert processed.notice_date == ~D[2024-12-25]
    end

    test "handles nil date gracefully" do
      scraped = build_scraped_notice(%{issue_date: nil})

      {:ok, processed} = FraNoticeProcessor.process_notice(scraped)
      assert is_nil(processed.notice_date)
    end

    test "stores source metadata" do
      scraped = build_scraped_notice()

      {:ok, processed} = FraNoticeProcessor.process_notice(scraped)

      assert processed.source_metadata.source == "nfcc.org.uk"
      assert processed.source_metadata.uprn == scraped.uprn
      assert processed.source_metadata.frs == scraped.frs
      assert processed.source_metadata.premises_type == scraped.premises_type
      assert processed.source_metadata.status == scraped.status
    end
  end

  describe "process_notices/1" do
    test "processes multiple notices" do
      notices = [
        build_scraped_notice(%{uprn: "111"}),
        build_scraped_notice(%{uprn: "222"}),
        build_scraped_notice(%{uprn: "333"})
      ]

      assert {:ok, processed} = FraNoticeProcessor.process_notices(notices)
      assert length(processed) == 3
    end
  end

  describe "process_and_create_notice/2" do
    setup do
      # Create FRA agency for tests
      {:ok, agency} =
        EhsEnforcement.Enforcement.Agency
        |> Ash.Changeset.for_create(:create, %{
          code: :fra,
          name: "Fire and Rescue Authorities (NFCC)",
          base_url: "https://nfcc.org.uk",
          enabled: true
        })
        |> Ash.create()

      %{agency: agency}
    end

    test "creates notice in database", %{agency: _agency} do
      scraped = build_scraped_notice(%{uprn: "test_#{System.unique_integer([:positive])}"})

      assert {:ok, notice} = FraNoticeProcessor.process_and_create_notice(scraped, nil)

      assert notice.regulator_id =~ ~r/^fra_/
      assert notice.offence_action_type == "FRA Enforcement Notice"
      assert notice.agency_id != nil
      assert notice.offender_id != nil
    end

    test "creates offender with correct attributes", %{agency: _agency} do
      scraped =
        build_scraped_notice(%{
          uprn: "test_offender_#{System.unique_integer([:positive])}",
          responsible_person: "Test Fire Safety Ltd",
          address: "456 Test Street, Manchester, M1 2CD",
          frs: "Greater Manchester"
        })

      {:ok, notice} = FraNoticeProcessor.process_and_create_notice(scraped, nil)

      # Load the offender
      {:ok, offender} = Ash.get(EhsEnforcement.Enforcement.Offender, notice.offender_id)

      assert offender.name == "Test Fire Safety Ltd"
      assert offender.address == "456 Test Street, Manchester, M1 2CD"
      assert offender.postcode == "M1 2CD"
      assert offender.country == "England"
    end

    test "rejects duplicate notices", %{agency: _agency} do
      uprn = "duplicate_test_#{System.unique_integer([:positive])}"
      scraped = build_scraped_notice(%{uprn: uprn})

      # First creation should succeed
      assert {:ok, _notice1} = FraNoticeProcessor.process_and_create_notice(scraped, nil)

      # Second creation with same UPRN/date/type should fail (duplicate regulator_id)
      assert {:error, _reason} = FraNoticeProcessor.process_and_create_notice(scraped, nil)
    end
  end

  # Helper functions

  defp build_scraped_notice(overrides \\ %{}) do
    defaults = %{
      uprn: "83224833",
      frs: "West Yorkshire",
      issue_date: "06/11/2025",
      notice_type: "ENFORCEMENT",
      premises_type: "FACTORY WAREHOUSE",
      status: "IN FORCE",
      address: "F1 Tyres, Ratcliffe Mills, Forge Lane, Thornhill Lees, Dewsbury, WF12 9BU",
      responsible_person: "Usman Ahmed T/A F1 Tyres",
      date_complied_with: nil,
      reasons: "A8,A9,A11,A13,A14,A15,A17,A19,A21",
      additional_information: nil,
      scrape_timestamp: DateTime.utc_now()
    }

    merged = Map.merge(defaults, overrides)

    struct(ScrapedNotice, merged)
  end
end
