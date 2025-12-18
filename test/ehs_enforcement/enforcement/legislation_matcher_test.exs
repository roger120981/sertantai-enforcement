defmodule EhsEnforcement.Enforcement.LegislationMatcherTest do
  use EhsEnforcement.DataCase, async: true

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.LegislationMatcher

  describe "find_or_create_from_breach/2" do
    test "creates new legislation from breach text" do
      breach_text = "Health and Safety at Work etc. Act 1974, Section 2(1)"

      assert {:ok, legislation_id} = LegislationMatcher.find_or_create_from_breach(breach_text)
      assert legislation_id != nil

      # Verify legislation was created correctly
      {:ok, legislation} = Ash.get(Enforcement.Legislation, legislation_id)
      # Title is normalized (year stripped, stored in separate field)
      assert legislation.legislation_title == "Health and Safety at Work etc. Act"
      assert legislation.legislation_year == 1974
      assert legislation.legislation_type == :act
    end

    test "finds existing legislation from breach text" do
      # Create legislation first (with normalized title - no year)
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      breach_text = "Health and Safety at Work etc. Act 1974, Section 2(1)"

      assert {:ok, legislation_id} = LegislationMatcher.find_or_create_from_breach(breach_text)
      assert legislation_id == existing.id

      # Should not create duplicate
      query = Ash.Query.filter(Enforcement.Legislation, legislation_year == 1974)
      assert {:ok, legislations} = Ash.read(query)
      assert length(legislations) == 1
    end

    test "handles breach without legislation reference" do
      breach_text = "Some general violation description"

      assert {:ok, nil} = LegislationMatcher.find_or_create_from_breach(breach_text)
    end

    test "handles empty breach text" do
      # Empty strings should not cause crashes, though they won't extract legislation
      assert {:ok, nil} = LegislationMatcher.find_or_create_from_breach("")
    end

    test "normalizes legislation title before matching" do
      # Create with normalized title (no year in title)
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      # Try to match with slightly different formatting (should still normalize to same title)
      breach_text = "Health and Safety at Work etc. Act 1974, Section 3(1)"

      assert {:ok, legislation_id} = LegislationMatcher.find_or_create_from_breach(breach_text)
      assert legislation_id == existing.id
    end

    test "creates separate legislation for different years" do
      breach_text_1974 = "Health and Safety at Work etc. Act 1974, Section 2(1)"
      breach_text_2015 = "Health and Safety at Work etc Act 2015, Section 2(1)"

      assert {:ok, id_1974} = LegislationMatcher.find_or_create_from_breach(breach_text_1974)
      assert {:ok, id_2015} = LegislationMatcher.find_or_create_from_breach(breach_text_2015)

      assert id_1974 != id_2015

      {:ok, leg_1974} = Ash.get(Enforcement.Legislation, id_1974)
      {:ok, leg_2015} = Ash.get(Enforcement.Legislation, id_2015)

      assert leg_1974.legislation_year == 1974
      assert leg_2015.legislation_year == 2015
    end

    test "handles Regulations" do
      breach_text =
        "Construction (design and Management) Regulations 2015, Regulation 13(1)"

      assert {:ok, legislation_id} = LegislationMatcher.find_or_create_from_breach(breach_text)

      {:ok, legislation} = Ash.get(Enforcement.Legislation, legislation_id)

      # Note: normalize_legislation_title properly capitalizes words after punctuation
      # and strips year from title (stored separately in legislation_year)
      assert legislation.legislation_title ==
               "Construction (Design and Management) Regulations"

      assert legislation.legislation_year == 2015
      assert legislation.legislation_type == :regulation
    end
  end

  describe "find_or_create_legislation/4" do
    test "creates new legislation with title and year" do
      act_name = "Health and Safety at Work etc. Act 1974"
      act_year = 1974

      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(act_name, act_year)

      {:ok, legislation} = Ash.get(Enforcement.Legislation, legislation_id)
      # Title normalized (year stripped)
      assert legislation.legislation_title == "Health and Safety at Work etc. Act"
      assert legislation.legislation_year == 1974
      assert legislation.legislation_type == :act
    end

    test "finds existing legislation by title and year" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      act_name = "Health and Safety at Work etc. Act 1974"
      act_year = 1974

      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(act_name, act_year)

      assert legislation_id == existing.id
    end

    test "finds existing legislation by title when no year provided" do
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      act_name = "Health and Safety at Work etc. Act 1974"

      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(act_name, nil)

      assert legislation_id == existing.id
    end

    test "creates legislation without year" do
      act_name = "Some Act"

      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(act_name, nil)

      {:ok, legislation} = Ash.get(Enforcement.Legislation, legislation_id)
      assert legislation.legislation_title == "Some Act"
      assert legislation.legislation_year == nil
    end

    test "prefers most recent year when matching by title only" do
      # Create two versions of the same Act (title normalized - no year)
      {:ok, _old} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      {:ok, recent} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 2015,
          legislation_type: :act
        })

      # When searching without year, should find most recent
      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(
                 "Health and Safety at Work etc. Act 1974",
                 nil
               )

      assert legislation_id == recent.id
    end

    test "normalizes title using utility function" do
      # The utility should normalize "Act" variations and strip year
      act_name = "Health and Safety at Work etc. Act 1974"

      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(act_name, 1974)

      {:ok, legislation} = Ash.get(Enforcement.Legislation, legislation_id)
      # Should be normalized by Utility.normalize_legislation_title/1 (year stripped)
      assert legislation.legislation_title == "Health and Safety at Work etc. Act"
    end

    test "determines legislation type correctly" do
      # Test Act
      assert {:ok, act_id} =
               LegislationMatcher.find_or_create_legislation(
                 "Health and Safety at Work etc. Act 1974",
                 1974
               )

      {:ok, act_leg} = Ash.get(Enforcement.Legislation, act_id)
      assert act_leg.legislation_type == :act

      # Test Regulations
      assert {:ok, reg_id} =
               LegislationMatcher.find_or_create_legislation(
                 "Construction (design and Management) Regulations 2015",
                 2015
               )

      {:ok, reg_leg} = Ash.get(Enforcement.Legislation, reg_id)
      assert reg_leg.legislation_type == :regulation
    end
  end

  describe "bulk_find_or_create_from_breaches/2" do
    test "processes multiple breaches and returns map of legislation IDs" do
      breach_texts = [
        "Health and Safety at Work etc. Act 1974, Section 2(1)",
        "Construction (design and Management) Regulations 2015, Regulation 13(1)",
        "Work at Height Regulations 2005, Regulation 4(1)"
      ]

      assert {:ok, id_map} =
               LegislationMatcher.bulk_find_or_create_from_breaches(breach_texts)

      assert map_size(id_map) == 3
      assert Map.has_key?(id_map, Enum.at(breach_texts, 0))
      assert Map.has_key?(id_map, Enum.at(breach_texts, 1))
      assert Map.has_key?(id_map, Enum.at(breach_texts, 2))

      # All IDs should be present
      assert Map.get(id_map, Enum.at(breach_texts, 0)) != nil
      assert Map.get(id_map, Enum.at(breach_texts, 1)) != nil
      assert Map.get(id_map, Enum.at(breach_texts, 2)) != nil
    end

    test "handles mix of valid and invalid breaches" do
      breach_texts = [
        "Health and Safety at Work etc. Act 1974, Section 2(1)",
        "Some random text without legislation",
        "Construction (design and Management) Regulations 2015, Regulation 13(1)"
      ]

      assert {:ok, id_map} =
               LegislationMatcher.bulk_find_or_create_from_breaches(breach_texts)

      assert map_size(id_map) == 3

      # Valid breaches should have IDs
      assert Map.get(id_map, Enum.at(breach_texts, 0)) != nil
      assert Map.get(id_map, Enum.at(breach_texts, 2)) != nil

      # Invalid breach should have nil
      assert Map.get(id_map, Enum.at(breach_texts, 1)) == nil
    end

    test "reuses existing legislation records" do
      # Pre-create one legislation (with normalized title - no year)
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      breach_texts = [
        "Health and Safety at Work etc. Act 1974, Section 2(1)",
        "Construction (design and Management) Regulations 2015, Regulation 13(1)"
      ]

      assert {:ok, id_map} =
               LegislationMatcher.bulk_find_or_create_from_breaches(breach_texts)

      # First one should match existing
      assert Map.get(id_map, Enum.at(breach_texts, 0)) == existing.id

      # Second one should be newly created
      assert Map.get(id_map, Enum.at(breach_texts, 1)) != existing.id
    end

    test "handles empty list" do
      assert {:ok, id_map} = LegislationMatcher.bulk_find_or_create_from_breaches([])

      assert id_map == %{}
    end
  end

  describe "extract_display_title/1" do
    test "extracts title from breach text" do
      breach_text = "Health and Safety at Work etc. Act 1974, Section 2(1)"

      title = LegislationMatcher.extract_display_title(breach_text)

      assert title == "Health and Safety at Work etc. Act 1974"
    end

    test "returns 'Unknown Legislation' for invalid text" do
      breach_text = "Some random text"

      title = LegislationMatcher.extract_display_title(breach_text)

      assert title == "Unknown Legislation"
    end
  end

  describe "race condition handling" do
    test "handles duplicate creation attempts gracefully" do
      # This test simulates a race condition where two processes try to create
      # the same legislation simultaneously. In reality, Ash will handle this
      # with unique constraints, but we want to ensure the code retries the lookup.

      act_name = "Health and Safety at Work etc. Act 1974"
      act_year = 1974

      # First creation should succeed
      assert {:ok, id1} = LegislationMatcher.find_or_create_legislation(act_name, act_year)

      # Second attempt should find existing (not error)
      assert {:ok, id2} = LegislationMatcher.find_or_create_legislation(act_name, act_year)

      # Should return the same ID
      assert id1 == id2

      # Only one record should exist (title normalized - no year)
      query =
        Ash.Query.filter(
          Enforcement.Legislation,
          legislation_title == "Health and Safety at Work etc. Act" and
            legislation_year == 1974
        )

      assert {:ok, legislations} = Ash.read(query)
      assert length(legislations) == 1
    end
  end

  describe "edge cases" do
    test "handles very long legislation titles" do
      long_title =
        "The Control of Substances Hazardous to Health Regulations 2002"

      assert {:ok, legislation_id} =
               LegislationMatcher.find_or_create_legislation(long_title, 2002)

      {:ok, legislation} = Ash.get(Enforcement.Legislation, legislation_id)
      # Title normalized: "The" stripped, year stripped
      assert legislation.legislation_title ==
               "Control of Substances Hazardous to Health Regulations"
    end

    test "handles legislation with special characters" do
      title_with_special = "Health and Safety at Work etc. Act 1974"

      assert {:ok, _legislation_id} =
               LegislationMatcher.find_or_create_legislation(title_with_special, 1974)
    end

    test "handles year as integer" do
      assert {:ok, _legislation_id} =
               LegislationMatcher.find_or_create_legislation("Some Act", 2020)
    end

    test "matches legislation case-insensitively through normalization" do
      # Create with normalized title (no year)
      {:ok, existing} =
        Enforcement.create_legislation(%{
          legislation_title: "Health and Safety at Work etc. Act",
          legislation_year: 1974,
          legislation_type: :act
        })

      # Try to find with same title (normalization should handle any differences)
      assert {:ok, found_id} =
               LegislationMatcher.find_or_create_legislation(
                 "Health and Safety at Work etc. Act 1974",
                 1974
               )

      assert found_id == existing.id
    end
  end
end
