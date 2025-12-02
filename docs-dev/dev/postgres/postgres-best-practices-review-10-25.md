# PostgreSQL Best Practices Review - EHS Enforcement Schema

**Review Date**: 2025-10-24
**PostgreSQL Version**: 14+ (Current production version)
**Database**: `sertantai_enforcement_dev`

## Executive Summary

This review evaluates the EHS Enforcement database schema against modern PostgreSQL best practices, focusing on performance, data integrity, maintainability, and scalability.

**Overall Assessment**: ✅ **GOOD** - Schema demonstrates solid understanding of PostgreSQL features with room for optimization

**Key Strengths**:
- Excellent use of UUIDs for distributed systems
- Proper indexing strategy with B-tree and GIN indexes
- Good use of pg_trgm for fuzzy text search
- Appropriate use of JSONB for flexible data
- Proper foreign key constraints

**Areas for Improvement**:
- Some missing indexes on foreign keys
- Opportunity for partial indexes on large tables
- Table partitioning for time-series data
- Statistics and vacuuming configuration
- Query performance monitoring

---

## 1. Data Types & Column Design

### ✅ Strengths

**UUID Primary Keys**:
```sql
id uuid PRIMARY KEY DEFAULT gen_random_uuid()
```
- Excellent choice for distributed systems
- Prevents enumeration attacks
- Good for replication and sharding

**Appropriate Use of NUMERIC for Money**:
```sql
offence_fine DECIMAL
offence_costs DECIMAL
```
- Correct choice over FLOAT for financial data
- Ensures precision in calculations

**JSONB for Flexible Data**:
```sql
agency_stats JSONB NOT NULL DEFAULT '{}'
offender_breakdown JSONB NOT NULL DEFAULT '{}'
```
- Good use of JSONB for semi-structured data
- Allows for flexible querying with GIN indexes

**citext for Case-Insensitive Email**:
```sql
email CITEXT NOT NULL UNIQUE
```
- Proper use of extension for case-insensitive comparisons
- Better than LOWER() in application code

### ⚠️ Recommendations

**R1.1**: Consider using `timestamptz` instead of `timestamp` for all datetime fields
```sql
-- Current
inserted_at TIMESTAMP WITHOUT TIME ZONE

-- Recommended
inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
```
**Benefit**: Properly handles timezone conversions, essential for international data

**R1.2**: Add explicit precision to DECIMAL fields
```sql
-- Current
offence_fine DECIMAL

-- Recommended
offence_fine NUMERIC(12,2)  -- Up to 9,999,999,999.99
```
**Benefit**: Prevents unexpected precision issues and documents expected range

**R1.3**: Consider ENUM types for frequently-used status fields
```sql
-- Instead of TEXT with check constraints
CREATE TYPE case_status AS ENUM ('pending', 'running', 'completed', 'failed', 'stopped');

-- Then use in table
status case_status NOT NULL DEFAULT 'pending'
```
**Benefit**: Better performance, type safety, and self-documenting schema

---

## 2. Indexing Strategy

### ✅ Strengths

**Composite Indexes for Common Query Patterns**:
```sql
CREATE INDEX cases_agency_date_index
ON cases (agency_id, offence_action_date);
```
- Good identification of multi-column query patterns
- Proper column ordering (equality first, range second)

**GIN Indexes for Full-Text Search**:
```sql
CREATE INDEX notices_notice_body_gin_trgm
ON notices USING GIN (notice_body gin_trgm_ops);
```
- Excellent use of pg_trgm for fuzzy search
- Appropriate index type for text search

**Partial Indexes for Conditional Uniqueness**:
```sql
CREATE UNIQUE INDEX cases_unique_case_reference_index
ON cases (case_reference)
WHERE (case_reference IS NOT NULL);
```
- Good use of partial indexes to exclude NULLs
- Reduces index size and improves performance

### ⚠️ Recommendations

**R2.1**: Add missing foreign key indexes
```sql
-- Currently missing explicit indexes on some FK columns
CREATE INDEX metrics_agency_id_idx ON metrics (agency_id);
CREATE INDEX metrics_offender_id_idx ON metrics (offender_id);
CREATE INDEX metrics_legislation_id_idx ON metrics (legislation_id);
```
**Benefit**: Dramatically improves JOIN performance and FK constraint checking

