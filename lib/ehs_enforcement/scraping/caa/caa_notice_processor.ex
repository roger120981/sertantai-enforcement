defmodule EhsEnforcement.Scraping.Caa.CaaNoticeProcessor do
  @moduledoc """
  CAA undertaking processing pipeline - transforms scraped data for Ash Notice resource creation.

  Handles:
  - Data transformation from CAA HTML format to Notice resource format
  - Offender creation/lookup
  - Deterministic regulator_id generation for deduplication

  ## Data Flow

  ```
  ScrapedUndertaking
    → ProcessedUndertaking
      → Notice (with Offender, Agency)
  ```

  ## Legislation Mapping

  Common CAA undertaking legislation:
  - Regulation 261/2004 (EU261/UK261) - Passenger rights for delays/cancellations
  - Regulation 1107/2006 - Disabled persons and reduced mobility access
  - Consumer Protection from Unfair Trading Regulations 2008

  ## Legal Note

  Undertakings are provided voluntarily without admission of wrongdoing.
  Only a court can decide whether a breach has occurred.
  """

  require Logger

  alias EhsEnforcement.Scraping.Caa.CaaUndertakingScraper.ScrapedUndertaking

  @caa_agency_code :caa

  defmodule ProcessedUndertaking do
    @moduledoc "Struct representing an undertaking ready for Ash Notice resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :notice_date,
      :notice_body,
      :offence_breaches,
      :offence_action_type,
      :url,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped undertaking into format ready for Ash Notice resource creation.

  Returns {:ok, %ProcessedUndertaking{}} or {:error, reason}
  """
  def process_undertaking(%ScrapedUndertaking{} = undertaking) do
    Logger.debug("CAA: Processing undertaking for #{undertaking.organisation}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(undertaking)

      # Build notice body (commitments + comments)
      notice_body = build_notice_body(undertaking)

      # Build offence breaches (legislation)
      offence_breaches = build_offence_breaches(undertaking)

      processed = %ProcessedUndertaking{
        regulator_id: regulator_id,
        agency_code: @caa_agency_code,
        offender_attrs: build_offender_attrs(undertaking),
        notice_date: undertaking.date_provided,
        notice_body: notice_body,
        offence_breaches: offence_breaches,
        offence_action_type: "CAA Undertaking",
        url: build_source_url(),
        source_metadata: build_source_metadata(undertaking)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("CAA: Failed to process undertaking: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped undertakings in batch.

  Returns {:ok, [%ProcessedUndertaking{}]} or {:ok, [%ProcessedUndertaking{}], errors: [...]}
  """
  def process_undertakings(scraped_undertakings) when is_list(scraped_undertakings) do
    Logger.info("CAA: Processing #{length(scraped_undertakings)} scraped undertakings")

    {processed, errors} =
      Enum.reduce(scraped_undertakings, {[], []}, fn undertaking, {proc_acc, err_acc} ->
        case process_undertaking(undertaking) do
          {:ok, processed_undertaking} ->
            {[processed_undertaking | proc_acc], err_acc}

          {:error, reason} ->
            identifier = "#{undertaking.organisation}@#{undertaking.date_provided}"
            {proc_acc, [{identifier, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("CAA: Successfully processed all #{length(processed_list)} undertakings")
      {:ok, processed_list}
    else
      Logger.warning(
        "CAA: Processed #{length(processed_list)} undertakings with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Create a Notice from processed data using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def create_notice_from_processed(%ProcessedUndertaking{} = processed, actor) do
    Logger.debug("CAA: Creating notice from processed data: #{processed.regulator_id}")

    # Get CAA agency
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
              offence_breaches: processed.offence_breaches,
              offence_action_type: processed.offence_action_type,
              offence_action_date: processed.notice_date,
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
                  Logger.debug("CAA: Notice already exists: #{processed.regulator_id}")
                  {:ok, :duplicate}
                else
                  Logger.error("CAA: Failed to create notice: #{inspect(ash_error)}")
                  {:error, ash_error}
                end

              {:error, reason} ->
                Logger.error("CAA: Failed to create notice: #{inspect(reason)}")
                {:error, {:notice_creation_error, reason}}
            end

          {:error, reason} ->
            Logger.error("CAA: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, {:agency_not_found, processed.agency_code}}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  @doc """
  Process and create a single undertaking as a Notice using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def process_and_create_undertaking(%ScrapedUndertaking{} = undertaking, actor) do
    case process_undertaking(undertaking) do
      {:ok, processed} ->
        create_notice_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Process and create all undertakings from scraped data.

  Returns {:ok, %{created: count, duplicates: count, errors: count}}
  """
  def process_and_create_all(scraped_undertakings, actor) when is_list(scraped_undertakings) do
    Logger.info("CAA: Processing and creating #{length(scraped_undertakings)} undertakings")

    results =
      Enum.reduce(scraped_undertakings, %{created: 0, duplicates: 0, errors: []}, fn undertaking,
                                                                                     acc ->
        case process_and_create_undertaking(undertaking, actor) do
          {:ok, :duplicate} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _notice} ->
            %{acc | created: acc.created + 1}

          {:error, reason} ->
            identifier = "#{undertaking.organisation}@#{undertaking.date_provided}"
            %{acc | errors: [{identifier, reason} | acc.errors]}
        end
      end)

    Logger.info(
      "CAA: Created #{results.created}, duplicates #{results.duplicates}, errors #{length(results.errors)}"
    )

    {:ok, results}
  end

  # Private Functions

  defp generate_regulator_id(undertaking) do
    # Format: caa_undertaking_{date}_{org_slug}
    # Deterministic for deduplication

    date_part =
      case undertaking.date_provided do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    org_slug =
      (undertaking.organisation || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 40)
      |> String.trim("_")

    "caa_undertaking_#{date_part}_#{org_slug}"
  end

  defp build_offender_attrs(undertaking) do
    %{
      name: undertaking.organisation || "[Unknown Organisation]",
      country: "United Kingdom"
    }
  end

  defp build_notice_body(undertaking) do
    parts = []

    # Add commitments
    parts =
      if undertaking.commitments && String.length(undertaking.commitments) > 0 do
        ["COMMITMENTS:\n\n#{undertaking.commitments}" | parts]
      else
        parts
      end

    # Add comments if present
    parts =
      if undertaking.comments && String.length(undertaking.comments) > 0 do
        ["COMMENTS:\n\n#{undertaking.comments}" | parts]
      else
        parts
      end

    # Add legal disclaimer
    parts = [
      "Note: This undertaking was provided voluntarily without admission of wrongdoing. Only a court can decide whether a breach has occurred."
      | parts
    ]

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n---\n\n")
    |> String.trim()
  end

  defp build_offence_breaches(undertaking) do
    if undertaking.legislation && String.length(undertaking.legislation) > 0 do
      "Legislation: #{undertaking.legislation}"
    else
      nil
    end
  end

  defp build_source_url do
    "https://www.caa.co.uk/our-work/about-us/enforcement/table-of-undertakings/"
  end

  defp build_source_metadata(undertaking) do
    %{
      scraped_at: undertaking.scrape_timestamp,
      scraper_version: "1.0",
      source: "caa.co.uk",
      organisation: undertaking.organisation,
      date_provided_raw: undertaking.date_provided_raw,
      legislation: undertaking.legislation
    }
  end

  defp duplicate_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn error ->
      case error do
        %Ash.Error.Changes.InvalidChanges{message: msg} ->
          String.contains?(msg || "", "already exists")

        %{message: msg} when is_binary(msg) ->
          String.contains?(msg, "already exists") or
            String.contains?(msg, "has already been taken")

        _ ->
          false
      end
    end)
  end

  defp duplicate_error?(_), do: false
end
