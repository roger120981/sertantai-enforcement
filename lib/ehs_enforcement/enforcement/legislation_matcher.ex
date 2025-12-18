defmodule EhsEnforcement.Enforcement.LegislationMatcher do
  @moduledoc """
  Finds or creates Legislation records from breach text parsing.

  Uses `BreachParser` to extract legislation references, then delegates
  to `TieredMatcher` for finding or creating Legislation records.

  ## Example Flow

      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1)"
      {:ok, legislation_id} = LegislationMatcher.find_or_create_from_breach(breach_text)

  ## Matching Strategy

  This module delegates to `EhsEnforcement.Legislation.TieredMatcher` which
  implements a 6-tier matching strategy:

  1. Unique identifier (year + type_code + number)
  2. Title + year + number
  3. Title + year + type_code
  4. Exact normalized title + year
  5. Fuzzy title + year (similarity >= 0.85)
  6. Create new record (logs warning)

  See `TieredMatcher` documentation for full details.
  """

  require Logger

  alias EhsEnforcement.Enforcement.BreachParser
  alias EhsEnforcement.Legislation.TieredMatcher

  @doc """
  Find or create Legislation record from breach text.

  Returns `{:ok, legislation_id}` or `{:error, reason}`.
  Returns `{:ok, nil}` if no legislation can be extracted.
  """
  def find_or_create_from_breach(breach_text, opts \\ []) when is_binary(breach_text) do
    parsed = BreachParser.parse_breach(breach_text)

    case {parsed.act_name, parsed.act_year} do
      {nil, _} ->
        Logger.debug("No legislation found in breach: #{String.slice(breach_text, 0..50)}")
        {:ok, nil}

      {act_name, act_year} ->
        find_or_create_legislation(act_name, act_year, parsed.legislation_part, opts)
    end
  end

  @doc """
  Find or create Legislation record from structured data.

  Args:
  - `act_name`: Full name of Act/Regulation (e.g., "Health and Safety at Work etc Act 1974")
  - `act_year`: Year of legislation (integer or nil)
  - `legislation_part`: Section/Regulation reference (not used for lookup, stored in Offence)
  - `opts`: Options including `:actor` for authorization

  Returns `{:ok, legislation_id}` or `{:error, reason}`.
  """
  def find_or_create_legislation(act_name, act_year, _legislation_part \\ nil, opts \\ [])

  # Handle old 4-arg signature where nil actor was passed directly
  def find_or_create_legislation(act_name, act_year, legislation_part, nil) do
    find_or_create_legislation(act_name, act_year, legislation_part, [])
  end

  # Handle old 4-arg signature where non-nil actor was passed directly
  def find_or_create_legislation(act_name, act_year, legislation_part, actor)
      when not is_list(actor) do
    find_or_create_legislation(act_name, act_year, legislation_part, actor: actor)
  end

  def find_or_create_legislation(act_name, act_year, _legislation_part, opts)
      when is_list(opts) do
    input = %{
      title: act_name,
      year: act_year
    }

    case TieredMatcher.find_or_create(input, opts) do
      {:ok, legislation} ->
        {:ok, legislation.id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Find or create Legislation with tier information for debugging.

  Returns `{:ok, legislation_id, [tier: n, match_type: atom]}` or `{:error, reason}`.
  """
  def find_or_create_from_breach_with_tier(breach_text, opts \\ []) when is_binary(breach_text) do
    parsed = BreachParser.parse_breach(breach_text)

    case {parsed.act_name, parsed.act_year} do
      {nil, _} ->
        Logger.debug("No legislation found in breach: #{String.slice(breach_text, 0..50)}")
        {:ok, nil, tier: nil, match_type: nil}

      {act_name, act_year} ->
        input = %{title: act_name, year: act_year}

        case TieredMatcher.find_or_create_with_tier(input, opts) do
          {:ok, legislation, meta} ->
            {:ok, legislation.id, meta}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Bulk find or create Legislation records from list of breach texts.

  Returns `{:ok, legislation_id_map}` where map is `%{breach_text => legislation_id}`.
  Legislation IDs may be nil if no legislation could be extracted.
  """
  def bulk_find_or_create_from_breaches(breach_texts, opts \\ [])
      when is_list(breach_texts) do
    results =
      Enum.reduce_while(breach_texts, {:ok, %{}}, fn breach_text, {:ok, acc} ->
        case find_or_create_from_breach(breach_text, opts) do
          {:ok, legislation_id} ->
            {:cont, {:ok, Map.put(acc, breach_text, legislation_id)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, id_map} ->
        legislation_count = Enum.count(id_map, fn {_k, v} -> not is_nil(v) end)

        Logger.info(
          "Bulk legislation lookup complete: #{legislation_count}/#{length(breach_texts)} found"
        )

        {:ok, id_map}

      error ->
        error
    end
  end

  @doc """
  Extract legislation title for display (helper function).

  Returns human-readable legislation title from breach text.
  """
  def extract_display_title(breach_text) when is_binary(breach_text) do
    BreachParser.extract_legislation_title(breach_text)
  end
end
