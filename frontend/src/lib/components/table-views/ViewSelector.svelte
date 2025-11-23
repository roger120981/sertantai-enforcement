<script lang="ts">
	import { createEventDispatcher } from 'svelte'
	import { savedViews, recentViews, activeViewId, activeViewModified } from '$lib/stores/saved-views'
	import { viewActions } from '$lib/stores/saved-views'
	import type { SavedView } from '$lib/db/schema'

	const dispatch = createEventDispatcher<{
		viewSelected: { view: SavedView }
		deleteView: { id: string }
	}>()

	let open = false
	let searchQuery = ''
	let renamingId: string | null = null
	let renameValue = ''

	// Filter views based on search
	$: filteredViews = searchQuery
		? $savedViews.filter((v) => v.name.toLowerCase().includes(searchQuery.toLowerCase()))
		: $savedViews

	// Sort views alphabetically
	$: sortedViews = [...filteredViews].sort((a, b) => a.name.localeCompare(b.name))

	// Get active view object
	$: activeView = $savedViews.find((v) => v.id === $activeViewId)

	function toggleDropdown() {
		open = !open
		if (!open) {
			searchQuery = ''
			renamingId = null
		}
	}

	function closeDropdown() {
		open = false
		searchQuery = ''
		renamingId = null
	}

	async function selectView(view: SavedView) {
		console.log('[ViewSelector] Loading view:', view.name)
		await viewActions.load(view.id)
		dispatch('viewSelected', { view })
		closeDropdown()
	}

	function startRename(view: SavedView, event: Event) {
		event.stopPropagation()
		renamingId = view.id
		renameValue = view.name
	}

	async function confirmRename(id: string) {
		if (renameValue.trim() && renameValue !== renameValue) {
			await viewActions.rename(id, renameValue.trim())
		}
		renamingId = null
	}

	function cancelRename() {
		renamingId = null
		renameValue = ''
	}

	async function deleteView(id: string, event: Event) {
		event.stopPropagation()

		const view = $savedViews.find((v) => v.id === id)
		if (!view) return

		if (confirm(`Delete view "${view.name}"?`)) {
			await viewActions.delete(id)
			dispatch('deleteView', { id })
		}
	}

	function formatDate(timestamp: number): string {
		const date = new Date(timestamp)
		const now = new Date()
		const diffDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24))

		if (diffDays === 0) return 'Today'
		if (diffDays === 1) return 'Yesterday'
		if (diffDays < 7) return `${diffDays} days ago`
		if (diffDays < 30) return `${Math.floor(diffDays / 7)} weeks ago`
		return date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
	}

	// Close dropdown when clicking outside
	function handleClickOutside(event: MouseEvent) {
		if (open && !(event.target as Element).closest('.view-selector')) {
			closeDropdown()
		}
	}
</script>

<svelte:window on:click={handleClickOutside} />

