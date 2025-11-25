<script lang="ts">
  import { onMount } from 'svelte'
  import { browser } from '$app/environment'
  import {
    initLegislationSync,
    legislationSyncProgress,
    cachedLegislation,
  } from '$lib/electric/sync-legislation'
  import { checkElectricHealth } from '$lib/electric/sync'
  import { TableKit } from '@shotleybuilder/svelte-table-kit'
  import type { ColumnDef } from '@tanstack/svelte-table'
  import type { Legislation } from '$lib/db/schema'
  import { ViewSelector, SaveViewModal, activeViewId, activeViewModified, viewActions } from 'svelte-table-views-tanstack'
  import type { TableConfig, SavedView } from 'svelte-table-views-tanstack'
  import NaturalLanguageQuery from '$lib/components/NaturalLanguageQuery.svelte'

  // State
  let loading = true
  let electricHealthy = false
  let baselineLoaded = false

  // Saved views state
  let showSaveModal = false
  let capturedConfig: TableConfig | null = null

  // AI-generated configuration from NL query
  let aiFilters: any[] = []
  let aiSort: { columnId: string; direction: 'asc' | 'desc' } | null = null
  let aiColumns: string[] = []
  let aiColumnOrder: string[] = []
  let configVersion = 0 // Track config version for reactive updates

  // Initialize sync on mount (WITH baseline - all legislation)
  onMount(async () => {
    try {
      electricHealthy = await checkElectricHealth()
      console.log('[Legislation Page] Electric health:', electricHealthy)

      if (!electricHealthy) {
        console.warn('[Legislation Page] Electric service unavailable, working offline')
        loading = false
        return
      }

      // Initialize with baseline (all legislation)
      await initLegislationSync()
      console.log('[Legislation Page] Baseline sync complete - all legislation loaded')
      baselineLoaded = true
      loading = false
    } catch (err) {
      console.error('[Legislation Page] Initialization error:', err)
      loading = false
    }
  })

  // Helper function to format legislation type
  function formatLegislationType(type: string): string {
    const types: Record<string, string> = {
      act: 'Act',
      regulation: 'Regulation',
      order: 'Order',
      acop: 'ACOP',
    }
    return types[type] || type
  }

  // Column definitions
  const columns: ColumnDef<Legislation>[] = [
    {
      id: 'legislation_title',
      accessorKey: 'legislation_title',
      header: 'Title',
      cell: (info) => info.getValue() || 'N/A',
      enableSorting: true,
      enableGrouping: false,
    },
    {
      id: 'legislation_year',
      accessorKey: 'legislation_year',
      header: 'Year',
      cell: (info) => {
        const year = info.getValue() as number | null
        return year ? year : '—'
      },
      enableSorting: true,
      enableGrouping: true,
    },
    {
      id: 'legislation_number',
      accessorKey: 'legislation_number',
      header: 'Number',
      cell: (info) => {
        const num = info.getValue() as number | null
        return num ? num : '—'
      },
      enableSorting: true,
    },
    {
      id: 'legislation_type',
      accessorKey: 'legislation_type',
      header: 'Type',
      cell: (info) => {
        const type = info.getValue() as string
        return formatLegislationType(type)
      },
      enableSorting: true,
      enableGrouping: true,
    },
    {
      id: 'total_offences',
      accessorKey: 'total_offences',
      header: 'Offences',
      cell: (info) => {
        const total = info.getValue() as number
        return total > 0 ? total : '0'
      },
      enableSorting: true,
    },
    {
      id: 'total_cases',
      accessorKey: 'total_cases',
      header: 'Cases',
      cell: (info) => {
        const total = info.getValue() as number
        return total > 0 ? total : '0'
      },
      enableSorting: true,
    },
    {
      id: 'total_notices',
      accessorKey: 'total_notices',
      header: 'Notices',
      cell: (info) => {
        const total = info.getValue() as number
        return total > 0 ? total : '0'
      },
      enableSorting: true,
    },
    {
      id: 'first_used_date',
      accessorKey: 'first_used_date',
      header: 'First Used',
      cell: (info) => {
        const date = info.getValue() as string | null
        if (!date) return '—'
        return new Date(date).toLocaleDateString()
      },
      enableSorting: true,
    },
    {
      id: 'last_used_date',
      accessorKey: 'last_used_date',
      header: 'Last Used',
      cell: (info) => {
        const date = info.getValue() as string | null
        if (!date) return '—'
        return new Date(date).toLocaleDateString()
      },
      enableSorting: true,
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: (info) => {
        const legislationId = info.row.original.id
        return `<a href="/legislation/${legislationId}" class="text-blue-600 hover:text-blue-800 font-medium">View</a>`
      },
      enableSorting: false,
    },
  ]

  // Reactive table data from Svelte store
  $: data = $cachedLegislation || []

  // Debug logging for tableKitConfig
  $: if (browser) {
    console.log('[Legislation Page] TableKit Config:', {
      configVersion,
      hasAiConfig,
      config: tableKitConfig
    })
  }

  // Handle NL query success - update AI configuration
  function handleQuerySuccess(filters: any[], sort: any | null, columns?: string[], columnOrder?: string[]) {
    console.log('[Legislation Page] NL Query Success:', { filters, sort, columns, columnOrder })

    aiFilters = filters || []
    aiSort = sort
    aiColumns = columns || []
    aiColumnOrder = columnOrder || []

    // Clear active view when new query is made
    viewActions.clearActive()

    // Increment version to trigger config update
    configVersion++
    console.log('[Legislation Page] Updated config version:', configVersion)
  }

  // View management functions
  function captureCurrentConfig(): TableConfig {
    // Capture current table state for saving
    return {
      filters: aiFilters,
      sort: aiSort,
      columns: aiColumns.length > 0 ? aiColumns : columns.map(c => String(c.id)),
      columnOrder: aiColumnOrder.length > 0 ? aiColumnOrder : columns.map(c => String(c.id)),
      columnWidths: {},
      pageSize: 20,
      grouping: []
    }
  }

  function applyViewConfig(config: TableConfig) {
    console.log('[Legislation Page] Applying view config:', config)

    // Get available column IDs
    const availableColumnIds = new Set(columns.map(c => String(c.id)))

    // Validate columns - filter out missing columns
    const validColumns = config.columns.filter(colId => availableColumnIds.has(colId))
    const validColumnOrder = config.columnOrder.filter(colId => availableColumnIds.has(colId))

    // Check for missing columns
    const missingColumns = config.columns.filter(colId => !availableColumnIds.has(colId))
    if (missingColumns.length > 0) {
      console.warn('[Legislation Page] View contains missing columns:', missingColumns)
    }

    // Set AI config which will reactively update TableKit
    aiFilters = config.filters
    aiSort = config.sort
    aiColumns = validColumns.length > 0 ? validColumns : []
    aiColumnOrder = validColumnOrder.length > 0 ? validColumnOrder : []
    configVersion++
  }

  async function handleViewSelected(event: CustomEvent<{ view: SavedView }>) {
    const view = event.detail.view
    console.log('[Legislation Page] View selected:', view.name)

    // Clear AI config
    aiFilters = []
    aiSort = null
    aiColumns = []
    aiColumnOrder = []
    configVersion++

    // Apply view config to table
    setTimeout(() => {
      applyViewConfig(view.config)
    }, 100)
  }

  function handleSaveView() {
    try {
      capturedConfig = captureCurrentConfig()
      console.log('[Legislation Page] Opening save modal with config:', capturedConfig)
      showSaveModal = true
    } catch (err) {
      console.error('[Legislation Page] Failed to capture table config:', err)
      alert('Failed to capture table configuration. Please try again.')
    }
  }

  async function handleUpdateView() {
    const activeId = $activeViewId
    if (!activeId) return

    try {
      const config = captureCurrentConfig()
      await viewActions.update(activeId, { config })
      console.log('[Legislation Page] View updated successfully')
    } catch (err) {
      console.error('[Legislation Page] Failed to update view:', err)
      alert('Failed to update view. Please try again.')
    }
  }

  function handleViewSaved(event: CustomEvent<{ id: string; name: string }>) {
    console.log('[Legislation Page] View saved:', event.detail.name)
  }

  // Build TableKit configuration from AI (reactive - updates when configVersion changes)
  $: hasAiConfig = aiFilters.length > 0 || aiSort !== null || aiColumns.length > 0 || aiColumnOrder.length > 0

  $: tableKitConfig = hasAiConfig ? {
    id: `ai_query_v${configVersion}`,
    version: '1.0',
    defaultFilters: aiFilters.length > 0 ? aiFilters : undefined,
    defaultSorting: aiSort ? [{ columnId: aiSort.columnId, direction: aiSort.direction }] : undefined,
    defaultColumnOrder: aiColumnOrder.length > 0 ? aiColumnOrder : undefined,
    defaultVisibleColumns: aiColumns.length > 0 ? aiColumns : undefined,
    filterLogic: 'and' as const
  } : undefined

