# Database Schema Documentation

This document provides comprehensive schema documentation for the EHS Enforcement application database, based on current Ash resources and PostgreSQL migrations.

## Overview

The EHS Enforcement application uses PostgreSQL as its primary database with Ash Framework resources that manage schema and data operations. The schema is organized into several domains:

- **Accounts** - User authentication and session management
- **Enforcement** - Core enforcement data (cases, notices, agencies, offenders, metrics)
- **Configuration** - Application configuration and scraping settings
- **Scraping** - Web scraping session tracking and temporary data storage
- **Sync** - Data synchronization tracking
- **Events** - Event sourcing and audit trails

## Schema Summary

| Table | Primary Key | Records Type | Domain |
|-------|-------------|--------------|--------|
| `users` | `id` (uuid) | User accounts | Accounts |
| `user_identities` | `id` (uuid) | OAuth identities | Accounts |
| `tokens` | `jti` (text) | Auth tokens | Accounts |
| `agencies` | `id` (uuid) | Enforcement agencies | Enforcement |
| `offenders` | `id` (uuid) | Companies/individuals | Enforcement |
| `cases` | `id` (uuid) | Court cases | Enforcement |
| `notices` | `id` (uuid) | Enforcement notices | Enforcement |
| `legislation` | `id` (uuid) | Legislation lookup | Enforcement |
| `offences` | `id` (uuid) | Unified offences (HSE + EA) | Enforcement |
| `metrics` | `id` (uuid) | Dashboard metrics | Enforcement |
| `scraping_configs` | `id` (uuid) | Scraping configuration | Configuration |
| `scrape_sessions` | `id` (uuid) | Scraping session tracking | Scraping |
| `processing_logs` | `id` (uuid) | Processing logs | Scraping |
| `scraped_cases` | `id` (uuid) | Temporary scraped data | Scraping |
| `sync_logs` | `id` (uuid) | Sync operation logs | Sync |
| `events` | `id` (bigserial) | Event sourcing | Events |

---

## Accounts Domain

### `users` Table

**Purpose**: Core user accounts with GitHub OAuth authentication and admin privileges.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Unique user identifier |
| `email` | `citext` | NOT NULL, UNIQUE | User email address (case-insensitive) |
| `github_id` | `text` | NULLABLE | GitHub user ID from OAuth |
| `github_login` | `text` | NULLABLE | GitHub username |
| `name` | `text` | NULLABLE | User's display name |
| `avatar_url` | `text` | NULLABLE | GitHub avatar URL |
| `github_url` | `text` | NULLABLE | GitHub profile URL |
| `is_admin` | `boolean` | NOT NULL, DEFAULT false | Admin privilege flag |
| `admin_checked_at` | `timestamp` | NULLABLE | Last admin status check |
| `last_login_at` | `timestamp` | NULLABLE | Last login timestamp |
| `primary_provider` | `text` | NOT NULL, DEFAULT 'github' | OAuth provider |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `users_unique_email_index` (UNIQUE on `email`)
- Index on `github_id`
- Index on `github_login`
- Index on `is_admin`

**Ash Identity**: `unique_email` on `[:email]`

---

### `user_identities` Table

**Purpose**: OAuth provider identities linked to users (supports multiple providers per user).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Identity record ID |
| `user_id` | `uuid` | NOT NULL, FK → users.id | Associated user |
| `uid` | `text` | NOT NULL | Provider-specific user ID |
| `strategy` | `text` | NOT NULL | OAuth strategy (e.g., 'github') |
| `access_token` | `text` | NULLABLE | OAuth access token |
| `refresh_token` | `text` | NULLABLE | OAuth refresh token |
| `access_token_expires_at` | `timestamp` | NULLABLE | Token expiration |

**Indexes**:
- `user_identities_unique_on_strategy_and_uid_and_user_id_index` (UNIQUE on `[:strategy, :uid, :user_id]`)

**Foreign Keys**:
- `user_identities_user_id_fkey`: `user_id` → `users.id` (CASCADE DELETE)

---

### `tokens` Table

**Purpose**: Authentication tokens and session management.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `jti` | `text` | PRIMARY KEY, NOT NULL | JWT ID (unique identifier) |
| `subject` | `text` | NOT NULL | Token subject (usually user ID) |
| `purpose` | `text` | NOT NULL | Token purpose/type |
| `expires_at` | `timestamp` | NOT NULL | Token expiration time |
| `extra_data` | `jsonb` | NULLABLE | Additional token metadata |
| `created_at` | `timestamp` | NOT NULL | Token creation time |
| `updated_at` | `timestamp` | NOT NULL | Token update time |

**Indexes**:
- UNIQUE index on `jti`
- Index on `purpose`
- Index on `expires_at`

---

## Enforcement Domain

### `agencies` Table

**Purpose**: Enforcement agencies (HSE, ONR, ORR, EA, etc.) that issue cases and notices.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Agency unique identifier |
| `code` | `text` | NOT NULL, UNIQUE | Agency code (:hse, :onr, :orr, :ea) |
| `name` | `text` | NOT NULL | Agency full name |
| `base_url` | `text` | NULLABLE | Agency website base URL |
| `enabled` | `boolean` | NOT NULL, DEFAULT true | Whether agency is active |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `agencies_unique_code_index` (UNIQUE on `code`)

**Ash Identity**: `unique_code` on `[:code]`

**Ash Constraints**: `code` must be one of `[:hse, :ea, :sepa, :nrw, :orr, :mca, :caa, :cqc, :dwi, :opss, :gc, :onr, :fra, :niea, :fsa, :ico]`

**Agency Codes Reference**:
| Code | Agency | Status |
|------|--------|--------|
| `hse` | Health and Safety Executive | Implemented |
| `ea` | Environment Agency | Implemented |
| `sepa` | Scottish Environment Protection Agency | In Progress |
| `nrw` | Natural Resources Wales | Planned |
| `orr` | Office of Rail and Road | Researched |
| `mca` | Maritime and Coastguard Agency | Researched |
| `caa` | Civil Aviation Authority | Planned |
| `cqc` | Care Quality Commission | Planned |
| `dwi` | Drinking Water Inspectorate | Planned |
| `opss` | Office for Product Safety and Standards | Researched |
| `gc` | Gambling Commission | Planned |
| `onr` | Office for Nuclear Regulation | Planned |
| `fra` | Fire and Rescue Authorities (NFCC) | Researched |
| `niea` | Northern Ireland Environment Agency | Planned |
| `fsa` | Food Standards Agency | Planned |
| `ico` | Information Commissioner's Office | Planned |

**Relationships**:
- `has_many :cases` → `cases.agency_id`
- `has_many :notices` → `notices.agency_id`

---

### `offenders` Table

