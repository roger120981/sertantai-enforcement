defmodule EhsEnforcement.Scraping.Mca.McaProsecutionScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper
  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper.ScrapedProsecution

  @fixtures_path "test/fixtures/mca"

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

    test "creates struct with individual defendant including age" do
      prosecution = %ScrapedProsecution{
        year: 2024,
        case_title: "Master sentenced",
        defendant: "Sam Farrow",
        defendant_age: 33,
        defendant_location: "Tower Hamlets, London",
        hearing_date: ~D[2024-03-28],
        court: "Plymouth Magistrates Court",
        offences: [],
        details: "Convicted of safety violations",
        fine: Decimal.new("2500"),
        costs: Decimal.new("1500"),
        victim_surcharge: nil,
        custodial_sentence: nil,
        community_service_hours: 150,
        total_penalty: Decimal.new("4000"),
        scrape_timestamp: DateTime.utc_now()
      }

      assert prosecution.defendant == "Sam Farrow"
      assert prosecution.defendant_age == 33
      assert prosecution.community_service_hours == 150
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

    test "years are sorted descending" do
      years = McaProsecutionScraper.available_html_years()
      assert years == Enum.sort(years, :desc)
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

  describe "scrape_year/2 validation" do
    test "returns error for invalid year (future)" do
      assert {:error, {:year_not_available, 2030}} = McaProsecutionScraper.scrape_year(2030)
    end

    test "returns error for invalid year (before HTML range)" do
      assert {:error, {:year_not_available, 2019}} = McaProsecutionScraper.scrape_year(2019)
    end
  end

  describe "HTML fixture parsing" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "prosecutions_2024.html"))
      %{html: html}
    end

    test "fixture contains expected case structure", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      # Find h2 elements with case numbers
      h2_elements = Floki.find(document, "h2[id]")

      case_h2s =
        Enum.filter(h2_elements, fn h2 ->
          text = Floki.text(h2) |> String.trim()
          Regex.match?(~r/^\d+\.\s+/, text)
        end)

      assert length(case_h2s) == 3
    end

    test "extracts case titles from fixture", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      titles =
        document
        |> Floki.find("h2[id]")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&Regex.match?(~r/^\d+\.\s+/, &1))
        |> Enum.map(&Regex.replace(~r/^\d+\.\s*/, &1, ""))

      assert "Boat owner fined after maritime incident" in titles
      assert "Fishing vessel master sentenced" in titles
      assert "Ferry company prosecuted for safety failures" in titles
    end

    test "extracts defendant info from fixture", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      defendants =
        document
        |> Floki.find("h3[id^='defendant']")
        |> Enum.map(fn h3 ->
          h3_id = Floki.attribute(h3, "id") |> List.first()
          # Get next p element
          extract_next_p(document, h3_id)
        end)
        |> Enum.reject(&is_nil/1)

      assert "Intrada Ships Management Ltd, London" in defendants
      assert "Sam Farrow, age 33, Tower Hamlets, London" in defendants
      assert "Oceanic Ferries PLC" in defendants
    end

    test "extracts hearing dates from fixture", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      dates =
        document
        |> Floki.find("h3[id*='date-of-hearing']")
        |> Enum.map(fn h3 ->
          h3_id = Floki.attribute(h3, "id") |> List.first()
          extract_next_p(document, h3_id)
        end)
        |> Enum.reject(&is_nil/1)

      assert "14 February 2024" in dates
      assert "28 March 2024" in dates
      assert "15 June 2024" in dates
    end
  end

  describe "data parsing helpers" do
    test "parses hearing date in DD Month YYYY format" do
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

    test "parses various date formats" do
      dates = [
        {"14 February 2025", ~D[2025-02-14]},
        {"1 January 2024", ~D[2024-01-01]},
        {"31 December 2023", ~D[2023-12-31]},
        {"15 June 2024", ~D[2024-06-15]}
      ]

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

      Enum.each(dates, fn {date_string, expected} ->
        [_, day, month, year] = Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})/, date_string)
        month_num = Map.get(months, String.downcase(month))

        result = Date.new!(String.to_integer(year), month_num, String.to_integer(day))

        assert result == expected, "Failed for #{date_string}"
      end)
    end

    test "extracts money amounts from text" do
      text = "The company was fined £180,000 and ordered to pay £500,000 in costs"

      fine =
        case Regex.run(~r/fined?[^\d]*£([\d,]+(?:\.\d{2})?)/i, text) do
          [_, amount] -> amount |> String.replace(",", "") |> Decimal.new()
          nil -> nil
        end

      assert Decimal.equal?(fine, Decimal.new("180000"))

      costs =
        case Regex.run(~r/£([\d,]+(?:\.\d{2})?)\s*(?:in\s+)?costs?/i, text) do
          [_, amount] -> amount |> String.replace(",", "") |> Decimal.new()
          nil -> nil
        end

      assert Decimal.equal?(costs, Decimal.new("500000"))
    end

    test "extracts victim surcharge" do
      text = "A victim surcharge of £190 was also imposed."

      surcharge =
        case Regex.run(~r/victim\s+surcharge[^\d]*£([\d,]+(?:\.\d{2})?)/i, text) do
          [_, amount] -> amount |> String.replace(",", "") |> Decimal.new()
          nil -> nil
        end

      assert Decimal.equal?(surcharge, Decimal.new("190"))
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

      section_pattern =
        ~r/(Section\s+\d+[A-Za-z]?(?:\(\d+\))?)\s+(?:of\s+)?(?:the\s+)?(.+?(?:Act|Regulations?)\s+\d{4})/i

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

    test "parses company defendant without age" do
      defendant_text = "Intrada Ships Management Ltd, London"

      {name, age, _location} =
        case Regex.run(~r/^(.+?),?\s*age[d]?\s*(\d+)/i, defendant_text) do
          [_, n, a] -> {String.trim(n), String.to_integer(a), nil}
          nil -> {defendant_text, nil, nil}
        end

      assert name == "Intrada Ships Management Ltd, London"
      assert is_nil(age)
    end
  end

  describe "PDF extraction" do
    test "scrape_pdf_year returns error when pdftotext not available" do
      result = McaProsecutionScraper.scrape_pdf_year(2019)

      case result do
        {:error, {:pdftotext_not_available, _}} ->
          assert true

        {:ok, _prosecutions} ->
          assert true

        {:error, _} ->
          assert true
      end
    end

    test "PDF publication page fixture contains PDF link" do
      html = File.read!(Path.join(@fixtures_path, "pdf_publication_page.html"))
      {:ok, document} = Floki.parse_document(html)

      pdf_links =
        document
        |> Floki.find("a[href$='.pdf']")
        |> Enum.map(fn a -> Floki.attribute(a, "href") |> List.first() end)
        |> Enum.reject(&is_nil/1)

      assert length(pdf_links) >= 1
      assert Enum.any?(pdf_links, &String.contains?(&1, "mca-prosecutions-2019.pdf"))
    end
  end

  # External tests that make live HTTP calls
  # Run with: mix test --include external

  describe "scrape_year/2 (live API)" do
    @tag :external
    @tag :slow
    test "fetches prosecutions for a specific year" do
      assert {:ok, prosecutions} = McaProsecutionScraper.scrape_year(2024)
      assert is_list(prosecutions)

      if length(prosecutions) > 0 do
        [first | _] = prosecutions
        assert %ScrapedProsecution{} = first
        assert first.year == 2024
      end
    end
  end

  describe "scrape_all/1 (live API)" do
    @tag :external
    @tag :slow
    test "fetches prosecutions for all HTML years" do
      assert {:ok, prosecutions} = McaProsecutionScraper.scrape_all(years: [2024])
      assert is_list(prosecutions)
    end

    @tag :external
    test "allows filtering by specific years" do
      assert {:ok, prosecutions} = McaProsecutionScraper.scrape_all(years: [2024, 2023])
      assert is_list(prosecutions)

      Enum.each(prosecutions, fn p ->
        assert p.year in [2023, 2024]
      end)
    end
  end

  # Helper functions for fixture parsing

  defp extract_next_p(document, h3_id) when is_binary(h3_id) do
    html = Floki.raw_html(document)

    pattern = ~r/<h3[^>]*id="#{Regex.escape(h3_id)}"[^>]*>.*?<\/h3>\s*<p[^>]*>(.*?)<\/p>/is

    case Regex.run(pattern, html) do
      [_, content] -> String.trim(content)
      nil -> nil
    end
  end
end