</script>

<svelte:head>
  <title>Legislation | EHS Enforcement</title>
  <meta name="description" content="UK environmental, health, and safety legislation reference" />
</svelte:head>

<div class="container mx-auto px-4 py-8">
  <!-- Header -->
  <div class="mb-6">
    <h1 class="text-3xl font-bold text-gray-900 mb-2">Legislation</h1>
    <p class="text-gray-600">UK Acts, Regulations, and Orders referenced in enforcement actions - filter, sort, and group dynamically</p>
  </div>

  <!-- Natural Language Query (browser only to avoid SSR issues) -->
  {#if browser}
    <NaturalLanguageQuery onQuerySuccess={handleQuerySuccess} placeholder="Ask about legislation in plain English..." />
  {/if}

  <!-- Sync Status Banner -->
  {#if $legislationSyncProgress.phase === 'syncing'}
    <div class="mb-6 p-4 rounded-lg bg-blue-50 border border-blue-200">
      <div class="flex items-center gap-3">
        <div class="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-600"></div>
        <div>
          <div class="font-semibold text-blue-900">Loading...</div>
          <div class="text-sm text-blue-700">Syncing legislation data</div>
        </div>
      </div>
    </div>
  {/if}

  {#if $legislationSyncProgress.error}
    <div class="mb-6 p-4 rounded-lg bg-red-50 border border-red-200">
      <div class="font-semibold text-red-900">Sync Error</div>
      <div class="text-sm text-red-700">{$legislationSyncProgress.error}</div>
    </div>
  {/if}


  <!-- Loading State -->
  {#if loading}
    <div class="flex items-center justify-center py-12">
      <div class="text-center">
        <div
          class="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mb-4"
        ></div>
        <p class="text-gray-600">Initializing...</p>
      </div>
    </div>

  <!-- Empty State (no data loaded) -->
  {:else if !loading && data.length === 0}
    <div class="bg-gray-50 border border-gray-200 rounded-lg p-12 text-center">
      <div class="text-6xl mb-4">📚</div>
      <h3 class="text-gray-900 font-semibold text-lg mb-2">No Legislation Available</h3>
      <p class="text-gray-600 mb-4">
        {#if !electricHealthy}
          Electric service is unavailable. Please check your connection.
        {:else}
          No legislation found. The legislation database is currently empty.
        {/if}
      </p>
      <div class="bg-white border border-blue-200 rounded-lg p-6 max-w-xl mx-auto text-left">
        <h4 class="font-semibold text-gray-900 mb-2">Examples of Legislation:</h4>
        <ul class="text-sm text-gray-700 space-y-1">
          <li>• Health and Safety at Work etc. Act 1974</li>
          <li>• The Construction (Design and Management) Regulations 2015</li>
          <li>• The Work at Height Regulations 2005</li>
          <li>• The Management of Health and Safety at Work Regulations 1999</li>
        </ul>
      </div>
    </div>

  <!-- Legislation Table -->
  {:else if data.length > 0}
    <!-- Stats Card -->
    <div class="bg-white border border-gray-200 rounded-lg px-6 py-4 mb-4">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm text-gray-600">Total Legislation</div>
          <div class="text-2xl font-bold text-gray-900">{data.length.toLocaleString()}</div>
        </div>
        <div class="flex gap-8">
          <div>
            <div class="text-sm text-gray-600">Acts</div>
            <div class="text-lg font-semibold text-blue-600">
              {data.filter(l => l.legislation_type === 'act').length}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-600">Regulations</div>
            <div class="text-lg font-semibold text-green-600">
              {data.filter(l => l.legislation_type === 'regulation').length}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-600">Orders</div>
            <div class="text-lg font-semibold text-yellow-600">
              {data.filter(l => l.legislation_type === 'order').length}
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- TableKit Component -->
    <TableKit
      {data}
      {columns}
      config={tableKitConfig}
      storageKey="legislation_table_v1"
      persistState={!hasAiConfig}
      align="left"
      features={{
        columnVisibility: true,
        columnResizing: true,
        columnReordering: true,
        filtering: true,
        sorting: true,
        sortingMode: 'control',
        pagination: true,
        grouping: true
      }}
    >
      <!-- Custom toolbar controls (left side) -->
      <svelte:fragment slot="toolbar-left">
        <ViewSelector on:viewSelected={handleViewSelected} />

        <!-- Save/Update Button (Split when view is active and modified) -->
        {#if $activeViewId && $activeViewModified}
          <!-- Split Button: Update | Save New -->
          <div class="inline-flex rounded-md shadow-sm">
            <!-- Update Existing Button -->
            <button
              type="button"
              on:click={handleUpdateView}
              class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-l-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
              Update View
            </button>
            <!-- Save as New Button -->
            <button
              type="button"
              on:click={handleSaveView}
              class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-indigo-600 border-l border-indigo-500 rounded-r-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 4v16m8-8H4"
                />
              </svg>
              Save New
            </button>
          </div>
        {:else}
          <!-- Regular Save Button -->
          <button
            type="button"
            on:click={handleSaveView}
            class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"
              />
            </svg>
            Save View
          </button>
        {/if}
      </svelte:fragment>

      <!-- Custom cell rendering for actions column -->
      <svelte:fragment slot="cell" let:cell let:column>
        {#if column === 'actions'}
          <a href="/legislation/{cell.row.original.id}" class="text-blue-600 hover:text-blue-800 font-medium">
            View
          </a>
        {:else}
          {cell.getValue()}
        {/if}
      </svelte:fragment>
    </TableKit>
  {/if}
</div>

<!-- Save View Modal -->
{#if browser && showSaveModal && capturedConfig}
  <SaveViewModal
    bind:open={showSaveModal}
    config={capturedConfig}
    on:save={handleViewSaved}
  />
{/if}