**Purpose**: Companies or individuals subject to enforcement actions (normalized to prevent duplication).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Offender unique identifier |
| `name` | `text` | NOT NULL | Original company/individual name |
| `normalized_name` | `text` | NULLABLE | Normalized name for matching |
| `address` | `text` | NULLABLE | Offender business address |
| `local_authority` | `text` | NULLABLE | Local authority area |
| `country` | `text` | NULLABLE | Country (England, Scotland, Wales, Northern Ireland) |
| `postcode` | `text` | NULLABLE | Postal code |
| `main_activity` | `text` | NULLABLE | Primary business activity |
| `sic_code` | `text` | NULLABLE | Standard Industrial Classification code |
| `business_type` | `text` | NULLABLE | Business structure type (atom: :limited_company, :individual, :partnership, :plc, :other) |
| `industry` | `text` | NULLABLE | Industry classification |
| `first_seen_date` | `date` | NULLABLE | First enforcement action date |
| `last_seen_date` | `date` | NULLABLE | Most recent enforcement date |
| `total_cases` | `integer` | NOT NULL, DEFAULT 0 | Total court cases count |
| `total_notices` | `integer` | NOT NULL, DEFAULT 0 | Total notices count |
| `total_fines` | `decimal` | NOT NULL, DEFAULT 0 | Total fine amounts |
| `company_registration_number` | `text` | NULLABLE | Companies House registration number (UK only) |
| `company_registration_validated` | `boolean` | DEFAULT false | Whether Companies House validation succeeded |
| `company_validation_confidence` | `decimal` | NULLABLE | Similarity score from Companies House match (0-1) |
| `company_validation_date` | `timestamp` | NULLABLE | When Companies House validation was performed |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `offenders_unique_name_postcode_index` (UNIQUE on `[:normalized_name, :postcode]`)
- `offenders_unique_company_number_index` (UNIQUE on `company_registration_number` WHERE `company_registration_number IS NOT NULL`)

**Ash Identities**:
- `unique_name_postcode` on `[:normalized_name, :postcode]`
- `unique_company_number` on `[:company_registration_number]` WHERE `not is_nil(company_registration_number)`

**Ash Constraints**: `business_type` must be one of `[:limited_company, :individual, :partnership, :plc, :other]`

**Companies House Integration (Nov 2025)**:
- Offender deduplication uses Companies House API for UK company validation
- `company_registration_number` prevents duplicates via unique constraint
- `company_validation_confidence` stores similarity match score (threshold: 0.9 for production)
- Merge preview UI shows validation before executing duplicate merges

**Relationships**:
- `has_many :cases` → `cases.offender_id`
- `has_many :notices` → `notices.offender_id`

**Business Logic**: 
- `normalized_name` is automatically generated from `name` using company name normalization rules
- Statistics (`total_cases`, `total_notices`, `total_fines`) are maintained via updates

---

### `cases` Table

**Purpose**: Court enforcement cases against offenders. Supports both HSE and EA (Environment Agency) enforcement data with agency-specific extensions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Case unique identifier |
| `case_reference` | `text` | NULLABLE, UNIQUE (if not null) | Agency's case reference number (EA 'Case Reference' field, formerly `airtable_id`) |
| `regulator_id` | `text` | NULLABLE | Unique ID from agency system (EA: ea_record_id, HSE: regulator case ID) |
| `agency_id` | `uuid` | NOT NULL, FK → agencies.id | Issuing agency |
| `offender_id` | `uuid` | NOT NULL, FK → offenders.id | Subject offender |
| `offence_result` | `text` | NULLABLE | Court outcome description |
| `offence_fine` | `decimal` | NULLABLE | Fine amount imposed |
| `offence_costs` | `decimal` | NULLABLE | Legal costs imposed |
| `offence_action_date` | `date` | NULLABLE | Date of enforcement action |
| `offence_hearing_date` | `date` | NULLABLE | Court hearing date |
| `regulator_function` | `text` | NULLABLE | Regulatory function involved |
| `regulator_url` | `text` | NULLABLE | Source URL at regulator |
| `related_cases` | `text` | NULLABLE | Related case references |
| `offence_action_type` | `text` | NULLABLE | Type of enforcement action |
| `url` | `text` | NULLABLE | Public case URL |
| `offence_breaches` | `text` | NULLABLE | Description of regulation breaches/violations (re-added Oct 2025) |
| `last_synced_at` | `timestamp` | NULLABLE | Last synchronization time |
| `ea_event_reference` | `text` | NULLABLE | EA event ID (e.g., '205107') |
| `ea_total_violation_count` | `integer` | NULLABLE | Total EA violation count for multi-violation cases |
| `environmental_impact` | `text` | NULLABLE | EA environmental impact description |
| `environmental_receptor` | `text` | NULLABLE | EA environmental receptor affected |
| `is_ea_multi_violation` | `boolean` | DEFAULT false | Whether case has multiple EA violations |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `cases_unique_case_reference_index` (UNIQUE on `case_reference` WHERE `case_reference IS NOT NULL`)
- `cases_unique_case_per_agency_index` (UNIQUE COMPOSITE on `[agency_id, regulator_id]` WHERE `regulator_id IS NOT NULL`)
- `cases_offence_action_date_index` on `offence_action_date` (dashboard metrics)
- `cases_agency_id_index` on `agency_id` (filtering performance)
- `cases_agency_date_index` (COMPOSITE on `[:agency_id, :offence_action_date]`)
- `cases_offence_fine_index` on `offence_fine` (range queries)
- `cases_regulator_id_index` on `regulator_id` (standard B-tree)
- `cases_regulator_id_gin_trgm` on `regulator_id` (trigram similarity search)

**Ash Identities**:
- `unique_case_reference` on `[:case_reference]` WHERE `not is_nil(case_reference)`
- `unique_case_per_agency` on `[:agency_id, :regulator_id]` WHERE `not is_nil(regulator_id)`

**Schema Changes (Oct-Nov 2025)**:
- Renamed `airtable_id` → `case_reference` to better reflect multi-agency usage (Oct 2025)
- Added composite unique constraint on `[agency_id, regulator_id]` for cross-agency uniqueness (Oct 2025)
- Added EA-specific fields for Environment Agency enforcement data (Oct 2025)
- Re-added `offence_breaches` field for backward compatibility with processing (Oct 2025)

**Deduplication History (Nov 2025)**:
- **Issue #10**: Removed 543 corrupt HSE cases with EA-pattern regulator_ids
  - Cases had 3-4 digit IDs (EA pattern) instead of 8-digit HSE pattern
  - All corrupt cases had empty data (no fines, costs, action types)
  - Verified via manual checks against agency websites
- **Composite Constraint**: `(agency_id, regulator_id)` prevents cross-agency duplicates
- **Duplicate Detector**: Updated to respect agency boundaries (removed aggressive financial matching strategy)
- **Result**: 0 true duplicates remaining in database

**Foreign Keys**:
- `cases_agency_id_fkey`: `agency_id` → `agencies.id`
- `cases_offender_id_fkey`: `offender_id` → `offenders.id`

