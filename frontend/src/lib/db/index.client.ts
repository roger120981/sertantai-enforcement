/**
 * TanStack DB Collections (Client-Only)
 *
 * Creates reactive collections for each database table.
 * Collections provide:
 * - Local storage with IndexedDB persistence
 * - Reactive queries that auto-update
 * - Optimistic mutations
 *
 * NOTE: This module uses dynamic imports to ensure it only runs in the browser.
 * DO NOT import collections directly - use the exported functions instead.
 */

import { browser } from '$app/environment'
import type { Case, Agency, Offender, ScrapeSession, SavedView } from './schema'
import type { Collection } from '@tanstack/db'

// Collection singletons (initialized lazily in browser)
let casesCol: Collection<Case, string> | null = null
let agenciesCol: Collection<Agency, string> | null = null
let offendersCol: Collection<Offender, string> | null = null
let scrapeSessionsCol: Collection<ScrapeSession, string> | null = null
let savedViewsCol: Collection<SavedView, string> | null = null

/**
 * Initialize collections (browser only)
 */
async function ensureCollections() {
  if (!browser) {
    throw new Error('TanStack DB collections can only be initialized in the browser')
  }

  if (casesCol && agenciesCol && offendersCol && scrapeSessionsCol && savedViewsCol) {
    return // Already initialized
  }

  const { createCollection, localStorageCollectionOptions } = await import('@tanstack/db')

  casesCol = createCollection(
    localStorageCollectionOptions<Case, string>({
      storageKey: 'ehs-enforcement-cases',
      getKey: (item) => item.id,
    })
  )

  agenciesCol = createCollection(
    localStorageCollectionOptions<Agency, string>({
      storageKey: 'ehs-enforcement-agencies',
      getKey: (item) => item.id,
    })
  )

  offendersCol = createCollection(
    localStorageCollectionOptions<Offender, string>({
      storageKey: 'ehs-enforcement-offenders',
      getKey: (item) => item.id,
    })
  )

  scrapeSessionsCol = createCollection(
    localStorageCollectionOptions<ScrapeSession, string>({
      storageKey: 'ehs-enforcement-scrape-sessions',
      getKey: (item) => item.id,
    })
  )

  savedViewsCol = createCollection(
    localStorageCollectionOptions<SavedView, string>({
      storageKey: 'ehs-enforcement-saved-views',
      getKey: (item) => item.id,
    })
  )
}

/**
 * Get cases collection (browser only)
 */
export async function getCasesCollection(): Promise<Collection<Case, string>> {
  await ensureCollections()
  return casesCol!
}

/**
 * Get agencies collection (browser only)
 */
export async function getAgenciesCollection(): Promise<Collection<Agency, string>> {
  await ensureCollections()
  return agenciesCol!
}

/**
 * Get offenders collection (browser only)
 */
export async function getOffendersCollection(): Promise<Collection<Offender, string>> {
  await ensureCollections()
  return offendersCol!
}

/**
 * Get scrape sessions collection (browser only)
 */
export async function getScrapeSessionsCollection(): Promise<Collection<ScrapeSession, string>> {
  await ensureCollections()
  return scrapeSessionsCol!
}

/**
 * Get saved views collection (browser only)
 */
export async function getSavedViewsCollection(): Promise<Collection<SavedView, string>> {
  await ensureCollections()
  return savedViewsCol!
}

// Legacy exports for backward compatibility (will throw on server)
export const casesCollection = new Proxy({} as Collection<Case, string>, {
  get() {
    throw new Error('Use getCasesCollection() instead of direct import')
  },
})

export const agenciesCollection = new Proxy({} as Collection<Agency, string>, {
  get() {
    throw new Error('Use getAgenciesCollection() instead of direct import')
  },
})

export const offendersCollection = new Proxy({} as Collection<Offender, string>, {
  get() {
    throw new Error('Use getOffendersCollection() instead of direct import')
  },
})

/**
 * Initialize all collections
 *
 * Ensures collections are created and ready to use
 */
export async function initDB(): Promise<void> {
  if (!browser) {
    console.warn('[TanStack DB] initDB called on server - skipping')
    return
  }

  try {
    await ensureCollections()
    console.log('[TanStack DB] Collections initialized successfully')
  } catch (error) {
    console.error('[TanStack DB] Failed to initialize collections:', error)
    throw error
  }
}

/**
 * Get database status
 */
export function getDBStatus() {
  if (!browser) {
    return {
      initialized: false,
      collections: {},
      storage: 'N/A (SSR)',
    }
  }

  const initialized = casesCol !== null && agenciesCol !== null && offendersCol !== null && scrapeSessionsCol !== null && savedViewsCol !== null

  return {
    initialized,
    collections: initialized
      ? {
          cases: casesCol!.id,
          agencies: agenciesCol!.id,
          offenders: offendersCol!.id,
          scrapeSessions: scrapeSessionsCol!.id,
          savedViews: savedViewsCol!.id,
        }
      : {},
    storage: 'localStorage (IndexedDB)',
  }
}

/**
 * Clear all collections (useful for testing/debugging)
 *
 * WARNING: This will delete all local data!
 */
export async function clearDB(): Promise<void> {
  if (!browser) {
    console.warn('[TanStack DB] clearDB called on server - skipping')
    return
  }

  try {
    await ensureCollections()

    // Clear each collection
    const caseKeys = Array.from(casesCol!.getAllKeys())
    const agencyKeys = Array.from(agenciesCol!.getAllKeys())
    const offenderKeys = Array.from(offendersCol!.getAllKeys())
    const scrapeSessionKeys = Array.from(scrapeSessionsCol!.getAllKeys())

    for (const key of caseKeys) {
      casesCol!.delete(key)
    }
    for (const key of agencyKeys) {
      agenciesCol!.delete(key)
    }
    for (const key of offenderKeys) {
      offendersCol!.delete(key)
    }
    for (const key of scrapeSessionKeys) {
      scrapeSessionsCol!.delete(key)
    }

    console.log('[TanStack DB] Collections cleared')
  } catch (error) {
    console.error('[TanStack DB] Failed to clear collections:', error)
    throw error
  }
}
