<script lang="ts">
	import { createEventDispatcher } from 'svelte'
	import { viewActions } from '$lib/stores/saved-views'
	import type { TableConfig } from './types'

	export let open = false
	export let config: TableConfig
	export let originalQuery: string | undefined = undefined

	const dispatch = createEventDispatcher<{ save: { id: string; name: string } }>()

	let name = ''
	let description = ''
	let saving = false
	let error = ''

	// Reset form when modal opens
	$: if (open) {
		name = ''
		description = ''
		error = ''
	}

	// Count filters
	$: filterCount = config.filters.length
	$: hasSort = config.sort !== null
	$: columnCount = config.columns.length

	async function handleSave() {
		// Validation
		if (!name.trim()) {
			error = 'Name is required'
			return
		}

		if (name.length > 100) {
			error = 'Name must be 100 characters or less'
			return
		}

		// Check for duplicate name
		const nameExists = await viewActions.nameExists(name.trim())
		if (nameExists) {
			error = `View "${name.trim()}" already exists. Please choose a different name.`
			return
		}

		// Check storage limit
		const stats = await viewActions.getStorageStats()
		if (stats.count >= stats.limit) {
			error = `Storage limit reached (${stats.limit} views). Please delete unused views.`
			return
		}

		saving = true
		error = ''

		try {
			const savedView = await viewActions.save({
				name: name.trim(),
				description: description.trim() || undefined,
				config,
				originalQuery
			})

			console.log('[SaveViewModal] View saved successfully:', savedView.name)

			// Dispatch save event
			dispatch('save', { id: savedView.id, name: savedView.name })

			// Close modal
			open = false
		} catch (err) {
			console.error('[SaveViewModal] Failed to save view:', err)
			error = 'Failed to save view. Please try again.'
		} finally {
			saving = false
		}
	}

	function handleCancel() {
		open = false
	}

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			handleCancel()
		} else if (e.key === 'Enter' && e.ctrlKey) {
			handleSave()
		}
	}
</script>

{#if open}
	<div
		class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
		on:click={handleCancel}
		on:keydown={handleKeydown}
		role="dialog"
		aria-modal="true"
		aria-labelledby="modal-title"
	>
		<div
			class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4"
			on:click|stopPropagation
			role="document"
		>
			<!-- Header -->
			<div class="px-6 py-4 border-b border-gray-200">
				<h2 id="modal-title" class="text-xl font-semibold text-gray-900">Save Table View</h2>
			</div>

			<!-- Body -->
			<div class="px-6 py-4 space-y-4">
				<!-- Name Input -->
				<div>
					<label for="view-name" class="block text-sm font-medium text-gray-700 mb-1">
						Name <span class="text-red-500">*</span>
					</label>
					<input
						id="view-name"
						type="text"
						bind:value={name}
						placeholder="e.g., High-value HSE cases 2024"
						maxlength="100"
						class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
						class:border-red-500={error && !name.trim()}
						autofocus
					/>
					<p class="text-xs text-gray-500 mt-1">{name.length}/100 characters</p>
				</div>

				<!-- Description Input -->
				<div>
					<label for="view-description" class="block text-sm font-medium text-gray-700 mb-1">
						Description (optional)
					</label>
					<textarea
						id="view-description"
						bind:value={description}
						placeholder="Brief description of this view..."
						maxlength="500"
						rows="3"
						class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none"
					/>
					<p class="text-xs text-gray-500 mt-1">{description.length}/500 characters</p>
				</div>

				<!-- What's being saved -->
				<div class="bg-gray-50 rounded-md p-4 space-y-2">
					<p class="text-sm font-medium text-gray-700">This view includes:</p>
					<ul class="text-sm text-gray-600 space-y-1">
						{#if filterCount > 0}
							<li class="flex items-center gap-2">
								<svg
									class="w-4 h-4 text-green-600"
									fill="none"
									stroke="currentColor"
									viewBox="0 0 24 24"
								>
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M5 13l4 4L19 7"
									/>
								</svg>
								{filterCount} active {filterCount === 1 ? 'filter' : 'filters'}
							</li>
						{/if}
						{#if hasSort}
							<li class="flex items-center gap-2">
								<svg
									class="w-4 h-4 text-green-600"
									fill="none"
									stroke="currentColor"
									viewBox="0 0 24 24"
								>
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M5 13l4 4L19 7"
									/>
								</svg>
								Sort by: {config.sort?.columnId} ({config.sort?.direction})
							</li>
						{/if}
						<li class="flex items-center gap-2">
							<svg
								class="w-4 h-4 text-green-600"
								fill="none"
								stroke="currentColor"
								viewBox="0 0 24 24"
							>
								<path
									stroke-linecap="round"
									stroke-linejoin="round"
									stroke-width="2"
									d="M5 13l4 4L19 7"
								/>
							</svg>
							{columnCount} visible {columnCount === 1 ? 'column' : 'columns'} (custom order)
						</li>
						<li class="flex items-center gap-2">
							<svg
								class="w-4 h-4 text-green-600"
								fill="none"
								stroke="currentColor"
								viewBox="0 0 24 24"
							>
								<path
									stroke-linecap="round"
									stroke-linejoin="round"
									stroke-width="2"
									d="M5 13l4 4L19 7"
								/>
							</svg>
							Column widths and page size
						</li>
					</ul>
				</div>

				<!-- Error Message -->
				{#if error}
					<div class="bg-red-50 border border-red-200 rounded-md p-3">
						<p class="text-sm text-red-800">{error}</p>
					</div>
				{/if}
			</div>

			<!-- Footer -->
			<div class="px-6 py-4 border-t border-gray-200 flex justify-end gap-3">
				<button
					type="button"
					on:click={handleCancel}
					disabled={saving}
					class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50"
				>
					Cancel
				</button>
				<button
					type="button"
					on:click={handleSave}
					disabled={saving || !name.trim()}
					class="px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
				>
					{#if saving}
						<svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
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
						Saving...
					{:else}
						<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"
							/>
						</svg>
						Save View
					{/if}
				</button>
			</div>

			<!-- Keyboard shortcuts hint -->
			<div class="px-6 pb-3">
				<p class="text-xs text-gray-500">
					Tip: Press <kbd class="px-1 py-0.5 bg-gray-100 border border-gray-300 rounded text-xs"
						>Esc</kbd
					> to cancel,
					<kbd class="px-1 py-0.5 bg-gray-100 border border-gray-300 rounded text-xs">Ctrl</kbd>
					+
					<kbd class="px-1 py-0.5 bg-gray-100 border border-gray-300 rounded text-xs">Enter</kbd>
					to save
				</p>
			</div>
		</div>
	</div>
{/if}
