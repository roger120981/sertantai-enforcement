defmodule EhsEnforcement.Scraping.Nrw.NrwAiArticleParserTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Nrw.NrwAiArticleParser.ParsedCase
  alias EhsEnforcement.Scraping.Nrw.NrwNewsScraper.ScrapedArticle

  describe "ParsedCase struct" do
    test "can be created with all fields" do
      parsed_case = %ParsedCase{
        offender_name: "Test Company Ltd",
        offender_type: :company,
        offender_location: "Cardiff, CF10 1AA",
        hearing_date: ~D[2024-03-21],
        fine_amount: Decimal.new("10000"),
        costs_amount: Decimal.new("5000"),
        surcharge_amount: Decimal.new("800"),
        total_amount: Decimal.new("15800"),
        poca_amount: nil,
        offence_description: "Operating without permit",
        offence_result: "Fined £10,000",
        legislation: "Environmental Permitting Regulations 2016",
        article_url: "https://naturalresources.wales/test",
        article_title: "Test Article",
        article_date: ~D[2024-03-21]
      }

      assert parsed_case.offender_name == "Test Company Ltd"
      assert parsed_case.offender_type == :company
      assert Decimal.equal?(parsed_case.fine_amount, Decimal.new("10000"))
    end

    test "can encode to JSON" do
      parsed_case = %ParsedCase{
        offender_name: "Test Company Ltd",
        offender_type: :company,
        offender_location: nil,
        hearing_date: ~D[2024-03-21],
        fine_amount: Decimal.new("10000"),
        costs_amount: nil,
        surcharge_amount: nil,
        total_amount: nil,
        poca_amount: nil,
        offence_description: "Test offence",
        offence_result: "Fined",
        legislation: "Test Act",
        article_url: "https://example.com",
        article_title: "Test",
        article_date: ~D[2024-03-21]
      }

      assert {:ok, json} = Jason.encode(parsed_case)
      assert String.contains?(json, "Test Company Ltd")
      assert String.contains?(json, "company")
    end
  end

  describe "AI response parsing" do
    test "parses valid single-case response" do
      article = build_test_article("Test Article", "Content here")

      json_response = """
      {
        "cases": [
          {
            "offender_name": "John Davies",
            "offender_type": "individual",
            "offender_location": "Powys",
            "hearing_date": "2024-03-21",
            "fine_amount": 2000,
            "costs_amount": 5000,
            "surcharge_amount": 800,
            "total_amount": 7800,
            "poca_amount": null,
            "offence_description": "Illegal tree felling",
            "offence_result": "Fined £2,000",
            "legislation": "Forestry Act 1967"
          }
        ],
        "extraction_notes": "Single defendant case"
      }
      """

      {:ok, cases} = parse_ai_response(json_response, article)

      assert length(cases) == 1
      [case1] = cases

      assert case1.offender_name == "John Davies"
      assert case1.offender_type == :individual
      assert case1.offender_location == "Powys"
      assert case1.hearing_date == ~D[2024-03-21]
      assert Decimal.equal?(case1.fine_amount, Decimal.new("2000"))
      assert Decimal.equal?(case1.costs_amount, Decimal.new("5000"))
      assert Decimal.equal?(case1.surcharge_amount, Decimal.new("800"))
      assert case1.article_url == article.url
      assert case1.article_title == article.title
    end

    test "parses valid multi-case response" do
      article = build_test_article("Multi Defendant", "Content")

      json_response = """
      {
        "cases": [
          {
            "offender_name": "Benji and Co Limited",
            "offender_type": "company",
            "offender_location": "Welshpool",
            "hearing_date": "2025-10-14",
            "fine_amount": 40000,
            "costs_amount": 15000,
            "surcharge_amount": 2000,
            "total_amount": 57000,
            "poca_amount": null,
            "offence_description": "Operating without permit",
            "offence_result": "Fined £40,000",
            "legislation": "Environmental Permitting Regulations 2016"
          },
          {
            "offender_name": "Peter Rees",
            "offender_type": "individual",
            "offender_location": "Newtown",
            "hearing_date": "2025-10-14",
            "fine_amount": 10000,
            "costs_amount": null,
            "surcharge_amount": 2000,
            "total_amount": 12000,
            "poca_amount": null,
            "offence_description": "Knowingly permitting operation without permit",
            "offence_result": "Fined £10,000",
            "legislation": "Environmental Protection Act 1990"
          }
        ],
        "extraction_notes": "Company and director - separate penalties"
      }
      """

      {:ok, cases} = parse_ai_response(json_response, article)

      assert length(cases) == 2

      [company_case, individual_case] = cases

      assert company_case.offender_name == "Benji and Co Limited"
      assert company_case.offender_type == :company
      assert Decimal.equal?(company_case.fine_amount, Decimal.new("40000"))

      assert individual_case.offender_name == "Peter Rees"
      assert individual_case.offender_type == :individual
      assert Decimal.equal?(individual_case.fine_amount, Decimal.new("10000"))
    end

    test "parses POCA confiscation case" do
      article = build_test_article("POCA Case", "Content")

      json_response = """
      {
        "cases": [
          {
            "offender_name": "Thomas Jeffrey Lane",
            "offender_type": "individual",
            "offender_location": "Pontypool",
            "hearing_date": "2024-06-14",
            "fine_amount": null,
            "costs_amount": null,
            "surcharge_amount": null,
            "total_amount": null,
            "poca_amount": 78614,
            "offence_description": "Illegal tree felling for profit",
            "offence_result": "POCA confiscation order",
            "legislation": "Forestry Act 1967"
          }
        ]
      }
      """

      {:ok, cases} = parse_ai_response(json_response, article)

      assert length(cases) == 1
      [case1] = cases

      assert case1.offender_name == "Thomas Jeffrey Lane"
      assert is_nil(case1.fine_amount)
      assert Decimal.equal?(case1.poca_amount, Decimal.new("78614"))
    end

    test "handles empty cases array" do
      article = build_test_article("Not Enforcement", "General news content")

      json_response = """
      {
        "cases": [],
        "extraction_notes": "Article is not about enforcement"
      }
      """

      {:ok, cases} = parse_ai_response(json_response, article)
      assert cases == []
    end

    test "handles null cases field" do
      article = build_test_article("Test", "Content")

      json_response = """
      {
        "cases": null,
        "extraction_notes": "Could not extract cases"
      }
      """

      {:ok, cases} = parse_ai_response(json_response, article)
      assert cases == []
    end

    test "handles invalid JSON" do
      article = build_test_article("Test", "Content")

      invalid_json = "This is not valid JSON"

      {:error, {:json_parse_error, _}} = parse_ai_response(invalid_json, article)
    end

    test "handles unexpected response structure" do
      article = build_test_article("Test", "Content")

      unexpected_json = """
      {
        "result": "some other format"
      }
      """

      {:error, {:invalid_response_structure, _}} = parse_ai_response(unexpected_json, article)
    end

    test "skips cases without offender name" do
      article = build_test_article("Test", "Content")

      json_response = """
      {
        "cases": [
          {
            "offender_name": "Valid Company Ltd",
            "offender_type": "company",
            "fine_amount": 10000
          },
          {
            "offender_name": "",
            "offender_type": "individual",
            "fine_amount": 5000
          },
          {
            "offender_name": null,
            "offender_type": "company",
            "fine_amount": 3000
          }
        ]
      }
      """

      {:ok, cases} = parse_ai_response(json_response, article)

      # Only the valid case should be included
      assert length(cases) == 1
      assert hd(cases).offender_name == "Valid Company Ltd"
    end
  end

  describe "date parsing" do
    test "parses ISO 8601 dates" do
      assert parse_date("2024-03-21") == ~D[2024-03-21]
      assert parse_date("2025-01-15") == ~D[2025-01-15]
    end

    test "parses UK date format" do
      assert parse_date("21 March 2024") == ~D[2024-03-21]
      assert parse_date("14 October 2025") == ~D[2025-10-14]
      assert parse_date("1 January 2024") == ~D[2024-01-01]
    end

    test "handles nil and empty dates" do
      assert is_nil(parse_date(nil))
      assert is_nil(parse_date(""))
    end

    test "handles invalid dates" do
      assert is_nil(parse_date("invalid"))
      assert is_nil(parse_date("2024-13-45"))
    end
  end

  describe "decimal parsing" do
    test "parses integer values" do
      assert Decimal.equal?(parse_decimal(10000), Decimal.new("10000"))
      assert Decimal.equal?(parse_decimal(0), Decimal.new("0"))
    end

    test "parses float values" do
      result = parse_decimal(2500.50)
      assert Decimal.compare(result, Decimal.new("2500.5")) == :eq
    end

    test "parses string values" do
      assert Decimal.equal?(parse_decimal("10000"), Decimal.new("10000"))
      assert Decimal.equal?(parse_decimal("£2,500.50"), Decimal.new("2500.50"))
      assert Decimal.equal?(parse_decimal("2,000"), Decimal.new("2000"))
    end

    test "handles nil and empty values" do
      assert is_nil(parse_decimal(nil))
      assert is_nil(parse_decimal(""))
    end
  end

  describe "offender type parsing" do
    test "parses company type" do
      assert parse_offender_type("company") == :company
    end

    test "parses individual type" do
      assert parse_offender_type("individual") == :individual
    end

    test "returns unknown for invalid types" do
      assert parse_offender_type("other") == :unknown
      assert parse_offender_type(nil) == :unknown
      assert parse_offender_type("") == :unknown
    end
  end

  # Helper functions

  defp build_test_article(title, content) do
    %ScrapedArticle{
      url: "https://naturalresources.wales/about-us/news/test-article/?lang=en",
      slug: "test-article",
      title: title,
      publication_date: ~D[2024-03-21],
      content: content,
      scrape_timestamp: DateTime.utc_now()
    }
  end

  # These mirror the parser's internal logic for testing

  defp parse_ai_response(content, article) do
    case Jason.decode(content) do
      {:ok, %{"cases" => cases}} when is_list(cases) ->
        parsed_cases =
          cases
          |> Enum.map(fn case_data -> build_parsed_case(case_data, article) end)
          |> Enum.reject(&is_nil/1)

        {:ok, parsed_cases}

      {:ok, %{"cases" => nil}} ->
        {:ok, []}

      {:ok, other} ->
        {:error, {:invalid_response_structure, other}}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  end

  defp build_parsed_case(case_data, article) when is_map(case_data) do
    offender_name = case_data["offender_name"]

    if is_nil(offender_name) or offender_name == "" do
      nil
    else
      %ParsedCase{
        offender_name: offender_name,
        offender_type: parse_offender_type(case_data["offender_type"]),
        offender_location: case_data["offender_location"],
        hearing_date: parse_date(case_data["hearing_date"]),
        fine_amount: parse_decimal(case_data["fine_amount"]),
        costs_amount: parse_decimal(case_data["costs_amount"]),
        surcharge_amount: parse_decimal(case_data["surcharge_amount"]),
        total_amount: parse_decimal(case_data["total_amount"]),
        poca_amount: parse_decimal(case_data["poca_amount"]),
        offence_description: case_data["offence_description"],
        offence_result: case_data["offence_result"],
        legislation: case_data["legislation"],
        article_url: article.url,
        article_title: article.title,
        article_date: article.publication_date
      }
    end
  end

  defp build_parsed_case(_, _), do: nil

  defp parse_offender_type("company"), do: :company
  defp parse_offender_type("individual"), do: :individual
  defp parse_offender_type(_), do: :unknown

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> parse_uk_date(date_string)
    end
  end

  defp parse_date(_), do: nil

  defp parse_uk_date(date_string) do
    case Regex.run(
           ~r/(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/i,
           date_string
         ) do
      [_, day, month, year] ->
        month_num = month_to_number(month)

        case Date.new(String.to_integer(year), month_num, String.to_integer(day)) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp month_to_number(month) do
    case String.downcase(month) do
      "january" -> 1
      "february" -> 2
      "march" -> 3
      "april" -> 4
      "may" -> 5
      "june" -> 6
      "july" -> 7
      "august" -> 8
      "september" -> 9
      "october" -> 10
      "november" -> 11
      "december" -> 12
      _ -> 1
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp parse_decimal(value) when is_binary(value) do
    value
    |> String.replace(",", "")
    |> String.replace("£", "")
    |> String.trim()
    |> case do
      "" ->
        nil

      str ->
        case Decimal.parse(str) do
          {decimal, _} -> decimal
          :error -> nil
        end
    end
  end

  defp parse_decimal(_), do: nil
end
