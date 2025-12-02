# HSE Notice Scraping: Records Not Persisting to Database

## Summary
HSE notice scraping logs show successful processing of notices, but records are not being persisted to the PostgreSQL database. The scrape session reports progress (e.g., "cases_found: 20, cases_created: 20") but database queries confirm 0 new notices, 0 new offenders, and 0 new review records.

## Evidence

### 1. Log Output Shows Processing
```
[info] HSE: Created/updated notice 315346737
[debug] Successfully processed notice: 315346737
[info] Medium confidence: 3 active companies found for Oyster Yachts Limited. Will create review record after offender is created. Candidates: ["11260018", "01121818", "11417804"]
[debug] Successfully processed notice: 315346766
```

### 2. Database Shows No Records
```sql
-- Check for specific notices from logs
SELECT COUNT(*) FROM notices WHERE regulator_id IN ('315346737', '315346766');
-- Result: 0 rows

-- Check for Oyster Yachts offender
SELECT id, name FROM offenders WHERE name ILIKE '%Oyster Yachts%';
-- Result: 0 rows

-- Check for review records
SELECT COUNT(*) FROM offender_match_reviews;
-- Result: 0 rows

-- Latest notice insertion was 2 days ago
SELECT MAX(inserted_at) FROM notices;
-- Result: 2025-11-08 20:46:34 (scrape running on 2025-11-10)
```

### 3. Scrape Session Shows Activity
```sql
SELECT session_id, agency, status, pages_processed, cases_found, cases_created, errors_count
FROM scrape_sessions WHERE agency = 'hse' ORDER BY inserted_at DESC LIMIT 1;

-- Result:
session_id    | agency | status    | pages_processed | cases_found | cases_created | errors_count
ccc5fef12efdb1ed | hse   | completed | 2              | 20          | 20           | 0
```

## Impact

### **Critical Issues**
1. **Data Loss**: Scraped HSE notice data is not being saved despite successful processing
2. **Misleading Logs**: Progress tracking shows records as "created" when they're not persisted
3. **Inconsistent State**: `ScrapeSession` records show `cases_created: 20` but database has 0 notices
4. **Cascade Effect**: No offenders created → no review records created → Companies House integration not testable

### **Affected Features**
- HSE notice scraping (database: "notices")
- Offender creation for HSE notices
- Companies House matching workflow (medium-confidence reviews)
- Admin UI progress tracking (shows fake progress)

## Possible Root Causes

### 1. Transaction Rollback
- All operations processed in a transaction that's being rolled back
- Error occurring after processing but before commit
- Database connection issue causing silent rollback

### 2. Ash Resource Action Issues
- Incorrect Ash action being called (e.g., `:read` instead of `:create`)
- Missing `actor` parameter causing authorization failure
- Action returning `{:ok, _}` without actually persisting

### 3. Test Environment Conflict
- Code might be using test database instead of dev database
- Mock/stub left enabled in dev environment
- Database connection pool issue

### 4. Notice vs Case Confusion
- Session tracking reports "cases_created" for notice scraping
- Possible code path that updates session but not actual records
- Mismatch between log messages and actual database operations

## Investigation Steps

1. **Add Transaction Logging**
   - Log before and after Ash.create calls
   - Log transaction boundaries (start, commit, rollback)
   - Check for errors being swallowed

2. **Verify Ash Actions**
   - Check `EhsEnforcement.Enforcement.create_notice` implementation
   - Verify correct action name (`:create` vs custom actions)
   - Ensure `actor` parameter being passed

3. **Database Connection**
   - Verify `EhsEnforcement.Repo` configuration for dev environment
   - Check if correct database being used (sertantai_enforcement_dev vs test)
   - Test manual Ash.create from IEx

4. **Code Path Analysis**
   - Trace from notice processor through to database
   - Check for conditional logic that might skip persistence
   - Verify `after_action` callbacks in Notice resource

## Reproduction

1. Start Phoenix server: `mix phx.server`
2. Navigate to `/admin/scrape`
3. Select: Agency=HSE, Database=Notices, Pages=2
4. Click "Start Scraping"
5. Observe: Logs show "Successfully processed notice: X"
6. Check database:
   ```sql
   SELECT COUNT(*) FROM notices WHERE inserted_at > NOW() - INTERVAL '5 minutes';
   -- Expected: 20, Actual: 0
   ```

## Related Code Locations

- **Notice Processor**: `lib/ehs_enforcement/scraping/hse/notice_processor.ex`
- **Notice Resource**: `lib/ehs_enforcement/enforcement/resources/notice.ex`
- **HSE Agency Behavior**: `lib/ehs_enforcement/scraping/agencies/hse.ex`
- **Offender Builder**: `lib/ehs_enforcement/agencies/hse/offender_builder.ex`
- **Scrape Session**: `lib/ehs_enforcement/scraping/resources/scrape_session.ex`

## Environment

- **Elixir**: 1.18.4
- **Phoenix**: 1.7+
- **Ash**: 3.0+
- **Database**: PostgreSQL (sertantai_enforcement_dev)
- **Port**: 4002

## Expected Behavior

After successful scraping:
- Notices table should have new rows with `regulator_id` matching log output
- Offenders table should have new rows for each unique offender
- `offender_match_reviews` table should have records for medium-confidence matches
- Latest `inserted_at` timestamp should match current time

## Actual Behavior

After successful scraping:
- All database tables remain unchanged
- `ScrapeSession` shows progress but no actual data persisted
- Logs indicate success but database queries show no records
- Latest `inserted_at` timestamps are days old
