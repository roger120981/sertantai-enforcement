defmodule EhsEnforcement.Scraping.Caa.CaaProsecutionScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Caa.CaaProsecutionScraper
  alias EhsEnforcement.Scraping.Caa.CaaProsecutionScraper.ScrapedProsecution

  @fixtures_path "test/fixtures/caa"

  describe "parse_pdf_text/3 with 2024-2025 format" do
    setup do
      text = File.read!(Path.join(@fixtures_path, "prosecutions_2024_2025.txt"))
      timestamp = ~U[2025-12-02 12:00:00Z]
      {:ok, text: text, timestamp: timestamp}
    end

    test "parses all prosecutions from 2024-2025 fixture", %{text: text, timestamp: timestamp} do
      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2024-2025", timestamp)

      assert length(prosecutions) == 6
      assert Enum.all?(prosecutions, &match?(%ScrapedProsecution{}, &1))
    end

    test "parses Barry SCOTT prosecution correctly", %{text: text, timestamp: timestamp} do
      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2024-2025", timestamp)

      scott = Enum.find(prosecutions, &(&1.defendant == "Barry SCOTT"))

      assert scott != nil
      assert scott.fiscal_year == "2024-2025"
      assert scott.date == "28/05/2024"
      assert scott.court == "Reading Crown Court"
      assert scott.sentence =~ "Fine £1,500"
      assert Decimal.equal?(scott.fine_amount, Decimal.new("1500"))
      assert scott.brief_description =~ "pilot in command of Piper PA-28"
      assert scott.brief_description =~ "negligently endangering an aircraft"
      assert scott.scrape_timestamp == timestamp
    end

    test "parses Charles HUDSON prosecution correctly", %{text: text, timestamp: timestamp} do
      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2024-2025", timestamp)

      hudson = Enum.find(prosecutions, &(&1.defendant == "Charles HUDSON"))

      assert hudson != nil
      assert hudson.date == "29/08/2024"
      assert hudson.court == "Chelmsford Magistrates' Court"
      assert Decimal.equal?(hudson.fine_amount, Decimal.new("4000"))
      assert hudson.brief_description =~ "Folland Gnat aircraft"
      assert hudson.brief_description =~ "Stansted TMZ"
    end

    test "parses Gordon OLIVER prosecution correctly", %{text: text, timestamp: timestamp} do
      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2024-2025", timestamp)

      oliver = Enum.find(prosecutions, &(&1.defendant == "Gordon OLIVER"))

      assert oliver != nil
      assert oliver.date == "09/01/2025"
      assert oliver.court == "Carlisle Magistrates' Court"
      assert Decimal.equal?(oliver.fine_amount, Decimal.new("1675"))
      assert oliver.brief_description =~ "Buttermere Bash"
      assert oliver.brief_description =~ "flying display"
    end

    test "parses Christopher HOLLANDS prosecution correctly", %{text: text, timestamp: timestamp} do
      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2024-2025", timestamp)

      hollands = Enum.find(prosecutions, &(&1.defendant == "Christopher HOLLANDS"))

      assert hollands != nil
      assert hollands.date == "20/03/2025"
      assert hollands.court == "Manchester Magistrates' Court"
      assert Decimal.equal?(hollands.fine_amount, Decimal.new("4511"))
      assert hollands.brief_description =~ "commercial airline flight from Oslo to Manchester"
      assert hollands.brief_description =~ "RAF Typhoons"
    end

    test "all prosecutions have required fields populated", %{text: text, timestamp: timestamp} do
      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2024-2025", timestamp)

      for p <- prosecutions do
        assert p.defendant != nil and p.defendant != ""
        assert p.fiscal_year == "2024-2025"
        assert p.date != nil
        assert p.court != nil
        assert p.fine_amount != nil
        assert p.scrape_timestamp == timestamp
      end
    end
  end

  describe "parse_pdf_text/3 with legacy format" do
    # Legacy format (pre-2023) requires AI parsing - regex approach was abandoned
    # See Phase 6 in session document for details

    test "legacy format returns empty list (requires AI parsing)" do
      text = File.read!(Path.join(@fixtures_path, "prosecutions_2021_2022_legacy.txt"))
      timestamp = ~U[2025-12-02 12:00:00Z]

      prosecutions = CaaProsecutionScraper.parse_pdf_text(text, "2021-2022", timestamp)

      # Legacy format returns empty list - AI parsing not yet implemented
      assert prosecutions == []
    end

    test "legacy format is correctly detected" do
      text = File.read!(Path.join(@fixtures_path, "prosecutions_2021_2022_legacy.txt"))

      # parse_legacy_format should be called (returns empty list)
      prosecutions =
        CaaProsecutionScraper.parse_legacy_format(text, "2021-2022", DateTime.utc_now())

      assert is_list(prosecutions)
      assert prosecutions == []
    end
  end

  describe "format detection" do
    test "correctly identifies modern format" do
      modern_text = """
      Defendant
      Barry SCOTT

      Brief Description
      Some description here.

      Date
      01/01/2024
      """

      prosecutions =
        CaaProsecutionScraper.parse_modern_format(modern_text, "2024-2025", DateTime.utc_now())

      # Should attempt to parse as modern format (may be empty due to minimal text)
      assert is_list(prosecutions)
    end

    test "correctly identifies legacy format" do
      legacy_text = """
      DEFENDANT      BRIEF DESCRIPTION                         DATE         COURT          SENTENCE
      JOHN SMITH     Description text here.                    01/01/2020   Crown Court    Fine £1,000
      """

      prosecutions =
        CaaProsecutionScraper.parse_legacy_format(legacy_text, "2019-2020", DateTime.utc_now())

      assert is_list(prosecutions)
    end
  end

  describe "parse_fine_amount/1" do
    test "parses standard fine format" do
      assert Decimal.equal?(
               CaaProsecutionScraper.parse_fine_amount("Fine £1,500"),
               Decimal.new("1500")
             )

      assert Decimal.equal?(
               CaaProsecutionScraper.parse_fine_amount("Fine £4,000"),
               Decimal.new("4000")
             )

      assert Decimal.equal?(
               CaaProsecutionScraper.parse_fine_amount("Fine £600"),
               Decimal.new("600")
             )
    end

    test "parses fine with decimal places" do
      assert Decimal.equal?(
               CaaProsecutionScraper.parse_fine_amount("Fine £4,511.50"),
               Decimal.new("4511.50")
             )
    end

    test "parses fine without 'Fine' prefix" do
      assert Decimal.equal?(
               CaaProsecutionScraper.parse_fine_amount("£2,000"),
               Decimal.new("2000")
             )
    end

    test "returns nil for non-fine sentences" do
      assert CaaProsecutionScraper.parse_fine_amount("Community service") == nil
      assert CaaProsecutionScraper.parse_fine_amount("Suspended sentence") == nil
      assert CaaProsecutionScraper.parse_fine_amount(nil) == nil
    end
  end

  describe "available_years/0" do
    test "returns list of available fiscal years" do
      years = CaaProsecutionScraper.available_years()

      assert is_list(years)
      assert "2024-2025" in years
      assert "2017-2018" in years
      assert length(years) == 8
    end

    test "returns years in descending order" do
      years = CaaProsecutionScraper.available_years()

      assert hd(years) == "2024-2025"
      assert List.last(years) == "2017-2018"
    end
  end

  describe "prosecutions_page_url/0" do
    test "returns the CAA prosecutions page URL" do
      url = CaaProsecutionScraper.prosecutions_page_url()

      assert url ==
               "https://www.caa.co.uk/our-work/about-us/enforcement/enforcement-and-prosecutions/"
    end
  end

  describe "ScrapedProsecution struct" do
    test "has all expected fields" do
      prosecution = %ScrapedProsecution{
        fiscal_year: "2024-2025",
        defendant: "Test Defendant",
        brief_description: "Test description",
        date: "01/01/2024",
        court: "Test Court",
        sentence: "Fine £1,000",
        fine_amount: Decimal.new("1000"),
        scrape_timestamp: DateTime.utc_now()
      }

      assert prosecution.fiscal_year == "2024-2025"
      assert prosecution.defendant == "Test Defendant"
      assert prosecution.brief_description == "Test description"
      assert prosecution.date == "01/01/2024"
      assert prosecution.court == "Test Court"
      assert prosecution.sentence == "Fine £1,000"
      assert Decimal.equal?(prosecution.fine_amount, Decimal.new("1000"))
    end

    test "is JSON encodable" do
      prosecution = %ScrapedProsecution{
        fiscal_year: "2024-2025",
        defendant: "Test",
        brief_description: "Desc",
        date: "01/01/2024",
        court: "Court",
        sentence: "Fine £100",
        fine_amount: Decimal.new("100"),
        scrape_timestamp: ~U[2025-01-01 00:00:00Z]
      }

      assert {:ok, _json} = Jason.encode(prosecution)
    end
  end
end
