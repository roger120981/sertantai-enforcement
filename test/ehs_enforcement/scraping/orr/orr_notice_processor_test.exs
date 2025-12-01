defmodule EhsEnforcement.Scraping.Orr.OrrNoticeProcessorTest do
  use EhsEnforcement.DataCase, async: true

  alias EhsEnforcement.Scraping.Orr.OrrNoticeProcessor
  alias EhsEnforcement.Scraping.Orr.OrrNoticeProcessor.ProcessedNotice
  alias EhsEnforcement.Scraping.Orr.OrrNoticeScraper.ScrapedNotice

  describe "process_notice/1" do
    test "processes an improvement notice into ProcessedNotice" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Network Rail Infrastructure Limited",
        reference: "I/20241205/MDB/01",
        issue_date: "5 December 2024",
        compliance_date: "5 March 2025",
        status: "Open",
        description: "Failed to ensure adequate safety measures at level crossing",
        pdf_url: "https://orrprdpubreg1.blob.core.windows.net/docs/notice.pdf",
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert %ProcessedNotice{} = processed
      assert processed.agency_code == :orr
      assert processed.notice_date == ~D[2024-12-05]
      assert processed.compliance_date == ~D[2025-03-05]
      assert processed.offence_action_type == "ORR Improvement Notice"
      assert processed.notice_status == :in_force

      # Check regulator_id uses reference
      assert String.contains?(processed.regulator_id, "imp")
      assert String.contains?(processed.regulator_id, "20241205")

      # Check offender attrs
      assert processed.offender_attrs.name == "Network Rail Infrastructure Limited"
      assert processed.offender_attrs.country == "United Kingdom"

      # Check notice body includes reference and description
      assert String.contains?(processed.notice_body, "I/20241205/MDB/01")
      assert String.contains?(processed.notice_body, "level crossing")
    end

    test "processes a prohibition notice into ProcessedNotice" do
      scraped = %ScrapedNotice{
        notice_type: :prohibition,
        year: 2023,
        company: "Train Operator Ltd",
        reference: "P/KB/14062023",
        issue_date: "14 June 2023",
        compliance_date: nil,
        status: "Complied",
        description: "Prohibited operation of unsafe rolling stock",
        pdf_url: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.offence_action_type == "ORR Prohibition Notice"
      assert processed.notice_status == :complied
      assert String.contains?(processed.regulator_id, "proh")
    end

    test "handles notice with minimal data" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2020,
        company: "Test Railway Ltd",
        reference: nil,
        issue_date: nil,
        compliance_date: nil,
        status: nil,
        description: nil,
        pdf_url: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.offender_attrs.name == "Test Railway Ltd"
      assert processed.notice_date == nil
      assert processed.compliance_date == nil
      assert processed.notice_status == nil
    end

    test "generates unique regulator_id for different notices" do
      base = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Company A Ltd",
        reference: "I/2024/A/01",
        issue_date: "1 March 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      other = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Company B Ltd",
        reference: "I/2024/B/01",
        issue_date: "1 March 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed1} = OrrNoticeProcessor.process_notice(base)
      {:ok, processed2} = OrrNoticeProcessor.process_notice(other)

      assert processed1.regulator_id != processed2.regulator_id
    end

    test "generates consistent regulator_id for same notice" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Consistent Company Ltd",
        reference: "I/2024/CONS/01",
        issue_date: "15 June 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed1} = OrrNoticeProcessor.process_notice(scraped)
      {:ok, processed2} = OrrNoticeProcessor.process_notice(scraped)

      assert processed1.regulator_id == processed2.regulator_id
    end

    test "regulator_id falls back to components when no reference" do
      scraped = %ScrapedNotice{
        notice_type: :prohibition,
        year: 2023,
        company: "Fallback Company Ltd",
        reference: nil,
        issue_date: "20 July 2023",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert String.starts_with?(processed.regulator_id, "orr_proh_2023_")
      assert String.contains?(processed.regulator_id, "fallback_company")
      assert String.ends_with?(processed.regulator_id, "_20230720")
    end
  end

  describe "process_notices/1" do
    test "processes multiple notices" do
      notices = [
        %ScrapedNotice{
          notice_type: :improvement,
          year: 2024,
          company: "Company One Ltd",
          reference: "I/2024/ONE",
          issue_date: "1 January 2024",
          scrape_timestamp: DateTime.utc_now()
        },
        %ScrapedNotice{
          notice_type: :prohibition,
          year: 2023,
          company: "Company Two Ltd",
          reference: "P/2023/TWO",
          issue_date: "1 June 2023",
          scrape_timestamp: DateTime.utc_now()
        }
      ]

      assert {:ok, processed_list} = OrrNoticeProcessor.process_notices(notices)

      assert length(processed_list) == 2
      assert Enum.all?(processed_list, &match?(%ProcessedNotice{}, &1))

      # Check types are preserved
      types = Enum.map(processed_list, & &1.offence_action_type)
      assert "ORR Improvement Notice" in types
      assert "ORR Prohibition Notice" in types
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = OrrNoticeProcessor.process_notices([])
    end
  end

  describe "status mapping" do
    test "maps 'Complied' to :complied" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test",
        status: "Complied",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)
      assert processed.notice_status == :complied
    end

    test "maps 'Open' to :in_force" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test",
        status: "Open",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)
      assert processed.notice_status == :in_force
    end

    test "maps 'In Force' to :in_force" do
      scraped = %ScrapedNotice{
        notice_type: :prohibition,
        year: 2023,
        company: "Test",
        status: "In Force",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)
      assert processed.notice_status == :in_force
    end

    test "maps 'Withdrawn' to :withdrawn" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2022,
        company: "Test",
        status: "Withdrawn",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)
      assert processed.notice_status == :withdrawn
    end

    test "maps unknown status to nil" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test",
        status: "Unknown Status",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)
      assert processed.notice_status == nil
    end
  end

  describe "date parsing" do
    test "parses standard date format" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test",
        issue_date: "5 December 2024",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.notice_date == ~D[2024-12-05]
    end

    test "parses date with ordinal suffix" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2023,
        company: "Test",
        issue_date: "1st March 2023",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.notice_date == ~D[2023-03-01]
    end

    test "parses compliance date" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test",
        issue_date: "5 December 2024",
        compliance_date: "5 March 2025",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.compliance_date == ~D[2025-03-05]
    end

    test "handles nil dates gracefully" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2020,
        company: "Test",
        issue_date: nil,
        compliance_date: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.notice_date == nil
      assert processed.compliance_date == nil
    end

    test "handles invalid date strings gracefully" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2020,
        company: "Test",
        issue_date: "invalid date",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert processed.notice_date == nil
    end
  end

  describe "source URL generation" do
    test "generates correct URL for improvement notice" do
      scraped = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert String.contains?(processed.url, "improvement-notices")
      assert String.contains?(processed.url, "2024")
    end

    test "generates correct URL for prohibition notice" do
      scraped = %ScrapedNotice{
        notice_type: :prohibition,
        year: 2023,
        company: "Test",
        scrape_timestamp: DateTime.utc_now()
      }

      {:ok, processed} = OrrNoticeProcessor.process_notice(scraped)

      assert String.contains?(processed.url, "prohibition-notices")
      assert String.contains?(processed.url, "2023")
    end
  end

  describe "ProcessedNotice struct" do
    test "has all expected fields" do
      processed = %ProcessedNotice{
        regulator_id: "orr_imp_2024_test_20240101",
        agency_code: :orr,
        offender_attrs: %{name: "Test", country: "United Kingdom"},
        notice_date: ~D[2024-01-01],
        compliance_date: ~D[2024-04-01],
        notice_body: "Test notice body",
        offence_action_type: "ORR Improvement Notice",
        offence_action_date: ~D[2024-01-01],
        notice_status: :in_force,
        url: "https://www.orr.gov.uk/...",
        source_metadata: %{year: 2024}
      }

      assert processed.regulator_id == "orr_imp_2024_test_20240101"
      assert processed.agency_code == :orr
      assert processed.notice_status == :in_force
    end

    test "is JSON encodable" do
      processed = %ProcessedNotice{
        regulator_id: "orr_imp_2024_test",
        agency_code: :orr,
        offender_attrs: %{name: "Test Company"},
        offence_action_type: "ORR Improvement Notice",
        source_metadata: %{year: 2024, notice_type: :improvement}
      }

      assert {:ok, json} = Jason.encode(processed)
      assert is_binary(json)
      assert String.contains?(json, "orr_imp_2024_test")
    end
  end
end
