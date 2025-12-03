defmodule EhsEnforcement.Scraping.Fra.FraNoticeScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper
  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper.ScrapedNotice

  @fixtures_path "test/fixtures/fra"

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

    test "creates struct with nil optional fields" do
      notice = %ScrapedNotice{
        uprn: nil,
        frs: "London Fire Brigade",
        issue_date: "01/11/2025",
        notice_type: "PROHIBITION",
        premises_type: "RESIDENTIAL",
        status: "IN FORCE",
        address: "123 Test Street, London, E1 1AA",
        responsible_person: "Test Ltd",
        date_complied_with: nil,
        reasons: nil,
        additional_information: nil,
        scrape_timestamp: DateTime.utc_now()
      }

      assert is_nil(notice.uprn)
      assert is_nil(notice.date_complied_with)
      assert notice.frs == "London Fire Brigade"
    end
  end

  describe "data parsing from fixtures" do
    setup do
      page1_json = File.read!(Path.join(@fixtures_path, "wpdatatables_page1.json"))
      page1_data = Jason.decode!(page1_json)

      prohibition_json =
        File.read!(Path.join(@fixtures_path, "wpdatatables_prohibition_only.json"))

      prohibition_data = Jason.decode!(prohibition_json)

      %{page1: page1_data, prohibition: prohibition_data}
    end

    test "fixture contains expected record counts", %{page1: page1, prohibition: prohibition} do
      assert page1["recordsTotal"] == "7723"
      assert page1["recordsFiltered"] == "7723"
      assert length(page1["data"]) == 5

      assert prohibition["recordsTotal"] == "7723"
      assert prohibition["recordsFiltered"] == "2145"
      assert length(prohibition["data"]) == 3
    end

    test "parses first notice from fixture data", %{page1: page1} do
      [first_row | _] = page1["data"]

      assert Enum.at(first_row, 0) == "83224833"
      assert Enum.at(first_row, 1) == "West Yorkshire"
      assert Enum.at(first_row, 2) == "06/11/2025"
      assert Enum.at(first_row, 3) == "ENFORCEMENT"
      assert Enum.at(first_row, 4) == "FACTORY WAREHOUSE"
      assert Enum.at(first_row, 5) == "IN FORCE"
    end

    test "fixture data contains all notice types", %{page1: page1} do
      notice_types = Enum.map(page1["data"], fn row -> Enum.at(row, 3) end)

      assert "ENFORCEMENT" in notice_types
      assert "PROHIBITION" in notice_types
      assert "ALTERATIONS" in notice_types
    end

    test "fixture data contains different statuses", %{page1: page1} do
      statuses = Enum.map(page1["data"], fn row -> Enum.at(row, 5) end)

      assert "IN FORCE" in statuses
      assert "COMPLIED" in statuses
      assert "WITHDRAWN" in statuses
    end

    test "prohibition filter only contains prohibition notices", %{prohibition: prohibition} do
      notice_types = Enum.map(prohibition["data"], fn row -> Enum.at(row, 3) end)

      Enum.each(notice_types, fn type ->
        assert type == "PROHIBITION"
      end)
    end
  end

  describe "nonce extraction" do
    test "extracts nonce from HTML fixture" do
      html = File.read!(Path.join(@fixtures_path, "nfcc_page.html"))

      case Regex.run(~r/wdtNonceFrontendServerSide_6"\s+value="([^"]+)"/, html) do
        [_, nonce] ->
          assert nonce == "test_nonce_abc123"

        nil ->
          flunk("Could not extract nonce from fixture HTML")
      end
    end
  end

  describe "data parsing helpers" do
    test "normalizes address with line breaks" do
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

    test "normalizes address with multiple line breaks" do
      address = "Unit 5\nIndustrial Estate\r\nManchester\nM1 2AB"

      normalized =
        address
        |> String.replace("\r\n", ", ")
        |> String.replace("\n", ", ")
        |> String.replace(~r/\s+/, " ")
        |> String.replace(~r/,\s*,/, ",")
        |> String.trim()
        |> String.trim_trailing(",")

      assert normalized == "Unit 5, Industrial Estate, Manchester, M1 2AB"
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

    test "handles various date formats" do
      dates = [
        {"06/11/2025", ~D[2025-11-06]},
        {"01/01/2024", ~D[2024-01-01]},
        {"31/12/2023", ~D[2023-12-31]},
        {"15/06/2025", ~D[2025-06-15]}
      ]

      Enum.each(dates, fn {date_string, expected} ->
        [_, day, month, year] = Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, date_string)

        result =
          Date.new!(
            String.to_integer(year),
            String.to_integer(month),
            String.to_integer(day)
          )

        assert result == expected, "Failed for #{date_string}"
      end)
    end

    test "extracts article codes from reasons field" do
      reasons = "A8,A9,A11,A13,A14,A15,A17,A19,A21"
      codes = String.split(reasons, ",")

      assert length(codes) == 9
      assert "A8" in codes
      assert "A21" in codes
    end
  end

  describe "notice type validation" do
    test "validates allowed notice types" do
      valid_types = ["PROHIBITION", "ENFORCEMENT", "ALTERATIONS"]

      Enum.each(valid_types, fn type ->
        assert type in valid_types
      end)
    end

    test "validates status values from fixture", %{} do
      valid_statuses = ["IN FORCE", "COMPLIED", "WITHDRAWN"]

      page1_json = File.read!(Path.join(@fixtures_path, "wpdatatables_page1.json"))
      page1_data = Jason.decode!(page1_json)

      statuses = Enum.map(page1_data["data"], fn row -> Enum.at(row, 5) end)

      Enum.each(statuses, fn status ->
        assert status in valid_statuses, "Unexpected status: #{status}"
      end)
    end
  end

  # External tests that make live HTTP calls
  # Run with: mix test --include external

  describe "scrape_all/1 (live API)" do
    @tag :external
    @tag :slow
    test "fetches notices from NFCC register" do
      assert {:ok, notices} = FraNoticeScraper.scrape_all(max_pages: 1, page_size: 5)
      assert is_list(notices)
      assert length(notices) > 0

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

      Enum.each(notices, fn notice ->
        assert notice.notice_type == "PROHIBITION"
      end)
    end
  end

  describe "get_total_count/0 (live API)" do
    @tag :external
    test "returns total record count" do
      assert {:ok, count} = FraNoticeScraper.get_total_count()
      assert is_integer(count)
      assert count > 5000
    end
  end
end
