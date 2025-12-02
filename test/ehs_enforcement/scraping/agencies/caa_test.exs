defmodule EhsEnforcement.Scraping.Agencies.CaaTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Agencies.Caa
  alias EhsEnforcement.Scraping.AgencyBehavior
  alias EhsEnforcement.Scraping.Caa.CaaProsecutionScraper

  describe "AgencyBehavior implementation" do
    test "get_agency_module/1 returns Caa module" do
      assert AgencyBehavior.get_agency_module(:caa) == Caa
    end

    test "validate_params/1 accepts valid data_type :all" do
      assert {:ok, params} = Caa.validate_params(data_type: :all)
      assert params.data_type == :all
    end

    test "validate_params/1 accepts valid data_type :prosecutions" do
      assert {:ok, params} = Caa.validate_params(data_type: :prosecutions)
      assert params.data_type == :prosecutions
    end

    test "validate_params/1 accepts valid data_type :undertakings" do
      assert {:ok, params} = Caa.validate_params(data_type: :undertakings)
      assert params.data_type == :undertakings
    end

    test "validate_params/1 rejects invalid data_type" do
      assert {:error, message} = Caa.validate_params(data_type: :invalid)
      assert message =~ "Invalid data_type"
    end

    test "validate_params/1 accepts years filter" do
      assert {:ok, params} = Caa.validate_params(years: ["2024-2025", "2023-2024"])
      assert params.years == ["2024-2025", "2023-2024"]
    end

    test "validate_params/1 defaults to :all data_type" do
      assert {:ok, params} = Caa.validate_params([])
      assert params.data_type == :all
    end

    test "validate_params/1 defaults to :manual scrape_type" do
      assert {:ok, params} = Caa.validate_params([])
      assert params.scrape_type == :manual
    end

    test "validate_params/1 accepts scheduled scrape_type" do
      assert {:ok, params} = Caa.validate_params(scrape_type: :scheduled)
      assert params.scrape_type == :scheduled
    end
  end

  describe "AI parsing support" do
    test "validate_params/1 accepts use_ai_parsing option" do
      assert {:ok, params} = Caa.validate_params(use_ai_parsing: true)
      assert params.use_ai_parsing == true
    end

    test "validate_params/1 defaults use_ai_parsing to false" do
      assert {:ok, params} = Caa.validate_params([])
      assert params.use_ai_parsing == false
    end

    test "ai_parsing_available?/0 returns boolean" do
      result = Caa.ai_parsing_available?()
      assert is_boolean(result)
    end

    test "scraper reports modern format years" do
      modern_years = CaaProsecutionScraper.modern_format_years()
      assert is_list(modern_years)
      assert "2024-2025" in modern_years
      assert "2023-2024" in modern_years
    end

    test "scraper reports legacy format years" do
      legacy_years = CaaProsecutionScraper.legacy_format_years()
      assert is_list(legacy_years)
      assert "2021-2022" in legacy_years
      assert "2017-2018" in legacy_years
    end

    test "legacy_format_year?/1 correctly identifies legacy years" do
      assert CaaProsecutionScraper.legacy_format_year?("2021-2022") == true
      assert CaaProsecutionScraper.legacy_format_year?("2017-2018") == true
      assert CaaProsecutionScraper.legacy_format_year?("2024-2025") == false
      assert CaaProsecutionScraper.legacy_format_year?("2023-2024") == false
    end
  end

  describe "module documentation" do
    test "has moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Caa)
      assert moduledoc =~ "CAA-specific scraping"
      assert moduledoc =~ "Civil Aviation Authority"
    end
  end
end
