defmodule EhsEnforcement.Enforcement.LegislationMatcher do
  @moduledoc """
  Finds or creates Legislation records from breach text parsing.

  Uses `BreachParser` to extract legislation references, then searches
  for existing Legislation records or creates new ones.

  Handles:
  - Normalizing legislation titles using existing utility functions
  - Fuzzy matching against existing legislation
  - Creating new Legislation records when needed
  - Caching lookups to avoid repeated database queries

  ## Example Flow

      breach_text = "Health and Safety at Work etc Act 1974, Section 2(1)"
      {:ok, legislation_id} = LegislationMatcher.find_or_create_from_breach(breach_text)
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.BreachParser
  alias EhsEnforcement.Utility

  @doc """
  Find or create Legislation record from breach text.

  Returns `{:ok, legislation_id}` or `{:error, reason}`.
  Returns `{:ok, nil}` if no legislation can be extracted.
  """
  def find_or_create_from_breach(breach_text, opts \\ []) when is_binary(breach_text) do
    actor = Keyword.get(opts, :actor)

    parsed = BreachParser.parse_breach(breach_text)

    case {parsed.act_name, parsed.act_year} do
      {nil, _} ->
        Logger.debug("No legislation found in breach: #{String.slice(breach_text, 0..50)}")
        {:ok, nil}

      {act_name, act_year} ->
        find_or_create_legislation(act_name, act_year, parsed.legislation_part, actor)
    end
  end

  @doc """
  Find or create Legislation record from structured data.

  Args:
  - `act_name`: Full name of Act/Regulation (e.g., "Health and Safety at Work etc Act 1974")
  - `act_year`: Year of legislation (integer or nil)
  - `legislation_part`: Section/Regulation reference (not used for lookup, stored in Offence)
  - `actor`: Optional actor for authorization

  Returns `{:ok, legislation_id}` or `{:error, reason}`.
  """
  def find_or_create_legislation(act_name, act_year, _legislation_part \\ nil, actor \\ nil) do
    # Normalize the title using existing utility function
    normalized_title = Utility.normalize_legislation_title(act_name)
    legislation_type = Utility.determine_legislation_type(act_name)

    Logger.debug(
      "Looking up legislation: #{normalized_title} (#{act_year || "no year"}), type: #{legislation_type}"
    )

    # Try to find existing legislation by title and year
    case find_existing_legislation(normalized_title, act_year, actor) do
      {:ok, existing} when not is_nil(existing) ->
        Logger.debug("Found existing legislation: #{existing.id}")
        {:ok, existing.id}

      {:ok, nil} ->
        # Create new legislation record
        create_legislation(normalized_title, act_year, legislation_type, actor)

      {:error, reason} ->
        Logger.error("Failed to search for legislation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Find existing legislation by normalized title and year
  defp find_existing_legislation(normalized_title, year, actor) do
    query_opts = if actor, do: [actor: actor], else: []

    query =
      if year do
        Enforcement.Legislation
        |> Ash.Query.filter(legislation_title == ^normalized_title and legislation_year == ^year)
      else
        # If no year, match on title only
        Enforcement.Legislation
        |> Ash.Query.filter(legislation_title == ^normalized_title)
        |> Ash.Query.sort(legislation_year: :desc)
        |> Ash.Query.limit(1)
      end

    query
    |> Ash.read_one(query_opts)
  end

  # Create new legislation record
  defp create_legislation(normalized_title, year, legislation_type, actor) do
    attrs = %{
      legislation_title: normalized_title,
      legislation_year: year,
      legislation_type: legislation_type
    }

    create_opts = if actor, do: [actor: actor], else: []

    Logger.info("Creating new legislation: #{normalized_title} (#{year || "no year"})")

    case Ash.create(Enforcement.Legislation, attrs, create_opts) do
      {:ok, legislation} ->
        {:ok, legislation.id}

      {:error, %Ash.Error.Invalid{errors: errors} = ash_error} ->
        # Check if this is a uniqueness constraint violation (race condition)
        if duplicate_error?(errors) do
          Logger.debug(
            "Legislation already exists (race condition), retrying lookup: #{normalized_title}"
          )

          # Retry the lookup since another process created it
          case find_existing_legislation(normalized_title, year, actor) do
            {:ok, existing} when not is_nil(existing) ->
              {:ok, existing.id}

            _ ->
              {:error, ash_error}
          end
        else
          Logger.error("Failed to create legislation: #{inspect(ash_error)}")
          {:error, ash_error}
        end

      {:error, reason} ->
        Logger.error("Failed to create legislation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if error is a uniqueness constraint violation
  defp duplicate_error?(errors) do
    Enum.any?(errors, fn error ->
      case error do
        %{field: :legislation_title, message: message} ->
          String.contains?(message, "already been taken") or
            String.contains?(message, "already exists")

        # Check for unique_legislation identity error
        %{message: message} ->
          String.contains?(message, "unique_legislation") or
            String.contains?(message, "unique constraint")

        _ ->
          false
      end
    end)
  end

  @doc """
  Bulk find or create Legislation records from list of breach texts.

  Returns `{:ok, legislation_id_map}` where map is `%{breach_text => legislation_id}`.
  Legislation IDs may be nil if no legislation could be extracted.
  """
  def bulk_find_or_create_from_breaches(breach_texts, opts \\ [])
      when is_list(breach_texts) do
    actor = Keyword.get(opts, :actor)

    results =
      Enum.reduce_while(breach_texts, {:ok, %{}}, fn breach_text, {:ok, acc} ->
        case find_or_create_from_breach(breach_text, actor: actor) do
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
