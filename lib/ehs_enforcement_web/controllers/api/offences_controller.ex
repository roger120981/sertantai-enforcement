defmodule EhsEnforcementWeb.Api.OffencesController do
  @moduledoc """
  API controller for Offence resource operations.

  Supports listing, viewing, creating, and updating offences.
  Used by the frontend Svelte table and admin editing interfaces.
  """

  use EhsEnforcementWeb, :controller

  require Ash.Query

  alias EhsEnforcement.Enforcement.Offence

  @doc """
  List all offences with optional filters.

  GET /api/offences

  Query Parameters:
  - limit: Number of records (default: 1000, max: 5000)
  - offset: Pagination offset (default: 0)
  - case_id: Filter by case UUID
  - notice_id: Filter by notice UUID
  - legislation_id: Filter by legislation UUID
  - with_fines: true to only show offences with fines > 0
  - order_by: Field to sort by (default: created_at)
  - order: asc or desc (default: desc)
  """
  def index(conn, params) do
    limit = parse_limit(params["limit"])
    offset = parse_offset(params["offset"])
    order_by = params["order_by"] || "created_at"
    order_direction = parse_order(params["order"])

    # Build query with filters
    query =
      Offence
      |> Ash.Query.new()
      |> Ash.Query.load([:case, :notice, :legislation])
      |> apply_filters(params)
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> apply_sort(order_by, order_direction)

    case Ash.read(query) do
      {:ok, offences} ->
        conn
        |> json(%{
          success: true,
          data: Enum.map(offences, &serialize_offence/1),
          meta: %{
            limit: limit,
            offset: offset,
            count: length(offences)
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to load offences",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Get a single offence by ID.

  GET /api/offences/:id
  """
  def show(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Ash.get(Offence, id, actor: current_user, load: [:case, :notice, :legislation]) do
      {:ok, offence_record} ->
        conn
        |> json(%{
          success: true,
          data: serialize_offence(offence_record)
        })

      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Offence not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to load offence",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Create a new offence.

  POST /api/offences
  Body: %{
    offence_description: "...",
    offence_reference: "...",
    legislation_part: "...",
    fine: 5000.00,
    sequence_number: 1,
    case_id: "uuid",
    notice_id: "uuid",
    legislation_id: "uuid"
  }
  """
  def create(conn, params) do
    current_user = conn.assigns[:current_user]

    case Ash.create(Offence, params, actor: current_user) do
      {:ok, offence_record} ->
        # Load relationships for response
        case Ash.load(offence_record, [:case, :notice, :legislation]) do
          {:ok, loaded_offence} ->
            conn
            |> put_status(:created)
            |> json(%{
              success: true,
              message: "Offence created successfully",
              data: serialize_offence(loaded_offence)
            })

          {:error, _} ->
            # Fallback if load fails
            conn
            |> put_status(:created)
            |> json(%{
              success: true,
              message: "Offence created successfully",
              data: serialize_offence(offence_record)
            })
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Failed to create offence",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Update an offence.

  PATCH /api/offences/:id
  Body: %{...update fields...}
  """
  def update(conn, %{"id" => id} = params) do
    current_user = conn.assigns[:current_user]

    with {:ok, offence_record} <- Ash.get(Offence, id, actor: current_user),
         {:ok, updated_offence} <-
           Ash.update(offence_record, Map.drop(params, ["id"]), actor: current_user),
         {:ok, loaded_offence} <- Ash.load(updated_offence, [:case, :notice, :legislation]) do
      conn
      |> json(%{
        success: true,
        message: "Offence updated successfully",
        data: serialize_offence(loaded_offence)
      })
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Offence not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Failed to update offence",
          details: inspect(reason)
        })
    end
  end

  # Private Helper Functions

  defp apply_filters(query, params) do
    query
    |> filter_by_case(params["case_id"])
    |> filter_by_notice(params["notice_id"])
    |> filter_by_legislation(params["legislation_id"])
    |> filter_with_fines(params["with_fines"])
  end

  defp filter_by_case(query, nil), do: query

  defp filter_by_case(query, case_id) when is_binary(case_id) do
    Ash.Query.filter(query, case_id == ^case_id)
  end

  defp filter_by_notice(query, nil), do: query

  defp filter_by_notice(query, notice_id) when is_binary(notice_id) do
    Ash.Query.filter(query, notice_id == ^notice_id)
  end

  defp filter_by_legislation(query, nil), do: query

  defp filter_by_legislation(query, legislation_id) when is_binary(legislation_id) do
    Ash.Query.filter(query, legislation_id == ^legislation_id)
  end

  defp filter_with_fines(query, nil), do: query
  defp filter_with_fines(query, "false"), do: query

  defp filter_with_fines(query, "true") do
    Ash.Query.filter(query, not is_nil(fine) and fine > 0)
  end

  defp apply_sort(query, "created_at", :desc), do: Ash.Query.sort(query, created_at: :desc)
  defp apply_sort(query, "created_at", :asc), do: Ash.Query.sort(query, created_at: :asc)
  defp apply_sort(query, "fine", :desc), do: Ash.Query.sort(query, fine: :desc)
  defp apply_sort(query, "fine", :asc), do: Ash.Query.sort(query, fine: :asc)

  defp apply_sort(query, "sequence_number", :desc),
    do: Ash.Query.sort(query, sequence_number: :desc)

  defp apply_sort(query, "sequence_number", :asc),
    do: Ash.Query.sort(query, sequence_number: :asc)

  defp apply_sort(query, _field, :desc), do: Ash.Query.sort(query, created_at: :desc)
  defp apply_sort(query, _field, :asc), do: Ash.Query.sort(query, created_at: :asc)

  defp parse_limit(nil), do: 1000

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {num, _} -> min(max(num, 1), 5000)
      _ -> 1000
    end
  end

  defp parse_limit(limit) when is_integer(limit), do: min(max(limit, 1), 5000)

  defp parse_offset(nil), do: 0

  defp parse_offset(offset) when is_binary(offset) do
    case Integer.parse(offset) do
      {num, _} -> max(num, 0)
      _ -> 0
    end
  end

  defp parse_offset(offset) when is_integer(offset), do: max(offset, 0)

  defp parse_order(nil), do: :desc
  defp parse_order("asc"), do: :asc
  defp parse_order("desc"), do: :desc
  defp parse_order(_), do: :desc

  # Serialization

  defp serialize_offence(offence_record) do
    # Load calculations dynamically
    calculated = load_calculations(offence_record)

    %{
      id: offence_record.id,
      offence_description: offence_record.offence_description,
      offence_reference: offence_record.offence_reference,
      legislation_part: offence_record.legislation_part,
      fine: offence_record.fine,
      sequence_number: offence_record.sequence_number,
      case_id: offence_record.case_id,
      notice_id: offence_record.notice_id,
      legislation_id: offence_record.legislation_id,
      # Relationships (if loaded)
      case: serialize_case(offence_record.case),
      notice: serialize_notice(offence_record.notice),
      legislation: serialize_legislation(offence_record.legislation),
      # Calculations (new)
      parent_type: calculated.parent_type,
      parent_reference: calculated.parent_reference,
      severity_category: calculated.severity_category,
      has_sequence: calculated.has_sequence,
      total_financial_penalty: calculated.total_financial_penalty,
      legislation_reference: calculated.legislation_reference,
      # Timestamps
      created_at: offence_record.created_at,
      updated_at: offence_record.updated_at
    }
  end

  defp load_calculations(offence_record) do
    # Parent type
    parent_type =
      cond do
        not is_nil(offence_record.case_id) -> "Case"
        not is_nil(offence_record.notice_id) -> "Notice"
        true -> "Unknown"
      end

    # Parent reference
    parent_reference =
      cond do
        not is_nil(offence_record.case_id) and
          Ash.Resource.loaded?(offence_record, :case) and not is_nil(offence_record.case) ->
          offence_record.case.case_reference

        not is_nil(offence_record.notice_id) and
          Ash.Resource.loaded?(offence_record, :notice) and not is_nil(offence_record.notice) ->
          offence_record.notice.regulator_ref_number

        true ->
          nil
      end

    # Severity category
    severity_category =
      cond do
        is_nil(offence_record.fine) or offence_record.fine == 0 -> "None"
        Decimal.compare(offence_record.fine, Decimal.new(1000)) == :lt -> "Low"
        Decimal.compare(offence_record.fine, Decimal.new(10000)) == :lt -> "Medium"
        true -> "High"
      end

    # Has sequence
    has_sequence = not is_nil(offence_record.sequence_number)

    # Total financial penalty
    total_financial_penalty = offence_record.fine || Decimal.new(0)

    # Legislation reference
    legislation_reference =
      if Ash.Resource.loaded?(offence_record, :legislation) and
           not is_nil(offence_record.legislation) do
        if is_nil(offence_record.legislation_part) do
          offence_record.legislation.legislation_title
        else
          "#{offence_record.legislation.legislation_title} - #{offence_record.legislation_part}"
        end
      else
        nil
      end

    %{
      parent_type: parent_type,
      parent_reference: parent_reference,
      severity_category: severity_category,
      has_sequence: has_sequence,
      total_financial_penalty: total_financial_penalty,
      legislation_reference: legislation_reference
    }
  end

  defp serialize_case(nil), do: nil

  defp serialize_case(case_record) do
    %{
      id: case_record.id,
      case_reference: case_record.case_reference,
      offence_action_type: case_record.offence_action_type,
      offence_action_date: case_record.offence_action_date
    }
  end

  defp serialize_notice(nil), do: nil

  defp serialize_notice(notice_record) do
    %{
      id: notice_record.id,
      regulator_ref_number: notice_record.regulator_ref_number,
      offence_action_type: notice_record.offence_action_type,
      notice_date: notice_record.notice_date
    }
  end

  defp serialize_legislation(nil), do: nil

  defp serialize_legislation(legislation_record) do
    %{
      id: legislation_record.id,
      legislation_title: legislation_record.legislation_title,
      legislation_year: legislation_record.legislation_year,
      legislation_type: legislation_record.legislation_type
    }
  end
end
