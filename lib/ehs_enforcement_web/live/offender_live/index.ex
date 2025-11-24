defmodule EhsEnforcementWeb.OffenderLive.Index do
  use EhsEnforcementWeb, :live_view

  alias EhsEnforcement.Enforcement

  require Ash.Query

  @per_page 20

  # Security: Whitelist allowed sort fields to prevent DOS via String.to_atom
  @allowed_sort_fields ~w(name total_fines total_cases total_notices first_seen_date last_seen_date)

  # Security: Whitelist allowed sort orders to prevent DOS via String.to_atom
  @allowed_sort_orders ~w(asc desc)

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to real-time updates
    :ok = Phoenix.PubSub.subscribe(EhsEnforcement.PubSub, "offender:updates")
    :ok = Phoenix.PubSub.subscribe(EhsEnforcement.PubSub, "case_created")
    :ok = Phoenix.PubSub.subscribe(EhsEnforcement.PubSub, "notice_created")

    # Load agencies for filter dropdown
    {:ok, agencies} = Enforcement.list_agencies()

    socket =
      socket
      |> assign(:page_title, "Offenders")
      |> assign(:loading, true)
      |> assign(:offenders, [])
      |> assign(:agencies, agencies)
      |> assign(:total_count, 0)
      |> assign(:current_page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:filters, %{})
      |> assign(:search_query, "")
      |> assign(:sort_by, "total_fines")
      |> assign(:sort_order, "desc")
      |> assign(:fuzzy_search, false)
      |> assign(:search_active, false)
      |> assign(:filter_count, 0)
      |> assign(:counting_filters, false)
      |> assign(:filters_applied, false)
      |> assign(:search_task_ref, nil)
      |> assign(:count_task_ref, nil)
      |> load_offenders()

    {:ok, socket, temporary_assigns: [offenders: []]}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket = apply_params(socket, params)
    {:noreply, async_load_offenders(socket)}
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    filters = parse_filters(params["filters"] || %{})
    search_query = get_in(params, ["search", "query"]) || params["search[query]"] || ""

    # Count records that match the filters in real-time
    socket_with_filters =
      socket
      |> assign(:filters, filters)
      |> assign(:search_query, search_query)
      # Reset applied state
      |> assign(:filters_applied, false)

    {:noreply,
     socket_with_filters
     |> assign(:current_page, 1)
     |> count_filtered_offenders()}
  end

  @impl true
  def handle_event("apply_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters_applied, true)
     |> async_load_offenders()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:search_query, "")
     |> assign(:current_page, 1)
     |> assign(:filters_applied, false)
     |> assign(:filter_count, 0)
     |> load_offenders()}
  end

  # Handle form change event (default form behavior)
  @impl true
  def handle_event("validate", params, socket) do
    handle_event("filter_change", params, socket)
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:current_page, 1)
      |> assign(:loading, true)
      |> push_patch(to: build_path(socket, socket.assigns.filters, query, 1))

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", params, socket) do
    {sort_by, sort_order} =
      case params do
        %{"sort_by" => sort_by, "sort_order" => sort_order} -> {sort_by, sort_order}
        %{"sort_by" => sort_by} -> {sort_by, socket.assigns.sort_order}
        %{"sort_order" => sort_order} -> {socket.assigns.sort_by, sort_order}
        _ -> {socket.assigns.sort_by, socket.assigns.sort_order}
      end

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)

    {:noreply, async_load_offenders(socket)}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    next_page = socket.assigns.current_page + 1
    max_page = max_pages(socket.assigns.total_count, socket.assigns.per_page)

    if next_page <= max_page do
      socket =
        socket
        |> assign(:current_page, next_page)
        |> assign(:loading, true)
        |> push_patch(
          to: build_path(socket, socket.assigns.filters, socket.assigns.search_query, next_page)
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    prev_page = max(socket.assigns.current_page - 1, 1)

    socket =
      socket
      |> assign(:current_page, prev_page)
      |> assign(:loading, true)
      |> push_patch(
        to: build_path(socket, socket.assigns.filters, socket.assigns.search_query, prev_page)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_fuzzy_search", _params, socket) do
    fuzzy_search = !socket.assigns.fuzzy_search

    socket =
      socket
      |> assign(:fuzzy_search, fuzzy_search)
      # Reset to first page when changing search mode
      |> assign(:current_page, 1)
      |> assign(:loading, true)
      |> load_offenders()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => page_size_str}, socket) do
    page_size = String.to_integer(page_size_str)

    socket =
      socket
      |> assign(:per_page, page_size)
      # Reset to first page when changing page size
      |> assign(:current_page, 1)
      |> assign(:loading, true)
      |> load_offenders()

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    csv_data = generate_csv(socket.assigns.offenders)

    socket =
      socket
      |> push_event("download_csv", %{
        data: csv_data,
        filename: "offenders_#{Date.utc_today()}.csv"
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_offender", %{"offender_id" => offender_id}, socket) do
    case Ash.get(Enforcement.Offender, offender_id, actor: socket.assigns.current_user) do
      {:ok, offender_record} ->
        case Ash.destroy(offender_record, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Offender deleted successfully")
             |> load_offenders()}

          {:error, error} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to delete offender: #{Exception.message(error)}")
             |> load_offenders()}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Offender not found")
         |> load_offenders()}
    end
  end

  @impl true
  def handle_info({:case_created, _case_record}, socket) do
    {:noreply, refresh_offender_stats(socket)}
  end

  @impl true
  def handle_info({:notice_created, _notice_record}, socket) do
    {:noreply, refresh_offender_stats(socket)}
  end

  @impl true
  def handle_info({:offender_updated, _offender}, socket) do
    {:noreply, refresh_offender_stats(socket)}
  end

  @impl true
  def handle_info({:search_complete, task_ref, {offenders, total_count}}, socket) do
    # Only process if this is the current search task
    if socket.assigns.search_task_ref == task_ref do
      {:noreply,
       socket
       |> assign(:offenders, offenders)
       |> assign(:total_count, total_count)
       |> assign(:loading, false)
       |> assign(:search_task_ref, nil)}
    else
      # Ignore results from cancelled/old searches
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:search_timeout, task_ref}, socket) do
    if socket.assigns.search_task_ref == task_ref do
      require Logger
      Logger.warning("Offender search query timed out after 10 seconds")

      {:noreply,
       socket
       |> assign(:loading, false)
       |> assign(:search_task_ref, nil)
       |> put_flash(:error, "Search timed out. Please try refining your search criteria.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:search_error, task_ref, error}, socket) do
    if socket.assigns.search_task_ref == task_ref do
      require Logger
      Logger.error("Offender search query failed: #{inspect(error)}")

      {:noreply,
       socket
       |> assign(:offenders, [])
       |> assign(:total_count, 0)
       |> assign(:loading, false)
       |> assign(:search_task_ref, nil)
       |> put_flash(:error, "Search failed. Please try again.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:count_complete, task_ref, count}, socket) do
    if socket.assigns.count_task_ref == task_ref do
      {:noreply,
       socket
       |> assign(:filter_count, count)
       |> assign(:counting_filters, false)
       |> assign(:count_task_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:count_timeout, task_ref}, socket) do
    if socket.assigns.count_task_ref == task_ref do
      require Logger
      Logger.warning("Offender filter count query timed out after 5 seconds")

      {:noreply,
       socket
       |> assign(:filter_count, 0)
       |> assign(:counting_filters, false)
       |> assign(:count_task_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:count_error, task_ref, error}, socket) do
    if socket.assigns.count_task_ref == task_ref do
      require Logger
      Logger.error("Offender filter count query failed: #{inspect(error)}")

      {:noreply,
       socket
       |> assign(:filter_count, 0)
       |> assign(:counting_filters, false)
       |> assign(:count_task_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  # Private functions

  defp apply_params(socket, params) do
    filters = parse_filters(params["filters"] || %{})
    search_query = params["search"] || ""
    page = String.to_integer(params["page"] || "1")
    sort_by = params["sort_by"] || "total_fines"
    sort_order = params["sort_order"] || "desc"

    socket
    |> assign(:filters, filters)
    |> assign(:search_query, search_query)
    |> assign(:current_page, page)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
  end

  defp parse_filters(filter_params) do
    %{}
    |> maybe_add_filter(:agency, filter_params["agency"])
    |> maybe_add_filter(:industry, filter_params["industry"])
    |> maybe_add_filter(:local_authority, filter_params["local_authority"])
    |> maybe_add_filter(:business_type, filter_params["business_type"])
    |> maybe_add_filter(:repeat_only, filter_params["repeat_only"])
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, _key, ""), do: filters

  defp maybe_add_filter(filters, key, value) when key == :repeat_only do
    case value do
      "true" -> Map.put(filters, key, true)
      true -> Map.put(filters, key, true)
      _ -> filters
    end
  end

  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)

  defp load_offenders(socket) do
    %{
      filters: filters,
      search_query: search_query,
      sort_by: sort_by,
      sort_order: sort_order,
      current_page: page,
      per_page: page_size,
      fuzzy_search: fuzzy_search,
      filters_applied: filters_applied
    } = socket.assigns

    try do
      # Don't load any offenders unless filters have been explicitly applied
      has_filters = map_size(filters) > 0
      has_search = is_binary(search_query) && String.trim(search_query) != ""

      if (!has_filters && !has_search) || !filters_applied do
        socket
        |> assign(:offenders, [])
        |> assign(:total_count, 0)
        |> assign(:loading, false)
      else
        # Check if fuzzy search is enabled and we have a search query
        use_fuzzy = fuzzy_search && has_search

        {offenders, total_count} =
          if use_fuzzy do
            # Use fuzzy search with pg_trgm
            trimmed_query = String.trim(search_query)

            limited_query =
              if String.length(trimmed_query) > 100 do
                String.slice(trimmed_query, 0, 100)
              else
                trimmed_query
              end

            offset = (page - 1) * page_size

            fuzzy_opts = [
              limit: page_size,
              offset: offset
            ]

            {:ok, fuzzy_results} = Enforcement.fuzzy_search_offenders(limited_query, fuzzy_opts)

            # For fuzzy search, estimate total count
            estimated_total =
              if length(fuzzy_results) == page_size do
                # Estimate there's at least one more page
                page * page_size + 1
              else
                # We've reached the end
                offset + length(fuzzy_results)
              end

            {fuzzy_results, estimated_total}
          else
            # Use regular filtering with optimized indexes
            query_opts =
              build_optimized_query_options(
                filters,
                search_query,
                sort_by,
                sort_order,
                page,
                page_size
              )

            regular_results = Enforcement.list_offenders_with_filters_cached!(query_opts)

            # Get total count using same optimized filter
            count_opts = [filter: build_optimized_filter(filters, search_query)]
            regular_total = Enforcement.count_offenders_cached!(count_opts)

            {regular_results, regular_total}
          end

        socket
        |> assign(:offenders, offenders)
        |> assign(:total_count, total_count)
        |> assign(:loading, false)
      end
    rescue
      error ->
        require Logger
        Logger.error("Failed to load offenders: #{inspect(error)}")

        socket
        |> assign(:offenders, [])
        |> assign(:total_count, 0)
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to load offenders: #{Exception.message(error)}")
    end
  end

  defp build_optimized_query_options(filters, search_query, sort_by, sort_order, page, page_size) do
    offset = (page - 1) * page_size

    [
      filter: build_optimized_filter(filters, search_query),
      sort: build_sort_options(sort_by, sort_order),
      limit: page_size,
      offset: offset
    ]
  end

  # Optimized filter building that formats data for the Enforcement context
  # The Enforcement context handles optimized filtering internally
  defp build_optimized_filter(filters, search_query) do
    %{}
    |> add_filter_if_present(filters, :agency)
    |> add_filter_if_present(filters, :industry)
    |> add_filter_if_present(filters, :local_authority)
    |> add_filter_if_present(filters, :business_type)
    |> add_filter_if_present(filters, :repeat_only)
    |> add_search_filter(search_query)
  end

  defp add_filter_if_present(acc, filters, key) do
    case filters[key] do
      value when is_binary(value) and value != "" -> Map.put(acc, key, value)
      value when not is_nil(value) -> Map.put(acc, key, value)
      _ -> acc
    end
  end

  defp add_search_filter(acc, search_query) do
    case search_query do
      query when is_binary(query) and query != "" ->
        trimmed_query = String.trim(query)

        # Limit search term length to prevent database issues
        limited_query =
          if String.length(trimmed_query) > 100 do
            String.slice(trimmed_query, 0, 100)
          else
            trimmed_query
          end

        search_pattern = "%#{limited_query}%"
        Map.put(acc, :search, search_pattern)

      _ ->
        acc
    end
  end

  defp build_sort_options(sort_by, sort_order) do
    # Security: Validate before converting to atom to prevent DOS attacks
    sort_by_atom =
      if is_binary(sort_by) do
        if sort_by in @allowed_sort_fields do
          String.to_existing_atom(sort_by)
        else
          # Invalid field, use default
          :total_fines
        end
      else
        sort_by
      end

    sort_order_atom =
      if is_binary(sort_order) do
        if sort_order in @allowed_sort_orders do
          String.to_existing_atom(sort_order)
        else
          # Invalid order, use default
          :desc
        end
      else
        sort_order
      end

    case {sort_by_atom, sort_order_atom} do
      {field, dir}
      when field in [
             :name,
             :total_fines,
             :total_cases,
             :total_notices,
             :first_seen_date,
             :last_seen_date
           ] ->
        [{field, dir}]

      _ ->
        # Default sort
        [total_fines: :desc]
    end
  end

  defp build_path(socket, filters, search_query, page) do
    params = %{}

    params = if filters != %{}, do: Map.put(params, "filters", filters), else: params
    params = if search_query != "", do: Map.put(params, "search", search_query), else: params
    params = if page != 1, do: Map.put(params, "page", page), else: params
    params = Map.put(params, "sort_by", socket.assigns.sort_by)
    params = Map.put(params, "sort_order", socket.assigns.sort_order)

    ~p"/offenders?#{params}"
  end

  defp max_pages(total_count, per_page) do
    ceil(total_count / per_page)
  end

  defp refresh_offender_stats(socket) do
    # Reload current page data
    load_offenders(socket)
  end

  defp format_currency(nil), do: "£0"

  defp format_currency(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, _} -> format_currency(decimal)
      :error -> "£0"
    end
  end

  defp format_currency(%Decimal{} = amount) do
    "£#{Decimal.to_string(amount)}"
  end

  defp format_currency(amount) when is_integer(amount) do
    "£#{amount}"
  end

  defp generate_csv(offenders) do
    headers =
      "Name,Local Authority,Industry,Total Cases,Total Notices,Total Fines,First Seen,Last Seen"

    rows =
      Enum.map(offenders, fn offender ->
        [
          offender.name || "",
          offender.local_authority || "",
          offender.industry || "",
          to_string(offender.total_cases || 0),
          to_string(offender.total_notices || 0),
          Decimal.to_string(offender.total_fines || Decimal.new(0)),
          format_date(offender.first_seen_date),
          format_date(offender.last_seen_date)
        ]
        |> Enum.join(",")
      end)

    [headers | rows]
    |> Enum.join("\n")
  end

  defp format_date(nil), do: ""
  defp format_date(date), do: Date.to_string(date)

  defp count_filtered_offenders(socket) do
    %{filters: filters, search_query: search_query} = socket.assigns

    has_filters = map_size(filters) > 0
    has_search = is_binary(search_query) && String.trim(search_query) != ""

    if !has_filters && !has_search do
      socket
      |> assign(:filter_count, 0)
      |> assign(:counting_filters, false)
      |> assign(:count_task_ref, nil)
    else
      # Cancel any previous count task
      socket = cancel_previous_count(socket)

      # Generate unique reference for this count task
      task_ref = make_ref()

      # Capture filter parameters
      count_params = %{
        filters: filters,
        search_query: search_query
      }

      # Get the parent LiveView PID
      parent_pid = self()

      # Spawn async task for count query
      {:ok, _pid} =
        Task.start(fn ->
          # Set timeout for the count query (5 seconds)
          timeout_ref = Process.send_after(parent_pid, {:count_timeout, task_ref}, 5_000)

          try do
            # Execute the count query
            count = execute_offender_count_query(count_params)

            # Cancel timeout if we completed successfully
            _ = Process.cancel_timer(timeout_ref)

            # Send result back to LiveView
            send(parent_pid, {:count_complete, task_ref, count})
          rescue
            error ->
              # Cancel timeout and send error
              _ = Process.cancel_timer(timeout_ref)
              send(parent_pid, {:count_error, task_ref, error})
          end
        end)

      # Return socket with counting state and task reference
      socket
      |> assign(:counting_filters, true)
      |> assign(:count_task_ref, task_ref)
    end
  end

  defp execute_offender_count_query(count_params) do
    %{filters: filters, search_query: search_query} = count_params
    filter = build_optimized_filter(filters, search_query)
    Enforcement.count_offenders_cached!(filter: filter)
  end

  defp cancel_previous_count(socket) do
    case socket.assigns.count_task_ref do
      nil ->
        socket

      _task_ref ->
        socket
        |> assign(:count_task_ref, nil)
    end
  end

  defp async_load_offenders(socket) do
    # Cancel any previous search task
    socket = cancel_previous_search(socket)

    # Generate unique reference for this search
    task_ref = make_ref()

    # Capture the current assigns needed for the search
    search_params = %{
      filters: socket.assigns.filters,
      search_query: socket.assigns.search_query,
      fuzzy_search: socket.assigns.fuzzy_search,
      sort_by: socket.assigns.sort_by,
      sort_order: socket.assigns.sort_order,
      current_page: socket.assigns.current_page,
      per_page: socket.assigns.per_page,
      filters_applied: socket.assigns.filters_applied
    }

    # Get the parent LiveView PID
    parent_pid = self()

    # Spawn async task for database query
    {:ok, _pid} =
      Task.start(fn ->
        # Set timeout for the query (10 seconds)
        timeout_ref = Process.send_after(parent_pid, {:search_timeout, task_ref}, 10_000)

        try do
          # Execute the search query
          result = execute_search_query(search_params)

          # Cancel timeout if we completed successfully
          _ = Process.cancel_timer(timeout_ref)

          # Send results back to LiveView
          send(parent_pid, {:search_complete, task_ref, result})
        rescue
          error ->
            # Cancel timeout and send error
            _ = Process.cancel_timer(timeout_ref)
            send(parent_pid, {:search_error, task_ref, error})
        end
      end)

    # Return socket with loading state and task reference
    socket
    |> assign(:loading, true)
    |> assign(:search_task_ref, task_ref)
  end

  defp execute_search_query(search_params) do
    %{
      filters: filters,
      search_query: search_query,
      fuzzy_search: fuzzy_search,
      sort_by: sort_by,
      sort_order: sort_order,
      current_page: page,
      per_page: page_size,
      filters_applied: filters_applied
    } = search_params

    # Don't load any offenders unless filters have been explicitly applied
    has_filters = map_size(filters) > 0
    has_search = is_binary(search_query) && String.trim(search_query) != ""

    if (!has_filters && !has_search) || !filters_applied do
      {[], 0}
    else
      # Check if fuzzy search is enabled and we have a search query
      use_fuzzy = fuzzy_search && has_search

      if use_fuzzy do
        # Use fuzzy search with pg_trgm
        trimmed_query = String.trim(search_query)

        limited_query =
          if String.length(trimmed_query) > 100 do
            String.slice(trimmed_query, 0, 100)
          else
            trimmed_query
          end

        offset = (page - 1) * page_size

        fuzzy_opts = [
          limit: page_size,
          offset: offset
        ]

        {:ok, fuzzy_results} = Enforcement.fuzzy_search_offenders(limited_query, fuzzy_opts)

        # For fuzzy search, estimate total count
        estimated_total =
          if length(fuzzy_results) == page_size do
            # Estimate there's at least one more page
            page * page_size + 1
          else
            # We've reached the end
            offset + length(fuzzy_results)
          end

        {fuzzy_results, estimated_total}
      else
        # Use regular filtering with optimized indexes
        query_opts = [
          filter: build_optimized_filter(filters, search_query),
          sort: build_sort_options(sort_by, sort_order),
          limit: page_size,
          offset: (page - 1) * page_size
        ]

        regular_results = Enforcement.list_offenders_with_filters_cached!(query_opts)

        # Get total count using same optimized filter
        count_opts = [filter: build_optimized_filter(filters, search_query)]
        regular_total = Enforcement.count_offenders_cached!(count_opts)

        {regular_results, regular_total}
      end
    end
  end

  defp cancel_previous_search(socket) do
    case socket.assigns.search_task_ref do
      nil ->
        socket

      _task_ref ->
        # Note: We don't actually kill the task (it's not supervised)
        # Instead, we just ignore its results in handle_info
        # The task will complete and its message will be discarded
        socket
        |> assign(:search_task_ref, nil)
    end
  end
end
