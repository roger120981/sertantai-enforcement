defmodule EhsEnforcementWeb.ReportsLive.Index do
  @moduledoc """
  Reports and Analytics LiveView for generating filtered reports and exports.

  Provides:
  - Custom report generation with mandatory filtering
  - Multi-format export (CSV, Excel, JSON, PDF)
  - Database protection through date constraints
  - Template management foundation
  """

  use EhsEnforcementWeb, :live_view

  alias EhsEnforcement.Enforcement
  # alias EhsEnforcementWeb.CaseLive.CSVExport  # Removed - legacy LiveView deleted

  @impl true
  def mount(_params, _session, socket) do
    # Load initial data for filters
    agencies = Enforcement.list_agencies!()

    {:ok,
     socket
     |> assign(:agencies, agencies)
     |> assign(:show_generate_modal, false)
     |> assign(:show_export_modal, false)
     |> assign(:export_format, "csv")
     |> assign(:report_template, "enforcement_summary")
     |> assign(:date_from, "")
     |> assign(:date_to, "")
     |> assign(:agency_filter, "")
     |> assign(:min_fine, "")
     |> assign(:max_fine, "")
     |> assign(:search_query, "")
     |> assign(:export_in_progress, false)
     |> assign(:last_export_result, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_generate_modal", _params, socket) do
    {:noreply, assign(socket, :show_generate_modal, true)}
  end

  @impl true
  def handle_event("hide_generate_modal", _params, socket) do
    {:noreply, assign(socket, :show_generate_modal, false)}
  end

  @impl true
  def handle_event("show_export_modal", _params, socket) do
    {:noreply, assign(socket, :show_export_modal, true)}
  end

  @impl true
  def handle_event("hide_export_modal", _params, socket) do
    {:noreply, assign(socket, :show_export_modal, false)}
  end

  @impl true
  def handle_event("update_report_template", %{"template" => template}, socket) do
    {:noreply, assign(socket, :report_template, template)}
  end

  @impl true
  def handle_event("update_export_format", %{"format" => format}, socket) do
    {:noreply, assign(socket, :export_format, format)}
  end

  @impl true
  def handle_event("update_filters", params, socket) do
    socket =
      socket
      |> assign(:date_from, params["date_from"] || "")
      |> assign(:date_to, params["date_to"] || "")
      |> assign(:agency_filter, params["agency_filter"] || "")
      |> assign(:min_fine, params["min_fine"] || "")
      |> assign(:max_fine, params["max_fine"] || "")
      |> assign(:search_query, params["search_query"] || "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_report", _params, socket) do
    # Validate that required filters are provided
    case validate_filters(socket.assigns) do
      :ok ->
        # Generate report based on template and filters
        case generate_filtered_report(socket.assigns) do
          {:ok, report_data} ->
            {:noreply,
             socket
             |> assign(:show_generate_modal, false)
             |> put_flash(
               :info,
               "Report generated successfully with #{length(report_data)} records"
             )}

          {:error, message} ->
            {:noreply, put_flash(socket, :error, "Report generation failed: #{message}")}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("export_data", _params, socket) do
    # Validate that required filters are provided
    case validate_filters(socket.assigns) do
      :ok ->
        # Start export process
        socket = assign(socket, :export_in_progress, true)

        case perform_filtered_export(socket.assigns) do
          {:ok, export_result} ->
            {:noreply,
             socket
             |> assign(:export_in_progress, false)
             |> assign(:show_export_modal, false)
             |> assign(:last_export_result, export_result)
             |> put_flash(
               :info,
               "Export completed: #{export_result.filename} (#{export_result.size})"
             )}

          {:error, message} ->
            {:noreply,
             socket
             |> assign(:export_in_progress, false)
             |> put_flash(:error, "Export failed: #{message}")}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, push_navigate(socket, to: "/dashboard")}
  end

  # Validate that mandatory filters are provided for database protection
  defp validate_filters(assigns) do
    errors = []

    # Check date range (mandatory for exports)
    errors =
      if assigns.date_from == "" or assigns.date_to == "" do
        ["Date range is required for all reports and exports" | errors]
      else
        # Validate date format
        with {:ok, date_from} <- Date.from_iso8601(assigns.date_from),
             {:ok, date_to} <- Date.from_iso8601(assigns.date_to) do
          # Check date range is reasonable (not more than 2 years)
          days_diff = Date.diff(date_to, date_from)

          if days_diff > 730 do
            ["Date range cannot exceed 2 years for performance reasons" | errors]
          else
            errors
          end
        else
          _ -> ["Invalid date format. Use YYYY-MM-DD format" | errors]
        end
      end

    case errors do
      [] -> :ok
      [error | _] -> {:error, error}
    end
  end

  # Generate filtered report based on template and filters
  defp generate_filtered_report(assigns) do
    try do
      filters = build_filter_map(assigns)

      case assigns.report_template do
        "enforcement_summary" ->
          generate_enforcement_summary(filters)

        "agency_breakdown" ->
          generate_agency_breakdown(filters)

        "offender_analysis" ->
          generate_offender_analysis(filters)

        "compliance_status" ->
          generate_compliance_status(filters)

        _ ->
          {:error, "Unknown report template"}
      end
    rescue
      error ->
        {:error, "Report generation failed: #{inspect(error)}"}
    end
  end

  # Perform filtered export in the specified format
  defp perform_filtered_export(assigns) do
    try do
      filters = build_filter_map(assigns)

      case assigns.export_format do
        "csv" ->
          export_to_csv(filters)

        "excel" ->
          export_to_excel(filters)

        "json" ->
          export_to_json(filters)

        "pdf" ->
          export_to_pdf(filters)

        _ ->
          {:error, "Unsupported export format"}
      end
    rescue
      error ->
        {:error, "Export failed: #{inspect(error)}"}
    end
  end

  # Build filter map from assigns
  defp build_filter_map(assigns) do
    %{
      date_from: assigns.date_from,
      date_to: assigns.date_to,
      agency_id: if(assigns.agency_filter != "", do: assigns.agency_filter, else: nil),
      min_fine: if(assigns.min_fine != "", do: assigns.min_fine, else: nil),
      max_fine: if(assigns.max_fine != "", do: assigns.max_fine, else: nil),
      search: if(assigns.search_query != "", do: assigns.search_query, else: nil)
    }
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Map.new()
  end

  # Report generation functions
  defp generate_enforcement_summary(filters) do
    # Load filtered cases and notices
    cases = load_filtered_cases(filters)
    notices = load_filtered_notices(filters)

    report_data = cases ++ notices
    {:ok, report_data}
  end

  defp generate_agency_breakdown(filters) do
    cases = load_filtered_cases(filters)

    agency_stats =
      cases
      |> Enum.group_by(& &1.agency_id)
      |> Enum.map(fn {agency_id, agency_cases} ->
        agency = Enum.find(agency_cases, & &1.agency).agency

        %{
          agency_id: agency_id,
          agency_name: agency.name,
          case_count: length(agency_cases),
          total_fines: calculate_total_fines(agency_cases)
        }
      end)

    {:ok, agency_stats}
  end

  defp generate_offender_analysis(filters) do
    cases = load_filtered_cases(filters)

    offender_stats =
      cases
      |> Enum.group_by(& &1.offender_id)
      |> Enum.map(fn {offender_id, offender_cases} ->
        offender = Enum.find(offender_cases, & &1.offender).offender

        %{
          offender_id: offender_id,
          offender_name: offender.name,
          case_count: length(offender_cases),
          total_fines: calculate_total_fines(offender_cases),
          is_repeat_offender: length(offender_cases) > 1
        }
      end)

    {:ok, offender_stats}
  end

  defp generate_compliance_status(filters) do
    notices = load_filtered_notices(filters)

    compliance_stats =
      notices
      |> Enum.map(fn notice ->
        compliance_status =
          case notice.compliance_date do
            %Date{} = compliance_date ->
              if Date.compare(compliance_date, Date.utc_today()) in [:eq, :lt] do
                "complied"
              else
                "pending"
              end

            _ ->
              "unknown"
          end

        Map.put(notice, :compliance_status, compliance_status)
      end)

    {:ok, compliance_stats}
  end

  # Export functions
  defp export_to_csv(_filters) do
    # Legacy CSVExport module removed - CSV export functionality moved to Svelte frontend
    {:error, "CSV export has been moved to the Svelte frontend"}
  end

  defp export_to_excel(_filters) do
    # Excel export functionality moved to Svelte frontend
    {:error, "Excel export has been moved to the Svelte frontend"}
  end

  defp export_to_json(filters) do
    try do
      cases = load_filtered_cases(filters)
      json_data = Jason.encode!(cases)

      filename =
        "cases_export_#{Date.utc_today() |> Date.to_string() |> String.replace("-", "")}.json"

      size = format_file_size(byte_size(json_data))

      {:ok, %{filename: filename, size: size, format: "JSON", content: json_data}}
    rescue
      error ->
        {:error, "JSON export failed: #{inspect(error)}"}
    end
  end

  defp export_to_pdf(_filters) do
    # Placeholder for PDF export
    # In a real implementation, this would use a library like PdfGenerator
    {:error, "PDF export not yet implemented"}
  end

  # Data loading functions with filtering
  defp load_filtered_cases(filters) do
    query_opts = [
      filter: build_ash_filter(filters),
      sort: [offence_action_date: :desc],
      load: [:offender, :agency]
    ]

    Enforcement.list_cases!(query_opts)
  end

  defp load_filtered_notices(filters) do
    query_opts = [
      filter: build_ash_filter(filters),
      sort: [offence_action_date: :desc],
      load: [:offender, :agency]
    ]

    Enforcement.list_notices!(query_opts)
  end

  # Build Ash filter from filter map (reuse from CSVExport)
  defp build_ash_filter(filters) do
    Enum.reduce(filters, [], fn
      {:agency_id, id}, acc when is_binary(id) ->
        [{:agency_id, id} | acc]

      {:date_from, date}, acc when is_binary(date) ->
        case Date.from_iso8601(date) do
          {:ok, parsed_date} ->
            [{:offence_action_date, [greater_than_or_equal_to: parsed_date]} | acc]

          _ ->
            acc
        end

      {:date_to, date}, acc when is_binary(date) ->
        case Date.from_iso8601(date) do
          {:ok, parsed_date} ->
            [{:offence_action_date, [less_than_or_equal_to: parsed_date]} | acc]

          _ ->
            acc
        end

      {:min_fine, amount}, acc when is_binary(amount) ->
        case Decimal.parse(amount) do
          {decimal_amount, _} ->
            [{:offence_fine, [greater_than_or_equal_to: decimal_amount]} | acc]

          :error ->
            acc
        end

      {:max_fine, amount}, acc when is_binary(amount) ->
        case Decimal.parse(amount) do
          {decimal_amount, _} -> [{:offence_fine, [less_than_or_equal_to: decimal_amount]} | acc]
          :error -> acc
        end

      {:search, query}, acc when is_binary(query) ->
        search_conditions = [
          [offender: [name: [ilike: "%#{query}%"]]],
          [regulator_id: [ilike: "%#{query}%"]],
          [offence_breaches: [ilike: "%#{query}%"]]
        ]

        [{:or, search_conditions} | acc]

      _, acc ->
        acc
    end)
  end

  # Helper functions
  defp calculate_total_fines(cases) do
    cases
    |> Enum.map(&(&1.offence_fine || Decimal.new(0)))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes}B"

  defp format_file_size(bytes) when bytes < 1_048_576 do
    kb = Float.round(bytes / 1024, 1)
    "#{kb}KB"
  end

  defp format_file_size(bytes) do
    mb = Float.round(bytes / 1_048_576, 1)
    "#{mb}MB"
  end
end
