<script lang="ts">
  import { onMount } from 'svelte'
  import { browser } from '$app/environment'
  import { useScrapeSessions } from '$lib/query/scrapeSessions'
  import type { SessionFilters } from '$lib/query/scrapeSessions'
  import { syncScrapeSessions, checkElectricHealth } from '$lib/electric/sync'

  // Filter state
  let filterStatus: 'all' | 'active' | 'completed' | 'failed' = 'all'
  let filterAgency: 'all' | 'hse' | 'environment_agency' = 'all'

  // Reactive filters
  $: filters = {
    status: filterStatus,
    agency: filterAgency === 'all' ? undefined : filterAgency,
    limit: 100,
  } satisfies SessionFilters

  // Module-level const query (NOT reactive $:)
  // TanStack Query handles reactivity via queryKey changes
  const sessions = browser ? useScrapeSessions(filters) : null

  // Loading/error state for sync initialization
  let loading = true
  let error: string | null = null
  let electricHealthy = false

  // Initialize SPECIFIC sync on mount
  onMount(async () => {
    try {
      electricHealthy = await checkElectricHealth()

      if (electricHealthy) {
        await syncScrapeSessions()  // ✅ Sync ONLY sessions table
      }

      loading = false
    } catch (err) {
      error = err instanceof Error ? err.message : 'Unknown error'
      loading = false
    }
  })

  // Computed values
  $: sessionsList = $sessions?.data || []

  // Clear filters
  function handleClearFilters() {
    filterStatus = 'all'
    filterAgency = 'all'
  }

  // Helper functions
  function detectAgency(session: any): 'hse' | 'environment_agency' {
    // Check agency field first
    if (session.agency === 'environment_agency' || session.agency === 'ea') {
      return 'environment_agency'
    }
    // Check database field for legacy sessions
    if (['ea_enforcement', 'Ea_notices', 'ea_notices'].includes(session.database)) {
      return 'environment_agency'
    }
    return 'hse'
  }

  function agencyBadgeClass(agency: string): string {
    return agency === 'environment_agency' || agency === 'ea'
      ? 'bg-green-100 text-green-800'
      : 'bg-blue-100 text-blue-800'
  }

  function formatAgency(agency: string): string {
    return agency === 'environment_agency' || agency === 'ea' ? 'EA' : 'HSE'
  }

  function formatDateRange(dateFrom: string | null, dateTo: string | null): string {
    if (!dateFrom && !dateTo) return 'N/A'
    if (dateFrom && !dateTo) return `From ${formatDate(dateFrom)}`
    if (!dateFrom && dateTo) return `Until ${formatDate(dateTo)}`
    return `${formatDate(dateFrom!)} - ${formatDate(dateTo!)}`
  }

  function formatDate(dateString: string): string {
    try {
      const date = new Date(dateString)
      return date.toLocaleDateString('en-GB', { month: 'short', year: 'numeric' })
    } catch {
      return 'N/A'
    }
  }

  function formatActionTypes(actionTypes: string[] | null): string[] {
    if (!actionTypes || !Array.isArray(actionTypes)) return []
    return actionTypes.map((type) => {
      const typeMap: Record<string, string> = {
        court_case: 'Court Case',
        caution: 'Caution',
        enforcement_notice: 'Enforcement Notice',
      }
      return typeMap[type] || type.charAt(0).toUpperCase() + type.slice(1)
    })
  }

  function actionTypeBadgeClass(actionType: string): string {
    if (actionType.includes('Court')) return 'bg-red-100 text-red-800'
    if (actionType.includes('Caution')) return 'bg-yellow-100 text-yellow-800'
    if (actionType.includes('Notice')) return 'bg-blue-100 text-blue-800'
    return 'bg-gray-100 text-gray-800'
  }

  function formatDateTime(isoString: string): string {
    const date = new Date(isoString)
    return date.toLocaleString('en-GB', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    })
  }
</script>