**Relationships**:
- `belongs_to :agency` → `agencies`
- `belongs_to :offender` → `offenders`
- `has_many :offences` → `offences.case_id` (unified schema)

**Calculations**:
- `computed_breaches_summary` - PostgreSQL fragment aggregating linked offences into semicolon-separated summary

**Event Sourcing**: Enabled with actions `[:create, :sync, :bulk_create]`

---

### `notices` Table

**Purpose**: Enforcement notices issued to offenders (improvement notices, prohibition notices, etc.). Supports both HSE and EA (Environment Agency) enforcement notices with fuzzy text search using PostgreSQL pg_trgm extension.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Notice unique identifier |
| `airtable_id` | `text` | NULLABLE, UNIQUE (if not null) | Airtable record ID |
| `regulator_id` | `text` | NULLABLE | HSE/agency internal notice ID |
| `regulator_ref_number` | `text` | NULLABLE | Official reference number |
| `agency_id` | `uuid` | NOT NULL, FK → agencies.id | Issuing agency |
| `offender_id` | `uuid` | NOT NULL, FK → offenders.id | Subject offender |
| `notice_date` | `date` | NULLABLE | Date notice was issued |
| `operative_date` | `date` | NULLABLE | Date notice becomes operative |
| `compliance_date` | `date` | NULLABLE | Required compliance date |
| `notice_body` | `text` | NULLABLE | Full notice text content |
| `offence_action_type` | `text` | NULLABLE | Type of enforcement action |
| `offence_action_date` | `date` | NULLABLE | Date of original offence |
| `url` | `text` | NULLABLE | Public notice URL |
| `offence_breaches` | `text` | NULLABLE | Description of regulation breaches/violations (re-added Oct 2025) |
| `last_synced_at` | `timestamp` | NULLABLE | Last synchronization time |
| `regulator_event_reference` | `text` | NULLABLE | EA event reference ID |
| `environmental_impact` | `text` | NULLABLE | EA environmental impact description |
| `environmental_receptor` | `text` | NULLABLE | EA environmental receptor affected |
| `legal_act` | `text` | NULLABLE | EA legal act citation |
| `legal_section` | `text` | NULLABLE | EA legal section reference |
| `regulator_function` | `text` | NULLABLE | EA regulator function |
| `penalty_amount` | `decimal` | NULLABLE | SEPA monetary penalty amount (FMP/VMP) |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `notices_unique_airtable_id_index` (UNIQUE on `airtable_id` WHERE `airtable_id IS NOT NULL`)
- `notices_unique_regulator_per_agency_index` (UNIQUE COMPOSITE on `[:regulator_id, :agency_id]` WHERE `regulator_id IS NOT NULL AND regulator_id != ''`)
- `notices_offence_action_date_index` on `offence_action_date` (dashboard metrics)
- `notices_agency_id_index` on `agency_id` (filtering performance)
- `notices_agency_date_index` (COMPOSITE on `[:agency_id, :offence_action_date]`)
- `notices_regulator_id_index` on `regulator_id` (standard B-tree)
- `notices_offence_action_type_index` on `offence_action_type` (filtering)

**Fuzzy Search Indexes (pg_trgm GIN)**:
- `notices_regulator_id_gin_trgm` on `regulator_id` (trigram similarity search)
- `notices_notice_body_gin_trgm` on `notice_body` (trigram similarity search)

**Schema Changes (Aug-Nov 2025)**:
- Added EA-specific fields for Environment Agency enforcement notices (Oct 2025)
- Re-added `offence_breaches` field for backward compatibility with processing (Oct 2025)
- Added `penalty_amount` field for SEPA monetary penalties (Nov 2025)

**Deduplication History (Nov 2025)**:
- **Issue #4**: Removed 1,693 duplicate notices from production database
  - 1,693 HSE notices incorrectly created with EA regulator_id values
  - Cross-agency contamination: 48 HSE notices with EA IDs (same pattern as case duplicates)
  - All duplicates had correct EA counterparts with complete data
  - SQL bulk cleanup strategy used for efficient removal
- **Composite Constraint**: `(regulator_id, agency_id)` prevents cross-agency duplicates
- **Duplicate Detector**: Updated to respect agency boundaries and regulator_id format patterns
- **Result**: 0 true duplicates remaining in database after cleanup

**Ash Identities**:
- `unique_airtable_id` on `[:airtable_id]` WHERE `not is_nil(airtable_id)`
- `unique_regulator_per_agency` on `[:regulator_id, :agency_id]` WHERE `expr(not is_nil(regulator_id) and regulator_id != "")`

**Foreign Keys**:
- `notices_agency_id_fkey`: `agency_id` → `agencies.id`
- `notices_offender_id_fkey`: `offender_id` → `offenders.id`

**Relationships**:
- `belongs_to :agency` → `agencies`
- `belongs_to :offender` → `offenders`
- `has_many :offences` → `offences.notice_id` (unified)

**Calculations**:
- `computed_breaches_summary` - PostgreSQL fragment aggregating linked offences into semicolon-separated summary

**Fuzzy Search Features**:
- **Function**: `Enforcement.fuzzy_search_notices/2` supports trigram similarity search
- **Search Fields**: `regulator_id`, `notice_body`
- **UI Integration**: Toggle-enabled fuzzy search in LiveView interface
- **Performance**: GIN indexes with `gin_trgm_ops` operator class for fast similarity queries
- **Similarity Threshold**: Configurable threshold (default 0.3) for match sensitivity

---

### `legislation` Table (NEW - Unified Schema)

**Purpose**: Normalized lookup table for legislation referenced in enforcement actions. Replaces inline legislation references from legacy breaches/violations tables.

| Column | Type | Constraints | Description | Example |
|--------|------|-------------|-------------|---------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Legislation unique identifier | |
| `legislation_title` | `text` | NOT NULL | Full legislation title | "Health and Safety at Work etc. Act" |
| `legislation_year` | `integer` | NULLABLE, 1800-2100 | Year enacted | 1974 |
| `legislation_number` | `integer` | NULLABLE, >= 1 | Official chapter/number | 33 |
| `legislation_type` | `text` | NOT NULL, DEFAULT 'act' | Type of legislation | "act", "regulation", "order", "acop" |
| `created_at` | `timestamp` | NOT NULL | Record creation time | |
| `updated_at` | `timestamp` | NOT NULL | Record update time | |

**Indexes**:
- `legislation_title_year_number_unique` (UNIQUE on `[:legislation_title, :legislation_year, :legislation_number]`)
- `legislation_unique_legislation_index` (UNIQUE on `[:legislation_title, :legislation_year, :legislation_number]` NULLS NOT DISTINCT)
- `legislation_unique_title_year_index` (UNIQUE on `[:legislation_title, :legislation_year]` NULLS NOT DISTINCT)
- `legislation_type_index` on `legislation_type`
- `legislation_year_index` on `legislation_year`
- `legislation_title_gin_trgm` (GIN trigram index for fuzzy search)

