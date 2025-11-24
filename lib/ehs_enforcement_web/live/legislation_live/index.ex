defmodule EhsEnforcementWeb.LegislationLive.Index do
  use EhsEnforcementWeb, :live_view

  require Ash.Query

  alias EhsEnforcement.Enforcement

  @default_page_size 20
  @max_page_size 100

  # Security: Whitelist allowed sort fields to prevent DOS via String.to_atom
  @allowed_sort_fields ~w(legislation_title legislation_year legislation_type)

  # Security: Whitelist allowed filter keys to prevent DOS via String.to_atom
  @allowed_filter_keys ~w(legislation_type agency year_from year_to search)

  # Security: Whitelist allowed agency codes to prevent DOS via String.to_atom
  @allowed_agency_codes ~w(hse ea sepa nrw)

  # Security: Whitelist allowed legislation types to prevent DOS via String.to_atom
  @allowed_legislation_types ~w(act regulation statutory_instrument order rules directive)

  @impl true
  def mount(_params, _session, socket) do
    :ok = Phoenix.PubSub.subscribe(EhsEnforcement.PubSub, "legislation_updates")

    {:ok,
     socket
     |> assign(:filters, %{})
     |> assign(:sort_by, :legislation_year)
     |> assign(:sort_dir, :desc)
     |> assign(:page, 1)
     |> assign(:page_size, @default_page_size)
     |> assign(:total_legislation, 0)
     |> assign(:loading, true)
     |> assign(:search_active, false)
     |> assign(:fuzzy_search, false)
     |> assign(:sort_requested, false)
     |> assign(:filter_count, 0)
     |> assign(:counting_filters, false)
     |> assign(:filters_applied, false)
     |> assign(:search_task_ref, nil)
     |> assign(:count_task_ref, nil)
     |> load_legislation(), temporary_assigns: [legislation: []]}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")

    filters =
      case params["filter"] do
        "search" ->
          socket.assigns.filters

        _ ->
          socket.assigns.filters
      end

    search_active = params["filter"] == "search"

    {:noreply,
     socket
     |> assign(:page, max(1, page))
     |> assign(:filters, filters)
     |> assign(:search_active, search_active)
     |> load_legislation()}
  end

  @impl true
  def handle_event("filter", %{"filters" => filter_params}, socket) do
    filters = atomize_and_clean_filters(filter_params)

    # Count records that match the filters in real-time
    socket_with_filters = assign(socket, :filters, filters)

    {:noreply,
     socket_with_filters
     |> assign(:page, 1)
     |> assign(:filters_applied, false)
     |> assign(:counting_filters, true)
     |> count_filtered_legislation()}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    updated_filters = Map.delete(socket.assigns.filters, :search)

    {:noreply,
     socket
     |> assign(:filters, updated_filters)
     |> assign(:page, 1)
     |> assign(:filters_applied, false)
     |> assign(:counting_filters, true)
     |> count_filtered_legislation()}
  end

  @impl true
  def handle_event("apply_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters_applied, true)
     |> assign(:page, 1)
     |> async_load_legislation()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:page, 1)
     |> assign(:sort_requested, false)
     |> assign(:filters_applied, false)
     |> assign(:filter_count, 0)
     |> load_legislation()}
  end

  @impl true
  def handle_event("toggle_fuzzy_search", _params, socket) do
    fuzzy_search = !socket.assigns.fuzzy_search

    {:noreply,
     socket
     |> assign(:fuzzy_search, fuzzy_search)
     |> assign(:page, 1)
     |> load_legislation()}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    # Security: Validate field against whitelist before converting to atom
    if field in @allowed_sort_fields do
      sort_by = String.to_existing_atom(field)
      # Toggle sort direction if same field, otherwise default to desc
      sort_dir =
        if socket.assigns.sort_by == sort_by do
          if socket.assigns.sort_dir == :desc, do: :asc, else: :desc
        else
          :desc
        end

      {:noreply,
       socket
       |> assign(:sort_by, sort_by)
       |> assign(:sort_dir, sort_dir)
       |> assign(:page, 1)
       |> assign(:sort_requested, true)
       |> async_load_legislation()}
    else
      # Reject invalid sort field
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("paginate", %{"page" => page_str}, socket) do
    case Integer.parse(page_str) do
      {page, _} when page > 0 ->
        total_pages =
          calculate_total_pages(socket.assigns.total_legislation, socket.assigns.page_size)

        valid_page = min(page, total_pages)

        {:noreply,
         socket
         |> assign(:page, valid_page)
         |> async_load_legislation()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => size_str}, socket) do
    case Integer.parse(size_str) do
      {size, _} when size > 0 and size <= @max_page_size ->
        {:noreply,
         socket
         |> assign(:page_size, size)
         |> assign(:page, 1)
         |> push_patch(to: ~p"/legislation")
         |> load_legislation()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_legislation", %{"legislation_id" => legislation_id}, socket) do
    case Ash.get(Enforcement.Legislation, legislation_id, actor: socket.assigns.current_user) do
      {:ok, legislation_record} ->
        case Ash.destroy(legislation_record, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Legislation deleted successfully")
             |> load_legislation()}

          {:error, error} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to delete legislation: #{inspect(error)}")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Legislation not found")}
    end
  end

  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:legislation_created, _legislation}, socket) do
    {:noreply, load_legislation(socket)}
  end

  @impl true
  def handle_info({:legislation_updated, _legislation}, socket) do
    {:noreply, load_legislation(socket)}
  end

  @impl true
  def handle_info({:legislation_deleted, _legislation}, socket) do
    {:noreply, load_legislation(socket)}
  end

  @impl true
  def handle_info({:search_complete, task_ref, {legislation, total_legislation}}, socket) do
    # Only process if this is the current search task
    if socket.assigns.search_task_ref == task_ref do
      {:noreply,
       socket
       |> assign(:legislation, legislation)
       |> assign(:total_legislation, total_legislation)
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
      Logger.warning("Legislation search query timed out after 10 seconds")

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
      Logger.error("Legislation search query failed: #{inspect(error)}")

      {:noreply,
       socket
       |> assign(:legislation, [])
       |> assign(:total_legislation, 0)
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
      Logger.warning("Legislation filter count query timed out after 5 seconds")

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
      Logger.error("Legislation filter count query failed: #{inspect(error)}")

      {:noreply,
       socket
       |> assign(:filter_count, 0)
       |> assign(:counting_filters, false)
       |> assign(:count_task_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  defp count_filtered_legislation(socket) do
    %{filters: filters} = socket.assigns

    if map_size(filters) == 0 do
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
      count_params = %{filters: filters}

      # Get the parent LiveView PID
      parent_pid = self()

      # Spawn async task for count query
      {:ok, _pid} =
        Task.start(fn ->
          # Set timeout for the count query (5 seconds)
          timeout_ref = Process.send_after(parent_pid, {:count_timeout, task_ref}, 5_000)

          try do
            # Execute the count query
            count = execute_legislation_count_query(count_params)

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

  defp execute_legislation_count_query(count_params) do
    %{filters: filters} = count_params
    count_filters = build_filter(filters)
    count_opts = [filter: count_filters]
    Enforcement.count_legislation!(count_opts)
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

  defp load_legislation(socket) do
    %{
      filters: filters,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page,
      page_size: page_size,
      fuzzy_search: fuzzy_search,
      sort_requested: sort_requested,
      filters_applied: filters_applied
    } = socket.assigns

    try do
      if !filters_applied && map_size(filters) == 0 && !sort_requested do
        socket
        |> assign(:legislation, [])
        |> assign(:total_legislation, 0)
        |> assign(:loading, false)
      else
        combined_search = filters[:search] || ""

        use_fuzzy =
          fuzzy_search && is_binary(combined_search) && String.trim(combined_search) != ""

        {legislation, total_legislation} =
          if use_fuzzy do
            trimmed_query = String.trim(combined_search)

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

            {:ok, fuzzy_results} = Enforcement.search_legislation_title(limited_query, fuzzy_opts)

            estimated_total =
              if length(fuzzy_results) == page_size do
                page * page_size + 1
              else
                offset + length(fuzzy_results)
              end

            {fuzzy_results, estimated_total}
          else
            query_opts = build_query_options(filters, sort_by, sort_dir, page, page_size)
            regular_results = Enforcement.list_legislation_with_filters!(query_opts)

            count_filters = build_filter(filters)

            count_filters =
              if combined_search != "" do
                Map.put(count_filters, :search, "%#{String.trim(combined_search)}%")
              else
                count_filters
              end

            count_opts = [filter: count_filters]
            regular_total = Enforcement.count_legislation!(count_opts)

            {regular_results, regular_total}
          end

        socket
        |> assign(:legislation, legislation)
        |> assign(:total_legislation, total_legislation)
        |> assign(:loading, false)
        |> assign(:sort_requested, false)
      end
    rescue
      error ->
        require Logger
        Logger.error("Failed to load legislation: #{inspect(error)}")

        socket
        |> assign(:legislation, [])
        |> assign(:total_legislation, 0)
        |> assign(:loading, false)
    end
  end

  defp build_query_options(filters, sort_by, sort_dir, page, page_size) do
    offset = (page - 1) * page_size

    filter = build_filter(filters)

    [
      filter: filter,
      sort: build_sort_options(sort_by, sort_dir),
      limit: page_size,
      offset: offset
    ]
  end

  defp build_filter(filters) do
    %{}
    |> add_filter_if_present(filters, :legislation_type)
    |> add_agency_filter(filters)
    |> add_year_range_filters(filters)
    |> add_search_filter(filters)
  end

  defp add_filter_if_present(acc, filters, key) do
    case filters[key] do
      value when is_binary(value) and value != "" ->
        atom_value =
          if key == :legislation_type do
            # Security: Validate legislation type before converting to atom
            if value in @allowed_legislation_types do
              String.to_existing_atom(value)
            else
              # Invalid type, skip this filter
              nil
            end
          else
            value
          end

        if atom_value do
          Map.put(acc, key, atom_value)
        else
          acc
        end

      _ ->
        acc
    end
  end

  defp add_agency_filter(acc, filters) do
    case filters[:agency] do
      agency when is_binary(agency) and agency != "" ->
        # Security: Validate agency code before converting to atom
        if agency in @allowed_agency_codes do
          agency_atom = String.to_existing_atom(agency)
          Map.put(acc, :agency, agency_atom)
        else
          # Invalid agency code, skip this filter
          acc
        end

      _ ->
        acc
    end
  end

  defp add_year_range_filters(acc, filters) do
    year_conditions = []

    year_conditions =
      case filters[:year_from] do
        year when is_binary(year) and year != "" ->
          case Integer.parse(year) do
            {parsed_year, _} -> [{:greater_than_or_equal_to, parsed_year} | year_conditions]
            _ -> year_conditions
          end

        _ ->
          year_conditions
      end

    year_conditions =
      case filters[:year_to] do
        year when is_binary(year) and year != "" ->
          case Integer.parse(year) do
            {parsed_year, _} -> [{:less_than_or_equal_to, parsed_year} | year_conditions]
            _ -> year_conditions
          end

        _ ->
          year_conditions
      end

    if year_conditions != [] do
      Map.put(acc, :legislation_year, year_conditions)
    else
      acc
    end
  end

  defp add_search_filter(acc, filters) do
    case filters[:search] do
      query when is_binary(query) and query != "" ->
        trimmed_query = String.trim(query)

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

  defp build_sort_options(sort_by, sort_dir) do
    case {sort_by, sort_dir} do
      {field, dir} when field in [:legislation_title, :legislation_year, :legislation_type] ->
        [{field, dir}]

      _ ->
        [legislation_year: :desc]
    end
  end

  defp atomize_and_clean_filters(filter_params) do
    filter_params
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_binary(value) ->
        # Security: Validate filter key before converting to atom
        if key in @allowed_filter_keys do
          atom_key = String.to_existing_atom(key)
          cleaned_value = String.trim(value)

          if cleaned_value != "" do
            Map.put(acc, atom_key, cleaned_value)
          else
            acc
          end
        else
          # Invalid filter key, skip it
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp calculate_total_pages(0, _page_size), do: 1

  defp calculate_total_pages(total_legislation, page_size) do
    ceil(total_legislation / page_size)
  end

  defp format_legislation_type(:act), do: "Act"
  defp format_legislation_type(:regulation), do: "Regulation"
  defp format_legislation_type(:order), do: "Order"
  defp format_legislation_type(:acop), do: "ACOP"
  defp format_legislation_type(type) when is_atom(type), do: String.capitalize(to_string(type))
  defp format_legislation_type(_), do: "Unknown"

  defp total_pages(total_count, page_size) do
    ceil(total_count / page_size)
  end

  defp get_sort_icon(assigns, field) do
    # Security: Validate field before converting to atom
    if field in @allowed_sort_fields do
      field_atom = String.to_existing_atom(field)

      if assigns.sort_by == field_atom do
        if assigns.sort_dir == :desc do
          "↓"
        else
          "↑"
        end
      else
        ""
      end
    else
      # Invalid field, no icon
      ""
    end
  end

  defp legislation_type_class(:act), do: "bg-blue-100 text-blue-800"
  defp legislation_type_class(:regulation), do: "bg-green-100 text-green-800"
  defp legislation_type_class(:order), do: "bg-yellow-100 text-yellow-800"
  defp legislation_type_class(:acop), do: "bg-purple-100 text-purple-800"
  defp legislation_type_class(_), do: "bg-gray-100 text-gray-800"

  defp async_load_legislation(socket) do
    # Cancel any previous search task
    socket = cancel_previous_search(socket)

    # Generate unique reference for this search
    task_ref = make_ref()

    # Capture the current assigns needed for the search
    search_params = %{
      filters: socket.assigns.filters,
      fuzzy_search: socket.assigns.fuzzy_search,
      sort_by: socket.assigns.sort_by,
      sort_dir: socket.assigns.sort_dir,
      page: socket.assigns.page,
      page_size: socket.assigns.page_size,
      sort_requested: socket.assigns.sort_requested,
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
      fuzzy_search: fuzzy_search,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page,
      page_size: page_size,
      sort_requested: sort_requested,
      filters_applied: filters_applied
    } = search_params

    if !filters_applied && map_size(filters) == 0 && !sort_requested do
      {[], 0}
    else
      combined_search = filters[:search] || ""
      use_fuzzy = fuzzy_search && is_binary(combined_search) && String.trim(combined_search) != ""

      if use_fuzzy do
        trimmed_query = String.trim(combined_search)

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

        {:ok, fuzzy_results} = Enforcement.search_legislation_title(limited_query, fuzzy_opts)

        estimated_total =
          if length(fuzzy_results) == page_size do
            page * page_size + 1
          else
            offset + length(fuzzy_results)
          end

        {fuzzy_results, estimated_total}
      else
        query_opts = [
          filter: build_filter(filters),
          sort: build_sort_options(sort_by, sort_dir),
          limit: page_size,
          offset: (page - 1) * page_size
        ]

        regular_results = Enforcement.list_legislation_with_filters!(query_opts)

        count_filters = build_filter(filters)

        count_filters =
          if combined_search != "" do
            Map.put(count_filters, :search, "%#{String.trim(combined_search)}%")
          else
            count_filters
          end

        count_opts = [filter: count_filters]
        regular_total = Enforcement.count_legislation!(count_opts)

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
