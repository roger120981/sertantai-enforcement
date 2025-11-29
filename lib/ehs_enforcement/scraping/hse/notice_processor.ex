defmodule EhsEnforcement.Scraping.Hse.NoticeProcessor do
  @moduledoc """
  HSE notice processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from HSE format to Ash resource format
  - Notice detail enrichment using HSE APIs
  - Integration with existing OffenderMatcher for offender matching/creation
  - Validation and error handling following Ash patterns
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Agencies.Hse.OffenderBuilder
  alias EhsEnforcement.Scraping.Hse.NoticeScraper
  alias EhsEnforcement.Scraping.Shared.DateParser

  @hse_agency_code :hse

  defmodule ProcessedNotice do
    @moduledoc "Struct representing a notice ready for Ash resource creation"

    @derive Jason.Encoder
    defstruct [
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
      :regulator_function,
      :regulator_url,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped notice into format ready for Ash resource creation.

  Returns {:ok, %ProcessedNotice{}} or {:error, reason}
  """
  def process_notice(basic_notice) when is_map(basic_notice) do
    Logger.debug("Processing scraped notice: #{basic_notice.regulator_id}")

    try do
      # Enrich notice with details if regulator_id exists
      enriched_notice =
        case basic_notice.regulator_id do
          nil ->
            basic_notice

          "" ->
            basic_notice

          regulator_id ->
            case NoticeScraper.get_notice_details(regulator_id) do
              details when is_map(details) -> Map.merge(basic_notice, details)
              _ -> basic_notice
            end
        end

      # Get breach details if available
      enriched_notice_with_breaches =
        case enriched_notice.regulator_id do
          nil ->
            enriched_notice

          "" ->
            enriched_notice

          regulator_id ->
            case NoticeScraper.get_notice_breaches(regulator_id) do
              %{offence_breaches: breaches} when is_list(breaches) ->
                Map.put(enriched_notice, :offence_breaches, breaches)

              _ ->
                enriched_notice
            end
        end

      processed = %ProcessedNotice{
        regulator_id: enriched_notice_with_breaches.regulator_id,
        agency_code: @hse_agency_code,
        offender_attrs: build_offender_attrs(enriched_notice_with_breaches),
        notice_date: parse_date(enriched_notice_with_breaches[:notice_date]),
        operative_date: parse_date(enriched_notice_with_breaches[:operative_date]),
        compliance_date: parse_date(enriched_notice_with_breaches[:offence_compliance_date]),
        notice_body: enriched_notice_with_breaches[:offence_description],
        offence_action_type: enriched_notice_with_breaches.offence_action_type,
        offence_action_date: enriched_notice_with_breaches.offence_action_date,
        offence_breaches: format_breaches(enriched_notice_with_breaches[:offence_breaches]),
        regulator_function: enriched_notice_with_breaches[:regulator_function],
        regulator_url: build_regulator_url(enriched_notice_with_breaches.regulator_id),
        source_metadata: build_source_metadata(enriched_notice_with_breaches)
      }

      Logger.debug("Successfully processed notice: #{enriched_notice_with_breaches.regulator_id}")
      {:ok, processed}
    rescue
      error ->
        Logger.error("Failed to process notice #{basic_notice.regulator_id}: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped notices in batch.

  Returns {:ok, [%ProcessedNotice{}]} or {:error, reason}
  """
  def process_notices(scraped_notices) when is_list(scraped_notices) do
    Logger.info("Processing #{length(scraped_notices)} scraped notices")

    results =
      Enum.reduce(scraped_notices, {[], []}, fn notice, {processed, errors} ->
        case process_notice(notice) do
          {:ok, processed_notice} -> {[processed_notice | processed], errors}
          {:error, reason} -> {processed, [{notice.regulator_id, reason} | errors]}
        end
      end)

    case results do
      {processed_notices, []} ->
        Logger.info("Successfully processed all #{length(processed_notices)} notices")
        {:ok, Enum.reverse(processed_notices)}

      {processed_notices, errors} ->
        Logger.warning(
          "Processed #{length(processed_notices)} notices with #{length(errors)} errors"
        )

        {:ok, Enum.reverse(processed_notices), errors: errors}
    end
  end

  @doc """
  Process and create a single notice directly using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def process_and_create_notice(basic_notice, actor) do
    case process_notice(basic_notice) do
      {:ok, processed_notice} ->
        create_notice_from_processed(processed_notice, actor)

      {:error, reason} ->
        Logger.error("Failed to process notice #{basic_notice.regulator_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Create a notice from processed data using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def create_notice_from_processed(%ProcessedNotice{} = processed, actor) do
    Logger.debug("Creating notice from processed data: #{processed.regulator_id}")

    # Get HSE agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender
        case EhsEnforcement.Enforcement.Offender.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Create notice using Ash
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
              agency_id: agency.id,
              offender_id: offender.id
            }

            EhsEnforcement.Enforcement.Notice
            |> Ash.Changeset.for_create(:create, notice_attrs)
            |> Ash.create(actor: actor)

          {:error, reason} ->
            Logger.error(
              "Failed to find/create offender for notice #{processed.regulator_id}: #{inspect(reason)}"
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

  defp build_offender_attrs(notice_data) do
    base_attrs = OffenderBuilder.build_offender_attrs(notice_data, :notice)

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

  defp build_regulator_url(regulator_id) when is_binary(regulator_id) do
    "https://resources.hse.gov.uk/notices/notices/notice_details.asp?SF=CN&SV=#{regulator_id}"
  end

  defp build_regulator_url(_), do: nil

  defp build_source_metadata(notice_data) do
    %{
      scraped_at: DateTime.utc_now(),
      scraper_version: "1.0",
      hse_source: "notices.hse.gov.uk",
      raw_data_keys: Map.keys(notice_data)
    }
  end

  defp parse_date(date) do
    DateParser.parse_date(date)
  end

  defp format_breaches(nil), do: nil
  defp format_breaches([]), do: nil

  defp format_breaches(breaches) when is_list(breaches) do
    breaches
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      formatted -> Enum.join(formatted, "; ")
    end
  end

  defp format_breaches(breach) when is_binary(breach) do
    case String.trim(breach) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
