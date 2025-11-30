defmodule EhsEnforcement.Enforcement.Case do
  @moduledoc """
  Represents an enforcement case (court case) against an offender.
  """

  use Ash.Resource,
    domain: EhsEnforcement.Enforcement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban, AshEvents.Events],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("cases")
    repo(EhsEnforcement.Repo)

    identity_wheres_to_sql(unique_case_reference: "case_reference IS NOT NULL")

    # R4.1: Data validation constraints
    check_constraints do
      check_constraint(:offence_fine_non_negative, "offence_fine IS NULL OR offence_fine >= 0",
        message: "Fine amount must be non-negative"
      )

      check_constraint(:offence_costs_non_negative, "offence_costs IS NULL OR offence_costs >= 0",
        message: "Costs amount must be non-negative"
      )

      check_constraint(
        :dates_logical_order,
        "offence_hearing_date IS NULL OR offence_action_date IS NULL OR offence_hearing_date >= offence_action_date",
        message: "Hearing date must be on or after action date"
      )
    end

    custom_indexes do
      # Performance indexes for dashboard metrics calculations
      index([:offence_action_date], name: "cases_offence_action_date_index")
      index([:agency_id], name: "cases_agency_id_index")

      # Composite index for common query patterns (agency + date filtering)
      index([:agency_id, :offence_action_date], name: "cases_agency_date_index")

      # Fine amount filtering index for range queries
      index([:offence_fine], name: "cases_offence_fine_index")

      # Text search indexes for regulator_id
      index([:regulator_id], name: "cases_regulator_id_index")

      # pg_trgm GIN indexes for fuzzy text search
      index([:regulator_id], name: "cases_regulator_id_gin_trgm", using: "GIN")
    end

    custom_statements do
      # Enable pg_trgm extension for fuzzy text search
      statement :enable_pg_trgm do
        up("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        down("DROP EXTENSION IF EXISTS pg_trgm")
      end
    end
  end

  pub_sub do
    # Use our PubSub module, not the Endpoint
    module(EhsEnforcement.PubSub)
    prefix("case")

    # Broadcast when a case is created
    # Topics: "case:created" and "case:created:<id>"
    publish(:create, ["created", :id])
    publish(:create, ["created"])

    # Broadcast when a case is updated
    # Topics: "case:updated" and "case:updated:<id>"
    publish(:update, ["updated", :id])
    publish(:update, ["updated"])

    # Broadcast when a case is updated from scraping (HSE website → Postgres)
    # Topics: "case:scraped:updated" and "case:scraped:updated:<id>"
    publish(:update_from_scraping, ["scraped:updated", :id])
    publish(:update_from_scraping, ["scraped:updated"])

    # Broadcast when a case is synced from Airtable (Airtable → Postgres)
    # Topics: "case:synced" and "case:synced:<id>"
    publish(:sync_from_airtable, ["synced", :id])
    publish(:sync_from_airtable, ["synced"])

    # Broadcast when a case is destroyed
    # Topics: "case:deleted" and "case:deleted:<id>"
    publish(:destroy, ["deleted", :id])

    # Broadcast when cases are bulk created
    # Topic: "case:bulk_created"
    publish(:bulk_create, ["bulk_created"])
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:case_reference, :string,
      description: "Agency's case reference number (e.g., EA 'Case Reference' field)"
    )

    attribute(:regulator_id, :string,
      description: "Unique ID from agency system (EA: ea_record_id, HSE: regulator case ID)"
    )

    attribute(:offence_result, :string)
    attribute(:offence_fine, :decimal)
    attribute(:offence_costs, :decimal)
    attribute(:offence_action_date, :date)
    attribute(:offence_hearing_date, :date)
    attribute(:regulator_function, :string)
    attribute(:regulator_url, :string)
    attribute(:related_cases, :string)
    attribute(:offence_action_type, :string)
    attribute(:url, :string)

    attribute(:offence_breaches, :string,
      description: "Description of regulation breaches/violations"
    )

    attribute(:last_synced_at, :utc_datetime)

    # EA-specific extensions for Environment Agency enforcement data
    attribute(:ea_event_reference, :string, description: "EA event ID (e.g., '205107')")
    attribute(:ea_total_violation_count, :integer, description: "Number of violations in EA case")

    attribute(:environmental_impact, :string,
      description: "Environmental impact level: 'none', 'minor', 'major'"
    )

    attribute(:environmental_receptor, :string,
      description: "Environmental receptor affected: 'land', 'water', 'air'"
    )

    attribute(:is_ea_multi_violation, :boolean,
      default: false,
      description: "True if EA case has multiple distinct violations"
    )

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
        WHERE o.case_id = ?),
        '')",
                  id
                )
              ) do
      description "Computed summary of all offences/breaches linked to this case"
    end
  end

  relationships do
    belongs_to :agency, EhsEnforcement.Enforcement.Agency do
      allow_nil?(false)
    end

    belongs_to :offender, EhsEnforcement.Enforcement.Offender do
      allow_nil?(false)
    end

    # Unified relationship (consolidated schema)
    has_many :offences, EhsEnforcement.Enforcement.Offence
  end

  identities do
    identity(:unique_case_reference, [:case_reference], where: expr(not is_nil(case_reference)))
    identity(:unique_case_per_agency, [:agency_id, :regulator_id])
  end

  events do
    # Reference the centralized event log resource
    event_log(EhsEnforcement.Events.Event)

    # Track current action versions for schema evolution during replay
    current_action_versions(
      create: 1,
      update_from_scraping: 1,
      sync_from_airtable: 1,
      bulk_create: 1
    )

    # Only track core data operations (exclude scraping orchestration and read actions)
    only_actions([:create, :update_from_scraping, :sync_from_airtable, :bulk_create])
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)

      accept([
        :case_reference,
        :regulator_id,
        :offence_result,
        :offence_fine,
        :offence_costs,
        :offence_action_date,
        :offence_hearing_date,
        :regulator_function,
        :regulator_url,
        :related_cases,
        :offence_action_type,
        :url,
        :offence_breaches,
        :last_synced_at,
        # EA-specific fields
        :ea_event_reference,
        :ea_total_violation_count,
        :environmental_impact,
        :environmental_receptor,
        :is_ea_multi_violation
      ])

      argument(:agency_code, :atom)
      argument(:offender_attrs, :map)
      argument(:agency_id, :uuid)
      argument(:offender_id, :uuid)

      validate(present([:regulator_id]))

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
                          # Log error but don't fail case creation
                          require Logger

                          Logger.error(
                            "Failed to create review record for offender #{offender.id}: #{inspect(review_error)}"
                          )
                      end
                    end

                    changeset
                    |> Ash.Changeset.force_change_attribute(:agency_id, agency.id)
                    |> Ash.Changeset.force_change_attribute(:offender_id, offender.id)

                  {:error, error} ->
                    # Preserve the actual error details for debugging
                    error_msg =
                      case error do
                        %Ash.Error.Invalid{errors: errors} when is_list(errors) ->
                          error_details =
                            Enum.map_join(errors, ", ", fn err ->
                              "#{err.field || "unknown"}: #{err.message || inspect(err)}"
                            end)

                          "Failed to create offender: #{error_details}"

                        %{message: msg} when is_binary(msg) ->
                          "Failed to create offender: #{msg}"

                        _ ->
                          "Failed to create offender: #{inspect(error)}"
                      end

                    Ash.Changeset.add_error(changeset, error_msg)
                end

              {:ok, nil} ->
                Ash.Changeset.add_error(changeset, "Agency not found: #{agency_code}")

              {:error, _} ->
                Ash.Changeset.add_error(changeset, "Failed to lookup agency: #{agency_code}")
            end

          true ->
            Ash.Changeset.add_error(changeset,
              field: :agency_id,
              message:
                "Either agency_id + offender_id OR agency_code + offender_attrs must be provided"
            )
        end
      end)

      # Automatically update offender's agencies array when case is created
      change(
        after_action(fn changeset, case_record, _context ->
          update_offender_agencies(case_record.offender_id)
          {:ok, case_record}
        end)
      )
    end

    update :update_from_scraping do
      accept([
        :offence_result,
        :offence_fine,
        :offence_costs,
        :offence_hearing_date,
        :url,
        :related_cases
      ])

      # No last_synced_at change - this is scraping, not Airtable syncing
    end

    @doc """
    Synchronize a case with data from Airtable (for bulk migration).

    This action is specifically for Airtable → Postgres synchronization during
    the initial 30K record migration. It sets `last_synced_at` to track sync status.

    ## PubSub Events

    When this action succeeds, it publishes to:
    - `case:synced` - General sync event (all synced cases)
    - `case:synced:<case_id>` - Specific case sync event

    ## Usage

        # During Airtable migration
        {:ok, synced_case} = Ash.update(case, airtable_data, action: :sync_from_airtable, actor: actor)
    """
    update :sync_from_airtable do
      accept([
        :offence_result,
        :offence_fine,
        :offence_costs,
        :offence_hearing_date,
        :url,
        :related_cases
      ])

      change(set_attribute(:last_synced_at, &DateTime.utc_now/0))
    end

    read :by_date_range do
      argument(:from_date, :date, allow_nil?: false)
      argument(:to_date, :date, allow_nil?: false)

      filter(
        expr(
          offence_action_date >= ^arg(:from_date) and
            offence_action_date <= ^arg(:to_date)
        )
      )
    end

    create :scrape_hse_cases do
      description("Scheduled scraping of HSE cases - standard daily scrape")

      argument(:max_pages, :integer, default: 20)
      argument(:start_page, :integer, default: 1)
      argument(:database, :string, default: "cases")

      change(fn changeset, context ->
        max_pages = Ash.Changeset.get_argument(changeset, :max_pages)
        start_page = Ash.Changeset.get_argument(changeset, :start_page)
        database = Ash.Changeset.get_argument(changeset, :database)

        session_opts = %{
          max_pages: max_pages,
          start_page: start_page,
          database: database
        }

        case EhsEnforcement.Scraping.ScrapeCoordinator.start_scraping_session(session_opts) do
          {:ok, session_result} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_result,
              message:
                "Scraping completed: #{session_result.cases_created} cases created, #{session_result.cases_updated} updated"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_error,
              message: "Scraping failed: #{inspect(error)}"
            )
        end
      end)
    end

    create :scrape_hse_cases_deep do
      description("Deep scheduled scraping of HSE cases - weekly comprehensive scrape")

      argument(:max_pages, :integer, default: 100)
      argument(:start_page, :integer, default: 1)
      argument(:database, :string, default: "cases")

      change(fn changeset, context ->
        max_pages = Ash.Changeset.get_argument(changeset, :max_pages)
        start_page = Ash.Changeset.get_argument(changeset, :start_page)
        database = Ash.Changeset.get_argument(changeset, :database)

        session_opts = %{
          max_pages: max_pages,
          start_page: start_page,
          database: database
        }

        case EhsEnforcement.Scraping.ScrapeCoordinator.start_scraping_session(session_opts) do
          {:ok, session_result} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_result,
              message:
                "Deep scraping completed: #{session_result.cases_created} cases created, #{session_result.cases_updated} updated"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_error,
              message: "Deep scraping failed: #{inspect(error)}"
            )
        end
      end)
    end

    create :handle_scrape_error do
      description("Handle errors from scheduled scraping jobs")

      argument(:error_details, :map)
      argument(:job_name, :string)
      argument(:attempt_number, :integer)

      change(fn changeset, context ->
        error_details = Ash.Changeset.get_argument(changeset, :error_details)
        job_name = Ash.Changeset.get_argument(changeset, :job_name)
        attempt_number = Ash.Changeset.get_argument(changeset, :attempt_number)

        # Log the error for monitoring
        require Logger

        Logger.error("Scheduled scraping job failed", %{
          job_name: job_name,
          attempt: attempt_number,
          error_details: error_details
        })

        # For now, just record the error - could extend to send notifications
        Ash.Changeset.add_error(changeset,
          field: :job_error,
          message:
            "Job #{job_name} failed on attempt #{attempt_number}: #{inspect(error_details)}"
        )
      end)
    end

    create :scrape_ea_cases do
      description(
        "Scheduled scraping of EA cases - recent date range with conservative pagination"
      )

      argument(:date_from, :date, default: fn -> Date.add(Date.utc_today(), -30) end)
      argument(:date_to, :date, default: &Date.utc_today/0)
      argument(:action_types, {:array, :atom}, default: [:court_case])
      argument(:max_pages, :integer, default: 20)
      argument(:start_page, :integer, default: 1)

      change(fn changeset, context ->
        date_from = Ash.Changeset.get_argument(changeset, :date_from)
        date_to = Ash.Changeset.get_argument(changeset, :date_to)
        action_types = Ash.Changeset.get_argument(changeset, :action_types)
        max_pages = Ash.Changeset.get_argument(changeset, :max_pages)
        start_page = Ash.Changeset.get_argument(changeset, :start_page)

        session_opts = [
          agency: :ea,
          date_from: date_from,
          date_to: date_to,
          action_types: action_types,
          max_pages: max_pages,
          start_page: start_page,
          scrape_type: :scheduled
        ]

        case EhsEnforcement.Scraping.ScrapeCoordinator.start_scraping_session(session_opts) do
          {:ok, session_result} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_result,
              message:
                "EA scraping completed: #{session_result.cases_created} cases created, #{session_result.cases_updated} updated"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_error,
              message: "EA scraping failed: #{inspect(error)}"
            )
        end
      end)
    end

    create :scrape_ea_cases_historical do
      description("Manual EA historical scraping - user controls dates, pages, and action types")

      argument(:date_from, :date, allow_nil?: false)
      argument(:date_to, :date, allow_nil?: false)
      argument(:start_page, :integer, allow_nil?: false)
      argument(:max_pages, :integer, allow_nil?: false)

      argument(:action_types, {:array, :atom},
        default: [:court_case, :caution, :enforcement_notice]
      )

      change(fn changeset, context ->
        date_from = Ash.Changeset.get_argument(changeset, :date_from)
        date_to = Ash.Changeset.get_argument(changeset, :date_to)
        start_page = Ash.Changeset.get_argument(changeset, :start_page)
        max_pages = Ash.Changeset.get_argument(changeset, :max_pages)
        action_types = Ash.Changeset.get_argument(changeset, :action_types)

        session_opts = [
          agency: :ea,
          date_from: date_from,
          date_to: date_to,
          start_page: start_page,
          max_pages: max_pages,
          action_types: action_types,
          scrape_type: :manual
        ]

        case EhsEnforcement.Scraping.ScrapeCoordinator.start_scraping_session(session_opts) do
          {:ok, session_result} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_result,
              message:
                "EA historical scraping completed: #{session_result.cases_created} cases created, #{session_result.cases_updated} updated"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_error,
              message: "EA historical scraping failed: #{inspect(error)}"
            )
        end
      end)
    end

    create :handle_scrape_error_ea do
      description("Handle errors from scheduled EA scraping jobs")

      argument(:error_details, :map)
      argument(:job_name, :string)
      argument(:attempt_number, :integer)
      argument(:date_from, :date)
      argument(:date_to, :date)

      change(fn changeset, context ->
        error_details = Ash.Changeset.get_argument(changeset, :error_details)
        job_name = Ash.Changeset.get_argument(changeset, :job_name)
        attempt_number = Ash.Changeset.get_argument(changeset, :attempt_number)
        date_from = Ash.Changeset.get_argument(changeset, :date_from)
        date_to = Ash.Changeset.get_argument(changeset, :date_to)

        # Log the error for monitoring
        require Logger

        Logger.error("Scheduled EA scraping job failed", %{
          job_name: job_name,
          attempt: attempt_number,
          date_range: "#{date_from} to #{date_to}",
          error_details: error_details
        })

        # For now, just record the error - could extend to send notifications
        Ash.Changeset.add_error(changeset,
          field: :job_error,
          message:
            "EA job #{job_name} failed on attempt #{attempt_number} for date range #{date_from} to #{date_to}: #{inspect(error_details)}"
        )
      end)
    end

    # ============================================================================
    # NRW Scraping Actions
    # ============================================================================

    create :scrape_nrw_cases do
      description("Scheduled scraping of NRW cases - weekly scrape of news articles")

      argument(:limit, :integer, default: 20)

      change(fn changeset, _context ->
        limit = Ash.Changeset.get_argument(changeset, :limit)

        # Generate a session ID for this scrape
        session_id = Ecto.UUID.generate()

        # Call the NRW coordinator directly
        case EhsEnforcement.Scraping.Api.NrwCoordinator.scrape_batch(session_id, limit, nil) do
          {:ok, result} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_result,
              message:
                "NRW scraping completed: #{result.created} cases created, #{result.updated} updated"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :scraping_error,
              message: "NRW scraping failed: #{inspect(error)}"
            )
        end
      end)
    end

    create :handle_scrape_error_nrw do
      description("Handle errors from scheduled NRW scraping jobs")

      argument(:error_details, :map)
      argument(:job_name, :string)
      argument(:attempt_number, :integer)
      argument(:limit, :integer)

      change(fn changeset, _context ->
        error_details = Ash.Changeset.get_argument(changeset, :error_details)
        job_name = Ash.Changeset.get_argument(changeset, :job_name)
        attempt_number = Ash.Changeset.get_argument(changeset, :attempt_number)
        limit = Ash.Changeset.get_argument(changeset, :limit)

        # Log the error for monitoring
        require Logger

        Logger.error("Scheduled NRW scraping job failed", %{
          job_name: job_name,
          attempt: attempt_number,
          limit: limit,
          error_details: error_details
        })

        # For now, just record the error - could extend to send notifications
        Ash.Changeset.add_error(changeset,
          field: :job_error,
          message:
            "NRW job #{job_name} failed on attempt #{attempt_number} with limit #{limit}: #{inspect(error_details)}"
        )
      end)
    end

    read :duplicate_detection do
      description("Efficient duplicate checking by regulator_id for scraping operations")

      argument(:regulator_ids, {:array, :string}, allow_nil?: false)

      filter(expr(regulator_id in ^arg(:regulator_ids)))

      prepare(fn query, _context ->
        Ash.Query.select(query, [:id, :regulator_id])
      end)
    end

    create :bulk_create do
      description("Batch processing for creating multiple cases efficiently")

      argument(:cases_data, {:array, :map}, allow_nil?: false)
      argument(:batch_size, :integer, default: 50)

      change(fn changeset, context ->
        cases_data = Ash.Changeset.get_argument(changeset, :cases_data)
        batch_size = Ash.Changeset.get_argument(changeset, :batch_size)

        # Extract regulator_ids for duplicate detection
        regulator_ids = Enum.map(cases_data, & &1[:regulator_id])

        # Check for existing cases to prevent duplicates
        case Ash.read(__MODULE__, action: :duplicate_detection, regulator_ids: regulator_ids) do
          {:ok, existing_cases} ->
            existing_ids = MapSet.new(existing_cases, & &1.regulator_id)

            new_cases_data =
              Enum.reject(cases_data, fn case_data ->
                MapSet.member?(existing_ids, case_data[:regulator_id])
              end)

            skipped_count = length(cases_data) - length(new_cases_data)

            # Process only new cases in batches
            batches = Enum.chunk_every(new_cases_data, batch_size)

            results = %{
              created: 0,
              errors: [],
              skipped: skipped_count
            }

            final_results =
              Enum.reduce(batches, results, fn batch, acc ->
                batch_results =
                  Enum.reduce(batch, acc, fn case_data, batch_acc ->
                    case Ash.create(__MODULE__, case_data, domain: EhsEnforcement.Enforcement) do
                      {:ok, _case} ->
                        %{batch_acc | created: batch_acc.created + 1}

                      {:error, error} ->
                        error_msg =
                          "Failed to create case with regulator_id #{case_data[:regulator_id]}: #{inspect(error)}"

                        %{batch_acc | errors: [error_msg | batch_acc.errors]}
                    end
                  end)

                # Brief pause between batches to prevent overwhelming the database
                :timer.sleep(100)
                batch_results
              end)

            success_msg =
              if final_results.created > 0 or final_results.skipped > 0 do
                parts = []

                if final_results.created > 0,
                  do: parts = ["#{final_results.created} created" | parts]

                if final_results.skipped > 0,
                  do: parts = ["#{final_results.skipped} skipped (duplicates)" | parts]

                "Bulk create completed: #{Enum.join(parts, ", ")}"
              else
                "No cases processed"
              end

            Ash.Changeset.add_error(changeset,
              field: :bulk_result,
              message: success_msg
            )

          {:error, _duplicate_check_error} ->
            Ash.Changeset.add_error(changeset,
              field: :bulk_error,
              message: "Bulk create failed: unable to check for duplicates"
            )
        end
      end)
    end
  end

  calculations do
    calculate :total_penalty, :decimal do
      calculation(expr((offence_fine || 0) + (offence_costs || 0)))
    end
  end

  oban do
    triggers do
      trigger :scheduled_scrape_hse do
        action(:scrape_hse_cases)

        # Daily at 2 AM
        scheduler_cron("0 2 * * *")
        max_attempts(3)
        queue(:scraping)
        on_error(:handle_scrape_error)
        worker_module_name(EhsEnforcement.Enforcement.Case.AshOban.Worker.ScheduledScrapeHse)

        scheduler_module_name(
          EhsEnforcement.Enforcement.Case.AshOban.Scheduler.ScheduledScrapeHse
        )
      end

      trigger :weekly_scrape_deep do
        action(:scrape_hse_cases_deep)

        # Weekly on Sunday at 3 AM
        scheduler_cron("0 3 * * 0")
        max_attempts(5)
        queue(:scraping)
        on_error(:handle_scrape_error)
        worker_module_name(EhsEnforcement.Enforcement.Case.AshOban.Worker.WeeklyScrapeDeep)
        scheduler_module_name(EhsEnforcement.Enforcement.Case.AshOban.Scheduler.WeeklyScrapeDeep)
      end

      trigger :scheduled_scrape_ea do
        action(:scrape_ea_cases)

        # Weekly on Monday at 4 AM (offset from HSE scraping)
        scheduler_cron("0 4 * * 1")
        max_attempts(3)
        queue(:scraping)
        on_error(:handle_scrape_error_ea)
        worker_module_name(EhsEnforcement.Enforcement.Case.AshOban.Worker.ScheduledScrapeEa)

        scheduler_module_name(EhsEnforcement.Enforcement.Case.AshOban.Scheduler.ScheduledScrapeEa)
      end

      trigger :weekly_scrape_nrw do
        action(:scrape_nrw_cases)

        # Weekly on Tuesday at 5 AM (offset from HSE/EA scraping)
        scheduler_cron("0 5 * * 2")
        max_attempts(3)
        queue(:scraping)
        on_error(:handle_scrape_error_nrw)
        worker_module_name(EhsEnforcement.Enforcement.Case.AshOban.Worker.WeeklyScrapeNrw)

        scheduler_module_name(EhsEnforcement.Enforcement.Case.AshOban.Scheduler.WeeklyScrapeNrw)
      end
    end
  end

  code_interface do
    define(:create)
    define(:update_from_scraping)
    define(:sync_from_airtable)
    define(:scrape_hse_cases)
    define(:scrape_hse_cases_deep)
    define(:scrape_ea_cases)
    define(:scrape_ea_cases_historical)
    define(:scrape_nrw_cases)
    define(:duplicate_detection)
    define(:bulk_create)
  end

  # Helper function to update offender agencies when cases are created/updated
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
