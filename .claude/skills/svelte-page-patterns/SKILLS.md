---
name: svelte-page-patterns
description: Establishes correct patterns for SvelteKit pages in this Phoenix/ElectricSQL application including SSR-safe reactive queries, filter state, and data synchronization. Use when creating new SvelteKit pages, fixing SSR race conditions, or implementing data-driven pages with ElectricSQL.
---

# SvelteKit Page Patterns for Phoenix + ElectricSQL

Correct patterns for building SvelteKit pages in this application's architecture:
- **Backend**: Phoenix (port 4002) with PostgreSQL
- **Frontend**: SvelteKit (port 5173) with ElectricSQL real-time sync
- **Data Flow**: PostgreSQL → ElectricSQL ShapeStream → Svelte Store → TanStack Query → UI

## ⚠️ CRITICAL: Understanding Sync Strategies

**Two fundamentally different sync strategies exist in this codebase:**

### Strategy 1: Phoenix API (No ElectricSQL)
**Example**: `/data` page
**Pattern**: Direct API calls to Phoenix backend
**When to use**: Large datasets, complex queries, server-side filtering

### Strategy 2: ElectricSQL Sync (Specific Table Sync)
**Examples**: `/cases`, `/admin/scrape-sessions`
**Pattern**: Call specific sync function for ONE table only
**When to use**: Small-to-medium tables that need real-time updates

## ❌ ANTI-PATTERN: Never Use `startSync()`

**The `startSync()` function syncs ALL tables simultaneously:**
- `syncCases()`
- `syncAgencies()`
- `syncOffenders()`
- `syncScrapeSessions()`

**This creates a race condition causing browser lockup!**

```svelte
<!-- ❌ WRONG - DO NOT DO THIS -->
<script lang="ts">
  import { startSync } from '$lib/electric/sync'

  onMount(async () => {
    await startSync()  // ❌ Syncs ALL tables - causes race condition!
  })
</script>
```

**Why it fails:**
- Multiple ElectricSQL ShapeStreams compete for resources
- Browser locks up
- Back button navigation fails
- Controls become unresponsive

## ✅ CORRECT Pattern 1: Phoenix API (No Sync)

**Reference**: `/data/+page.svelte` (lines 188-195)

**Use when:** Fetching large datasets from Phoenix REST/GraphQL endpoints

```svelte
<script lang="ts">
  import { browser } from '$app/environment'
  import { useUnifiedData } from '$lib/query/unified'

  // Filter state (regular variables)
  let recordType: 'all' | 'case' | 'notice' = 'all'
  let dateFrom = ''
  let dateTo = ''

  // Reactive filters object (recreates when dependencies change)
  $: filters = {
    record_type: recordType,
    date_from: dateFrom || undefined,
    date_to: dateTo || undefined,
    limit: 100,
  }

  // Reactive query - created immediately when browser is true
  $: dataQuery = browser ? useUnifiedData(filters) : null
</script>

{#if !browser || $dataQuery?.isLoading}
  <p>Loading...</p>
{:else if $dataQuery?.isError}
  <p>Error: {$dataQuery.error?.message}</p>
{:else if $dataQuery?.data}
  <!-- Render data -->
  {#each $dataQuery.data.data as record}
    <div>{record.id}</div>
  {/each}
{/if}
```

**Key Points:**
- **Reactive query**: `$: dataQuery = browser ? useQuery(filters) : null`
- **Reactive filters**: `$: filters = {...}` recreates when filter vars change
- **No `onMount`**: Query created immediately when `browser` is true
- **No sync calls**: Data fetched directly from Phoenix API
- **TanStack Query reactivity**: New query created when `queryKey` changes

## ✅ CORRECT Pattern 2: ElectricSQL Specific Sync

**Reference**: `/cases/+page.svelte` (lines 20, 57-85)

**Use when:** Syncing specific table for real-time updates

