defmodule EhsEnforcement.UtilityTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Utility

  describe "normalize_legislation_title/1" do
    test "converts all caps to proper title case" do
      assert Utility.normalize_legislation_title("HEALTH AND SAFETY AT WORK ACT") ==
               "Health and Safety at Work Act"
    end

    test "handles small words correctly" do
      assert Utility.normalize_legislation_title(
               "control of substances hazardous to health regulations"
             ) ==
               "Control of Substances Hazardous to Health Regulations"
    end

    test "handles nil input" do
      assert Utility.normalize_legislation_title(nil) == nil
    end

    test "handles empty string" do
      assert Utility.normalize_legislation_title("") == ""
    end

    test "expands common HSE abbreviations" do
      # Year is stripped from normalized title (stored separately in legislation_year)
      assert Utility.normalize_legislation_title("PUWER 1998") ==
               "Provision and Use of Work Equipment Regulations"

      assert Utility.normalize_legislation_title("COSHH REGULATIONS") ==
               "Control of Substances Hazardous to Health Regulations"
    end

    test "strips leading 'The' to match Baserow format" do
      assert Utility.normalize_legislation_title("The Health and Safety at Work Act") ==
               "Health and Safety at Work Act"

      assert Utility.normalize_legislation_title("THE ENVIRONMENTAL PROTECTION ACT") ==
               "Environmental Protection Act"
    end

    test "strips trailing year to match Baserow format" do
      assert Utility.normalize_legislation_title("Health and Safety at Work Act 1974") ==
               "Health and Safety at Work Act"

      assert Utility.normalize_legislation_title(
               "Control of Substances Hazardous to Health Regulations 2002"
             ) ==
               "Control of Substances Hazardous to Health Regulations"

      # Also handles parenthesized years
      assert Utility.normalize_legislation_title("Some Regulation (2015)") ==
               "Some Regulation"
    end

    test "strips both leading 'The' and trailing year" do
      assert Utility.normalize_legislation_title("The Health and Safety at Work etc. Act 1974") ==
               "Health and Safety at Work etc. Act"
    end

    test "standardizes etc. placement" do
      assert Utility.normalize_legislation_title("Health and Safety at Work etc Act") ==
               "Health and Safety at Work etc. Act"
    end

    test "removes extra spaces" do
      assert Utility.normalize_legislation_title("Health   and    Safety  at   Work") ==
               "Health and Safety at Work"
    end
  end

  describe "determine_legislation_type/1" do
    test "identifies acts" do
      assert Utility.determine_legislation_type("Health and Safety at Work Act") == :act
      assert Utility.determine_legislation_type("Environmental Protection Act 1990") == :act
    end

    test "identifies regulations" do
      assert Utility.determine_legislation_type(
               "Control of Substances Hazardous to Health Regulations"
             ) == :regulation

      assert Utility.determine_legislation_type("Construction Regulations 2015") == :regulation
    end

    test "identifies orders" do
      assert Utility.determine_legislation_type("Pollution Prevention Order 2010") == :order
    end

    test "identifies approved codes of practice" do
      assert Utility.determine_legislation_type("Workplace Safety ACOP") == :acop
      assert Utility.determine_legislation_type("Approved Code of Practice L24") == :acop
    end

    test "defaults to act for ambiguous titles" do
      assert Utility.determine_legislation_type("Some Legal Framework") == :act
    end

    test "handles regulations containing 'act' word" do
      assert Utility.determine_legislation_type(
               "Management of Health and Safety at Work Regulations"
             ) == :regulation
    end
  end

  describe "extract_year_from_title/1" do
    test "extracts 4-digit years" do
      assert Utility.extract_year_from_title("Health and Safety at Work Act 1974") == 1974
      assert Utility.extract_year_from_title("COSHH Regulations 2002") == 2002
    end

    test "returns nil for titles without year" do
      assert Utility.extract_year_from_title("Health and Safety at Work Act") == nil
      assert Utility.extract_year_from_title("Some Regulation") == nil
    end

    test "handles multiple years (returns first)" do
      assert Utility.extract_year_from_title("Act 1974 replaced by Act 2005") == 1974
    end
  end

  describe "extract_number_from_context/2" do
    test "extracts integer number from context" do
      context = %{number: 37}
      assert Utility.extract_number_from_context("Some Act", context) == 37
    end

    test "extracts string number from context" do
      context = %{"number" => "123"}
      assert Utility.extract_number_from_context("Some Act", context) == 123
    end

    test "returns nil for invalid number string" do
      context = %{"number" => "not_a_number"}
      assert Utility.extract_number_from_context("Some Act", context) == nil
    end

    test "returns nil for empty context" do
      assert Utility.extract_number_from_context("Some Act", %{}) == nil
    end
  end

  describe "validate_legislation_data/1" do
    test "validates complete data successfully" do
      data = %{
        title: "Health and Safety at Work Act 1974",
        year: 1974,
        number: 37,
        type: :act
      }

      {:ok, validated} = Utility.validate_legislation_data(data)

      # Title is normalized (year stripped, stored in separate field)
      assert validated.legislation_title == "Health and Safety at Work Act"
      assert validated.legislation_year == 1974
      assert validated.legislation_number == 37
      assert validated.legislation_type == :act
    end

    test "auto-extracts year from title" do
      data = %{title: "Health and Safety at Work Act 1974"}

      {:ok, validated} = Utility.validate_legislation_data(data)

      assert validated.legislation_year == 1974
    end

    test "auto-determines type from title" do
      data = %{title: "Control of Substances Hazardous to Health Regulations"}

      {:ok, validated} = Utility.validate_legislation_data(data)

      assert validated.legislation_type == :regulation
    end

    test "normalizes title" do
      data = %{title: "HEALTH AND SAFETY AT WORK ACT"}

      {:ok, validated} = Utility.validate_legislation_data(data)

      assert validated.legislation_title == "Health and Safety at Work Act"
    end

    test "rejects empty title" do
      data = %{title: ""}

      {:error, reason} = Utility.validate_legislation_data(data)

      assert reason == "Legislation title cannot be empty"
    end

    test "rejects nil title" do
      data = %{title: nil}

      {:error, reason} = Utility.validate_legislation_data(data)

      assert reason == "Legislation title cannot be empty"
    end

    test "rejects data without title" do
      data = %{year: 1974}

      {:error, reason} = Utility.validate_legislation_data(data)

      assert reason == "Legislation data must include title"
    end
  end

  describe "calculate_title_similarity/2" do
    test "returns 1.0 for identical titles" do
      title1 = "Health and Safety at Work Act"
      title2 = "Health and Safety at Work Act"

      similarity = Utility.calculate_title_similarity(title1, title2)

      assert similarity == 1.0
    end

    test "returns high similarity for similar titles" do
      title1 = "Health and Safety at Work Act"
      title2 = "HEALTH AND SAFETY AT WORK ACT"

      similarity = Utility.calculate_title_similarity(title1, title2)

      assert similarity > 0.9
    end

    test "returns lower similarity for different titles" do
      title1 = "Health and Safety at Work Act"
      # More different title
      title2 = "Computer Security Regulations"

      similarity = Utility.calculate_title_similarity(title1, title2)

      # Adjusted threshold based on actual Jaro-Winkler distance
      assert similarity < 0.5
    end

    test "handles nil inputs" do
      assert Utility.calculate_title_similarity(nil, "Some Act") == 0.0
      assert Utility.calculate_title_similarity("Some Act", nil) == 0.0
      assert Utility.calculate_title_similarity(nil, nil) == 0.0
    end

    test "normalizes titles before comparison" do
      title1 = "health and safety at work act"
      title2 = "HEALTH AND SAFETY AT WORK ACT"

      similarity = Utility.calculate_title_similarity(title1, title2)

      assert similarity == 1.0
    end
  end

  describe "parse_legislation_url/1" do
    test "parses UK Public General Act URL" do
      url = "https://www.legislation.gov.uk/ukpga/1974/37"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "ukpga"
      assert result.year == 1974
      assert result.number == "37"
    end

    test "parses UK Statutory Instrument URL" do
      url = "https://www.legislation.gov.uk/uksi/2015/51"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "uksi"
      assert result.year == 2015
      assert result.number == "51"
    end

    test "parses URL without www prefix" do
      url = "https://legislation.gov.uk/ukpga/1990/43"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "ukpga"
      assert result.year == 1990
      assert result.number == "43"
    end

    test "parses Scottish Statutory Instrument URL" do
      url = "https://www.legislation.gov.uk/ssi/2014/312"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "ssi"
      assert result.year == 2014
      assert result.number == "312"
    end

    test "parses Welsh Statutory Instrument URL" do
      url = "https://www.legislation.gov.uk/wsi/2016/1154"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "wsi"
      assert result.year == 2016
      assert result.number == "1154"
    end

    test "parses Northern Ireland Statutory Rules URL" do
      url = "https://www.legislation.gov.uk/nisr/2006/510"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "nisr"
      assert result.year == 2006
      assert result.number == "510"
    end

    test "parses Act of Scottish Parliament URL" do
      url = "https://www.legislation.gov.uk/asp/2003/13"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "asp"
      assert result.year == 2003
      assert result.number == "13"
    end

    test "handles URL with trailing path segments" do
      # Sometimes URLs have additional path like /contents or /section/1
      url = "https://www.legislation.gov.uk/ukpga/1974/37/contents"

      assert {:ok, result} = Utility.parse_legislation_url(url)
      assert result.type_code == "ukpga"
      assert result.year == 1974
      assert result.number == "37"
    end

    test "returns error for nil URL" do
      assert {:error, :invalid_url} = Utility.parse_legislation_url(nil)
    end

    test "returns error for empty string URL" do
      assert {:error, :invalid_url} = Utility.parse_legislation_url("")
    end

    test "returns error for invalid URL format" do
      assert {:error, :invalid_url} = Utility.parse_legislation_url("not-a-url")
    end

    test "returns error for non-legislation.gov.uk URL" do
      assert {:error, :invalid_url} =
               Utility.parse_legislation_url("https://example.com/ukpga/1974/37")
    end

    test "returns error for URL missing required components" do
      # Missing number
      assert {:error, :invalid_url} =
               Utility.parse_legislation_url("https://www.legislation.gov.uk/ukpga/1974")
    end
  end

  describe "build_legislation_url/3" do
    test "builds URL from string components" do
      url = Utility.build_legislation_url("ukpga", 1974, "37")

      assert url == "https://www.legislation.gov.uk/ukpga/1974/37"
    end

    test "builds URL from integer number" do
      url = Utility.build_legislation_url("uksi", 2015, 51)

      assert url == "https://www.legislation.gov.uk/uksi/2015/51"
    end

    test "roundtrips with parse_legislation_url" do
      original_url = "https://www.legislation.gov.uk/ukpga/1974/37"

      {:ok, parsed} = Utility.parse_legislation_url(original_url)
      rebuilt_url = Utility.build_legislation_url(parsed.type_code, parsed.year, parsed.number)

      assert rebuilt_url == original_url
    end
  end
end
