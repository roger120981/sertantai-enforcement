defmodule EhsEnforcementWeb.UnifiedDataController do
  @moduledoc """
  Controller for unified data endpoint that combines Cases and Notices.

  This endpoint powers the dynamic query table (Issue #5) by returning
  a unified dataset that can be filtered, sorted, and paginated.

  ## Unified Record Structure

  Each record includes:
  - `record_type`: "case" or "notice" (identifies source table)
  - All fields from both Cases and Notices (NULL where not applicable)
  - Common fields: regulator_id, offence_action_date, offence_action_type, etc.

  ## Query Parameters

  - `limit`: Number of records to return (default: 100, max: 1000)
  - `offset`: Pagination offset (default: 0)
  - `order_by`: Field to sort by (default: offence_action_date)
  - `order`: Sort direction - "asc" or "desc" (default: desc)
  - `record_type`: Filter by type - "case", "notice", or "all" (default: all)
  - `date_from`: Filter by date >= this value (ISO 8601 format)
  - `date_to`: Filter by date <= this value (ISO 8601 format)
  - `agency_id`: Filter by agency UUID

  ## Example Response

  ```json
  {
    "data": [
      {
        "id": "uuid",
        "record_type": "case",
        "case_reference": "HSE-2023-001",
        "regulator_id": "hse_case_123",
        "offence_action_date": "2023-12-01",
        "offence_action_type": "Conviction",
        "offence_result": "Fine",
        "offence_fine": 50000.00,
        "offence_costs": 5000.00,
        "offence_breaches": "Health and Safety at Work Act breach",
        "agency_id": "uuid",
        ...
      },
      {
        "id": "uuid",
        "record_type": "notice",
        "regulator_id": "hse_notice_456",
        "notice_date": "2023-11-15",
        "offence_action_date": "2023-11-15",
        "offence_action_type": "Improvement Notice",
        "notice_body": "Required to implement safety measures",
        "offence_breaches": "Safety violations",
        ...
      }
    ],
    "meta": {
      "total_count": 45123,
      "limit": 100,
      "offset": 0,
      "cases_count": 5120,
      "notices_count": 40003
    }
  }
  ```
  """

  use EhsEnforcementWeb, :controller

  require Ash.Query

  @doc """
  GET /api/unified-data

  Returns unified dataset combining Cases and Notices.
  """
  def index(conn, params) do
    # Parse query parameters
    limit = parse_limit(params["limit"])
    offset = parse_offset(params["offset"])
    record_type_filter = params["record_type"] || "all"
    date_from = params["date_from"]
    date_to = params["date_to"]
    agency_id = params["agency_id"]
    order_by = params["order_by"] || "offence_action_date"
    order_direction = parse_order(params["order"])

    # Fetch Cases and Notices separately, then merge
    # (Simpler than complex SQL UNION for Ash framework)
    cases_query = build_cases_query(record_type_filter, date_from, date_to, agency_id)
    notices_query = build_notices_query(record_type_filter, date_from, date_to, agency_id)

    # Execute queries
    {:ok, cases} = Ash.read(cases_query)
    {:ok, notices} = Ash.read(notices_query)

    # Transform to unified format
    unified_cases = Enum.map(cases, &transform_case_to_unified/1)
    unified_notices = Enum.map(notices, &transform_notice_to_unified/1)

    # Merge and sort
    all_records = unified_cases ++ unified_notices

    sorted_records =
      case order_by do
        "offence_action_date" ->
          Enum.sort_by(
            all_records,
            fn record -> record[order_by] || ~D[1900-01-01] end,
            order_direction
          )

        _ ->
          # For string fields, sort case-insensitively
          Enum.sort_by(
            all_records,
            fn record -> String.downcase(to_string(record[order_by] || "")) end,
            order_direction
          )
      end

    # Apply pagination
    paginated_records =
      sorted_records
      |> Enum.drop(offset)
      |> Enum.take(limit)

    # Build response with metadata
    json(conn, %{
      data: paginated_records,
      meta: %{
        total_count: length(all_records),
        limit: limit,
        offset: offset,
        cases_count: length(unified_cases),
        notices_count: length(unified_notices),
        record_types: get_record_type_counts(all_records)
      }
    })
  end

  # Private Functions

  defp build_cases_query("notice", _, _, _),
    do: Ash.Query.new(EhsEnforcement.Enforcement.Case) |> Ash.Query.limit(0)

  defp build_cases_query(_, date_from, date_to, agency_id) do
    query = Ash.Query.new(EhsEnforcement.Enforcement.Case)

    query
    # Load agency and offender relationships
    |> Ash.Query.load([:agency, :offender])
    |> apply_date_filters(date_from, date_to, :offence_action_date)
    |> apply_agency_filter(agency_id)
  end

  defp build_notices_query("case", _, _, _),
    do: Ash.Query.new(EhsEnforcement.Enforcement.Notice) |> Ash.Query.limit(0)

  defp build_notices_query(_, date_from, date_to, agency_id) do
    query = Ash.Query.new(EhsEnforcement.Enforcement.Notice)

    query
    # Load agency and offender relationships
    |> Ash.Query.load([:agency, :offender])
    |> apply_date_filters(date_from, date_to, :offence_action_date)
    |> apply_agency_filter(agency_id)
  end

  defp apply_date_filters(query, nil, nil, _field), do: query

  defp apply_date_filters(query, date_from, nil, :offence_action_date)
       when is_binary(date_from) do
    case Date.from_iso8601(date_from) do
      {:ok, date} -> Ash.Query.filter(query, offence_action_date >= ^date)
      _ -> query
    end
  end

  defp apply_date_filters(query, nil, date_to, :offence_action_date) when is_binary(date_to) do
    case Date.from_iso8601(date_to) do
      {:ok, date} -> Ash.Query.filter(query, offence_action_date <= ^date)
      _ -> query
    end
  end

  defp apply_date_filters(query, date_from, date_to, :offence_action_date)
       when is_binary(date_from) and is_binary(date_to) do
    with {:ok, from} <- Date.from_iso8601(date_from),
         {:ok, to} <- Date.from_iso8601(date_to) do
      Ash.Query.filter(query, offence_action_date >= ^from and offence_action_date <= ^to)
    else
      _ -> query
    end
  end

  defp apply_agency_filter(query, nil), do: query

  defp apply_agency_filter(query, agency_id_str) when is_binary(agency_id_str) do
    Ash.Query.filter(query, agency_id == ^agency_id_str)
  end

  defp transform_case_to_unified(case_record) do
    %{
      id: case_record.id,
      record_type: "case",
      # Case-specific fields
      case_reference: case_record.case_reference,
      offence_result: case_record.offence_result,
      offence_fine: case_record.offence_fine,
      offence_costs: case_record.offence_costs,
      offence_hearing_date: case_record.offence_hearing_date,
      related_cases: case_record.related_cases,
      # Common fields
      regulator_id: case_record.regulator_id,
      offence_action_date: case_record.offence_action_date,
      offence_action_type: case_record.offence_action_type,
      offence_breaches: case_record.offence_breaches,
      regulator_function: case_record.regulator_function,
      environmental_impact: case_record.environmental_impact,
      environmental_receptor: case_record.environmental_receptor,
      url: case_record.url,
      agency_id: case_record.agency_id,
      # Agency fields (from relationship)
      agency_code: case_record.agency.code,
      agency_name: case_record.agency.name,
      # Notice-specific fields (NULL for cases)
      notice_date: nil,
      notice_body: nil,
      operative_date: nil,
      compliance_date: nil,
      regulator_ref_number: nil,
      # Timestamps
      inserted_at: case_record.inserted_at,
      updated_at: case_record.updated_at
    }
  end

  defp transform_notice_to_unified(notice_record) do
    %{
      id: notice_record.id,
      record_type: "notice",
      # Notice-specific fields
      notice_date: notice_record.notice_date,
      notice_body: notice_record.notice_body,
      operative_date: notice_record.operative_date,
      compliance_date: notice_record.compliance_date,
      regulator_ref_number: notice_record.regulator_ref_number,
      # Common fields
      regulator_id: notice_record.regulator_id,
      offence_action_date: notice_record.offence_action_date,
      offence_action_type: notice_record.offence_action_type,
      offence_breaches: notice_record.offence_breaches,
      regulator_function: notice_record.regulator_function,
      environmental_impact: notice_record.environmental_impact,
      environmental_receptor: notice_record.environmental_receptor,
      url: notice_record.url,
      agency_id: notice_record.agency_id,
      # Agency fields (from relationship)
      agency_code: notice_record.agency.code,
      agency_name: notice_record.agency.name,
      # Case-specific fields (NULL for notices)
      case_reference: nil,
      offence_result: nil,
      offence_fine: nil,
      offence_costs: nil,
      offence_hearing_date: nil,
      related_cases: nil,
      # Timestamps
      inserted_at: notice_record.inserted_at,
      updated_at: notice_record.updated_at
    }
  end

  defp parse_limit(nil), do: 100

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {num, _} -> min(max(num, 1), 1000)
      _ -> 100
    end
  end

  defp parse_limit(limit) when is_integer(limit), do: min(max(limit, 1), 1000)

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

  defp get_record_type_counts(records) do
    Enum.reduce(records, %{"case" => 0, "notice" => 0}, fn record, acc ->
      Map.update!(acc, record.record_type, &(&1 + 1))
    end)
  end
end
