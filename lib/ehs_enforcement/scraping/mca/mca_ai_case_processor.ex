defmodule EhsEnforcement.Scraping.Mca.McaAiCaseProcessor do
  @moduledoc """
  Processes AI-parsed MCA prosecution cases and creates database records.

  Transforms `McaAiPdfParser.ParsedCase` structs into Ash resource records,
  handling the creation of:
  - Case records
  - Offender records (with lookup/create)
  - Offence records linking Cases to Legislation

  ## Usage

      alias EhsEnforcement.Scraping.Mca.{McaAiPdfParser, McaAiCaseProcessor}

      {:ok, parsed_cases} = McaAiPdfParser.parse_pdf_text(text, 2019)
      {:ok, case_record} = McaAiCaseProcessor.process_and_create_case(parsed_case, actor)
  """

  require Logger

  alias EhsEnforcement.Enforcement.Agency
  alias EhsEnforcement.Enforcement.Case
  alias EhsEnforcement.Enforcement.Offence
  alias EhsEnforcement.Enforcement.Offender
  alias EhsEnforcement.Scraping.Mca.McaAiPdfParser.ParsedCase
  alias EhsEnforcement.Scraping.Mca.McaProsecutionProcessor

  @doc """
  Process an AI-parsed case and create database records.

  Creates Case, Offender, and Offence records from a ParsedCase struct.

  Returns {:ok, case_record} or {:error, reason}
  """
  def process_and_create_case(%ParsedCase{} = parsed_case, actor \\ nil) do
    Logger.debug("MCA AI: Processing case for #{parsed_case.defendant_name}")

    with {:ok, agency} <- get_mca_agency(),
         {:ok, offender} <- find_or_create_offender(parsed_case, agency),
         {:ok, case_record} <- create_case(parsed_case, agency, offender, actor),
         {:ok, _offences} <- create_offence_records(case_record, parsed_case.legislation, actor) do
      {:ok, case_record}
    end
  end

  @doc """
  Process multiple AI-parsed cases.

  Returns {:ok, results} with created/existing/error counts.
  """
  def process_cases(parsed_cases, actor \\ nil) when is_list(parsed_cases) do
    results =
      Enum.reduce(parsed_cases, %{created: [], existing: [], errors: []}, fn parsed_case, acc ->
        case process_and_create_case(parsed_case, actor) do
          {:ok, case_record} ->
            %{acc | created: [case_record | acc.created]}

          {:error, %Ash.Error.Invalid{errors: errors}} = error ->
            if duplicate_error?(errors) do
              %{acc | existing: [parsed_case | acc.existing]}
            else
              Logger.warning("MCA AI: Error creating case: #{inspect(error)}")
              %{acc | errors: [{parsed_case, error} | acc.errors]}
            end

          {:error, reason} = error ->
            Logger.warning("MCA AI: Error processing case: #{inspect(reason)}")
            %{acc | errors: [{parsed_case, error} | acc.errors]}
        end
      end)

    {:ok, results}
  end

  # Private functions

  defp get_mca_agency do
    case Ash.get(Agency, code: "mca") do
      {:ok, agency} -> {:ok, agency}
      {:error, _} -> {:error, :agency_not_found}
    end
  end

  defp find_or_create_offender(%ParsedCase{} = parsed_case, agency) do
    name = parsed_case.defendant_name

    # Try to find existing offender by name
    case find_offender_by_name(name) do
      {:ok, offender} ->
        # Update agencies list if needed
        _ = update_offender_agencies(offender, agency)
        {:ok, offender}

      {:error, :not_found} ->
        # Create new offender
        create_offender(parsed_case, agency)
    end
  end

  defp find_offender_by_name(name) do
    require Ash.Query

    query =
      Offender
      |> Ash.Query.filter(name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [offender]} -> {:ok, offender}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_offender(%ParsedCase{} = parsed_case, agency) do
    Logger.info("Creating offender: #{parsed_case.defendant_name} (no postcode)")

    offender_params = %{
      name: parsed_case.defendant_name,
      postcode: nil,
      address: parsed_case.defendant_location,
      agencies: [agency.name]
    }

    case Ash.create(Offender, offender_params) do
      {:ok, offender} ->
        Logger.info("Created offender: #{offender.name} (ID: #{offender.id})")
        {:ok, offender}

      {:error, reason} ->
        Logger.error("Failed to create offender: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_offender_agencies(offender, agency) do
    current_agencies = offender.agencies || []

    unless agency.name in current_agencies do
      updated_agencies = [agency.name | current_agencies]

      case Ash.update(offender, %{agencies: updated_agencies}) do
        {:ok, updated} ->
          Logger.info(
            "Updated agencies for offender #{offender.name}: #{inspect(updated_agencies)}"
          )

          {:ok, updated}

        {:error, reason} ->
          Logger.warning("Failed to update offender agencies: #{inspect(reason)}")
          {:ok, offender}
      end
    else
      {:ok, offender}
    end
  end

  defp create_case(%ParsedCase{} = parsed_case, agency, offender, _actor) do
    regulator_id = generate_regulator_id(parsed_case)

    Logger.debug("MCA AI: Creating case from AI-parsed data: #{regulator_id}")

    # Build case params using correct Case resource field names
    case_params = %{
      agency_id: agency.id,
      offender_id: offender.id,
      regulator_id: regulator_id,
      offence_hearing_date: parsed_case.hearing_date,
      offence_result: parsed_case.offence_result || "Prosecution",
      offence_action_type: :prosecution,
      offence_fine: parsed_case.fine_amount,
      offence_costs: parsed_case.costs_amount,
      url: build_source_url(parsed_case.year)
    }

    case Ash.create(Case, case_params) do
      {:ok, case_record} ->
        Logger.debug("MCA AI: Created case: #{regulator_id}")
        {:ok, case_record}

      {:error, reason} ->
        Logger.error("MCA AI: Failed to create case: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_offence_records(case_record, legislation_list, actor)
       when is_list(legislation_list) do
    Logger.debug(
      "MCA AI: Creating #{length(legislation_list)} offence records for case #{case_record.id}"
    )

    offences =
      legislation_list
      |> Enum.map(fn legislation_str ->
        create_single_offence(case_record, legislation_str, actor)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, offences}
  end

  defp create_offence_records(case_record, _legislation, _actor) do
    Logger.debug("MCA AI: No legislation to link for case #{case_record.id}")
    {:ok, []}
  end

  defp create_single_offence(case_record, legislation_str, _actor)
       when is_binary(legislation_str) do
    # Use the shared legislation matcher from the main processor
    case McaProsecutionProcessor.find_or_create_legislation(legislation_str) do
      {:ok, legislation} ->
        offence_params = %{
          case_id: case_record.id,
          legislation_id: legislation.id,
          offence_description: "Maritime safety violation"
        }

        case Ash.create(Offence, offence_params) do
          {:ok, offence} ->
            Logger.debug("MCA AI: Created offence #{offence.id} for case #{case_record.id}")
            offence

          {:error, reason} ->
            Logger.warning("MCA AI: Failed to create offence: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        Logger.warning(
          "MCA AI: Failed to find/create legislation '#{legislation_str}': #{inspect(reason)}"
        )

        nil
    end
  end

  defp create_single_offence(_case_record, _legislation, _actor), do: nil

  defp generate_regulator_id(%ParsedCase{} = parsed_case) do
    # Format: mca_{year}_{defendant_slug}_{date}
    defendant_slug =
      parsed_case.defendant_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 30)

    date_suffix =
      case parsed_case.hearing_date do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    "mca_#{parsed_case.year}_#{defendant_slug}_#{date_suffix}"
  end

  defp build_source_url(year) do
    "https://www.gov.uk/government/publications/mca-enforcement-unit-prosecutions-#{year}"
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
end
