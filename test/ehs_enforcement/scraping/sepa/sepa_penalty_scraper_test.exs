defmodule EhsEnforcement.Scraping.Sepa.SepaPenaltyScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper.ScrapedPenalty

  @fixtures_path "test/fixtures/sepa"

  describe "HTML parsing" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "penalties_page.html"))
      {:ok, document} = Floki.parse_document(html)
      %{html: html, document: document}
    end

    test "parses penalties section correctly", %{document: document} do
      # Find the penalties section accordion items
      penalties_section =
        document
        |> Floki.find("h2#anchor-penaltiesimposedbyyear + .accordion .accordion-item")

      # Should find 2 accordion items (2025 and 2024)
      assert length(penalties_section) == 2
    end

    test "extracts penalty table rows correctly", %{document: document} do
      # Get all tables in the penalties section
      tables =
        document
        |> Floki.find("h2#anchor-penaltiesimposedbyyear + .accordion table")

      # Should have 2 tables (one for 2025, one for 2024)
      assert length(tables) == 2

      # Get rows from first table (2025)
      [first_table | _] = tables
      rows = Floki.find(first_table, "tbody tr")

      # Should have 4 rows (1 header + 3 data rows)
      assert length(rows) == 4
    end

    test "extracts penalty data from table cells", %{document: document} do
      # Get first data row from 2025 table
      [first_table | _] =
        document
        |> Floki.find("h2#anchor-penaltiesimposedbyyear + .accordion table")

      data_rows =
        first_table
        |> Floki.find("tbody tr")
        # Skip header row
        |> Enum.drop(1)

      [first_row | _] = data_rows
      cells = Floki.find(first_row, "td")

      assert length(cells) == 6

      # Extract cell values
      [penalty_type, name_address, date, offence, amount, _doc] = cells

      assert Floki.text(penalty_type) |> String.trim() == "Fixed monetary penalty"
      assert Floki.text(name_address) |> String.trim() == "Test Company Ltd, Edinburgh, EH1 1AA"
      assert Floki.text(date) |> String.trim() == "15 March 2025"
      assert String.contains?(Floki.text(offence), "Environmental Protection Act 1990")
      assert Floki.text(amount) |> String.trim() == "£600"
    end

    test "parses undertakings section correctly", %{document: document} do
      undertakings_section =
        document
        |> Floki.find("h2#anchor-undertakingsbyyear + .accordion .accordion-item")

      # Should find 1 accordion item (2025)
      assert length(undertakings_section) == 1

      # Get the table
      [table] =
        document
        |> Floki.find("h2#anchor-undertakingsbyyear + .accordion table")

      # Get data rows (skip header)
      data_rows =
        table
        |> Floki.find("tbody tr")
        |> Enum.drop(1)

      assert length(data_rows) == 1

      [row] = data_rows
      cells = Floki.find(row, "td")

      # Undertakings have 6 columns
      assert length(cells) == 6

      [type, name, date, offence, legislation, _doc] = cells

      assert Floki.text(type) |> String.trim() == "Enforcement undertaking"
      assert Floki.text(name) |> String.trim() == "Undertaking Corp, Inverness, IV1 1GH"
      assert Floki.text(date) |> String.trim() == "1 April 2025"
      assert String.contains?(Floki.text(legislation), "Pollution Prevention and Control")
    end

    test "parses costs recovery section correctly", %{document: document} do
      costs_section =
        document
        |> Floki.find("h2#anchor-costsrecoverynoticesissuedbyyear + .accordion .accordion-item")

      # Should find 1 accordion item (2025)
      assert length(costs_section) == 1

      # Get the table
      [table] =
        document
        |> Floki.find("h2#anchor-costsrecoverynoticesissuedbyyear + .accordion table")

      # Get data rows (skip header)
      data_rows =
        table
        |> Floki.find("tbody tr")
        |> Enum.drop(1)

      assert length(data_rows) == 1

      [row] = data_rows
      cells = Floki.find(row, "td")

      # Costs recovery has 4 columns
      assert length(cells) == 4

      [action, name, date, amount] = cells

      assert Floki.text(action) |> String.trim() == "Costs recovery"
      assert Floki.text(name) |> String.trim() == "Costs Recovery Ltd, Perth, PH1 1IJ"
      assert Floki.text(date) |> String.trim() == "20 May 2025"
      assert Floki.text(amount) |> String.trim() == "£1,500.00"
    end
  end

  describe "ScrapedPenalty struct" do
    test "can be created with all fields" do
      penalty = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company Ltd, Edinburgh, EH1",
        date: "15 March 2025",
        offence_details: "Environmental Protection Act 1990",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: DateTime.utc_now()
      }

      assert penalty.penalty_type == "Fixed monetary penalty"
      assert penalty.year == 2025
      assert penalty.section_type == :penalties
    end

    test "can encode to JSON" do
      penalty = %ScrapedPenalty{
        penalty_type: "Fixed monetary penalty",
        name_and_address: "Test Company Ltd",
        date: "15 March 2025",
        offence_details: "Test offence",
        penalty_amount: Decimal.new("600"),
        documentation_url: nil,
        legislation_breached: nil,
        year: 2025,
        section_type: :penalties,
        scrape_timestamp: ~U[2025-01-01 12:00:00Z]
      }

      assert {:ok, json} = Jason.encode(penalty)
      assert String.contains?(json, "Fixed monetary penalty")
      assert String.contains?(json, "Test Company Ltd")
    end
  end

  describe "penalty amount parsing" do
    test "parses standard amounts" do
      assert parse_amount("£600") == Decimal.new("600")
      assert parse_amount("£300") == Decimal.new("300")
      assert parse_amount("£1,000") == Decimal.new("1000")
    end

    test "parses amounts with decimals" do
      assert parse_amount("£2,500.50") == Decimal.new("2500.50")
      assert parse_amount("£1,129.25") == Decimal.new("1129.25")
    end

    test "handles nil and empty values" do
      assert parse_amount(nil) == nil
      assert parse_amount("") == nil
    end

    test "handles non-monetary text" do
      assert parse_amount("Available upon request") == nil
      assert parse_amount("N/A") == nil
    end
  end

  describe "year extraction" do
    test "extracts year from accordion button text" do
      assert extract_year("2025") == 2025
      assert extract_year("2024") == 2024
      assert extract_year(" 2023 ") == 2023
    end

    test "handles invalid year text" do
      assert extract_year("invalid") == nil
      assert extract_year("") == nil
      assert extract_year("19") == nil
    end
  end

  # Helper functions that mirror the scraper's internal logic

  defp parse_amount(nil), do: nil
  defp parse_amount(""), do: nil

  defp parse_amount(text) do
    case Regex.run(~r/£([\d,]+(?:\.\d{2})?)/, text) do
      [_, amount_str] ->
        amount_str
        |> String.replace(",", "")
        |> Decimal.parse()
        |> case do
          {decimal, _} -> decimal
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_year(text) do
    case Integer.parse(String.trim(text)) do
      {year, _} when year >= 2000 and year <= 2100 -> year
      _ -> nil
    end
  end
end
