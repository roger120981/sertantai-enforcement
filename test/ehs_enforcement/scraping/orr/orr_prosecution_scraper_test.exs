defmodule EhsEnforcement.Scraping.Orr.OrrProsecutionScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Orr.OrrProsecutionScraper
  alias EhsEnforcement.Scraping.Orr.OrrProsecutionScraper.ScrapedProsecution

  @fixtures_path "test/support/fixtures/orr"

  describe "parse_prosecutions_page/2 with full fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "prosecutions_page.html"))
      timestamp = ~U[2025-01-15 10:00:00Z]
      {:ok, html: html, timestamp: timestamp}
    end

    test "extracts all prosecutions from fixture", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      assert length(prosecutions) == 4
    end

    test "extracts First Greater Western prosecution correctly", %{
      html: html,
      timestamp: timestamp
    } do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      fgw =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "First Greater Western")
        end)

      assert fgw != nil
      assert fgw.year == 2025
      assert fgw.company == "First Greater Western Limited (trading as Great Western Railway)"
      assert String.contains?(fgw.summary, "fined £1 million")
      assert String.contains?(fgw.summary, "fatal incident near Twerton")
      assert String.contains?(fgw.breaches_involved, "Health & Safety at Work")
      assert String.contains?(fgw.breaches_involved, "Section 3(1)")
      assert fgw.date_of_offence == "On and before 1st December 2018"
      assert fgw.plea == "Guilty"
      assert String.contains?(fgw.result, "Convicted")
      assert fgw.court == "Bristol Crown Court"
      assert fgw.sentencing_date == "3 October 2025"

      assert fgw.penalty ==
               "£1 million (Very Large Organisation – sentenced in Medium culpability / Harm Category 2 range)"

      assert fgw.penalty_amount == Decimal.new("1000000")
      assert fgw.costs == "£78,444.19"
      assert fgw.costs_amount == Decimal.new("78444.19")
      assert String.contains?(fgw.location, "Railway routes")
      assert fgw.orr_details == "Railway Safety Directorate"
      assert fgw.scrape_timestamp == timestamp
    end

    test "extracts Network Rail (Surbiton) prosecution correctly", %{
      html: html,
      timestamp: timestamp
    } do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      nr =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Network Rail") and
            String.contains?(p.location || "", "Surbiton")
        end)

      assert nr != nil
      assert nr.year == 2025
      assert nr.company == "Network Rail Infrastructure Limited"
      assert Decimal.eq?(nr.penalty_amount, Decimal.new("3410000"))
      assert Decimal.eq?(nr.costs_amount, Decimal.new("145000"))
      assert nr.court == "Kingston upon Thames Crown Court"
    end

    test "extracts Severn Valley Railway prosecution correctly", %{
      html: html,
      timestamp: timestamp
    } do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      svr =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Severn Valley")
        end)

      assert svr != nil
      assert svr.year == 2024
      assert svr.company == "Severn Valley Railway (Holdings) PLC"
      assert svr.penalty_amount == Decimal.new("40000")
      assert svr.costs_amount == Decimal.new("15000")
      assert svr.court == "Kidderminster Magistrates Court"
    end

    test "extracts Transport for London prosecution correctly", %{
      html: html,
      timestamp: timestamp
    } do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      tfl =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Transport for London")
        end)

      assert tfl != nil
      assert tfl.year == 2023
      assert tfl.company == "Transport for London"
      assert String.contains?(tfl.summary, "Croydon tram derailment")
      assert String.contains?(tfl.summary, "seven passengers")
      assert tfl.penalty_amount == Decimal.new("10000000")
      assert tfl.costs_amount == Decimal.new("250000")
      assert tfl.court == "Croydon Crown Court"
    end

    test "groups prosecutions by year correctly", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      by_year = Enum.group_by(prosecutions, & &1.year)

      assert length(by_year[2025]) == 2
      assert length(by_year[2024]) == 1
      assert length(by_year[2023]) == 1
    end
  end

  describe "parse_prosecutions_page/2 with minimal fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "prosecutions_minimal.html"))
      timestamp = ~U[2025-01-15 10:00:00Z]
      {:ok, html: html, timestamp: timestamp}
    end

    test "extracts single prosecution", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      assert length(prosecutions) == 1

      p = List.first(prosecutions)
      assert p.company == "Test Company Ltd"
      assert p.year == 2025
      assert p.penalty_amount == Decimal.new("500000")
      assert p.costs_amount == Decimal.new("25000")
    end
  end

  describe "parse_prosecutions_page/2 with edge cases fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "prosecutions_edge_cases.html"))
      timestamp = ~U[2025-01-15 10:00:00Z]
      {:ok, html: html, timestamp: timestamp}
    end

    test "extracts all prosecutions including edge cases", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      assert length(prosecutions) == 3
    end

    test "parses million pound amounts correctly", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      big_railway =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Big Railway")
        end)

      assert big_railway != nil
      assert Decimal.eq?(big_railway.penalty_amount, Decimal.new("3750000"))
      assert Decimal.eq?(big_railway.costs_amount, Decimal.new("180000.50"))
    end

    test "parses £1 million word format correctly", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      metro =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Metro Systems")
        end)

      assert metro != nil
      assert metro.penalty_amount == Decimal.new("1000000")
      assert metro.year == 2023
    end

    test "handles prosecution with missing optional fields", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      small_train =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Small Train")
        end)

      assert small_train != nil
      assert small_train.company == "Small Train Co Limited"
      assert small_train.penalty_amount == Decimal.new("12500")
      assert small_train.year == 2024
      # Missing fields should be nil
      assert small_train.breaches_involved == nil
      assert small_train.date_of_offence == nil
      assert small_train.plea == nil
      assert small_train.costs == nil
      assert small_train.costs_amount == nil
    end

    test "handles multiple breaches in ordered list", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      big_railway =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Big Railway")
        end)

      assert big_railway != nil
      assert String.contains?(big_railway.breaches_involved, "Section 2(1)")
      assert String.contains?(big_railway.breaches_involved, "Regulation 5")
    end

    test "parses date with ordinal suffix correctly", %{html: html, timestamp: timestamp} do
      prosecutions = OrrProsecutionScraper.parse_html(html, timestamp)

      big_railway =
        Enum.find(prosecutions, fn p ->
          String.contains?(p.company || "", "Big Railway")
        end)

      assert big_railway != nil
      assert big_railway.date_of_offence == "On and before 15th March 2022"
    end
  end

  describe "parse_penalty_amount/1" do
    test "parses standard currency format" do
      assert OrrProsecutionScraper.parse_penalty_amount("£500,000") == Decimal.new("500000")
      assert OrrProsecutionScraper.parse_penalty_amount("£12,500") == Decimal.new("12500")
      assert OrrProsecutionScraper.parse_penalty_amount("£1,234,567") == Decimal.new("1234567")
    end

    test "parses currency with decimals" do
      assert OrrProsecutionScraper.parse_penalty_amount("£78,444.19") == Decimal.new("78444.19")
      assert OrrProsecutionScraper.parse_penalty_amount("£180,000.50") == Decimal.new("180000.50")
    end

    test "parses million format" do
      assert Decimal.eq?(
               OrrProsecutionScraper.parse_penalty_amount("£1 million"),
               Decimal.new("1000000")
             )

      assert Decimal.eq?(
               OrrProsecutionScraper.parse_penalty_amount("£3.75 million"),
               Decimal.new("3750000")
             )

      assert Decimal.eq?(
               OrrProsecutionScraper.parse_penalty_amount("£3.41 million"),
               Decimal.new("3410000")
             )

      assert Decimal.eq?(
               OrrProsecutionScraper.parse_penalty_amount("£10 million"),
               Decimal.new("10000000")
             )
    end

    test "handles nil input" do
      assert OrrProsecutionScraper.parse_penalty_amount(nil) == nil
    end

    test "handles text with extra content" do
      result = OrrProsecutionScraper.parse_penalty_amount("£1 million (Very Large Organisation)")
      assert result == Decimal.new("1000000")
    end
  end

  describe "prosecutions_url/0" do
    test "returns the correct URL" do
      url = OrrProsecutionScraper.prosecutions_url()

      assert url ==
               "https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions"
    end
  end

  describe "ScrapedProsecution struct" do
    test "has all expected fields" do
      prosecution = %ScrapedProsecution{
        year: 2025,
        company: "Network Rail Infrastructure Limited",
        summary: "Test summary",
        breaches_involved: "Health and Safety at Work etc Act 1974",
        date_of_offence: "3 July 2019",
        plea: "Guilty",
        result: "Convicted",
        court: "Swansea Crown Court",
        sentencing_date: "14 February 2025",
        penalty: "£3,750,000 (High culpability, Category 1 harm)",
        penalty_amount: Decimal.new("3750000"),
        costs: "£145,000",
        costs_amount: Decimal.new("145000"),
        location: "Near Margam, South Wales",
        orr_details: "Railway Safety Directorate",
        scrape_timestamp: DateTime.utc_now()
      }

      assert prosecution.year == 2025
      assert prosecution.company == "Network Rail Infrastructure Limited"
      assert prosecution.penalty_amount == Decimal.new("3750000")
      assert prosecution.costs_amount == Decimal.new("145000")
    end

    test "is JSON encodable" do
      prosecution = %ScrapedProsecution{
        year: 2025,
        company: "Test Company Ltd",
        summary: "Test summary",
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, json} = Jason.encode(prosecution)
      assert is_binary(json)
      assert String.contains?(json, "Test Company Ltd")
    end
  end

  describe "scrape_all/1" do
    @tag :external
    test "scrapes prosecutions from live ORR website" do
      assert {:ok, prosecutions} = OrrProsecutionScraper.scrape_all()

      assert is_list(prosecutions)
      assert length(prosecutions) > 0

      first = List.first(prosecutions)
      assert %ScrapedProsecution{} = first
      assert is_binary(first.company) or is_nil(first.company)
      assert is_integer(first.year) or is_nil(first.year)
    end

    @tag :external
    test "filters by year when specified" do
      assert {:ok, prosecutions} = OrrProsecutionScraper.scrape_all(years: [2025])

      assert is_list(prosecutions)

      Enum.each(prosecutions, fn p ->
        assert p.year == 2025
      end)
    end
  end
end
