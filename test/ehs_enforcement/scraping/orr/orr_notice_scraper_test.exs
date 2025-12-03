defmodule EhsEnforcement.Scraping.Orr.OrrNoticeScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Orr.OrrNoticeScraper
  alias EhsEnforcement.Scraping.Orr.OrrNoticeScraper.ScrapedNotice

  @fixtures_path "test/fixtures/orr"

  describe "parse_notices_page/4 with improvement notices fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "improvement_notices_2024.html"))
      timestamp = ~U[2025-01-15 10:00:00Z]
      {:ok, html: html, timestamp: timestamp}
    end

    test "extracts correct number of notices", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      assert length(notices) == 4
    end

    test "extracts company names correctly", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      company_names = Enum.map(notices, & &1.company)

      assert "Great Western Society Limited" in company_names
      assert "The Tramway Museum Society" in company_names
      assert "Network Rail Infrastructure Limited" in company_names
      assert "Chiltern Railways" in company_names
    end

    test "company names do not contain descriptions", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      Enum.each(notices, fn notice ->
        # Company names should be short (< 100 chars) and not contain failure descriptions
        assert String.length(notice.company) < 100,
               "Company name too long: #{notice.company}"

        refute String.contains?(notice.company, "failed to"),
               "Company name contains 'failed to': #{notice.company}"

        refute String.contains?(notice.company, "has failed"),
               "Company name contains 'has failed': #{notice.company}"
      end)
    end

    test "extracts reference IDs correctly", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      references = Enum.map(notices, & &1.reference) |> Enum.reject(&is_nil/1)

      assert "I/20241205/MDB/01" in references
      assert "I/20240812/JGT" in references
      assert "I/240219-1-JGT" in references
    end

    test "extracts issue dates correctly", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      gws_notice = Enum.find(notices, &(&1.company == "Great Western Society Limited"))
      assert gws_notice.issue_date == "5 December 2024"

      nr_notice = Enum.find(notices, &(&1.company == "Network Rail Infrastructure Limited"))
      assert nr_notice.issue_date == "12 August 2024"
    end

    test "extracts compliance dates correctly", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      gws_notice = Enum.find(notices, &(&1.company == "Great Western Society Limited"))
      assert gws_notice.compliance_date == "1 March 2025"
    end

    test "extracts status correctly", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      statuses = Enum.map(notices, & &1.status) |> Enum.reject(&is_nil/1)

      # All notices in fixture have "Complied" status
      assert Enum.all?(statuses, &(&1 == "Complied"))
    end

    test "sets correct notice type", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      assert Enum.all?(notices, &(&1.notice_type == :improvement))
    end

    test "sets correct year", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      assert Enum.all?(notices, &(&1.year == 2024))
    end

    test "sets scrape timestamp", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      assert Enum.all?(notices, &(&1.scrape_timestamp == timestamp))
    end

    test "generates PDF URLs", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      notices_with_urls = Enum.filter(notices, &(!is_nil(&1.pdf_url)))

      # Most notices should have PDF URLs
      assert length(notices_with_urls) >= 3

      # PDF URLs should be properly formatted
      Enum.each(notices_with_urls, fn notice ->
        assert String.starts_with?(notice.pdf_url, "https://")
        assert String.ends_with?(notice.pdf_url, ".pdf")
      end)
    end
  end

  describe "parse_notices_page/4 with prohibition notices fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "prohibition_notices_2022.html"))
      timestamp = ~U[2025-01-15 10:00:00Z]
      {:ok, html: html, timestamp: timestamp}
    end

    test "extracts correct number of prohibition notices", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :prohibition, 2022, timestamp)

      assert length(notices) == 5
    end

    test "extracts prohibition notice company names correctly", %{
      html: html,
      timestamp: timestamp
    } do
      notices = OrrNoticeScraper.parse_notices_page(html, :prohibition, 2022, timestamp)

      company_names = Enum.map(notices, & &1.company)

      assert "Keighley and Worth Valley Railway Preservation Society Limited" in company_names
      assert "Gwili Railway Company Limited" in company_names
      assert "Wensleydale Railway PLC" in company_names
      assert "Colne Valley Railway Preservation Society" in company_names
      assert "Network Rail Infrastructure Limited" in company_names
    end

    test "extracts prohibition reference IDs correctly", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :prohibition, 2022, timestamp)

      references = Enum.map(notices, & &1.reference) |> Enum.reject(&is_nil/1)

      assert "P/20220628/KWVR/SJS/01" in references
      assert "P/20220628/GWILI/SJS/01" in references
      assert "P/MB15032022" in references
      assert "P/KB10012022" in references
      assert "P/20220105/NR/SJS/01" in references
    end

    test "extracts different statuses", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :prohibition, 2022, timestamp)

      statuses = Enum.map(notices, & &1.status) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      assert "Complied" in statuses
      assert "In Force" in statuses
    end

    test "sets correct notice type for prohibition", %{html: html, timestamp: timestamp} do
      notices = OrrNoticeScraper.parse_notices_page(html, :prohibition, 2022, timestamp)

      assert Enum.all?(notices, &(&1.notice_type == :prohibition))
    end
  end

  describe "ScrapedNotice struct" do
    test "has all expected fields" do
      notice = %ScrapedNotice{
        notice_type: :improvement,
        year: 2024,
        company: "Test Company Ltd",
        reference: "I/20240101/TEST/01",
        issue_date: "1 January 2024",
        compliance_date: "1 March 2024",
        status: "Complied",
        description: "Test description",
        pdf_url: "https://example.com/test.pdf",
        scrape_timestamp: ~U[2025-01-15 10:00:00Z]
      }

      assert notice.notice_type == :improvement
      assert notice.year == 2024
      assert notice.company == "Test Company Ltd"
      assert notice.reference == "I/20240101/TEST/01"
    end
  end

  describe "improvement_years/0" do
    test "returns list of years" do
      years = OrrNoticeScraper.improvement_years()

      assert is_list(years)
      assert 2024 in years
      assert 2012 in years
    end
  end

  describe "prohibition_years/0" do
    test "returns list of years" do
      years = OrrNoticeScraper.prohibition_years()

      assert is_list(years)
      assert 2022 in years
      assert 2012 in years
    end
  end

  describe "edge cases" do
    test "handles empty HTML gracefully" do
      html = "<html><body><main></main></body></html>"
      timestamp = ~U[2025-01-15 10:00:00Z]

      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      assert notices == [] or is_list(notices)
    end

    test "handles malformed HTML gracefully" do
      html = "<div>Some random content without proper structure</div>"
      timestamp = ~U[2025-01-15 10:00:00Z]

      notices = OrrNoticeScraper.parse_notices_page(html, :improvement, 2024, timestamp)

      assert is_list(notices)
    end
  end
end