**R2.2**: Consider partial indexes for active records
```sql
-- For frequently queried active sessions
CREATE INDEX scrape_sessions_active_idx
ON scrape_sessions (agency, status, updated_at)
WHERE status IN ('pending', 'running');
```
**Benefit**: Smaller, faster indexes for common queries

**R2.3**: Add covering indexes for dashboard queries
```sql
-- Include frequently selected columns in index
CREATE INDEX cases_dashboard_covering_idx
ON cases (agency_id, offence_action_date)
INCLUDE (offence_fine, offence_costs, offender_id);
```
**Benefit**: Index-only scans eliminate table lookups

**R2.4**: Consider BRIN indexes for time-series data
```sql
-- For tables with timestamp-ordered inserts
CREATE INDEX events_occurred_at_brin_idx
ON events USING BRIN (occurred_at);
```
**Benefit**: Tiny index size (100-1000x smaller) for time-series data

---

## 3. Table Design & Normalization

### ✅ Strengths

**Proper Normalization**:
- Excellent normalization with `legislation` and `offences` tables
- Good separation of concerns (agencies, offenders, cases, notices)
- Proper many-to-many relationships

**Denormalization Where Appropriate**:
- `computed_breaches_summary` calculated fields for backward compatibility
- Statistics fields on `offenders` table (total_cases, total_fines)
- Good balance between normalization and query performance

### ⚠️ Recommendations

**R3.1**: Consider table partitioning for large tables
```sql
-- For cases table (by offence_action_date)
CREATE TABLE cases (
  -- existing columns
) PARTITION BY RANGE (offence_action_date);

CREATE TABLE cases_2020 PARTITION OF cases
  FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');

CREATE TABLE cases_2021 PARTITION OF cases
  FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
-- etc.
```
**Benefit**: Better query performance, easier archiving, improved maintenance

**R3.2**: Add `deleted_at` for soft deletes instead of hard deletes
```sql
ALTER TABLE cases ADD COLUMN deleted_at TIMESTAMPTZ;
CREATE INDEX cases_not_deleted_idx ON cases (id) WHERE deleted_at IS NULL;
```
**Benefit**: Enables audit trails and data recovery

**R3.3**: Consider materialized views for complex dashboard queries
```sql
CREATE MATERIALIZED VIEW dashboard_summary AS
SELECT
  agency_id,
  DATE_TRUNC('month', offence_action_date) as month,
  COUNT(*) as case_count,
  SUM(offence_fine) as total_fines
FROM cases
GROUP BY agency_id, DATE_TRUNC('month', offence_action_date);

CREATE UNIQUE INDEX ON dashboard_summary (agency_id, month);
```
**Benefit**: Pre-computed results for expensive aggregations

---

## 4. Constraints & Data Integrity

### ✅ Strengths

**Proper Foreign Key Constraints**:
```sql
FOREIGN KEY (agency_id) REFERENCES agencies(id)
FOREIGN KEY (offender_id) REFERENCES offenders(id)
```
- Good referential integrity enforcement
- Proper CASCADE and RESTRICT policies

**Composite Unique Constraints**:
```sql
UNIQUE (agency_id, regulator_id)
```
- Excellent cross-agency uniqueness enforcement

**NULLS NOT DISTINCT for Proper NULL Handling**:
```sql
CREATE UNIQUE INDEX legislation_unique_legislation_index
ON legislation (legislation_title, legislation_year, legislation_number)
NULLS NOT DISTINCT;
```
- Modern PostgreSQL 15+ feature for proper NULL handling
- Correct unique constraint behavior

### ⚠️ Recommendations

**R4.1**: Add CHECK constraints for data validation
```sql
-- Ensure non-negative financial values
ALTER TABLE cases
ADD CONSTRAINT cases_fine_non_negative
CHECK (offence_fine IS NULL OR offence_fine >= 0);

ALTER TABLE cases
ADD CONSTRAINT cases_costs_non_negative
CHECK (offence_costs IS NULL OR offence_costs >= 0);

-- Ensure logical date ordering
ALTER TABLE notices
ADD CONSTRAINT notices_dates_logical
CHECK (compliance_date IS NULL OR notice_date IS NULL OR compliance_date >= notice_date);
```
**Benefit**: Database-level validation prevents invalid data

