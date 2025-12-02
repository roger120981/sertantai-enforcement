defmodule EhsEnforcement.Scraping.Caa.CaaUndertakingScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Caa.CaaUndertakingScraper
  alias EhsEnforcement.Scraping.Caa.CaaUndertakingScraper.ScrapedUndertaking

  @fixtures_path "test/fixtures/caa"

  describe "parse_html/2" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "undertakings.html"))
      timestamp = ~U[2025-12-02 12:00:00Z]
      {:ok, html: html, timestamp: timestamp}
    end

    test "parses all undertakings from fixture", %{html: html, timestamp: timestamp} do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      # Should find all 34 accordion sections as undertakings
      assert length(undertakings) == 34
      assert Enum.all?(undertakings, &match?(%ScrapedUndertaking{}, &1))
    end

    test "parses Wizz Air undertaking correctly", %{html: html, timestamp: timestamp} do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      wizz = Enum.find(undertakings, &(&1.organisation == "Wizz Air"))

      assert wizz != nil
      assert wizz.date_provided == ~D[2023-07-26]
      assert wizz.legislation == "Regulation 261/2004"
      assert wizz.commitments =~ "re-routing under comparable transport conditions"
      assert wizz.commitments =~ "reimburse passengers"
      assert wizz.scrape_timestamp == timestamp
    end

    test "parses Emirates undertaking correctly", %{html: html, timestamp: timestamp} do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      emirates = Enum.find(undertakings, &(&1.organisation == "Emirates"))

      assert emirates != nil
      assert emirates.date_provided == ~D[2018-03-29]
      assert emirates.legislation == "Regulation 261/2004"
      assert emirates.commitments =~ "compensate passengers"
      assert emirates.commitments =~ "missed connection"
    end

    test "parses Manchester Airport PLC undertaking (with malformed HTML)", %{
      html: html,
      timestamp: timestamp
    } do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      manchester = Enum.find(undertakings, &(&1.organisation == "Manchester Airport PLC"))

      assert manchester != nil
      assert manchester.date_provided == ~D[2018-03-20]
      assert manchester.legislation == "Regulation 1107/2006"
      # This entry has duplicate "Date provided:" where "Commitments:" should be
      assert manchester.commitments =~ "performance improvement plan"
      assert manchester.commitments =~ "disabled persons"
    end

    test "parses HDC Travel Ltd undertaking with anchor tags in h3", %{
      html: html,
      timestamp: timestamp
    } do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      hdc = Enum.find(undertakings, &(&1.organisation == "HDC Travel Ltd"))

      assert hdc != nil
      assert hdc.date_provided == ~D[2018-02-14]
      assert hdc.legislation == "Consumer Protection from Unfair Trading Regulations 2008"
      assert hdc.commitments =~ "departure and arrival times"
    end

    test "all undertakings have required fields populated", %{html: html, timestamp: timestamp} do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      for u <- undertakings do
        assert u.organisation != nil and u.organisation != ""
        assert u.date_provided != nil
        assert u.legislation != nil and u.legislation != ""
        assert u.commitments != nil and String.length(u.commitments) > 10
        assert u.scrape_timestamp == timestamp
      end
    end

    test "parses multiple airlines with same legislation", %{html: html, timestamp: timestamp} do
      undertakings = CaaUndertakingScraper.parse_html(html, timestamp)

      # Many airlines have EU261 undertakings
      eu261_undertakings =
        Enum.filter(undertakings, &String.contains?(&1.legislation, "261/2004"))

      assert length(eu261_undertakings) > 5
    end
  end

  describe "parse_date/1" do
    test "parses standard date format" do
      assert CaaUndertakingScraper.parse_date("26 July 2023") == ~D[2023-07-26]
      assert CaaUndertakingScraper.parse_date("14 February 2018") == ~D[2018-02-14]
      assert CaaUndertakingScraper.parse_date("1 December 2017") == ~D[2017-12-01]
    end

    test "parses date with extra whitespace" do
      assert CaaUndertakingScraper.parse_date("  20 March 2018  ") == ~D[2018-03-20]
    end

    test "returns nil for invalid date" do
      assert CaaUndertakingScraper.parse_date("invalid") == nil
      assert CaaUndertakingScraper.parse_date("") == nil
      assert CaaUndertakingScraper.parse_date(nil) == nil
    end

    test "handles all months" do
      assert CaaUndertakingScraper.parse_date("1 January 2020") == ~D[2020-01-01]
      assert CaaUndertakingScraper.parse_date("1 February 2020") == ~D[2020-02-01]
      assert CaaUndertakingScraper.parse_date("1 March 2020") == ~D[2020-03-01]
      assert CaaUndertakingScraper.parse_date("1 April 2020") == ~D[2020-04-01]
      assert CaaUndertakingScraper.parse_date("1 May 2020") == ~D[2020-05-01]
      assert CaaUndertakingScraper.parse_date("1 June 2020") == ~D[2020-06-01]
      assert CaaUndertakingScraper.parse_date("1 July 2020") == ~D[2020-07-01]
      assert CaaUndertakingScraper.parse_date("1 August 2020") == ~D[2020-08-01]
      assert CaaUndertakingScraper.parse_date("1 September 2020") == ~D[2020-09-01]
      assert CaaUndertakingScraper.parse_date("1 October 2020") == ~D[2020-10-01]
      assert CaaUndertakingScraper.parse_date("1 November 2020") == ~D[2020-11-01]
      assert CaaUndertakingScraper.parse_date("1 December 2020") == ~D[2020-12-01]
    end
  end

  describe "undertakings_url/0" do
    test "returns the CAA undertakings page URL" do
      url = CaaUndertakingScraper.undertakings_url()

      assert url == "https://www.caa.co.uk/our-work/about-us/enforcement/table-of-undertakings/"
    end
  end

  describe "ScrapedUndertaking struct" do
    test "has all expected fields" do
      undertaking = %ScrapedUndertaking{
        organisation: "Test Airline",
        date_provided: ~D[2023-01-15],
        date_provided_raw: "15 January 2023",
        legislation: "Regulation 261/2004",
        commitments: "To compensate passengers...",
        comments: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert undertaking.organisation == "Test Airline"
      assert undertaking.date_provided == ~D[2023-01-15]
      assert undertaking.legislation == "Regulation 261/2004"
      assert undertaking.commitments =~ "compensate"
    end

    test "is JSON encodable" do
      undertaking = %ScrapedUndertaking{
        organisation: "Test",
        date_provided: ~D[2023-01-01],
        date_provided_raw: "1 January 2023",
        legislation: "Test Law",
        commitments: "Test commitments",
        comments: nil,
        scrape_timestamp: ~U[2025-01-01 00:00:00Z]
      }

      assert {:ok, json} = Jason.encode(undertaking)
      assert is_binary(json)
    end
  end
end
