/**
 * Saved View Types for Table Configuration Persistence
 *
 * Enables users to save table configurations (filters, sort, columns, etc.)
 * as named "views" for quick reuse.
 */

export interface FilterCondition {
	columnId: string
	operator: string
	value: any
}

export interface SortConfig {
	columnId: string
	direction: 'asc' | 'desc'
}

export interface TableConfig {
	filters: FilterCondition[]
	sort: SortConfig | null
	columns: string[]
	columnOrder: string[]
	columnWidths: Record<string, number>
	pageSize: number
	grouping?: string[]
}

export interface SavedView {
	// Identity
	id: string
	name: string
	description?: string

	// Complete table configuration (single source of truth)
	config: TableConfig

	// Optional: Keep original NL query for reference/rerun
	originalQuery?: string

	// Metadata
	createdAt: number
	updatedAt: number
	usageCount: number
	lastUsed: number
}

export type SavedViewInput = Omit<SavedView, 'id' | 'createdAt' | 'updatedAt' | 'usageCount' | 'lastUsed'>
