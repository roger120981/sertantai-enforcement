defmodule EhsEnforcementWeb.Api.DashboardController do
  use EhsEnforcementWeb, :controller

  alias EhsEnforcement.Enforcement.Metrics
  require Ash.Query

  @doc """
  GET /api/public/dashboard/stats?period=month&agency_id=...

  Returns dashboard statistics for the specified time period and optional agency filter.

  Query Parameters:
  - period: "week" | "month" | "year" (default: "month")
  - agency_id: UUID (optional) - Filter stats by specific agency

  Response:
  {
    "stats": {
      "active_agencies": 4,
      "recent_cases": 142,
      "recent_notices": 78,
      "total_cases": 1523,
      "total_notices": 892,
      "total_fines": "2450000.00",
      "total_costs": "125000.00",
      "timeframe": "Last 30 Days",
      "period": "30 days",
      "total_legislation": 150,
      "acts_count": 45,
      "regulations_count": 80,
      "orders_count": 20,
      "acops_count": 5
    },
    "recent_activity": [
      {
        "type": "Case",
        "record_type": "case",
        "is_case": true,
        "regulator_id": "HSE-2024-12345",
        "date": "2024-01-15",
        "organization": "ABC Ltd",
        "description": "Safety violation",
        "fine_amount": "5000.00",
        "agency_link": "https://..."
      }
    ],
    "agency_stats": [
      {
        "agency_id": "...",
        "agency_name": "HSE",
        "case_count": 100,
        "notice_count": 50
      }
    ]
  }
  """
  def stats(conn, params) do
    # Parse parameters
    period = parse_period(params["period"])
    agency_id = params["agency_id"]

    # Load metrics for the specified combination
    case load_metrics(period, agency_id) do
      {:ok, metrics} ->
        # Format response
        response = %{
          stats: format_stats(metrics),
          recent_activity: format_recent_activity(metrics.recent_activity),
          agency_stats: convert_agency_stats_to_list(metrics.agency_stats)
        }

        conn
        |> put_status(:ok)
        |> json(response)

      {:error, :not_found} ->
        # Graceful degradation - return empty stats
        conn
        |> put_status(:ok)
        |> json(%{
          stats: empty_stats(period),
          recent_activity: [],
          agency_stats: [],
          error: "Metrics not yet calculated for this period"
        })

      {:error, error} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to load dashboard stats", details: inspect(error)})
    end
  end

  # ==========================================
  # PRIVATE FUNCTIONS
  # ==========================================

  defp parse_period(nil), do: :month
  defp parse_period("week"), do: :week
  defp parse_period("month"), do: :month
  defp parse_period("year"), do: :year
  defp parse_period(_), do: :month

  defp load_metrics(period, agency_id) do
    # Build query for specific filter combination
    query =
      Metrics
      |> Ash.Query.filter(period == ^period)
      |> Ash.Query.filter(is_nil(record_type))
      |> Ash.Query.filter(is_nil(offender_id))
      |> Ash.Query.filter(is_nil(legislation_id))

    # Add agency filter
    query =
      if agency_id do
        Ash.Query.filter(query, agency_id == ^agency_id)
      else
        Ash.Query.filter(query, is_nil(agency_id))
      end

    case Ash.read(query) do
      {:ok, [metric]} ->
        {:ok, metric}

      {:ok, []} ->
        {:error, :not_found}

      {:error, error} ->
        require Logger
        Logger.error("Failed to load metrics: #{inspect(error)}")
        {:error, error}
    end
  end

  defp format_stats(metrics) do
    %{
      active_agencies: metrics.active_agencies_count,
      recent_cases: metrics.recent_cases_count,
      recent_notices: metrics.recent_notices_count,
      total_cases: metrics.total_cases_count,
      total_notices: metrics.total_notices_count,
      total_fines: Decimal.to_string(metrics.total_fines_amount, :normal),
      total_costs: Decimal.to_string(metrics.total_costs_amount, :normal),
      timeframe: metrics.period_label,
      period: "#{metrics.days_ago} days",
      # Legislation breakdown
      total_legislation: get_in(metrics.legislation_breakdown, ["total"]) || 0,
      acts_count: get_in(metrics.legislation_breakdown, ["acts"]) || 0,
      regulations_count: get_in(metrics.legislation_breakdown, ["regulations"]) || 0,
      orders_count: get_in(metrics.legislation_breakdown, ["orders"]) || 0,
      acops_count: get_in(metrics.legislation_breakdown, ["acops"]) || 0
    }
  end

  defp empty_stats(period) do
    %{
      active_agencies: 0,
      recent_cases: 0,
      recent_notices: 0,
      total_cases: 0,
      total_notices: 0,
      total_fines: "0",
      total_costs: "0",
      timeframe: period_label(period),
      period: "#{period_days(period)} days",
      total_legislation: 0,
      acts_count: 0,
      regulations_count: 0,
      orders_count: 0,
      acops_count: 0
    }
  end

  defp period_label(:week), do: "Last 7 Days"
  defp period_label(:month), do: "Last 30 Days"
  defp period_label(:year), do: "Last 365 Days"

  defp period_days(:week), do: 7
  defp period_days(:month), do: 30
  defp period_days(:year), do: 365

  defp format_recent_activity(recent_activity) when is_list(recent_activity) do
    Enum.map(recent_activity, &format_activity_item/1)
  end

  defp format_recent_activity(_), do: []

  defp format_activity_item(activity) when is_map(activity) do
    # Parse date if it's a string
    date =
      case activity["date"] do
        date_string when is_binary(date_string) ->
          case Date.from_iso8601(date_string) do
            {:ok, d} -> Date.to_iso8601(d)
            _ -> nil
          end

        %Date{} = d ->
          Date.to_iso8601(d)

        _ ->
          nil
      end

    # Ensure is_case field is set (for badge coloring)
    is_case = activity["record_type"] == "case" || activity["is_case"] == true

    %{
      type: activity["type"] || "Unknown",
      record_type: activity["record_type"],
      is_case: is_case,
      regulator_id: activity["regulator_id"],
      date: date,
      organization: activity["organization"],
      description: activity["description"],
      fine_amount: format_fine_amount(activity["fine_amount"]),
      agency_link: activity["agency_link"]
    }
  end

  defp format_fine_amount(nil), do: "£0"
  defp format_fine_amount(0), do: "£0"
  defp format_fine_amount(amount) when amount in [+0.0, -0.0], do: "£0"

  defp format_fine_amount(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, _} -> format_fine_amount(decimal)
      :error -> "£0"
    end
  end

  defp format_fine_amount(%Decimal{} = amount) do
    # Format with thousands separator
    amount_float = Decimal.to_float(amount)
    formatted = :erlang.float_to_binary(amount_float, decimals: 2)
    parts = String.split(formatted, ".")
    integer_part = hd(parts)
    decimal_part = if length(parts) > 1, do: "." <> Enum.at(parts, 1), else: ".00"

    # Add thousands separators
    integer_with_commas =
      integer_part
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")

    "£#{integer_with_commas}#{decimal_part}"
  end

  defp format_fine_amount(amount) when is_number(amount) do
    amount
    |> Decimal.from_float()
    |> format_fine_amount()
  end

  defp convert_agency_stats_to_list(agency_stats_map) when is_map(agency_stats_map) do
    agency_stats_map
    |> Map.values()
    |> Enum.sort_by(& &1["case_count"], :desc)
  end

  defp convert_agency_stats_to_list(_), do: []
end
