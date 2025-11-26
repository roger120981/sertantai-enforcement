<script lang="ts">
  import { onMount } from 'svelte'
  import { browser } from '$app/environment'
  import {
    initOffencesSync,
    offencesSyncProgress,
    cachedOffences,
  } from '$lib/electric/sync-offences'
  import { checkElectricHealth } from '$lib/electric/sync'
  import { TableKit } from '@shotleybuilder/svelte-table-kit'
  import type { ColumnDef } from '@tanstack/svelte-table'
  import type { Offence } from '$lib/db/schema'
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

  // Initialize sync on mount (WITH baseline - all offences)
  onMount(async () => {
    try {
      electricHealthy = await checkElectricHealth()
      console.log('[Offences Page] Electric health:', electricHealthy)

      if (!electricHealthy) {
        console.warn('[Offences Page] Electric service unavailable, working offline')
        loading = false
        return
      }

      // Initialize with baseline (all offences)
      await initOffencesSync()
      console.log('[Offences Page] Baseline sync complete - all offences loaded')
      baselineLoaded = true
      loading = false
    } catch (err) {
      console.error('[Offences Page] Initialization error:', err)
      loading = false
    }
  })

  // Column definitions
  const columns: ColumnDef<Offence>[] = [
    {
      id: 'offence_description',
      accessorKey: 'offence_description',
      header: 'Description',
      cell: (info) => {
        const description = info.getValue() as string
        if (!description) return '—'
        // Truncate long descriptions
        return description.length > 100 ? description.substring(0, 100) + '...' : description
      },
      enableSorting: true,
      enableGrouping: false,
    },
    {
      id: 'legislation_part',
      accessorKey: 'legislation_part',
      header: 'Legislation Part',
      cell: (info) => info.getValue() || '—',
      enableSorting: true,
      enableGrouping: true,
    },
    {
      id: 'parent_type',
      accessorKey: 'parent_type',
      header: 'Parent Type',
      cell: (info) => {
        const type = info.getValue() as string
        if (!type || type === 'Unknown') return '—'
        return type
      },
      enableSorting: true,
      enableGrouping: true,
    },
    {
      id: 'parent_reference',
      accessorKey: 'parent_reference',
      header: 'Reference',
      cell: (info) => info.getValue() || '—',
      enableSorting: true,
    },
    {
      id: 'fine',
      accessorKey: 'fine',
      header: 'Fine',
      cell: (info) => {
        const fine = info.getValue() as number
        return fine > 0 ? `£${fine.toLocaleString()}` : '£0'
      },
      enableSorting: true,
    },
    {
      id: 'severity_category',
      accessorKey: 'severity_category',
      header: 'Severity',
      cell: (info) => {
        const severity = info.getValue() as string
        if (!severity || severity === 'None') return '—'

        // Color-code severity
        const colors = {
          Low: 'text-green-700 bg-green-100',
          Medium: 'text-orange-700 bg-orange-100',
          High: 'text-red-700 bg-red-100'
        }
        const colorClass = colors[severity as keyof typeof colors] || 'text-gray-700 bg-gray-100'

        return `<span class="px-2 py-1 rounded-full text-xs font-medium ${colorClass}">${severity}</span>`
      },
      enableSorting: true,
      enableGrouping: true,
    },
    {
      id: 'sequence_number',
      accessorKey: 'sequence_number',
      header: 'Seq #',
      cell: (info) => {
        const seq = info.getValue() as number
        return seq ? seq : '—'
      },
      enableSorting: true,
    },
    {
      id: 'created_at',
      accessorKey: 'created_at',
      header: 'Created',
      cell: (info) => {
        const date = info.getValue() as string
        return date ? new Date(date).toLocaleDateString() : '—'
      },
      enableSorting: true,
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: (info) => {
        const offenceId = info.row.original.id
        return `<a href="/offences/${offenceId}" class="text-blue-600 hover:text-blue-800 font-medium">View</a>`
      },
      enableSorting: false,
    },
  ]

  // Reactive table data from Svelte store
  $: data = $cachedOffences || []

  // Debug logging for tableKitConfig
  $: if (browser) {
    console.log('[Offences Page] TableKit Config:', {
      configVersion,
      hasAiConfig,
      config: tableKitConfig
    })
  }

  // Handle NL query success - update AI configuration
  function handleQuerySuccess(filters: any[], sort: any | null, columns?: string[], columnOrder?: string[]) {
    console.log('[Offences Page] NL Query Success:', { filters, sort, columns, columnOrder })

    aiFilters = filters || []
    aiSort = sort
    aiColumns = columns || []
    aiColumnOrder = columnOrder || []

    // Clear active view when new query is made
    viewActions.clearActive()

    // Increment version to trigger config update
    configVersion++
    console.log('[Offences Page] Updated config version:', configVersion)
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
    console.log('[Offences Page] Applying view config:', config)

    // Get available column IDs
    const availableColumnIds = new Set(columns.map(c => String(c.id)))

    // Validate columns - filter out missing columns
    const validColumns = config.columns.filter(colId => availableColumnIds.has(colId))
    const validColumnOrder = config.columnOrder.filter(colId => availableColumnIds.has(colId))

    // Check for missing columns
    const missingColumns = config.columns.filter(colId => !availableColumnIds.has(colId))
    if (missingColumns.length > 0) {
      console.warn('[Offences Page] View contains missing columns:', missingColumns)
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
    console.log('[Offences Page] View selected:', view.name)

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
      console.log('[Offences Page] Opening save modal with config:', capturedConfig)
      showSaveModal = true
    } catch (err) {
      console.error('[Offences Page] Failed to capture table config:', err)
      alert('Failed to capture table configuration. Please try again.')
    }
  }

  async function handleUpdateView() {
    const activeId = $activeViewId
    if (!activeId) return

    try {
      const config = captureCurrentConfig()
      await viewActions.update(activeId, { config })
      console.log('[Offences Page] View updated successfully')
    } catch (err) {
      console.error('[Offences Page] Failed to update view:', err)
      alert('Failed to update view. Please try again.')
    }
  }

  function handleViewSaved(event: CustomEvent<{ id: string; name: string }>) {
    console.log('[Offences Page] View saved:', event.detail.name)
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
  <title>Offences | EHS Enforcement</title>
  <meta name="description" content="Browse offences and legislative breaches" />
</svelte:head>

<div class="container mx-auto px-4 py-8">
  <!-- Header -->
  <div class="mb-6">
    <h1 class="text-3xl font-bold text-gray-900 mb-2">Offences</h1>
    <p class="text-gray-600">Legislative breaches and violations - filter, sort, and group dynamically</p>
  </div>

  <!-- Natural Language Query (browser only to avoid SSR issues) -->
  {#if browser}
    <NaturalLanguageQuery onQuerySuccess={handleQuerySuccess} placeholder="Ask about offences in plain English..." />
  {/if}

  <!-- Sync Error Banner -->
  {#if $offencesSyncProgress.error}
    <div class="mb-6 p-4 rounded-lg bg-red-50 border border-red-200">
      <div class="font-semibold text-red-900">Sync Error</div>
      <div class="text-sm text-red-700">{$offencesSyncProgress.error}</div>
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
      <div class="text-6xl mb-4">📋</div>
      <h3 class="text-gray-900 font-semibold text-lg mb-2">No Offences Available</h3>
      <p class="text-gray-600 mb-4">
        {#if !electricHealthy}
          Electric service is unavailable. Please check your connection.
        {:else}
          No offences found. Offences data will appear here when cases are processed.
        {/if}
      </p>
    </div>

  <!-- Offences Table -->
  {:else if data.length > 0}
    <!-- Stats Card -->
    <div class="bg-white border border-gray-200 rounded-lg px-6 py-4 mb-4">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm text-gray-600">Total Offences</div>
          <div class="text-2xl font-bold text-gray-900">{data.length.toLocaleString()}</div>
        </div>
        <div class="flex gap-6 text-sm">
          <div>
            <div class="text-gray-600">With Fines</div>
            <div class="font-semibold text-gray-900">
              {data.filter(o => o.fine && o.fine > 0).length.toLocaleString()}
            </div>
          </div>
          <div>
            <div class="text-gray-600">Multi-Violation</div>
            <div class="font-semibold text-gray-900">
              {data.filter(o => o.sequence_number && o.sequence_number > 1).length.toLocaleString()}
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
      storageKey="offences_table_v1"
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

      <!-- Custom cell rendering for severity and actions columns -->
      <svelte:fragment slot="cell" let:cell let:column>
        {#if column === 'severity_category'}
          {@html cell.getValue()}
        {:else if column === 'actions'}
          <a href="/offences/{cell.row.original.id}" class="text-blue-600 hover:text-blue-800 font-medium">
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
