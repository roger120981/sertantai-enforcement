defmodule EhsEnforcement.Scraping.Caa.CaaAiCaseProcessor do
  @moduledoc """
  Processes AI-parsed CAA prosecution cases and creates database records.

  Transforms `CaaAiPdfParser.ParsedProsecution` structs into Ash resource records,
  handling the creation of:
  - Case records
  - Offender records (with lookup/create)

  This module works with the AI-parsed legacy format prosecutions (2017-2022)
  that cannot be parsed with regex due to their spatial table layout.

  ## Usage

      alias EhsEnforcement.Scraping.Caa.{CaaAiPdfParser, CaaAiCaseProcessor}

      {:ok, parsed_prosecutions} = CaaAiPdfParser.parse_pdf_text(text, "2021-2022")
      {:ok, results} = CaaAiCaseProcessor.process_prosecutions(parsed_prosecutions, actor)

  ## Deduplication

  Uses deterministic `regulator_id` format: `caa_ai_{fiscal_year}_{defendant_slug}_{date}`
  This allows detection of already-imported prosecutions.
  """

  require Logger

  alias EhsEnforcement.Scraping.Caa.CaaAiPdfParser.ParsedProsecution

  @caa_agency_code :caa

  @doc """
  Process an AI-parsed prosecution and create database records.

  Creates Case and Offender records from a ParsedProsecution struct.

  Returns {:ok, case_record}, {:ok, :duplicate}, or {:error, reason}
  """
  def process_and_create_case(%ParsedProsecution{} = parsed, actor \\ nil) do
    Logger.debug("CAA AI Processor: Processing case for #{parsed.defendant_name}")

    case EhsEnforcement.Enforcement.get_agency_by_code(@caa_agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        create_case_with_offender(parsed, agency, actor)

      {:ok, nil} ->
        Logger.error("CAA AI Processor: Agency not found: #{@caa_agency_code}")
        {:error, {:agency_not_found, @caa_agency_code}}

      {:error, reason} ->
        Logger.error("CAA AI Processor: Failed to get agency: #{inspect(reason)}")
        {:error, {:agency_error, reason}}
    end
  end

  @doc """
  Process multiple AI-parsed prosecutions.

  Returns {:ok, %{created: [...], duplicates: [...], errors: [...]}}
  """
  def process_prosecutions(parsed_prosecutions, actor \\ nil)
      when is_list(parsed_prosecutions) do
    Logger.info(
      "CAA AI Processor: Processing #{length(parsed_prosecutions)} AI-parsed prosecutions"
    )

    results =
      Enum.reduce(
        parsed_prosecutions,
        %{created: [], duplicates: [], errors: []},
        fn parsed, acc ->
          case process_and_create_case(parsed, actor) do
            {:ok, :duplicate} ->
              %{acc | duplicates: [parsed | acc.duplicates]}

            {:ok, case_record} ->
              %{acc | created: [case_record | acc.created]}

            {:error, reason} ->
              Logger.warning(
                "CAA AI Processor: Error processing #{parsed.defendant_name}: #{inspect(reason)}"
              )

              %{acc | errors: [{parsed, reason} | acc.errors]}
          end
        end
      )

    Logger.info(
      "CAA AI Processor: Created #{length(results.created)}, " <>
        "duplicates #{length(results.duplicates)}, " <>
        "errors #{length(results.errors)}"
    )

    {:ok, results}
  end

  # Private functions

  defp create_case_with_offender(%ParsedProsecution{} = parsed, agency, actor) do
    offender_attrs = build_offender_attrs(parsed)

    case EhsEnforcement.Enforcement.Offender.find_or_create_offender(offender_attrs) do
      {:ok, offender} ->
        create_case(parsed, agency, offender, actor)

      {:error, reason} ->
        Logger.error("CAA AI Processor: Failed to find/create offender: #{inspect(reason)}")
        {:error, {:offender_error, reason}}
    end
  end

  defp create_case(%ParsedProsecution{} = parsed, agency, offender, actor) do
    regulator_id = generate_regulator_id(parsed)

    Logger.debug("CAA AI Processor: Creating case: #{regulator_id}")

    case_attrs = %{
      regulator_id: regulator_id,
      agency_id: agency.id,
      offender_id: offender.id,
      offence_hearing_date: parsed.hearing_date,
      offence_action_date: parsed.hearing_date,
      offence_fine: parsed.fine_amount,
      offence_costs: nil,
      offence_result: build_offence_result(parsed),
      offence_breaches: build_offence_breaches(parsed),
      offence_action_type: "CAA Prosecution",
      url: build_source_url(),
      last_synced_at: DateTime.utc_now()
    }

    case EhsEnforcement.Enforcement.Case
         |> Ash.Changeset.for_create(:create, case_attrs)
         |> Ash.create(actor: actor) do
      {:ok, created_case} ->
        Logger.info("CAA AI Processor: Created case: #{regulator_id}")
        {:ok, created_case}

      {:error, %Ash.Error.Invalid{} = ash_error} ->
        if duplicate_error?(ash_error) do
          Logger.debug("CAA AI Processor: Case already exists: #{regulator_id}")
          {:ok, :duplicate}
        else
          Logger.error("CAA AI Processor: Failed to create case: #{inspect(ash_error)}")
          {:error, ash_error}
        end

      {:error, reason} ->
        Logger.error("CAA AI Processor: Failed to create case: #{inspect(reason)}")
        {:error, {:case_creation_error, reason}}
    end
  end

  @doc """
  Generate a deterministic regulator_id for deduplication.

  Format: caa_ai_{fiscal_year}_{defendant_slug}_{date}

  The 'ai' prefix distinguishes these from regex-parsed prosecutions.
  """
  def generate_regulator_id(%ParsedProsecution{} = parsed) do
    fiscal_year =
      (parsed.fiscal_year || "unknown")
      |> String.replace("-", "")

    defendant_slug =
      (parsed.defendant_name || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 40)
      |> String.trim("_")

    date_part =
      case parsed.hearing_date do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    "caa_ai_#{fiscal_year}_#{defendant_slug}_#{date_part}"
  end

  defp build_offender_attrs(%ParsedProsecution{} = parsed) do
    %{
      name: parsed.defendant_name || "[Unknown Defendant]",
      country: "United Kingdom"
    }
  end

  defp build_offence_result(%ParsedProsecution{} = parsed) do
    parts = []

    # Add offence description
    parts =
      if parsed.offence_description && String.length(parsed.offence_description) > 0 do
        [parsed.offence_description | parts]
      else
        parts
      end

    # Add sentence/outcome
    parts =
      if parsed.offence_outcome && String.length(parsed.offence_outcome) > 0 do
        ["Outcome: #{parsed.offence_outcome}" | parts]
      else
        # Build sentence from individual components
        sentence = build_sentence_text(parsed)

        if String.length(sentence) > 0 do
          ["Sentence: #{sentence}" | parts]
        else
          parts
        end
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp build_sentence_text(%ParsedProsecution{} = parsed) do
    sentence_parts = []

    # Fine
    sentence_parts =
      if parsed.fine_amount do
        ["Fine £#{Decimal.to_string(parsed.fine_amount)}" | sentence_parts]
      else
        sentence_parts
      end

    # Imprisonment
    sentence_parts =
      if parsed.imprisonment_months do
        months = parsed.imprisonment_months
        term = if months == 1, do: "month", else: "months"
        imprisonment = "#{months} #{term} imprisonment"

        imprisonment =
          if parsed.suspended_months do
            suspended_term = if parsed.suspended_months == 1, do: "month", else: "months"
            "#{imprisonment}, suspended for #{parsed.suspended_months} #{suspended_term}"
          else
            imprisonment
          end

        [imprisonment | sentence_parts]
      else
        sentence_parts
      end

    # Community order
    sentence_parts =
      if parsed.community_order_months do
        months = parsed.community_order_months
        term = if months == 1, do: "month", else: "months"
        ["Community order #{months} #{term}" | sentence_parts]
      else
        sentence_parts
      end

    # Unpaid work
    sentence_parts =
      if parsed.unpaid_work_hours do
        hours = parsed.unpaid_work_hours
        term = if hours == 1, do: "hour", else: "hours"
        ["#{hours} #{term} unpaid work" | sentence_parts]
      else
        sentence_parts
      end

    sentence_parts
    |> Enum.reverse()
    |> Enum.join("; ")
  end

  defp build_offence_breaches(%ParsedProsecution{} = parsed) do
    parts = []

    # Add court
    parts =
      if parsed.court_name && String.length(parsed.court_name) > 0 do
        ["Court: #{parsed.court_name}" | parts]
      else
        parts
      end

    # Add legislation
    parts =
      if parsed.legislation && length(parsed.legislation) > 0 do
        legislation_text =
          parsed.legislation
          |> Enum.join(", ")

        ["Legislation: #{legislation_text}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp build_source_url do
    "https://www.caa.co.uk/our-work/about-us/enforcement/enforcement-and-prosecutions/"
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
