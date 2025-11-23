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
	let selectedIndex = -1 // For keyboard navigation

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
			selectedIndex = -1
		}
	}

	function closeDropdown() {
		open = false
		searchQuery = ''
		renamingId = null
		selectedIndex = -1
	}

	// Keyboard navigation handler
	function handleKeydown(event: KeyboardEvent) {
		if (!open || renamingId) return

		const viewsList = sortedViews

		switch (event.key) {
			case 'ArrowDown':
				event.preventDefault()
				selectedIndex = Math.min(selectedIndex + 1, viewsList.length - 1)
				break
			case 'ArrowUp':
				event.preventDefault()
				selectedIndex = Math.max(selectedIndex - 1, -1)
				break
			case 'Enter':
				event.preventDefault()
				if (selectedIndex >= 0 && selectedIndex < viewsList.length) {
					selectView(viewsList[selectedIndex])
				}
				break
			case 'Escape':
				event.preventDefault()
				closeDropdown()
				break
		}
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
		const view = $savedViews.find((v) => v.id === id)
		if (!view) return

		const trimmedValue = renameValue.trim()

		// Only rename if value changed and is not empty
		if (trimmedValue && trimmedValue !== view.name) {
			await viewActions.rename(id, trimmedValue)
		}

		renamingId = null
		renameValue = ''
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

	async function duplicateView(view: SavedView, event: Event) {
		event.stopPropagation()

		try {
			// Generate unique name
			let duplicateName = `${view.name} (Copy)`
			let counter = 2
			while (await viewActions.nameExists(duplicateName)) {
				duplicateName = `${view.name} (Copy ${counter})`
				counter++
			}

			// Create duplicate with new ID and name
			await viewActions.save({
				name: duplicateName,
				description: view.description,
				config: view.config,
				originalQuery: view.originalQuery
			})

			console.log('[ViewSelector] Duplicated view:', view.name, '→', duplicateName)
		} catch (err) {
			console.error('[ViewSelector] Failed to duplicate view:', err)
			alert('Failed to duplicate view. Please try again.')
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

<svelte:window on:click={handleClickOutside} on:keydown={handleKeydown} />

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
										on:click={(e) => duplicateView(view, e)}
										class="p-1 hover:bg-blue-100 rounded"
										title="Duplicate"
									>
										<svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
											<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
										</svg>
									</button>
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
						<!-- Reset selectedIndex when no views -->
						{@const _ = (selectedIndex = -1)}
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
						{#each sortedViews as view, i}
							{#if renamingId === view.id}
								<div class="px-3 py-2 bg-gray-50 rounded-md mb-1">
									<div class="flex items-center gap-2">
										<input
											type="text"
											bind:value={renameValue}
											on:keydown={(e) => {
												if (e.key === 'Enter') {
													e.preventDefault()
													confirmRename(view.id)
												}
												if (e.key === 'Escape') {
													e.preventDefault()
													cancelRename()
												}
											}}
											class="flex-1 px-2 py-1 text-sm border border-indigo-500 rounded focus:outline-none focus:ring-2 focus:ring-indigo-500"
											autofocus
										/>
										<button
											type="button"
											on:click={() => confirmRename(view.id)}
											class="p-1 bg-indigo-600 text-white rounded hover:bg-indigo-700"
											title="Save (Enter)"
										>
											<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
												<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
											</svg>
										</button>
										<button
											type="button"
											on:click={cancelRename}
											class="p-1 bg-gray-400 text-white rounded hover:bg-gray-500"
											title="Cancel (Esc)"
										>
											<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
												<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
											</svg>
										</button>
									</div>
								</div>
							{:else}
								<button
									type="button"
									on:click={() => selectView(view)}
									class="w-full text-left px-3 py-2 rounded-md hover:bg-gray-50 flex items-center justify-between group mb-1"
									class:bg-indigo-50={view.id === $activeViewId}
									class:ring-2={selectedIndex === i}
									class:ring-indigo-400={selectedIndex === i}
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
											on:click={(e) => duplicateView(view, e)}
											class="p-1 hover:bg-blue-100 rounded"
											title="Duplicate"
										>
											<svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
												<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
											</svg>
										</button>
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
