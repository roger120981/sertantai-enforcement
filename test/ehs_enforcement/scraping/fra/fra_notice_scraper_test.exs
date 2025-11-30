defmodule EhsEnforcement.Scraping.Fra.FraNoticeScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper
  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper.ScrapedNotice

  describe "ScrapedNotice struct" do
    test "creates struct with all fields" do
      notice = %ScrapedNotice{
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

      assert notice.uprn == "83224833"
      assert notice.frs == "West Yorkshire"
      assert notice.notice_type == "ENFORCEMENT"
      assert notice.status == "IN FORCE"
    end
  end

  describe "scrape_all/1" do
    @tag :external
    @tag :slow
    test "fetches notices from NFCC register" do
      # This test requires network access and takes time
      # Run with: mix test --include external

      assert {:ok, notices} = FraNoticeScraper.scrape_all(max_pages: 1, page_size: 5)
      assert is_list(notices)
      assert length(notices) > 0

      # Check first notice has expected structure
      [first | _] = notices
      assert %ScrapedNotice{} = first
      assert is_binary(first.uprn) or is_nil(first.uprn)
      assert is_binary(first.frs)
      assert is_binary(first.notice_type)
      assert first.notice_type in ["PROHIBITION", "ENFORCEMENT", "ALTERATIONS"]
    end

    @tag :external
    test "filters by notice type" do
      assert {:ok, notices} =
               FraNoticeScraper.scrape_all(
                 notice_type: "PROHIBITION",
                 max_pages: 1,
                 page_size: 10
               )

      # All returned notices should be PROHIBITION type
      Enum.each(notices, fn notice ->
        assert notice.notice_type == "PROHIBITION"
      end)
    end
  end

  describe "get_total_count/0" do
    @tag :external
    test "returns total record count" do
      assert {:ok, count} = FraNoticeScraper.get_total_count()
      assert is_integer(count)
      # NFCC register has ~7700 records as of Nov 2025
      assert count > 5000
    end
  end

  describe "data parsing" do
    test "normalizes address with line breaks" do
      # Simulate the internal normalize_address function behavior
      address = "Chicken Cottage, 196-198 Alma Road, Bournemouth\r\n, BH9 1AJ"

      normalized =
        address
        |> String.replace("\r\n", ", ")
        |> String.replace("\n", ", ")
        |> String.replace(~r/\s+/, " ")
        |> String.replace(~r/,\s*,/, ",")
        |> String.trim()
        |> String.trim_trailing(",")

      assert normalized == "Chicken Cottage, 196-198 Alma Road, Bournemouth, BH9 1AJ"
    end

    test "parses DD/MM/YYYY date format" do
      date_string = "06/11/2025"

      result =
        case Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, date_string) do
          [_, day, month, year] ->
            Date.new!(
              String.to_integer(year),
              String.to_integer(month),
              String.to_integer(day)
            )

          _ ->
            nil
        end

      assert result == ~D[2025-11-06]
    end
  end
end