```svelte
<script lang="ts">
  import { onMount } from 'svelte'
  import { browser } from '$app/environment'
  import { useScrapeSessions } from '$lib/query/scrapeSessions'
  import { syncScrapeSessions, checkElectricHealth } from '$lib/electric/sync'

  // Filter state (regular variables)
  let filterStatus: 'all' | 'active' | 'completed' | 'failed' = 'all'
  let filterDatabase = 'all'

  // Reactive filters object (recreates when dependencies change)
  $: filters = {
    status: filterStatus,
    database: filterDatabase === 'all' ? undefined : filterDatabase,
    limit: 100,
  }

  // Module-level const query (NOT reactive $:)
  // TanStack Query handles reactivity via queryKey changes
  const sessionsQuery = browser ? useScrapeSessions(filters) : null

  // Loading/error state for sync initialization
  let loading = true
  let error: string | null = null
  let electricHealthy = false

  // Initialize SPECIFIC sync on mount
  onMount(async () => {
    try {
      electricHealthy = await checkElectricHealth()

      if (electricHealthy) {
        await syncScrapeSessions()  // ✅ Sync ONLY sessions table
      }

      loading = false
    } catch (err) {
      error = err instanceof Error ? err.message : 'Unknown error'
      loading = false
    }
  })
</script>

{#if loading}
  <div class="flex items-center">
    <svg class="animate-spin...">...</svg>
    Initializing sync...
  </div>
{:else if error}
  <div class="text-red-600">Error: {error}</div>
{:else if !browser || $sessionsQuery?.isLoading}
  <p>Loading data...</p>
{:else if $sessionsQuery?.isError}
  <p>Error: {$sessionsQuery.error?.message}</p>
{:else if $sessionsQuery?.data}
  <!-- Render data -->
  {#each $sessionsQuery.data as session}
    <div>{session.id}</div>
  {/each}
{/if}
```

**Key Points:**
- **Module-level const**: `const query = browser ? useQuery(filters) : null`
- **Specific sync function**: Call `syncScrapeSessions()` NOT `startSync()`
- **Loading state**: Track sync initialization separately from query loading
- **Error handling**: Catch sync initialization errors
- **TanStack Query reactivity**: `queryKey` changes trigger new queries automatically

## 🔑 Key Insight: TanStack Query Reactivity

**TanStack Query automatically creates new query instances when `queryKey` changes.**

The reactive `$: filters = {...}` object causes `queryKey: ['sessions', 'list', filters]` to change, triggering a new query.

**This means the query itself can be a `const`!**

```typescript
// lib/query/scrapeSessions.ts
export function useScrapeSessions(filters?: SessionFilters) {
  return createQuery({
    queryKey: ['sessions', 'list', filters],  // ← Key includes filters
    queryFn: () => fetchSessions(filters),
    enabled: browser,
    staleTime: 0,
    refetchInterval: 5000,  // Continuously updates
  })
}
```

When `filters` changes:
1. Svelte reactive statement recreates `filters` object
2. TanStack Query sees new `queryKey` value
3. New query instance created automatically
4. UI updates with new results

**No need for reactive `$: query` declaration!**

## Available Sync Functions

**Each table has its own specific sync function:**

```typescript
// lib/electric/sync.ts exports:
export async function syncCases(organizationId?: string)      // Cases table
export async function syncAgencies()                          // Agencies table
export async function syncOffenders()                         // Offenders table
export async function syncScrapeSessions()                    // Scrape sessions table

// ❌ NEVER USE THIS IN PAGES:
export async function startSync(organizationId?: string)      // Syncs ALL tables - causes race!
```

**Always use the specific sync function for your table!**

## Filter Controls Pattern

```svelte
<script lang="ts">
  // Filter state (regular let variables)
  let filterStatus: 'all' | 'active' | 'completed' | 'failed' = 'all'
  let filterDatabase = 'all'

  // Reactive filters object
  $: filters = {
    status: filterStatus,
    database: filterDatabase === 'all' ? undefined : filterDatabase,
    limit: 100,
  }

  // For Pattern 1 (Phoenix API): Reactive query
  $: dataQuery = browser ? useYourData(filters) : null

  // For Pattern 2 (ElectricSQL): Module-level const
  const dataQuery = browser ? useYourData(filters) : null

  function handleClearFilters() {
    filterStatus = 'all'
    filterDatabase = 'all'
  }
</script>

<!-- Status Filter -->
<select bind:value={filterStatus}>
  <option value="all">All Statuses</option>
  <option value="active">Active</option>
  <option value="completed">Completed</option>
  <option value="failed">Failed</option>
</select>

<!-- Type Filter -->
<select bind:value={filterDatabase}>
  <option value="all">All Types</option>
  <option value="cases">Cases</option>
  <option value="notices">Notices</option>
</select>

<!-- Clear Filters -->
<button on:click={handleClearFilters}>Clear Filters</button>
```

## Data Flow Diagrams

