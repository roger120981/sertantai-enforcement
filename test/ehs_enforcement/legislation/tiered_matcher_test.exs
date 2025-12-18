defmodule EhsEnforcement.Legislation.TieredMatcherTest do
  use EhsEnforcement.DataCase, async: true

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Legislation.TieredMatcher

  describe "find_or_create/2" do
    test "returns legislation when found" do
      # Create legislation first
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act,
          legislation_type_code: "ukpga",
          legislation_number: "37"
        })

      # Should find it via Tier 1 (unique identifier)
      assert {:ok, found} =
               TieredMatcher.find_or_create(%{
                 title: "Health and Safety at Work etc. Act",
                 year: 1974
               })

      assert found.id == existing.id
    end

    test "creates new legislation when not found" do
      assert {:ok, legislation} =
               TieredMatcher.find_or_create(%{
                 title: "Some Obscure Act",
                 year: 2020
               })

      assert legislation.legislation_title == "Some Obscure Act"
      assert legislation.legislation_year == 2020
    end

    test "normalizes title before matching" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      # Search with year in title - should normalize and find
      assert {:ok, found} =
               TieredMatcher.find_or_create(%{
                 title: "The Health and Safety at Work etc. Act 1974",
                 year: 1974
               })

      assert found.id == existing.id
    end
  end

  describe "find_or_create_with_tier/2" do
    test "Tier 1: matches on year + type_code + number" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act,
          legislation_type_code: "ukpga",
          legislation_number: "37"
        })

      # Lookup table will enrich with type_code and number for HSWA
      assert {:ok, found, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Health and Safety at Work etc. Act",
                 year: 1974
               })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 1
      assert Keyword.get(meta, :match_type) == :unique_identifier
    end

    test "Tier 2: matches on title + year + number when type_code differs" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Custom Legislation",
          legislation_year: 2020,
          legislation_type: :act,
          legislation_type_code: nil,
          legislation_number: "123"
        })

      assert {:ok, found, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Custom Legislation",
                 year: 2020,
                 number: "123"
               })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 2
      assert Keyword.get(meta, :match_type) == :title_year_number
    end

    test "Tier 3: matches on title + year + type_code when number differs" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Custom Regulations",
          legislation_year: 2020,
          legislation_type: :regulation,
          legislation_type_code: "uksi",
          legislation_number: nil
        })

      assert {:ok, found, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Custom Regulations",
                 year: 2020,
                 type_code: "uksi"
               })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 3
      assert Keyword.get(meta, :match_type) == :title_year_type_code
    end

    test "Tier 4: matches on exact normalized title + year" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Some Unique Act",
          legislation_year: 2015,
          legislation_type: :act
        })

      assert {:ok, found, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "The Some Unique Act 2015",
                 year: 2015
               })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 4
      assert Keyword.get(meta, :match_type) == :title_year_exact
    end

    test "Tier 5: fuzzy matches on similar title + year" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Provision and Use of Work Equipment Regulations",
          legislation_year: 1998,
          legislation_type: :regulation
        })

      # Slight variation in title - should fuzzy match (similarity ~0.93)
      assert {:ok, found, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Provision and Use of Work Equipment Regs",
                 year: 1998
               })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 5
      assert Keyword.get(meta, :match_type) == :fuzzy_match
    end

    test "Tier 6: creates new record when no match found" do
      assert {:ok, created, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Brand New Obscure Act",
                 year: 2024
               })

      assert created.legislation_title == "Brand New Obscure Act"
      assert created.legislation_year == 2024
      assert Keyword.get(meta, :tier) == 6
      assert Keyword.get(meta, :match_type) == :created
    end
  end

  describe "enrichment from lookup table" do
    test "enriches known legislation with type_code, number, and URL" do
      # CDM 2015 is in the lookup table
      assert {:ok, legislation, meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Construction (Design and Management) Regulations",
                 year: 2015
               })

      assert legislation.legislation_type_code == "uksi"
      assert legislation.legislation_number == "51"
      assert legislation.legislation_url == "https://www.legislation.gov.uk/uksi/2015/51"
      assert Keyword.get(meta, :tier) == 6
    end

    test "enriches from URL when provided" do
      assert {:ok, legislation, _meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Some Act",
                 year: 2020,
                 url: "https://www.legislation.gov.uk/ukpga/2020/99"
               })

      assert legislation.legislation_type_code == "ukpga"
      assert legislation.legislation_number == "99"
      assert legislation.legislation_year == 2020
    end

    test "URL takes precedence over lookup table" do
      # HSWA lookup table says ukpga/1974/37
      # But if we provide a different URL, that should be used
      assert {:ok, legislation, _meta} =
               TieredMatcher.find_or_create_with_tier(%{
                 title: "Health and Safety at Work etc. Act",
                 year: 1974,
                 url: "https://www.legislation.gov.uk/ukpga/1974/99"
               })

      # URL values should override lookup table
      assert legislation.legislation_number == "99"
    end
  end

  describe "find/2" do
    test "returns legislation when found" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Test Act",
          legislation_year: 2020,
          legislation_type: :act
        })

      assert {:ok, found} = TieredMatcher.find(%{title: "Test Act", year: 2020})
      assert found.id == existing.id
    end

    test "returns nil when not found" do
      assert {:ok, nil} = TieredMatcher.find(%{title: "Non-existent Act", year: 1900})
    end
  end

  describe "find_with_tier/2" do
    test "returns tier information when found" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Test Regulations",
          legislation_year: 2021,
          legislation_type: :regulation
        })

      assert {:ok, found, meta} =
               TieredMatcher.find_with_tier(%{title: "Test Regulations", year: 2021})

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 4
    end

    test "returns nil tier when not found" do
      assert {:ok, nil, meta} =
               TieredMatcher.find_with_tier(%{title: "Non-existent", year: 1900})

      assert Keyword.get(meta, :tier) == nil
      assert Keyword.get(meta, :match_type) == nil
    end
  end

  describe "batch_find_or_create/2" do
    test "processes multiple inputs" do
      inputs = [
        %{title: "First Act", year: 2020},
        %{title: "Second Act", year: 2021},
        %{title: "Third Act", year: 2022}
      ]

      assert {:ok, results} = TieredMatcher.batch_find_or_create(inputs)

      assert map_size(results) == 3
      assert Map.has_key?(results, "First Act")
      assert Map.has_key?(results, "Second Act")
      assert Map.has_key?(results, "Third Act")
    end

    test "finds existing and creates new" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Existing Act",
          legislation_year: 2020,
          legislation_type: :act
        })

      inputs = [
        %{title: "Existing Act", year: 2020},
        %{title: "New Act", year: 2021}
      ]

      assert {:ok, results} = TieredMatcher.batch_find_or_create(inputs)

      assert results["Existing Act"].id == existing.id
      assert results["New Act"].legislation_title == "New Act"
    end
  end

  describe "edge cases" do
    test "handles nil year gracefully" do
      # When year is nil and title not in lookup, creates with nil year
      assert {:ok, legislation} =
               TieredMatcher.find_or_create(%{
                 title: "Unknown Act",
                 year: nil
               })

      assert legislation.legislation_title == "Unknown Act"
      assert legislation.legislation_year == nil
    end

    test "uses lookup table year when input year is nil" do
      # HSWA is in lookup table with year 1974
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act,
          legislation_type_code: "ukpga",
          legislation_number: "37"
        })

      assert {:ok, found} =
               TieredMatcher.find_or_create(%{
                 title: "Health and Safety at Work etc. Act",
                 year: nil
               })

      # Should have used lookup table to find the 1974 version
      assert found.id == existing.id
    end

    test "different years for same title are different legislation" do
      {:ok, v1974} =
        Enforcement.create_legislation(%{
          legislation_title: "Some Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      {:ok, v2015} =
        Enforcement.create_legislation(%{
          legislation_title: "Some Act",
          legislation_year: 2015,
          legislation_type: :act
        })

      assert {:ok, found_1974} = TieredMatcher.find_or_create(%{title: "Some Act", year: 1974})
      assert {:ok, found_2015} = TieredMatcher.find_or_create(%{title: "Some Act", year: 2015})

      assert found_1974.id == v1974.id
      assert found_2015.id == v2015.id
      assert found_1974.id != found_2015.id
    end
  end
end
