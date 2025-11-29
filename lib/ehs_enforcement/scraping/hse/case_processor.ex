defmodule EhsEnforcement.Scraping.Hse.CaseProcessor do
  @moduledoc """
  HSE case processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from HSE format to Ash resource format
  - Integration with existing Breaches module for legislation linking
  - Offender matching/creation using existing OffenderMatcher
  - Validation and error handling following Ash patterns
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Agencies.Hse.OffenderBuilder
  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.BreachParser
  alias EhsEnforcement.Enforcement.LegislationMatcher
  alias EhsEnforcement.Scraping.Hse.CaseScraper.ScrapedCase

  @hse_agency_code :hse

  defmodule ProcessedCase do
    @moduledoc "Struct representing a case ready for Ash resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :offence_result,
      :offence_fine,
      :offence_costs,
      :offence_action_date,
      :offence_hearing_date,
      :offence_breaches,
      :offence_breaches_clean,
      :offence_lrt,
      :regulator_function,
      :regulator_url,
      :related_cases,
      :offence_action_type,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped case into format ready for Ash resource creation.

  Returns {:ok, %ProcessedCase{}} or {:error, reason}
  """
  def process_case(%ScrapedCase{} = scraped_case) do
    Logger.debug("Processing scraped case: #{scraped_case.regulator_id}")

    try do
      processed = %ProcessedCase{
        regulator_id: scraped_case.regulator_id,
        agency_code: @hse_agency_code,
        offender_attrs: build_offender_attrs(scraped_case),
        offence_result: scraped_case.offence_result,
        offence_fine: scraped_case.offence_fine,
        offence_costs: scraped_case.offence_costs,
        offence_action_date: scraped_case.offence_action_date,
        offence_hearing_date: scraped_case.offence_hearing_date,
        offence_breaches: scraped_case.offence_breaches,
        regulator_function: scraped_case.regulator_function,
        regulator_url: build_regulator_url(scraped_case.regulator_id),
        related_cases: scraped_case.related_cases,
        offence_action_type: "Court Case",
        source_metadata: build_source_metadata(scraped_case)
      }

      # Process breaches with legislation linking if breaches exist
      processed_with_breaches =
        case scraped_case.offence_breaches do
          breaches when is_list(breaches) and length(breaches) > 0 ->
            process_breaches(processed, breaches)

          breach when is_binary(breach) and breach != "" ->
            process_breaches(processed, [breach])

          _ ->
            processed
        end

      Logger.debug("Successfully processed case: #{scraped_case.regulator_id}")
      {:ok, processed_with_breaches}
    rescue
      error ->
        Logger.error("Failed to process case #{scraped_case.regulator_id}: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped cases in batch.

  Returns {:ok, [%ProcessedCase{}]} or {:error, reason}
  """
  def process_cases(scraped_cases) when is_list(scraped_cases) do
    Logger.info("Processing #{length(scraped_cases)} scraped cases")

    try do
      processed_cases =
        Enum.reduce_while(scraped_cases, [], fn scraped_case, acc ->
          case process_case(scraped_case) do
            {:ok, processed_case} ->
              {:cont, [processed_case | acc]}

            {:error, reason} ->
              Logger.warning("Skipping case #{scraped_case.regulator_id}: #{inspect(reason)}")
              # Continue processing other cases
              {:cont, acc}
          end
        end)

      successful_count = length(processed_cases)
      Logger.info("Successfully processed #{successful_count}/#{length(scraped_cases)} cases")

      {:ok, Enum.reverse(processed_cases)}
    rescue
      error -> {:error, {:batch_processing_error, error}}
    end
  end

  @doc """
  Process a single scraped case and create Ash resource immediately.

  Optimized for real-time scraping where each case should be saved individually.
  Returns {:ok, case} or {:error, reason}
  """
  def process_and_create_case(%ScrapedCase{} = scraped_case, actor \\ nil) do
    Logger.debug("🔄 Processing and creating case: #{scraped_case.regulator_id}")

    with {:ok, processed_case} <-
           (
             Logger.debug("📝 About to process case: #{scraped_case.regulator_id}")
             result = process_case(scraped_case)
             Logger.debug("📝 Process case result: #{inspect(result)}")
             result
           ),
         {:ok, case_record} <-
           (
             Logger.debug("💾 About to create case: #{processed_case.regulator_id}")
             result = create_case(processed_case, actor)
             Logger.debug("💾 Create case result: #{inspect(result)}")
             result
           ),
         {:ok, _offences} <-
           (
             Logger.debug("🔗 About to create offences for case: #{case_record.id}")
             result = create_case_offences(case_record, scraped_case.offence_breaches, actor)
             Logger.debug("🔗 Create offences result: #{inspect(result)}")
             result
           ) do
      Logger.info("✅ Successfully processed and created case: #{case_record.regulator_id}")
      {:ok, case_record}
    else
      {:error, reason} = error ->
        # Only log as error if it's not a duplicate case
        unless duplicate_error?(reason) do
          Logger.error(
            "❌ Failed to process and create case #{scraped_case.regulator_id}: #{inspect(reason)}"
          )
        end

        error
    end
  end

  @doc """
  Create Offence resources from breach data for an HSE case.

  Parses breach text, finds/creates legislation, and creates linked Offence records.
  Returns {:ok, offences} or {:error, reason}
  """
  def create_case_offences(case_record, breach_data, actor \\ nil)

  def create_case_offences(_case_record, nil, _actor), do: {:ok, []}
  def create_case_offences(_case_record, "", _actor), do: {:ok, []}
  def create_case_offences(_case_record, [], _actor), do: {:ok, []}

  def create_case_offences(case_record, breach_data, actor) when is_list(breach_data) do
    Logger.debug(
      "Creating #{length(breach_data)} offences for HSE case: #{case_record.regulator_id}"
    )

    # Parse all breaches and extract legislation
    parsed_breaches = BreachParser.parse_breaches(breach_data)

    # Create offence records with legislation linking, filtering out those without legislation
    offences_data =
      Enum.reduce(parsed_breaches, [], fn parsed, acc ->
        # Find or create legislation for this breach
        case LegislationMatcher.find_or_create_from_breach(
               parsed.offence_description,
               actor: actor
             ) do
          {:ok, nil} ->
            Logger.warning(
              "Skipping offence without legislation reference: #{String.slice(parsed.offence_description, 0..50)}..."
            )

            acc

          {:ok, legislation_id} ->
            # Build offence attributes
            offence_attrs =
              %{
                case_id: case_record.id,
                offence_description: parsed.offence_description,
                legislation_part: parsed.legislation_part,
                legislation_id: legislation_id,
                fine: parsed.fine,
                sequence_number: parsed.sequence_number
              }
              # Filter out nil values
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            [offence_attrs | acc]

          {:error, reason} ->
            Logger.error("Failed to find/create legislation for breach: #{inspect(reason)}")

            acc
        end
      end)
      |> Enum.reverse()

    # If no valid offences, return success with empty list
    if offences_data == [] do
      Logger.info(
        "No offences with valid legislation found for HSE case: #{case_record.regulator_id}"
      )

      {:ok, []}
    else
      # Bulk create offences
      case Ash.bulk_create(offences_data, Enforcement.Offence, :create) do
        %Ash.BulkResult{status: :success} = _bulk_result ->
          Logger.info(
            "Successfully created #{length(offences_data)} offences for HSE case: #{case_record.regulator_id}"
          )

          {:ok, offences_data}

        %Ash.BulkResult{status: :error} = bulk_result ->
          Logger.error(
            "Failed to create offences for HSE case #{case_record.regulator_id}: #{inspect(bulk_result.errors)}"
          )

          {:error, bulk_result.errors}
      end
    end
  end

  def create_case_offences(case_record, breach_text, actor) when is_binary(breach_text) do
    # Convert semicolon-separated string to list
    breach_list = String.split(breach_text, ";") |> Enum.map(&String.trim/1)
    create_case_offences(case_record, breach_list, actor)
  end

  @doc """
  Create Ash case resource from processed case data.

  Returns {:ok, case} or {:error, ash_error}
  """
  def create_case(%ProcessedCase{} = processed_case, actor \\ nil) do
    Logger.debug("Creating Ash case resource for: #{processed_case.regulator_id}")

    case_attrs = %{
      agency_code: processed_case.agency_code,
      regulator_id: processed_case.regulator_id,
      offender_attrs: processed_case.offender_attrs,
      offence_result: processed_case.offence_result,
      offence_fine: processed_case.offence_fine,
      offence_costs: processed_case.offence_costs,
      offence_action_date: processed_case.offence_action_date,
      offence_hearing_date: processed_case.offence_hearing_date,
      offence_breaches: processed_case.offence_breaches,
      regulator_function: processed_case.regulator_function,
      regulator_url: processed_case.regulator_url,
      related_cases: processed_case.related_cases,
      offence_action_type: processed_case.offence_action_type
    }

    # Add actor context if provided
    create_opts = if actor, do: [actor: actor], else: []

    case Enforcement.create_case(case_attrs, create_opts) do
      {:ok, case_record} ->
        Logger.info("Successfully created case: #{case_record.regulator_id}")
        {:ok, case_record}

      {:error, ash_error} ->
        # Handle duplicate by updating existing case with new scraping data
        if duplicate_error?(ash_error) do
          handle_duplicate_case_update(processed_case, case_attrs, ash_error, actor)
        else
          Logger.error(
            "Failed to create case #{processed_case.regulator_id}: #{inspect(ash_error)}"
          )

          {:error, ash_error}
        end
    end
  end

  @doc """
  Create multiple Ash case resources from processed cases using bulk operations.

  Returns {:ok, result} with summary stats or {:error, reason}
  """
  def create_cases(processed_cases, actor \\ nil) when is_list(processed_cases) do
    Logger.info("📋 Processing #{length(processed_cases)} cases for database creation")

    # Convert processed cases to format expected by bulk_create action
    cases_data = Enum.map(processed_cases, &processed_case_to_attrs/1)

    # Filter out cases that already exist using efficient duplicate detection
    regulator_ids = Enum.map(processed_cases, & &1.regulator_id)

    case Ash.read(Enforcement.Case,
           actor: actor,
           action: :duplicate_detection,
           regulator_ids: regulator_ids
         ) do
      {:ok, existing_cases} ->
        existing_ids = MapSet.new(existing_cases, & &1.regulator_id)

        new_cases_data =
          Enum.reject(cases_data, fn case_data ->
            MapSet.member?(existing_ids, case_data[:regulator_id])
          end)

        skipped_count = length(cases_data) - length(new_cases_data)

        if skipped_count > 0 do
          Logger.info("⏭️ Skipped #{skipped_count} existing cases")
        end

        Logger.info("💾 Creating #{length(new_cases_data)} new cases")

        # Use bulk_create for performance if we have cases to create
        if length(new_cases_data) > 0 do
          create_cases_bulk(new_cases_data, processed_cases, actor, skipped_count)
        else
          Logger.info("No new cases to create")

          {:ok,
           %{
             created: [],
             errors: [],
             stats: %{created_count: 0, error_count: 0, skipped_count: skipped_count}
           }}
        end

      {:error, _duplicate_check_error} ->
        Logger.warning("Duplicate detection failed, falling back to individual case creation")
        create_cases_individual(processed_cases, actor)
    end
  end

  # Private functions

  # Handle duplicate case by updating existing case with new scraping data
  defp handle_duplicate_case_update(processed_case, case_attrs, ash_error, actor) do
    Logger.debug(
      "Case already exists, updating with :update_from_scraping: #{processed_case.regulator_id}"
    )

    # Find the existing case and update it
    query_opts = if actor, do: [actor: actor], else: []

    case EhsEnforcement.Enforcement.Case
         |> Ash.Query.filter(regulator_id == ^processed_case.regulator_id)
         |> Ash.read_one(query_opts) do
      {:ok, existing_case} when not is_nil(existing_case) ->
        update_existing_case_with_scraping_data(
          existing_case,
          case_attrs,
          processed_case,
          ash_error,
          actor
        )

      {:ok, nil} ->
        Logger.warning("Case marked as duplicate but not found: #{processed_case.regulator_id}")

        {:error, ash_error}

      {:error, query_error} ->
        Logger.error(
          "Failed to query existing case #{processed_case.regulator_id}: #{inspect(query_error)}"
        )

        {:error, ash_error}
    end
  end

  # Update existing case with new scraping data
  defp update_existing_case_with_scraping_data(
         existing_case,
         case_attrs,
         processed_case,
         ash_error,
         actor
       ) do
    update_attrs = %{
      offence_result: case_attrs.offence_result,
      offence_fine: case_attrs.offence_fine,
      offence_costs: case_attrs.offence_costs,
      offence_hearing_date: case_attrs.offence_hearing_date,
      url: case_attrs.regulator_url,
      related_cases: case_attrs.related_cases
    }

    update_opts = if actor, do: [actor: actor], else: []

    case Enforcement.update_case_from_scraping(existing_case, update_attrs, update_opts) do
      {:ok, updated_case} ->
        Logger.info(
          "Successfully updated existing case via :update_from_scraping: #{updated_case.regulator_id}"
        )

        # Still return the original duplicate error to preserve existing counting logic
        {:error, ash_error}

      {:error, update_error} ->
        Logger.error(
          "Failed to update existing case #{processed_case.regulator_id}: #{inspect(update_error)}"
        )

        {:error, ash_error}
    end
  end

  defp build_offender_attrs(%ScrapedCase{} = scraped_case) do
    base_attrs = OffenderBuilder.build_offender_attrs(scraped_case, :case)

    # Attempt to match Companies House registration number
    case OffenderBuilder.match_companies_house_number(base_attrs) do
      {:ok, enhanced_attrs, :needs_review, candidates} ->
        # Medium confidence match - log candidates for manual review
        # TODO: Store review candidates in a separate review table
        Logger.info(
          "Medium confidence Companies House match for #{enhanced_attrs.name}: #{length(candidates)} candidates found"
        )

        enhanced_attrs

      {:ok, enhanced_attrs} ->
        # High confidence match or no match
        enhanced_attrs

      {:error, _reason} ->
        # On error, fall back to base attrs (error already logged)
        base_attrs
    end
  end

  defp build_regulator_url(regulator_id) do
    "https://resources.hse.gov.uk/convictions/case/case_details.asp?SF=CN&SV=#{regulator_id}"
  end

  defp build_source_metadata(%ScrapedCase{} = scraped_case) do
    %{
      scraped_at: scraped_case.scrape_timestamp,
      source_page: scraped_case.page_number,
      scraper_version: "1.0",
      source: "hse_website"
    }
  end

  defp process_breaches(%ProcessedCase{} = processed_case, breaches) when is_list(breaches) do
    Logger.debug(
      "Processing #{length(breaches)} breaches for case #{processed_case.regulator_id}"
    )

    try do
      # Process breaches locally (simplified from legacy Breaches.enum_breaches)
      processed_breach_data = process_breaches_locally(breaches)

      # Extract the processed breach information
      %{
        processed_case
        | offence_breaches: processed_breach_data.offence_breaches,
          offence_breaches_clean: processed_breach_data.offence_breaches_clean,
          offence_lrt: processed_breach_data.offence_lrt
      }
    rescue
      error ->
        Logger.warning(
          "Failed to process breaches for case #{processed_case.regulator_id}: #{inspect(error)}"
        )

        # Return original case if breach processing fails
        processed_case
    end
  end

  # Helper functions for bulk operations

  defp processed_case_to_attrs(%ProcessedCase{} = processed_case) do
    %{
      agency_code: processed_case.agency_code,
      regulator_id: processed_case.regulator_id,
      offender_attrs: processed_case.offender_attrs,
      offence_result: processed_case.offence_result,
      offence_fine: processed_case.offence_fine,
      offence_costs: processed_case.offence_costs,
      offence_action_date: processed_case.offence_action_date,
      offence_hearing_date: processed_case.offence_hearing_date,
      offence_breaches: processed_case.offence_breaches,
      regulator_function: processed_case.regulator_function,
      regulator_url: processed_case.regulator_url,
      related_cases: processed_case.related_cases,
      offence_action_type: processed_case.offence_action_type
    }
  end

  defp create_cases_bulk(cases_data, _processed_cases, actor, skipped_count) do
    Logger.info("Using bulk_create for #{length(cases_data)} cases")

    # Add actor context if provided - bulk_create handles actor internally
    _bulk_opts = if actor, do: [actor: actor], else: []

    case Enforcement.Case.bulk_create(cases_data: cases_data, batch_size: 50) do
      {:ok, _bulk_result} ->
        Logger.info("Bulk create completed successfully")

        {:ok,
         %{
           # bulk_create doesn't return individual records
           created: [],
           errors: [],
           stats: %{
             # Assuming all succeeded
             created_count: length(cases_data),
             error_count: 0,
             skipped_count: skipped_count
           }
         }}

      {:error, bulk_error} ->
        Logger.error("Bulk create failed: #{inspect(bulk_error)}")
        {:error, bulk_error}
    end
  end

  defp create_cases_individual(processed_cases, actor) do
    Logger.info("Using individual case creation for #{length(processed_cases)} cases")

    results =
      Enum.reduce(processed_cases, %{created: [], errors: []}, fn processed_case, acc ->
        case create_case(processed_case, actor) do
          {:ok, case_record} ->
            %{acc | created: [case_record | acc.created]}

          {:error, error} ->
            error_info = %{regulator_id: processed_case.regulator_id, error: error}
            %{acc | errors: [error_info | acc.errors]}
        end
      end)

    created_count = length(results.created)
    error_count = length(results.errors)

    Logger.info(
      "Individual case creation complete: #{created_count} created, #{error_count} errors"
    )

    if error_count > 0 do
      Logger.warning("Errors creating cases: #{inspect(results.errors)}")
    end

    {:ok,
     %{
       created: Enum.reverse(results.created),
       errors: Enum.reverse(results.errors),
       stats: %{created_count: created_count, error_count: error_count, skipped_count: 0}
     }}
  end

  # Local implementations to replace legacy Common/Breaches modules

  defp process_breaches_locally(breaches) when is_list(breaches) do
    # Simplified breach processing - just concatenate and clean
    breaches_text = Enum.join(breaches, "; ")

    %{
      offence_breaches: breaches_text,
      offence_breaches_clean: String.trim(breaches_text),
      # Legislation linking would go here
      offence_lrt: nil
    }
  end

  defp duplicate_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %{field: :regulator_id, message: message} ->
        String.contains?(message, "already been taken") or
          String.contains?(message, "already exists")

      _ ->
        false
    end)
  end

  defp duplicate_error?(_), do: false
end
