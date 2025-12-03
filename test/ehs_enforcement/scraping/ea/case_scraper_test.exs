defmodule EhsEnforcement.Scraping.Ea.CaseScraperTest do
  @moduledoc """
  Unit tests for EA case scraper functionality.

  Tests the two-stage EA scraping pattern:
  - Stage 1: Summary records collection
  - Stage 2: Detail records enrichment
  """

  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Ea.CaseScraper
  alias EhsEnforcement.Scraping.Ea.CaseScraper.{EaDetailRecord, EaSummaryRecord}

  @fixtures_path "test/fixtures/ea"

  describe "EA scraper data structures" do
    test "EaSummaryRecord struct has required fields" do
      record = %EaSummaryRecord{
        ea_record_id: "test123",
        offender_name: "Test Company",
        action_date: ~D[2025-08-01],
        action_type: :court_case,
        detail_url: "https://example.com/test",
        scraped_at: DateTime.utc_now()
      }

      assert record.ea_record_id == "test123"
      assert record.offender_name == "Test Company"
      assert record.action_type == :court_case
    end

    test "EaSummaryRecord includes summary_address field" do
      record = %EaSummaryRecord{
        ea_record_id: "test456",
        offender_name: "Another Company Ltd",
        summary_address: "123 Industrial Estate, Manchester, M1 2AB",
        action_date: ~D[2024-01-15],
        action_type: :court_case,
        detail_url: "https://example.com/test456",
        scraped_at: DateTime.utc_now()
      }

      assert record.summary_address == "123 Industrial Estate, Manchester, M1 2AB"
    end

    test "EaDetailRecord struct has required fields" do
      record = %EaDetailRecord{
        ea_record_id: "test123",
        offender_name: "Test Company",
        action_date: ~D[2025-08-01],
        action_type: :court_case,
        total_fine: Decimal.new(5000),
        scraped_at: DateTime.utc_now()
      }

      assert record.ea_record_id == "test123"
      assert record.total_fine == Decimal.new(5000)
    end

    test "EaDetailRecord struct has all detail fields" do
      record = %EaDetailRecord{
        ea_record_id: "10000529",
        offender_name: "Test Environmental Company Ltd",
        action_date: ~D[2024-01-15],
        action_type: :court_case,
        company_registration_number: "12345678",
        industry_sector: "Manufacturing",
        address: "123 Industrial Estate",
        town: "Manchester",
        county: "Greater Manchester",
        postcode: "M1 2AB",
        total_fine: Decimal.new("15000"),
        offence_description: "Operating without permit",
        case_reference: "EA/CC/2024/001",
        event_reference: "EVT10000529",
        agency_function: "Regulation",
        water_impact: "Major",
        land_impact: "Minor",
        air_impact: "None",
        act: "Environmental Permitting Regulations 2016",
        section: "Regulation 38(1)",
        legal_reference: "Environmental Permitting Regulations 2016 - Regulation 38(1)",
        detail_url:
          "https://environment.data.gov.uk/public-register/enforcement-action/registration/10000529",
        scraped_at: DateTime.utc_now()
      }

      assert record.company_registration_number == "12345678"
      assert record.water_impact == "Major"
      assert record.case_reference == "EA/CC/2024/001"
    end
  end

  describe "HTML fixture parsing - summary page" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "summary_page.html"))
      %{html: html}
    end

    test "fixture contains expected table structure", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      rows = Floki.find(document, "table tbody tr")
      assert length(rows) == 3
    end

    test "extracts offender names from summary table", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      names =
        document
        |> Floki.find("table tbody tr td:first-child a")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)

      assert "Test Environmental Company Ltd" in names
      assert "Waste Management Services Ltd" in names
      assert "Water Treatment Solutions PLC" in names
    end

    test "extracts detail URLs from summary table", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      urls =
        document
        |> Floki.find("table tbody tr td:first-child a")
        |> Enum.map(fn a ->
          Floki.attribute(a, "href") |> List.first()
        end)

      assert length(urls) == 3
      assert Enum.all?(urls, &String.contains?(&1, "registration/"))
    end

    test "extracts dates from summary table", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      dates =
        document
        |> Floki.find("table tbody tr td:last-child")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)

      assert "15/01/2024" in dates
      assert "20/02/2024" in dates
      assert "01/03/2024" in dates
    end

    test "parses summary page using test helper", %{html: html} do
      # Use the test helper exposed in test environment
      {:ok, records} = CaseScraper.test_parse_summary_page(html, :court_case)

      assert length(records) == 3

      [first | _] = records
      assert first.offender_name == "Test Environmental Company Ltd"
      assert first.action_type == :court_case
      assert first.ea_record_id == "10000529"
    end
  end

  describe "HTML fixture parsing - detail page" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "detail_page.html"))
      %{html: html}
    end

    test "fixture contains expected sections", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      sections = Floki.find(document, ".details-section h3")
      section_titles = Enum.map(sections, &Floki.text/1)

      assert "Company Information" in section_titles
      assert "Enforcement Details" in section_titles
      assert "Environmental Impact" in section_titles
      assert "Legal Framework" in section_titles
    end

    test "extracts company information from detail page", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      # Extract using dt/dd pairs
      extract_field = fn doc, label ->
        case Floki.find(doc, "dt:fl-contains('#{label}') + dd") do
          [dd] -> Floki.text(dd) |> String.trim()
          _ -> nil
        end
      end

      assert extract_field.(document, "Company No.") == "12345678"
      assert extract_field.(document, "Industry Sector") == "Manufacturing"
      assert extract_field.(document, "Town") == "Manchester"
      assert extract_field.(document, "Postcode") == "M1 2AB"
    end

    test "extracts enforcement details from detail page", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      extract_field = fn doc, label ->
        case Floki.find(doc, "dt:fl-contains('#{label}') + dd") do
          [dd] -> Floki.text(dd) |> String.trim()
          _ -> nil
        end
      end

      assert extract_field.(document, "Case Reference") == "EA/CC/2024/001"
      assert extract_field.(document, "Total Fine") == "£15,000.00"
      assert extract_field.(document, "Agency Function") == "Regulation"
    end

    test "extracts environmental impact from detail page", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      extract_field = fn doc, label ->
        case Floki.find(doc, "dt:fl-contains('#{label}') + dd") do
          [dd] -> Floki.text(dd) |> String.trim()
          _ -> nil
        end
      end

      assert extract_field.(document, "Water Impact") == "Major"
      assert extract_field.(document, "Land Impact") == "Minor"
      assert extract_field.(document, "Air Impact") == "None"
    end

    test "extracts legal framework from detail page", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      extract_field = fn doc, label ->
        case Floki.find(doc, "dt:fl-contains('#{label}') + dd") do
          [dd] -> Floki.text(dd) |> String.trim()
          _ -> nil
        end
      end

      act = extract_field.(document, "Act")
      section = extract_field.(document, "Section")

      assert act == "Environmental Permitting (England and Wales) Regulations 2016"
      assert section == "Regulation 38(1)"
    end
  end

  describe "HTML fixture parsing - Water Resources Act detail" do
    test "extracts Water Resources Act legislation" do
      html = File.read!(Path.join(@fixtures_path, "detail_page_water_act.html"))
      {:ok, document} = Floki.parse_document(html)

      extract_field = fn doc, label ->
        case Floki.find(doc, "dt:fl-contains('#{label}') + dd") do
          [dd] -> Floki.text(dd) |> String.trim()
          _ -> nil
        end
      end

      assert extract_field.(document, "Act") == "Water Resources Act 1991"
      assert extract_field.(document, "Section") == "Section 85(1)"
      assert extract_field.(document, "Total Fine") == "£8,500.00"
    end
  end

  describe "date parsing" do
    test "parses DD/MM/YYYY format" do
      assert CaseScraper.test_parse_ea_date("15/01/2024") == ~D[2024-01-15]
      assert CaseScraper.test_parse_ea_date("20/02/2024") == ~D[2024-02-20]
      assert CaseScraper.test_parse_ea_date("01/03/2024") == ~D[2024-03-01]
    end

    test "parses ISO format" do
      assert CaseScraper.test_parse_ea_date("2024-01-15") == ~D[2024-01-15]
      assert CaseScraper.test_parse_ea_date("2024-12-31") == ~D[2024-12-31]
    end

    test "returns nil for invalid date" do
      assert CaseScraper.test_parse_ea_date("invalid") == nil
      assert CaseScraper.test_parse_ea_date("") == nil
    end
  end

  describe "URL handling" do
    test "extracts record ID from URL" do
      url = "/public-register/enforcement-action/registration/10000529?__pageState=result"
      assert CaseScraper.test_extract_record_id_from_url(url) == "10000529"
    end

    test "extracts record ID from absolute URL" do
      url =
        "https://environment.data.gov.uk/public-register/enforcement-action/registration/10000530"

      assert CaseScraper.test_extract_record_id_from_url(url) == "10000530"
    end

    test "builds absolute URL from relative" do
      relative = "/public-register/enforcement-action/registration/10000529"
      absolute = CaseScraper.test_build_absolute_detail_url(relative)

      assert String.starts_with?(absolute, "https://environment.data.gov.uk")
      assert String.contains?(absolute, "10000529")
    end

    test "returns absolute URL unchanged" do
      absolute =
        "https://environment.data.gov.uk/public-register/enforcement-action/registration/10000529"

      assert CaseScraper.test_build_absolute_detail_url(absolute) == absolute
    end
  end

  describe "row parsing" do
    test "extracts summary record from table row" do
      row_html = """
      <tr>
        <td>
          <a href="/public-register/enforcement-action/registration/10000529">
            Test Company Ltd
          </a>
        </td>
        <td>123 Test Street, London</td>
        <td>15/01/2024</td>
      </tr>
      """

      {:ok, [row]} = Floki.parse_fragment(row_html)
      timestamp = DateTime.utc_now()

      {:ok, record} =
        CaseScraper.test_extract_summary_record_from_row(row, :court_case, timestamp)

      assert record.offender_name == "Test Company Ltd"
      assert record.summary_address == "123 Test Street, London"
      assert record.action_date == ~D[2024-01-15]
      assert record.ea_record_id == "10000529"
      assert record.action_type == :court_case
    end

    test "handles row without address column" do
      row_html = """
      <tr>
        <td>
          <a href="/public-register/enforcement-action/registration/10000530">
            Another Company Ltd
          </a>
        </td>
        <td>20/02/2024</td>
      </tr>
      """

      {:ok, [row]} = Floki.parse_fragment(row_html)
      timestamp = DateTime.utc_now()

      {:ok, record} = CaseScraper.test_extract_summary_record_from_row(row, :caution, timestamp)

      assert record.offender_name == "Another Company Ltd"
      assert record.summary_address == nil
      assert record.action_date == ~D[2024-02-20]
      assert record.action_type == :caution
    end
  end

  describe "function exports" do
    test "collect_summary_records_for_action_type/4 is exported" do
      assert function_exported?(CaseScraper, :collect_summary_records_for_action_type, 4)
    end

    test "fetch_detail_record_individual/2 is exported" do
      assert function_exported?(CaseScraper, :fetch_detail_record_individual, 2)
    end

    test "scrape_enforcement_actions/4 is exported" do
      assert function_exported?(CaseScraper, :scrape_enforcement_actions, 4)
    end
  end
end