**Ash Identity**: `unique_legislation` on `[:legislation_title, :legislation_year, :legislation_number]`

**Schema Changes (Oct 2025)**:
- Added `NULLS NOT DISTINCT` option to unique indexes for proper NULL handling
- Added partial unique index on title+year for legislation without numbers

**Ash Constraints**: `legislation_type` must be one of `[:act, :regulation, :order, :acop]`

**Relationships**:
- `has_many :offences` → `offences.legislation_id`

**Calculations**:
- `full_reference` - Complete citation including year and number

---

### `offences` Table (NEW - Unified Schema)

**Purpose**: Unified table consolidating legislation breaches and violations from both HSE and EA enforcement actions. Replaces separate `breaches` and `violations` tables.

| Column | Type | Constraints | Description | Example |
|--------|------|-------------|-------------|---------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Offence unique identifier | |
| `case_id` | `uuid` | NULLABLE, FK → cases.id | Associated court case | |
| `notice_id` | `uuid` | NULLABLE, FK → notices.id | Associated enforcement notice | |
| `legislation_id` | `uuid` | NOT NULL, FK → legislation.id | Referenced legislation | |
| `offence_reference` | `text` | NULLABLE, UNIQUE (if not null) | External reference | "SW/A/2010/2051079/01" |
| `offence_description` | `text` | NULLABLE | Description of the specific breach | "Failed to comply with permit conditions" |
| `legislation_part` | `text` | NULLABLE | Section/regulation/part reference | "Section 33", "Regulation 4" |
| `fine` | `decimal` | NULLABLE, >= 0 | Financial penalty for this offence | 2750.00 |
| `sequence_number` | `integer` | NULLABLE, >= 1 | Order within case (EA pattern) | 1, 2, 3 |
| `created_at` | `timestamp` | NOT NULL | Record creation time | |
| `updated_at` | `timestamp` | NOT NULL | Record update time | |

**Indexes**:
- Foreign key indexes: `case_id`, `notice_id`, `legislation_id`
- Composite indexes: `[:case_id, :sequence_number]`, `[:legislation_id, :fine]`
- Performance indexes: `fine`, `sequence_number`
- Unique constraints: `offence_reference` (conditional), `[:case_id, :sequence_number]` (conditional)
- Fuzzy search (pg_trgm GIN): `offence_description`, `offence_reference`, `legislation_part`

**Ash Identities**:
- `unique_offence_reference` on `[:offence_reference]` WHERE `not is_nil(offence_reference)`
- `unique_case_sequence` on `[:case_id, :sequence_number]` WHERE `not is_nil(case_id) and not is_nil(sequence_number)`

**Foreign Keys**:
- `offences_case_id_fkey`: `case_id` → `cases.id`
- `offences_notice_id_fkey`: `notice_id` → `notices.id`
- `offences_legislation_id_fkey`: `legislation_id` → `legislation.id`

**Relationships**:
- `belongs_to :case` → `cases`
- `belongs_to :notice` → `notices`
- `belongs_to :legislation` → `legislation`

**Business Logic**:
- At least one of `case_id` or `notice_id` must be present
- Supports both HSE (simple breaches) and EA (complex multi-violation) patterns
- `sequence_number` used for EA cases with multiple violations
- `offence_reference` used for EA external case references

**Event Sourcing**: Enabled with actions `[:create, :update, :bulk_create]`

**Calculations**:
- `total_financial_penalty` - Fine amount (defaults to 0)
- `legislation_reference` - Combined legislation title and part reference

---

### Legacy Schema Migration (COMPLETED - Aug 2025)

**Status**: ✅ **FULLY NORMALIZED** - Complete schema consolidation achieved

#### Legacy Tables Removed
- **`violations` Table**: EA violations → migrated to `offences` table
- **`breaches` Table**: HSE breaches → migrated to `offences` table

#### Legacy Fields Removed
- **`notices.offence_breaches`**: Text field → migrated to linked `offences` records
- **`cases.offence_breaches`**: Raw text field → migrated to linked `offences` records  
- **`cases.offence_breaches_clean`**: Cleaned text field → migrated to linked `offences` records

#### Migration Results
- **Data Migration**: 100% successful with zero data loss
  - 30 notices with breach data → 68 offence records
  - 424 cases with breach data → 540 offence records
  - Total: 608 offence records + 53 legislation records
- **Schema Cleanup**: All denormalized text fields removed
- **Computed Fields**: Added `computed_breaches_summary` to both cases and notices
- **Relationships**: All resources updated to use unified `offences` ↔ `legislation` pattern

#### Benefits Achieved
- ✅ **Zero Denormalization**: No text fields containing breach data remain
- ✅ **Unified Pattern**: Both cases and notices use identical offence relationships
- ✅ **Normalized Legislation**: Single source of truth for all legislation references
- ✅ **Better Performance**: Proper indexes on relationships vs text search
- ✅ **Data Integrity**: Foreign key constraints enforced throughout
- ✅ **Query Flexibility**: Can filter/search individual offences vs concatenated text

---

### `metrics` Table (NEW - Oct 2025)

**Purpose**: Pre-calculated dashboard metrics with multi-dimensional filtering support for performance optimization. Enables fast dashboard rendering by storing computed aggregations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Metrics record unique identifier |
| `period` | `text` | NOT NULL | Time period identifier (e.g., "7_days", "30_days", "90_days", "all_time") |
| `period_label` | `text` | NOT NULL | Human-readable period label |
| `days_ago` | `integer` | NOT NULL | Days in the lookback period |
| `cutoff_date` | `date` | NOT NULL | Calculated cutoff date for the period |
| `calculated_at` | `timestamp` | NOT NULL | When metrics were calculated |
| `calculated_by` | `text` | NOT NULL | Who/what triggered calculation |
| `agency_id` | `uuid` | NULLABLE | Filter: specific agency (NULL = all agencies) |
| `record_type` | `text` | NULLABLE | Filter: "case" or "notice" (NULL = both) |
| `offender_id` | `uuid` | NULLABLE | Filter: specific offender (NULL = all offenders) |
| `legislation_id` | `uuid` | NULLABLE | Filter: specific legislation (NULL = all legislation) |
| `recent_cases_count` | `integer` | NOT NULL, DEFAULT 0 | Cases within period |
| `recent_notices_count` | `integer` | NOT NULL, DEFAULT 0 | Notices within period |
| `total_cases_count` | `integer` | NOT NULL, DEFAULT 0 | All-time cases count |
| `total_notices_count` | `integer` | NOT NULL, DEFAULT 0 | All-time notices count |
| `total_offences_count` | `integer` | NOT NULL, DEFAULT 0 | Total offences/violations |
| `total_fines_amount` | `decimal` | NOT NULL, DEFAULT 0 | Sum of all fines |
| `total_costs_amount` | `decimal` | NOT NULL, DEFAULT 0 | Sum of all costs |
| `active_agencies_count` | `integer` | NOT NULL, DEFAULT 0 | Number of active agencies |
| `agency_stats` | `jsonb` | NOT NULL, DEFAULT {} | Per-agency breakdown |
| `offender_breakdown` | `jsonb` | NOT NULL, DEFAULT {} | Top offenders statistics |
| `legislation_breakdown` | `jsonb` | NOT NULL, DEFAULT {} | Top legislation statistics |
| `recent_activity` | `jsonb[]` | NOT NULL, DEFAULT [] | Recent enforcement actions |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `metrics_unique_filter_combination_index` (UNIQUE on `[:period, :agency_id, :record_type, :offender_id, :legislation_id]`)

