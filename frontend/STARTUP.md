# Week 4 POC Startup Guide

This guide walks through starting the complete local-first stack for the EHS Enforcement POC.

## Architecture Overview

```
PostgreSQL (with logical replication)
    ↓
ElectricSQL HTTP Shape API (port 3000)
    ↓
TanStack DB (IndexedDB in browser)
    ↓
Svelte UI (port 5173)
```

## Prerequisites

1. **Docker and Docker Compose** - for PostgreSQL and ElectricSQL services
2. **Node.js 20+** - for SvelteKit frontend
3. **PostgreSQL data** - Cases table with some test data

## Step 1: Start Backend Services

From the project root:

```bash
# Start PostgreSQL with logical replication + ElectricSQL
docker-compose -f docker-compose.dev.yml up -d postgres electric

# Verify services are running
docker-compose -f docker-compose.dev.yml ps
```

Expected output:
- `postgres` - running on port 5434
- `electric` - running on port 3000

### Verify ElectricSQL Health

```bash
curl http://localhost:3000/health
```

Should return: `OK` (200 status)

## Step 2: Ensure Database Has Data

Connect to PostgreSQL:

```bash
PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev
```

Check for cases:

```sql
-- Count cases
SELECT COUNT(*) FROM cases;

-- View sample cases
SELECT id, case_reference, regulator_id, offence_result, offence_action_type
FROM cases
LIMIT 5;
```

If no data exists, run the Phoenix app to populate:

```bash
# From project root
mix phx.server

# Visit http://localhost:4002 and trigger data collection
# OR run data seeding/scraping tasks
```

## Step 3: Install Frontend Dependencies

```bash
cd frontend

# Install dependencies (if not already done)
npm install
```

## Step 4: Configure Environment

```bash
# Copy example env file
cp .env.example .env

# Verify settings (should already be correct for local dev)
cat .env
```

Expected values:
```
PUBLIC_API_URL=http://localhost:4002
PUBLIC_ELECTRIC_URL=http://localhost:3000
PUBLIC_ENV=development
```

## Step 5: Start Frontend Dev Server

```bash
npm run dev
```

The server will start on http://localhost:5173

## Step 6: Verify POC is Working

1. **Visit Home Page**: http://localhost:5173
   - Should see architecture overview
   - Status indicators for PostgreSQL, Electric, TanStack DB
   - Navigation to Cases page

2. **Visit Cases Page**: http://localhost:5173/cases
   - Should see sync status banner (green = connected)
   - Loading state while initializing
   - List of cases ordered by action date (most recent first)
   - Each case showing:
     - Case reference and regulator ID
     - Result and action type
     - Fines and costs (if applicable)
     - Breaches
     - Agency and offender IDs

3. **Check Browser Console**:
   ```
   [TanStack DB] Database initialized successfully
   [Cases Page] Database initialized
   [Cases Page] Electric health: true
   [Electric Sync] Starting full sync...
   [Electric Sync] Received N case updates
   ```

4. **Test Real-time Sync**:
   ```bash
   # In another terminal, insert a test case
   PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev

   INSERT INTO cases (
     id, case_reference, regulator_id, offence_result,
     offence_action_date, agency_id, offender_id,
     inserted_at, updated_at
   ) VALUES (
     gen_random_uuid()::text,
     'TEST-2025-001',
     'TEST-REG-001',
     'Fine',
     '2025-01-15',
     (SELECT id FROM agencies LIMIT 1),
     (SELECT id FROM offenders LIMIT 1),
     NOW(),
     NOW()
   );
   ```

   The new case should appear in the UI within seconds without refresh!

## Troubleshooting

### Electric Health Check Fails

**Symptom**: Yellow "Offline Mode" banner on cases page

**Check**:
```bash
# Is Electric running?
docker-compose -f docker-compose.dev.yml ps electric

# Check Electric logs
docker-compose -f docker-compose.dev.yml logs electric
```

**Fix**:
```bash
# Restart Electric
docker-compose -f docker-compose.dev.yml restart electric

# Or rebuild if needed
docker-compose -f docker-compose.dev.yml up -d --force-recreate electric
```

### No Cases Displaying

**Symptom**: Empty state "No Cases Found" even after sync

**Check**:
1. Does database have cases?
   ```sql
   SELECT COUNT(*) FROM cases;
   ```

2. Is logical replication enabled?
   ```sql
   SHOW wal_level;  -- Should be 'logical'
   ```

3. Check Electric sync logs in browser console

**Fix**:
```bash
# Ensure PostgreSQL has correct replication settings
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml up -d postgres electric

# Verify wal_level
PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev -c "SHOW wal_level;"
```

### TanStack DB Initialization Error

**Symptom**: Console error about IndexedDB

**Fix**:
1. Clear browser IndexedDB:
   - Open DevTools → Application → Storage → IndexedDB
   - Delete `ehs_enforcement_db`
   - Refresh page

2. Check browser compatibility (requires IndexedDB support)

### Port Conflicts

**Symptom**: Services fail to start

**Fix**:
```bash
# Check what's using ports
lsof -i :3000  # ElectricSQL
lsof -i :5434  # PostgreSQL
lsof -i :5173  # Vite dev server

# Kill conflicting processes or change ports in configs
```

## Development Workflow

### Making Schema Changes

If you modify the Ash resource schema:

1. Update backend schema:
   ```bash
   cd .. # back to project root
   mix ash.codegen
   mix ash.migrate
   ```

2. Update frontend schema:
   ```bash
   cd frontend
   # Edit src/lib/db/schema.ts to match new fields
   ```

3. Restart both backend and frontend

### Clearing Local Data

```bash
# In browser console
await clearDB()

# Or delete IndexedDB in DevTools
```

### Viewing Sync Activity

```bash
# Watch Electric logs in real-time
docker-compose -f docker-compose.dev.yml logs -f electric

# Watch PostgreSQL queries
docker-compose -f docker-compose.dev.yml logs -f postgres
```

## Next Steps

Once POC is validated:
1. Test offline mode (stop Electric, verify cached data works)
2. Test sync reconnection (restart Electric, verify sync resumes)
3. Add write operations (mutations through TanStack DB)
4. Implement optimistic UI updates
5. Add conflict resolution
6. Extend to Agencies and Offenders pages

## Useful Commands

```bash
# Full stack restart
docker-compose -f docker-compose.dev.yml restart && cd frontend && npm run dev

# Check all services
curl http://localhost:3000/health  # Electric
curl http://localhost:4002          # Phoenix (if running)
curl http://localhost:5173          # Frontend

# Database console
PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev

# View all Electric shapes
curl http://localhost:3000/v1/shape/cases

# Frontend dev server with debugging
npm run dev -- --debug

# Build frontend for production
npm run build
npm run preview
```
