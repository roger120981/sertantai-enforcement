/**
 * Offenders Query-Based On-Demand Caching
 *
 * Implements the "Query-Based On-Demand Caching" pattern for offenders:
 * - NO baseline sync (pure search-driven)
 * - Search-triggered subset syncs only
 * - LRU cache management (max 10 searches)
 * - Changes-only stream for real-time updates (optional)
 *
 * Dataset: ~223 records (current), 10k+ (production potential)
 * Strategy: Search-first UX - users must search to see data
 *
 * See PUBLIC_SYNC.md for research and rationale.
 */

import { ShapeStream } from '@electric-sql/client'
import type { Offender } from '$lib/db/schema'
import { writable } from 'svelte/store'
import {
	SearchShapeManager,
	generateCacheKey,
	generateSearchDescription,
} from './search-shape-manager'

/**
 * Electric service configuration
 */
const ELECTRIC_URL = import.meta.env.PUBLIC_ELECTRIC_URL || 'http://localhost:3001'

/**
 * Sync progress state
 */
export interface OffendersSyncProgress {
	phase: 'idle' | 'searching'
	totalCached: number // Total offenders across all cached searches
	currentSearch: string | null
	searchInProgress: boolean
	error: string | null
}

/**
 * Search parameters
 */
export interface OffendersSearchParams {
	searchTerm?: string
	companyNumber?: string
	location?: string // postcode, town, county
	industry?: string
	businessType?: string
}

/**
 * Store for sync progress tracking
 */
export const offendersSyncProgress = writable<OffendersSyncProgress>({
	phase: 'idle',
	totalCached: 0,
	currentSearch: null,
	searchInProgress: false,
	error: null,
})

/**
 * Cached offenders data (search results only - NO baseline)
 * This is what TanStack Table reads from
 */
export const cachedOffenders = writable<Offender[]>([])

/**
 * Shape manager for search-based caching
 */
const searchShapeManager = new SearchShapeManager(10) // Max 10 cached searches

/**
 * Build SQL WHERE clause from search parameters
 */
function buildWhereClause(params: OffendersSearchParams): string {
	const conditions: string[] = []

	// Search term (searches name, normalized_name, local_authority)
	if (params.searchTerm && params.searchTerm.trim()) {
		const term = params.searchTerm.trim()
		// Use ILIKE for case-insensitive search
		conditions.push(
			`(name ILIKE '%${term}%' OR normalized_name ILIKE '%${term}%' OR local_authority ILIKE '%${term}%')`
		)
	}

	// Company registration number
	if (params.companyNumber && params.companyNumber.trim()) {
		conditions.push(`company_registration_number LIKE '%${params.companyNumber.trim()}%'`)
	}

	// Location (postcode, town, county)
	if (params.location && params.location.trim()) {
		const loc = params.location.trim()
		conditions.push(`(postcode ILIKE '%${loc}%' OR town ILIKE '%${loc}%' OR county ILIKE '%${loc}%')`)
	}

	// Industry
	if (params.industry && params.industry.trim()) {
		const ind = params.industry.trim()
		conditions.push(`(industry ILIKE '%${ind}%' OR main_activity ILIKE '%${ind}%')`)
	}

	// Business type
	if (params.businessType) {
		conditions.push(`business_type = '${params.businessType}'`)
	}

	return conditions.length > 0 ? conditions.join(' AND ') : ''
}

/**
 * Baseline sync for all offenders
 *
 * Loads all offenders from the database. Since aggregate fields (total_cases, total_notices, last_seen_date)
 * are not yet populated, we load all offenders to provide a complete dataset.
 * Users can filter/search using the table controls and AI queries.
 */
async function syncBaselineOffenders(): Promise<void> {
	console.log('[Offenders Sync] Starting baseline sync (all offenders)...')

	offendersSyncProgress.update((state) => ({
		...state,
		phase: 'searching',
		currentSearch: 'Baseline: All offenders',
		searchInProgress: true,
	}))

	try {
		// Load all offenders (no WHERE clause)
		// This is fine since we only have ~23k records
		console.log('[Offenders Sync] Loading all offenders (no filter)')

		const stream = new ShapeStream<Offender>({
			url: `${ELECTRIC_URL}/v1/shape`,
			params: {
				table: 'offenders',
			},
		})

		const baselineResults: Offender[] = []

		return new Promise((resolve, reject) => {
			let initialSyncComplete = false

			const subscription = stream.subscribe((messages) => {
				messages.forEach((msg: any) => {
					if (msg.headers?.control) return

					const operation = msg.headers?.operation
					const data = msg.value as Offender

					if (operation === 'insert' && data) {
						baselineResults.push(data)
					}
				})

				// Mark baseline complete after first batch
				if (!initialSyncComplete && messages.length > 0) {
					initialSyncComplete = true

					// Set as cached offenders
					cachedOffenders.set(baselineResults)

					// Cache the baseline shape
					const baselineCacheKey = 'baseline_all'
					searchShapeManager.add(
						baselineCacheKey,
						'Baseline: All offenders',
						subscription,
						baselineResults.length
					)

					offendersSyncProgress.update((state) => ({
						...state,
						phase: 'idle',
						searchInProgress: false,
						currentSearch: null,
						totalCached: baselineResults.length,
					}))

					console.log(
						`[Offenders Sync] Baseline complete: ${baselineResults.length} offenders loaded`
					)

					resolve()
				}
			})

			// Timeout after 30 seconds (baseline can be larger)
			setTimeout(() => {
				if (!initialSyncComplete) {
					offendersSyncProgress.update((state) => ({
						...state,
						phase: 'idle',
						searchInProgress: false,
						currentSearch: null,
						error: 'Baseline sync timeout',
					}))
					reject(new Error('Baseline sync timeout'))
				}
			}, 30000)
		})
	} catch (error) {
		console.error('[Offenders Sync] Baseline sync failed:', error)
		offendersSyncProgress.update((state) => ({
			...state,
			phase: 'idle',
			searchInProgress: false,
			currentSearch: null,
			error: error instanceof Error ? error.message : 'Baseline sync failed',
		}))
		throw error
	}
}