**Purpose**: Supports fast dashboard queries with various filter combinations without expensive on-the-fly aggregations.

**Filter Dimensions**:
- **Period**: Time-based filtering (7 days, 30 days, 90 days, all time)
- **Agency**: Agency-specific metrics (HSE, EA, etc.)
- **Record Type**: Cases vs notices breakdown
- **Offender**: Individual offender statistics
- **Legislation**: Legislation-specific enforcement patterns

**Usage Pattern**:
- Metrics are pre-calculated on a schedule or on-demand
- Dashboard queries retrieve pre-computed values for instant rendering
- Unique constraint ensures one metrics record per filter combination per period
- NULL values in filter dimensions represent "all" (e.g., NULL agency_id = all agencies)

---

## Configuration Domain

### `scraping_configs` Table

**Purpose**: Configuration profiles for HSE case scraping operations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Configuration unique identifier |
| `name` | `text` | NOT NULL, UNIQUE | Profile name |
| `is_active` | `boolean` | NOT NULL, DEFAULT true | Whether profile is active |
| `description` | `text` | NULLABLE | Profile description |
| `hse_base_url` | `text` | NOT NULL, DEFAULT 'https://www.hse.gov.uk' | HSE website base URL |
| `hse_database` | `text` | NOT NULL, DEFAULT 'convictions' | HSE database to scrape |
| `requests_per_minute` | `integer` | NOT NULL, DEFAULT 10 | Rate limiting: requests/minute |
| `network_timeout_ms` | `integer` | NOT NULL, DEFAULT 30000 | HTTP timeout (milliseconds) |
| `pause_between_pages_ms` | `integer` | NOT NULL, DEFAULT 3000 | Delay between requests |
| `consecutive_existing_threshold` | `integer` | NOT NULL, DEFAULT 10 | Stop after N existing records |
| `max_pages_per_session` | `integer` | NOT NULL, DEFAULT 100 | Max pages per scraping session |
| `max_consecutive_errors` | `integer` | NOT NULL, DEFAULT 3 | Stop after N consecutive errors |
| `batch_size` | `integer` | NOT NULL, DEFAULT 50 | Records per processing batch |
| `scheduled_scraping_enabled` | `boolean` | NOT NULL, DEFAULT true | Enable scheduled scraping |
| `manual_scraping_enabled` | `boolean` | NOT NULL, DEFAULT true | Enable manual scraping |
| `real_time_progress_enabled` | `boolean` | NOT NULL, DEFAULT true | Enable progress updates |
| `admin_notifications_enabled` | `boolean` | NOT NULL, DEFAULT true | Enable admin notifications |
| `daily_scrape_cron` | `text` | NULLABLE, DEFAULT '0 2 * * *' | Daily scraping schedule |
| `weekly_scrape_cron` | `text` | NULLABLE, DEFAULT '0 1 * * 0' | Weekly scraping schedule |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `scraping_configs_unique_name_index` (UNIQUE on `name`)

**Ash Identity**: `unique_name` on `[:name]`

**Ash Constraints**:
- `requests_per_minute` > 0
- `network_timeout_ms` >= 5000
- `consecutive_existing_threshold` >= 3
- `max_pages_per_session` >= 5
- `batch_size` >= 10
- `hse_base_url` matches HTTP/HTTPS URL pattern
- `hse_database` must be one of `["convictions", "enforcement", "notices"]`

---

## Scraping Domain

### `scrape_sessions` Table (NEW - Aug 2025)

**Purpose**: Tracks web scraping sessions for both HSE and EA agencies with real-time progress monitoring via PubSub.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Session unique identifier |
| `session_id` | `text` | NOT NULL, UNIQUE | External session identifier |
| `agency` | `text` | NOT NULL, DEFAULT 'hse' | Agency being scraped (:hse or :environment_agency) |
| `status` | `text` | NOT NULL, DEFAULT 'pending' | Session status (:pending, :running, :completed, :failed, :stopped) |
| `database` | `text` | NOT NULL, DEFAULT 'convictions' | HSE database ("convictions", "notices", "appeals") |
| `start_page` | `integer` | NOT NULL, DEFAULT 1 | HSE: Starting page number |
| `max_pages` | `integer` | NOT NULL, DEFAULT 10 | HSE: Maximum pages to scrape |
| `end_page` | `integer` | NULLABLE | HSE: Actual ending page |
| `current_page` | `integer` | NULLABLE | Current page being processed |
| `pages_processed` | `integer` | DEFAULT 0 | Total pages completed |
| `date_from` | `date` | NULLABLE | EA: Start date for date range scraping |
| `date_to` | `date` | NULLABLE | EA: End date for date range scraping |
| `action_types` | `text[]` | NULLABLE | EA: Action types to scrape |
| `cases_found` | `integer` | DEFAULT 0 | Total cases discovered |
| `cases_processed` | `integer` | DEFAULT 0 | Cases processed |
| `cases_created` | `integer` | DEFAULT 0 | New cases created |
| `cases_created_current_page` | `integer` | DEFAULT 0 | Cases created on current page |
| `cases_updated` | `integer` | DEFAULT 0 | Cases updated |
| `cases_updated_current_page` | `integer` | DEFAULT 0 | Cases updated on current page |
| `cases_exist_total` | `integer` | DEFAULT 0 | Cases that already existed |
| `cases_exist_current_page` | `integer` | DEFAULT 0 | Existing cases on current page |
| `errors_count` | `integer` | DEFAULT 0 | Error count |
| `inserted_at` | `timestamp` | NOT NULL | Session creation time |
| `updated_at` | `timestamp` | NOT NULL | Last update time |

**Indexes**:
- `scrape_sessions_unique_session_id_index` (UNIQUE on `session_id`)

**Ash Identity**: `unique_session_id` on `[:session_id]`

**Purpose**: Unified session tracking for both HSE page-based scraping and EA date-range scraping patterns.

**PubSub Integration**: Real-time progress updates broadcast via Phoenix PubSub on topic `scrape_session:updated`.

---

### `processing_logs` Table (NEW - Aug 2025)

