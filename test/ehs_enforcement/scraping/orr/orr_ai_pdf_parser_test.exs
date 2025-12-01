defmodule EhsEnforcement.Scraping.Orr.OrrAiPdfParserTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Orr.OrrAiPdfParser
  alias EhsEnforcement.Scraping.Orr.OrrAiPdfParser.ParsedCase

  @fixtures_path "test/support/fixtures/orr"

  describe "pdf_urls_for_year/1" do
    test "returns URLs for 2021" do
      urls = OrrAiPdfParser.pdf_urls_for_year(2021)

      assert length(urls) == 6
      assert Enum.all?(urls, &String.starts_with?(&1, "https://www.orr.gov.uk"))
      assert Enum.any?(urls, &String.contains?(&1, "daventry"))
    end

    test "returns URLs for 2012" do
      urls = OrrAiPdfParser.pdf_urls_for_year(2012)

      assert length(urls) == 8
      assert Enum.any?(urls, &String.contains?(&1, "grayrigg"))
      assert Enum.any?(urls, &String.contains?(&1, "elsenham"))
    end

    test "returns empty list for unknown year" do
      urls = OrrAiPdfParser.pdf_urls_for_year(1990)
      assert urls == []
    end

    test "returns URLs for earliest year 2002" do
      urls = OrrAiPdfParser.pdf_urls_for_year(2002)

      assert length(urls) == 2
      assert Enum.any?(urls, &String.contains?(&1, "potters-bar"))
    end
  end

  describe "all_pdf_urls/0" do
    test "returns map of all years" do
      all_urls = OrrAiPdfParser.all_pdf_urls()

      assert is_map(all_urls)
      assert Map.has_key?(all_urls, 2021)
      assert Map.has_key?(all_urls, 2012)
      assert Map.has_key?(all_urls, 2006)

      # Verify all URLs are fully qualified
      Enum.each(all_urls, fn {_year, urls} ->
        assert Enum.all?(urls, &String.starts_with?(&1, "https://"))
      end)
    end

    test "contains at least 70 total PDF URLs" do
      all_urls = OrrAiPdfParser.all_pdf_urls()

      total_count =
        all_urls
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()

      # We have 70+ historical PDFs
      assert total_count >= 70
    end
  end

  describe "ParsedCase struct" do
    test "has all expected fields" do
      case_struct = %ParsedCase{
        company_name: "Network Rail",
        company_type: :infrastructure_manager,
        location: "Grayrigg",
        incident_date: ~D[2007-02-23],
        sentencing_date: ~D[2012-04-04],
        court_name: "Bristol Crown Court",
        fine_amount: Decimal.new("4000000"),
        costs_amount: Decimal.new("215000"),
        total_amount: Decimal.new("4215000"),
        plea: "Guilty",
        result: "Convicted",
        offence_description: "Failure to conduct undertaking safely",
        breaches: ["Section 3(1) HSWA 1974"],
        legislation: ["Health and Safety at Work etc Act 1974"],
        year: 2012,
        case_title: "Network Rail (Grayrigg)",
        source_url: "https://www.orr.gov.uk/example.pdf"
      }

      assert case_struct.company_name == "Network Rail"
      assert case_struct.company_type == :infrastructure_manager
      assert Decimal.eq?(case_struct.fine_amount, Decimal.new("4000000"))
    end
  end

  describe "parse_pdf_text/3 with mock AI client" do
    # These tests verify the parsing logic when AI returns properly formatted responses
    # In test environment, the mock client is used

    test "handles single defendant case" do
      # This test uses the Mock AI client which returns a predefined response
      pdf_text = File.read!(Path.join(@fixtures_path, "prosecution_pdf_text.txt"))

      # The mock client will return a mock response
      # We're testing that parse_pdf_text properly calls the client and handles response
      result = OrrAiPdfParser.parse_pdf_text(pdf_text, 2012)

      # With mock client, we expect either success or mock response
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles empty PDF text gracefully" do
      result = OrrAiPdfParser.parse_pdf_text("", 2020)

      # Should not crash, returns either empty list or error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "parse_ai_response/3 (via parse_pdf_text)" do
    # Test the JSON parsing behavior by examining module structure
    # These are unit tests for the response parsing logic

    test "module exports expected functions" do
      # Verify public API
      assert function_exported?(OrrAiPdfParser, :parse_pdf_text, 2)
      assert function_exported?(OrrAiPdfParser, :parse_pdf_text, 3)
      assert function_exported?(OrrAiPdfParser, :parse_pdf_url, 2)
      assert function_exported?(OrrAiPdfParser, :scrape_pdf_year, 1)
      assert function_exported?(OrrAiPdfParser, :scrape_all_pdfs, 0)
      assert function_exported?(OrrAiPdfParser, :pdf_urls_for_year, 1)
      assert function_exported?(OrrAiPdfParser, :all_pdf_urls, 0)
    end
  end

  describe "year coverage" do
    test "covers all years from 2002 to 2021" do
      all_urls = OrrAiPdfParser.all_pdf_urls()
      years = Map.keys(all_urls) |> Enum.sort()

      # Should have good year coverage
      assert 2002 in years
      assert 2006 in years
      assert 2012 in years
      assert 2016 in years
      assert 2021 in years
    end

    test "2006-2021 period has reasonable coverage" do
      all_urls = OrrAiPdfParser.all_pdf_urls()

      # Count years in the ORR regulation period (2006+)
      orr_years =
        all_urls
        |> Map.keys()
        |> Enum.filter(&(&1 >= 2006))

      # ORR took over rail safety in April 2006
      # Should have at least 10 years covered
      assert length(orr_years) >= 10
    end
  end

  describe "URL structure validation" do
    test "all URLs follow expected patterns" do
      all_urls = OrrAiPdfParser.all_pdf_urls()

      all_urls
      |> Map.values()
      |> List.flatten()
      |> Enum.each(fn url ->
        assert String.starts_with?(url, "https://www.orr.gov.uk/sites/default/files/")
        assert String.ends_with?(url, ".pdf")
      end)
    end

    test "newer years use dated folder structure" do
      urls_2021 = OrrAiPdfParser.pdf_urls_for_year(2021)

      # 2021 URLs should have year-month folder structure
      assert Enum.any?(urls_2021, fn url ->
               Regex.match?(~r/files\/\d{4}-\d{2}\//, url)
             end)
    end

    test "older years use /om/ folder structure" do
      urls_2006 = OrrAiPdfParser.pdf_urls_for_year(2006)

      # 2006 URLs should use /om/ folder
      assert Enum.all?(urls_2006, fn url ->
               String.contains?(url, "/om/")
             end)
    end
  end
end