<div class="view-selector relative">
	<!-- Trigger Button -->
	<button
		type="button"
		on:click={toggleDropdown}
		class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500"
		class:ring-2={open}
		class:ring-indigo-500={open}
	>
		<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
			<path
				stroke-linecap="round"
				stroke-linejoin="round"
				stroke-width="2"
				d="M4 6h16M4 10h16M4 14h16M4 18h16"
			/>
		</svg>
		{#if activeView}
			<span class="font-semibold">{activeView.name}</span>
			{#if $activeViewModified}
				<span class="text-orange-500" title="View has been modified">✏️</span>
			{/if}
		{:else}
			Saved Views
		{/if}
		<svg
			class="w-4 h-4 transition-transform"
			class:rotate-180={open}
			fill="none"
			stroke="currentColor"
			viewBox="0 0 24 24"
		>
			<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
		</svg>
	</button>

	<!-- Dropdown Menu -->
	{#if open}
		<div
			class="absolute left-0 mt-2 w-80 bg-white border border-gray-200 rounded-lg shadow-lg z-50 max-h-96 flex flex-col"
		>
			<!-- Search -->
			<div class="p-3 border-b border-gray-200">
				<div class="relative">
					<svg
						class="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400"
						fill="none"
						stroke="currentColor"
						viewBox="0 0 24 24"
					>
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
						/>
					</svg>
					<input
						type="text"
						bind:value={searchQuery}
						placeholder="Search views..."
						class="w-full pl-10 pr-3 py-2 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
					/>
				</div>
			</div>

			<!-- Scrollable Content -->
			<div class="overflow-y-auto flex-1">
				<!-- Recent Views -->
				{#if $recentViews.length > 0 && !searchQuery}
					<div class="px-3 py-2 border-b border-gray-200">
						<h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
							Recent
						</h3>
						{#each $recentViews as view}
							<button
								type="button"
								on:click={() => selectView(view)}
								class="w-full text-left px-3 py-2 rounded-md hover:bg-gray-50 flex items-center justify-between group"
								class:bg-indigo-50={view.id === $activeViewId}
							>
								<div class="flex-1 min-w-0">
									<p class="text-sm font-medium text-gray-900 truncate">{view.name}</p>
									<p class="text-xs text-gray-500">
										Last used: {formatDate(view.lastUsed)}
									</p>
								</div>
								<div class="flex items-center gap-1 opacity-0 group-hover:opacity-100">
									<button
										type="button"
										on:click={(e) => startRename(view, e)}
										class="p-1 hover:bg-gray-200 rounded"
										title="Rename"
									>
										<svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
											<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
										</svg>
									</button>
									<button
										type="button"
										on:click={(e) => deleteView(view.id, e)}
										class="p-1 hover:bg-red-100 rounded"
										title="Delete"
									>
										<svg class="w-4 h-4 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
											<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
										</svg>
									</button>
								</div>
							</button>
						{/each}
					</div>
				{/if}

				<!-- All Views -->
				<div class="px-3 py-2">
					<h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
						{searchQuery ? 'Search Results' : 'All Views'}
						{#if !searchQuery}
							<span class="text-gray-400">({$savedViews.length})</span>
						{/if}
					</h3>

					{#if sortedViews.length === 0}
						<div class="py-8 text-center">
							<svg class="w-12 h-12 mx-auto text-gray-400 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
								<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
							</svg>
							<p class="text-sm text-gray-500">
								{searchQuery ? 'No views found' : 'No saved views yet'}
							</p>
							<p class="text-xs text-gray-400 mt-1">
								{searchQuery ? 'Try a different search' : 'Save your first view to get started'}
							</p>
						</div>
					{:else}
						{#each sortedViews as view}
							{#if renamingId === view.id}
								<div class="px-3 py-2 bg-gray-50 rounded-md mb-1">
									<input
										type="text"
										bind:value={renameValue}
										on:blur={() => confirmRename(view.id)}
										on:keydown={(e) => {
											if (e.key === 'Enter') confirmRename(view.id)
											if (e.key === 'Escape') cancelRename()
										}}
										class="w-full px-2 py-1 text-sm border border-indigo-500 rounded focus:outline-none focus:ring-2 focus:ring-indigo-500"
										autofocus
									/>
								</div>
							{:else}
								<button
									type="button"
									on:click={() => selectView(view)}
									class="w-full text-left px-3 py-2 rounded-md hover:bg-gray-50 flex items-center justify-between group mb-1"
									class:bg-indigo-50={view.id === $activeViewId}
								>
									<div class="flex-1 min-w-0">
										<p class="text-sm font-medium text-gray-900 truncate">{view.name}</p>
										<div class="flex items-center gap-3 text-xs text-gray-500">
											{#if view.config.filters.length > 0}
												<span>{view.config.filters.length} filters</span>
											{/if}
											{#if view.usageCount > 0}
												<span>{view.usageCount} uses</span>
											{/if}
										</div>
									</div>
									<div class="flex items-center gap-1 opacity-0 group-hover:opacity-100">
										<button
											type="button"
											on:click={(e) => startRename(view, e)}
											class="p-1 hover:bg-gray-200 rounded"
											title="Rename"
										>
											<svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
												<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
											</svg>
										</button>
										<button
											type="button"
											on:click={(e) => deleteView(view.id, e)}
											class="p-1 hover:bg-red-100 rounded"
											title="Delete"
										>
											<svg class="w-4 h-4 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
												<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
											</svg>
										</button>
									</div>
								</button>
							{/if}
						{/each}
					{/if}
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	.rotate-180 {
		transform: rotate(180deg);
	}
</style>
