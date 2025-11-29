defmodule EhsEnforcement.Scraping.Agencies.Sepa do
  @moduledoc """
  SEPA-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Scottish Environment
  Protection Agency (SEPA) scraping operations.

  ## SEPA-Specific Characteristics

  - **Single page scraping**: All data is on one page (no pagination)
  - **Section filtering**: Can filter by penalties, undertakings, or costs_recovery
  - **Year filtering**: Can filter by specific year
  - **Civil penalties only**: FMP, VMP, Undertakings (not court cases)

  ## Data Types

  - Fixed Monetary Penalties (FMP): £300, £600, £1,000
  - Variable Monetary Penalties (VMP): Discretionary amounts
  - Enforcement Undertakings: Voluntary compliance agreements
  - Costs Recovery Notices: Recovery of enforcement costs
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ProcessingLog
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyProcessor
  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper

  @impl true
  def validate_params(opts) do
    Logger.debug("SEPA: Validating parameters: #{inspect(opts)}")

    # SEPA-specific parameters
    section = Keyword.get(opts, :section, :all)
    year = Keyword.get(opts, :year)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)

    # Validate section parameter
    valid_sections = [:all, :penalties, :undertakings, :costs_recovery]

    if section not in valid_sections do
      {:error, "Invalid section: #{section}. Must be one of: #{inspect(valid_sections)}"}
    else
      validated_params = %{
        section: section,
        year: year,
        actor: actor,
        scrape_type: scrape_type
      }

      Logger.debug("SEPA: Parameters validated successfully")
      {:ok, validated_params}
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("SEPA: Starting scraping session",
      section: validated_params.section,
      year: validated_params.year
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    # SEPA uses a single page, so we set max_pages to 1
    ash_session_params = %{
      session_id: session_id,
      agency: :sepa,
      start_page: 1,
      max_pages: 1,
      database: section_to_database(validated_params.section),
      status: :running,
      current_page: 1,
      pages_processed: 0,
      cases_found: 0,
      cases_processed: 0,
      cases_created: 0,
      cases_exist_total: 0,
      errors_count: 0
    }

    case Ash.create(ScrapeSession, ash_session_params) do
      {:ok, session} ->
        Logger.metadata(session_id: session.session_id, agency: :sepa)
        Logger.info("SEPA: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the SEPA scraping workflow
        execute_sepa_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("SEPA: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create SEPA scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("SEPA: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Private functions for SEPA-specific implementation

  defp section_to_database(:all), do: "all"
  defp section_to_database(:penalties), do: "penalties"
  defp section_to_database(:undertakings), do: "undertakings"
  defp section_to_database(:costs_recovery), do: "costs_recovery"

  defp execute_sepa_scraping_session(session) do
    Logger.info("SEPA: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})

    # Scrape SEPA data
    scrape_opts = [
      section: validated_params.section,
      year: validated_params.year
    ]

    case SepaPenaltyScraper.scrape_all(scrape_opts) do
      {:ok, scraped_penalties} ->
        Logger.info("SEPA: Scraped #{length(scraped_penalties)} penalties")

        # Update session with found count
        session = update_session(session, %{cases_found: length(scraped_penalties)})

        # Process and create notices
        process_penalties_serially(session, scraped_penalties)
        |> finalize_session()

      {:error, reason} ->
        Logger.error("SEPA: Scraping failed: #{inspect(reason)}")

        session
        |> update_session(%{status: :failed, errors_count: session.errors_count + 1})
        |> finalize_session()
    end
  end

  defp process_penalties_serially(session, penalties) do
    Logger.info("SEPA: Processing #{length(penalties)} penalties serially")

    validated_params = Map.get(session, :validated_params, %{})
    actor = Map.get(validated_params, :actor)

    # Track results
    initial_state = {
      session,
      %{
        created: 0,
        existing: 0,
        errors: 0,
        processed_items: []
      }
    }

    {final_session, results} =
      Enum.reduce(penalties, initial_state, fn penalty, {current_session, acc} ->
        case SepaPenaltyProcessor.process_and_create_penalty(penalty, actor) do
          {:ok, notice} ->
            Logger.info("SEPA: Created notice: #{notice.regulator_id}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_created: current_session.cases_created + 1
              })

            updated_acc = %{
              acc
              | created: acc.created + 1,
                processed_items: [penalty | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            if duplicate_error?(errors) do
              Logger.info("SEPA: Penalty already exists: #{penalty.name_and_address}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  cases_exist_total: current_session.cases_exist_total + 1
                })

              updated_acc = %{
                acc
                | existing: acc.existing + 1,
                  processed_items: [penalty | acc.processed_items]
              }

              {updated_session, updated_acc}
            else
              Logger.warning("SEPA: Error creating penalty: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("SEPA: Error processing penalty: #{inspect(reason)}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                errors_count: current_session.errors_count + 1
              })

            updated_acc = %{acc | errors: acc.errors + 1}

            {updated_session, updated_acc}
        end
      end)

    # Create processing log
    create_processing_log(final_session, results)

    # Update pages_processed (SEPA is single-page)
    update_session(final_session, %{pages_processed: 1})
  end

  defp update_session(session, params) do
    validated_params = Map.get(session, :validated_params)

    case Ash.update(session, params) do
      {:ok, updated_session} ->
        if validated_params do
          Map.put(updated_session, :validated_params, validated_params)
        else
          updated_session
        end

      {:error, reason} ->
        Logger.error("SEPA: Failed to update session: #{inspect(reason)}")
        session
    end
  end

  defp finalize_session(session) do
    final_status =
      cond do
        session.status == :failed -> :failed
        session.errors_count > 0 and session.cases_created == 0 -> :failed
        true -> :completed
      end

    case Ash.update(session, %{status: final_status}) do
      {:ok, final_session} ->
        Logger.info("SEPA: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("SEPA: Failed to finalize session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp duplicate_error?(errors) when is_list(errors) do
    Enum.any?(errors, fn error ->
      case error do
        %{message: message} when is_binary(message) ->
          String.contains?(message, "already exists") or
            String.contains?(message, "has already been taken")

        _ ->
          false
      end
    end)
  end

  defp duplicate_error?(_), do: false

  defp create_processing_log(session, results) do
    # Create summary for UI display
    item_summary =
      results.processed_items
      |> Enum.take(50)
      |> Enum.map(fn penalty ->
        %{
          name: penalty.name_and_address,
          date: penalty.date,
          type: penalty.penalty_type,
          amount:
            if(penalty.penalty_amount, do: Decimal.to_string(penalty.penalty_amount), else: nil)
        }
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :sepa,
      batch_or_page: 1,
      items_found: length(results.processed_items),
      items_created: results.created,
      items_existing: results.existing,
      items_failed: results.errors,
      creation_errors: [],
      scraped_items: item_summary
    }

    case Ash.create(ProcessingLog, log_params) do
      {:ok, _log} ->
        Logger.debug("SEPA: Created processing log")

      {:error, reason} ->
        Logger.warning("SEPA: Failed to create processing log: #{inspect(reason)}")
    end
  end
end
