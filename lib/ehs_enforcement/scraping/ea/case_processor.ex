defmodule EhsEnforcement.Scraping.Ea.CaseProcessor do
  @moduledoc """
  EA case processing pipeline - transforms scraped EA data for Ash resource creation.

  Handles:
  - EA data transformation from EaDetailRecord to Ash Case resource format
  - Multi-violation scenario detection and Violation resource creation
  - Integration with existing DataTransformer for field mapping
  - Offender matching/creation using company registration numbers
  - Environmental impact and legal framework processing
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Agencies.Ea.DataTransformer
  alias EhsEnforcement.Agencies.Ea.OffenderBuilder
  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Enforcement.BreachParser
  alias EhsEnforcement.Enforcement.LegislationMatcher
  alias EhsEnforcement.Enforcement.UnifiedCaseProcessor
  alias EhsEnforcement.Scraping.Ea.CaseScraper.EaDetailRecord
  alias EhsEnforcement.Scraping.Shared.EnvironmentalHelpers

  @behaviour EhsEnforcement.Enforcement.CaseProcessorBehaviour

  @ea_agency_code :ea

  defmodule ProcessedEaCase do
    @moduledoc "Struct representing an EA case ready for Ash resource creation"

    @derive Jason.Encoder
    defstruct [
      # Core identifiers (mapped from EA data)
      :regulator_id,
      :case_reference,
      :agency_code,
      :offender_attrs,

      # Enforcement details
      :offence_result,
      :offence_fine,
      :offence_costs,
      :offence_action_date,
      :offence_hearing_date,
      :offence_breaches,
      # Renamed from offence_breaches_clean for clarity
      :legal_reference,
      :regulator_function,
      :regulator_url,
      :related_cases,
      :offence_action_type,

      # EA-specific fields (new schema extensions)
      :ea_event_reference,
      :ea_total_violation_count,
      :environmental_impact,
      :environmental_receptor,
      :is_ea_multi_violation,

      # Source metadata
      :source_metadata,

      # Multi-violation data (for Violation resources)
      :violations_data
    ]
  end

  @doc """
  Process a single EA detail record into format ready for Ash Case resource creation.

  Returns {:ok, %ProcessedEaCase{}} or {:error, reason}
  """
  def process_ea_case(%EaDetailRecord{} = ea_record) do
    Logger.debug("Processing EA case: #{ea_record.ea_record_id}")

    try do
      # Transform EA record using existing DataTransformer
      transformed_data = DataTransformer.transform_ea_record(ea_record)

      processed = %ProcessedEaCase{
        regulator_id: transformed_data.regulator_id,
        case_reference: ea_record.case_reference,
        agency_code: @ea_agency_code,
        offender_attrs: build_ea_offender_attrs(ea_record),
        offence_result: map_ea_action_to_result(ea_record.action_type),
        offence_fine: ea_record.total_fine || Decimal.new(0),
        # EA doesn't separate costs
        offence_costs: Decimal.new(0),
        offence_action_date: ea_record.action_date,
        # EA doesn't provide hearing dates
        offence_hearing_date: nil,
        offence_breaches: build_combined_breaches_text(ea_record),
        legal_reference: build_legal_reference(ea_record),
        regulator_function: normalize_ea_function(ea_record.agency_function),
        regulator_url: ea_record.detail_url,
        # Could be enhanced later
        related_cases: nil,
        offence_action_type: map_ea_action_to_hse_type(ea_record.action_type),

        # EA-specific extensions
        ea_event_reference: ea_record.event_reference,
        ea_total_violation_count: detect_violation_count(ea_record),
        environmental_impact: assess_environmental_impact(ea_record),
        environmental_receptor: detect_primary_receptor(ea_record),
        is_ea_multi_violation: multi_violation_case?(ea_record),
        source_metadata: build_ea_source_metadata(ea_record),
        violations_data: build_violations_data(ea_record)
      }

      Logger.debug("Successfully processed EA case: #{ea_record.ea_record_id}")
      {:ok, processed}
    rescue
      error ->
        Logger.error("Failed to process EA case #{ea_record.ea_record_id}: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple EA detail records in batch.

  Returns {:ok, [%ProcessedEaCase{}]} or {:error, reason}
  """
  def process_ea_cases(ea_records) when is_list(ea_records) do
    Logger.info("Processing #{length(ea_records)} EA records")

    try do
      processed_cases =
        Enum.reduce_while(ea_records, [], fn ea_record, acc ->
          case process_ea_case(ea_record) do
            {:ok, processed_case} ->
              {:cont, [processed_case | acc]}

            {:error, reason} ->
              Logger.warning("Skipping EA record #{ea_record.ea_record_id}: #{inspect(reason)}")
              # Continue processing other records
              {:cont, acc}
          end
        end)

      successful_count = length(processed_cases)
      Logger.info("Successfully processed #{successful_count}/#{length(ea_records)} EA cases")

      {:ok, Enum.reverse(processed_cases)}
    rescue
      error -> {:error, {:batch_processing_error, error}}
    end
  end

  @doc """
  Process a single EA record and create Ash Case resource immediately.

  Handles multi-violation scenarios by creating both Case and Violation resources.
  Returns {:ok, case} or {:error, reason}
  """
  def process_and_create_case(ea_record_or_transformed, actor \\ nil)

  def process_and_create_case(%EaDetailRecord{} = ea_record, actor) do
    Logger.debug("🔄 Processing and creating EA case: #{ea_record.ea_record_id}")

    with {:ok, processed_case} <-
           (
             Logger.debug("📝 About to process EA case: #{ea_record.ea_record_id}")
             result = process_ea_case(ea_record)
             Logger.debug("📝 Process EA case result: #{inspect(result)}")
             result
           ),
         {:ok, case_record, _status} <-
           (
             Logger.debug("💾 About to create EA case: #{processed_case.regulator_id}")
             result = create_ea_case(processed_case, actor)
             Logger.debug("💾 Create EA case result: #{inspect(result)}")
             result
           ),
         {:ok, _violations} <-
           (
             Logger.debug("🔗 About to create violations for case: #{case_record.id}")
             result = create_case_violations(case_record, processed_case.violations_data, actor)
             Logger.debug("🔗 Create violations result: #{inspect(result)}")
             result
           ) do
      Logger.info("✅ Successfully processed and created EA case: #{case_record.regulator_id}")
      {:ok, case_record}
    else
      {:error, reason} = error ->
        # Only log as error if it's not a duplicate case
        unless duplicate_error?(reason) do
          Logger.error(
            "❌ Failed to process and create EA case #{ea_record.ea_record_id}: #{inspect(reason)}"
          )
        end

        error
    end
  end

  def process_and_create_case(transformed_case, actor) when is_map(transformed_case) do
    Logger.debug("🔄 Processing pre-transformed EA case data")

    # Handle case where we receive transformed data from DataTransformer
    case create_case_from_transformed_data(transformed_case, actor) do
      {:ok, case_record} ->
        Logger.info("✅ Successfully created EA case from transformed data")
        {:ok, case_record}

      {:error, reason} = error ->
        unless duplicate_error?(reason) do
          Logger.error("❌ Failed to create EA case from transformed data: #{inspect(reason)}")
        end

        error
    end
  end

  @doc """
  Behavior implementation: Process and create case with status for UI display.
  """
  @impl EhsEnforcement.Enforcement.CaseProcessorBehaviour
  def process_and_create_case_with_status(processed_case, actor \\ nil)

  def process_and_create_case_with_status(%ProcessedEaCase{} = processed_case, actor) do
    case_attrs = build_case_attrs(processed_case)
    UnifiedCaseProcessor.process_and_create_case_with_status(case_attrs, actor)
  end

  def process_and_create_case_with_status(transformed_case, actor)
      when is_map(transformed_case) do
    case_attrs = build_case_attrs_from_transformed(transformed_case)
    UnifiedCaseProcessor.process_and_create_case_with_status(case_attrs, actor)
  end

  @doc """
  Create Ash Case resource from processed EA case data.

  Returns {:ok, case} or {:error, ash_error}
  """
  def create_ea_case(%ProcessedEaCase{} = processed_case, actor \\ nil) do
    Logger.debug("Creating Ash Case resource for EA case: #{processed_case.regulator_id}")

    case_attrs = %{
      agency_code: processed_case.agency_code,
      regulator_id: processed_case.regulator_id,
      case_reference: processed_case.case_reference,
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
      offence_action_type: processed_case.offence_action_type,

      # EA-specific fields
      ea_event_reference: processed_case.ea_event_reference,
      ea_total_violation_count: processed_case.ea_total_violation_count,
      environmental_impact: processed_case.environmental_impact,
      environmental_receptor: processed_case.environmental_receptor,
      is_ea_multi_violation: processed_case.is_ea_multi_violation
    }

    # Add actor context if provided
    create_opts = if actor, do: [actor: actor], else: []

    case Enforcement.create_case(case_attrs, create_opts) do
      {:ok, case_record} ->
        Logger.info("Successfully created EA case: #{case_record.regulator_id}")
        {:ok, case_record, :created}

      {:error, ash_error} ->
        # Handle duplicate by updating existing case with new EA data
        if duplicate_error?(ash_error) do
          Logger.debug(
            "EA case already exists, checking if update needed: #{processed_case.regulator_id}"
          )

          # Get agency_id from agency_code for the query
          {:ok, agency} = Enforcement.get_agency_by_code(processed_case.agency_code)

          # Find the existing case and check if update is needed
          query_opts = if actor, do: [actor: actor], else: []

          case Enforcement.Case
               |> Ash.Query.filter(
                 agency_id == ^agency.id and regulator_id == ^processed_case.regulator_id
               )
               |> Ash.read_one(query_opts) do
            {:ok, existing_case} when not is_nil(existing_case) ->
              # Check if any fields actually need updating
              update_attrs = %{
                offence_result: case_attrs.offence_result,
                offence_fine: case_attrs.offence_fine,
                offence_costs: case_attrs.offence_costs,
                offence_hearing_date: case_attrs.offence_hearing_date,
                url: case_attrs.regulator_url,
                related_cases: case_attrs.related_cases
              }

              # Check if any field values actually differ
              needs_update =
                Enum.any?(update_attrs, fn {field, new_value} ->
                  case field do
                    :url -> existing_case.regulator_url != new_value
                    _ -> Map.get(existing_case, field) != new_value
                  end
                end)

              if needs_update do
                # Actually update the case
                update_opts = if actor, do: [actor: actor], else: []

                case Enforcement.update_case_from_scraping(
                       existing_case,
                       update_attrs,
                       update_opts
                     ) do
                  {:ok, updated_case} ->
                    Logger.info(
                      "Successfully updated existing EA case via :update_from_scraping: #{updated_case.regulator_id}"
                    )

                    {:ok, updated_case, :updated}

                  {:error, update_error} ->
                    Logger.error(
                      "Failed to update existing EA case #{processed_case.regulator_id}: #{inspect(update_error)}"
                    )

                    {:error, ash_error}
                end
              else
                Logger.debug(
                  "EA case already exists with identical data, no update needed: #{existing_case.regulator_id}"
                )

                {:ok, existing_case, :existing}
              end

            {:ok, nil} ->
              Logger.warning(
                "EA case marked as duplicate but not found: #{processed_case.regulator_id}"
              )

              {:error, ash_error}

            {:error, query_error} ->
              Logger.error(
                "Failed to query existing EA case #{processed_case.regulator_id}: #{inspect(query_error)}"
              )

              {:error, ash_error}
          end
        else
          Logger.error(
            "Failed to create EA case #{processed_case.regulator_id}: #{inspect(ash_error)}"
          )

          {:error, ash_error}
        end
    end
  end

  @doc """
  Create Offence resources for EA cases with legislation linking.

  Processes ALL EA cases (not just multi-violation), extracts legislation,
  and creates properly linked Offence records.

  Returns {:ok, offences} or {:error, reason}
  """
  def create_case_violations(case_record, violations_data, actor \\ nil) do
    if is_list(violations_data) and length(violations_data) > 0 do
      Logger.debug(
        "Creating #{length(violations_data)} offences for EA case: #{case_record.regulator_id}"
      )

      # Process each violation to find/create legislation, filtering out those without legislation
      offences_data =
        Enum.reduce(violations_data, [], fn violation, acc ->
          # Build combined offence text for legislation lookup
          # Prioritize legal_act+legal_section over offence_description for better parsing
          offence_text =
            case violation do
              %{legal_act: act, legal_section: section}
              when is_binary(act) and is_binary(section) ->
                "#{act}, #{section}"

              %{legal_act: act} when is_binary(act) ->
                act

              %{offence_description: desc} when is_binary(desc) ->
                desc

              _ ->
                nil
            end

          # Find or create legislation
          legislation_result =
            if offence_text do
              LegislationMatcher.find_or_create_from_breach(offence_text, actor: actor)
            else
              {:ok, nil}
            end

          case legislation_result do
            {:ok, nil} ->
              Logger.warning(
                "Skipping EA offence without legislation reference: #{inspect(violation)}"
              )

              acc

            {:ok, legislation_id} ->
              # Build offence attributes with legislation link
              offence_attrs =
                %{
                  case_id: case_record.id,
                  offence_description: violation[:offence_description],
                  legislation_part: violation[:legislation_part],
                  legislation_id: legislation_id,
                  fine: violation[:fine],
                  sequence_number: violation[:sequence_number]
                }
                # Filter out nil values
                |> Enum.reject(fn {_k, v} -> is_nil(v) end)
                |> Map.new()

              [offence_attrs | acc]

            {:error, reason} ->
              Logger.error(
                "Failed to find/create legislation for EA violation: #{inspect(reason)}"
              )

              acc
          end
        end)
        |> Enum.reverse()

      # If no valid offences, return success with empty list
      if offences_data == [] do
        Logger.info(
          "No offences with valid legislation found for EA case: #{case_record.regulator_id}"
        )

        {:ok, []}
      else
        # Bulk create offences with legislation linkage
        case Ash.bulk_create(offences_data, Enforcement.Offence, :create) do
          %Ash.BulkResult{status: :success} = _bulk_result ->
            Logger.info(
              "Successfully created #{length(offences_data)} offences for EA case: #{case_record.regulator_id}"
            )

            {:ok, offences_data}

          %Ash.BulkResult{status: :error} = bulk_result ->
            Logger.error(
              "Failed to create offences for EA case #{case_record.regulator_id}: #{inspect(bulk_result.errors)}"
            )

            {:error, bulk_result.errors}
        end
      end
    else
      # No violations to create
      {:ok, []}
    end
  end

  # Private helper functions

  defp build_ea_offender_attrs(%EaDetailRecord{} = ea_record) do
    OffenderBuilder.build_offender_attrs(ea_record, :case)
  end

  defp build_legal_reference(%EaDetailRecord{} = ea_record) do
    case {ea_record.act, ea_record.section} do
      {act, section} when is_binary(act) and is_binary(section) ->
        "#{String.trim(act)} - #{String.trim(section)}"

      {act, _} when is_binary(act) ->
        String.trim(act)

      _ ->
        nil
    end
  end

  defp build_combined_breaches_text(%EaDetailRecord{} = ea_record) do
    legal_ref = build_legal_reference(ea_record)
    offence_desc = ea_record.offence_description

    case {offence_desc, legal_ref} do
      {desc, ref} when is_binary(desc) and is_binary(ref) ->
        "#{String.trim(desc)}\n\nLegal Reference: #{ref}"

      {desc, nil} when is_binary(desc) ->
        String.trim(desc)

      {nil, ref} when is_binary(ref) ->
        "Legal Reference: #{ref}"

      _ ->
        nil
    end
  end

  defp build_ea_source_metadata(%EaDetailRecord{} = ea_record) do
    %{
      scraped_at: ea_record.scraped_at,
      source: "ea_website",
      scraper_version: "2.0",
      ea_record_id: ea_record.ea_record_id,
      detail_url: ea_record.detail_url
    }
  end

  # EA-specific field mapping functions

  defp map_ea_action_to_result(action_type) do
    case action_type do
      :court_case -> "Court Action"
      :caution -> "Formal Caution"
      :enforcement_notice -> "Enforcement Notice Issued"
      _ -> "Regulatory Action"
    end
  end

  defp map_ea_action_to_hse_type(action_type) do
    case action_type do
      :court_case -> "Court Case"
      :caution -> "Formal Caution"
      :enforcement_notice -> "Enforcement Notice"
      _ -> "Other"
    end
  end

  defp normalize_ea_function(agency_function) when is_binary(agency_function) do
    "Environmental - #{String.trim(agency_function)}"
  end

  defp normalize_ea_function(_), do: "Environmental"

  defp assess_environmental_impact(%EaDetailRecord{} = ea_record) do
    EnvironmentalHelpers.assess_environmental_impact(
      ea_record.water_impact,
      ea_record.land_impact,
      ea_record.air_impact
    )
  end

  defp detect_primary_receptor(%EaDetailRecord{} = ea_record) do
    EnvironmentalHelpers.detect_primary_receptor(
      ea_record.water_impact,
      ea_record.land_impact,
      ea_record.air_impact
    )
  end

  defp detect_violation_count(%EaDetailRecord{} = ea_record) do
    # For now, assume single violation per EA record
    # This could be enhanced to detect multiple case references
    if multi_violation_case?(ea_record), do: length(build_violations_data(ea_record)), else: 1
  end

  defp multi_violation_case?(%EaDetailRecord{} = ea_record) do
    # Check if case reference suggests multiple violations
    # EA multi-violation cases often have numbered case references
    case_ref = ea_record.case_reference || ""
    String.contains?(case_ref, "/01") or String.contains?(case_ref, "/02")
  end

  defp build_violations_data(%EaDetailRecord{} = ea_record) do
    # Build combined offence description from EA data
    offence_text = build_combined_breaches_text(ea_record)

    # Return empty if no offence description
    if is_nil(offence_text) or offence_text == "" do
      []
    else
      # Parse the offence text to extract legislation info
      parsed = BreachParser.parse_breach(offence_text)

      # Create violation data for ALL EA cases (not just multi-violation)
      [
        %{
          offence_description: offence_text,
          legislation_part: parsed.legislation_part || ea_record.section,
          fine: ea_record.total_fine,
          sequence_number: 1,
          # Store EA-specific fields for legislation matching
          legal_act: ea_record.act,
          legal_section: ea_record.section
        }
      ]
    end
  end

  # Industry classification mapping

  # Error handling helpers

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

  # Alternative creation method for pre-transformed data

  defp create_case_from_transformed_data(transformed_case, actor) do
    case_attrs = %{
      agency_code: transformed_case[:agency_code] || transformed_case.agency_code || :ea,
      regulator_id: transformed_case[:regulator_id] || transformed_case.regulator_id,
      case_reference: transformed_case[:case_reference] || transformed_case.case_reference,
      offender_attrs: build_offender_attrs_from_transformed(transformed_case),
      offence_result: transformed_case[:offence_result] || "Regulatory Action",
      offence_fine: transformed_case[:total_fine] || Decimal.new(0),
      offence_costs: Decimal.new(0),
      offence_action_date: transformed_case[:action_date],
      offence_hearing_date: nil,
      offence_breaches: build_combined_breaches_from_transformed(transformed_case),
      regulator_function: transformed_case[:agency_function] || "Environmental",
      regulator_url: transformed_case[:regulator_url],
      related_cases: nil,
      offence_action_type: transformed_case[:offence_action_type] || "Other"
    }

    create_opts = if actor, do: [actor: actor], else: []

    case Enforcement.create_case(case_attrs, create_opts) do
      {:ok, case_record} ->
        {:ok, case_record}

      {:error, ash_error} ->
        # Handle duplicate by updating existing case with new EA data
        if duplicate_error?(ash_error) do
          Logger.debug("EA transformed case already exists, updating: #{case_attrs.regulator_id}")

          # Find the existing case and update it
          query_opts = if actor, do: [actor: actor], else: []

          case Enforcement.Case
               |> Ash.Query.filter(regulator_id == ^case_attrs.regulator_id)
               |> Ash.read_one(query_opts) do
            {:ok, existing_case} when not is_nil(existing_case) ->
              # Update with the new EA data using our scraping action
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
                    "Successfully updated existing EA transformed case: #{updated_case.regulator_id}"
                  )

                  {:ok, updated_case}

                {:error, update_error} ->
                  Logger.error(
                    "Failed to update existing EA transformed case #{case_attrs.regulator_id}: #{inspect(update_error)}"
                  )

                  {:error, ash_error}
              end

            {:ok, nil} ->
              Logger.warning(
                "EA transformed case marked as duplicate but not found: #{case_attrs.regulator_id}"
              )

              {:error, ash_error}

            {:error, query_error} ->
              Logger.error(
                "Failed to query existing EA transformed case #{case_attrs.regulator_id}: #{inspect(query_error)}"
              )

              {:error, ash_error}
          end
        else
          {:error, ash_error}
        end
    end
  end

  defp build_offender_attrs_from_transformed(transformed_case) do
    %{
      name: transformed_case[:offender_name],
      address: transformed_case[:address],
      local_authority: transformed_case[:county],
      postcode: transformed_case[:postcode],
      main_activity: transformed_case[:industry_sector],
      # Would need additional mapping
      industry: "Unknown",
      # EA-specific fields (now supported)
      company_registration_number: transformed_case[:company_registration_number],
      town: transformed_case[:town],
      county: transformed_case[:county],
      industry_sectors: build_industry_sectors_array(transformed_case[:industry_sector])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp build_industry_sectors_array(nil), do: []
  defp build_industry_sectors_array(""), do: []

  defp build_industry_sectors_array(industry_sector) when is_binary(industry_sector) do
    [industry_sector]
  end

  defp build_combined_breaches_from_transformed(transformed_case) do
    legal_ref = transformed_case[:legal_reference]
    offence_desc = transformed_case[:offence_description]

    case {offence_desc, legal_ref} do
      {desc, ref} when is_binary(desc) and is_binary(ref) ->
        "#{String.trim(desc)}\n\nLegal Reference: #{ref}"

      {desc, nil} when is_binary(desc) ->
        String.trim(desc)

      {nil, ref} when is_binary(ref) ->
        "Legal Reference: #{ref}"

      _ ->
        nil
    end
  end

  # Helper functions for unified case processor

  defp build_case_attrs(%ProcessedEaCase{} = processed_case) do
    %{
      agency_code: processed_case.agency_code,
      regulator_id: processed_case.regulator_id,
      case_reference: processed_case.case_reference,
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
      offence_action_type: processed_case.offence_action_type,

      # EA-specific fields
      ea_event_reference: processed_case.ea_event_reference,
      ea_total_violation_count: processed_case.ea_total_violation_count,
      environmental_impact: processed_case.environmental_impact,
      environmental_receptor: processed_case.environmental_receptor,
      is_ea_multi_violation: processed_case.is_ea_multi_violation
    }
  end

  defp build_case_attrs_from_transformed(transformed_case) do
    %{
      agency_code: transformed_case[:agency_code] || transformed_case.agency_code || :ea,
      regulator_id: transformed_case[:regulator_id] || transformed_case.regulator_id,
      case_reference: transformed_case[:case_reference] || transformed_case.case_reference,
      offender_attrs: build_offender_attrs_from_transformed(transformed_case),
      offence_result: transformed_case[:offence_result] || "Regulatory Action",
      offence_fine: transformed_case[:total_fine] || Decimal.new(0),
      offence_costs: Decimal.new(0),
      offence_action_date: transformed_case[:action_date],
      offence_hearing_date: nil,
      offence_breaches: build_combined_breaches_from_transformed(transformed_case),
      regulator_function: transformed_case[:agency_function] || "Environmental",
      regulator_url: transformed_case[:regulator_url],
      related_cases: nil,
      offence_action_type: transformed_case[:offence_action_type] || "Other"
    }
  end
end