**Purpose**: Detailed processing logs for scraping sessions, recording batch/page-level results and errors.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Log record unique identifier |
| `session_id` | `text` | NOT NULL | Associated scrape session |
| `agency` | `text` | NOT NULL | Agency identifier |
| `batch_or_page` | `integer` | DEFAULT 1 | Batch number or page number |
| `items_found` | `integer` | DEFAULT 0 | Items discovered in this batch/page |
| `items_created` | `integer` | DEFAULT 0 | New items created |
| `items_existing` | `integer` | DEFAULT 0 | Items that already existed |
| `items_failed` | `integer` | DEFAULT 0 | Items that failed processing |
| `creation_errors` | `text[]` | DEFAULT [] | Array of error messages |
| `scraped_items` | `jsonb[]` | DEFAULT [] | Raw scraped data for debugging |
| `inserted_at` | `timestamp` | NOT NULL | Log creation time |
| `updated_at` | `timestamp` | NOT NULL | Log update time |

**Purpose**: Provides granular logging for troubleshooting scraping issues and tracking batch processing results.

---

### `scraped_cases` Table (NEW - Aug 2025)

**Purpose**: Temporary staging table for scraped case data before processing into main `cases` table. Used for HSE scraping workflow.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Scraped case record ID |
| `session_id` | `text` | NOT NULL | Associated scrape session |
| `regulator_id` | `text` | NOT NULL | HSE case identifier |
| `page` | `integer` | NOT NULL | Page number where found |
| `offender_name` | `text` | NULLABLE | Scraped offender name |
| `offence_action_date` | `date` | NULLABLE | Scraped action date |
| `offence_fine` | `decimal` | NULLABLE | Scraped fine amount |
| `offence_result` | `text` | NULLABLE | Scraped case result |
| `processing_status` | `text` | DEFAULT 'scraping' | Processing stage status |
| `database_status` | `text` | DEFAULT 'pending' | Database operation status |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |
| `updated_at` | `timestamp` | NOT NULL | Record update time |

**Indexes**:
- `scraped_cases_unique_case_per_session_index` (UNIQUE on `[:session_id, :regulator_id, :page]`)

**Purpose**: Staging table allows scraping to be decoupled from database processing, enabling better error handling and retry logic.

**Lifecycle**: Records are typically processed into `cases` table and then can be archived or deleted after successful processing.

---

## Sync Domain

### `sync_logs` Table

**Purpose**: Tracks data synchronization operations and their results.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PRIMARY KEY, NOT NULL | Sync log unique identifier |
| `agency_id` | `uuid` | NOT NULL, FK → agencies.id | Agency being synchronized |
| `sync_type` | `text` | NULLABLE | Type of sync operation |
| `status` | `text` | NULLABLE | Sync operation status |
| `records_synced` | `integer` | NOT NULL, DEFAULT 0 | Number of records processed |
| `error_message` | `text` | NULLABLE | Error details if failed |
| `started_at` | `timestamp` | NULLABLE | Sync start time |
| `completed_at` | `timestamp` | NULLABLE | Sync completion time |
| `inserted_at` | `timestamp` | NOT NULL | Record creation time |

**Ash Constraints**:
- `sync_type` must be one of `[:cases, :notices]`
- `status` must be one of `[:started, :completed, :failed]`

**Foreign Keys**:
- `sync_logs_agency_id_fkey`: `agency_id` → `agencies.id`

**Relationships**:
- `belongs_to :agency` → `agencies`

---

## Events Domain

### `events` Table

**Purpose**: Event sourcing and audit trail for core domain operations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `bigserial` | PRIMARY KEY, NOT NULL | Event sequence identifier |
| `record_id` | `uuid` | NOT NULL | ID of the affected record |
| `resource` | `text` | NOT NULL | Ash resource name |
| `action` | `text` | NOT NULL | Action name that was performed |
| `action_type` | `text` | NOT NULL | Type of action (create, update, etc.) |
| `version` | `integer` | NOT NULL, DEFAULT 1 | Action version for schema evolution |
| `data` | `jsonb` | NOT NULL, DEFAULT {} | Event data payload |
| `metadata` | `jsonb` | NOT NULL, DEFAULT {} | Additional event metadata |
| `occurred_at` | `timestamp` | NOT NULL | Event timestamp |

**Purpose**: Centralized event log supporting event sourcing patterns and audit requirements.

---

## Relationship Summary

### Primary Entity Relationships

```
agencies (1) → (N) cases
agencies (1) → (N) notices
agencies (1) → (N) sync_logs

offenders (1) → (N) cases
offenders (1) → (N) notices

cases (1) → (N) offences (unified)
notices (1) → (N) offences (unified)

legislation (1) → (N) offences

users (1) → (N) user_identities
```

### Critical Foreign Key Constraints

All foreign key relationships use CASCADE or RESTRICT policies:
- `user_identities.user_id` → `users.id` (CASCADE DELETE)
- `cases.agency_id` → `agencies.id` (RESTRICT)
- `cases.offender_id` → `offenders.id` (RESTRICT)
- `notices.agency_id` → `agencies.id` (RESTRICT)
- `notices.offender_id` → `offenders.id` (RESTRICT)
- `offences.case_id` → `cases.id` (RESTRICT) - **Unified**
- `offences.notice_id` → `notices.id` (RESTRICT) - **Unified**
- `offences.legislation_id` → `legislation.id` (RESTRICT) - **Unified**
- `sync_logs.agency_id` → `agencies.id` (RESTRICT)

---

## Complete Schema Normalization (2025-08-16)

### Phase 1: Tables Consolidation ✅ COMPLETED

**Background**: The legacy schema had separate `breaches` (HSE) and `violations` (EA) tables that served the same purpose but with different structures.

**Solution**: Unified schema with normalized legislation lookup:

| Legacy Pattern | Unified Pattern | Benefits |
|---------------|-----------------|----------|
| `breaches` + `violations` tables | Single `offences` table | Eliminates duplication |
| Inline legislation text | `legislation` lookup table | Normalizes legislation data |
| Agency-specific patterns | Universal pattern | Supports both HSE and EA use cases |

### Phase 2: Denormalized Fields Migration ✅ COMPLETED

**Background**: Both `cases` and `notices` tables contained denormalized text fields storing breach information that should be properly normalized.

**Solution**: Migrate text fields to proper relational data:

| Denormalized Pattern | Normalized Pattern | Benefits |
|---------------------|-------------------|----------|
| `notices.offence_breaches` text | `notices` ↔ `offences` relationship | Eliminates text-based breach storage |
| `cases.offence_breaches` text | `cases` ↔ `offences` relationship | Consistent data structure |
| `cases.offence_breaches_clean` text | Unified processing via relationships | No duplicate processing logic |

### Complete Migration Results

**Tables Migration**:
- ✅ **`violations`** → `offences` (3 violations migrated)
- ✅ **`breaches`** → `offences` (0 breaches, was empty)
- ✅ **Legacy tables removed** (both `violations` and `breaches` dropped)

