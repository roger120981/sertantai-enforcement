<script lang="ts">
  import { onMount } from 'svelte'
  import { browser } from '$app/environment'
  import { useScrapeSessions } from '$lib/query/scrapeSessions'
  import type { SessionFilters } from '$lib/query/scrapeSessions'
  import { useStopScrapingMutation } from '$lib/query/scraping'
  import { syncScrapeSessions, checkElectricHealth } from '$lib/electric/sync'

  // Filter state
  let filterStatus: 'all' | 'active' | 'completed' | 'failed' = 'all'
  let filterDatabase = 'all'

  // Reactive filters object
  $: filters = {
    status: filterStatus,
    database: filterDatabase === 'all' ? undefined : filterDatabase,
    limit: 100,
  } as SessionFilters

  // TanStack Query for sessions data (only in browser, not SSR)
  const sessionsQuery = browser ? useScrapeSessions(filters) : null

  // Stop scraping mutation
  const stopScraping = browser ? useStopScrapingMutation() : null

  // State
  let loading = true
  let error: string | null = null
  let electricHealthy = false

  // Initialize sync on mount
  onMount(async () => {
    try {
      electricHealthy = await checkElectricHealth()
      console.log('[Scrape Sessions] Electric health:', electricHealthy)

      if (!electricHealthy) {
        console.warn('[Scrape Sessions] Electric service unavailable, working offline')
      }

      if (electricHealthy) {
        await syncScrapeSessions()
        console.log('[Scrape Sessions] Sync started')
      }

      loading = false
    } catch (err) {
      console.error('[Scrape Sessions] Initialization error:', err)
      error = err instanceof Error ? err.message : 'Unknown error'
      loading = false
    }
  })

  // Track which session is being stopped (to show loading state on specific button)
  let stoppingSessionId: string | null = null

  // Clear filters
  function handleClearFilters() {
    filterStatus = 'all'
    filterDatabase = 'all'
  }

  // Stop a running session
  function handleStopSession(sessionId: string) {
    if (!stopScraping || !confirm('Are you sure you want to stop this scraping session?')) {
      return
    }

    stoppingSessionId = sessionId

    $stopScraping.mutate(sessionId, {
      onSuccess: () => {
        console.log(`[Sessions] Stopped session ${sessionId}`)
        stoppingSessionId = null
        // Refetch sessions to update UI
        sessionsQuery?.refetch()
      },
      onError: (error) => {
        console.error(`[Sessions] Failed to stop session:`, error)
        stoppingSessionId = null
        alert(`Failed to stop session: ${error instanceof Error ? error.message : 'Unknown error'}`)
      },
    })
  }

  // Helper functions (matching LiveView)
  function formatStatus(status: string): string {
    const statusMap: Record<string, string> = {
      pending: 'Pending',
      running: 'Running',
      completed: 'Completed',
      failed: 'Failed',
      stopped: 'Stopped',
    }
    return statusMap[status] || 'Unknown'
  }

  function statusBadgeClass(status: string): string {
    const classMap: Record<string, string> = {
      pending: 'bg-yellow-100 text-yellow-800',
      running: 'bg-blue-100 text-blue-800',
      completed: 'bg-green-100 text-green-800',
      failed: 'bg-red-100 text-red-800',
      stopped: 'bg-gray-100 text-gray-800',
    }
    return classMap[status] || 'bg-gray-100 text-gray-800'
  }

  function databaseTypeBadgeClass(database: string): string {
    const classMap: Record<string, string> = {
      convictions: 'bg-red-100 text-red-800',
      notices: 'bg-yellow-100 text-yellow-800',
    }
    return classMap[database] || 'bg-gray-100 text-gray-800'
  }

  function formatDatabaseType(database: string): string {
    const typeMap: Record<string, string> = {
      convictions: 'Cases',
      notices: 'Notices',
    }
    return typeMap[database] || database.charAt(0).toUpperCase() + database.slice(1)
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

  function sessionDuration(session: any): string {
    const status = session.status
    let durationSeconds: number

    if (status === 'completed' || status === 'failed' || status === 'stopped') {
      const insertedAt = new Date(session.inserted_at).getTime()
      const updatedAt = new Date(session.updated_at).getTime()
      durationSeconds = Math.floor((updatedAt - insertedAt) / 1000)
    } else {
      const insertedAt = new Date(session.inserted_at).getTime()
      const now = Date.now()
      durationSeconds = Math.floor((now - insertedAt) / 1000)
      return formatDuration(durationSeconds) + ' (ongoing)'
    }

    return formatDuration(durationSeconds)
  }

  function formatDuration(seconds: number): string {
    if (seconds < 60) {
      return `${seconds}s`
    } else if (seconds < 3600) {
      const minutes = Math.floor(seconds / 60)
      const remainingSeconds = seconds % 60
      return `${minutes}m ${remainingSeconds}s`
    } else {
      const hours = Math.floor(seconds / 3600)
      const remainingSeconds = seconds % 3600
      const minutes = Math.floor(remainingSeconds / 60)
      const secs = remainingSeconds % 60
      return `${hours}h ${minutes}m ${secs}s`
    }
  }

  function progressPercentage(session: any): number {
    const { max_pages, pages_processed } = session
    if (max_pages > 0 && pages_processed !== null) {
      return Math.min(100, (pages_processed / max_pages) * 100)
    }
    return 0
  }
</script>

<div class="max-w-7xl mx-auto p-6">
  <!-- Page Header -->
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-3xl font-bold text-gray-900">Scraping Sessions</h1>
        <p class="mt-2 text-gray-600">
          Monitor and review HSE scraping session history and progress
        </p>
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
          href="/admin/scrape-sessions-design"
          class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
            />
          </svg>
          View Design
        </a>

        <a
          href="/admin"
          class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
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
          <option value="failed">Failed</option>
        </select>
      </div>

      <!-- Database Filter -->
      <div>
        <label for="database-filter" class="block text-sm font-medium text-gray-700 mb-1">
          Type
        </label>
        <select
          id="database-filter"
          bind:value={filterDatabase}
          class="block w-40 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
        >
          <option value="all">All Types</option>
          <option value="convictions">Cases</option>
          <option value="notices">Notices</option>
        </select>
      </div>

      <!-- Clear Filters Button -->
      <div class="pt-6">
        <button
          type="button"
          on:click={handleClearFilters}
          class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
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
        <h2 class="text-lg font-semibold text-gray-900">Session History</h2>
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
          {:else if !sessionsQuery || $sessionsQuery.isLoading}
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
              Loading sessions...
            </div>
          {:else}
            {($sessionsQuery.data || []).length} session{($sessionsQuery.data || []).length !== 1 ? 's' : ''}
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
              Type
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Status
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Started
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Duration
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Pages
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Progress
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Created
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Errors
            </th>
            <th
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              Actions
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          {#if $sessionsQuery?.data && $sessionsQuery.data.length > 0}
            {#each $sessionsQuery.data as session (session.id)}
              <tr class="hover:bg-gray-50">
                <!-- Session ID -->
                <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900">
                  {session.session_id.slice(0, 8)}
                </td>

                <!-- Type -->
                <td class="px-6 py-4 whitespace-nowrap">
                  <span
                    class="inline-flex items-center px-2 py-1 rounded text-xs font-medium {databaseTypeBadgeClass(
                      session.database
                    )}"
                  >
                    {formatDatabaseType(session.database)}
                  </span>
                </td>

                <!-- Status -->
                <td class="px-6 py-4 whitespace-nowrap">
                  <span
                    class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {statusBadgeClass(
                      session.status
                    )}"
                  >
                    {formatStatus(session.status)}
                  </span>
                </td>

                <!-- Started -->
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {formatDateTime(session.inserted_at)}
                </td>

                <!-- Duration -->
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {sessionDuration(session)}
                </td>

                <!-- Pages Info -->
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {session.pages_processed}/{session.max_pages}
                  {#if session.start_page && session.start_page > 1}
                    <span class="text-xs text-gray-500">(from {session.start_page})</span>
                  {/if}
                </td>

                <!-- Progress Bar -->
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="w-16 bg-gray-200 rounded-full h-2 mr-2">
                      <div
                        class="h-2 rounded-full transition-all duration-300 {session.status ===
                        'completed'
                          ? 'bg-green-500'
                          : session.status === 'running'
                            ? 'bg-blue-500'
                            : 'bg-gray-400'}"
                        style="width: {progressPercentage(session)}%"
                      />
                    </div>
                    <span class="text-xs text-gray-600 w-8">
                      {Math.trunc(progressPercentage(session))}%
                    </span>
                  </div>
                </td>

                <!-- Created Count -->
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                  <span class="font-medium text-green-600">{session.cases_created || 0}</span>
                  {#if (session.cases_updated || 0) > 0}
                    <span class="text-xs text-blue-600">+{session.cases_updated} updated</span>
                  {/if}
                </td>

                <!-- Errors -->
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                  {#if (session.errors_count || 0) > 0}
                    <span class="text-red-600 font-medium">{session.errors_count}</span>
                  {:else}
                    <span class="text-gray-400">0</span>
                  {/if}
                </td>

                <!-- Actions -->
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                  {#if session.status === 'running'}
                    {@const isStopping = stoppingSessionId === session.session_id}
                    <button
                      type="button"
                      on:click={() => handleStopSession(session.session_id)}
                      disabled={isStopping}
                      class="inline-flex items-center px-3 py-1.5 border border-red-300 shadow-sm text-xs font-medium rounded-md text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      {#if isStopping}
                        <svg
                          class="animate-spin -ml-0.5 mr-1.5 h-3 w-3"
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
                        Stopping...
                      {:else}
                        <svg
                          class="h-3 w-3 mr-1"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M6 18L18 6M6 6l12 12"
                          />
                        </svg>
                        Stop
                      {/if}
                    </button>
                  {:else}
                    <span class="text-gray-400 text-xs">-</span>
                  {/if}
                </td>
              </tr>
            {/each}
          {:else}
            <tr>
              <td colspan="10" class="px-6 py-12 text-center">
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
                    {#if filterStatus !== 'all' || filterDatabase !== 'all'}
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
