defmodule EhsEnforcement.Legislation.LookupTableTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Legislation.LookupTable

  describe "lookup/1" do
    test "finds Health and Safety at Work etc. Act" do
      assert {:ok, info} = LookupTable.lookup("Health and Safety at Work etc. Act")

      assert info.type_code == "ukpga"
      assert info.number == "37"
      assert info.year == 1974
      assert info.url == "https://www.legislation.gov.uk/ukpga/1974/37"
    end

    test "finds legislation with normalized input (all caps)" do
      assert {:ok, info} = LookupTable.lookup("HEALTH AND SAFETY AT WORK ETC. ACT")

      assert info.type_code == "ukpga"
      assert info.year == 1974
    end

    test "finds legislation with leading 'The' stripped" do
      assert {:ok, info} = LookupTable.lookup("The Health and Safety at Work etc. Act")

      assert info.type_code == "ukpga"
      assert info.year == 1974
    end

    test "finds legislation with trailing year stripped" do
      assert {:ok, info} = LookupTable.lookup("Health and Safety at Work etc. Act 1974")

      assert info.type_code == "ukpga"
      assert info.year == 1974
    end

    test "finds legislation with both 'The' and year" do
      assert {:ok, info} = LookupTable.lookup("The Health and Safety at Work etc. Act 1974")

      assert info.type_code == "ukpga"
      assert info.year == 1974
    end

    test "finds COSHH Regulations" do
      assert {:ok, info} =
               LookupTable.lookup("Control of Substances Hazardous to Health Regulations")

      assert info.type_code == "uksi"
      assert info.number == "2677"
      assert info.year == 2002
    end

    test "finds CDM Regulations" do
      assert {:ok, info} = LookupTable.lookup("Construction (Design and Management) Regulations")

      assert info.type_code == "uksi"
      assert info.number == "51"
      assert info.year == 2015
    end

    test "finds Work at Height Regulations" do
      assert {:ok, info} = LookupTable.lookup("Work at Height Regulations")

      assert info.type_code == "uksi"
      assert info.number == "735"
      assert info.year == 2005
    end

    test "finds Environmental Protection Act" do
      assert {:ok, info} = LookupTable.lookup("Environmental Protection Act")

      assert info.type_code == "ukpga"
      assert info.number == "43"
      assert info.year == 1990
    end

    test "finds Water Resources Act" do
      assert {:ok, info} = LookupTable.lookup("Water Resources Act")

      assert info.type_code == "ukpga"
      assert info.number == "57"
      assert info.year == 1991
    end

    test "finds Environmental Permitting Regulations" do
      assert {:ok, info} =
               LookupTable.lookup("Environmental Permitting (England and Wales) Regulations")

      assert info.type_code == "uksi"
      assert info.number == "1154"
      assert info.year == 2016
    end

    test "returns :not_found for unknown legislation" do
      assert :not_found = LookupTable.lookup("Some Unknown Act That Does Not Exist")
    end

    test "returns :not_found for nil input" do
      assert :not_found = LookupTable.lookup(nil)
    end

    test "returns :not_found for empty string" do
      assert :not_found = LookupTable.lookup("")
    end
  end

  describe "lookup/2 with year validation" do
    test "returns info when year matches" do
      assert {:ok, info} = LookupTable.lookup("Health and Safety at Work etc. Act", 1974)

      assert info.year == 1974
    end

    test "returns :year_mismatch when year doesn't match" do
      assert {:error, :year_mismatch} =
               LookupTable.lookup("Health and Safety at Work etc. Act", 2000)
    end

    test "returns :not_found for unknown legislation with year" do
      assert :not_found = LookupTable.lookup("Unknown Act", 1974)
    end

    test "ignores nil year and returns result" do
      assert {:ok, _info} = LookupTable.lookup("Health and Safety at Work etc. Act", nil)
    end
  end

  describe "exists?/1" do
    test "returns true for known legislation" do
      assert LookupTable.exists?("Health and Safety at Work etc. Act")
      assert LookupTable.exists?("Environmental Protection Act")
      assert LookupTable.exists?("Work at Height Regulations")
    end

    test "returns true with normalized variations" do
      assert LookupTable.exists?("THE HEALTH AND SAFETY AT WORK ETC. ACT 1974")
      assert LookupTable.exists?("The Environmental Protection Act 1990")
    end

    test "returns false for unknown legislation" do
      refute LookupTable.exists?("Unknown Legislation")
    end

    test "returns false for nil" do
      refute LookupTable.exists?(nil)
    end
  end

  describe "count/0" do
    test "returns positive count" do
      count = LookupTable.count()
      assert count > 0
      # Should have at least 30+ entries (H&S + Environmental)
      assert count >= 30
    end
  end

  describe "all_entries/0" do
    test "returns list of entries" do
      entries = LookupTable.all_entries()

      assert is_list(entries)
      assert length(entries) > 0
    end

    test "each entry has required fields" do
      entries = LookupTable.all_entries()

      Enum.each(entries, fn {title, info} ->
        assert is_binary(title)
        assert is_binary(info.type_code)
        assert is_binary(info.number)
        assert is_integer(info.year)
        assert is_binary(info.url)
        assert String.starts_with?(info.url, "https://www.legislation.gov.uk/")
      end)
    end

    test "entries are sorted alphabetically by title" do
      entries = LookupTable.all_entries()
      titles = Enum.map(entries, fn {title, _} -> title end)

      assert titles == Enum.sort(titles)
    end
  end

  describe "URL generation" do
    test "generates correct URL for Acts" do
      {:ok, info} = LookupTable.lookup("Health and Safety at Work etc. Act")

      assert info.url == "https://www.legislation.gov.uk/ukpga/1974/37"
    end

    test "generates correct URL for Statutory Instruments" do
      {:ok, info} = LookupTable.lookup("Work at Height Regulations")

      assert info.url == "https://www.legislation.gov.uk/uksi/2005/735"
    end
  end

  describe "common HSE enforcement legislation" do
    test "includes PUWER" do
      assert {:ok, info} = LookupTable.lookup("Provision and Use of Work Equipment Regulations")
      assert info.year == 1998
    end

    test "includes LOLER" do
      assert {:ok, info} =
               LookupTable.lookup("Lifting Operations and Lifting Equipment Regulations")

      assert info.year == 1998
    end

    test "includes RIDDOR" do
      assert {:ok, info} =
               LookupTable.lookup(
                 "Reporting of Injuries, Diseases and Dangerous Occurrences Regulations"
               )

      assert info.year == 2013
    end

    test "includes Electricity at Work Regulations" do
      assert {:ok, info} = LookupTable.lookup("Electricity at Work Regulations")
      assert info.year == 1989
    end

    test "includes Control of Asbestos Regulations" do
      assert {:ok, info} = LookupTable.lookup("Control of Asbestos Regulations")
      assert info.year == 2012
    end

    test "includes DSEAR" do
      assert {:ok, info} =
               LookupTable.lookup("Dangerous Substances and Explosive Atmospheres Regulations")

      assert info.year == 2002
    end

    test "includes COMAH" do
      assert {:ok, info} = LookupTable.lookup("Control of Major Accident Hazards Regulations")
      assert info.year == 2015
    end
  end

  describe "common EA enforcement legislation" do
    test "includes Waste Regulations" do
      assert {:ok, info} = LookupTable.lookup("Waste (England and Wales) Regulations")
      assert info.year == 2011
    end

    test "includes Wildlife and Countryside Act" do
      assert {:ok, info} = LookupTable.lookup("Wildlife and Countryside Act")
      assert info.year == 1981
    end

    test "includes Clean Air Act" do
      assert {:ok, info} = LookupTable.lookup("Clean Air Act")
      assert info.year == 1993
    end

    test "includes Control of Pollution regulations" do
      assert {:ok, _info} =
               LookupTable.lookup("Control of Pollution (Oil Storage) (England) Regulations")
    end
  end
end
