<script lang="ts">
  import { onDestroy } from 'svelte'
  import { writable } from 'svelte/store'
  import { browser } from '$app/environment'
  import { useStartScrapingMutation, useStopScrapingMutation } from '$lib/query/scraping'
  import { createSSEStore } from '$lib/stores/sse'
  import ScrapingProgress from '$lib/components/ScrapingProgress.svelte'
  import FullResultsTable from '$lib/components/FullResultsTable.svelte'
  import type {
    ScrapingProgress as ProgressType,
    SSEEvent,
    RecordProcessedEvent,
  } from '$lib/types/scraping'

  // Mutations
  const startScraping = browser ? useStartScrapingMutation() : null
  const stopScraping = browser ? useStopScrapingMutation() : null

  // SSE Store
  const sse = browser ? createSSEStore() : null

  // Form state
  let formData = {
    agency: 'hse' as 'hse' | 'ea' | 'sepa' | 'nrw' | 'caa' | 'opss' | 'orr' | 'fra' | 'mca',
    database: 'notices' as 'notices' | 'convictions' | 'appeals' | 'penalties' | 'cases' | 'all' | 'prosecutions' | 'undertakings',
    startPage: 1 as number | string,
    maxPages: 5 as number | string,
    country: 'All',
    section: 'all' as 'all' | 'penalties' | 'undertakings' | 'costs_recovery',
    limit: 20,
    // CAA-specific
    caaDataType: 'all' as 'all' | 'prosecutions' | 'undertakings',
    caaYears: [] as number[],
    useAiParsing: true,
    // OPSS-specific
    opssDataType: 'all' as 'all' | 'notices' | 'prosecutions',
    opssPeriods: [] as string[],
    // ORR-specific
    orrDataType: 'all' as 'all' | 'prosecutions' | 'notices',
    orrYears: [] as number[],
    orrNoticeType: '' as '' | 'improvement' | 'prohibition',
    // FRA-specific
    fraNoticeType: '',
    fraFrs: [] as string[],
    fraMaxPages: 10,
    // MCA-specific
    mcaYears: [] as number[],
    includePdfYears: true,
  }

  // Reset form values when agency changes (but only when not scraping)
  let previousAgency = formData.agency
  $: if (formData.agency !== previousAgency && !isScraping) {
    previousAgency = formData.agency
    if (formData.agency === 'hse') {
      formData.database = 'notices'
      formData.startPage = 1
      formData.maxPages = 5
    } else if (formData.agency === 'ea') {
      formData.database = 'notices'
      // Set default dates for EA (last 30 days)
      const today = new Date()
      const thirtyDaysAgo = new Date(today)
      thirtyDaysAgo.setDate(today.getDate() - 30)
      formData.startPage = thirtyDaysAgo.toISOString().split('T')[0]
      formData.maxPages = today.toISOString().split('T')[0]
    } else if (formData.agency === 'sepa') {
      formData.database = 'penalties'
      formData.section = 'all'
    } else if (formData.agency === 'nrw') {
      formData.database = 'cases'
      formData.limit = 20
    } else if (formData.agency === 'caa') {
      formData.database = 'all'
      formData.caaDataType = 'all'
      formData.useAiParsing = true
    } else if (formData.agency === 'opss') {
      formData.database = 'all'
      formData.opssDataType = 'all'
    } else if (formData.agency === 'orr') {
      formData.database = 'all'
      formData.orrDataType = 'all'
      formData.orrNoticeType = ''
    } else if (formData.agency === 'fra') {
      formData.database = 'notices'
      formData.fraMaxPages = 10
    } else if (formData.agency === 'mca') {
      formData.database = 'prosecutions'
      formData.includePdfYears = true
    }
  }

  // Scraping state
  let currentSessionId: string | null = null
  let isScraping = false

  // Store ALL processed records (not just last 20)
  let allProcessedRecords: RecordProcessedEvent[] = []

  // Progress tracking (transient, frontend-only) - using writable store for guaranteed reactivity
  const progress = writable<ProgressType>({
    phase: 'idle',
    currentPage: 0,
    pagesScraped: 0,
    totalPages: 0,
    recordsFound: 0,
    recordsToProcess: 0,
    recordsExisting: 0,
    recordsProcessed: 0,
    recordsEnriched: 0,
    recordsCreated: 0,
    recordsUpdated: 0,
    errorsCount: 0,
    recentRecords: [],
    recentErrors: [],
  })

  // Handle SSE events - subscribe directly instead of reactive statement
  $: if (browser && $sse?.lastEvent) {
    // Call immediately, don't wait for next tick
    handleSSEEvent($sse.lastEvent)
  }

  function handleSSEEvent(event: SSEEvent) {
    console.log('[Page] SSE Event:', event)

    switch (event.type) {
      case 'progress':
        updateProgress(event.data)
        break

      case 'record_processed':
        // Add to ALL records (no limit)
        allProcessedRecords = [...allProcessedRecords, event.data]
        // Also add to recent records (keep last 20 for live display)
        progress.update((p) => ({
          ...p,
          recentRecords: [...p.recentRecords, event.data].slice(-20),
        }))
        break

      case 'error':
        progress.update((p) => ({
          ...p,
          errorsCount: p.errorsCount + 1,
          recentErrors: [...p.recentErrors, event.data].slice(-20),
        }))
        break

      case 'completed':
        progress.update((p) => ({
          ...p,
          phase: 'completed',
          recordsCreated: event.data.records_created,
          recordsUpdated: event.data.records_updated,
        }))
        isScraping = false
        console.log('[Page] Scraping completed!')
        break

      case 'stopped':
        progress.update((p) => ({
          ...p,
          phase: 'idle',
        }))
        isScraping = false
        console.log('[Page] Scraping stopped')
        break
    }
  }

  function updateProgress(data: any) {
    console.log('[updateProgress] Received data:', data)

    // Use store.update() for guaranteed reactivity
    progress.update((prev) => {
      const newProgress = {
        phase: data.phase ?? prev.phase,
        currentPage: data.current_page ?? prev.currentPage,
        pagesScraped: data.pages_scraped ?? prev.pagesScraped,
        totalPages: data.total_pages ?? prev.totalPages,
        recordsFound: data.records_found ?? prev.recordsFound,
        recordsToProcess: data.records_to_process ?? prev.recordsToProcess,
        recordsExisting: data.records_existing ?? prev.recordsExisting,
        recordsProcessed: data.records_processed ?? prev.recordsProcessed,
        recordsEnriched: data.records_enriched ?? prev.recordsEnriched,
        recordsCreated: data.records_created ?? prev.recordsCreated,
        recordsUpdated: data.records_updated ?? prev.recordsUpdated,
        errorsCount: prev.errorsCount,
        recentRecords: prev.recentRecords,
        recentErrors: prev.recentErrors,
      }

      if (data.records_created !== undefined) {
        console.log('[updateProgress] Set recordsCreated to:', newProgress.recordsCreated, '(was:', prev.recordsCreated, ')')
      }
      if (data.records_updated !== undefined) {
        console.log('[updateProgress] Set recordsUpdated to:', newProgress.recordsUpdated, '(was:', prev.recordsUpdated, ')')
      }

      return newProgress
    })
  }

  // Start scraping
  async function handleStart() {
    if (!startScraping || !sse) return

    try {
      // Reset all records
      allProcessedRecords = []

      // Reset progress using store.set()
      progress.set({
        phase: 'idle',
        currentPage: 0,
        pagesScraped: 0,
        totalPages: typeof formData.maxPages === 'number' ? formData.maxPages - (typeof formData.startPage === 'number' ? formData.startPage : 0) + 1 : 0,
        recordsFound: 0,
        recordsToProcess: 0,
        recordsExisting: 0,
        recordsProcessed: 0,
        recordsEnriched: 0,
        recordsCreated: 0,
        recordsUpdated: 0,
        errorsCount: 0,
        recentRecords: [],
        recentErrors: [],
      })

      // Call API to start scraping with correct parameters based on agency
      let requestParams: import('$lib/types/scraping').StartScrapingRequest
      if (formData.agency === 'hse') {
        requestParams = {
          agency: 'hse',
          database: formData.database as 'notices' | 'convictions' | 'appeals',
          start_page: formData.startPage as number,
          max_pages: formData.maxPages as number,
          country: formData.country,
        }
      } else if (formData.agency === 'ea') {
        requestParams = {
          agency: 'ea',
          database: formData.database as 'notices' | 'convictions' | 'appeals',
          from_date: formData.startPage as string,
          to_date: formData.maxPages as string,
        }
      } else if (formData.agency === 'nrw') {
        // NRW - news article scraping with limit
        requestParams = {
          agency: 'nrw',
          database: 'cases',
          limit: formData.limit,
        }
      } else if (formData.agency === 'caa') {
        // CAA - prosecution and undertaking scraping
        requestParams = {
          agency: 'caa',
          database: formData.caaDataType,
          data_type: formData.caaDataType,
          years: formData.caaYears.length > 0 ? formData.caaYears : undefined,
          use_ai_parsing: formData.useAiParsing,
        }
      } else if (formData.agency === 'opss') {
        // OPSS - product safety enforcement
        requestParams = {
          agency: 'opss',
          database: formData.opssDataType,
          data_type: formData.opssDataType,
          periods: formData.opssPeriods.length > 0 ? formData.opssPeriods : undefined,
        }
      } else if (formData.agency === 'orr') {
        // ORR - rail safety enforcement
        requestParams = {
          agency: 'orr',
          database: formData.orrDataType,
          data_type: formData.orrDataType,
          years: formData.orrYears.length > 0 ? formData.orrYears : undefined,
          notice_type: formData.orrNoticeType || undefined,
        }
      } else if (formData.agency === 'fra') {
        // FRA - fire safety notices
        requestParams = {
          agency: 'fra',
          database: 'notices',
          notice_type: formData.fraNoticeType || undefined,
          frs: formData.fraFrs.length > 0 ? formData.fraFrs : undefined,
          max_pages: formData.fraMaxPages,
        }
      } else if (formData.agency === 'mca') {
        // MCA - maritime prosecutions
        requestParams = {
          agency: 'mca',
          database: 'prosecutions',
          years: formData.mcaYears.length > 0 ? formData.mcaYears : undefined,
          include_pdf_years: formData.includePdfYears,
        }
      } else {
        // SEPA - single page scraping with section filter
        requestParams = {
          agency: 'sepa',
          database: 'penalties',
          section: formData.section,
        }
      }

      $startScraping.mutate(requestParams, {
          onSuccess: (data) => {
            console.log('[Page] Scraping started:', data)
            currentSessionId = data.data.session_id
            isScraping = true

            // Connect to SSE stream
            sse.connect(currentSessionId!)
          },
          onError: (error: any) => {
            console.error('[Page] Failed to start scraping:', error)
            alert(`Failed to start scraping: ${error.message}`)
          },
        }
      )
    } catch (err) {
      console.error('[Page] Error starting scraping:', err)
    }
  }

  // Stop scraping
  async function handleStop() {
    if (!currentSessionId || !stopScraping || !sse) return

    $stopScraping.mutate(currentSessionId, {
      onSuccess: () => {
        console.log('[Page] Scraping stopped')
        sse.disconnect()
        isScraping = false
        currentSessionId = null
      },
      onError: (error: any) => {
        console.error('[Page] Failed to stop scraping:', error)
        alert(`Failed to stop scraping: ${error.message}`)
      },
    })
  }

  // Cleanup on destroy
  onDestroy(() => {
    if (sse) {
      sse.disconnect()
    }
  })
