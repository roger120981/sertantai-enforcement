defmodule EhsEnforcement.Enforcement.Offender do
  @moduledoc """
  Represents a company or individual subject to enforcement action.
  Normalized to eliminate duplication between cases and notices.
  """

  use Ash.Resource,
    domain: EhsEnforcement.Enforcement,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Expr

  postgres do
    table("offenders")
    repo(EhsEnforcement.Repo)

    # Define how conditional identity constraints are translated to SQL
    identity_wheres_to_sql(
      unique_company_number: """
      company_registration_number IS NOT NULL AND
      company_registration_number != ''
      """,
      unique_name: """
      company_registration_number IS NULL OR
      company_registration_number = ''
      """
    )

    custom_indexes do
      # pg_trgm GIN indexes for fuzzy text search on offender fields
      index([:name], name: "offenders_name_gin_trgm", using: "GIN")
      index([:normalized_name], name: "offenders_normalized_name_gin_trgm", using: "GIN")
      index([:local_authority], name: "offenders_local_authority_gin_trgm", using: "GIN")
      index([:main_activity], name: "offenders_main_activity_gin_trgm", using: "GIN")
      index([:postcode], name: "offenders_postcode_gin_trgm", using: "GIN")

      # GIN index for agencies array to enable efficient array contains queries
      index([:agencies], name: "offenders_agencies_gin", using: "GIN")
    end
  end

  pub_sub do
    module(EhsEnforcementWeb.Endpoint)
    prefix("offender")

    publish(:create, ["created", :id])
    publish(:update, ["updated", :id])
    publish(:update_statistics, ["stats_updated", :id])
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:name, :string, allow_nil?: false)
    attribute(:normalized_name, :string)
    attribute(:address, :string)
    attribute(:local_authority, :string)
    attribute(:country, :string)
    attribute(:postcode, :string)
    attribute(:main_activity, :string)
    attribute(:sic_code, :string)

    attribute :business_type, :atom do
      constraints(one_of: [:limited_company, :individual, :partnership, :plc, :other])
    end

    attribute(:industry, :string)

    # Denormalized list of all agencies that have taken enforcement action against this offender
    # This allows efficient filtering without complex joins across cases and notices
    attribute(:agencies, {:array, :string}, default: [])

    # EA-specific extensions for Environment Agency enforcement data
    attribute(:company_registration_number, :string,
      description: "Companies House registration number (e.g., '04622955')"
    )

    attribute(:town, :string, description: "Town from EA structured address (e.g., 'BARNSLEY')")

    attribute(:county, :string,
      description: "County from EA structured address (e.g., 'SOUTH YORKSHIRE')"
    )

    attribute(:industry_sectors, {:array, :string},
      default: [],
      description: "EA detailed industry sectors (e.g., ['Manufacturing - General Engineering'])"
    )

    # Aggregated statistics
    attribute(:first_seen_date, :date)
    attribute(:last_seen_date, :date)
    attribute(:total_cases, :integer, default: 0)
    attribute(:total_notices, :integer, default: 0)
    attribute(:total_fines, :decimal, default: 0)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :cases, EhsEnforcement.Enforcement.Case
    has_many :notices, EhsEnforcement.Enforcement.Notice
  end

  identities do
    # For companies with registration numbers (primarily EA, potentially HSE)
    # Company registration number is authoritative - same number = same legal entity
    # This prevents duplicates when same company operates from multiple locations
    identity(:unique_company_number, [:company_registration_number],
      where: expr(not is_nil(company_registration_number) and company_registration_number != "")
    )

    # For offenders without company numbers (HSE individuals, partnerships, non-UK entities)
    # Use normalized name only (removed postcode to allow multi-location offenders)
    identity(:unique_name, [:normalized_name],
      where: expr(is_nil(company_registration_number) or company_registration_number == "")
    )
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :name,
        :address,
        :local_authority,
        :country,
        :postcode,
        :main_activity,
        :sic_code,
        :business_type,
        :industry,
        :first_seen_date,
        :last_seen_date,
        :total_cases,
        :total_notices,
        :total_fines,
        :agencies,
        # EA-specific fields
        :company_registration_number,
        :town,
        :county,
        :industry_sectors
      ])

      change(fn changeset, _context ->
        changeset
        # Normalize company name for matching
        |> normalize_name_change()
        # Clean company registration number
        |> clean_company_number_change()
      end)
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :name,
        :address,
        :local_authority,
        :country,
        :main_activity,
        :sic_code,
        :business_type,
        :industry,
        :agencies
      ])

      change(fn changeset, _context ->
        changeset
        # Normalize company name for matching
        |> normalize_name_change()
        # Clean company registration number
        |> clean_company_number_change()
      end)
    end

    update :update_statistics do
      require_atomic?(false)
      accept([])
      argument(:fine_amount, :decimal)

      change(fn changeset, _context ->
        fine_amount = Ash.Changeset.get_argument(changeset, :fine_amount) || Decimal.new("0")

        # Get current values from the database record, defaulting to 0 if nil
        current_cases = changeset.data.total_cases || 0
        current_notices = changeset.data.total_notices || 0
        current_fines = changeset.data.total_fines || Decimal.new("0")

        new_fines = Decimal.add(current_fines, fine_amount)

        # Set new values by incrementing
        changeset
        |> Ash.Changeset.force_change_attribute(:total_cases, current_cases + 1)
        |> Ash.Changeset.force_change_attribute(:total_notices, current_notices + 1)
        |> Ash.Changeset.force_change_attribute(:total_fines, new_fines)
      end)
    end

    read :search do
      argument(:query, :string, allow_nil?: false)

      filter(
        expr(
          ilike(name, "%" <> ^arg(:query) <> "%") or
            ilike(normalized_name, "%" <> ^arg(:query) <> "%") or
            ilike(local_authority, "%" <> ^arg(:query) <> "%") or
            ilike(postcode, "%" <> ^arg(:query) <> "%")
        )
      )
    end

    update :sync_and_merge_duplicates do
      require_atomic?(false)
      accept([])

      argument :duplicate_ids, {:array, :uuid} do
        allow_nil?(false)

        description(
          "IDs of duplicate offenders to merge into this one (ALL orphans deleted after merge)"
        )
      end

      change(fn changeset, _context ->
        require Logger
        master_id = changeset.data.id
        duplicate_ids = Ash.Changeset.get_argument(changeset, :duplicate_ids)

        Logger.info("Starting merge: master=#{master_id}, duplicates=#{inspect(duplicate_ids)}")

        # 1. Fetch Companies House canonical data
        company_number = changeset.data.company_registration_number

        companies_house_data =
          if company_number do
            case EhsEnforcement.Integrations.CompaniesHouse.lookup_company(company_number) do
              {:ok, profile} ->
                # 2. Validate name similarity (>= 0.9)
                canonical_name = profile["company_name"]

                similarity =
                  String.jaro_distance(
                    normalize_company_name(changeset.data.name),
                    normalize_company_name(canonical_name)
                  )

                Logger.info("Companies House validation: similarity=#{similarity}")

                # Production threshold: 0.9 (high confidence required)
                if similarity < 0.9 do
                  raise "Companies House validation failed: name similarity #{similarity} below 0.9 threshold"
                end

                # Extract address components
                address_components =
                  EhsEnforcement.Integrations.CompaniesHouse.extract_address_components(profile)

                %{
                  name: canonical_name,
                  address: address_components[:address],
                  town: address_components[:town],
                  county: address_components[:county],
                  postcode: address_components[:postcode]
                }

              {:error, reason} ->
                Logger.warning(
                  "Companies House lookup failed: #{inspect(reason)} - proceeding without validation"
                )

                # Company not found (dissolved, bad number, etc) - proceed without Companies House data
                %{}
            end
          else
            Logger.warning("No company number - skipping Companies House validation")
            %{}
          end

        # 3. Apply Companies House data to master record
        changeset =
          Enum.reduce(companies_house_data, changeset, fn {field, value}, acc ->
            if value do
              Ash.Changeset.force_change_attribute(acc, field, value)
            else
              acc
            end
          end)

        # 4. Load all duplicate offenders to get their data
        duplicates =
          Enum.map(duplicate_ids, fn id ->
            case Ash.get(EhsEnforcement.Enforcement.Offender, id) do
              {:ok, offender} ->
                offender

              {:error, error} ->
                Logger.error("Failed to load duplicate #{id}: #{inspect(error)}")
                raise "Failed to load duplicate offender: #{inspect(error)}"
            end
          end)

        Logger.warning("Note: Using direct database queries for foreign key migration")

        # 5. Migrate foreign keys from all duplicates to master using Ecto
        # (Ash doesn't have bulk update API for this pattern)
        import Ecto.Query

        # Convert UUIDs to binary format for Ecto
        master_binary = Ecto.UUID.dump!(master_id)

        Enum.each(duplicate_ids, fn duplicate_id ->
          duplicate_binary = Ecto.UUID.dump!(duplicate_id)

          # Update Cases
          {cases_updated, _} =
            EhsEnforcement.Repo.update_all(
              from(c in "cases", where: c.offender_id == ^duplicate_binary),
              set: [offender_id: master_binary, updated_at: DateTime.utc_now()]
            )

          # Update Notices
          {notices_updated, _} =
            EhsEnforcement.Repo.update_all(
              from(n in "notices", where: n.offender_id == ^duplicate_binary),
              set: [offender_id: master_binary, updated_at: DateTime.utc_now()]
            )

          Logger.info(
            "Migrated #{cases_updated} cases and #{notices_updated} notices from #{duplicate_id} to #{master_id}"
          )
        end)

        # 6. Recalculate statistics from actual data (don't trust existing totals)
        require Ash.Query

        # Count cases
        total_cases =
          EhsEnforcement.Enforcement.Case
          |> Ash.Query.filter(offender_id == ^master_id)
          |> Ash.count!()

        # Count notices
        total_notices =
          EhsEnforcement.Enforcement.Notice
          |> Ash.Query.filter(offender_id == ^master_id)
          |> Ash.count!()

        # Sum fines from cases
        total_fines =
          EhsEnforcement.Enforcement.Case
          |> Ash.Query.filter(offender_id == ^master_id)
          |> Ash.Query.select([:offence_fine])
          |> Ash.read!()
          |> Enum.reduce(Decimal.new(0), fn case_record, acc ->
            Decimal.add(acc, case_record.offence_fine || Decimal.new(0))
          end)

        Logger.info(
          "Recalculated stats: cases=#{total_cases}, notices=#{total_notices}, fines=#{total_fines}"
        )

        # 7. Merge array fields (agencies, industry_sectors) from duplicates
        all_agencies =
          [changeset.data.agencies | Enum.map(duplicates, & &1.agencies)]
          |> List.flatten()
          |> Enum.uniq()

        all_industry_sectors =
          [changeset.data.industry_sectors | Enum.map(duplicates, & &1.industry_sectors)]
          |> List.flatten()
          |> Enum.uniq()

        # Apply all updates to master record
        changeset
        |> Ash.Changeset.force_change_attribute(:total_cases, total_cases)
        |> Ash.Changeset.force_change_attribute(:total_notices, total_notices)
        |> Ash.Changeset.force_change_attribute(:total_fines, total_fines)
        |> Ash.Changeset.force_change_attribute(:agencies, all_agencies)
        |> Ash.Changeset.force_change_attribute(:industry_sectors, all_industry_sectors)
        |> Ash.Changeset.after_action(fn _changeset, result ->
          # 8. Delete ALL duplicate records after successful merge
          Enum.each(duplicate_ids, fn duplicate_id ->
            case Ash.get(EhsEnforcement.Enforcement.Offender, duplicate_id) do
              {:ok, duplicate} ->
                case Ash.destroy(duplicate) do
                  :ok ->
                    Logger.info("Deleted duplicate offender: #{duplicate_id}")

                  {:error, error} ->
                    Logger.error("Failed to delete duplicate #{duplicate_id}: #{inspect(error)}")
                    raise "Failed to delete duplicate: #{inspect(error)}"
                end

              {:error, error} ->
                Logger.error("Failed to load duplicate #{duplicate_id}: #{inspect(error)}")
            end
          end)

          {:ok, result}
        end)
      end)
    end
  end

  calculations do
    calculate :enforcement_count, :integer do
      calculation(expr(total_cases + total_notices))
    end
  end

  code_interface do
    define(:create, args: [:name])
    define(:update_statistics)
    define(:search, args: [:query])
  end

  @doc """
  Finds or creates an offender with deduplication logic.

  This function handles finding existing offenders by name and postcode,
  with fuzzy matching fallback to prevent duplicates.
  """
  def find_or_create_offender(attrs) do
    # Remove metadata fields that shouldn't be processed
    {_review_candidates, clean_attrs} = Map.pop(attrs, :__review_candidates__)

    normalized_attrs = normalize_attrs(clean_attrs)

    # Check if name is empty or only whitespace
    name = String.trim(normalized_attrs[:name] || "")

    if name == "" do
      {:error, %Ash.Error.Invalid{errors: [%{message: "Name cannot be empty"}]}}
    else
      # Use Ash to find existing offender by name and postcode
      case EhsEnforcement.Enforcement.get_offender_by_name_and_postcode(
             name,
             normalized_attrs[:postcode]
           ) do
        {:ok, offender} ->
          {:ok, offender}

        {:error, %Ash.Error.Query.NotFound{}} ->
          # Try fuzzy search - only if name has content
          if String.length(name) > 2 do
            # Normalize the search query for better matching
            normalized_search = normalize_company_name(name)

            case EhsEnforcement.Enforcement.search_offenders(normalized_search) do
              {:ok, []} ->
                # Create new offender using Ash
                create_offender_with_retry(Map.put(normalized_attrs, :name, name))

              {:ok, similar_offenders} ->
                # Return best match or create new
                best_match =
                  find_best_match(similar_offenders, Map.put(normalized_attrs, :name, name))

                if best_match do
                  {:ok, best_match}
                else
                  create_offender_with_retry(Map.put(normalized_attrs, :name, name))
                end

              {:error, %Ash.Error.Invalid{}} ->
                # Handle case where search query is invalid (empty, etc.)
                create_offender_with_retry(Map.put(normalized_attrs, :name, name))

              error ->
                error
            end
          else
            # Name too short for fuzzy search, just create
            create_offender_with_retry(Map.put(normalized_attrs, :name, name))
          end

        error ->
          error
      end
    end
  end

  @doc """
  Normalize company names to standard format for matching.
  """
  def normalize_company_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    # Remove common punctuation that could interfere with matching
    |> String.replace(~r/[\.,:;!@#$%^&*()]+/, "")
    # Normalize company suffixes
    |> String.replace(~r/\s+(limited|ltd\.?)$/i, " limited")
    |> String.replace(~r/\s+(plc|p\.l\.c\.?)$/i, " plc")
    # Replace multiple spaces with single space
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def normalize_company_name(name), do: name

  # Private helper functions for find_or_create_offender

  defp normalize_attrs(attrs) when is_map(attrs) do
    # Convert string keys to atom keys for consistent processing
    normalized_attrs =
      attrs
      |> convert_string_keys_to_atoms()
      |> Map.update(:postcode, nil, &normalize_postcode/1)
      |> normalize_business_type()

    # Ensure we have a name field
    name = String.trim(normalized_attrs[:name] || "")
    Map.put(normalized_attrs, :name, name)
  end

  defp convert_string_keys_to_atoms(attrs) do
    # Convert common string keys to atoms to ensure consistency
    key_mappings = %{
      "name" => :name,
      "postcode" => :postcode,
      "local_authority" => :local_authority,
      "main_activity" => :main_activity,
      "business_type" => :business_type,
      "industry" => :industry
    }

    Enum.reduce(key_mappings, attrs, fn {string_key, atom_key}, acc ->
      case Map.get(acc, string_key) do
        nil ->
          acc

        value ->
          acc
          |> Map.put(atom_key, value)
          |> Map.delete(string_key)
      end
    end)
  end

  defp normalize_business_type(attrs) do
    case Map.get(attrs, :business_type) do
      nil ->
        attrs

      :limited_company ->
        attrs

      :individual ->
        attrs

      :partnership ->
        attrs

      :plc ->
        attrs

      :other ->
        attrs

      _invalid_type ->
        # Remove invalid business types
        Map.delete(attrs, :business_type)
    end
  end

  defp normalize_postcode(nil), do: nil

  defp normalize_postcode(postcode) when is_binary(postcode) do
    postcode |> String.trim() |> String.upcase()
  end

  defp create_offender_with_retry(attrs) do
    require Logger
    Logger.info("Creating offender: #{attrs[:name]} (#{attrs[:postcode] || "no postcode"})")

    # Remove metadata fields that shouldn't be passed to Ash.create
    {_review_candidates, clean_attrs} = Map.pop(attrs, :__review_candidates__)

    case EhsEnforcement.Enforcement.create_offender(clean_attrs) do
      {:ok, offender} ->
        Logger.info("✅ Created offender: #{offender.name} (ID: #{offender.id})")
        {:ok, offender}

      {:error, %Ash.Error.Invalid{} = error} ->
        Logger.warning(
          "❌ Offender creation failed: #{attrs[:name]} - #{extract_error_message(error)}"
        )

        # Handle identity collision - the offender exists but possibly with different postcode
        # First try exact match (name + postcode)
        case EhsEnforcement.Enforcement.get_offender_by_name_and_postcode(
               attrs.name,
               attrs[:postcode]
             ) do
          {:ok, offender} ->
            Logger.info(
              "♻️ Found existing offender (exact match): #{offender.name} (ID: #{offender.id})"
            )

            {:ok, offender}

          {:error, %Ash.Error.Query.NotFound{}} ->
            # Postcode mismatch - try finding by normalized name only
            # This handles cases like "Diocese of Leeds" with multiple properties
            find_offender_by_normalized_name(attrs[:name])

          error ->
            Logger.error("❌ Failed to find offender after creation error: #{inspect(error)}")
            error
        end

      error ->
        Logger.error("❌ Offender creation failed with unexpected error: #{inspect(error)}")
        error
    end
  end

  defp find_offender_by_normalized_name(name) when is_binary(name) do
    require Logger
    require Ash.Query

    normalized = normalize_company_name(name)

    Logger.debug("Looking up offender by normalized name: #{normalized}")

    # Query by normalized_name directly since that's what the identity uses
    EhsEnforcement.Enforcement.Offender
    |> Ash.Query.filter(normalized_name == ^normalized)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
    |> case do
      {:ok, nil} ->
        Logger.warning("❌ No offender found with normalized name: #{normalized}")
        {:error, %Ash.Error.Query.NotFound{}}

      {:ok, offender} ->
        Logger.info(
          "♻️ Found existing offender by normalized name: #{offender.name} (ID: #{offender.id})"
        )

        {:ok, offender}

      error ->
        Logger.error("❌ Error looking up offender by normalized name: #{inspect(error)}")
        error
    end
  end

  defp find_offender_by_normalized_name(_), do: {:error, %Ash.Error.Query.NotFound{}}

  defp find_best_match([], _attrs), do: nil

  defp find_best_match(candidates, attrs) do
    search_postcode = normalize_postcode(attrs[:postcode])

    # Calculate similarity scores and postcode matches
    scored_candidates =
      candidates
      |> Enum.map(fn candidate ->
        # Calculate similarity if not already present
        similarity =
          case Map.get(candidate, :similarity) do
            nil -> calculate_similarity(get_name(candidate), attrs[:name] || "")
            existing -> existing
          end

        # Check if postcode matches
        candidate_postcode = normalize_postcode(get_postcode(candidate))
        postcode_match = candidate_postcode == search_postcode

        # If we have a search postcode and the candidate has a different postcode,
        # and they're both non-nil, then don't match (treat as different entities)
        postcode_conflict =
          search_postcode != nil &&
            candidate_postcode != nil &&
            candidate_postcode != search_postcode

        # Don't match if there's a postcode conflict (same name, different locations)
        if postcode_conflict do
          # Force no match
          Map.put(candidate, :similarity, 0.0)
        else
          # Only boost similarity if it was calculated (not pre-provided)
          adjusted_similarity =
            case Map.get(candidate, :similarity) do
              nil ->
                # We calculated it, so boost for postcode match
                if postcode_match && similarity > 0.6 do
                  # Boost by 0.15, but cap at 1.0
                  min(similarity + 0.15, 1.0)
                else
                  similarity
                end

              existing ->
                # Pre-provided similarity score, don't modify it
                existing
            end

          candidate
          |> Map.put(:similarity, adjusted_similarity)
          |> Map.put(:postcode_match, postcode_match)
        end
      end)
      |> Enum.filter(fn candidate -> Map.get(candidate, :similarity, 0) > 0.7 end)
      |> Enum.sort_by(
        fn candidate ->
          # Sort by similarity desc, then postcode match desc
          similarity = Map.get(candidate, :similarity, 0)
          postcode_match = Map.get(candidate, :postcode_match, false)
          {similarity, if(postcode_match, do: 1, else: 0)}
        end,
        :desc
      )

    case scored_candidates do
      [] -> nil
      [best | _] -> best
    end
  end

  # Get name from candidate (works with both Offender structs and plain maps)
  defp get_name(%{name: name}), do: name
  defp get_name(candidate), do: Map.get(candidate, :name, "")

  # Get postcode from candidate (works with both Offender structs and plain maps)
  defp get_postcode(%{postcode: postcode}), do: postcode
  defp get_postcode(candidate), do: Map.get(candidate, :postcode)

  defp calculate_similarity(str1, str2) do
    # Normalize both strings for comparison
    norm1 = normalize_company_name(str1 || "")
    norm2 = normalize_company_name(str2 || "")

    if norm1 == norm2 do
      1.0
    else
      # Use a combination of Jaccard similarity and length ratio
      jaccard = jaccard_similarity(norm1, norm2)

      # Boost score for very similar names (accounting for common variations)
      if String.jaro_distance(norm1, norm2) > 0.85 do
        max(jaccard, 0.9)
      else
        jaccard
      end
    end
  end

  defp jaccard_similarity(str1, str2) do
    # Split into normalized tokens for better matching
    tokens1 = str1 |> String.split(~r/\s+/) |> MapSet.new()
    tokens2 = str2 |> String.split(~r/\s+/) |> MapSet.new()

    intersection = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
    union = MapSet.union(tokens1, tokens2) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end

  defp extract_error_message(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.map_join(errors, ", ", fn error ->
      "#{error.field || "unknown"}: #{error.message || inspect(error)}"
    end)
  end

  defp extract_error_message(error), do: inspect(error)

  # Changeset helper functions

  defp normalize_name_change(changeset) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name ->
        # Keep original name, but add normalized version for matching
        normalized_name = normalize_company_name(name)
        Ash.Changeset.force_change_attribute(changeset, :normalized_name, normalized_name)
    end
  end

  defp clean_company_number_change(changeset) do
    case Ash.Changeset.get_attribute(changeset, :company_registration_number) do
      nil ->
        changeset

      number ->
        # Clean and normalize company registration number
        alias EhsEnforcement.Integrations.CompaniesHouse
        cleaned = CompaniesHouse.clean_company_number(number)

        Ash.Changeset.force_change_attribute(
          changeset,
          :company_registration_number,
          cleaned
        )
    end
  end
end
