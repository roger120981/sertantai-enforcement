# Industry Filtering Implementation Plan

**Status**: Ready to implement
**Effort**: 1 week
**Target**: Week of January 13, 2025
**Priority Score**: 350 (highest)

---

## User Story

*"As a compliance professional in the construction industry, I want to see only enforcement actions against construction companies so I can benchmark our performance against peers."*

---

## Implementation

### Data Already Available
- **SIC codes**: `Offender.sic_code` field (HSE data)
- **EA sectors**: `Offender.industry_sectors` array (EA data: Waste Management, Water, etc.)
- **Industry field**: `Offender.industry` text field

### UI Components Needed

1. **SIC Code Dropdown** (Cases/Notices pages)
   - Searchable dropdown (LiveView `phx-change` event)
   - Load standard SIC 2007 codes from static JSON file
   - Format: "46.72 - Wholesale of metals and metal ores"

2. **EA Sector Multi-Select** (Cases/Notices pages)
   - Checkbox list of EA sectors
   - Sectors: Waste Management, Water & Sewerage, Installations, Radioactive Substances, etc.

3. **Filter Chips** (Show active filters)
   - Display selected filters as removable chips
   - Click X to remove filter

4. **URL Persistence**
   - Filter params in URL: `?sic=4672&ea_sectors[]=waste`
   - Shareable links

---

## Technical Tasks

### 1. Create SIC Code Lookup Data
```elixir
# priv/static/data/sic_codes.json
[
  {"code": "01110", "description": "Growing of cereals (except rice), leguminous crops and oil seeds"},
  {"code": "46720", "description": "Wholesale of metals and metal ores"},
  ...
]
```

### 2. Add Filter Component
```elixir
# lib/ehs_enforcement_web/components/filter_component.ex
defmodule EhsEnforcementWeb.FilterComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="filters">
      <div class="filter-group">
        <label>SIC Code</label>
        <select phx-change="filter_sic" phx-target={@myself}>
          <option value="">All Industries</option>
          <%= for {code, desc} <- @sic_codes do %>
            <option value={code} selected={@selected_sic == code}>
              <%= code %> - <%= desc %>
            </option>
          <% end %>
        </select>
      </div>

      <div class="filter-group">
        <label>EA Sector</label>
        <%= for sector <- @ea_sectors do %>
          <label>
            <input type="checkbox" value={sector} phx-click="toggle_sector" phx-target={@myself} checked={sector in @selected_sectors} />
            <%= sector %>
          </label>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("filter_sic", %{"value" => sic}, socket) do
    send(self(), {:filter_changed, :sic, sic})
    {:noreply, socket}
  end

  def handle_event("toggle_sector", %{"value" => sector}, socket) do
    send(self(), {:filter_changed, :sector, sector})
    {:noreply, socket}
  end
end
```

### 3. Update LiveView to Handle Filters
```elixir
# lib/ehs_enforcement_web/live/case_live/index.ex
def handle_params(params, _url, socket) do
  filters = build_filters(params)

  {:ok, cases} = Enforcement.list_cases(
    filters: filters,
    actor: socket.assigns.current_user
  )

  {:noreply, assign(socket, cases: cases, filters: filters)}
end

defp build_filters(params) do
  []
  |> maybe_add_sic_filter(params["sic"])
  |> maybe_add_sector_filter(params["ea_sectors"])
end

defp maybe_add_sic_filter(filters, nil), do: filters
defp maybe_add_sic_filter(filters, sic) when sic != "" do
  [offender: [sic_code: [eq: sic]] | filters]
end
```

### 4. Add Ash Filter to Case Resource
```elixir
# No changes needed! Ash automatically supports filtering on relationship attributes:
# Ash.read(Case, filters: [offender: [sic_code: [eq: "46720"]]])
```

### 5. Pre-Compute Industry Statistics (Optional)
```elixir
# Add calculation to Metrics resource
calculations do
  calculate :cases_by_industry, {:array, :map} do
    calculation fn _records, _context ->
      Enforcement.case_count_by_industry()
    end
  end
end
```

---

## Testing

```elixir
defmodule EhsEnforcementWeb.CaseLive.FilterTest do
  use EhsEnforcementWeb.ConnCase
  import Phoenix.LiveViewTest

  test "filters cases by SIC code", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cases")

    # Select SIC code from dropdown
    view
    |> element("select[phx-change='filter_sic']")
    |> render_change(%{"value" => "46720"})

    # Verify URL updated
    assert_patch(view, "/cases?sic=46720")

    # Verify filtered cases displayed
    assert has_element?(view, "[data-sic='46720']")
    refute has_element?(view, "[data-sic='01110']")
  end
end
```

---

## Success Criteria
- ✅ SIC code dropdown functional
- ✅ EA sector checkboxes functional
- ✅ Filters persist in URL
- ✅ Filter chips display and are removable
- ✅ Case count updates with filters applied
- ✅ Tests pass

---

**Estimated Effort**: 20-30 hours
**Target Completion**: January 13, 2025
