/**
 * Types for HSE Notice scraping workflow
 */

export type ScrapingPhase =
  | 'idle'
  | 'scraping_pages'
  | 'filtering'
  | 'processing_records'
  | 'saving'
  | 'completed'
  | 'failed'

export type ScrapingStatus = 'pending' | 'running' | 'completed' | 'failed' | 'stopped'

/**
 * SSE Event types from backend
 */
export interface ProgressEvent {
  phase: ScrapingPhase
  current_page?: number
  pages_scraped?: number
  total_pages?: number
  records_found?: number
  records_to_process?: number
  records_existing?: number
  records_processed?: number
  records_enriched?: number
  records_created?: number
  records_updated?: number
}

export interface RecordProcessedEvent {
  regulator_id: string
  offender_name?: string
  notice_type?: string
}

export interface ErrorEvent {
  page?: number
  message: string
  regulator_id?: string
  timestamp?: string
}

export interface CompletedEvent {
  records_found: number
  records_existing: number
  records_created: number
  records_updated: number
}

/**
 * SSE Event wrapper
 */
export type SSEEvent =
  | { type: 'progress'; data: ProgressEvent }
  | { type: 'record_processed'; data: RecordProcessedEvent }
  | { type: 'error'; data: ErrorEvent }
  | { type: 'completed'; data: CompletedEvent }
  | { type: 'stopped'; data: Record<string, never> }

/**
 * Supported agencies
 */
export type Agency = 'hse' | 'ea' | 'sepa' | 'nrw'

/**
 * Scraping session (from API and ElectricSQL)
 */
export interface ScrapingSession {
  id: string
  session_id: string
  agency: Agency
  database: string
  start_page: number
  max_pages: number
  status: ScrapingStatus
  current_page: number | null
  pages_processed: number
  cases_found: number
  cases_processed: number
  cases_created: number
  cases_updated: number
  cases_exist_total: number
  errors_count: number
  inserted_at: string
  updated_at: string
}

/**
 * API request for starting scraping - HSE
 */
export interface HseScrapingRequest {
  agency: 'hse'
  database: 'notices' | 'convictions' | 'appeals'
  start_page: number
  max_pages: number
  country?: string
}

/**
 * API request for starting scraping - EA
 */
export interface EaScrapingRequest {
  agency: 'ea'
  database: 'notices' | 'convictions' | 'appeals'
  from_date: string
  to_date: string
}

/**
 * API request for starting scraping - SEPA
 */
export interface SepaScrapingRequest {
  agency: 'sepa'
  database: 'penalties'
  section?: 'all' | 'penalties' | 'undertakings' | 'costs_recovery'
}

/**
 * API request for starting scraping - NRW
 */
export interface NrwScrapingRequest {
  agency: 'nrw'
  database: 'cases'
  limit?: number
}

/**
 * Union type for all scraping requests
 */
export type StartScrapingRequest = HseScrapingRequest | EaScrapingRequest | SepaScrapingRequest | NrwScrapingRequest

/**
 * API response from start scraping
 */
export interface StartScrapingResponse {
  success: boolean
  data: {
    session_id: string
    sse_url: string
    session: ScrapingSession
  }
}

/**
 * UI state for progress tracking (transient, not persisted)
 */
export interface ScrapingProgress {
  phase: ScrapingPhase
  currentPage: number
  pagesScraped: number
  totalPages: number
  recordsFound: number
  recordsToProcess: number
  recordsExisting: number
  recordsProcessed: number
  recordsEnriched: number
  recordsCreated: number
  recordsUpdated: number
  errorsCount: number
  recentRecords: RecordProcessedEvent[]
  recentErrors: ErrorEvent[]
}

/**
 * Form data for scraping UI
 */
export interface ScrapingFormData {
  agency: Agency
  database: 'notices' | 'convictions' | 'appeals' | 'penalties' | 'cases'
  startPage: number | string
  maxPages: number | string
  country: string
  section: 'all' | 'penalties' | 'undertakings' | 'costs_recovery'
  limit: number
}