</script>

<div class="min-h-screen bg-gray-50">
  <!-- Header -->
  <div class="bg-white border-b border-gray-200">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="py-4">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-gray-900">UK Enforcement Data Scraping</h1>
            <p class="mt-1 text-sm text-gray-600">
              Manually trigger enforcement data scraping from UK regulatory agencies with real-time
              progress monitoring
            </p>
          </div>

          <div class="flex items-center space-x-3">
            <a
              href="/admin"
              class="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
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
            <a
              href="/admin/scrape-sessions"
              class="inline-flex items-center px-3 py-2 border border-blue-300 text-sm font-medium rounded-md text-blue-700 bg-blue-50 hover:bg-blue-100"
            >
              <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                />
              </svg>
              View Sessions
            </a>
            <a
              href="/admin/scrape-sessions-design"
              class="inline-flex items-center px-3 py-2 border border-purple-300 text-sm font-medium rounded-md text-purple-700 bg-purple-50 hover:bg-purple-100"
            >
              <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                />
              </svg>
              Sessions Design
            </a>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Main Content -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6">
    <!-- Configuration Form -->
    <div class="bg-white shadow-sm rounded-lg border border-gray-200">
      <div class="px-5 py-4 border-b border-gray-200">
        <h2 class="text-lg font-semibold text-gray-900">Scraping Configuration</h2>
      </div>

      <form on:submit|preventDefault={handleStart} class="p-5">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <!-- Agency Dropdown -->
          <div>
            <label for="agency" class="block text-sm font-medium text-gray-700 mb-2">Agency</label>
            <select
              id="agency"
              bind:value={formData.agency}
              disabled={isScraping}
              class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
            >
              <option value="hse">HSE (Health & Safety Executive)</option>
              <option value="ea">Environment Agency (EA)</option>
              <option value="sepa">SEPA (Scottish Environment Protection Agency)</option>
              <option value="nrw">NRW (Natural Resources Wales)</option>
              <option value="caa">CAA (Civil Aviation Authority)</option>
              <option value="opss">OPSS (Office for Product Safety & Standards)</option>
              <option value="orr">ORR (Office of Rail and Road)</option>
              <option value="fra">FRA (Fire and Rescue Authorities)</option>
              <option value="mca">MCA (Maritime and Coastguard Agency)</option>
            </select>
          </div>

          <!-- Select Enforcement Type (HSE/EA only) -->
          {#if formData.agency === 'hse' || formData.agency === 'ea'}
            <div>
              <label for="database" class="block text-sm font-medium text-gray-700 mb-2">
                Enforcement Type
              </label>
              <select
                id="database"
                bind:value={formData.database}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
              >
                <option value="notices">Enforcement Notices</option>
                <option value="convictions">Convictions</option>
                <option value="appeals">Appeals</option>
              </select>
            </div>
          {/if}

          <!-- SEPA Section Filter -->
          {#if formData.agency === 'sepa'}
            <div>
              <label for="section" class="block text-sm font-medium text-gray-700 mb-2">
                Section Filter
              </label>
              <select
                id="section"
                bind:value={formData.section}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
              >
                <option value="all">All Sections</option>
                <option value="penalties">Monetary Penalties (FMP/VMP)</option>
                <option value="undertakings">Enforcement Undertakings</option>
                <option value="costs_recovery">Costs Recovery Notices</option>
              </select>
            </div>
            <div class="lg:col-span-2">
              <p class="text-sm text-gray-500 mt-6">
                SEPA publishes all enforcement data on a single page. No pagination or date range needed.
              </p>
            </div>
          {/if}

          <!-- NRW Article Limit -->
          {#if formData.agency === 'nrw'}
            <div>
              <label for="limit" class="block text-sm font-medium text-gray-700 mb-2">
                Max Articles
              </label>
              <input
                id="limit"
                type="number"
                min="1"
                max="100"
                bind:value={formData.limit}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
              />
            </div>
            <div class="lg:col-span-2">
              <p class="text-sm text-gray-500 mt-6">
                NRW publishes enforcement data via news articles. AI parsing extracts case details from each article.
                Articles may contain multiple defendants.
              </p>
            </div>
          {/if}

          <!-- HSE: Start Page / Max Pages -->
          {#if formData.agency === 'hse'}
            <div>
              <label for="startPage" class="block text-sm font-medium text-gray-700 mb-2">
                Start Page
              </label>
              <input
                id="startPage"
                type="number"
                min="1"
                placeholder="1"
                bind:value={formData.startPage}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
              />
            </div>
            <div>
              <label for="maxPages" class="block text-sm font-medium text-gray-700 mb-2">
                Max Pages
              </label>
              <input
                id="maxPages"
                type="number"
                min="1"
                max="100"
                bind:value={formData.maxPages}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
              />
            </div>
          {/if}

          <!-- EA: Date Range -->
          {#if formData.agency === 'ea'}
            <div>
              <label for="startPage" class="block text-sm font-medium text-gray-700 mb-2">
                From Date
              </label>
              <input
                id="startPage"
                type="date"
                min="2000-01-01"
                max="2030-12-31"
                required
                bind:value={formData.startPage}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
              />
            </div>
            <div>
              <label for="maxPages" class="block text-sm font-medium text-gray-700 mb-2">
                To Date
              </label>
              <input
                id="maxPages"
                type="date"
                min="2000-01-01"
                max="2030-12-31"
                required
                bind:value={formData.maxPages}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
              />
            </div>
          {/if}

          <!-- CAA Options -->
          {#if formData.agency === 'caa'}
            <div>
              <label for="caaDataType" class="block text-sm font-medium text-gray-700 mb-2">
                Data Type
              </label>
              <select
                id="caaDataType"
                bind:value={formData.caaDataType}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
              >
                <option value="all">All (Prosecutions & Undertakings)</option>
                <option value="prosecutions">Prosecutions Only</option>
                <option value="undertakings">Undertakings Only</option>
              </select>
            </div>
            <div class="flex items-center space-x-4 lg:col-span-2">
              <label class="flex items-center space-x-2 text-sm text-gray-700">
                <input
                  type="checkbox"
                  bind:checked={formData.useAiParsing}
                  disabled={isScraping}
                  class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                />
                <span>Use AI parsing for PDF extraction</span>
              </label>
              <p class="text-sm text-gray-500">
                CAA publishes prosecution data in annual PDF reports.
              </p>
            </div>
          {/if}

          <!-- OPSS Options -->
          {#if formData.agency === 'opss'}
            <div>
              <label for="opssDataType" class="block text-sm font-medium text-gray-700 mb-2">
                Data Type
              </label>
              <select
                id="opssDataType"
                bind:value={formData.opssDataType}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
              >
                <option value="all">All (Notices & Prosecutions)</option>
                <option value="notices">Notices Only</option>
                <option value="prosecutions">Prosecutions Only</option>
              </select>
            </div>
            <div class="lg:col-span-2">
              <p class="text-sm text-gray-500 mt-6">
                OPSS publishes product safety enforcement data in bi-annual reports.
              </p>
            </div>
          {/if}

          <!-- ORR Options -->
          {#if formData.agency === 'orr'}
            <div>
              <label for="orrDataType" class="block text-sm font-medium text-gray-700 mb-2">
                Data Type
              </label>
              <select
                id="orrDataType"
                bind:value={formData.orrDataType}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
              >
                <option value="all">All (Prosecutions & Notices)</option>
                <option value="prosecutions">Prosecutions Only</option>
                <option value="notices">Notices Only</option>
              </select>
            </div>
            <div>
              <label for="orrNoticeType" class="block text-sm font-medium text-gray-700 mb-2">
                Notice Type
              </label>
              <select
                id="orrNoticeType"
                bind:value={formData.orrNoticeType}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
              >
                <option value="">All Notice Types</option>
                <option value="improvement">Improvement Notices</option>
                <option value="prohibition">Prohibition Notices</option>
              </select>
            </div>
            <div class="lg:col-span-2">
              <p class="text-sm text-gray-500">
                ORR regulates rail safety. Prosecution data is extracted from PDF reports.
              </p>
            </div>
          {/if}

          <!-- FRA Options -->
          {#if formData.agency === 'fra'}
            <div>
              <label for="fraMaxPages" class="block text-sm font-medium text-gray-700 mb-2">
                Max Pages
              </label>
              <input
                id="fraMaxPages"
                type="number"
                min="1"
                max="100"
                bind:value={formData.fraMaxPages}
                disabled={isScraping}
                class="w-full px-3 py-2 text-sm rounded-md border-gray-300 focus:border-blue-500 focus:ring-blue-500 disabled:bg-gray-50"
              />
            </div>
            <div class="lg:col-span-2">
              <p class="text-sm text-gray-500 mt-6">
                FRA data comes from the NFCC National Fire Safety Register. Each page contains ~100 notices.
              </p>
            </div>
          {/if}

          <!-- MCA Options -->
          {#if formData.agency === 'mca'}
            <div class="flex items-center space-x-4">
              <label class="flex items-center space-x-2 text-sm text-gray-700">
                <input
                  type="checkbox"
                  bind:checked={formData.includePdfYears}
                  disabled={isScraping}
                  class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                />
                <span>Include PDF years (requires AI parsing)</span>
              </label>
            </div>
            <div class="lg:col-span-2">
              <p class="text-sm text-gray-500">
                MCA publishes maritime prosecution data. Recent years are HTML, older years are PDFs.
              </p>
            </div>
          {/if}
        </div>

        <!-- Action Row -->
        <div class="mt-4 flex items-center justify-between">
          <label class="flex items-center space-x-2 text-sm text-gray-700">
            <input
              type="checkbox"
              disabled={isScraping}
              class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
            />
            <span>Process ALL records (including existing)</span>
          </label>

          <div class="flex items-center space-x-3">
            <span class="text-sm text-gray-600">
              {#if isScraping}
                Scraping in progress...
              {:else}
                Ready to start scraping
              {/if}
            </span>

            {#if !isScraping}
              <button
                type="submit"
                disabled={$startScraping?.isPending}
                class="inline-flex justify-center items-center px-6 py-2.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-400 disabled:cursor-not-allowed shadow-sm"
              >
                {#if $startScraping?.isPending}
                  <svg class="animate-spin -ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24">
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
                  Starting...
                {:else}
                  <svg class="h-4 w-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  Start Scraping
                {/if}
              </button>
            {:else}
              <button
                type="button"
                on:click={handleStop}
                disabled={$stopScraping?.isPending}
                class="inline-flex justify-center items-center px-6 py-2.5 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 shadow-sm"
              >
                <svg class="h-4 w-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8 7a1 1 0 00-1 1v4a1 1 0 001 1h4a1 1 0 001-1V8a1 1 0 00-1-1H8z"
                    clip-rule="evenodd"
                  />
                </svg>
                Stop Scraping
              </button>
            {/if}
          </div>
        </div>
      </form>
    </div>

    <!-- Progress Tracker -->
    <ScrapingProgress progress={$progress} />

    <!-- Errors Panel (shown when errors exist) -->
    {#if $progress.recentErrors.length > 0}
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-6 py-4 bg-red-50 border-b border-red-200">
          <div class="flex items-center">
            <svg
              class="h-5 w-5 text-red-500 mr-2"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <h3 class="text-lg font-semibold text-red-900">
              Errors ({$progress.recentErrors.length})
            </h3>
          </div>
        </div>
        <div class="p-4 max-h-96 overflow-y-auto">
          <div class="space-y-2">
            {#each $progress.recentErrors as error, index (error.timestamp || index)}
              <div class="flex items-start space-x-3 p-3 bg-red-50 rounded-lg border border-red-100">
                <!-- Error Icon -->
                <div class="flex-shrink-0 mt-1">
                  <svg
                    class="h-5 w-5 text-red-500"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </div>

                <!-- Error Content -->
                <div class="flex-1 min-w-0">
                  <div class="flex items-start justify-between mb-2">
                    <p class="text-sm font-medium text-red-900">
                      {error.message}
                    </p>
                  </div>

                  <!-- Error Details -->
                  <div class="flex flex-wrap gap-3 text-xs text-gray-600">
                    {#if error.regulator_id}
                      <span class="flex items-center">
                        <svg
                          class="h-3 w-3 mr-1 text-gray-400"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"
                          />
                        </svg>
                        ID: {error.regulator_id.slice(0, 12)}...
                      </span>
                    {/if}

                    {#if error.page}
                      <span class="flex items-center">
                        <svg
                          class="h-3 w-3 mr-1 text-gray-400"
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
                        Page: {error.page}
                      </span>
                    {/if}

                    {#if error.timestamp}
                      <span class="flex items-center">
                        <svg
                          class="h-3 w-3 mr-1 text-gray-400"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                          />
                        </svg>
                        {new Date(error.timestamp).toLocaleTimeString()}
                      </span>
                    {/if}
                  </div>
                </div>
              </div>
            {/each}
          </div>
        </div>
      </div>
    {/if}

    <!-- All Processed Records Table (optimistically updated from ElectricSQL) -->
    <FullResultsTable records={allProcessedRecords} />
  </div>
</div>
