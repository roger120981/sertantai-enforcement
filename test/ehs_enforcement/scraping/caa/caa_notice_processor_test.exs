defmodule EhsEnforcement.Scraping.Caa.CaaNoticeProcessorTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Caa.CaaNoticeProcessor
  alias EhsEnforcement.Scraping.Caa.CaaNoticeProcessor.ProcessedUndertaking
  alias EhsEnforcement.Scraping.Caa.CaaUndertakingScraper.ScrapedUndertaking

  describe "process_undertaking/1" do
    test "processes a scraped undertaking into correct format" do
      scraped = %ScrapedUndertaking{
        organisation: "Wizz Air",
        date_provided: ~D[2023-07-26],
        date_provided_raw: "26 July 2023",
        legislation: "Regulation 261/2004",
        commitments:
          "To offer passengers whose flights have been cancelled the choice of re-routing.",
        comments: nil,
        scrape_timestamp: ~U[2025-12-02 12:00:00Z]
      }

      assert {:ok, processed} = CaaNoticeProcessor.process_undertaking(scraped)

      assert %ProcessedUndertaking{} = processed
      assert processed.agency_code == :caa
      assert processed.regulator_id == "caa_undertaking_20230726_wizz_air"
      assert processed.notice_date == ~D[2023-07-26]
      assert processed.offence_action_type == "CAA Undertaking"
      assert processed.offence_breaches == "Legislation: Regulation 261/2004"
      assert processed.notice_body =~ "COMMITMENTS:"
      assert processed.notice_body =~ "re-routing"
      assert processed.notice_body =~ "without admission of wrongdoing"
      assert processed.url =~ "caa.co.uk"
    end

    test "generates deterministic regulator_id" do
      scraped = %ScrapedUndertaking{
        organisation: "Emirates",
        date_provided: ~D[2018-03-29],
        date_provided_raw: "29 March 2018",
        legislation: "Regulation 261/2004",
        commitments: "To compensate passengers.",
        comments: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed1} = CaaNoticeProcessor.process_undertaking(scraped)
      assert {:ok, processed2} = CaaNoticeProcessor.process_undertaking(scraped)

      assert processed1.regulator_id == processed2.regulator_id
      assert processed1.regulator_id == "caa_undertaking_20180329_emirates"
    end

    test "handles missing date gracefully" do
      scraped = %ScrapedUndertaking{
        organisation: "Test Airline",
        date_provided: nil,
        date_provided_raw: nil,
        legislation: "Test Law",
        commitments: "Test commitments",
        comments: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = CaaNoticeProcessor.process_undertaking(scraped)

      assert processed.notice_date == nil
      assert processed.regulator_id =~ "00000000"
    end

    test "builds offender attributes correctly" do
      scraped = %ScrapedUndertaking{
        organisation: "British Airways plc",
        date_provided: ~D[2017-06-15],
        date_provided_raw: "15 June 2017",
        legislation: "Regulation 261/2004",
        commitments: "Test commitments",
        comments: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = CaaNoticeProcessor.process_undertaking(scraped)

      assert processed.offender_attrs.name == "British Airways plc"
      assert processed.offender_attrs.country == "United Kingdom"
    end

    test "includes comments in notice body when present" do
      scraped = %ScrapedUndertaking{
        organisation: "Test Airline",
        date_provided: ~D[2020-01-01],
        date_provided_raw: "1 January 2020",
        legislation: "Test Law",
        commitments: "Main commitments here.",
        comments: "Additional context about the undertaking.",
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = CaaNoticeProcessor.process_undertaking(scraped)

      assert processed.notice_body =~ "COMMITMENTS:"
      assert processed.notice_body =~ "Main commitments here"
      assert processed.notice_body =~ "COMMENTS:"
      assert processed.notice_body =~ "Additional context"
    end

    test "handles special characters in organisation name" do
      scraped = %ScrapedUndertaking{
        organisation: "TUI UK Ltd & Partners",
        date_provided: ~D[2019-05-10],
        date_provided_raw: "10 May 2019",
        legislation: "Regulation 261/2004",
        commitments: "Test commitments",
        comments: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert {:ok, processed} = CaaNoticeProcessor.process_undertaking(scraped)

      # Special characters should be normalized in regulator_id
      assert processed.regulator_id == "caa_undertaking_20190510_tui_uk_ltd_partners"
      assert processed.offender_attrs.name == "TUI UK Ltd & Partners"
    end
  end

  describe "process_undertakings/1" do
    test "processes multiple undertakings" do
      undertakings = [
        %ScrapedUndertaking{
          organisation: "Airline A",
          date_provided: ~D[2023-01-01],
          date_provided_raw: "1 January 2023",
          legislation: "Regulation 261/2004",
          commitments: "Commitment A",
          comments: nil,
          scrape_timestamp: DateTime.utc_now()
        },
        %ScrapedUndertaking{
          organisation: "Airline B",
          date_provided: ~D[2023-02-01],
          date_provided_raw: "1 February 2023",
          legislation: "Regulation 261/2004",
          commitments: "Commitment B",
          comments: nil,
          scrape_timestamp: DateTime.utc_now()
        }
      ]

      assert {:ok, processed_list} = CaaNoticeProcessor.process_undertakings(undertakings)

      assert length(processed_list) == 2
      assert Enum.all?(processed_list, &match?(%ProcessedUndertaking{}, &1))
    end

    test "preserves order of undertakings" do
      undertakings = [
        %ScrapedUndertaking{
          organisation: "First",
          date_provided: ~D[2023-01-01],
          date_provided_raw: "1 January 2023",
          legislation: "Law",
          commitments: "Commitment",
          comments: nil,
          scrape_timestamp: DateTime.utc_now()
        },
        %ScrapedUndertaking{
          organisation: "Second",
          date_provided: ~D[2023-02-01],
          date_provided_raw: "1 February 2023",
          legislation: "Law",
          commitments: "Commitment",
          comments: nil,
          scrape_timestamp: DateTime.utc_now()
        }
      ]

      assert {:ok, processed_list} = CaaNoticeProcessor.process_undertakings(undertakings)

      [first, second] = processed_list
      assert first.offender_attrs.name == "First"
      assert second.offender_attrs.name == "Second"
    end
  end

  describe "ProcessedUndertaking struct" do
    test "has all expected fields" do
      processed = %ProcessedUndertaking{
        regulator_id: "caa_undertaking_20230101_test",
        agency_code: :caa,
        offender_attrs: %{name: "Test", country: "United Kingdom"},
        notice_date: ~D[2023-01-01],
        notice_body: "Test body",
        offence_breaches: "Legislation: Test",
        offence_action_type: "CAA Undertaking",
        url: "https://example.com"
      }

      assert processed.regulator_id == "caa_undertaking_20230101_test"
      assert processed.agency_code == :caa
      assert processed.notice_date == ~D[2023-01-01]
      assert processed.offence_action_type == "CAA Undertaking"
    end

    test "is JSON encodable" do
      processed = %ProcessedUndertaking{
        regulator_id: "caa_undertaking_20230101_test",
        agency_code: :caa,
        offender_attrs: %{name: "Test", country: "United Kingdom"},
        notice_date: ~D[2023-01-01],
        notice_body: "Test body",
        offence_breaches: "Legislation: Test",
        offence_action_type: "CAA Undertaking",
        url: "https://example.com",
        source_metadata: %{source: "caa.co.uk"}
      }

      assert {:ok, json} = Jason.encode(processed)
      assert is_binary(json)
    end
  end

  describe "integration with scraper output" do
    test "processes real scraped undertaking format" do
      # Simulate what CaaUndertakingScraper.parse_html returns
      scraped = %ScrapedUndertaking{
        organisation: "Manchester Airport PLC",
        date_provided: ~D[2018-03-20],
        date_provided_raw: "20 March 2018",
        legislation: "Regulation 1107/2006",
        commitments: """
        To develop a performance improvement plan to provide a high quality and consistent assistance service to disabled persons and persons with reduced mobility.

        To consult the Civil Aviation Authority (CAA) and organisations and groups representing disabled people in developing the performance improvement plan.

        To publish the performance improvement plan on its website prior to implementation.

        To meet deadlines for publishing and submitting data.
        """,
        comments: nil,
        scrape_timestamp: ~U[2025-12-02 12:00:00Z]
      }

      assert {:ok, processed} = CaaNoticeProcessor.process_undertaking(scraped)

      assert processed.regulator_id == "caa_undertaking_20180320_manchester_airport_plc"
      assert processed.offence_breaches == "Legislation: Regulation 1107/2006"
      assert processed.notice_body =~ "performance improvement plan"
      assert processed.notice_body =~ "disabled persons"
      assert processed.notice_body =~ "without admission of wrongdoing"
    end
  end
end