**Fields Migration**:
- ✅ **`notices.offence_breaches`** → 68 offence records (30 notices processed)
- ✅ **`cases.offence_breaches`** → 540 offence records (424 cases processed)
- ✅ **`cases.offence_breaches_clean`** → Same 540 records (intelligent format preference)
- ✅ **All denormalized fields removed** (3 text columns dropped)

**Final Schema State**:
- **Total Offences**: 4 → 608 (68 from notices + 540 from cases + 4 original)
- **Total Legislation**: 3 → 53 (comprehensive legislation database)
- **Computed Fields**: Added to both cases and notices for backward compatibility
- **Zero Denormalization**: No breach text fields remain in schema

### Implementation Architecture

**Data Processing Logic**:
- **Notice Format**: `"Act 1974 / 2 / 1; Regulations 2015 / 13 /"` (semicolon-separated)
- **Case Raw Format**: `"Act 1974 / 2 / 1\nRegulations 2015 / 4 / 1"` (newline-separated)
- **Case Clean Format**: `"Act 1974 37 2(1)\nRegulations 2015 51 4(1)"` (structured with reg numbers)
- **Intelligent Processing**: Prefers clean format when available, falls back to raw

**Database Optimizations**:
- **Performance**: Optimized indexes including pg_trgm for fuzzy search
- **Data Integrity**: Proper foreign key relationships and constraints
- **Flexibility**: Supports both simple (HSE) and complex (EA) violation patterns
- **Maintainability**: Single codebase for all offence-related operations

### Legacy Compatibility

**Computed Fields**: Both cases and notices now include `computed_breaches_summary` calculated fields that generate the same format as the original denormalized text fields:

```sql
-- Example computed output
"HEALTH AND SAFETY AT WORK ACT 1974 / SECTION 2 SUBSECTION 1; CONSTRUCTION REGULATIONS 2015 / SECTION 13"
```

This ensures backward compatibility for any code expecting the original text format while providing all the benefits of normalized relational data.

---

## Common Schema Issues and Solutions

### 1. Offender Deduplication
**Issue**: Multiple variations of the same company name
**Solution**: Use `normalized_name` field with automatic normalization in Ash resource

### 2. Airtable Integration
**Issue**: Maintaining sync with external Airtable data
**Solution**: `airtable_id` fields with conditional unique constraints (`WHERE airtable_id IS NOT NULL`)

### 3. Agency Code Validation
**Issue**: Ensuring valid agency codes
**Solution**: Ash constraint `one_of: [:hse, :onr, :orr, :ea]` with unique index

### 4. Event Sourcing
**Issue**: Audit trail and data evolution
**Solution**: Centralized `events` table with versioned actions for schema evolution

### 5. Configuration Management
**Issue**: Managing multiple scraping configurations
**Solution**: Single active configuration with validation constraints

---

## Database Constraints Summary

### Unique Constraints
- `users.email` (case-insensitive)
- `agencies.code`
- `offenders.normalized_name + postcode`
- `cases.case_reference` (conditional, formerly airtable_id)
- `cases.agency_id + regulator_id` (composite, cross-agency uniqueness)
- `notices.airtable_id` (conditional)
- `scraping_configs.name`
- `scrape_sessions.session_id`
- `scraped_cases.session_id + regulator_id + page`
- `metrics.period + agency_id + record_type + offender_id + legislation_id`
- `user_identities.strategy + uid + user_id`
- `tokens.jti`
- `legislation.title + year + number` (with NULLS NOT DISTINCT)
- `legislation.title + year` (with NULLS NOT DISTINCT, partial match)
- `offences.offence_reference` (conditional, unified schema)
- `offences.case_id + sequence_number` (conditional, unified schema)

### Check Constraints (via Ash validations)
- Rate limiting values > minimum thresholds
- URL format validation
- Enum value constraints on status/type fields
- Business logic validations

This schema supports the full EHS enforcement data collection and management workflow with proper normalization, constraints, and audit capabilities.

---

## Airtable to PostgreSQL Field Mapping

The original production database is a single Airtable table containing all enforcement records. This section maps the Airtable field names to their corresponding PostgreSQL table and column combinations in the normalized schema.

### Core Record Fields

| Airtable Field | PostgreSQL Table | Column | Notes |
|---------------|------------------|--------|-------|
| `agency_code` | `cases` / `notices` | `agency_id` | Mapped via `agencies.code` lookup |
| `regulator_id` | `cases` / `notices` | `regulator_id` | Direct mapping (primary identifier) |
| `notice_id` | `notices` | `regulator_id` | Alternative identifier for notices |
| `offence_action_type` | `cases` / `notices` | `offence_action_type` | Used to partition records |
| `offence_action_date` | `cases` / `notices` | `offence_action_date` | Direct mapping |

### Offender Fields (Normalized to `offenders` table)

| Airtable Field | PostgreSQL Table | Column | Notes |
|---------------|------------------|--------|-------|
| `offender_name` | `offenders` | `name` | Original company/individual name |
| `offender_name` | `offenders` | `normalized_name` | Auto-generated normalized version |
| `offender_address` | `offenders` | `address` | Business address |
| `offender_local_authority` | `offenders` | `local_authority` | Direct mapping |
| `offender_country` | `offenders` | `country` | England, Scotland, Wales, Northern Ireland |
| `offender_postcode` | `offenders` | `postcode` | Normalized to uppercase |
| `offender_main_activity` | `offenders` | `main_activity` | Direct mapping |
| `offender_sic` | `offenders` | `sic_code` | Standard Industrial Classification code |
| `offender_business_type` | `offenders` | `business_type` | Mapped to atoms: LTD→:limited_company, PLC→:plc, etc. |
| `offender_industry` | `offenders` | `industry` | Industry classification |

### Case-Specific Fields

| Airtable Field | PostgreSQL Table | Column | Notes |
|---------------|------------------|--------|-------|
| `offence_hearing_date` | `cases` | `offence_hearing_date` | Court hearing date |
| `offence_result` | `cases` | `offence_result` | Court case outcome |
| `offence_fine` | `cases` | `offence_fine` | Financial penalty amount |
| `offence_costs` | `cases` | `offence_costs` | Legal costs |
| `offence_breaches` | `cases` | `offence_breaches` | Raw breach text |
| `offence_breaches_clean` | `cases` | `offence_breaches_clean` | Processed breach text |
| `regulator_function` | `cases` | `regulator_function` | HSE division/function |
| `regulator_url` | `cases` | `regulator_url` | Direct link to case |
| `related_cases` | `cases` | `related_cases` | Connected case references |

### Notice-Specific Fields

| Airtable Field | PostgreSQL Table | Column | Notes |
|---------------|------------------|--------|-------|
| `notice_date` | `notices` | `notice_date` | Date notice was issued |
| `date_issued` | `notices` | `notice_date` | Alternative field name |
| `operative_date` | `notices` | `operative_date` | When notice becomes effective |
| `compliance_date` | `notices` | `compliance_date` | Compliance deadline |
| `notice_body` | `notices` | `notice_body` | Full notice text |
| `breach_details` | `notices` | `offence_breaches` | Notice-specific breach info |