### Pattern 1: Phoenix API
```
PostgreSQL → Phoenix REST API → TanStack Query → UI
                 ↓
            (fetch on demand)
```

### Pattern 2: ElectricSQL Sync
```
PostgreSQL → ElectricSQL ShapeStream → Svelte Store
                                            ↓
              TanStack Query (refetchInterval: 5000)
                                            ↓
                                         Svelte UI
```

## Reference Pages

**Working examples in this codebase:**

| Page | Pattern | Sync Function | Query Type |
|------|---------|---------------|------------|
| `/data` | Phoenix API | None | Reactive `$:` |
| `/cases` | ElectricSQL | `startCasesSync()` | Module-level `const` |
| `/admin/scrape-sessions` | ElectricSQL | `syncScrapeSessions()` | Module-level `const` |

**Key Files:**
- `/frontend/src/routes/data/+page.svelte` (lines 188-195) - Phoenix API pattern
- `/frontend/src/routes/cases/+page.svelte` (lines 20, 57-85) - ElectricSQL pattern
- `/frontend/src/lib/electric/sync.ts` - All sync functions
- `/frontend/src/lib/query/unified.ts` - Phoenix API query example
- `/frontend/src/lib/query/scrapeSessions.ts` - ElectricSQL query example

## Troubleshooting

### Browser lockup / race condition

**Symptom**: Browser freezes, back button doesn't work, controls unresponsive

**Cause**: Calling `startSync()` which syncs ALL tables simultaneously

**Fix**: Change to specific sync function:
```diff
- import { startSync } from '$lib/electric/sync'
+ import { syncScrapeSessions, checkElectricHealth } from '$lib/electric/sync'

  onMount(async () => {
    try {
      const electricHealthy = await checkElectricHealth()
      if (electricHealthy) {
-       await startSync()
+       await syncScrapeSessions()
      }
    }
  })
```

### Filters not working

**Symptom**: Changing filter dropdowns doesn't update the table

**Cause**: Static filter object or non-reactive query

**Fix**: Use reactive statements:
```diff
- const filters = { status: filterStatus }  // ❌ Static
+ $: filters = { status: filterStatus }     // ✅ Reactive
```

### No data appearing

**Symptom**: Table shows "Loading..." forever or displays empty

**Phoenix API Pattern**:
- Check browser console for API errors
- Verify API endpoint is running (http://localhost:4002)
- Check network tab for failed requests

**ElectricSQL Pattern**:
- Verify Electric health check passes
- Check specific sync function is called (not `startSync()`)
- Confirm query has `refetchInterval: 5000`
- Look for sync logs in browser console

### SSR errors / "browser is not defined"

**Symptom**: Errors during server-side rendering

**Cause**: Code executing before `browser` is available

**Fix**: Guard all browser-dependent code:
```svelte
<!-- ✅ Correct -->
{#if browser}
  <ComponentThatUsesDOM />
{/if}

<!-- ✅ Correct -->
$: query = browser ? useQuery() : null

<!-- ❌ Wrong -->
const query = useQuery()  // Runs during SSR!
```

## Common Mistakes

### 1. Using `startSync()` in pages
```svelte
<!-- ❌ WRONG -->
onMount(async () => {
  await startSync()  // Syncs ALL tables - race condition!
})
```

### 2. Reactive query with ElectricSQL sync
```svelte
<!-- ❌ WRONG - Pattern 2 should use const -->
$: sessionsQuery = browser && syncInitialized ? useScrapeSessions(filters) : null
```

### 3. Static filter object
```svelte
<!-- ❌ WRONG - Filters won't update -->
const filters = { status: filterStatus }
```

### 4. Module-level console.log
```svelte
<!-- ❌ WRONG - Executes during SSR -->
<script lang="ts">
  console.log('Page loaded')  // Runs on server!
</script>

<!-- ✅ CORRECT - Guard with browser check -->
<script lang="ts">
  $: if (browser) {
    console.log('Page loaded in browser')
  }
</script>
```

## Choosing the Right Pattern

**Use Pattern 1 (Phoenix API) when:**
- Dataset is large (thousands of records)
- Server-side filtering/sorting needed
- Complex queries with joins
- Don't need real-time updates

**Use Pattern 2 (ElectricSQL Sync) when:**
- Small-to-medium dataset (hundreds of records)
- Need real-time updates
- Simple queries on single table
- Want offline-first capability

**When in doubt, start with Pattern 1 (Phoenix API)** - it's simpler and avoids sync complexity.
