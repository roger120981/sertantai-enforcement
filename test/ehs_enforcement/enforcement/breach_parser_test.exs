defmodule EhsEnforcement.Enforcement.BreachParserTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Enforcement.BreachParser

  describe "parse_breach/1" do
    test "parses HSE breach with Act and Section" do
      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1)"

      result = BreachParser.parse_breach(breach_text)

      assert result.offence_description == breach_text

      assert result.legislation_reference ==
               "Health and Safety at Work etc Act 1974, Section 2(1)"

      assert result.legislation_part == "Section 2(1)"
      assert result.act_name == "Health and Safety at Work etc Act 1974"
      assert result.act_year == 1974
      assert result.fine == nil
    end

    test "parses breach with Regulations" do
      breach_text =
        "Construction (Design and Management) Regulations 2015, Regulation 13(1)"

      result = BreachParser.parse_breach(breach_text)

      assert result.act_name == "Construction (Design and Management) Regulations 2015"
      assert result.act_year == 2015
      assert result.legislation_part == "Regulation 13(1)"
    end

    test "parses breach with multiple sections" do
      breach_text = "Health and Safety at Work etc Act 1974, Section 2 and 3"

      result = BreachParser.parse_breach(breach_text)

      assert result.legislation_part == "Section 2 and 3"
      assert result.act_name == "Health and Safety at Work etc Act 1974"
    end

    test "parses EA breach format" do
      breach_text =
        "Environmental Permitting (England and Wales) Regulations 2016, Regulation 38(1)"

      result = BreachParser.parse_breach(breach_text)

      assert result.act_name ==
               "Environmental Permitting (England and Wales) Regulations 2016"

      assert result.act_year == 2016
      assert result.legislation_part == "Regulation 38(1)"
    end

    test "parses breach with Article reference" do
      breach_text = "Some Order 2020, Article 5(2)"

      result = BreachParser.parse_breach(breach_text)

      assert result.legislation_part == "Article 5(2)"
      assert result.act_year == 2020
    end

    test "parses breach with Rule reference" do
      breach_text = "Some Regulations 2019, Rule 10"

      result = BreachParser.parse_breach(breach_text)

      assert result.legislation_part == "Rule 10"
      assert result.act_year == 2019
    end

    test "extracts fine from breach text" do
      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1). Fine: £5,000"

      result = BreachParser.parse_breach(breach_text)

      assert Decimal.equal?(result.fine, Decimal.new("5000"))
    end

    test "extracts fine with decimal precision" do
      breach_text =
        "Health and Safety at Work etc Act 1974, Section 2(1). Fine: £12,500.50"

      result = BreachParser.parse_breach(breach_text)

      assert Decimal.equal?(result.fine, Decimal.new("12500.50"))
    end

    test "handles breach without legislation reference" do
      breach_text = "Some general violation description"

      result = BreachParser.parse_breach(breach_text)

      assert result.offence_description == breach_text
      assert result.legislation_reference == nil
      assert result.legislation_part == nil
      assert result.act_name == nil
      assert result.act_year == nil
    end

    test "handles breach with Act but no Section" do
      breach_text = "Health and Safety at Work etc Act 1974"

      result = BreachParser.parse_breach(breach_text)

      assert result.act_name == "Health and Safety at Work etc Act 1974"
      assert result.act_year == 1974
      assert result.legislation_part == nil
    end

    test "trims whitespace from breach text" do
      breach_text = "  Health and Safety at Work etc Act 1974, Section 2(1)  "

      result = BreachParser.parse_breach(breach_text)

      assert result.offence_description == String.trim(breach_text)
    end

    test "handles empty breach text" do
      result = BreachParser.parse_breach("")

      assert result.offence_description == ""
      assert result.act_name == nil
    end
  end

  describe "parse_breaches/1 with semicolon-separated string" do
    test "parses multiple breaches from semicolon-separated string" do
      breaches =
        "Health and Safety at Work etc Act 1974, Section 2(1); Construction (Design and Management) Regulations 2015, Regulation 13(1)"

      results = BreachParser.parse_breaches(breaches)

      assert length(results) == 2
      assert Enum.at(results, 0).sequence_number == 1
      assert Enum.at(results, 0).act_name == "Health and Safety at Work etc Act 1974"
      assert Enum.at(results, 1).sequence_number == 2

      assert Enum.at(results, 1).act_name ==
               "Construction (Design and Management) Regulations 2015"
    end

    test "handles trailing/leading whitespace around semicolons" do
      breaches =
        "Health and Safety at Work etc Act 1974, Section 2(1) ; Construction (Design and Management) Regulations 2015, Regulation 13(1) "

      results = BreachParser.parse_breaches(breaches)

      assert length(results) == 2
      # Should trim whitespace from each breach
      assert String.trim(Enum.at(results, 0).offence_description) ==
               "Health and Safety at Work etc Act 1974, Section 2(1)"
    end

    test "ignores empty segments after splitting" do
      breaches = "Health and Safety at Work etc Act 1974, Section 2(1);; ; "

      results = BreachParser.parse_breaches(breaches)

      assert length(results) == 1
      assert Enum.at(results, 0).sequence_number == 1
    end

    test "handles single breach without semicolon" do
      breaches = "Health and Safety at Work etc Act 1974, Section 2(1)"

      results = BreachParser.parse_breaches(breaches)

      assert length(results) == 1
      assert Enum.at(results, 0).sequence_number == 1
    end

    test "handles empty string" do
      results = BreachParser.parse_breaches("")

      assert results == []
    end
  end

  describe "parse_breaches/1 with list" do
    test "parses list of breaches" do
      breaches = [
        "Health and Safety at Work etc Act 1974, Section 2(1)",
        "Construction (Design and Management) Regulations 2015, Regulation 13(1)",
        "Work at Height Regulations 2005, Regulation 4(1)"
      ]

      results = BreachParser.parse_breaches(breaches)

      assert length(results) == 3
      assert Enum.at(results, 0).sequence_number == 1
      assert Enum.at(results, 1).sequence_number == 2
      assert Enum.at(results, 2).sequence_number == 3

      assert Enum.at(results, 0).act_name == "Health and Safety at Work etc Act 1974"

      assert Enum.at(results, 1).act_name ==
               "Construction (Design and Management) Regulations 2015"

      assert Enum.at(results, 2).act_name == "Work at Height Regulations 2005"
    end

    test "handles empty list" do
      results = BreachParser.parse_breaches([])

      assert results == []
    end

    test "handles list with one item" do
      breaches = ["Health and Safety at Work etc Act 1974, Section 2(1)"]

      results = BreachParser.parse_breaches(breaches)

      assert length(results) == 1
      assert Enum.at(results, 0).sequence_number == 1
    end
  end

  describe "extract_legislation_title/1" do
    test "extracts Act name" do
      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1)"

      title = BreachParser.extract_legislation_title(breach_text)

      assert title == "Health and Safety at Work etc Act 1974"
    end

    test "extracts Regulations name" do
      breach_text =
        "Construction (Design and Management) Regulations 2015, Regulation 13(1)"

      title = BreachParser.extract_legislation_title(breach_text)

      assert title == "Construction (Design and Management) Regulations 2015"
    end

    test "returns 'Unknown Legislation' when no legislation found" do
      breach_text = "Some random violation text"

      title = BreachParser.extract_legislation_title(breach_text)

      assert title == "Unknown Legislation"
    end
  end

  describe "extract_legislation_type/1" do
    test "identifies Act" do
      breach_text = "Health and Safety at Work etc Act 1974"

      type = BreachParser.extract_legislation_type(breach_text)

      assert type == :act
    end

    test "identifies Regulations" do
      breach_text = "Construction (Design and Management) Regulations 2015"

      type = BreachParser.extract_legislation_type(breach_text)

      assert type == :regulation
    end

    test "identifies Order" do
      breach_text = "Some Order 2020"

      type = BreachParser.extract_legislation_type(breach_text)

      assert type == :order
    end

    test "returns nil for unknown type" do
      breach_text = "Some unknown legislation format"

      type = BreachParser.extract_legislation_type(breach_text)

      assert type == nil
    end
  end

  describe "clean_breach_text/1" do
    test "removes excess whitespace" do
      text = "Health and Safety    at   Work etc Act 1974"

      cleaned = BreachParser.clean_breach_text(text)

      assert cleaned == "Health and Safety at Work etc Act 1974"
    end

    test "normalizes line breaks" do
      text = "Health and Safety\nat Work etc\r\nAct 1974"

      cleaned = BreachParser.clean_breach_text(text)

      assert cleaned == "Health and Safety at Work etc Act 1974"
    end

    test "trims leading and trailing whitespace" do
      text = "  Health and Safety at Work etc Act 1974  \n"

      cleaned = BreachParser.clean_breach_text(text)

      assert cleaned == "Health and Safety at Work etc Act 1974"
    end

    test "handles empty string" do
      cleaned = BreachParser.clean_breach_text("")

      assert cleaned == ""
    end
  end

  describe "edge cases and real-world examples" do
    test "handles complex HSE breach with multiple subsections" do
      breach_text =
        "Health and Safety at Work etc Act 1974, Section 2(1) and 3(1). Fine: £25,000.00"

      result = BreachParser.parse_breach(breach_text)

      assert result.act_name == "Health and Safety at Work etc Act 1974"
      assert result.act_year == 1974
      assert result.legislation_part == "Section 2(1) and 3(1)"
      assert Decimal.equal?(result.fine, Decimal.new("25000"))
    end

    test "handles EA breach with no subsection number" do
      breach_text = "Environmental Permitting (England and Wales) Regulations 2016"

      result = BreachParser.parse_breach(breach_text)

      assert result.act_name ==
               "Environmental Permitting (England and Wales) Regulations 2016"

      assert result.act_year == 2016
      assert result.legislation_part == nil
    end

    test "handles lowercase 'fine' in text" do
      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1). fine: £1,500"

      result = BreachParser.parse_breach(breach_text)

      assert Decimal.equal?(result.fine, Decimal.new("1500"))
    end

    test "handles fine without comma separator" do
      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1). Fine: £500"

      result = BreachParser.parse_breach(breach_text)

      assert Decimal.equal?(result.fine, Decimal.new("500"))
    end

    test "handles very long legislation names" do
      breach_text =
        "The Control of Substances Hazardous to Health Regulations 2002, Regulation 7(1)"

      result = BreachParser.parse_breach(breach_text)

      assert result.act_name ==
               "The Control of Substances Hazardous to Health Regulations 2002"

      assert result.act_year == 2002
      assert result.legislation_part == "Regulation 7(1)"
    end
  end
end
