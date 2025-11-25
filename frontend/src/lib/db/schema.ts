/**
 * Database Type Definitions
 *
 * TypeScript types mirroring Ash resources from EhsEnforcement.Enforcement
 * These types are used by TanStack DB collections for type safety.
 */

/**
 * Case Type
 * Mirrors: EhsEnforcement.Enforcement.Case
 */
export interface Case {
  // Primary key
  id: string

  // Core case identification
  case_reference: string | null
  regulator_id: string | null

  // Offense details
  offence_result: string | null
  offence_fine: number | null
  offence_costs: number | null
  offence_action_date: string | null // ISO date string
  offence_hearing_date: string | null // ISO date string
  offence_action_type: string | null
  offence_breaches: string | null

  // Regulator information
  regulator_function: string | null
  regulator_url: string | null

  // EA-specific fields
  ea_event_reference: string | null
  ea_total_violation_count: number | null
  environmental_impact: string | null
  environmental_receptor: string | null
  is_ea_multi_violation: boolean | null

  // Relationships (foreign keys)
  agency_id: string
  offender_id: string

  // Metadata
  url: string | null
  related_cases: string | null
  last_synced_at: string | null // ISO datetime string

  // Timestamps
  inserted_at: string // ISO datetime string
  updated_at: string // ISO datetime string
}

/**
 * Agency Type
 * Mirrors: EhsEnforcement.Enforcement.Agency
 */
export interface Agency {
  id: string
  code: string // atom in Ash: :hse, :onr, :orr, :ea
  name: string
  base_url: string | null
  enabled: boolean
  inserted_at: string
  updated_at: string
}

/**
 * Offender Type
 * Mirrors: EhsEnforcement.Enforcement.Offender
 */
export interface Offender {
  // Primary key
  id: string

  // Core identification
  name: string
  normalized_name: string | null
  address: string | null
  local_authority: string | null
  country: string | null
  postcode: string | null
  town: string | null
  county: string | null

  // Business details
  business_type: 'limited_company' | 'individual' | 'partnership' | 'plc' | 'other' | null
  company_registration_number: string | null
  main_activity: string | null
  sic_code: string | null
  industry: string | null
  industry_sectors: string[] | null

  // Enforcement history
  agencies: string[] | null
  first_seen_date: string | null // ISO date string
  last_seen_date: string | null // ISO date string
  total_cases: number
  total_notices: number
  total_fines: number

  // Timestamps
  inserted_at: string // ISO datetime string
  updated_at: string // ISO datetime string
}

/**
 * Notice Type
 * Mirrors: EhsEnforcement.Enforcement.Notice
 */
export interface Notice {
  // Primary key
  id: string

  // Core notice identification
  airtable_id: string | null
  regulator_id: string | null
  regulator_ref_number: string | null

  // Notice dates
  notice_date: string | null // ISO date string
  operative_date: string | null // ISO date string
  compliance_date: string | null // ISO date string

  // Notice details
  notice_body: string | null
  offence_action_type: string | null
  offence_action_date: string | null // ISO date string
  offence_breaches: string | null
  url: string | null

  // EA-specific fields
  regulator_event_reference: string | null
  environmental_impact: string | null
  environmental_receptor: string | null
  legal_act: string | null
  legal_section: string | null
  regulator_function: string | null

  // Relationships (foreign keys)
  agency_id: string
  offender_id: string

  // Metadata
  last_synced_at: string | null // ISO datetime string

  // Timestamps
  inserted_at: string // ISO datetime string
  updated_at: string // ISO datetime string
}

/**
 * ScrapeSession Type
 * Mirrors: EhsEnforcement.Scraping.ScrapeSession
 */
export interface ScrapeSession {
  // Primary key
  id: string
  session_id: string

  // Agency and database config
  agency: 'hse' | 'environment_agency'
  database: string

  // HSE-specific parameters
  start_page: number
  max_pages: number
  end_page: number | null

  // EA-specific parameters
  date_from: string | null // ISO date string
  date_to: string | null // ISO date string
  action_types: string[] | null

  // Status tracking
  status: 'pending' | 'running' | 'completed' | 'failed' | 'stopped'

  // Progress metrics
  current_page: number | null
  pages_processed: number
  cases_found: number
  cases_processed: number
  cases_created: number
  cases_created_current_page: number
  cases_updated: number
  cases_updated_current_page: number
  cases_exist_total: number
  cases_exist_current_page: number
  errors_count: number

  // Timestamps
  inserted_at: string // ISO datetime string
  updated_at: string // ISO datetime string
}

/**
 * Legislation Type
 * Mirrors: EhsEnforcement.Enforcement.Legislation
 */
export interface Legislation {
  // Primary key
  id: string

  // Core legislation details
  legislation_title: string
  legislation_year: number | null
  legislation_number: number | null
  legislation_type: 'act' | 'regulation' | 'order' | 'acop'

  // Denormalized aggregates (from offences → cases/notices)
  total_offences: number
  total_cases: number
  total_notices: number
  first_used_date: string | null // ISO date string
  last_used_date: string | null // ISO date string

  // Timestamps
  created_at: string // ISO datetime string
  updated_at: string // ISO datetime string
}

/**
 * SavedView Type
 * User-saved table configurations for quick reuse
 * Local-only storage (not synced to backend)
 */
export interface SavedView {
  // Identity
  id: string
  name: string
  description?: string

  // Complete table configuration
  config: {
    filters: Array<{
      columnId: string
      operator: string
      value: any
    }>
    sort: {
      columnId: string
      direction: 'asc' | 'desc'
    } | null
    columns: string[]
    columnOrder: string[]
    columnWidths: Record<string, number>
    pageSize: number
    grouping?: string[]
  }

  // Optional: Original NL query
  originalQuery?: string

  // Metadata
  createdAt: number
  updatedAt: number
  usageCount: number
  lastUsed: number
}
