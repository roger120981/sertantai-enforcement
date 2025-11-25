<script lang="ts">
  import { onMount } from 'svelte'
  import { browser } from '$app/environment'
  import {
    initOffendersSync,
    searchOffenders,
    offendersSyncProgress,
    cachedOffenders,
    getOffendersCacheState,
    type OffendersSearchParams,
  } from '$lib/electric/sync-offenders'
  import { checkElectricHealth } from '$lib/electric/sync'
  import { TableKit } from '@shotleybuilder/svelte-table-kit'
  import type { ColumnDef } from '@tanstack/svelte-table'
  import type { Offender } from '$lib/db/schema'
  import { ViewSelector, SaveViewModal, activeViewId, activeViewModified, viewActions } from 'svelte-table-views-tanstack'
  import type { TableConfig, SavedView } from 'svelte-table-views-tanstack'
  import NaturalLanguageQuery from '$lib/components/NaturalLanguageQuery.svelte'

  // Svelte stores for offenders data
  const cacheState = browser ? getOffendersCacheState() : null

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

  // Initialize sync on mount (WITH baseline - all offenders)
  onMount(async () => {
    try {
      electricHealthy = await checkElectricHealth()
      console.log('[Offenders Page] Electric health:', electricHealthy)

      if (!electricHealthy) {
        console.warn('[Offenders Page] Electric service unavailable, working offline')
        loading = false
        return
      }

      // Initialize with baseline (all offenders)
      await initOffendersSync()
      console.log('[Offenders Page] Baseline sync complete - all offenders loaded')
      baselineLoaded = true
      loading = false
    } catch (err) {
      console.error('[Offenders Page] Initialization error:', err)
      loading = false
    }
  })

  // Column definitions
  const columns: ColumnDef<Offender>[] = [
    {
      id: 'name',
      accessorKey: 'name',
      header: 'Company Name',
      cell: (info) => info.getValue() || 'N/A',
      enableSorting: true,
      enableGrouping: false,
    },
    {
      id: 'company_registration_number',
      accessorKey: 'company_registration_number',
      header: 'Company Number',
      cell: (info) => info.getValue() || '—',
      enableSorting: true,
    },
    {
      id: 'business_type',
      accessorKey: 'business_type',
      header: 'Type',
      cell: (info) => {
        const type = info.getValue() as string
        if (!type) return '—'
        // Format business type
        return type
          .split('_')
          .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
          .join(' ')
      },
      enableSorting: true,
      enableGrouping: true,
    },
    {
      id: 'local_authority',
      accessorKey: 'local_authority',
      header: 'Location',
      cell: (info) => {
        const row = info.row.original
        const parts = [row.local_authority, row.town, row.postcode].filter(Boolean)
        return parts.length > 0 ? parts.join(', ') : '—'
      },
      enableGrouping: true,
    },
    {
      id: 'industry',
      accessorKey: 'industry',
      header: 'Industry',
      cell: (info) => {
        const ind = info.getValue() as string
        const activity = info.row.original.main_activity
        return ind || activity || '—'
      },
      enableGrouping: true,
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
      id: 'total_fines',
      accessorKey: 'total_fines',
      header: 'Total Fines',
      cell: (info) => {
        const fines = info.getValue() as number
        return fines > 0 ? `£${fines.toLocaleString()}` : '£0'
      },
      enableSorting: true,
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: (info) => {
        const offenderId = info.row.original.id
        return `<a href="/offenders/${offenderId}" class="text-blue-600 hover:text-blue-800 font-medium">View</a>`
      },
      enableSorting: false,
    },
  ]

  // Reactive table data from Svelte store
  $: data = $cachedOffenders || []

  // Debug logging for tableKitConfig
  $: if (browser) {
    console.log('[Offenders Page] TableKit Config:', {
      configVersion,
      hasAiConfig,
      config: tableKitConfig
    })
  }

  // Handle NL query success - update AI configuration
  function handleQuerySuccess(filters: any[], sort: any | null, columns?: string[], columnOrder?: string[]) {
    console.log('[Offenders Page] NL Query Success:', { filters, sort, columns, columnOrder })

    aiFilters = filters || []
    aiSort = sort
    aiColumns = columns || []
    aiColumnOrder = columnOrder || []

    // Clear active view when new query is made
    viewActions.clearActive()

    // Increment version to trigger config update
    configVersion++
    console.log('[Offenders Page] Updated config version:', configVersion)
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
    console.log('[Offenders Page] Applying view config:', config)

    // Get available column IDs
    const availableColumnIds = new Set(columns.map(c => String(c.id)))

    // Validate columns - filter out missing columns
    const validColumns = config.columns.filter(colId => availableColumnIds.has(colId))
    const validColumnOrder = config.columnOrder.filter(colId => availableColumnIds.has(colId))

    // Check for missing columns
    const missingColumns = config.columns.filter(colId => !availableColumnIds.has(colId))
    if (missingColumns.length > 0) {
      console.warn('[Offenders Page] View contains missing columns:', missingColumns)
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
    console.log('[Offenders Page] View selected:', view.name)

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
      console.log('[Offenders Page] Opening save modal with config:', capturedConfig)
      showSaveModal = true
    } catch (err) {
      console.error('[Offenders Page] Failed to capture table config:', err)
      alert('Failed to capture table configuration. Please try again.')
    }
  }

  async function handleUpdateView() {
    const activeId = $activeViewId
    if (!activeId) return

    try {
      const config = captureCurrentConfig()
      await viewActions.update(activeId, { config })
      console.log('[Offenders Page] View updated successfully')
    } catch (err) {
      console.error('[Offenders Page] Failed to update view:', err)
      alert('Failed to update view. Please try again.')
    }
  }

  function handleViewSaved(event: CustomEvent<{ id: string; name: string }>) {
    console.log('[Offenders Page] View saved:', event.detail.name)
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
  <title>Offenders | EHS Enforcement</title>
  <meta name="description" content="Search enforcement offenders and companies" />
</svelte:head>

<div class="container mx-auto px-4 py-8">
  <!-- Header -->
  <div class="mb-6">
    <h1 class="text-3xl font-bold text-gray-900 mb-2">Offenders</h1>
    <p class="text-gray-600">Companies and individuals subject to enforcement action - filter, sort, and group dynamically</p>
  </div>

  <!-- Natural Language Query (browser only to avoid SSR issues) -->
  {#if browser}
    <NaturalLanguageQuery onQuerySuccess={handleQuerySuccess} placeholder="Ask about offenders in plain English..." />
  {/if}

  <!-- Sync Status Banner -->
  {#if $offendersSyncProgress.searchInProgress}
    <div class="mb-6 p-4 rounded-lg bg-blue-50 border border-blue-200">
      <div class="flex items-center gap-3">
        <div class="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-600"></div>
        <div>
          <div class="font-semibold text-blue-900">Searching...</div>
          <div class="text-sm text-blue-700">{$offendersSyncProgress.currentSearch}</div>
        </div>
      </div>
    </div>
  {/if}

  {#if $offendersSyncProgress.error}
    <div class="mb-6 p-4 rounded-lg bg-red-50 border border-red-200">
      <div class="font-semibold text-red-900">Search Error</div>
      <div class="text-sm text-red-700">{$offendersSyncProgress.error}</div>
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
      <div class="text-6xl mb-4">📊</div>
      <h3 class="text-gray-900 font-semibold text-lg mb-2">No Offenders Available</h3>
      <p class="text-gray-600 mb-4">
        {#if !electricHealthy}
          Electric service is unavailable. Please check your connection.
        {:else}
          No offenders found. The baseline sync may have failed or returned no results.
        {/if}
      </p>
    </div>

  <!-- Offenders Table -->
  {:else if data.length > 0}
    <!-- Stats Card -->
    <div class="bg-white border border-gray-200 rounded-lg px-6 py-4 mb-4">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm text-gray-600">Total Offenders</div>
          <div class="text-2xl font-bold text-gray-900">{data.length.toLocaleString()}</div>
        </div>
        <div class="text-sm text-gray-600">
          All offenders loaded
        </div>
      </div>
    </div>

    <!-- TableKit Component -->
    <TableKit
      {data}
      {columns}
      config={tableKitConfig}
      storageKey="offenders_table_v2"
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
          <a href="/offenders/{cell.row.original.id}" class="text-blue-600 hover:text-blue-800 font-medium">
            View
          </a>
        {:else}
          {cell.getValue()}
        {/if}
      </svelte:fragment>
    </TableKit>

    <!-- Cached Searches Display -->
    {#if $cacheState && $cacheState.totalShapes > 0}
      <div class="mt-4 text-sm text-gray-600 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div class="font-semibold text-blue-900 mb-2">
          📦 Cached Searches ({$cacheState.totalShapes}/{$cacheState.maxShapes})
        </div>
        <div class="space-y-1">
          {#each Array.from($cacheState.cacheDescriptions.entries()) as [key, description]}
            <div class="text-blue-700">• {description}</div>
          {/each}
        </div>
        <p class="mt-2 text-xs text-blue-600">
          These searches are available offline. When cache is full, oldest searches are removed.
        </p>
      </div>
    {/if}
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
