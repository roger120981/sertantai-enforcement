<script lang="ts">
	import { browser } from '$app/environment'
	import { onMount } from 'svelte'
	import { TableKit } from '@shotleybuilder/svelte-table-kit'
	import type { ColumnDef, Table } from '@tanstack/svelte-table'
	import { useUnifiedData, type UnifiedRecord } from '$lib/query/unified'
	import NaturalLanguageQuery from '$lib/components/NaturalLanguageQuery.svelte'
	import { queryState } from '$lib/stores/query-state'
	import { ViewSelector, SaveViewModal, activeViewId, activeViewModified, viewActions } from 'svelte-table-views-tanstack'
	import type { TableConfig, SavedView } from 'svelte-table-views-tanstack'

	// AI-generated configuration from NL query
	let aiFilters: any[] = []
	let aiSort: { columnId: string; direction: 'asc' | 'desc' } | null = null
	let aiColumns: string[] = []
	let aiColumnOrder: string[] = []
	let configVersion = 0 // Track config version for reactive updates

	// Saved views state
	let showSaveModal = false
	let capturedConfig: TableConfig | null = null
	let currentOriginalQuery: string | undefined = undefined

	// Check for query state from store on mount (from homepage navigation)
	onMount(() => {
		const currentQueryState = $queryState
		if (currentQueryState && browser) {
			console.log('[Data Page] Found query state from store:', currentQueryState)
			handleQuerySuccess(
				currentQueryState.filters,
				currentQueryState.sort,
				currentQueryState.columns,
				currentQueryState.columnOrder
			)
			// Clear the store after consuming
			queryState.clear()
		}
	})

	// Handle NL query success - update AI configuration
	function handleQuerySuccess(filters: any[], sort: any | null, columns?: string[], columnOrder?: string[]) {
		console.log('[Data Page] NL Query Success:', { filters, sort, columns, columnOrder })
		console.log('[Data Page] Filters detail:', JSON.stringify(filters, null, 2))
		console.log('[Data Page] Sort detail:', JSON.stringify(sort, null, 2))

		aiFilters = filters || []
		aiSort = sort
		aiColumns = columns || []
		aiColumnOrder = columnOrder || []

		// Clear active view when new query is made
		viewActions.clearActive()

		// Increment version to trigger config update (v0.5.0 watches config.id)
		configVersion++
		console.log('[Data Page] Updated config version:', configVersion)
	}

	// Capture current table config (simplified - use TableKit config prop)
	function captureCurrentConfig(): TableConfig {
		// For Phase 4.1, we'll capture the current AI config
		// In future versions, we can capture actual table state via TableKit API
		return {
			filters: aiFilters,
			sort: aiSort,
			columns: aiColumns.length > 0 ? aiColumns : columns.map(c => String(c.id)),
			columnOrder: aiColumnOrder.length > 0 ? aiColumnOrder : columns.map(c => String(c.id)),
			columnWidths: {},
			pageSize: 25,
			grouping: []
		}
	}

	// Apply saved view configuration via TableKit config prop
	function applyViewConfig(config: TableConfig) {
		console.log('[Data Page] Applying view config:', config)

		// Get available column IDs
		const availableColumnIds = new Set(columns.map(c => String(c.id)))

		// Validate columns - filter out missing columns
		const validColumns = config.columns.filter(colId => availableColumnIds.has(colId))
		const validColumnOrder = config.columnOrder.filter(colId => availableColumnIds.has(colId))

		// Check for missing columns
		const missingColumns = config.columns.filter(colId => !availableColumnIds.has(colId))
		if (missingColumns.length > 0) {
			console.warn('[Data Page] View contains missing columns:', missingColumns)
			console.warn('[Data Page] Using only available columns:', validColumns)

			// Show warning to user
			const missingCount = missingColumns.length
			const totalCount = config.columns.length
			alert(
				`⚠️ Column Validation Warning\n\n` +
				`This view contains ${missingCount} column(s) that no longer exist (${totalCount} total).\n\n` +
				`Missing columns:\n${missingColumns.join(', ')}\n\n` +
				`The view will be loaded with ${validColumns.length} available columns.`
			)
		}

		// Set AI config which will reactively update TableKit
		aiFilters = config.filters
		aiSort = config.sort
		aiColumns = validColumns.length > 0 ? validColumns : []
		aiColumnOrder = validColumnOrder.length > 0 ? validColumnOrder : []
		configVersion++
	}

	// Handle view selection
	async function handleViewSelected(event: CustomEvent<{ view: SavedView }>) {
		const view = event.detail.view
		console.log('[Data Page] View selected:', view.name)

		// Clear AI config
		aiFilters = []
		aiSort = null
		aiColumns = []
		aiColumnOrder = []
		configVersion++

		// Apply view config to table
		setTimeout(() => {
			applyViewConfig(view.config)
			currentOriginalQuery = view.originalQuery
		}, 100)
	}

	// Handle save view button click
	function handleSaveView() {
		try {
			capturedConfig = captureCurrentConfig()
			console.log('[Data Page] Opening save modal with config:', capturedConfig)
			showSaveModal = true
		} catch (err) {
			console.error('[Data Page] Failed to capture table config:', err)
			alert('Failed to capture table configuration. Please try again.')
		}
	}

	// Handle update existing view
	async function handleUpdateView() {
		const activeId = $activeViewId
		if (!activeId) return

		try {
			const config = captureCurrentConfig()
			await viewActions.update(activeId, { config })
			console.log('[Data Page] View updated successfully')
		} catch (err) {
			console.error('[Data Page] Failed to update view:', err)
			alert('Failed to update view. Please try again.')
		}
	}

	// Handle view saved
	function handleViewSaved(event: CustomEvent<{ id: string; name: string }>) {
		console.log('[Data Page] View saved:', event.detail.name)
		// Modal will close automatically
	}

	// Removed table state tracking for Phase 4.1
	// Will add in Phase 4.2 when we have proper TableKit API access

	// Build TableKit configuration from AI (reactive - updates when configVersion changes)
	$: hasAiConfig = aiFilters.length > 0 || aiSort !== null || aiColumns.length > 0 || aiColumnOrder.length > 0

	$: tableKitConfig = hasAiConfig ? {
		id: `ai_query_v${configVersion}`, // v0.5.0 watches this for changes
		version: '1.0',
		defaultFilters: aiFilters.length > 0 ? aiFilters : undefined,
		defaultSorting: aiSort ? [{ columnId: aiSort.columnId, direction: aiSort.direction }] : undefined,
		defaultColumnOrder: aiColumnOrder.length > 0 ? aiColumnOrder : undefined,
		defaultVisibleColumns: aiColumns.length > 0 ? aiColumns : undefined,
		filterLogic: 'and' as const
	} : undefined

	// Debug logging for tableKitConfig
	$: if (browser) {
		console.log('[Data Page] TableKit Config:', {
			configVersion,
			hasAiConfig,
			config: tableKitConfig
		})
	}

	// Fetch unified data with default parameters (only in browser to avoid SSR issues)
	$: unifiedData = browser
		? useUnifiedData({
				limit: 100,
				offset: 0,
				order_by: 'offence_action_date',
				order: 'desc'
		  })
		: null

	// Helper to format date
	function formatDate(dateStr: string | null): string {
		if (!dateStr) return '-'
		const date = new Date(dateStr)
		return date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
	}

	// Helper to format currency
	function formatCurrency(amount: number | null): string {
		if (amount === null || amount === undefined) return '-'
		return new Intl.NumberFormat('en-GB', {
			style: 'currency',
			currency: 'GBP',
			minimumFractionDigits: 0,
			maximumFractionDigits: 0
		}).format(amount)
	}

	// Icon helper for column headers
	function getSourceIcon(sourceTable: string): string {
		switch (sourceTable) {
			case 'cases':
				return '⚖️' // Scales of justice
			case 'notices':
				return '📄' // Document
			case 'offenders':
				return '👥' // People
			case 'legislation':
				return '📖' // Book
			default:
				return '📊' // Generic data icon for common fields
		}
	}

	// Helper to create column header with icon
	function createHeaderWithIcon(label: string, sourceTable: string): string {
		const icon = getSourceIcon(sourceTable)
		return `${icon} ${label}`
	}

	// Complete column definitions for unified table
	const columns: ColumnDef<UnifiedRecord>[] = [
		// Record Type - Always visible, grouped first
		{
			id: 'record_type',
			accessorKey: 'record_type',
			header: createHeaderWithIcon('Type', 'common'),
			cell: (info) => info.getValue(),
			size: 100,
			enableGrouping: true,
			meta: { sourceTable: 'common', group: 'Core' }
		},

		// Agency Fields
		{
			id: 'agency_code',
			accessorKey: 'agency_code',
			header: createHeaderWithIcon('Agency', 'common'),
			cell: (info) => (info.getValue() || '-').toUpperCase(),
			size: 100,
			enableGrouping: true,
			meta: { sourceTable: 'common', group: 'Core' }
		},
		{
			id: 'agency_name',
			accessorKey: 'agency_name',
			header: createHeaderWithIcon('Agency Name', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 200,
			meta: { sourceTable: 'common', group: 'Common' }
		},

		// Common Fields
		{
			id: 'regulator_id',
			accessorKey: 'regulator_id',
			header: createHeaderWithIcon('Regulator ID', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 150,
			meta: { sourceTable: 'common', group: 'Common' }
		},
		{
			id: 'offence_action_date',
			accessorKey: 'offence_action_date',
			header: createHeaderWithIcon('Action Date', 'common'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'common', group: 'Core' }
		},
		{
			id: 'offence_action_type',
			accessorKey: 'offence_action_type',
			header: createHeaderWithIcon('Action Type', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 150,
			enableGrouping: true,
			meta: { sourceTable: 'common', group: 'Core' }
		},
		{
			id: 'offence_breaches',
			accessorKey: 'offence_breaches',
			header: createHeaderWithIcon('Breaches', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 300,
			meta: { sourceTable: 'common', group: 'Core' }
		},
		{
			accessorKey: 'regulator_function',
			header: createHeaderWithIcon('Regulator Function', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 150,
			enableGrouping: true,
			meta: { sourceTable: 'common', group: 'Common' }
		},
		{
			accessorKey: 'environmental_impact',
			header: createHeaderWithIcon('Environmental Impact', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 180,
			meta: { sourceTable: 'common', group: 'Common' }
		},
		{
			accessorKey: 'environmental_receptor',
			header: createHeaderWithIcon('Environmental Receptor', 'common'),
			cell: (info) => info.getValue() || '-',
			size: 180,
			meta: { sourceTable: 'common', group: 'Common' }
		},
		{
			id: 'url',
			accessorKey: 'url',
			header: createHeaderWithIcon('Link', 'common'),
			cell: (info) => (info.getValue() ? '🔗' : '-'),
			size: 80,
			enableSorting: false,
			meta: { sourceTable: 'common', group: 'Common' }
		},

		// Case-Specific Fields
		{
			id: 'case_reference',
			accessorKey: 'case_reference',
			header: createHeaderWithIcon('Case Reference', 'cases'),
			cell: (info) => info.getValue() || '-',
			size: 150,
			meta: { sourceTable: 'cases', group: 'Case Fields' }
		},
		{
			id: 'offence_result',
			accessorKey: 'offence_result',
			header: createHeaderWithIcon('Result', 'cases'),
			cell: (info) => info.getValue() || '-',
			size: 120,
			enableGrouping: true,
			meta: { sourceTable: 'cases', group: 'Case Fields' }
		},
		{
			id: 'offence_fine',
			accessorKey: 'offence_fine',
			header: createHeaderWithIcon('Fine', 'cases'),
			cell: (info) => formatCurrency(info.getValue() as number),
			size: 120,
			meta: { sourceTable: 'cases', group: 'Case Fields' }
		},
		{
			id: 'offence_costs',
			accessorKey: 'offence_costs',
			header: createHeaderWithIcon('Costs', 'cases'),
			cell: (info) => formatCurrency(info.getValue() as number),
			size: 120,
			meta: { sourceTable: 'cases', group: 'Case Fields' }
		},
		{
			id: 'offence_hearing_date',
			accessorKey: 'offence_hearing_date',
			header: createHeaderWithIcon('Hearing Date', 'cases'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'cases', group: 'Case Fields' }
		},
		{
			accessorKey: 'related_cases',
			header: createHeaderWithIcon('Related Cases', 'cases'),
			cell: (info) => {
				const val = info.getValue() as string[] | null
				return val && val.length > 0 ? val.join(', ') : '-'
			},
			size: 150,
			enableSorting: false,
			meta: { sourceTable: 'cases', group: 'Case Fields' }
		},

		// Notice-Specific Fields
		{
			accessorKey: 'notice_date',
			header: createHeaderWithIcon('Notice Date', 'notices'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'notices', group: 'Notice Fields' }
		},
		{
			accessorKey: 'notice_body',
			header: createHeaderWithIcon('Notice Body', 'notices'),
			cell: (info) => info.getValue() || '-',
			size: 300,
			meta: { sourceTable: 'notices', group: 'Notice Fields' }
		},
		{
			accessorKey: 'operative_date',
			header: createHeaderWithIcon('Operative Date', 'notices'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'notices', group: 'Notice Fields' }
		},
		{
			accessorKey: 'compliance_date',
			header: createHeaderWithIcon('Compliance Date', 'notices'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'notices', group: 'Notice Fields' }
		},
		{
			accessorKey: 'regulator_ref_number',
			header: createHeaderWithIcon('Regulator Ref', 'notices'),
			cell: (info) => info.getValue() || '-',
			size: 150,
			meta: { sourceTable: 'notices', group: 'Notice Fields' }
		},

		// Timestamps
		{
			accessorKey: 'inserted_at',
			header: createHeaderWithIcon('Created', 'common'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'common', group: 'Timestamps' }
		},
		{
			accessorKey: 'updated_at',
			header: createHeaderWithIcon('Updated', 'common'),
			cell: (info) => formatDate(info.getValue() as string),
			size: 120,
			meta: { sourceTable: 'common', group: 'Timestamps' }
		}
	]
</script>


<div class="container mx-auto px-4 py-8">
	<div class="mb-6">
		<h1 class="text-3xl font-bold text-gray-900 mb-2">Enforcement Data</h1>
		<p class="text-gray-600">
			Unified view of Cases and Notices with flexible filtering, sorting, and grouping
		</p>
	</div>

	<!-- Natural Language Query (browser only to avoid SSR issues) -->
	{#if browser}
		<NaturalLanguageQuery onQuerySuccess={handleQuerySuccess} placeholder="Ask about enforcement data in plain English..." />
	{/if}


	{#if !browser || $unifiedData?.isLoading}
		<div class="px-4 py-12 text-center bg-white rounded-lg border border-gray-200">
			<div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600"></div>
			<p class="mt-4 text-gray-600">Loading enforcement data...</p>
		</div>
	{:else if $unifiedData?.isError}
		<div class="px-4 py-8 bg-red-50 border border-red-200 rounded-lg">
			<h3 class="text-lg font-semibold text-red-800 mb-2">Error Loading Data</h3>
			<p class="text-red-600">{$unifiedData.error?.message || 'Unknown error occurred'}</p>
		</div>
	{:else if $unifiedData?.data}
		<!-- Stats Overview -->
		<div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
			<div class="bg-white rounded-lg border border-gray-200 px-4 py-3">
				<div class="text-sm text-gray-600">Total Records</div>
				<div class="text-2xl font-bold text-gray-900">
					{$unifiedData.data.meta.total_count.toLocaleString()}
				</div>
			</div>
			<div class="bg-white rounded-lg border border-gray-200 px-4 py-3">
				<div class="text-sm text-gray-600">Cases</div>
				<div class="text-2xl font-bold text-green-600">
					{$unifiedData.data.meta.cases_count.toLocaleString()}
				</div>
			</div>
			<div class="bg-white rounded-lg border border-gray-200 px-4 py-3">
				<div class="text-sm text-gray-600">Notices</div>
				<div class="text-2xl font-bold text-blue-600">
					{$unifiedData.data.meta.notices_count.toLocaleString()}
				</div>
			</div>
			<div class="bg-white rounded-lg border border-gray-200 px-4 py-3">
				<div class="text-sm text-gray-600">Showing</div>
				<div class="text-2xl font-bold text-gray-900">
					{$unifiedData.data.data.length.toLocaleString()}
				</div>
			</div>
		</div>

		<!-- Unified Data Table - v0.5.0 config prop is reactive -->
		{#if $unifiedData?.data?.data}
			<TableKit
				data={$unifiedData.data.data}
				{columns}
				config={tableKitConfig}
				storageKey="unified_data_table_v2"
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
			<svelte:fragment slot="cell" let:cell let:column>
				{#if column === 'record_type'}
					<span
						class="inline-flex px-2 py-1 text-xs font-semibold rounded-full {cell.getValue() ===
						'case'
							? 'bg-green-100 text-green-800'
							: 'bg-blue-100 text-blue-800'}"
					>
						{cell.getValue() === 'case' ? 'Case' : 'Notice'}
					</span>
				{:else if column === 'url' && cell.getValue()}
					<a
						href={cell.getValue()}
						target="_blank"
						rel="noopener noreferrer"
						class="text-indigo-600 hover:text-indigo-900"
					>
						<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
							/>
						</svg>
					</a>
				{:else if column === 'offence_breaches' || column === 'notice_body'}
					<div class="max-w-md truncate" title={cell.getValue()}>
						{cell.getValue()}
					</div>
				{:else}
					{cell.getValue()}
				{/if}
			</svelte:fragment>
		</TableKit>
		{/if}
	{/if}
</div>

<!-- Save View Modal -->
{#if browser && showSaveModal && capturedConfig}
	<SaveViewModal
		bind:open={showSaveModal}
		config={capturedConfig}
		originalQuery={currentOriginalQuery}
		on:save={handleViewSaved}
	/>
{/if}
