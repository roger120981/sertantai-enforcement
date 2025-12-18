defmodule EhsEnforcement.Scraping.Ea.NoticeLegislationTest do
  @moduledoc """
  Tests for EA notice legislation linking.

  These tests verify that when EA notices are processed, the legislation
  and offences tables are populated correctly.
  """
  use EhsEnforcement.DataCase

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Scraping.Ea.NoticeProcessor
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

  describe "process_and_create_notice/2 legislation linking" do
    test "creates notice with offence and legislation from legal_act and legal_section", %{
      agency: _agency
    } do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_001",
        offender_name: "Test Environmental Company Ltd",
        action_date: ~D[2023-06-15],
        action_type: :enforcement_notice,
        act: "Environmental Permitting (England and Wales) Regulations 2016",
        section: "Reg 36 - Comply with conditions and remedy pollution",
        company_registration_number: "12345678",
        address: "123 Test Street",
        town: "London",
        postcode: "SW1A 1AA",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_001"
      }

      assert {:ok, notice, _status} = NoticeProcessor.process_and_create_notice(ea_detail, nil)

      # Verify notice was created
      assert notice.regulator_id == "EA_NOTICE_001"

      # Verify offence was created and linked to notice
      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(notice_id == ^notice.id)
        |> Ash.read()

      assert length(offences) == 1, "Expected 1 offence to be created for the notice"

      offence = List.first(offences)
      assert offence.notice_id == notice.id
      assert offence.legislation_part == "Reg 36 - Comply with conditions and remedy pollution"

      # Verify legislation was created
      assert offence.legislation_id != nil, "Expected legislation_id to be set on offence"

      {:ok, legislation} = Ash.get(Enforcement.Legislation, offence.legislation_id)

      # Title normalized (year stripped)
      assert legislation.legislation_title ==
               "Environmental Permitting (England and Wales) Regulations"

      assert legislation.legislation_year == 2016
      assert legislation.legislation_type == :regulation
    end

    test "creates legislation table entry when processing EA notice with legal_act", %{
      agency: _agency
    } do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_002",
        offender_name: "Water Pollution Company Ltd",
        action_date: ~D[2023-07-20],
        action_type: :enforcement_notice,
        act: "Water Resources Act 1991",
        section: "Section 85(1)",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_002"
      }

      # Get legislation count before
      {:ok, legislation_before} = Ash.read(Enforcement.Legislation)
      count_before = length(legislation_before)

      assert {:ok, notice, _status} = NoticeProcessor.process_and_create_notice(ea_detail, nil)

      # Verify legislation was created
      {:ok, legislation_after} = Ash.read(Enforcement.Legislation)
      count_after = length(legislation_after)

      assert count_after > count_before, "Expected legislation table to have new entries"

      # Find the legislation we just created (title normalized - no year)
      {:ok, [legislation]} =
        Enforcement.Legislation
        |> Ash.Query.filter(legislation_title == "Water Resources Act")
        |> Ash.read()

      assert legislation.legislation_year == 1991
      assert legislation.legislation_type == :act
    end

    test "creates offences table entry when processing EA notice", %{agency: _agency} do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_003",
        offender_name: "Waste Disposal Company Ltd",
        action_date: ~D[2023-08-10],
        action_type: :enforcement_notice,
        act: "Environmental Protection Act 1990",
        section: "Section 33",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_003"
      }

      # Get offences count before
      {:ok, offences_before} = Ash.read(Enforcement.Offence)
      count_before = length(offences_before)

      assert {:ok, notice, _status} = NoticeProcessor.process_and_create_notice(ea_detail, nil)

      # Verify offence was created
      {:ok, offences_after} = Ash.read(Enforcement.Offence)
      count_after = length(offences_after)

      assert count_after > count_before, "Expected offences table to have new entries"

      # Find the offence linked to our notice
      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(notice_id == ^notice.id)
        |> Ash.read()

      assert length(offences) == 1
      offence = List.first(offences)
      assert offence.legislation_part == "Section 33"
    end

    test "handles EA notice without legal_act gracefully", %{agency: _agency} do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_004",
        offender_name: "No Legislation Company Ltd",
        action_date: ~D[2023-09-05],
        action_type: :enforcement_notice,
        act: nil,
        section: nil,
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_004"
      }

      # Should still create notice successfully
      assert {:ok, notice, _status} = NoticeProcessor.process_and_create_notice(ea_detail, nil)
      assert notice.regulator_id == "EA_NOTICE_004"

      # No offence should be created (no legislation to link)
      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(notice_id == ^notice.id)
        |> Ash.read()

      assert offences == []
    end

    test "reuses existing legislation for multiple notices with same Act", %{agency: _agency} do
      # Create first notice
      ea_detail_1 = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_REUSE_001",
        offender_name: "First Notice Company Ltd",
        action_date: ~D[2023-10-01],
        action_type: :enforcement_notice,
        act: "Environmental Permitting (England and Wales) Regulations 2016",
        section: "Regulation 36",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_REUSE_001"
      }

      assert {:ok, notice_1, _status} =
               NoticeProcessor.process_and_create_notice(ea_detail_1, nil)

      # Create second notice with same Act
      ea_detail_2 = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_REUSE_002",
        offender_name: "Second Notice Company Ltd",
        action_date: ~D[2023-10-15],
        action_type: :enforcement_notice,
        act: "Environmental Permitting (England and Wales) Regulations 2016",
        section: "Regulation 38",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_REUSE_002"
      }

      assert {:ok, notice_2, _status} =
               NoticeProcessor.process_and_create_notice(ea_detail_2, nil)

      # Get offences for both notices
      {:ok, offences_1} =
        Enforcement.Offence
        |> Ash.Query.filter(notice_id == ^notice_1.id)
        |> Ash.read()

      {:ok, offences_2} =
        Enforcement.Offence
        |> Ash.Query.filter(notice_id == ^notice_2.id)
        |> Ash.read()

      assert length(offences_1) == 1
      assert length(offences_2) == 1

      offence_1 = List.first(offences_1)
      offence_2 = List.first(offences_2)

      # Should reference the same legislation
      assert offence_1.legislation_id == offence_2.legislation_id

      # But different sections
      assert offence_1.legislation_part == "Regulation 36"
      assert offence_2.legislation_part == "Regulation 38"

      # Verify only one Legislation record exists for this Act (title normalized - no year)
      {:ok, legislations} =
        Enforcement.Legislation
        |> Ash.Query.filter(
          legislation_title == "Environmental Permitting (England and Wales) Regulations"
        )
        |> Ash.read()

      assert length(legislations) == 1
    end
  end

  describe "process_and_create_notice_with_status/2 legislation linking" do
    test "creates notice with legislation linking via status wrapper", %{agency: _agency} do
      ea_detail = %EaDetailRecord{
        ea_record_id: "EA_NOTICE_STATUS_001",
        offender_name: "Status Wrapper Test Company Ltd",
        action_date: ~D[2023-11-01],
        action_type: :enforcement_notice,
        act: "Environmental Permitting (England and Wales) Regulations 2016",
        section: "Regulation 36 - Comply with conditions",
        scraped_at: DateTime.utc_now(),
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/EA_NOTICE_STATUS_001"
      }

      assert {:ok, notice, status} =
               NoticeProcessor.process_and_create_notice_with_status(ea_detail, nil)

      assert status in [:created, :existing, :updated]
      assert notice.regulator_id == "EA_NOTICE_STATUS_001"

      # Verify offence was created
      {:ok, offences} =
        Enforcement.Offence
        |> Ash.Query.filter(notice_id == ^notice.id)
        |> Ash.read()

      assert length(offences) == 1, "Expected legislation linking to occur via status wrapper"

      offence = List.first(offences)
      assert offence.legislation_id != nil
    end
  end
end