**R4.2**: Add NOT NULL constraints where appropriate
```sql
-- Fields that should never be NULL
ALTER TABLE cases ALTER COLUMN offence_action_type SET NOT NULL;
ALTER TABLE notices ALTER COLUMN offence_action_type SET NOT NULL;
```
**Benefit**: Stronger data integrity and clearer schema semantics

**R4.3**: Consider exclusion constraints for overlapping data
```sql
-- If needed to prevent overlapping date ranges
CREATE EXTENSION btree_gist;

ALTER TABLE scrape_sessions
ADD CONSTRAINT scrape_sessions_no_overlap
EXCLUDE USING GIST (
  agency WITH =,
  tstzrange(inserted_at, COALESCE(updated_at, 'infinity'::timestamptz)) WITH &&
)
WHERE (status IN ('pending', 'running'));
```
**Benefit**: Prevents concurrent scraping sessions for same agency

---

## 5. Performance Optimization

### ✅ Strengths

**Pre-calculated Metrics Table**:
- Excellent use of `metrics` table to avoid expensive real-time aggregations
- Multi-dimensional filtering support
- Unique constraint ensures no duplicate calculations

**Proper Index Usage**:
- Good coverage of common query patterns
- Appropriate use of different index types (B-tree, GIN)

### ⚠️ Recommendations

**R5.1**: Add table statistics targets for better query planning
```sql
-- For columns used in WHERE clauses frequently
ALTER TABLE cases ALTER COLUMN agency_id SET STATISTICS 1000;
ALTER TABLE cases ALTER COLUMN offence_action_date SET STATISTICS 1000;
ALTER TABLE notices ALTER COLUMN agency_id SET STATISTICS 1000;
```
**Benefit**: More accurate query plans for better performance

**R5.2**: Configure autovacuum for high-update tables
```sql
-- For frequently updated tables like scrape_sessions
ALTER TABLE scrape_sessions SET (
  autovacuum_vacuum_scale_factor = 0.05,
  autovacuum_analyze_scale_factor = 0.02
);
```
**Benefit**: More frequent vacuuming prevents table bloat

**R5.3**: Add fillfactor for high-update tables
```sql
-- Leave room for HOT updates
ALTER TABLE scrape_sessions SET (fillfactor = 90);
ALTER TABLE metrics SET (fillfactor = 90);
```
**Benefit**: Reduces table bloat from frequent updates

**R5.4**: Consider table compression for large text fields
```sql
-- Enable compression for large text columns
ALTER TABLE notices ALTER COLUMN notice_body SET STORAGE EXTENDED;
ALTER TABLE cases ALTER COLUMN offence_breaches SET STORAGE EXTENDED;
```
**Benefit**: Reduces storage size (already default, but explicit is better)

---

## 6. Security & Access Control

### ✅ Strengths

**UUID Primary Keys**:
- Prevents enumeration attacks
- No sequential ID exposure

**Conditional Unique Indexes**:
- Proper handling of NULL values in unique constraints

### ⚠️ Recommendations

**R6.1**: Implement Row-Level Security (RLS) policies
```sql
-- Enable RLS on sensitive tables
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- Example policy for admin-only access
CREATE POLICY cases_admin_policy ON cases
  FOR ALL
  TO authenticated_users
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = current_user_id()
      AND users.is_admin = true
    )
  );
```
**Benefit**: Database-level authorization control

**R6.2**: Create read-only database roles
```sql
CREATE ROLE readonly_user;
GRANT CONNECT ON DATABASE ehs_enforcement TO readonly_user;
GRANT USAGE ON SCHEMA public TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
```
**Benefit**: Principle of least privilege for reporting/analytics

**R6.3**: Add audit trigger for sensitive tables
```sql
CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL,
  old_data JSONB,
  new_data JSONB,
  user_id UUID,
  changed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE FUNCTION audit_trigger_func() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, operation, old_data, new_data)
  VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), row_to_json(NEW));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cases_audit_trigger
AFTER UPDATE OR DELETE ON cases
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
```
**Benefit**: Complete audit trail for compliance

