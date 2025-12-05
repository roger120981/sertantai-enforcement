/**
 * TanStack Query Hooks for Scrape Sessions
 *
 * Provides reactive queries for browsing scraping session history.
 * Data is synced from PostgreSQL via ElectricSQL to Svelte store,
 * with fallback to REST API when ElectricSQL is unavailable.
 */

import { createQuery } from '@tanstack/svelte-query'
import { scrapeSessionsStore, setScrapeSessions } from '$lib/stores/scrapeSessions'
import { get } from 'svelte/store'
import type { ScrapeSession } from '$lib/db/schema'
import { browser } from '$app/environment'

// API base URL for fallback
const API_BASE = import.meta.env.PUBLIC_API_URL || 'http://localhost:4002'

/**
 * Query keys for session history
 */
export const scrapeSessionsKeys = {
  all: ['scrapeSessions'] as const,
  list: (filters?: SessionFilters) => ['scrapeSessions', 'list', filters] as const,
  detail: (id: string) => ['scrapeSessions', 'detail', id] as const,
}

/**
 * Session filtering options
 */
export interface SessionFilters {
  status?: 'all' | 'active' | 'completed' | 'failed'
  database?: string
  agency?: 'hse' | 'environment_agency' | 'all'
  limit?: number
  offset?: number
}

/**
 * Fetch sessions from REST API (fallback when ElectricSQL unavailable)
 */
async function fetchSessionsFromApi(filters?: SessionFilters): Promise<ScrapeSession[]> {
  const params = new URLSearchParams()

  if (filters?.limit) {
    params.set('limit', filters.limit.toString())
  }

  // Note: API handles status differently than frontend filter
  // API expects exact status, frontend uses grouped statuses

  const url = `${API_BASE}/api/scraping/sessions?${params.toString()}`

  try {
    const response = await fetch(url)
    if (!response.ok) {
      throw new Error(`API error: ${response.status}`)
    }

    const result = await response.json()
    if (result.success && Array.isArray(result.data)) {
      return result.data as ScrapeSession[]
    }
    return []
  } catch (error) {
    console.error('[ScrapeSessions] API fallback failed:', error)
    return []
  }
}

/**
 * Apply client-side filters to sessions
 */
function applyFilters(sessions: ScrapeSession[], filters?: SessionFilters): ScrapeSession[] {
  let filtered = [...sessions]

  // Apply status filter
  if (filters?.status && filters.status !== 'all') {
    switch (filters.status) {
      case 'active':
        filtered = filtered.filter(
          (s) => s.status === 'pending' || s.status === 'running'
        )
        break
      case 'completed':
        filtered = filtered.filter((s) => s.status === 'completed')
        break
      case 'failed':
        filtered = filtered.filter(
          (s) => s.status === 'failed' || s.status === 'stopped'
        )
        break
    }
  }

  // Apply database filter
  if (filters?.database && filters.database !== 'all') {
    filtered = filtered.filter((s) => s.database === filters.database)
  }

  // Apply agency filter
  if (filters?.agency && filters.agency !== 'all') {
    filtered = filtered.filter((s) => s.agency === filters.agency)
  }

  // Sort by most recent first
  filtered.sort((a, b) => {
    return new Date(b.inserted_at).getTime() - new Date(a.inserted_at).getTime()
  })

  // Apply pagination
  if (filters?.offset !== undefined && filters?.limit !== undefined) {
    filtered = filtered.slice(filters.offset, filters.offset + filters.limit)
  } else if (filters?.limit !== undefined) {
    filtered = filtered.slice(0, filters.limit)
  }

  return filtered
}

/**
 * Fetch sessions from Svelte store, with API fallback
 */
async function fetchScrapeSessions(filters?: SessionFilters): Promise<ScrapeSession[]> {
  if (!browser) {
    return []
  }

  // Read from Svelte store (populated by ElectricSQL sync)
  let sessions = get(scrapeSessionsStore)

  // If store is empty, try fetching from API
  if (sessions.length === 0) {
    console.log('[ScrapeSessions] Store empty, fetching from API fallback')
    const apiSessions = await fetchSessionsFromApi({ limit: filters?.limit || 100 })

    if (apiSessions.length > 0) {
      // Populate the store with API data for future queries
      setScrapeSessions(apiSessions)
      sessions = apiSessions
    }
  }

  return applyFilters(sessions, filters)
}

export function useScrapeSessions(filters?: SessionFilters) {
  return createQuery({
    queryKey: scrapeSessionsKeys.list(filters),
    queryFn: () => fetchScrapeSessions(filters),
    enabled: browser,
    staleTime: 0,
    refetchInterval: 5000,
  })
}

/**
 * Query a single session by ID
 */
export function useScrapeSession(id: string) {
  return createQuery({
    queryKey: scrapeSessionsKeys.detail(id),
    queryFn: () => {
      if (!browser) {
        return null
      }

      const sessions = get(scrapeSessionsStore)
      const session = sessions.find((s) => s.id === id)
      return session || null
    },
    enabled: browser && !!id,
    staleTime: 0,
    refetchInterval: 2000, // Faster refetch for individual session details
  })
}

/**
 * Get session count for stats
 */
export function useSessionStats() {
  return createQuery({
    queryKey: [...scrapeSessionsKeys.all, 'stats'] as const,
    queryFn: () => {
      if (!browser) {
        return { total: 0, active: 0, completed: 0, failed: 0 }
      }

      const sessions = get(scrapeSessionsStore)

      return {
        total: sessions.length,
        active: sessions.filter((s) => s.status === 'pending' || s.status === 'running').length,
        completed: sessions.filter((s) => s.status === 'completed').length,
        failed: sessions.filter((s) => s.status === 'failed' || s.status === 'stopped').length,
      }
    },
    enabled: browser,
    staleTime: 5000,
    refetchInterval: 10000,
  })
}
