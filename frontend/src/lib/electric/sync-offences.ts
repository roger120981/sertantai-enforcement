/**
 * Offences Baseline Sync
 *
 * Implements baseline sync for offences table (all records loaded on init).
 * Similar to legislation sync pattern.
 *
 * Dataset: 0 records (current), expected to grow with data extraction
 * Strategy: Baseline sync - load all offences on page load
 */

import { ShapeStream } from '@electric-sql/client'
import type { Offence } from '$lib/db/schema'
import { writable } from 'svelte/store'

/**
 * Electric service configuration
 */
const ELECTRIC_URL = import.meta.env.PUBLIC_ELECTRIC_URL || 'http://localhost:3001'

/**
 * Sync progress state
 */
export interface OffencesSyncProgress {
	phase: 'idle' | 'baseline' | 'streaming'
	total: number
	error: string | null
}

/**
 * Store for sync progress tracking
 */
export const offencesSyncProgress = writable<OffencesSyncProgress>({
	phase: 'idle',
	total: 0,
	error: null,
})

/**
 * Cached offences data (baseline - all offences)
 * This is what TanStack Table reads from
 */
export const cachedOffences = writable<Offence[]>([])

/**
 * Shape stream reference for cleanup
 */
let shapeStream: ShapeStream<Offence> | null = null

/**
 * Initialize offences sync with baseline (all offences)
 */
export async function initOffencesSync(): Promise<void> {
	console.log('[Offences Sync] Starting baseline sync...')

	offencesSyncProgress.update((state) => ({
		...state,
		phase: 'baseline',
		error: null,
	}))

	try {
		// Cleanup existing stream
		if (shapeStream) {
			console.log('[Offences Sync] Cleaning up existing stream')
			shapeStream.unsubscribeAll()
			shapeStream = null
		}

		// Create shape stream for all offences
		shapeStream = new ShapeStream<Offence>({
			url: `${ELECTRIC_URL}/v1/shape`,
			params: {
				table: 'offences',
			},
		})

		console.log('[Offences Sync] Shape stream created, waiting for baseline...')

		// Collect baseline data
		const offencesMap = new Map<string, Offence>()

		for await (const messages of shapeStream) {
			for (const message of messages) {
				// Handle inserts, updates, and deletes
				if (message.headers.action === 'delete') {
					offencesMap.delete(message.key)
					console.log(`[Offences Sync] Deleted offence: ${message.key}`)
				} else {
					const offence = message.value as Offence
					offencesMap.set(message.key, offence)
				}
			}

			// Check if we've completed the baseline
			if (messages.some((msg) => msg.headers.control === 'up-to-date')) {
				console.log('[Offences Sync] Baseline complete!')
				console.log('[Offences Sync] Total offences loaded:', offencesMap.size)

				// Update store with baseline data
				const offencesArray = Array.from(offencesMap.values())
				cachedOffences.set(offencesArray)

				offencesSyncProgress.update((state) => ({
					...state,
					phase: 'streaming',
					total: offencesArray.length,
				}))

				break // Exit baseline loop, continue streaming in background
			}
		}

		console.log('[Offences Sync] Baseline sync completed, now streaming updates...')

		// Continue streaming updates in background
		streamUpdates(shapeStream, offencesMap)
	} catch (err) {
		console.error('[Offences Sync] Error during sync:', err)
		offencesSyncProgress.update((state) => ({
			...state,
			phase: 'idle',
			error: err instanceof Error ? err.message : 'Unknown error during sync',
		}))
		throw err
	}
}

/**
 * Stream real-time updates after baseline
 */
async function streamUpdates(
	stream: ShapeStream<Offence>,
	offencesMap: Map<string, Offence>
): Promise<void> {
	try {
		for await (const messages of stream) {
			let hasChanges = false

			for (const message of messages) {
				// Skip control messages
				if (message.headers.control) continue

				hasChanges = true

				// Handle inserts, updates, and deletes
				if (message.headers.action === 'delete') {
					offencesMap.delete(message.key)
					console.log(`[Offences Sync] Real-time delete: ${message.key}`)
				} else {
					const offence = message.value as Offence
					offencesMap.set(message.key, offence)
					console.log(
						`[Offences Sync] Real-time ${message.headers.action}: ${offence.offence_description?.substring(0, 50) || offence.id}`
					)
				}
			}

			// Update store if there were changes
			if (hasChanges) {
				const offencesArray = Array.from(offencesMap.values())
				cachedOffences.set(offencesArray)
				offencesSyncProgress.update((state) => ({
					...state,
					total: offencesArray.length,
				}))
			}
		}
	} catch (err) {
		console.error('[Offences Sync] Error during streaming:', err)
		offencesSyncProgress.update((state) => ({
			...state,
			error: err instanceof Error ? err.message : 'Unknown error during streaming',
		}))
	}
}

/**
 * Cleanup function to stop syncing
 */
export function stopOffencesSync(): void {
	if (shapeStream) {
		console.log('[Offences Sync] Stopping sync and cleaning up')
		shapeStream.unsubscribeAll()
		shapeStream = null
	}
}