/**
 * Initialize offenders sync WITH baseline (all offenders)
 *
 * Loads all offenders to populate the table on first load.
 * Users can filter/search using table controls and AI queries.
 */
export async function initOffendersSync(): Promise<void> {
	console.log('[Offenders Sync] Initializing with baseline (all offenders)...')

	offendersSyncProgress.update((state) => ({
		...state,
		phase: 'searching',
		totalCached: 0,
		currentSearch: null,
		searchInProgress: false,
		error: null,
	}))

	// Sync baseline (all offenders)
	try {
		await syncBaselineOffenders()
		console.log('[Offenders Sync] Baseline loaded - ready for filtering and queries')
	} catch (error) {
		console.error('[Offenders Sync] Baseline sync failed, starting with empty table:', error)
		// Continue with empty table if baseline fails
		offendersSyncProgress.update((state) => ({
			...state,
			phase: 'idle',
			error: 'Baseline sync failed - try refreshing the page',
		}))
	}
}

/**
 * Search-triggered subset sync
 *
 * When user searches, sync matching offenders and cache for offline access.
 * Uses SearchShapeManager for LRU cache eviction.
 */
export async function searchOffenders(params: OffendersSearchParams): Promise<Offender[]> {
	const cacheKey = generateCacheKey(params)
	const description = generateSearchDescription(params)

	// Check cache first
	if (searchShapeManager.has(cacheKey)) {
		console.log(`[Offenders Sync] Cache HIT: ${description}`)
		searchShapeManager.get(cacheKey) // Update LRU timestamp

		// Return cached results (filter from cachedOffenders store)
		const allOffenders = cachedOffenders
		// In production, you'd filter by the search params
		// For now, return all cached offenders
		return new Promise((resolve) => {
			const unsubscribe = allOffenders.subscribe((offenders) => {
				resolve(offenders)
				unsubscribe()
			})
		})
	}

	// Cache MISS - sync new subset
	console.log(`[Offenders Sync] Cache MISS: ${description} - syncing from server...`)

	offendersSyncProgress.update((state) => ({
		...state,
		phase: 'searching',
		currentSearch: description,
		searchInProgress: true,
	}))

	try {
		const whereClause = buildWhereClause(params)

		if (!whereClause) {
			// Empty search - return empty results (no baseline)
			offendersSyncProgress.update((state) => ({
				...state,
				searchInProgress: false,
				currentSearch: null,
			}))
			return []
		}

		console.log('[Offenders Sync] WHERE clause:', whereClause)

		const stream = new ShapeStream<Offender>({
			url: `${ELECTRIC_URL}/v1/shape`,
			params: {
				table: 'offenders',
				where: whereClause,
			},
		})

		const searchResults: Offender[] = []

		return new Promise((resolve, reject) => {
			let initialSyncComplete = false

			const subscription = stream.subscribe((messages) => {
				messages.forEach((msg: any) => {
					if (msg.headers?.control) return

					const operation = msg.headers?.operation
					const data = msg.value as Offender

					if (operation === 'insert' && data) {
						searchResults.push(data)
					}
				})

				// Mark search complete after first batch
				if (!initialSyncComplete && messages.length > 0) {
					initialSyncComplete = true

					// Add to cached offenders
					cachedOffenders.update((existing) => {
						const combined = [...existing, ...searchResults]
						// Deduplicate
						return Array.from(new Map(combined.map((o) => [o.id, o])).values())
					})

					// Cache the shape subscription
					searchShapeManager.add(cacheKey, description, subscription, searchResults.length)

					offendersSyncProgress.update((state) => {
						let totalCached = 0
						cachedOffenders.subscribe((offenders) => {
							totalCached = offenders.length
						})()

						return {
							...state,
							searchInProgress: false,
							currentSearch: null,
							totalCached,
						}
					})

					console.log(
						`[Offenders Sync] Search complete: ${searchResults.length} results for "${description}"`
					)

					resolve(searchResults)
				}
			})

			// Timeout after 10 seconds
			setTimeout(() => {
				if (!initialSyncComplete) {
					offendersSyncProgress.update((state) => ({
						...state,
						searchInProgress: false,
						currentSearch: null,
						error: 'Search timeout',
					}))
					reject(new Error('Search timeout'))
				}
			}, 10000)
		})
	} catch (error) {
		console.error('[Offenders Sync] Search failed:', error)
		offendersSyncProgress.update((state) => ({
			...state,
			searchInProgress: false,
			currentSearch: null,
			error: error instanceof Error ? error.message : 'Unknown error',
		}))
		throw error
	}
}

/**
 * Stop all offenders syncs
 */
export function stopOffendersSync(): void {
	console.log('[Offenders Sync] Stopping all syncs...')

	// Clear search cache
	searchShapeManager.clear()

	offendersSyncProgress.update((state) => ({
		...state,
		phase: 'idle',
	}))
}

/**
 * Get cache statistics (for UI display)
 */
export function getOffendersCacheStats() {
	return searchShapeManager.getStats()
}

/**
 * Get cache state store (for UI)
 */
export function getOffendersCacheState() {
	return searchShapeManager.getCacheState()
}
