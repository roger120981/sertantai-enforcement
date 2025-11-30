defmodule EhsEnforcement.Scraping.Agencies.Mca do
  @moduledoc """
  MCA-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Maritime and Coastguard
  Agency (MCA) prosecution scraping operations from GOV.UK.

  ## MCA-Specific Characteristics

  - **Data source**: GOV.UK prosecution reports (HTML for 2020+, PDF for older)
  - **Data type**: Prosecutions (court cases), not notices
  - **Coverage**: UK maritime waters
  - **Volume**: ~5-10 prosecutions per year

  ## Legislation

  Creates Offence records linking Cases to Legislation for each citation:
  - Merchant Shipping Act 1995
  - Merchant Shipping (ISM Code) Regulations 2014
  - Fishing Vessels (Codes of Practice) Regulations 2017
  - And other maritime legislation

  ## Legal Basis

  Merchant Shipping Act 1995 and related regulations
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ProcessingLog
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Mca.McaProsecutionProcessor
  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper

  @impl true
  def validate_params(opts) do
    Logger.debug("MCA: Validating parameters: #{inspect(opts)}")

    # MCA-specific parameters
    years = Keyword.get(opts, :years, McaProsecutionScraper.available_html_years())
    include_pdf = Keyword.get(opts, :include_pdf_years, false)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)

    # Validate years are valid
    valid_html_years = McaProsecutionScraper.available_html_years()
    invalid_years = Enum.filter(years, &(&1 not in valid_html_years and &1 not in 2010..2019))

    if length(invalid_years) > 0 do
      {:error,
       "Invalid years: #{inspect(invalid_years)}. Valid HTML years: #{inspect(valid_html_years)}"}
    else
      validated_params = %{
        years: years,
        include_pdf_years: include_pdf,
        actor: actor,
        scrape_type: scrape_type
      }

      Logger.debug("MCA: Parameters validated successfully")
      {:ok, validated_params}
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("MCA: Starting scraping session",
      years: validated_params.years,
      include_pdf: validated_params.include_pdf_years
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    # Estimate max_pages based on years (each year is roughly 1 "page")
    max_pages = length(validated_params.years)

    ash_session_params = %{
      session_id: session_id,
      agency: :mca,
      start_page: 1,
      max_pages: max_pages,
      database: "prosecutions",
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
        Logger.metadata(session_id: session.session_id, agency: :mca)
        Logger.info("MCA: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the MCA scraping workflow
        execute_mca_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("MCA: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create MCA scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("MCA: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Private functions for MCA-specific implementation

  defp execute_mca_scraping_session(session) do
    Logger.info("MCA: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})

    # Scrape MCA data
    scrape_opts = [
      years: validated_params.years,
      include_pdf_years: validated_params.include_pdf_years
    ]

    case McaProsecutionScraper.scrape_all(scrape_opts) do
      {:ok, scraped_prosecutions} ->
        Logger.info("MCA: Scraped #{length(scraped_prosecutions)} prosecutions")

        # Update session with found count
        session = update_session(session, %{cases_found: length(scraped_prosecutions)})

        # Process and create prosecutions
        process_prosecutions_serially(session, scraped_prosecutions)
        |> finalize_session()

      {:ok, scraped_prosecutions, errors: year_errors} ->
        Logger.warning(
          "MCA: Scraped #{length(scraped_prosecutions)} with year errors: #{inspect(year_errors)}"
        )

        # Update session with found count
        session =
          update_session(session, %{
            cases_found: length(scraped_prosecutions),
            errors_count: length(year_errors)
          })

        # Process and create prosecutions
        process_prosecutions_serially(session, scraped_prosecutions)
        |> finalize_session()
    end
  end

  defp process_prosecutions_serially(session, prosecutions) do
    Logger.info("MCA: Processing #{length(prosecutions)} prosecutions serially")

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
      Enum.reduce(prosecutions, initial_state, fn prosecution, {current_session, acc} ->
        case McaProsecutionProcessor.process_and_create_prosecution(prosecution, actor) do
          {:ok, created_case} ->
            Logger.debug("MCA: Created case: #{created_case.regulator_id}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_created: current_session.cases_created + 1
              })

            updated_acc = %{
              acc
              | created: acc.created + 1,
                processed_items: [prosecution | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            if duplicate_error?(errors) do
              Logger.debug("MCA: Case already exists: #{prosecution.defendant}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  cases_exist_total: current_session.cases_exist_total + 1
                })

              updated_acc = %{
                acc
                | existing: acc.existing + 1,
                  processed_items: [prosecution | acc.processed_items]
              }

              {updated_session, updated_acc}
            else
              Logger.warning("MCA: Error creating case: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("MCA: Error processing prosecution: #{inspect(reason)}")

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

    # Calculate pages processed (1 page = 1 year)
    years_processed =
      results.processed_items
      |> Enum.map(& &1.year)
      |> Enum.uniq()
      |> length()

    update_session(final_session, %{pages_processed: years_processed})
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
        Logger.error("MCA: Failed to update session: #{inspect(reason)}")
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
        Logger.info("MCA: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("MCA: Failed to finalize session: #{inspect(reason)}")
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
      |> Enum.map(fn prosecution ->
        %{
          defendant: prosecution.defendant,
          year: prosecution.year,
          hearing_date: prosecution.hearing_date,
          court: prosecution.court,
          fine: prosecution.fine,
          case_title: prosecution.case_title
        }
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :mca,
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
        Logger.debug("MCA: Created processing log")

      {:error, reason} ->
        Logger.warning("MCA: Failed to create processing log: #{inspect(reason)}")
    end
  end
end