<div class="max-w-7xl mx-auto p-6">
  <!-- Page Header -->
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-3xl font-bold text-gray-900">Session Design Parameters</h1>
        <p class="mt-2 text-gray-600">View what was configured for each scraping session</p>
      </div>

      <!-- Navigation Buttons -->
      <div class="flex gap-3">
        <a
          href="/admin/scrape"
          class="inline-flex items-center px-4 py-2 border border-blue-300 shadow-sm text-sm font-medium rounded-md text-blue-700 bg-blue-50 hover:bg-blue-100 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          Back to Scraping
        </a>

        <a
          href="/admin/scrape-sessions"
          class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
        >
          <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 10V3L4 14h7v7l9-11h-7z"
            />
          </svg>
          View Execution
        </a>

        <a
          href="/admin"
          class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
        >
          <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          Admin Dashboard
        </a>
      </div>
    </div>
  </div>

  <!-- Filters -->
  <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
    <div class="flex flex-wrap items-center gap-4">
      <!-- Agency Filter -->
      <div>
        <label for="agency-filter" class="block text-sm font-medium text-gray-700 mb-1">
          Agency
        </label>
        <select
          id="agency-filter"
          bind:value={filterAgency}
          class="block w-40 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
        >
          <option value="all">All Agencies</option>
          <option value="hse">HSE</option>
          <option value="environment_agency">EA</option>
        </select>
      </div>

      <!-- Status Filter -->
      <div>
        <label for="status-filter" class="block text-sm font-medium text-gray-700 mb-1">
          Status
        </label>
        <select
          id="status-filter"
          bind:value={filterStatus}
          class="block w-40 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
        >
          <option value="all">All Statuses</option>
          <option value="active">Active</option>
          <option value="completed">Completed</option>
          <option value="failed">Failed/Stopped</option>
        </select>
      </div>

      <!-- Clear Filters Button -->
      <div class="pt-6">
        <button
          type="button"
          on:click={handleClearFilters}
          class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
        >
          <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
          Clear Filters
        </button>
      </div>
    </div>
  </div>

  <!-- Sessions Table -->
  <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold text-gray-900">Session Configurations</h2>
        <div class="text-sm text-gray-500">
          {#if loading}
            <div class="flex items-center">
              <svg
                class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-500"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                />
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
              Initializing sync...
            </div>
          {:else if error}
            <div class="text-red-600">Error: {error}</div>
          {:else if $sessions?.isLoading}
            <div class="flex items-center">
              <svg
                class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-500"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                />
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
              Loading data...
            </div>
          {:else}
            {sessionsList.length} session{sessionsList.length !== 1 ? 's' : ''}
          {/if}
        </div>
      </div>
    </div>

    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Session ID
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Agency
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Parameters
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Started
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          {#if sessionsList.length > 0}
            {#each sessionsList as session (session.id)}
              {@const actualAgency = detectAgency(session)}
              <tr class="hover:bg-gray-50">
                <!-- Session ID -->
                <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900">
                  {session.session_id.slice(0, 8)}
                </td>

                <!-- Agency -->
                <td class="px-6 py-4 whitespace-nowrap">
                  <span
                    class="inline-flex items-center px-2.5 py-0.5 rounded text-xs font-medium {agencyBadgeClass(
                      actualAgency
                    )}"
                  >
                    {formatAgency(actualAgency)}
                  </span>
                </td>

                <!-- Parameters (Agency-specific) -->
                <td class="px-6 py-4">
                  {#if actualAgency === 'hse'}
                    <!-- HSE Parameters -->
                    <div class="text-sm space-y-1">
                      <div class="text-gray-900 font-medium">
                        {session.database.charAt(0).toUpperCase() + session.database.slice(1)}
                      </div>
                      <div class="text-gray-600">
                        Pages {session.start_page}-{session.start_page + session.max_pages - 1}
                        <span class="text-xs text-gray-500">(max {session.max_pages})</span>
                      </div>
                    </div>
                  {:else}
                    <!-- EA Parameters -->
                    <div class="text-sm space-y-1">
                      {#if session.date_from || session.date_to}
                        <div class="text-gray-900 font-medium">
                          {formatDateRange(session.date_from, session.date_to)}
                        </div>
                      {:else}
                        <div class="text-gray-500 text-xs italic">
                          Legacy EA session - dates not recorded
                        </div>
                      {/if}
                      {#if session.action_types && session.action_types.length > 0}
                        <div class="flex flex-wrap gap-1 mt-1">
                          {#each formatActionTypes(session.action_types) as actionType}
                            <span
                              class="inline-flex items-center px-2 py-0.5 rounded text-xs {actionTypeBadgeClass(
                                actionType
                              )}"
                            >
                              {actionType}
                            </span>
                          {/each}
                        </div>
                      {/if}
                    </div>
                  {/if}
                </td>

                <!-- Started -->
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {formatDateTime(session.inserted_at)}
                </td>
              </tr>
            {/each}
          {:else}
            <tr>
              <td colspan="4" class="px-6 py-12 text-center">
                <div class="text-gray-500">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-400"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    />
                  </svg>
                  <p class="mt-4 text-sm">No scraping sessions found</p>
                  <p class="text-xs text-gray-400 mt-1">
                    {#if filterStatus !== 'all' || filterAgency !== 'all'}
                      Try adjusting your filters to see more results.
                    {:else}
                      Start a scraping session to see results here.
                    {/if}
                  </p>
                </div>
              </td>
            </tr>
          {/if}
        </tbody>
      </table>
    </div>
  </div>
</div>
