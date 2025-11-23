/**
 * Saved Views Store
 *
 * Reactive Svelte store for managing saved table view configurations.
 * Uses browser localStorage for Phase 4.1 (simple, fast implementation).
 *
 * Future: Migrate to TanStack DB or backend storage.
 */

import { writable, derived, get } from 'svelte/store'
import { browser } from '$app/environment'
import type { SavedView } from '$lib/db/schema'
import type { SavedViewInput } from '$lib/components/table-views/types'

const STORAGE_KEY = 'ehs_enforcement_saved_views'

// Active view tracking
export const activeViewId = writable<string | null>(null)
export const activeViewModified = writable<boolean>(false)

// Load views from localStorage
function loadViewsFromStorage(): SavedView[] {
	if (!browser) return []

	try {
		const stored = localStorage.getItem(STORAGE_KEY)
		if (!stored) return []

		const parsed = JSON.parse(stored)
		return Array.isArray(parsed) ? parsed : []
	} catch (err) {
		console.error('[SavedViews] Failed to load from localStorage:', err)
		return []
	}
}

// Save views to localStorage
function saveViewsToStorage(views: SavedView[]) {
	if (!browser) return

	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(views))
	} catch (err) {
		console.error('[SavedViews] Failed to save to localStorage:', err)
	}
}

// All saved views (reactive store)
export const savedViews = writable<SavedView[]>(loadViewsFromStorage())

// Sync to localStorage on changes
if (browser) {
	savedViews.subscribe((views) => {
		saveViewsToStorage(views)
	})
}

// Recent views (last 7 days, top 5, sorted by lastUsed)
export const recentViews = derived(savedViews, ($views) => {
	const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
	return $views
		.filter((v) => v.lastUsed >= sevenDaysAgo)
		.sort((a, b) => b.lastUsed - a.lastUsed)
		.slice(0, 5)
})

// Active view (full object)
export const activeView = derived([savedViews, activeViewId], ([$views, $id]) => {
	return $id ? $views.find((v) => v.id === $id) : null
})

/**
 * View Actions
 *
 * CRUD operations for saved views
 */
export const viewActions = {
	/**
	 * Save a new view
	 */
	async save(input: SavedViewInput): Promise<SavedView> {
		if (!browser) {
			throw new Error('Cannot save views on server')
		}

		const newView: SavedView = {
			...input,
			id: crypto.randomUUID(),
			createdAt: Date.now(),
			updatedAt: Date.now(),
			usageCount: 0,
			lastUsed: Date.now()
		}

		savedViews.update((views) => [...views, newView])
		console.log('[SavedViews] Saved new view:', newView.name, newView.id)

		return newView
	},

	/**
	 * Load an existing view
	 * Updates usage statistics and sets as active
	 */
	async load(id: string): Promise<SavedView | undefined> {
		if (!browser) {
			throw new Error('Cannot load views on server')
		}

		const views = get(savedViews)
		const view = views.find((v) => v.id === id)

		if (view) {
			// Update usage stats
			savedViews.update((views) =>
				views.map((v) =>
					v.id === id
						? {
								...v,
								usageCount: v.usageCount + 1,
								lastUsed: Date.now()
						  }
						: v
				)
			)

			activeViewId.set(id)
			activeViewModified.set(false)

			console.log('[SavedViews] Loaded view:', view.name, 'Usage:', view.usageCount + 1)
		} else {
			console.warn('[SavedViews] View not found:', id)
		}

		return view
	},

	/**
	 * Update an existing view
	 */
	async update(id: string, updates: Partial<SavedView>): Promise<void> {
		if (!browser) {
			throw new Error('Cannot update views on server')
		}

		const views = get(savedViews)
		const view = views.find((v) => v.id === id)

		if (view) {
			savedViews.update((views) =>
				views.map((v) =>
					v.id === id
						? {
								...v,
								...updates,
								updatedAt: Date.now()
						  }
						: v
				)
			)

			activeViewModified.set(false)
			console.log('[SavedViews] Updated view:', id)
		} else {
			console.warn('[SavedViews] Cannot update - view not found:', id)
		}
	},

	/**
	 * Delete a view
	 */
	async delete(id: string): Promise<void> {
		if (!browser) {
			throw new Error('Cannot delete views on server')
		}

		const views = get(savedViews)
		const view = views.find((v) => v.id === id)

		if (view) {
			savedViews.update((views) => views.filter((v) => v.id !== id))
			console.log('[SavedViews] Deleted view:', view.name)

			// Clear active view if it was the deleted one
			if (get(activeViewId) === id) {
				activeViewId.set(null)
				activeViewModified.set(false)
			}
		} else {
			console.warn('[SavedViews] Cannot delete - view not found:', id)
		}
	},

	/**
	 * Rename a view
	 */
	async rename(id: string, newName: string): Promise<void> {
		if (!browser) {
			throw new Error('Cannot rename views on server')
		}

		const views = get(savedViews)
		const view = views.find((v) => v.id === id)

		if (view) {
			savedViews.update((views) =>
				views.map((v) =>
					v.id === id
						? {
								...v,
								name: newName,
								updatedAt: Date.now()
						  }
						: v
				)
			)

			console.log('[SavedViews] Renamed view:', view.name, '→', newName)
		} else {
			console.warn('[SavedViews] Cannot rename - view not found:', id)
		}
	},

	/**
	 * Mark active view as modified
	 */
	markModified(): void {
		activeViewModified.set(true)
	},

	/**
	 * Clear active view
	 */
	clearActive(): void {
		activeViewId.set(null)
		activeViewModified.set(false)
	},

	/**
	 * Check if view name already exists
	 */
	async nameExists(name: string, excludeId?: string): Promise<boolean> {
		if (!browser) return false

		const views = get(savedViews)
		return views.some((v) => v.name === name && v.id !== excludeId)
	},

	/**
	 * Get storage usage stats
	 */
	async getStorageStats(): Promise<{ count: number; limit: number; percentFull: number }> {
		if (!browser) {
			return { count: 0, limit: 50, percentFull: 0 }
		}

		const views = get(savedViews)
		const count = views.length
		const limit = 50

		return {
			count,
			limit,
			percentFull: Math.round((count / limit) * 100)
		}
	}
}
