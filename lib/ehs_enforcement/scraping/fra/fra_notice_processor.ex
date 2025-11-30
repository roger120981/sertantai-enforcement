defmodule EhsEnforcement.Scraping.Fra.FraNoticeProcessor do
  @moduledoc """
  FRA notice processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from NFCC format to Notice resource format
  - Offender creation/lookup with England/Wales country assignment
  - Deterministic regulator_id generation for deduplication (using UPRN)
  - Mapping of FRA notice types to offence_action_type

  Fire & Rescue notice types under RRO 2005:
  - Prohibition Notice (Article 31) - prohibits use until resolved
  - Enforcement Notice (Article 30) - requires improvements
  - Alterations Notice (Article 29) - requires notification of changes
  """

  require Logger

  alias EhsEnforcement.Scraping.Fra.FraNoticeScraper.ScrapedNotice
  alias EhsEnforcement.Scraping.Shared.DateParser

  @fra_agency_code :fra

  defmodule ProcessedNotice do
    @moduledoc "Struct representing a notice ready for Ash Notice resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :notice_date,
      :notice_body,
      :offence_action_type,
      :offence_breaches,
      :url,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped notice into format ready for Ash Notice resource creation.

  Returns {:ok, %ProcessedNotice{}} or {:error, reason}
  """
  def process_notice(%ScrapedNotice{} = notice) do
    Logger.debug("FRA: Processing notice for #{notice.responsible_person} at #{notice.address}")

    try do
      # Generate deterministic regulator_id using UPRN for deduplication
      regulator_id = generate_regulator_id(notice)

      processed = %ProcessedNotice{
        regulator_id: regulator_id,
        agency_code: @fra_agency_code,
        offender_attrs: build_offender_attrs(notice),
        notice_date: parse_date(notice.issue_date),
        notice_body: build_notice_body(notice),
        offence_action_type: map_notice_type(notice.notice_type),
        offence_breaches: notice.additional_information,
        url: "https://nfcc.org.uk/our-services/enforcement-register/",
        source_metadata: build_source_metadata(notice)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("FRA: Failed to process notice: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped notices in batch.

  Returns {:ok, [%ProcessedNotice{}]} or {:ok, [%ProcessedNotice{}], errors: [...]}
  """
  def process_notices(scraped_notices) when is_list(scraped_notices) do
    Logger.info("FRA: Processing #{length(scraped_notices)} scraped notices")

    {processed, errors} =
      Enum.reduce(scraped_notices, {[], []}, fn notice, {proc_acc, err_acc} ->
        case process_notice(notice) do
          {:ok, processed_notice} ->
            {[processed_notice | proc_acc], err_acc}

          {:error, reason} ->
            identifier = "#{notice.responsible_person}@#{notice.uprn}"
            {proc_acc, [{identifier, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("FRA: Successfully processed all #{length(processed_list)} notices")
      {:ok, processed_list}
    else
      Logger.warning(
        "FRA: Processed #{length(processed_list)} notices with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Process and create a single notice using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def process_and_create_notice(%ScrapedNotice{} = notice, actor) do
    case process_notice(notice) do
      {:ok, processed} ->
        create_notice_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a Notice from processed data using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def create_notice_from_processed(%ProcessedNotice{} = processed, actor) do
    Logger.debug("FRA: Creating notice from processed data: #{processed.regulator_id}")

    # Get FRA agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender
        case EhsEnforcement.Enforcement.Offender.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Create notice using Ash
            notice_attrs = %{
              regulator_id: processed.regulator_id,
              notice_date: processed.notice_date,
              notice_body: processed.notice_body,
              offence_action_type: processed.offence_action_type,
              offence_breaches: processed.offence_breaches,
              url: processed.url,
              agency_id: agency.id,
              offender_id: offender.id,
              last_synced_at: DateTime.utc_now()
            }

            EhsEnforcement.Enforcement.Notice
            |> Ash.Changeset.for_create(:create, notice_attrs)
            |> Ash.create(actor: actor)

          {:error, reason} ->
            Logger.error("FRA: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, "Agency not found: #{processed.agency_code}"}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  # Private Functions

  defp generate_regulator_id(notice) do
    # Use UPRN as primary identifier - it's unique per property
    # Format: fra_{UPRN}_{YYYYMMDD}_{notice_type_initial}
    # This allows multiple notices for the same property on different dates

    uprn_part = notice.uprn || "unknown"

    date_part =
      case parse_date(notice.issue_date) do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    type_initial =
      case String.upcase(notice.notice_type || "") do
        "PROHIBITION" -> "P"
        "ENFORCEMENT" -> "E"
        "ALTERATIONS" -> "A"
        _ -> "X"
      end

    "fra_#{uprn_part}_#{date_part}_#{type_initial}"
  end

  defp build_offender_attrs(notice) do
    # Extract postcode from address
    postcode = extract_postcode(notice.address)

    # Determine country based on FRS (Fire & Rescue Service) name
    # Welsh FRAs: Mid and West Wales, North Wales, South Wales
    country = determine_country(notice.frs)

    %{
      name: notice.responsible_person || "[Unknown Responsible Person]",
      address: notice.address,
      postcode: postcode,
      country: country
    }
  end

  defp determine_country(nil), do: "England"

  defp determine_country(frs) do
    welsh_frs = [
      "Mid and West Wales",
      "North Wales",
      "South Wales"
    ]

    if Enum.any?(welsh_frs, &String.contains?(String.downcase(frs), String.downcase(&1))) do
      "Wales"
    else
      "England"
    end
  end

  defp extract_postcode(nil), do: nil

  defp extract_postcode(address) do
    # UK postcode pattern at end of address
    case Regex.run(~r/([A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2})\s*$/i, address) do
      [_, postcode] -> String.upcase(postcode) |> String.trim()
      _ -> nil
    end
  end

  defp build_notice_body(notice) do
    # Combine reasons and status into notice body
    parts =
      [
        notice.reasons,
        if(notice.status, do: "[Status: #{notice.status}]"),
        if(notice.premises_type, do: "[Premises: #{notice.premises_type}]")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      _ -> Enum.join(parts, "\n\n")
    end
  end

  defp map_notice_type(nil), do: "FRA Notice"

  defp map_notice_type(type) do
    case String.upcase(type) do
      "PROHIBITION" -> "FRA Prohibition Notice"
      "ENFORCEMENT" -> "FRA Enforcement Notice"
      "ALTERATIONS" -> "FRA Alterations Notice"
      other -> "FRA #{other} Notice"
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    # NFCC date format: "DD/MM/YYYY" e.g., "06/11/2025"
    case DateParser.parse_date(date_string) do
      %Date{} = date ->
        date

      nil ->
        # Try parsing DD/MM/YYYY directly
        case Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, date_string) do
          [_, day, month, year] ->
            case Date.new(
                   String.to_integer(year),
                   String.to_integer(month),
                   String.to_integer(day)
                 ) do
              {:ok, date} -> date
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  defp build_source_metadata(notice) do
    %{
      scraped_at: notice.scrape_timestamp,
      scraper_version: "1.0",
      source: "nfcc.org.uk",
      uprn: notice.uprn,
      frs: notice.frs,
      premises_type: notice.premises_type,
      status: notice.status,
      date_complied_with: notice.date_complied_with
    }
  end
end
