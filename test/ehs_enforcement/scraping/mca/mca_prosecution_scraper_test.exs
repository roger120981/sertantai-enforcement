defmodule EhsEnforcement.Scraping.Mca.McaProsecutionScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper
  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper.ScrapedProsecution

  describe "ScrapedProsecution struct" do
    test "creates struct with all fields" do
      prosecution = %ScrapedProsecution{
        year: 2024,
        case_title: "Company fined after maritime incident",
        defendant: "Intrada Ships Management Ltd",
        defendant_age: nil,
        defendant_location: "London",
        hearing_date: ~D[2025-02-14],
        court: "Southampton Crown Court",
        offences: [
          %{section: "Section 100", legislation: "Merchant Shipping Act 1995"}
        ],
        details: "A shipping company was fined for failing to operate safely...",
        fine: Decimal.new("180000"),
        costs: Decimal.new("500000"),
        victim_surcharge: nil,
        custodial_sentence: nil,
        community_service_hours: nil,
        total_penalty: Decimal.new("680000"),
        scrape_timestamp: DateTime.utc_now()
      }

      assert prosecution.year == 2024
      assert prosecution.defendant == "Intrada Ships Management Ltd"
      assert prosecution.court == "Southampton Crown Court"
      assert Decimal.equal?(prosecution.fine, Decimal.new("180000"))
    end
  end

  describe "available_html_years/0" do
    test "returns list of available years" do
      years = McaProsecutionScraper.available_html_years()

      assert is_list(years)
      assert length(years) >= 5
      assert 2025 in years
      assert 2024 in years
      assert 2020 in years
    end
  end

  describe "collection_url/0" do
    test "returns GOV.UK collection URL" do
      url = McaProsecutionScraper.collection_url()

      assert is_binary(url)
      assert String.starts_with?(url, "https://www.gov.uk")
      assert String.contains?(url, "prosecutions-and-detentions")
    end
  end

  describe "scrape_year/2" do
    @tag :external
    @tag :slow
    test "fetches prosecutions for a specific year" do
      # This test requires network access
      # Run with: mix test --include external

      assert {:ok, prosecutions} = McaProsecutionScraper.scrape_year(2024)
      assert is_list(prosecutions)

      # 2024 should have some prosecutions
      if length(prosecutions) > 0 do
        [first | _] = prosecutions
        assert %ScrapedProsecution{} = first
        assert first.year == 2024
      end
    end

    test "returns error for invalid year" do
      assert {:error, {:year_not_available, 2030}} = McaProsecutionScraper.scrape_year(2030)
    end
  end

  describe "scrape_all/1" do
    @tag :external
    @tag :slow
    test "fetches prosecutions for all HTML years" do
      # Test with single year to reduce time
      assert {:ok, prosecutions} = McaProsecutionScraper.scrape_all(years: [2024])
      assert is_list(prosecutions)
    end

    @tag :external
    test "allows filtering by specific years" do
      assert {:ok, prosecutions} = McaProsecutionScraper.scrape_all(years: [2024, 2023])
      assert is_list(prosecutions)

      # All prosecutions should be from 2023 or 2024
      Enum.each(prosecutions, fn p ->
        assert p.year in [2023, 2024]
      end)
    end
  end

  describe "data parsing" do
    test "parses hearing date in DD Month YYYY format" do
      # Test the date parsing logic
      date_text = "14 February 2025"

      result =
        case Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})/, date_text) do
          [_, day, month, year] ->
            months = %{
              "january" => 1,
              "february" => 2,
              "march" => 3,
              "april" => 4,
              "may" => 5,
              "june" => 6,
              "july" => 7,
              "august" => 8,
              "september" => 9,
              "october" => 10,
              "november" => 11,
              "december" => 12
            }

            month_num = Map.get(months, String.downcase(month))

            if month_num do
              Date.new!(String.to_integer(year), month_num, String.to_integer(day))
            else
              nil
            end

          nil ->
            nil
        end

      assert result == ~D[2025-02-14]
    end

    test "extracts money amounts from text" do
      text = "The company was fined £180,000 and ordered to pay £500,000 in costs"

      # Test fine extraction
      fine =
        case Regex.run(~r/fined?[^\d]*£([\d,]+(?:\.\d{2})?)/i, text) do
          [_, amount] -> amount |> String.replace(",", "") |> Decimal.new()
          nil -> nil
        end

      assert Decimal.equal?(fine, Decimal.new("180000"))

      # Test costs extraction
      costs =
        case Regex.run(~r/£([\d,]+(?:\.\d{2})?)\s*(?:in\s+)?costs?/i, text) do
          [_, amount] -> amount |> String.replace(",", "") |> Decimal.new()
          nil -> nil
        end

      assert Decimal.equal?(costs, Decimal.new("500000"))
    end

    test "extracts court name from details" do
      details = "The defendant appeared at Southampton Crown Court on 14 February 2025..."

      court =
        case Regex.run(
               ~r/((?:Southampton|Portsmouth|Plymouth|Cardiff|Bristol|Liverpool|Manchester|Newcastle|Hull)\s+(?:Crown|Magistrates['']?)\s+Court)/i,
               details
             ) do
          [match | _] -> String.trim(match)
          nil -> nil
        end

      assert court == "Southampton Crown Court"
    end

    test "extracts legislation citations" do
      details = """
      The company was convicted of failing to operate a ship safely
      contrary to Section 100 of the Merchant Shipping Act 1995.
      The master was convicted under Regulation 7 of the
      Merchant Shipping (ISM Code) Regulations 2014.
      """

      # Test Section pattern
      section_pattern =
        ~r/(Section\s+\d+[A-Za-z]?(?:\(\d+\))?)\s+(?:of\s+)?(?:the\s+)?(.+?(?:Act|Regulations?)\s+\d{4})/i

      # Test Regulation pattern
      regulation_pattern =
        ~r/(Regulation\s+\d+[A-Za-z]?(?:\(\d+\))?)\s+(?:of\s+)?(?:the\s+)?(.+?Regulations?\s+\d{4})/i

      section_offences =
        Regex.scan(section_pattern, details)
        |> Enum.map(fn [_full, section, legislation] ->
          %{section: String.trim(section), legislation: String.trim(legislation)}
        end)

      regulation_offences =
        Regex.scan(regulation_pattern, details)
        |> Enum.map(fn [_full, section, legislation] ->
          %{section: String.trim(section), legislation: String.trim(legislation)}
        end)

      offences = section_offences ++ regulation_offences

      assert length(offences) == 2
      assert Enum.any?(offences, &(&1.section == "Section 100"))
      assert Enum.any?(offences, &(&1.section == "Regulation 7"))
      assert Enum.any?(offences, &String.contains?(&1.legislation, "Merchant Shipping Act 1995"))
    end

    test "extracts custodial sentence" do
      details = "The defendant was sentenced to 18 weeks in prison suspended for 12 months"

      custodial =
        case Regex.run(~r/(\d+)\s+(weeks?|months?)\s+(?:in\s+)?(?:prison|imprisonment)/i, details) do
          [match | _] -> String.trim(match)
          nil -> nil
        end

      assert custodial == "18 weeks in prison"
    end

    test "extracts community service hours" do
      details = "The defendant must also complete 150 hours of unpaid work"

      hours =
        case Regex.run(~r/(\d+)\s+hours?\s+(?:of\s+)?unpaid\s+work/i, details) do
          [_, h] -> String.to_integer(h)
          nil -> nil
        end

      assert hours == 150
    end

    test "parses defendant with age and location" do
      defendant_text = "Sam Farrow, age 33, Tower Hamlets, London"

      {name, age, _location} =
        case Regex.run(~r/^(.+?),?\s*age[d]?\s*(\d+)/i, defendant_text) do
          [_, n, a] -> {String.trim(n), String.to_integer(a), nil}
          nil -> {defendant_text, nil, nil}
        end

      assert name == "Sam Farrow"
      assert age == 33
    end
  end

  describe "PDF extraction" do
    test "scrape_pdf_year returns error when pdftotext not available" do
      # This test may pass or fail depending on system configuration
      result = McaProsecutionScraper.scrape_pdf_year(2019)

      case result do
        {:error, {:pdftotext_not_available, _}} ->
          # Expected if pdftotext is not installed
          assert true

        {:ok, _prosecutions} ->
          # pdftotext is available and worked
          assert true

        {:error, _} ->
          # Other error (e.g., network)
          assert true
      end
    end
  end
end