### Record Partitioning Logic

The single Airtable table is partitioned into PostgreSQL tables based on `offence_action_type`:

| Airtable `offence_action_type` | PostgreSQL Table | Record Type |
|-------------------------------|------------------|-------------|
| `"Court Case"` | `cases` | Legal proceedings |
| `"Caution"` | `cases` | Formal warnings |
| `"Improvement Notice"` | `notices` | Compliance orders |
| `"Prohibition Notice"` | `notices` | Stop work orders |
| `"Crown Notice"` | `notices` | Crown-specific notices |
| Other enforcement types | `notices` | Various notice types |

### Derived/Computed Fields

Some PostgreSQL fields are computed from Airtable data during import:

| PostgreSQL Field | Source Logic | Notes |
|------------------|--------------|-------|
| `offenders.normalized_name` | Auto-generated from `offender_name` | Lowercase, standardized suffixes |
| `offenders.business_type` | Inferred from `offender_name` patterns | `:limited_company`, `:plc`, `:individual`, etc. |
| `agencies.id` | Lookup from `agency_code` | UUID foreign key |
| `offenders.id` | Find-or-create from name/postcode | UUID foreign key |

### Migration Strategy

1. **Single source of truth**: Airtable remains primary until migration complete
2. **Bidirectional sync**: Changes flow both ways during transition
3. **Deduplication**: PostgreSQL `normalized_name` handles company name variations
4. **Data integrity**: Foreign key constraints ensure referential integrity
5. **Audit trail**: `events` table tracks all data changes

### Schema Updates (2025-08-11)

**Latest Changes**: Added missing offender fields to support complete Airtable mapping:
- ✅ **Added fields**: `address`, `country`, `sic_code` 
- ✅ **Business type mapping**: Airtable strings → PostgreSQL atoms (LTD → :limited_company, etc.)
- ✅ **Country capture**: Now captures country from HSE search criteria (England, Scotland, Wales, Northern Ireland)

**Production Update**: Use `scripts/update_offender_fields.exs` to backfill existing production records with missing field data from Airtable.

### Common Field Naming Patterns

- **Dates**: Always use full descriptive names (`offence_action_date` not `action_date`)
- **Money**: Use `offence_fine` and `offence_costs` (separate fields)
- **IDs**: `regulator_id` for external identifiers, `id` for internal UUIDs
- **References**: `_id` suffix for foreign keys, `_url` for external links
- **Text processing**: Raw (`offence_breaches`) and clean (`offence_breaches_clean`) versions

---

## HSE Case Scraping Data Mapping

This section maps the data flow from the legacy HSE case scraping through the refactored scraper to the PostgreSQL database.

### Legacy HSECase Struct → Refactored ScrapedCase → PostgreSQL Cases Table

| Legacy HSECase Field | Refactored ScrapedCase Field | PostgreSQL Column | Notes |
|---------------------|------------------------------|-------------------|-------|
| `:regulator` | _Not captured_ | _Via agency lookup_ | Always "HSE" for HSE cases |
| `:regulator_id` | `:regulator_id` | `regulator_id` | HSE internal case reference |
| `:regulator_function` | `:regulator_function` | `regulator_function` | HSE division/function |
| `:regulator_regulator_function` | _Not needed_ | _Computed_ | "HSE_" + function |
| `:regulator_url` | _Not captured_ | `regulator_url` | Link to HSE case page |
| `:offender_name` | `:offender_name` | `offenders.name` | Via offender normalization |
| `:offender_local_authority` | `:offender_local_authority` | `offenders.local_authority` | Via offender record |
| `:offender_main_activity` | `:offender_main_activity` | `offenders.main_activity` | Via offender record |
| `:offender_business_type` | _Not captured_ | `offenders.business_type` | Inferred during processing |
| `:offender_index` | _Not used_ | _Not stored_ | Legacy field |
| `:offender_industry` | `:offender_industry` | `offenders.industry` | Via offender record |
| `:offence_result` | `:offence_result` | `offence_result` | Court case outcome |
| `:offence_fine` | `:offence_fine` | `offence_fine` | Financial penalty (Decimal) |
| `:offence_costs` | `:offence_costs` | `offence_costs` | Legal costs (Decimal) |
| `:offence_action_type` | _Not captured_ | `offence_action_type` | Inferred as "Court Case" |
| `:offence_action_date` | `:offence_action_date` | `offence_action_date` | Enforcement action date |
| `:offence_hearing_date` | `:offence_hearing_date` | `offence_hearing_date` | **Now captured** via breach scraping |
| `:offence_number` | `:offence_number` | _Not stored directly_ | **Now captured** breach count |
| `:offence_breaches` | `:offence_breaches` | `offence_breaches` | **Now captured** via breach scraping |
| `:offence_breaches_clean` | _Processing stage_ | `offence_breaches_clean` | Processed during case creation |
| `:offence_lrt` | _Not applicable_ | _Not used_ | Legacy field for legislation lookup |
| `:offender_related_cases` | `:related_cases` | `related_cases` | **Now captured** via related case scraping |

### New Data Captured by Enhanced Scraper

The refactored scraper now captures **all the data** that the legacy version extracted, plus additional metadata:

#### **Previously Missing (Now Captured):**
- ✅ **Breach Details**: Full breach descriptions from separate breach pages
- ✅ **Hearing Dates**: Court hearing dates from breach data
- ✅ **Related Cases**: Connected case references from related case pages
- ✅ **Breach Count**: Number of breaches (`offence_number`)

#### **Additional Metadata (New):**
- ✅ **Scrape Metadata**: `page_number`, `scrape_timestamp` for tracking
- ✅ **Error Handling**: Robust retry logic and rate limiting
- ✅ **Structured Processing**: Clean separation of scraping and database operations

### Data Flow Process

```
HSE Website Pages → ScrapedCase Struct → CaseProcessor → PostgreSQL
     ↓                    ↓                    ↓              ↓
1. Case list page     Raw scraped data    Processed data   Normalized tables
2. Case detail page   + breach details    + offender       cases + offenders  
3. Breach pages       + related cases     matching         + relationships
4. Related case pages + enriched data     + validation     + audit events
```

### Key Enhancements in Refactored Version

1. **Complete Data Extraction**: Now extracts all data fields from legacy version
2. **Robust Architecture**: Proper error handling, rate limiting, retries
3. **Ash Integration**: Uses Ash resources for database operations and business logic
4. **Data Normalization**: Separates offenders into dedicated table with deduplication
5. **Event Sourcing**: All database changes tracked in events table
6. **Type Safety**: Uses Decimal for monetary amounts, proper date parsing
7. **Testing**: Comprehensive test coverage with proper mocking

The enhanced scraper maintains **100% data compatibility** with the legacy version while providing significant architectural improvements for reliability and maintainability.