---

## 7. Monitoring & Maintenance

### ⚠️ Recommendations

**R7.1**: Set up query performance monitoring
```sql
-- Enable pg_stat_statements extension
CREATE EXTENSION pg_stat_statements;

-- Regular query to identify slow queries
SELECT
  query,
  calls,
  total_exec_time,
  mean_exec_time,
  stddev_exec_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 20;
```
**Benefit**: Identifies performance bottlenecks

**R7.2**: Monitor index usage
```sql
-- Find unused indexes
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%_pkey'
ORDER BY pg_relation_size(indexrelid) DESC;
```
**Benefit**: Identify and remove unused indexes

**R7.3**: Set up table bloat monitoring
```sql
-- Check table bloat
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  n_live_tup,
  n_dead_tup,
  ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```
**Benefit**: Identifies tables needing vacuum

---

## 8. Scalability Considerations

### ⚠️ Recommendations

**R8.1**: Consider connection pooling configuration
```elixir
# config/prod.exs
config :ehs_enforcement, EhsEnforcement.Repo,
  pool_size: 10,  # Adjust based on load
  queue_target: 50,  # ms
  queue_interval: 1000  # ms
```
**Benefit**: Better connection management under load

**R8.2**: Implement read replicas for reporting
```sql
-- Set up logical replication for read replicas
-- On primary
ALTER SYSTEM SET wal_level = logical;
CREATE PUBLICATION metrics_pub FOR TABLE metrics, cases, notices;

-- On replica
CREATE SUBSCRIPTION metrics_sub
CONNECTION 'host=primary_host dbname=ehs_enforcement'
PUBLICATION metrics_pub;
```
**Benefit**: Offload read-heavy dashboard queries

**R8.3**: Consider archiving old data
```sql
-- Archive old scrape sessions after 90 days
CREATE TABLE scrape_sessions_archive (LIKE scrape_sessions INCLUDING ALL);

INSERT INTO scrape_sessions_archive
SELECT * FROM scrape_sessions
WHERE status IN ('completed', 'failed')
  AND updated_at < NOW() - INTERVAL '90 days';

DELETE FROM scrape_sessions
WHERE status IN ('completed', 'failed')
  AND updated_at < NOW() - INTERVAL '90 days';
```
**Benefit**: Reduces table size and improves query performance

---

## Priority Recommendations

### High Priority (Immediate)

1. **R2.1**: Add missing foreign key indexes on `metrics` table
2. **R4.1**: Add CHECK constraints for data validation
3. **R5.1**: Set statistics targets for heavily-queried columns
4. **R7.1**: Enable pg_stat_statements for query monitoring

### Medium Priority (Next Sprint)

5. **R1.1**: Migrate to `timestamptz` for all datetime fields
6. **R3.2**: Add soft deletes with `deleted_at` column
7. **R5.2**: Configure autovacuum for high-update tables
8. **R2.2**: Add partial indexes for common filtered queries

### Low Priority (Future Optimization)

9. **R3.1**: Implement table partitioning for cases/notices
10. **R3.3**: Create materialized views for dashboard
11. **R6.1**: Implement Row-Level Security policies
12. **R8.2**: Set up read replicas for reporting

---

## Implementation Notes

**Migration Strategy**:
1. Test all changes in development environment first
2. Run EXPLAIN ANALYZE before and after index changes
3. Monitor query performance with pg_stat_statements
4. Apply changes during low-traffic periods
5. Have rollback plan for each migration

**Monitoring After Changes**:
- Track query performance metrics
- Monitor index usage statistics
- Watch for table bloat
- Check autovacuum activity
- Monitor connection pool saturation

---

## Conclusion

The EHS Enforcement database schema is well-designed with good use of PostgreSQL features. The recommendations focus on:

1. **Performance**: Better indexing and query optimization
2. **Data Integrity**: Additional constraints and validation
3. **Maintainability**: Better monitoring and maintenance strategies
4. **Scalability**: Partitioning and replication preparation

Implementing the high-priority recommendations will provide immediate performance and reliability benefits, while the medium and low-priority items position the application for future growth and scale.
