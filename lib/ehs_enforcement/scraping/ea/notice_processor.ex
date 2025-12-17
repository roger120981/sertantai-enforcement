defmodule EhsEnforcement.Scraping.Ea.NoticeProcessor do
  @moduledoc """
  EA Notice processing pipeline - transforms scraped enforcement notice data for Ash resource creation.

  Handles:
  - Data transformation from EA enforcement notice format to Ash Notice resource format
  - Environmental impact and legal framework data processing
  - Integration with EA.DataTransformer for consistent EA data patterns
  - Integration with EA.OffenderMatcher for offender matching/creation
  - Validation and error handling following Ash patterns

  ## EA Notice Characteristics

  EA enforcement notices include environmental-specific data not present in HSE notices:
  - Environmental impact assessment
  - Environmental receptor information (water, land, air)
  - Legal framework (acts and sections)
  - Agency function (waste, water quality, etc.)
  - Event reference numbers
  """

  require Logger
  alias EhsEnforcement.Agencies.Ea.DataTransformer
  alias EhsEnforcement.Agencies.Ea.OffenderBuilder
  alias EhsEnforcement.Agencies.Ea.OffenderMatcher
  alias EhsEnforcement.Scraping.Shared.EnvironmentalHelpers

  @ea_agency_code :ea

  defmodule ProcessedEaNotice do
    @moduledoc """
    Struct representing an EA enforcement notice ready for Ash resource creation.

    Extends the standard notice format with EA-specific environmental data.
    """

    @derive Jason.Encoder
    defstruct [
      # Core notice fields (standard across agencies)
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :notice_date,
      :operative_date,
      :compliance_date,
      :notice_body,
      :offence_action_type,
      :offence_action_date,
      :offence_breaches,
      :regulator_url,
      :source_metadata,

      # EA-specific environmental fields
      :regulator_event_reference,
      :environmental_impact,
      :environmental_receptor,
      :legal_act,
      :legal_section,
      :regulator_function
    ]
  end

  @doc """
  Process a single scraped EA enforcement notice into format ready for Ash resource creation.

  Takes an EaDetailRecord struct from the EA scraper and transforms it into
  a ProcessedEaNotice struct ready for Notice resource creation.

  ## Parameters

  - `ea_detail_record` - EaDetailRecord struct from EA.CaseScraper

  ## Returns

  - `{:ok, %ProcessedEaNotice{}}` - Successfully processed notice
  - `{:error, reason}` - Processing error

  ## Examples

      {:ok, processed} = NoticeProcessor.process_notice(ea_detail_record)
      {:ok, notice} = create_notice_from_processed(processed, actor)
  """
  def process_notice(ea_detail_record) when is_map(ea_detail_record) do
    Logger.debug(
      "EA NoticeProcessor: Processing enforcement notice: #{ea_detail_record.ea_record_id}"
    )

    try do
      # Transform EA record using the standard EA DataTransformer
      # This gives us the common case/notice fields in standard format
      transformed_data = DataTransformer.transform_ea_record(ea_detail_record)

      # Verify this is actually an enforcement notice
      if enforcement_notice?(ea_detail_record) do
        # Extract EA-specific environmental data
        environmental_data = extract_environmental_data(ea_detail_record)

        # Build offender attributes from EA detail record
        offender_attrs = build_offender_attrs(ea_detail_record)

        # Build processed notice struct
        processed = %ProcessedEaNotice{
          # Core notice fields
          regulator_id: transformed_data.regulator_id,
          agency_code: @ea_agency_code,
          offender_attrs: offender_attrs,
          notice_date: transformed_data.action_date,
          operative_date: parse_operative_date(ea_detail_record),
          compliance_date: parse_compliance_date(ea_detail_record),
          notice_body: transformed_data.offence_description,
          offence_action_type: transformed_data.offence_action_type,
          offence_action_date: transformed_data.action_date,
          offence_breaches: nil,
          regulator_url: transformed_data.regulator_url,
          source_metadata: build_source_metadata(ea_detail_record),

          # EA-specific environmental fields
          regulator_event_reference: environmental_data.event_reference,
          environmental_impact: environmental_data.impact,
          environmental_receptor: environmental_data.receptor,
          legal_act: environmental_data.legal_act,
          legal_section: environmental_data.legal_section,
          regulator_function: environmental_data.agency_function
        }

        Logger.debug(
          "EA NoticeProcessor: Successfully processed enforcement notice: #{ea_detail_record.ea_record_id}"
        )

        {:ok, processed}
      else
        Logger.warning(
          "EA NoticeProcessor: Record #{ea_detail_record.ea_record_id} is not an enforcement notice"
        )

        {:error, {:invalid_notice_type, ea_detail_record.offence_action_type}}
      end
    rescue
      error ->
        Logger.error(
          "EA NoticeProcessor: Failed to process notice #{ea_detail_record.ea_record_id}: #{inspect(error)}"
        )

        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped EA enforcement notices in batch.

  ## Returns

  - `{:ok, [%ProcessedEaNotice{}]}` - All notices processed successfully
  - `{:ok, [%ProcessedEaNotice{}], errors: errors}` - Some notices processed with errors
  """
  def process_notices(ea_detail_records) when is_list(ea_detail_records) do
    Logger.info("EA NoticeProcessor: Processing #{length(ea_detail_records)} enforcement notices")

    results =
      Enum.reduce(ea_detail_records, {[], []}, fn record, {processed, errors} ->
        case process_notice(record) do
          {:ok, processed_notice} -> {[processed_notice | processed], errors}
          {:error, reason} -> {processed, [{record.ea_record_id, reason} | errors]}
        end
      end)

    case results do
      {processed_notices, []} ->
        Logger.info(
          "EA NoticeProcessor: Successfully processed all #{length(processed_notices)} notices"
        )

        {:ok, Enum.reverse(processed_notices)}

      {processed_notices, errors} ->
        Logger.warning(
          "EA NoticeProcessor: Processed #{length(processed_notices)} notices with #{length(errors)} errors"
        )

        {:ok, Enum.reverse(processed_notices), errors: errors}
    end
  end

  @doc """
  Process and create a single EA enforcement notice directly using Ash patterns.

  Combines processing and Notice resource creation into a single operation.
  Also creates legislation and offence records when legal_act is present.

  ## Returns

  - `{:ok, %Notice{}, :created}` - Notice created successfully
  - `{:ok, %Notice{}, :updated}` - Existing notice updated
  - `{:ok, %Notice{}, :existing}` - Notice already exists, no changes
  - `{:error, reason}` - Processing or creation failed
  """
  def process_and_create_notice(ea_detail_record, actor) do
    # Use the legislation linking function to ensure offences and legislation
    # records are created when legal_act is present
    process_notice_with_legislation_linking(ea_detail_record, actor)
  end

  @doc """
  Process and create a notice with unified status reporting for UI display.

  This provides the same status interface as the unified case processor
  for consistent UI progress display.
  """
  def process_and_create_notice_with_status(ea_detail_record, actor) do
    case process_and_create_notice(ea_detail_record, actor) do
      {:ok, notice, status} ->
        {:ok, notice, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a notice from processed EA data using Ash patterns.

  Handles offender matching, agency lookup, and Notice resource creation
  with proper error handling and duplicate detection.
  """
  def create_notice_from_processed(%ProcessedEaNotice{} = processed, actor) do
    Logger.debug(
      "EA NoticeProcessor: Creating notice from processed data: #{processed.regulator_id}"
    )

    # Get EA agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender using EA offender matcher
        case OffenderMatcher.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Check for existing notice to avoid duplicates
            case check_for_existing_notice(processed.regulator_id, agency.id) do
              {:ok, nil} ->
                # Create new notice
                create_new_notice(processed, agency.id, offender.id, actor)

              {:ok, existing_notice} ->
                # Update existing notice with any new data
                update_existing_notice(existing_notice, processed, actor)

              {:error, reason} ->
                Logger.error(
                  "EA NoticeProcessor: Failed to check for existing notice: #{inspect(reason)}"
                )

                {:error, {:duplicate_check_error, reason}}
            end

          {:error, reason} ->
            Logger.error(
              "EA NoticeProcessor: Failed to find/create offender for notice #{processed.regulator_id}: #{inspect(reason)}"
            )

            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, "Agency not found: #{processed.agency_code}"}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  # Private Functions

  defp enforcement_notice?(ea_detail_record) do
    # EaDetailRecord uses :action_type (atom), not :offence_action_type (string)
    action_type = Map.get(ea_detail_record, :action_type, :unknown)

    # Check if action type is :enforcement_notice atom
    action_type == :enforcement_notice
  end

  defp extract_environmental_data(ea_detail_record) do
    # EaDetailRecord field names from CaseScraper
    %{
      # Not :ea_event_reference
      event_reference: Map.get(ea_detail_record, :event_reference),
      impact: build_environmental_impact(ea_detail_record),
      receptor: detect_environmental_receptor(ea_detail_record),
      # Direct field from EA detail page
      legal_act: Map.get(ea_detail_record, :act),
      # Direct field from EA detail page
      legal_section: Map.get(ea_detail_record, :section),
      agency_function: Map.get(ea_detail_record, :agency_function)
    }
  end

  # Build environmental impact from water/land/air impact fields
  defp build_environmental_impact(ea_detail_record) do
    EnvironmentalHelpers.build_environmental_impact_string(
      Map.get(ea_detail_record, :water_impact),
      Map.get(ea_detail_record, :land_impact),
      Map.get(ea_detail_record, :air_impact)
    )
  end

  # Detect primary environmental receptor from impact fields
  defp detect_environmental_receptor(ea_detail_record) do
    EnvironmentalHelpers.detect_environmental_receptor(
      Map.get(ea_detail_record, :water_impact),
      Map.get(ea_detail_record, :land_impact),
      Map.get(ea_detail_record, :air_impact)
    )
  end

  @doc """
  Process EA notice with legislation deduplication.

  Creates or links to legislation records to prevent duplicates.
  Links the notice to offences that reference the legislation.
  """
  def process_notice_with_legislation_linking(ea_detail_record, actor) do
    case process_notice(ea_detail_record) do
      {:ok, processed_notice} ->
        # Extract and process legislation from the EA notice
        case process_ea_legislation(processed_notice) do
          {:ok, legislation_data} ->
            # Create notice and link to legislation
            create_notice_with_legislation_links(processed_notice, legislation_data, actor)

          {:error, reason} ->
            # Still create notice even if legislation processing fails
            Logger.warning(
              "EA legislation processing failed for notice #{processed_notice.regulator_id}: #{inspect(reason)}"
            )

            create_notice_from_processed(processed_notice, actor)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Process EA legislation from notice data.

  EA notices include legal framework information that needs to be
  processed into structured legislation records.
  """
  @spec process_ea_legislation(ProcessedEaNotice.t()) :: {:ok, map() | nil} | {:error, term()}
  def process_ea_legislation(%ProcessedEaNotice{} = processed_notice) do
    if processed_notice.legal_act do
      try do
        # Parse EA legislation components
        components = %{
          title: processed_notice.legal_act,
          section: processed_notice.legal_section,
          year: extract_year_from_ea_act(processed_notice.legal_act),
          context: %{
            environmental_impact: processed_notice.environmental_impact,
            environmental_receptor: processed_notice.environmental_receptor,
            regulator_function: processed_notice.regulator_function
          }
        }

        # Find or create the legislation record
        case find_or_create_ea_legislation(components) do
          {:ok, legislation} ->
            legislation_data = %{
              legislation: legislation,
              section: components.section,
              description: build_ea_offence_description(components, processed_notice)
            }

            {:ok, legislation_data}

          {:error, reason} ->
            {:error, {:legislation_creation_error, reason}}
        end
      rescue
        error ->
          {:error, {:processing_error, error}}
      end
    else
      # No legal act specified in EA notice
      Logger.debug("No legal act found in EA notice #{processed_notice.regulator_id}")
      {:ok, nil}
    end
  end

  defp extract_year_from_ea_act(act_title) when is_binary(act_title) do
    # EA acts typically include year in title
    # Use non-capturing group (?:...) to avoid multiple matches in result
    case Regex.run(~r/\b(?:19|20)\d{2}\b/, act_title) do
      [year_str] -> String.to_integer(year_str)
      nil -> guess_ea_act_year(act_title)
    end
  end

  defp guess_ea_act_year(act_title) do
    # Common EA legislation years
    title_lower = String.downcase(act_title)

    cond do
      String.contains?(title_lower, "environmental protection") ->
        1990

      String.contains?(title_lower, "water resources") ->
        1991

      String.contains?(title_lower, "environment") and String.contains?(title_lower, "act") ->
        1995

      String.contains?(title_lower, "pollution prevention") ->
        1999

      String.contains?(title_lower, "waste") ->
        2005

      String.contains?(title_lower, "climate change") ->
        2008

      true ->
        nil
    end
  end

  @doc """
  Find or create EA legislation using the new deduplication system.
  """
  @spec find_or_create_ea_legislation(%{title: binary(), year: nil | integer()}) ::
          {:ok, struct()}
          | {:error, binary() | struct()}
  def find_or_create_ea_legislation(%{title: title, year: year} = components) do
    Logger.debug("Processing EA legislation: #{title}")

    # Determine number from EA context if possible
    number = extract_number_from_ea_context(components)

    # Use the unified legislation system
    EhsEnforcement.Enforcement.find_or_create_legislation(
      title,
      year,
      number,
      # Let the utility determine type
      nil
    )
  end

  defp extract_number_from_ea_context(%{title: title}) do
    # EA legislation numbers are less commonly available in notices
    # This could be enhanced with a lookup table similar to HSE
    # Note: legislation_number is a string field
    case title do
      # EPA 1990 Chapter 43
      "Environmental Protection Act" <> _ -> "43"
      # WRA 1991 Chapter 57
      "Water Resources Act" <> _ -> "57"
      _ -> nil
    end
  end

  defp build_ea_offence_description(%{title: title, section: section}, processed_notice) do
    base = title
    section_part = if section, do: " - Section #{section}", else: ""

    # Include environmental context if available
    context_parts =
      [
        if processed_notice.environmental_impact &&
             processed_notice.environmental_impact != "none" do
          "Environmental Impact: #{String.capitalize(processed_notice.environmental_impact)}"
        end,
        if processed_notice.environmental_receptor do
          "Receptor: #{String.capitalize(processed_notice.environmental_receptor)}"
        end
      ]
      |> Enum.filter(& &1)

    context_suffix =
      if Enum.any?(context_parts) do
        " (#{Enum.join(context_parts, ", ")})"
      else
        ""
      end

    "#{base}#{section_part}#{context_suffix}"
  end

  defp create_notice_with_legislation_links(processed_notice, legislation_data, actor) do
    case create_notice_from_processed(processed_notice, actor) do
      {:ok, notice, status} when legislation_data != nil ->
        # Create offence record linking the notice to legislation
        case create_ea_notice_offence(notice.id, legislation_data) do
          {:ok, _offence} ->
            Logger.info("Created EA notice #{notice.regulator_id} with legislation link")
            {:ok, notice, status}

          {:error, reason} ->
            Logger.warning(
              "Failed to create legislation link for notice #{notice.regulator_id}: #{inspect(reason)}"
            )

            # Still return success for notice creation
            {:ok, notice, status}
        end

      {:ok, notice, status} ->
        # No legislation data to link
        {:ok, notice, status}

      error ->
        error
    end
  end

  defp create_ea_notice_offence(notice_id, legislation_data) do
    offence_attrs = %{
      notice_id: notice_id,
      legislation_id: legislation_data.legislation.id,
      offence_description: legislation_data.description,
      legislation_part: legislation_data.section,
      # EA notices typically have single offence
      sequence_number: 1,
      # EA notices don't typically include fines
      fine: Decimal.new("0.00")
    }

    EhsEnforcement.Enforcement.create_offence(offence_attrs)
  end

  defp parse_operative_date(_ea_detail_record) do
    # EA enforcement notices typically don't have separate operative dates
    # They become operative when issued (notice_date)
    nil
  end

  defp parse_compliance_date(_ea_detail_record) do
    # EA enforcement notices may include compliance deadlines
    # This would need to be extracted from notice text/description
    # For now, return nil - can be enhanced later
    nil
  end

  defp build_source_metadata(ea_detail_record) do
    %{
      scraped_at: DateTime.utc_now(),
      scraper_version: "1.0",
      ea_source: "environment.data.gov.uk",
      raw_data_keys: Map.keys(ea_detail_record),
      action_type: "enforcement_notice"
    }
  end

  defp build_offender_attrs(ea_detail_record) do
    OffenderBuilder.build_offender_attrs(ea_detail_record, :notice)
  end

  defp check_for_existing_notice(regulator_id, agency_id) do
    import Ash.Query

    try do
      case EhsEnforcement.Enforcement.Notice
           |> filter(regulator_id == ^regulator_id and agency_id == ^agency_id)
           |> Ash.read_one() do
        # May be nil if not found
        {:ok, notice} -> {:ok, notice}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error ->
        Logger.error("EA NoticeProcessor: Error checking for existing notice: #{inspect(error)}")
        {:error, error}
    end
  end

  defp create_new_notice(processed, agency_id, offender_id, actor) do
    notice_attrs = %{
      regulator_id: processed.regulator_id,
      notice_date: processed.notice_date,
      operative_date: processed.operative_date,
      compliance_date: processed.compliance_date,
      notice_body: processed.notice_body,
      offence_action_type: processed.offence_action_type,
      offence_action_date: processed.offence_action_date,
      offence_breaches: processed.offence_breaches,
      url: processed.regulator_url,

      # EA-specific fields
      regulator_event_reference: processed.regulator_event_reference,
      environmental_impact: processed.environmental_impact,
      environmental_receptor: processed.environmental_receptor,
      legal_act: processed.legal_act,
      legal_section: processed.legal_section,
      regulator_function: processed.regulator_function,

      # Relationships
      agency_id: agency_id,
      offender_id: offender_id
    }

    case Ash.create(EhsEnforcement.Enforcement.Notice, notice_attrs, actor: actor) do
      {:ok, notice} ->
        Logger.info("EA NoticeProcessor: Created new notice: #{notice.regulator_id}")
        {:ok, notice, :created}

      {:error, reason} ->
        Logger.error("EA NoticeProcessor: Failed to create notice: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_existing_notice(existing_notice, processed, actor) do
    # Check if any fields need updating
    updates = build_notice_updates(existing_notice, processed)

    if map_size(updates) > 0 do
      case Ash.update(existing_notice, updates, actor: actor) do
        {:ok, updated_notice} ->
          Logger.info(
            "EA NoticeProcessor: Updated existing notice: #{updated_notice.regulator_id}"
          )

          {:ok, updated_notice, :updated}

        {:error, reason} ->
          Logger.error("EA NoticeProcessor: Failed to update notice: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug(
        "EA NoticeProcessor: Notice already up to date: #{existing_notice.regulator_id}"
      )

      {:ok, existing_notice, :existing}
    end
  end

  defp build_notice_updates(existing, processed) do
    potential_updates = %{
      notice_body: processed.notice_body,
      offence_breaches: processed.offence_breaches,
      environmental_impact: processed.environmental_impact,
      environmental_receptor: processed.environmental_receptor,
      legal_act: processed.legal_act,
      legal_section: processed.legal_section,
      regulator_function: processed.regulator_function,
      url: processed.regulator_url
    }

    # Only include fields that have actually changed
    potential_updates
    |> Enum.filter(fn {field, new_value} ->
      current_value = Map.get(existing, field)
      current_value != new_value and not is_nil(new_value)
    end)
    |> Map.new()
  end
end
