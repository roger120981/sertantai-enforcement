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
		const stream = new ShapeStream<Offence>({
			url: `${ELECTRIC_URL}/v1/shape`,
			params: {
				table: 'offences',
			},
		})

		console.log('[Offences Sync] Shape stream created, subscribing...')

		const offences: Offence[] = []

		shapeStream = stream.subscribe((messages) => {
			messages.forEach((msg: any) => {
				if (msg.headers?.control) {
					// Handle control messages (up-to-date)
					if (msg.headers.control === 'up-to-date') {
						console.log('[Offences Sync] Baseline complete!')
						console.log('[Offences Sync] Total offences loaded:', offences.length)

						cachedOffences.set(offences)
						offencesSyncProgress.update((state) => ({
							...state,
							phase: 'streaming',
							total: offences.length,
						}))
					}
					return
				}

				const operation = msg.headers?.operation
				const data = msg.value as Offence

				if (operation === 'insert' && data) {
					offences.push(data)
					console.log(`[Offences Sync] Insert: ${data.offence_description?.substring(0, 50) || data.id}`)
				} else if (operation === 'update' && data) {
					const index = offences.findIndex((o) => o.id === data.id)
					if (index !== -1) {
						offences[index] = data
						console.log(`[Offences Sync] Update: ${data.offence_description?.substring(0, 50) || data.id}`)
					}
				} else if (operation === 'delete' && msg.key) {
					const index = offences.findIndex((o) => o.id === msg.key)
					if (index !== -1) {
						offences.splice(index, 1)
						console.log(`[Offences Sync] Delete: ${msg.key}`)
					}
				}

				// Update store with current data
				cachedOffences.set([...offences])
				offencesSyncProgress.update((state) => ({
					...state,
					total: offences.length,
				}))
			})
		})

		console.log('[Offences Sync] Successfully subscribed to stream')
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
 * Cleanup function to stop syncing
 */
export function stopOffencesSync(): void {
	if (shapeStream) {
		console.log('[Offences Sync] Stopping sync and cleaning up')
		shapeStream.unsubscribeAll()
		shapeStream = null
	}
}
