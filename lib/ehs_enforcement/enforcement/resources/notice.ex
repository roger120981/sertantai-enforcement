defmodule EhsEnforcement.Enforcement.Notice do
  @moduledoc """
  Represents an enforcement notice issued to an offender.
  """

  use Ash.Resource,
    domain: EhsEnforcement.Enforcement,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("notices")
    repo(EhsEnforcement.Repo)

    identity_wheres_to_sql(
      unique_regulator_per_agency: "regulator_id IS NOT NULL AND regulator_id != ''"
    )

    # R4.1: Data validation constraints
    check_constraints do
      check_constraint(
        :dates_logical_order,
        "compliance_date IS NULL OR notice_date IS NULL OR compliance_date >= notice_date",
        message: "Compliance date must be on or after notice date"
      )

      check_constraint(
        :operative_date_after_notice,
        "operative_date IS NULL OR notice_date IS NULL OR operative_date >= notice_date",
        message: "Operative date must be on or after notice date"
      )
    end

    custom_indexes do
      # Performance indexes for dashboard metrics calculations
      index([:offence_action_date], name: "notices_offence_action_date_index")
      index([:agency_id], name: "notices_agency_id_index")

      # Composite index for common query patterns (agency + date filtering)
      index([:agency_id, :offence_action_date], name: "notices_agency_date_index")

      # Text search indexes for regulator_id
      index([:regulator_id], name: "notices_regulator_id_index")

      # Action type filtering index
      index([:offence_action_type], name: "notices_offence_action_type_index")

      # pg_trgm GIN indexes for fuzzy text search
      index([:regulator_id], name: "notices_regulator_id_gin_trgm", using: "GIN")
      index([:notice_body], name: "notices_notice_body_gin_trgm", using: "GIN")
    end
  end

  pub_sub do
    # Use our PubSub module, not the Endpoint (match Cases pattern exactly)
    module(EhsEnforcement.PubSub)
    prefix("notice")

    # Broadcast when a notice is created
    # Topics: "notice:created" and "notice:created:<id>"
    publish(:create, ["created", :id])
    publish(:create, ["created"])

    # Broadcast when a notice is updated
    # Topics: "notice:updated" and "notice:updated:<id>"
    publish(:update, ["updated", :id])
    publish(:update, ["updated"])
    publish(:destroy, ["deleted", :id])
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:airtable_id, :string)
    attribute(:regulator_id, :string)
    attribute(:regulator_ref_number, :string)
    attribute(:notice_date, :date)
    attribute(:operative_date, :date)
    attribute(:compliance_date, :date)
    attribute(:notice_body, :string)
    attribute(:offence_action_type, :string)
    attribute(:offence_action_date, :date)
    attribute(:url, :string)

    attribute(:offence_breaches, :string,
      description: "Description of regulation breaches/violations"
    )

    attribute(:last_synced_at, :utc_datetime)

    # EA-specific fields for environmental enforcement notices
    attribute(:regulator_event_reference, :string)
    attribute(:environmental_impact, :string)
    attribute(:environmental_receptor, :string)
    attribute(:legal_act, :string)
    attribute(:legal_section, :string)
    attribute(:regulator_function, :string)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  calculations do
    calculate :computed_breaches_summary,
              :string,
              expr(
                fragment(
                  "COALESCE(
        (SELECT string_agg(
          CONCAT(l.legislation_title,
                 CASE WHEN o.legislation_part IS NOT NULL
                      THEN CONCAT(' / ', o.legislation_part)
                      ELSE '' END),
          '; ' ORDER BY o.sequence_number
        )
        FROM offences o
        JOIN legislation l ON l.id = o.legislation_id
        WHERE o.notice_id = ?),
        '')",
                  id
                )
              ) do
      description "Computed summary of all offences/breaches linked to this notice"
    end
  end

  relationships do
    belongs_to :agency, EhsEnforcement.Enforcement.Agency do
      allow_nil?(false)
    end

    belongs_to :offender, EhsEnforcement.Enforcement.Offender do
      allow_nil?(false)
    end

    # Unified relationship (new schema)
    has_many :offences, EhsEnforcement.Enforcement.Offence
  end

  identities do
    # Composite unique constraint: A notice is uniquely identified by (regulator_id, agency_id)
    # This prevents duplicate notices from being created during scraping
    # and ensures cross-agency IDs don't conflict (HSE uses 9-digit, EA uses 8-digit)
    # Only applies when regulator_id is not NULL and not empty string
    identity(
      :unique_regulator_per_agency,
      [:regulator_id, :agency_id],
      where: expr(not is_nil(regulator_id) and regulator_id != "")
    )
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :airtable_id,
        :regulator_id,
        :regulator_ref_number,
        :notice_date,
        :operative_date,
        :compliance_date,
        :notice_body,
        :offence_action_type,
        :offence_action_date,
        :url,
        :offence_breaches,
        :last_synced_at,
        :regulator_event_reference,
        :environmental_impact,
        :environmental_receptor,
        :legal_act,
        :legal_section,
        :regulator_function
      ])

      argument(:agency_code, :atom)
      argument(:offender_attrs, :map)
      argument(:agency_id, :uuid)
      argument(:offender_id, :uuid)

      change(fn changeset, context ->
        cond do
          # Direct IDs provided
          Ash.Changeset.get_argument(changeset, :agency_id) &&
              Ash.Changeset.get_argument(changeset, :offender_id) ->
            agency_id = Ash.Changeset.get_argument(changeset, :agency_id)
            offender_id = Ash.Changeset.get_argument(changeset, :offender_id)

            changeset
            |> Ash.Changeset.force_change_attribute(:agency_id, agency_id)
            |> Ash.Changeset.force_change_attribute(:offender_id, offender_id)

          # Code and attrs provided
          Ash.Changeset.get_argument(changeset, :agency_code) &&
              Ash.Changeset.get_argument(changeset, :offender_attrs) ->
            agency_code = Ash.Changeset.get_argument(changeset, :agency_code)
            offender_attrs = Ash.Changeset.get_argument(changeset, :offender_attrs)

            # Look up agency by code
            case EhsEnforcement.Enforcement.get_agency_by_code(agency_code) do
              {:ok, agency} when not is_nil(agency) ->
                # Find or create offender
                # Extract review candidates if present (from Companies House matching)
                {clean_offender_attrs, review_candidates} =
                  Map.pop(offender_attrs, :__review_candidates__)

                case EhsEnforcement.Enforcement.Offender.find_or_create_offender(
                       clean_offender_attrs || offender_attrs
                     ) do
                  {:ok, offender} ->
                    # If we have review candidates, create a review record
                    if review_candidates && is_list(review_candidates) do
                      case EhsEnforcement.Agencies.Hse.OffenderBuilder.create_medium_confidence_review(
                             offender,
                             review_candidates
                           ) do
                        {:ok, _review} ->
                          # Successfully created review record
                          :ok

                        {:error, review_error} ->
                          # Log error but don't fail notice creation
                          require Logger

                          Logger.error(
                            "Failed to create review record for offender #{offender.id}: #{inspect(review_error)}"
                          )
                      end
                    end

                    changeset
                    |> Ash.Changeset.force_change_attribute(:agency_id, agency.id)
                    |> Ash.Changeset.force_change_attribute(:offender_id, offender.id)

                  {:error, _} ->
                    Ash.Changeset.add_error(changeset, "Failed to create offender")
                end

              {:ok, nil} ->
                Ash.Changeset.add_error(changeset, "Agency not found: #{agency_code}")

              {:error, _} ->
                Ash.Changeset.add_error(changeset, "Error looking up agency: #{agency_code}")
            end

          true ->
            Ash.Changeset.add_error(
              changeset,
              "Must provide either agency_id/offender_id or agency_code/offender_attrs"
            )
        end
      end)

      # Automatically update offender's agencies array when notice is created
      change(
        after_action(fn changeset, notice_record, _context ->
          update_offender_agencies(notice_record.offender_id)
          {:ok, notice_record}
        end)
      )
    end

    update :update do
      primary?(true)

      accept([
        :airtable_id,
        :regulator_id,
        :regulator_ref_number,
        :notice_date,
        :operative_date,
        :compliance_date,
        :notice_body,
        :offence_action_type,
        :offence_action_date,
        :url,
        :offence_breaches,
        :last_synced_at,
        :regulator_event_reference,
        :environmental_impact,
        :environmental_receptor,
        :legal_act,
        :legal_section,
        :regulator_function
      ])
    end
  end

  code_interface do
    define(:create)
  end

  # Helper function to update offender agencies when notices are created/updated
  defp update_offender_agencies(offender_id) do
    spawn(fn ->
      try do
        # Get the offender
        case EhsEnforcement.Enforcement.get_offender(offender_id) do
          {:ok, offender} ->
            # Get all unique agencies from cases and notices for this offender
            agencies = get_unique_agencies_for_offender(offender_id)

            # Update the offender's agencies array
            case Ash.update(offender, %{agencies: agencies}) do
              {:ok, _updated_offender} ->
                require Logger

                Logger.info(
                  "Updated agencies for offender #{offender.name}: #{inspect(agencies)}"
                )

              {:error, error} ->
                require Logger

                Logger.warning(
                  "Failed to update agencies for offender #{offender_id}: #{inspect(error)}"
                )
            end

          {:error, error} ->
            require Logger
            Logger.warning("Failed to get offender #{offender_id}: #{inspect(error)}")
        end
      rescue
        error ->
          require Logger
          Logger.error("Error updating offender agencies: #{inspect(error)}")
      end
    end)
  end

  defp get_unique_agencies_for_offender(offender_id) do
    # Get agencies from cases
    case_agencies =
      case EhsEnforcement.Enforcement.list_cases() do
        {:ok, cases} ->
          cases
          |> Enum.filter(&(&1.offender_id == offender_id))
          |> Enum.map(fn case_record ->
            case Ash.load(case_record, :agency) do
              {:ok, loaded_case} ->
                if loaded_case.agency, do: loaded_case.agency.name, else: nil

              _ ->
                nil
            end
          end)
          |> Enum.filter(&(&1 != nil))

        _ ->
          []
      end

    # Get agencies from notices
    notice_agencies =
      case EhsEnforcement.Enforcement.list_notices() do
        {:ok, notices} ->
          notices
          |> Enum.filter(&(&1.offender_id == offender_id))
          |> Enum.map(fn notice ->
            case Ash.load(notice, :agency) do
              {:ok, loaded_notice} ->
                if loaded_notice.agency, do: loaded_notice.agency.name, else: nil

              _ ->
                nil
            end
          end)
          |> Enum.filter(&(&1 != nil))

        _ ->
          []
      end

    # Combine and deduplicate
    (case_agencies ++ notice_agencies)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
