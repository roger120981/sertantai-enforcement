defmodule EhsEnforcementWeb.Api.DuplicatesController do
  use EhsEnforcementWeb, :controller

  alias EhsEnforcement.Enforcement.DuplicateDetector
  alias EhsEnforcement.Enforcement.{Case, Notice, Offender}

  @doc """
  Get duplicate records for a specific resource type (cases, notices, or offenders).

  GET /api/duplicates?type=cases
  """
  def index(conn, %{"type" => type}) do
    current_user = conn.assigns[:current_user]

    case detect_duplicates(type, current_user) do
      {:ok, duplicates} ->
        conn
        |> json(%{
          success: true,
          type: type,
          data: serialize_duplicates(duplicates, type)
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to detect duplicates",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Delete selected duplicate records.

  DELETE /api/duplicates
  Body: %{"type" => "cases", "ids" => ["id1", "id2"]}
  """
  def delete_selected(conn, %{"type" => type, "ids" => ids}) when is_list(ids) do
    current_user = conn.assigns[:current_user]
    resource = get_resource_for_type(type)

    results =
      Enum.map(ids, fn id ->
        case Ash.get(resource, id, actor: current_user) do
          {:ok, record} ->
            case Ash.destroy(record, actor: current_user) do
              :ok -> {:ok, id}
              {:error, error} -> {:error, {id, error}}
            end

          {:error, error} ->
            {:error, {id, error}}
        end
      end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &match?({:error, _}, &1))

    conn
    |> json(%{
      success: failures == 0,
      deleted: successes,
      failed: failures,
      message: build_deletion_message(successes, failures)
    })
  end

  # Private functions

  defp detect_duplicates("cases", current_user) do
    DuplicateDetector.find_duplicate_cases(current_user)
  end

  defp detect_duplicates("notices", current_user) do
    DuplicateDetector.find_duplicate_notices(current_user)
  end

  defp detect_duplicates("offenders", _current_user) do
    # Use company number duplicates for now (more reliable than fuzzy name matching)
    case EhsEnforcement.Enforcement.find_duplicate_offenders_by_company_number() do
      {:ok, duplicates} -> {:ok, duplicates}
      error -> error
    end
  end

  defp detect_duplicates(_type, _current_user) do
    {:error, :invalid_type}
  end

  defp serialize_duplicates(duplicate_groups, type) do
    Enum.map(duplicate_groups, fn group ->
      Enum.map(group, fn record ->
        serialize_record(record, type)
      end)
    end)
  end

  defp serialize_record(record, "cases") do
    %{
      id: record.id,
      regulator_id: record.regulator_id,
      case_result: record.case_result,
      offence_date: record.offence_date,
      sentence_date: record.sentence_date,
      prosecution_end_date: record.prosecution_end_date,
      fine_amount: record.fine_amount,
      offender_id: record.offender_id,
      offender_name: if(record.offender, do: record.offender.name, else: nil),
      agency_id: record.agency_id,
      agency_code: if(record.agency, do: record.agency.code, else: nil),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp serialize_record(record, "notices") do
    %{
      id: record.id,
      regulator_id: record.regulator_id,
      regulator_ref_number: record.regulator_ref_number,
      notice_type: record.notice_type,
      issued_date: record.issued_date,
      offender_id: record.offender_id,
      offender_name: if(record.offender, do: record.offender.name, else: nil),
      agency_id: record.agency_id,
      agency_code: if(record.agency, do: record.agency.code, else: nil),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp serialize_record(record, "offenders") do
    %{
      id: record.id,
      name: record.name,
      company_number: record.company_number,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp get_resource_for_type("cases"), do: Case
  defp get_resource_for_type("notices"), do: Notice
  defp get_resource_for_type("offenders"), do: Offender
  defp get_resource_for_type(_), do: nil

  defp build_deletion_message(successes, 0) when successes > 0 do
    "Successfully deleted #{successes} record#{if successes > 1, do: "s", else: ""}"
  end

  defp build_deletion_message(successes, failures) when successes > 0 and failures > 0 do
    "Deleted #{successes} record#{if successes > 1, do: "s", else: ""}, failed to delete #{failures}"
  end

  defp build_deletion_message(0, failures) when failures > 0 do
    "Failed to delete #{failures} record#{if failures > 1, do: "s", else: ""}"
  end

  defp build_deletion_message(_, _), do: "No records were deleted"
end
