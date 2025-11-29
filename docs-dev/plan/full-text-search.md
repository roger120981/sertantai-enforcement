# Full-Text Search Implementation Plan

**Status**: Ready to implement
**Effort**: 1 week
**Target**: Week of January 20, 2025
**Priority Score**: 350 (highest)

---

## User Story

*"As a compliance professional, I want to search for all cases involving 'fall from height' so I can understand the enforcement patterns around this specific hazard."*

---

## Implementation

### Infrastructure Already in Place
- **pg_trgm extension**: Enabled in PostgreSQL
- **GIN indexes**: Created on `offenders.name`, `offenders.normalized_name`
- **Ash filtering**: Supports custom filter expressions

### What's Missing
- Search UI component (input box with debouncing)
- Ash custom filter for full-text search
- Search across multiple fields simultaneously

---

## Technical Approach

### 1. Create Search Bar Component

```elixir
# lib/ehs_enforcement_web/components/search_bar_component.ex
defmodule EhsEnforcementWeb.SearchBarComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="search-bar">
      <input
        type="text"
        placeholder="Search cases, offenders, legislation..."
        value={@query}
        phx-change="search"
        phx-debounce="300"
        phx-target={@myself}
      />
      <%= if @query != "" do %>
        <button phx-click="clear_search" phx-target={@myself}>Clear</button>
      <% end %>
      <%= if @result_count do %>
        <span class="result-count"><%= @result_count %> results</span>
      <% end %>
    </div>
    """
  end

  def handle_event("search", %{"value" => query}, socket) do
    send(self(), {:search_changed, query})
    {:noreply, assign(socket, query: query)}
  end

  def handle_event("clear_search", _params, socket) do
    send(self(), {:search_changed, ""})
    {:noreply, assign(socket, query: "")}
  end
end
```

### 2. Add Ash Custom Filter Expression

```elixir
# lib/ehs_enforcement/enforcement/resources/case.ex
defmodule EhsEnforcement.Enforcement.Resources.Case do
  # ... existing code ...

  calculations do
    calculate :search_rank, :float do
      argument :search_term, :string, allow_nil?: false

      calculation fn records, context ->
        search_term = context.arguments.search_term

        # Use PostgreSQL similarity function
        query = """
        SELECT
          id,
          GREATEST(
            similarity(offender_name, $1),
            similarity(offence_breaches, $1),
            similarity(regulator_function, $1)
          ) as rank
        FROM cases
        WHERE
          offender_name % $1 OR
          offence_breaches % $1 OR
          regulator_function % $1
        ORDER BY rank DESC
        """

        # Execute raw SQL for complex similarity search
        # (Ash doesn't have built-in pg_trgm support yet)
      end
    end
  end

  # Simpler approach: Use Ash filter with ILIKE
  def search_filter(query_string) do
    search_pattern = "%#{query_string}%"

    Ash.Query.filter(
      Case,
      expr(
        offender.name ilike ^search_pattern or
        offence_breaches ilike ^search_pattern or
        regulator_function ilike ^search_pattern or
        offence_result ilike ^search_pattern
      )
    )
  end
end
```

### 3. Update LiveView with Search

```elixir
# lib/ehs_enforcement_web/live/case_live/index.ex
def handle_info({:search_changed, query}, socket) do
  cases = if query == "" do
    Enforcement.list_cases()
  else
    Case.search_filter(query)
    |> Enforcement.read!()
  end

  {:noreply, assign(socket, cases: cases, search_query: query)}
end
```

### 4. Highlight Matching Text

```elixir
# Helper function to highlight search terms
defmodule EhsEnforcementWeb.SearchHelpers do
  def highlight(text, search_term) when is_binary(text) and search_term != "" do
    # Escape HTML first
    safe_text = Phoenix.HTML.html_escape(text)

    # Highlight matching terms (case-insensitive)
    regex = ~r/#{Regex.escape(search_term)}/i
    String.replace(safe_text, regex, fn match ->
      ~s(<mark class="highlight">#{match}</mark>)
    end)
  end

  def highlight(text, _), do: text
end
```

Usage in template:
```heex
<td><%= raw(highlight(@case.offender.name, @search_query)) %></td>
```

---

## Advanced Features (Optional, Week 2)

### Fuzzy Matching with pg_trgm

```sql
-- PostgreSQL query for fuzzy search with similarity threshold
SELECT
  c.*,
  similarity(o.name, 'ACME Construction') as name_sim,
  similarity(c.offence_breaches, 'fall from height') as breach_sim
FROM cases c
JOIN offenders o ON c.offender_id = o.id
WHERE
  o.name % 'ACME Construction' OR  -- % operator = similar to
  c.offence_breaches % 'fall from height'
ORDER BY GREATEST(name_sim, breach_sim) DESC
LIMIT 50;
```

### Search Suggestions ("Did you mean?")

```elixir
defmodule EhsEnforcement.Search.Suggestions do
  @common_terms [
    "fall from height",
    "asbestos",
    "machinery",
    "confined space",
    "manual handling",
    "electricity",
    "vehicle",
    "fire",
    "hazardous substance"
  ]

  def suggest(query) do
    @common_terms
    |> Enum.map(fn term ->
      {term, String.jaro_distance(query, term)}
    end)
    |> Enum.filter(fn {_term, distance} -> distance > 0.7 end)
    |> Enum.sort_by(fn {_term, distance} -> distance end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {term, _} -> term end)
  end
end
```

---

## Testing

```elixir
defmodule EhsEnforcementWeb.CaseLive.SearchTest do
  use EhsEnforcementWeb.ConnCase
  import Phoenix.LiveViewTest

  test "searches cases by offender name", %{conn: conn} do
    {:ok, case1} = create_case(offender_name: "ACME Construction Ltd")
    {:ok, case2} = create_case(offender_name: "XYZ Manufacturing")

    {:ok, view, _html} = live(conn, "/cases")

    # Type search query
    view
    |> element("input[type='text']")
    |> render_change(%{"value" => "ACME"})

    # Verify only ACME case shown
    assert has_element?(view, "[data-case-id='#{case1.id}']")
    refute has_element?(view, "[data-case-id='#{case2.id}']")
  end

  test "searches across multiple fields", %{conn: conn} do
    {:ok, case1} = create_case(offence_breaches: "fall from height")

    {:ok, view, _html} = live(conn, "/cases")

    view
    |> element("input[type='text']")
    |> render_change(%{"value" => "fall"})

    assert has_element?(view, "[data-case-id='#{case1.id}']")
  end
end
```

---

## Success Criteria
- ✅ Search bar visible on all list views
- ✅ Results update in real-time (300ms debounce)
- ✅ Search across offender names, breaches, legislation
- ✅ Matching text highlighted in results
- ✅ "No results" message when no matches
- ✅ Tests pass

---

**Estimated Effort**: 20-30 hours
**Target Completion**: January 20, 2025
