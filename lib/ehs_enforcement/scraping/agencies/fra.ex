defmodule EhsEnforcement.Scraping.Agencies.Fra do
  @moduledoc """
  FRA-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Fire and Rescue
  Authorities (FRA) scraping operations via the NFCC enforcement register.

  ## FRA-Specific Characteristics

  - **Single data source**: NFCC aggregates all 47 FRAs into one register
  - **API-based scraping**: Uses wpDataTables AJAX API with pagination
  - **Notice types**: Prohibition, Enforcement, Alterations (RRO 2005)
  - **Coverage**: England and Wales (47 Fire & Rescue Authorities)

  ## Data Types

  - Prohibition Notices - prohibit use until fire safety resolved
  - Enforcement Notices - require improvements within timeframe
  - Alterations Notices - require notification before changes

  ## Legal Basis

  Regulatory Reform (Fire Safety) Order 2005, Articles 29-31
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ProcessingLog
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Fra.FraNoticeProcessor
  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper

  @default_page_size 100

  @impl true
  def validate_params(opts) do
    Logger.debug("FRA: Validating parameters: #{inspect(opts)}")

    # FRA-specific parameters
    notice_type = Keyword.get(opts, :notice_type)
    frs = Keyword.get(opts, :frs)
    status = Keyword.get(opts, :status)
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    max_pages = Keyword.get(opts, :max_pages)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)

    # Validate notice_type parameter
    valid_notice_types = [nil, "PROHIBITION", "ENFORCEMENT", "ALTERATIONS"]

    if notice_type not in valid_notice_types do
      {:error,
       "Invalid notice_type: #{notice_type}. Must be one of: #{inspect(valid_notice_types)}"}
    else
      validated_params = %{
        notice_type: notice_type,
        frs: frs,
        status: status,
        page_size: page_size,
        max_pages: max_pages,
        actor: actor,
        scrape_type: scrape_type
      }

      Logger.debug("FRA: Parameters validated successfully")
      {:ok, validated_params}
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("FRA: Starting scraping session",
      notice_type: validated_params.notice_type,
      frs: validated_params.frs,
      status: validated_params.status
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    # Estimate pages based on total records (~7700) / page_size
    estimated_pages = ceil(7700 / validated_params.page_size)

    max_pages =
      if validated_params.max_pages,
        do: min(validated_params.max_pages, estimated_pages),
        else: estimated_pages

    ash_session_params = %{
      session_id: session_id,
      agency: :fra,
      start_page: 1,
      max_pages: max_pages,
      database: notice_type_to_database(validated_params.notice_type),
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
        Logger.metadata(session_id: session.session_id, agency: :fra)
        Logger.info("FRA: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the FRA scraping workflow
        execute_fra_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("FRA: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create FRA scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("FRA: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Private functions for FRA-specific implementation

  defp notice_type_to_database(nil), do: "all"
  defp notice_type_to_database("PROHIBITION"), do: "prohibition"
  defp notice_type_to_database("ENFORCEMENT"), do: "enforcement"
  defp notice_type_to_database("ALTERATIONS"), do: "alterations"

  defp execute_fra_scraping_session(session) do
    Logger.info("FRA: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})

    # Scrape FRA data
    scrape_opts = [
      notice_type: validated_params.notice_type,
      frs: validated_params.frs,
      status: validated_params.status,
      page_size: validated_params.page_size,
      max_pages: validated_params.max_pages
    ]

    case FraNoticeScraper.scrape_all(scrape_opts) do
      {:ok, scraped_notices} ->
        Logger.info("FRA: Scraped #{length(scraped_notices)} notices")

        # Update session with found count
        session = update_session(session, %{cases_found: length(scraped_notices)})

        # Process and create notices
        process_notices_serially(session, scraped_notices)
        |> finalize_session()

      {:error, reason} ->
        Logger.error("FRA: Scraping failed: #{inspect(reason)}")

        session
        |> update_session(%{status: :failed, errors_count: session.errors_count + 1})
        |> finalize_session()
    end
  end

  defp process_notices_serially(session, notices) do
    Logger.info("FRA: Processing #{length(notices)} notices serially")

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
      Enum.reduce(notices, initial_state, fn notice, {current_session, acc} ->
        case FraNoticeProcessor.process_and_create_notice(notice, actor) do
          {:ok, created_notice} ->
            Logger.debug("FRA: Created notice: #{created_notice.regulator_id}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_created: current_session.cases_created + 1
              })

            updated_acc = %{
              acc
              | created: acc.created + 1,
                processed_items: [notice | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            if duplicate_error?(errors) do
              Logger.debug("FRA: Notice already exists: #{notice.uprn}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  cases_exist_total: current_session.cases_exist_total + 1
                })

              updated_acc = %{
                acc
                | existing: acc.existing + 1,
                  processed_items: [notice | acc.processed_items]
              }

              {updated_session, updated_acc}
            else
              Logger.warning("FRA: Error creating notice: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("FRA: Error processing notice: #{inspect(reason)}")

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

    # Calculate pages processed based on page_size
    page_size = Map.get(validated_params, :page_size, @default_page_size)
    pages_processed = ceil(length(notices) / page_size)

    update_session(final_session, %{pages_processed: pages_processed})
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
        Logger.error("FRA: Failed to update session: #{inspect(reason)}")
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
        Logger.info("FRA: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("FRA: Failed to finalize session: #{inspect(reason)}")
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
      |> Enum.map(fn notice ->
        %{
          name: notice.responsible_person,
          address: notice.address,
          date: notice.issue_date,
          type: notice.notice_type,
          status: notice.status,
          uprn: notice.uprn
        }
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :fra,
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
        Logger.debug("FRA: Created processing log")

      {:error, reason} ->
        Logger.warning("FRA: Failed to create processing log: #{inspect(reason)}")
    end
  end
end
