defmodule EhsEnforcement.Scraping.Orr.OrrNoticeProcessor do
  @moduledoc """
  ORR notice processing pipeline - transforms scraped notices for Ash Notice resource creation.

  Handles:
  - Data transformation from ORR website format to Notice resource format
  - Offender creation/lookup
  - Deterministic regulator_id generation for deduplication

  ## Data Flow

  ```
  ScrapedNotice
    → ProcessedNotice
      → Notice (with Offender, Agency)
  ```

  ## Notice Types

  - **Improvement Notices**: Require specific safety improvements within a timeframe
  - **Prohibition Notices**: Prohibit activities until safety issues are resolved
  """

  require Logger

  alias EhsEnforcement.Scraping.Orr.OrrNoticeScraper.ScrapedNotice

  @orr_agency_code :orr

  defmodule ProcessedNotice do
    @moduledoc "Struct representing a notice ready for Ash Notice resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :notice_date,
      :compliance_date,
      :notice_body,
      :offence_action_type,
      :offence_action_date,
      :notice_status,
      :url,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped notice into format ready for Ash Notice resource creation.

  Returns {:ok, %ProcessedNotice{}} or {:error, reason}
  """
  def process_notice(%ScrapedNotice{} = notice) do
    Logger.debug("ORR: Processing #{notice.notice_type} notice for #{notice.company}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(notice)

      # Parse dates
      issue_date = parse_date(notice.issue_date)
      compliance_date = parse_date(notice.compliance_date)

      # Map notice type to action type string
      action_type = map_notice_type(notice.notice_type)

      # Map status to atom
      notice_status = map_status(notice.status)

      # Build notice body from description
      notice_body = build_notice_body(notice)

      processed = %ProcessedNotice{
        regulator_id: regulator_id,
        agency_code: @orr_agency_code,
        offender_attrs: build_offender_attrs(notice),
        notice_date: issue_date,
        compliance_date: compliance_date,
        notice_body: notice_body,
        offence_action_type: action_type,
        offence_action_date: issue_date,
        notice_status: notice_status,
        url: build_source_url(notice),
        source_metadata: build_source_metadata(notice)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("ORR: Failed to process notice: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped notices in batch.

  Returns {:ok, [%ProcessedNotice{}]} or {:ok, [%ProcessedNotice{}], errors: [...]}
  """
  def process_notices(scraped_notices) when is_list(scraped_notices) do
    Logger.info("ORR: Processing #{length(scraped_notices)} scraped notices")

    {processed, errors} =
      Enum.reduce(scraped_notices, {[], []}, fn notice, {proc_acc, err_acc} ->
        case process_notice(notice) do
          {:ok, processed_notice} ->
            {[processed_notice | proc_acc], err_acc}

          {:error, reason} ->
            identifier = "#{notice.notice_type}:#{notice.company}@#{notice.year}"
            {proc_acc, [{identifier, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("ORR: Successfully processed all #{length(processed_list)} notices")
      {:ok, processed_list}
    else
      Logger.warning(
        "ORR: Processed #{length(processed_list)} notices with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Create a Notice from processed data using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def create_notice_from_processed(%ProcessedNotice{} = processed, actor) do
    Logger.debug("ORR: Creating notice from processed data: #{processed.regulator_id}")

    # Get ORR agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender
        case EhsEnforcement.Enforcement.Offender.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Create notice using Ash
            notice_attrs = %{
              regulator_id: processed.regulator_id,
              notice_date: processed.notice_date,
              compliance_date: processed.compliance_date,
              notice_body: processed.notice_body,
              offence_action_type: processed.offence_action_type,
              offence_action_date: processed.offence_action_date,
              notice_status: processed.notice_status,
              url: processed.url,
              agency_id: agency.id,
              offender_id: offender.id,
              last_synced_at: DateTime.utc_now()
            }

            case EhsEnforcement.Enforcement.Notice
                 |> Ash.Changeset.for_create(:create, notice_attrs)
                 |> Ash.create(actor: actor) do
              {:ok, created_notice} ->
                {:ok, created_notice}

              {:error, %Ash.Error.Invalid{} = ash_error} ->
                # Check if it's a duplicate
                if duplicate_error?(ash_error) do
                  Logger.debug("ORR: Notice already exists: #{processed.regulator_id}")
                  {:ok, :duplicate}
                else
                  Logger.error("ORR: Failed to create notice: #{inspect(ash_error)}")
                  {:error, ash_error}
                end

              {:error, reason} ->
                Logger.error("ORR: Failed to create notice: #{inspect(reason)}")
                {:error, {:notice_creation_error, reason}}
            end

          {:error, reason} ->
            Logger.error("ORR: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, {:agency_not_found, processed.agency_code}}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
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
  Process and create all notices from scraped data.

  Returns {:ok, %{created: count, duplicates: count, errors: count}}
  """
  def process_and_create_all(scraped_notices, actor) when is_list(scraped_notices) do
    Logger.info("ORR: Processing and creating #{length(scraped_notices)} notices")

    results =
      Enum.reduce(scraped_notices, %{created: 0, duplicates: 0, errors: []}, fn notice, acc ->
        case process_and_create_notice(notice, actor) do
          {:ok, :duplicate} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _notice} ->
            %{acc | created: acc.created + 1}

          {:error, reason} ->
            identifier = "#{notice.notice_type}:#{notice.company}@#{notice.year}"
            %{acc | errors: [{identifier, reason} | acc.errors]}
        end
      end)

    Logger.info(
      "ORR: Created #{results.created}, duplicates #{results.duplicates}, errors #{length(results.errors)}"
    )

    {:ok, results}
  end

  # Private Functions

  defp generate_regulator_id(notice) do
    # Use reference if available, otherwise generate from components
    # Format: orr_{type}_{reference} or orr_{type}_{year}_{company_slug}_{issue_date}

    type_prefix =
      case notice.notice_type do
        :improvement -> "imp"
        :prohibition -> "proh"
        _ -> "notice"
      end

    if notice.reference && String.length(notice.reference) > 0 do
      # Clean the reference for use as ID
      ref_slug =
        notice.reference
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "_")
        |> String.trim("_")

      "orr_#{type_prefix}_#{ref_slug}"
    else
      # Generate from components
      year = notice.year || 0

      company_slug =
        (notice.company || "unknown")
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "_")
        |> String.slice(0, 30)
        |> String.trim("_")

      date_part =
        case parse_date(notice.issue_date) do
          %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
          _ -> "00000000"
        end

      "orr_#{type_prefix}_#{year}_#{company_slug}_#{date_part}"
    end
  end

  defp build_offender_attrs(notice) do
    %{
      name: notice.company || "[Unknown Company]",
      country: "United Kingdom"
    }
  end

  defp map_notice_type(:improvement), do: "ORR Improvement Notice"
  defp map_notice_type(:prohibition), do: "ORR Prohibition Notice"
  defp map_notice_type(_), do: "ORR Notice"

  defp map_status(nil), do: nil
  defp map_status("Complied"), do: :complied
  defp map_status("Open"), do: :in_force
  defp map_status("In Force"), do: :in_force
  defp map_status("Withdrawn"), do: :withdrawn
  defp map_status(_), do: nil

  defp build_notice_body(notice) do
    parts = []

    # Add reference
    parts =
      if notice.reference && String.length(notice.reference) > 0 do
        ["Reference: #{notice.reference}" | parts]
      else
        parts
      end

    # Add description
    parts =
      if notice.description && String.length(notice.description) > 0 do
        [notice.description | parts]
      else
        parts
      end

    # Add status
    parts =
      if notice.status && String.length(notice.status) > 0 do
        ["Status: #{notice.status}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp build_source_url(notice) do
    type_str =
      case notice.notice_type do
        :improvement -> "improvement-notices"
        :prohibition -> "prohibition-notices"
        _ -> "improvement-notices"
      end

    year = notice.year || DateTime.utc_now().year

    "https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/#{type_str}/#{year}"
  end

  defp build_source_metadata(notice) do
    %{
      scraped_at: notice.scrape_timestamp,
      scraper_version: "1.0",
      source: "orr.gov.uk",
      notice_type: notice.notice_type,
      year: notice.year,
      company: notice.company,
      reference: notice.reference,
      pdf_url: notice.pdf_url
    }
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    # Common formats:
    # "3 October 2025"
    # "14 February 2025"

    # Clean up ordinal suffixes
    cleaned =
      date_string
      |> String.replace(~r/(\d+)(?:st|nd|rd|th)/, "\\1")
      |> String.trim()

    # Try to parse "DD Month YYYY"
    case Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})/, cleaned) do
      [_, day, month, year] ->
        month_num = month_to_number(month)

        if month_num do
          case Date.new(
                 String.to_integer(year),
                 month_num,
                 String.to_integer(day)
               ) do
            {:ok, date} -> date
            _ -> nil
          end
        else
          nil
        end

      nil ->
        nil
    end
  end

  defp parse_date(_), do: nil

  defp month_to_number(month) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12
    }

    Map.get(months, String.downcase(month))
  end

  defp duplicate_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn error ->
      case error do
        %Ash.Error.Changes.InvalidChanges{message: msg} ->
          String.contains?(msg || "", "already exists")

        _ ->
          false
      end
    end)
  end

  defp duplicate_error?(_), do: false
end
