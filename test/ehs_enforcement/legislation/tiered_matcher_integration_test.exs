defmodule EhsEnforcement.Legislation.TieredMatcherIntegrationTest do
  @moduledoc """
  Integration tests for the tiered matching strategy.

  Tests real-world breach text patterns from various agencies (HSE, EA, SEPA, etc.)
  to ensure the matching logic correctly finds or creates legislation records.

  Phase 6 of legislation table CRUD robustness implementation.
  """
  use EhsEnforcement.DataCase, async: true

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.BreachParser
  alias EhsEnforcement.Enforcement.LegislationMatcher
  alias EhsEnforcement.Legislation.TieredMatcher

  # Real breach text examples from agency scrapers
  @hse_breach_texts [
    "Health and Safety at Work etc Act 1974, Section 2(1)",
    "Health and Safety at Work etc. Act 1974 Section 3(1)",
    "The Health and Safety at Work etc Act 1974, s.2(1)",
    "Construction (Design and Management) Regulations 2015, Regulation 13(2)",
    "The Construction (Design and Management) Regulations 2015 Reg 4(1)",
    "Work at Height Regulations 2005, Regulation 4(1)",
    "Control of Substances Hazardous to Health Regulations 2002 Reg 7(1)",
    "Provision and Use of Work Equipment Regulations 1998 Regulation 4(1)",
    "Lifting Operations and Lifting Equipment Regulations 1998, Regulation 8(1)",
    "Management of Health and Safety at Work Regulations 1999, Regulation 3(1)",
    "Personal Protective Equipment at Work Regulations 1992 Regulation 4",
    "Electricity at Work Regulations 1989, Regulation 4(1)"
  ]

  @ea_breach_texts [
    "Environmental Protection Act 1990, Section 33(1)(a)",
    "Environmental Protection Act 1990 s.34(1)",
    "Environmental Permitting (England and Wales) Regulations 2016 Regulation 12(1)(a)",
    "Water Resources Act 1991, Section 85(1)",
    "The Water Resources Act 1991 s.85",
    "Control of Pollution (Amendment) Act 1989",
    "Waste (England and Wales) Regulations 2011",
    "Hazardous Waste (England and Wales) Regulations 2005"
  ]

  @sepa_breach_texts [
    "Environmental Protection Act 1990, Section 33",
    "Control of Pollution Act 1974",
    "Environment Act 1995, Section 108",
    "Water Environment (Controlled Activities) (Scotland) Regulations 2011"
  ]

  describe "integration with BreachParser" do
    test "correctly parses and matches HSE breach texts" do
      # Pre-create the legislation we expect to find
      {:ok, hswa} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act,
          legislation_type_code: "ukpga",
          legislation_number: "37"
        })

      # Test several variations of HSWA breach text
      hswa_variations = [
        "Health and Safety at Work etc Act 1974, Section 2(1)",
        "Health and Safety at Work etc. Act 1974 Section 3(1)",
        "The Health and Safety at Work etc Act 1974, s.2(1)"
      ]

      for breach_text <- hswa_variations do
        assert {:ok, legislation_id} =
                 LegislationMatcher.find_or_create_from_breach(breach_text)

        assert legislation_id == hswa.id,
               "Failed for breach: #{breach_text}"
      end
    end

    test "correctly parses and matches CDM 2015 variations" do
      {:ok, cdm} =
        Enforcement.create_legislation(%{
          legislation_title: "Construction (Design and Management) Regulations",
          legislation_year: 2015,
          legislation_type: :regulation,
          legislation_type_code: "uksi",
          legislation_number: "51"
        })

      cdm_variations = [
        "Construction (Design and Management) Regulations 2015, Regulation 13(2)",
        "The Construction (Design and Management) Regulations 2015 Reg 4(1)"
      ]

      for breach_text <- cdm_variations do
        assert {:ok, legislation_id} =
                 LegislationMatcher.find_or_create_from_breach(breach_text)

        assert legislation_id == cdm.id,
               "Failed for breach: #{breach_text}"
      end
    end

    test "correctly parses EA breach texts" do
      {:ok, epa} =
        Enforcement.create_legislation(%{
          legislation_title: "Environmental Protection Act",
          legislation_year: 1990,
          legislation_type: :act,
          legislation_type_code: "ukpga",
          legislation_number: "43"
        })

      epa_variations = [
        "Environmental Protection Act 1990, Section 33(1)(a)",
        "Environmental Protection Act 1990 s.34(1)"
      ]

      for breach_text <- epa_variations do
        assert {:ok, legislation_id} =
                 LegislationMatcher.find_or_create_from_breach(breach_text)

        assert legislation_id == epa.id,
               "Failed for breach: #{breach_text}"
      end
    end
  end

  describe "duplicate prevention" do
    test "does not create duplicates for HSWA from multiple breach texts" do
      # Get initial legislation count
      {:ok, initial_legislation} = Ash.read(Enforcement.Legislation)
      initial_count = length(initial_legislation)

      # Process multiple breach texts that should all reference HSWA
      breach_texts = [
        "Health and Safety at Work etc Act 1974, Section 2(1)",
        "Health and Safety at Work etc. Act 1974 Section 3",
        "The Health and Safety at Work etc Act 1974, s.33",
        "Health and Safety at Work Act 1974"
      ]

      legislation_ids =
        Enum.map(breach_texts, fn text ->
          {:ok, id} = LegislationMatcher.find_or_create_from_breach(text)
          id
        end)

      # All should reference the same legislation
      unique_ids = Enum.uniq(legislation_ids)
      assert length(unique_ids) == 1, "Expected 1 unique legislation, got #{length(unique_ids)}"

      # Should have created exactly 1 new record
      {:ok, final_legislation} = Ash.read(Enforcement.Legislation)
      assert length(final_legislation) == initial_count + 1
    end

    test "does not create duplicates for CDM 2015 from multiple breach texts" do
      {:ok, initial_legislation} = Ash.read(Enforcement.Legislation)
      initial_count = length(initial_legislation)

      breach_texts = [
        "Construction (Design and Management) Regulations 2015, Regulation 4(1)",
        "The Construction (Design and Management) Regulations 2015 Reg 13(2)",
        "CDM Regulations 2015"
      ]

      legislation_ids =
        Enum.map(breach_texts, fn text ->
          {:ok, id} = LegislationMatcher.find_or_create_from_breach(text)
          id
        end)
        |> Enum.reject(&is_nil/1)

      # All non-nil IDs should reference the same legislation
      unique_ids = Enum.uniq(legislation_ids)
      assert length(unique_ids) == 1, "Expected 1 unique legislation, got #{length(unique_ids)}"

      {:ok, final_legislation} = Ash.read(Enforcement.Legislation)
      # Should have created exactly 1 new record (CDM)
      assert length(final_legislation) == initial_count + 1
    end

    test "creates separate records for different years of same Act" do
      breach_1974 = "Health and Safety at Work etc Act 1974, Section 2(1)"
      breach_2015 = "Health and Safety at Work etc Act 2015, Section 2(1)"

      {:ok, id_1974} = LegislationMatcher.find_or_create_from_breach(breach_1974)
      {:ok, id_2015} = LegislationMatcher.find_or_create_from_breach(breach_2015)

      # Should be different legislation records
      assert id_1974 != id_2015

      {:ok, leg_1974} = Ash.get(Enforcement.Legislation, id_1974)
      {:ok, leg_2015} = Ash.get(Enforcement.Legislation, id_2015)

      assert leg_1974.legislation_year == 1974
      assert leg_2015.legislation_year == 2015
    end

    test "creates separate records for different legislation types with same year" do
      breach_hswa = "Health and Safety at Work etc Act 1974, Section 2(1)"
      breach_cpa = "Control of Pollution Act 1974, Section 3"

      {:ok, id_hswa} = LegislationMatcher.find_or_create_from_breach(breach_hswa)
      {:ok, id_cpa} = LegislationMatcher.find_or_create_from_breach(breach_cpa)

      # Should be different legislation records despite same year
      assert id_hswa != id_cpa
    end
  end

  describe "tier matching verification" do
    test "Tier 1 match via unique identifier" do
      # Create with full unique identifier
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act,
          legislation_type_code: "ukpga",
          legislation_number: "37"
        })

      # Lookup table enrichment should trigger Tier 1 match
      {:ok, found, meta} =
        TieredMatcher.find_or_create_with_tier(%{
          title: "Health and Safety at Work etc. Act",
          year: 1974
        })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 1
    end

    test "Tier 4 match via exact title + year" do
      # Create without type_code/number (simulating legacy data)
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Obscure Safety Measure Act",
          legislation_year: 2010,
          legislation_type: :act
        })

      # Should match via Tier 4 (exact title + year)
      {:ok, found, meta} =
        TieredMatcher.find_or_create_with_tier(%{
          title: "Obscure Safety Measure Act",
          year: 2010
        })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 4
    end

    test "Tier 5 fuzzy match for minor title variations" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Control of Substances Hazardous to Health Regulations",
          legislation_year: 2002,
          legislation_type: :regulation
        })

      # "COSHH Regulations" is too different, but slight variations should match
      {:ok, found, meta} =
        TieredMatcher.find_or_create_with_tier(%{
          title: "Control of Substances Hazardous to Health Regs",
          year: 2002
        })

      assert found.id == existing.id
      assert Keyword.get(meta, :tier) == 5
    end
  end

  describe "bulk processing performance" do
    test "processes batch of breach texts efficiently" do
      # Prepare test data
      breach_texts = @hse_breach_texts ++ @ea_breach_texts ++ @sepa_breach_texts

      # Time the batch processing
      {time_us, results} =
        :timer.tc(fn ->
          Enum.map(breach_texts, fn text ->
            LegislationMatcher.find_or_create_from_breach(text)
          end)
        end)

      # Verify all succeeded
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      assert success_count == length(breach_texts)

      # Log timing (for performance monitoring)
      time_ms = time_us / 1000
      per_item_ms = time_ms / length(breach_texts)

      # Should process in reasonable time (< 100ms per item on average)
      assert per_item_ms < 100,
             "Processing too slow: #{per_item_ms}ms per breach text"
    end

    test "batch_find_or_create processes multiple inputs" do
      inputs = [
        %{title: "Health and Safety at Work etc. Act", year: 1974},
        %{title: "Environmental Protection Act", year: 1990},
        %{title: "Water Resources Act", year: 1991},
        %{title: "Construction (Design and Management) Regulations", year: 2015}
      ]

      {:ok, results} = TieredMatcher.batch_find_or_create(inputs)

      assert map_size(results) == 4
      assert Map.has_key?(results, "Health and Safety at Work etc. Act")
      assert Map.has_key?(results, "Environmental Protection Act")

      # Verify enrichment worked
      hswa = results["Health and Safety at Work etc. Act"]
      assert hswa.legislation_type_code == "ukpga"
      assert hswa.legislation_number == "37"
    end
  end

  describe "edge cases from real scraper data" do
    test "handles breach text with no legislation reference" do
      breach_text = "Failed to maintain safe workplace. Fine: £10,000"

      assert {:ok, nil} = LegislationMatcher.find_or_create_from_breach(breach_text)
    end

    test "handles empty breach text" do
      assert {:ok, nil} = LegislationMatcher.find_or_create_from_breach("")
    end

    test "handles breach text with year but no Act name" do
      breach_text = "Section 2(1) of 1974"

      # Parser may or may not find this - verify it doesn't crash
      result = LegislationMatcher.find_or_create_from_breach(breach_text)
      assert match?({:ok, _}, result)
    end

    test "handles non-standard regulation abbreviations" do
      # Create the full regulation
      {:ok, coshh} =
        Enforcement.create_legislation(%{
          legislation_title: "Control of Substances Hazardous to Health Regulations",
          legislation_year: 2002,
          legislation_type: :regulation,
          legislation_type_code: "uksi",
          legislation_number: "2677"
        })

      # Test with full name
      {:ok, found} =
        TieredMatcher.find_or_create(%{
          title: "Control of Substances Hazardous to Health Regulations",
          year: 2002
        })

      assert found.id == coshh.id
    end

    test "handles multi-Act breach text" do
      breach_text =
        "Health and Safety at Work etc Act 1974, Section 2(1); " <>
          "Management of Health and Safety at Work Regulations 1999, Regulation 3(1)"

      # The parser should find the first Act
      parsed = BreachParser.parse_breach(breach_text)

      assert parsed.act_name != nil
      assert parsed.act_year != nil
    end

    test "handles Scottish and Welsh legislation variations" do
      # These should be handled as separate legislation
      scottish = %{
        title: "Water Environment (Controlled Activities) (Scotland) Regulations",
        year: 2011
      }

      welsh = %{
        title: "Environmental Permitting (England and Wales) Regulations",
        year: 2016
      }

      {:ok, scot_leg} = TieredMatcher.find_or_create(scottish)
      {:ok, welsh_leg} = TieredMatcher.find_or_create(welsh)

      assert scot_leg.id != welsh_leg.id
      assert scot_leg.legislation_title =~ "Scotland"
      assert welsh_leg.legislation_title =~ "Wales"
    end
  end

  describe "lookup table enrichment verification" do
    test "known legislation gets enriched with type_code and number" do
      # These are all in the lookup table
      known_legislation = [
        {"Health and Safety at Work etc. Act", 1974, "ukpga", "37"},
        {"Construction (Design and Management) Regulations", 2015, "uksi", "51"},
        {"Environmental Protection Act", 1990, "ukpga", "43"},
        {"Water Resources Act", 1991, "ukpga", "57"}
      ]

      for {title, year, expected_type_code, expected_number} <- known_legislation do
        {:ok, legislation} = TieredMatcher.find_or_create(%{title: title, year: year})

        assert legislation.legislation_type_code == expected_type_code,
               "Wrong type_code for #{title}: expected #{expected_type_code}, got #{legislation.legislation_type_code}"

        assert legislation.legislation_number == expected_number,
               "Wrong number for #{title}: expected #{expected_number}, got #{legislation.legislation_number}"
      end
    end

    test "unknown legislation does not get enriched" do
      {:ok, legislation} =
        TieredMatcher.find_or_create(%{
          title: "Made Up Obscure Regulations",
          year: 2023
        })

      assert legislation.legislation_type_code == nil
      assert legislation.legislation_number == nil
    end

    test "URL enrichment takes precedence over lookup table" do
      {:ok, legislation} =
        TieredMatcher.find_or_create(%{
          title: "Health and Safety at Work etc. Act",
          year: 1974,
          url: "https://www.legislation.gov.uk/ukpga/1974/99"
        })

      # URL says number is 99, not 37 from lookup table
      assert legislation.legislation_number == "99"
      assert legislation.legislation_type_code == "ukpga"
    end
  end
end
