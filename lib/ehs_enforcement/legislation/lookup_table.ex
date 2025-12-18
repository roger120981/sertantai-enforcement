defmodule EhsEnforcement.Legislation.LookupTable do
  @moduledoc """
  Lookup table mapping common UK legislation titles to their legislation.gov.uk identifiers.

  This enables Tier 1 matching (year + type_code + number) even when scraped data
  only provides the legislation title and year. The lookup table contains the most
  commonly cited legislation in HSE and EA enforcement actions.

  ## Usage

      # Lookup by normalized title
      case LookupTable.lookup("Health and Safety at Work etc. Act") do
        {:ok, %{type_code: "ukpga", number: "37"}} -> # Found!
        :not_found -> # Not in lookup table
      end

      # Lookup with year for validation
      case LookupTable.lookup("Health and Safety at Work etc. Act", 1974) do
        {:ok, info} -> # Found and year matches
        {:error, :year_mismatch} -> # Found but year doesn't match
        :not_found -> # Not in lookup table
      end

  ## Data Source

  The lookup table entries are derived from the Baserow legislation register
  (2,449 records imported) and prioritize legislation commonly cited in:
  - HSE prosecutions and notices
  - EA enforcement actions
  - Other UK regulators (SEPA, NRW, etc.)
  """

  alias EhsEnforcement.Utility

  @typedoc "Legislation identifier from lookup table"
  @type legislation_info :: %{
          type_code: String.t(),
          number: String.t(),
          year: integer(),
          url: String.t()
        }

  # Health and Safety legislation (commonly cited in HSE cases)
  @health_and_safety_legislation %{
    # Primary H&S Act
    "Health and Safety at Work etc. Act" => %{type_code: "ukpga", number: "37", year: 1974},

    # Management Regulations
    "Management of Health and Safety at Work Regulations" => %{
      type_code: "uksi",
      number: "3242",
      year: 1999
    },

    # Construction
    "Construction (Design and Management) Regulations" => %{
      type_code: "uksi",
      number: "51",
      year: 2015
    },
    "Construction (Health, Safety and Welfare) Regulations" => %{
      type_code: "uksi",
      number: "3139",
      year: 1996
    },

    # Hazardous Substances
    "Control of Substances Hazardous to Health Regulations" => %{
      type_code: "uksi",
      number: "2677",
      year: 2002
    },
    "Control of Asbestos Regulations" => %{type_code: "uksi", number: "632", year: 2012},
    "Control of Lead at Work Regulations" => %{type_code: "uksi", number: "2676", year: 2002},

    # Work Equipment
    "Provision and Use of Work Equipment Regulations" => %{
      type_code: "uksi",
      number: "2306",
      year: 1998
    },
    "Lifting Operations and Lifting Equipment Regulations" => %{
      type_code: "uksi",
      number: "2307",
      year: 1998
    },

    # Working at Height
    "Work at Height Regulations" => %{type_code: "uksi", number: "735", year: 2005},

    # Workplace
    "Workplace (Health, Safety and Welfare) Regulations" => %{
      type_code: "uksi",
      number: "3004",
      year: 1992
    },
    "Health and Safety (Display Screen Equipment) Regulations" => %{
      type_code: "uksi",
      number: "2792",
      year: 1992
    },

    # Manual Handling
    "Manual Handling Operations Regulations" => %{type_code: "uksi", number: "2793", year: 1992},

    # PPE
    "Personal Protective Equipment at Work Regulations" => %{
      type_code: "uksi",
      number: "2966",
      year: 1992
    },

    # Reporting
    "Reporting of Injuries, Diseases and Dangerous Occurrences Regulations" => %{
      type_code: "uksi",
      number: "1471",
      year: 2013
    },

    # Electricity
    "Electricity at Work Regulations" => %{type_code: "uksi", number: "635", year: 1989},

    # Gas
    "Gas Safety (Installation and Use) Regulations" => %{
      type_code: "uksi",
      number: "2451",
      year: 1998
    },

    # Pressure Systems
    "Pressure Systems Safety Regulations" => %{type_code: "uksi", number: "128", year: 2000},

    # Dangerous Substances
    "Dangerous Substances and Explosive Atmospheres Regulations" => %{
      type_code: "uksi",
      number: "2776",
      year: 2002
    },

    # Noise and Vibration
    "Control of Noise at Work Regulations" => %{type_code: "uksi", number: "1643", year: 2005},
    "Control of Vibration at Work Regulations" => %{type_code: "uksi", number: "1093", year: 2005},

    # Major Hazards
    "Control of Major Accident Hazards Regulations" => %{
      type_code: "uksi",
      number: "483",
      year: 2015
    },

    # First Aid
    "Health and Safety (First-aid) Regulations" => %{type_code: "uksi", number: "917", year: 1981},

    # Consultation
    "Health and Safety (Consultation with Employees) Regulations" => %{
      type_code: "uksi",
      number: "1513",
      year: 1996
    },
    "Safety Representatives and Safety Committees Regulations" => %{
      type_code: "uksi",
      number: "500",
      year: 1977
    },

    # Corporate Manslaughter
    "Corporate Manslaughter and Corporate Homicide Act" => %{
      type_code: "ukpga",
      number: "19",
      year: 2007
    }
  }

  # Environmental legislation (commonly cited in EA cases)
  @environmental_legislation %{
    # Primary Environmental Acts
    "Environmental Protection Act" => %{type_code: "ukpga", number: "43", year: 1990},
    "Environment Act 1995" => %{type_code: "ukpga", number: "25", year: 1995},
    "Environment Act 2021" => %{type_code: "ukpga", number: "17", year: 2021},

    # Water
    "Water Resources Act" => %{type_code: "ukpga", number: "57", year: 1991},
    "Water Industry Act" => %{type_code: "ukpga", number: "56", year: 1991},
    "Water Act" => %{type_code: "ukpga", number: "37", year: 2003},
    "Flood and Water Management Act" => %{type_code: "ukpga", number: "29", year: 2010},

    # Environmental Permitting
    "Environmental Permitting (England and Wales) Regulations" => %{
      type_code: "uksi",
      number: "1154",
      year: 2016
    },

    # Waste
    "Waste (England and Wales) Regulations" => %{type_code: "uksi", number: "988", year: 2011},
    "Hazardous Waste (England and Wales) Regulations" => %{
      type_code: "uksi",
      number: "894",
      year: 2005
    },
    "Controlled Waste (England and Wales) Regulations" => %{
      type_code: "uksi",
      number: "819",
      year: 2012
    },
    "Waste Electrical and Electronic Equipment Regulations" => %{
      type_code: "uksi",
      number: "3289",
      year: 2013
    },

    # Pollution Control
    "Control of Pollution (Oil Storage) (England) Regulations" => %{
      type_code: "uksi",
      number: "2954",
      year: 2001
    },
    "Control of Pollution (Silage, Slurry and Agricultural Fuel Oil) Regulations" => %{
      type_code: "uksi",
      number: "324",
      year: 1991
    },

    # Wildlife and Habitats
    "Wildlife and Countryside Act" => %{type_code: "ukpga", number: "69", year: 1981},
    "Conservation of Habitats and Species Regulations" => %{
      type_code: "uksi",
      number: "490",
      year: 2017
    },

    # Salmon and Freshwater Fisheries
    "Salmon and Freshwater Fisheries Act" => %{type_code: "ukpga", number: "41", year: 1975},

    # Clean Air
    "Clean Air Act" => %{type_code: "ukpga", number: "40", year: 1993},

    # Climate Change
    "Climate Change Act" => %{type_code: "ukpga", number: "27", year: 2008}
  }

  # Combine all legislation into single lookup map
  @all_legislation Map.merge(@health_and_safety_legislation, @environmental_legislation)

  # Build normalized title index at compile time
  @normalized_index (for {title, info} <- @all_legislation, into: %{} do
                       normalized = Utility.normalize_legislation_title(title)
                       {normalized, Map.put(info, :original_title, title)}
                     end)

  @doc """
  Lookup legislation info by title.

  The title is normalized before lookup to handle variations in casing,
  leading "The", and trailing year.

  ## Examples

      iex> LookupTable.lookup("Health and Safety at Work etc. Act")
      {:ok, %{type_code: "ukpga", number: "37", year: 1974, url: "https://www.legislation.gov.uk/ukpga/1974/37"}}

      iex> LookupTable.lookup("THE HEALTH AND SAFETY AT WORK ETC. ACT 1974")
      {:ok, %{type_code: "ukpga", number: "37", year: 1974, url: "https://www.legislation.gov.uk/ukpga/1974/37"}}

      iex> LookupTable.lookup("Unknown Legislation")
      :not_found
  """
  @spec lookup(String.t()) :: {:ok, legislation_info()} | :not_found
  def lookup(title) when is_binary(title) do
    normalized = Utility.normalize_legislation_title(title)

    case Map.get(@normalized_index, normalized) do
      nil ->
        :not_found

      info ->
        {:ok, build_full_info(info)}
    end
  end

  def lookup(nil), do: :not_found

  @doc """
  Lookup legislation info by title with year validation.

  Returns `{:error, :year_mismatch}` if the title is found but the year
  doesn't match. This helps catch cases where the same title exists for
  multiple years (rare but possible).

  ## Examples

      iex> LookupTable.lookup("Health and Safety at Work etc. Act", 1974)
      {:ok, %{type_code: "ukpga", number: "37", year: 1974, url: "https://www.legislation.gov.uk/ukpga/1974/37"}}

      iex> LookupTable.lookup("Health and Safety at Work etc. Act", 2000)
      {:error, :year_mismatch}

      iex> LookupTable.lookup("Unknown Legislation", 1974)
      :not_found
  """
  @spec lookup(String.t(), integer() | nil) ::
          {:ok, legislation_info()} | {:error, :year_mismatch} | :not_found
  def lookup(title, nil), do: lookup(title)

  def lookup(title, year) when is_binary(title) and is_integer(year) do
    case lookup(title) do
      {:ok, info} ->
        if info.year == year do
          {:ok, info}
        else
          {:error, :year_mismatch}
        end

      :not_found ->
        :not_found
    end
  end

  @doc """
  Get all entries in the lookup table.

  Returns a list of `{normalized_title, info}` tuples.
  Useful for debugging and documentation.
  """
  @spec all_entries() :: [{String.t(), legislation_info()}]
  def all_entries do
    @normalized_index
    |> Enum.map(fn {title, info} -> {title, build_full_info(info)} end)
    |> Enum.sort_by(fn {title, _} -> title end)
  end

  @doc """
  Get count of entries in the lookup table.
  """
  @spec count() :: integer()
  def count, do: map_size(@normalized_index)

  @doc """
  Check if a title exists in the lookup table.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(title) when is_binary(title) do
    normalized = Utility.normalize_legislation_title(title)
    Map.has_key?(@normalized_index, normalized)
  end

  def exists?(nil), do: false

  # Build full info map with URL
  defp build_full_info(%{type_code: type_code, number: number, year: year} = info) do
    %{
      type_code: type_code,
      number: number,
      year: year,
      url: Utility.build_legislation_url(type_code, year, number),
      original_title: Map.get(info, :original_title)
    }
  end
end
