defmodule EhsEnforcement.Legislation.TieredMatcher do
  @moduledoc """
  Consolidated tiered matching for finding or creating Legislation records.

  Implements a priority-based matching strategy to prevent duplicates and
  maximize linking to existing legislation records in the database.

  ## Matching Tiers (in order of precedence)

  1. **Tier 1: Unique Identifier Match** - `year + type_code + number`
     Highest confidence. Uses the legislation.gov.uk unique identifier.
     This is authoritative - if found, it's definitely the right record.

  2. **Tier 2: Title + Year + Number** - When type_code unavailable
     High confidence. Falls back when type_code is not known.

  3. **Tier 3: Title + Year + Type Code** - When number unavailable
     High confidence. Falls back when number is not known.

  4. **Tier 4: Exact Normalized Title + Year**
     Medium confidence. Uses exact title match after normalization.

  5. **Tier 5: Fuzzy Title + Year** - Similarity >= 0.85
     Lower confidence. Handles title variations and typos.

  6. **Tier 6: Create New Record**
     Last resort. Logs warning for manual review.

  ## Pre-Processing

  Before matching, the module attempts to enrich input data using:
  - `LookupTable` - Maps known legislation titles to their unique identifiers
  - `Utility.parse_legislation_url/1` - Extracts identifiers from legislation.gov.uk URLs

  ## Usage

      # From breach text (most common case)
      {:ok, legislation} = TieredMatcher.find_or_create(%{
        title: "Health and Safety at Work etc. Act",
        year: 1974
      })

      # With URL (highest confidence)
      {:ok, legislation} = TieredMatcher.find_or_create(%{
        title: "Health and Safety at Work etc. Act",
        year: 1974,
        url: "https://www.legislation.gov.uk/ukpga/1974/37"
      })

      # Returns match tier for debugging
      {:ok, legislation, tier: 1} = TieredMatcher.find_or_create_with_tier(%{...})
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Enforcement.Legislation
  alias EhsEnforcement.Legislation.LookupTable
  alias EhsEnforcement.Utility

  @similarity_threshold 0.85

  @type match_input :: %{
          required(:title) => String.t(),
          optional(:year) => integer() | nil,
          optional(:number) => String.t() | nil,
          optional(:type_code) => String.t() | nil,
          optional(:url) => String.t() | nil,
          optional(:type) => atom() | nil
        }

  @type match_result :: {:ok, Legislation.t()} | {:error, term()}
  @type match_result_with_tier :: {:ok, Legislation.t(), keyword()} | {:error, term()}

  @doc """
  Find or create a Legislation record using tiered matching.

  Accepts a map with the following keys:
  - `:title` (required) - Legislation title
  - `:year` (optional) - Year of enactment
  - `:number` (optional) - Legislation number
  - `:type_code` (optional) - legislation.gov.uk type code (ukpga, uksi, etc.)
  - `:url` (optional) - legislation.gov.uk URL
  - `:type` (optional) - Legislation type atom (:act, :regulation, etc.)

  Options:
  - `:actor` - Actor for Ash authorization

  Returns `{:ok, legislation}` or `{:error, reason}`.
  """
  @spec find_or_create(match_input(), keyword()) :: match_result()
  def find_or_create(input, opts \\ []) do
    case find_or_create_with_tier(input, opts) do
      {:ok, legislation, _meta} -> {:ok, legislation}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Find or create with tier information for debugging/logging.

  Returns `{:ok, legislation, [tier: n, match_type: :atom]}` or `{:error, reason}`.
  """
  @spec find_or_create_with_tier(match_input(), keyword()) :: match_result_with_tier()
  def find_or_create_with_tier(input, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    # Step 1: Normalize and enrich input
    enriched = enrich_input(input)

    Logger.debug(
      "TieredMatcher: Looking for legislation - title: #{enriched.title}, " <>
        "year: #{enriched.year || "nil"}, type_code: #{enriched.type_code || "nil"}, " <>
        "number: #{enriched.number || "nil"}"
    )

    # Step 2: Try each tier in order
    case try_all_tiers(enriched, actor) do
      {:found, legislation, tier, match_type} ->
        Logger.debug("TieredMatcher: Found match at tier #{tier} (#{match_type})")
        {:ok, legislation, tier: tier, match_type: match_type}

      {:not_found, enriched_data} ->
        # Tier 6: Create new record
        case create_legislation(enriched_data, actor) do
          {:ok, legislation} ->
            Logger.info(
              "TieredMatcher: Created new legislation (tier 6): #{enriched_data.title} " <>
                "(year: #{enriched_data.year || "nil"})"
            )

            {:ok, legislation, tier: 6, match_type: :created}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Enrich input with data from lookup table and URL parsing
  defp enrich_input(input) do
    title = Map.fetch!(input, :title)
    normalized_title = Utility.normalize_legislation_title(title)
    year = Map.get(input, :year)
    number = Map.get(input, :number)
    type_code = Map.get(input, :type_code)
    url = Map.get(input, :url)
    type = Map.get(input, :type)

    # Try to extract from URL first (highest confidence)
    {url_type_code, url_year, url_number} =
      case url do
        nil ->
          {nil, nil, nil}

        url_string ->
          case Utility.parse_legislation_url(url_string) do
            {:ok, %{type_code: tc, year: y, number: n}} -> {tc, y, n}
            {:error, _} -> {nil, nil, nil}
          end
      end

    # Try lookup table if we don't have type_code/number
    {lookup_type_code, lookup_number, lookup_year} =
      case LookupTable.lookup(normalized_title) do
        {:ok, info} -> {info.type_code, info.number, info.year}
        :not_found -> {nil, nil, nil}
      end

    # Merge with priority: URL > explicit input > lookup table
    final_type_code = url_type_code || type_code || lookup_type_code
    final_number = url_number || number || lookup_number
    final_year = url_year || year || lookup_year
    final_type = type || Utility.determine_legislation_type(title)

    # Build URL if we have all the parts
    final_url =
      cond do
        url != nil ->
          url

        final_type_code && final_year && final_number ->
          Utility.build_legislation_url(final_type_code, final_year, final_number)

        true ->
          nil
      end

    %{
      title: normalized_title,
      original_title: title,
      year: final_year,
      number: final_number,
      type_code: final_type_code,
      type: final_type,
      url: final_url
    }
  end

  # Try all matching tiers in order
  defp try_all_tiers(enriched, actor) do
    with {:not_found, _} <- try_tier_1(enriched, actor),
         {:not_found, _} <- try_tier_2(enriched, actor),
         {:not_found, _} <- try_tier_3(enriched, actor),
         {:not_found, _} <- try_tier_4(enriched, actor),
         {:not_found, _} <- try_tier_5(enriched, actor) do
      {:not_found, enriched}
    end
  end

  # Tier 1: Match on year + type_code + number (unique identifier)
  defp try_tier_1(%{year: nil} = enriched, _actor), do: {:not_found, enriched}
  defp try_tier_1(%{type_code: nil} = enriched, _actor), do: {:not_found, enriched}
  defp try_tier_1(%{number: nil} = enriched, _actor), do: {:not_found, enriched}

  defp try_tier_1(%{year: year, type_code: type_code, number: number} = enriched, actor) do
    query =
      Legislation
      |> Ash.Query.filter(
        legislation_year == ^year and
          legislation_type_code == ^type_code and
          legislation_number == ^number
      )

    query_opts = if actor, do: [actor: actor], else: []

    case Ash.read_one(query, query_opts) do
      {:ok, nil} -> {:not_found, enriched}
      {:ok, legislation} -> {:found, legislation, 1, :unique_identifier}
      {:error, _} -> {:not_found, enriched}
    end
  end

  # Tier 2: Match on title + year + number
  defp try_tier_2(%{year: nil} = enriched, _actor), do: {:not_found, enriched}
  defp try_tier_2(%{number: nil} = enriched, _actor), do: {:not_found, enriched}

  defp try_tier_2(%{title: title, year: year, number: number} = enriched, actor) do
    query =
      Legislation
      |> Ash.Query.filter(
        legislation_title == ^title and
          legislation_year == ^year and
          legislation_number == ^number
      )

    query_opts = if actor, do: [actor: actor], else: []

    case Ash.read_one(query, query_opts) do
      {:ok, nil} -> {:not_found, enriched}
      {:ok, legislation} -> {:found, legislation, 2, :title_year_number}
      {:error, _} -> {:not_found, enriched}
    end
  end

  # Tier 3: Match on title + year + type_code
  defp try_tier_3(%{year: nil} = enriched, _actor), do: {:not_found, enriched}
  defp try_tier_3(%{type_code: nil} = enriched, _actor), do: {:not_found, enriched}

  defp try_tier_3(%{title: title, year: year, type_code: type_code} = enriched, actor) do
    query =
      Legislation
      |> Ash.Query.filter(
        legislation_title == ^title and
          legislation_year == ^year and
          legislation_type_code == ^type_code
      )

    query_opts = if actor, do: [actor: actor], else: []

    case Ash.read_one(query, query_opts) do
      {:ok, nil} -> {:not_found, enriched}
      {:ok, legislation} -> {:found, legislation, 3, :title_year_type_code}
      {:error, _} -> {:not_found, enriched}
    end
  end

  # Tier 4: Match on normalized title + year (exact)
  defp try_tier_4(%{year: nil} = enriched, _actor), do: {:not_found, enriched}

  defp try_tier_4(%{title: title, year: year} = enriched, actor) do
    query =
      Legislation
      |> Ash.Query.filter(legislation_title == ^title and legislation_year == ^year)

    query_opts = if actor, do: [actor: actor], else: []

    case Ash.read_one(query, query_opts) do
      {:ok, nil} ->
        {:not_found, enriched}

      {:ok, legislation} ->
        {:found, legislation, 4, :title_year_exact}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        # Multiple matches - this shouldn't happen with proper uniqueness constraints
        # but handle gracefully by taking the first match
        if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
          {:not_found, enriched}
        else
          Logger.warning("TieredMatcher: Multiple matches for title+year: #{title} (#{year})")
          {:not_found, enriched}
        end

      {:error, _} ->
        {:not_found, enriched}
    end
  end

  # Tier 5: Match on title + year (fuzzy, similarity >= 0.85)
  defp try_tier_5(%{year: nil} = enriched, _actor), do: {:not_found, enriched}

  defp try_tier_5(%{title: title, year: year} = enriched, actor) do
    # Get candidates with the same year
    query =
      Legislation
      |> Ash.Query.filter(legislation_year == ^year)

    query_opts = if actor, do: [actor: actor], else: []

    case Ash.read(query, query_opts) do
      {:ok, []} ->
        {:not_found, enriched}

      {:ok, candidates} ->
        # Find best fuzzy match
        best_match =
          candidates
          |> Enum.map(fn candidate ->
            similarity = Utility.calculate_title_similarity(title, candidate.legislation_title)
            {candidate, similarity}
          end)
          |> Enum.filter(fn {_candidate, similarity} -> similarity >= @similarity_threshold end)
          |> Enum.max_by(fn {_candidate, similarity} -> similarity end, fn -> nil end)

        case best_match do
          nil ->
            {:not_found, enriched}

          {legislation, similarity} ->
            Logger.debug(
              "TieredMatcher: Fuzzy match (#{Float.round(similarity, 2)}): " <>
                "\"#{title}\" -> \"#{legislation.legislation_title}\""
            )

            {:found, legislation, 5, :fuzzy_match}
        end

      {:error, _} ->
        {:not_found, enriched}
    end
  end

  # Create new legislation record (Tier 6)
  defp create_legislation(enriched, actor) do
    attrs = %{
      legislation_title: enriched.title,
      legislation_year: enriched.year,
      legislation_number: enriched.number,
      legislation_type: enriched.type,
      legislation_type_code: enriched.type_code,
      legislation_url: enriched.url
    }

    create_opts = if actor, do: [actor: actor], else: []

    Logger.warning(
      "TieredMatcher: Creating new legislation record - please review: " <>
        "#{enriched.title} (year: #{enriched.year || "nil"}, " <>
        "type_code: #{enriched.type_code || "nil"}, number: #{enriched.number || "nil"})"
    )

    case Ash.create(Legislation, attrs, create_opts) do
      {:ok, legislation} ->
        {:ok, legislation}

      {:error, %Ash.Error.Invalid{errors: errors} = ash_error} ->
        # Check for race condition (another process created it)
        if duplicate_error?(errors) do
          Logger.debug("TieredMatcher: Race condition detected, retrying lookup")
          retry_after_race_condition(enriched, actor)
        else
          Logger.error("TieredMatcher: Failed to create legislation: #{inspect(ash_error)}")
          {:error, ash_error}
        end

      {:error, reason} ->
        Logger.error("TieredMatcher: Failed to create legislation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Handle race condition by retrying the full tier lookup
  defp retry_after_race_condition(enriched, actor) do
    case try_all_tiers(enriched, actor) do
      {:found, legislation, tier, match_type} ->
        Logger.debug("TieredMatcher: Found after race condition at tier #{tier} (#{match_type})")
        {:ok, legislation}

      {:not_found, _} ->
        # Still not found - this is unexpected
        {:error, :race_condition_unresolved}
    end
  end

  # Check if error is a uniqueness constraint violation
  defp duplicate_error?(errors) do
    Enum.any?(errors, fn error ->
      case error do
        %{field: _, message: message} when is_binary(message) ->
          String.contains?(message, "already been taken") or
            String.contains?(message, "already exists") or
            String.contains?(message, "unique constraint")

        %{message: message} when is_binary(message) ->
          String.contains?(message, "unique_legislation") or
            String.contains?(message, "unique_gov_uk") or
            String.contains?(message, "unique constraint")

        _ ->
          false
      end
    end)
  end

  @doc """
  Find legislation without creating. Returns nil if not found.
  """
  @spec find(match_input(), keyword()) :: {:ok, Legislation.t() | nil}
  def find(input, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    enriched = enrich_input(input)

    case try_all_tiers(enriched, actor) do
      {:found, legislation, _tier, _match_type} -> {:ok, legislation}
      {:not_found, _} -> {:ok, nil}
    end
  end

  @doc """
  Find legislation with tier information. Returns nil if not found.
  """
  @spec find_with_tier(match_input(), keyword()) :: {:ok, Legislation.t() | nil, keyword()}
  def find_with_tier(input, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    enriched = enrich_input(input)

    case try_all_tiers(enriched, actor) do
      {:found, legislation, tier, match_type} ->
        {:ok, legislation, tier: tier, match_type: match_type}

      {:not_found, _} ->
        {:ok, nil, tier: nil, match_type: nil}
    end
  end

  @doc """
  Batch find or create multiple legislation records.

  Returns a map of input titles to legislation records.
  """
  @spec batch_find_or_create([match_input()], keyword()) :: {:ok, map()} | {:error, term()}
  def batch_find_or_create(inputs, opts \\ []) when is_list(inputs) do
    results =
      Enum.reduce_while(inputs, {:ok, %{}}, fn input, {:ok, acc} ->
        title = Map.fetch!(input, :title)

        case find_or_create(input, opts) do
          {:ok, legislation} ->
            {:cont, {:ok, Map.put(acc, title, legislation)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, legislation_map} ->
        Logger.info(
          "TieredMatcher: Batch processed #{map_size(legislation_map)} legislation records"
        )

        {:ok, legislation_map}

      error ->
        error
    end
  end
end
