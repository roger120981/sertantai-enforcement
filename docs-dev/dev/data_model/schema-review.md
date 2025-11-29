# Schema Review: Cases vs Notices - Unified Enforcement Action Model

**Date**: 2025-11-20
**Context**: GitHub Issue #2 - AI Context Generation feature planning
**Session**: `.claude/sessions/2025-11-20-Github-Issue-2.md`

---

## 📋 Executive Summary

**Recommendation: KEEP SEPARATE TABLES** ✅

After comprehensive analysis of the schema, data patterns, scraping logic, and business domain, the current two-table approach (Cases + Notices) should be **maintained**. While they share some commonalities, Cases and Notices represent fundamentally different regulatory concepts with distinct lifecycles, attributes, and user workflows.

**Key Finding**: The apparent similarity (both tied to offenders, agencies, and offences) masks significant semantic and operational differences that would make a unified table complex, error-prone, and harder to maintain.

---

## 🔍 Analysis Summary

### Current Architecture
```
Enforcement Actions
├── Cases (Court Actions)
│   ├── Court proceedings with fines/costs
│   ├── Legal outcomes (guilty/not guilty)
│   └── Financial penalties
└── Notices (Regulatory Notices)
    ├── Improvement notices
    ├── Prohibition notices
    ├── Enforcement notices
    └── Compliance requirements
```

### Data Distribution (as of 2025-11-20)
- **Cases**: 0 records currently (historically thousands from HSE/EA)
- **Notices**: 293 records (2013-2025 date range)
  - Enforcement Notice: 273
  - Improvement Notice: 17
  - Prohibition Notice Immediate: 3

---

## 🎯 Core Question: Why Are They Separate?

### 1. **Fundamentally Different Regulatory Actions**

**Cases = Prosecutions (Retrospective Justice)**
- **Legal Proceedings**: Court cases resulting from enforcement investigations
- **Outcome**: Criminal or civil judgments (guilty, not guilty, appeal)
- **Financial Impact**: Fines, costs, compensation ordered by court
- **Timeline**: `offence_action_date` (when offense occurred) → `offence_hearing_date` (court date)
- **Finality**: Concluded legal proceedings with binding outcomes

**Notices = Compliance Orders (Proactive Prevention)**
- **Regulatory Orders**: Direct instructions from regulators to prevent harm
- **Purpose**: Stop dangerous practices, require improvements, ensure compliance
- **Timeline**: `notice_date` (issued) → `operative_date` (comes into force) → `compliance_date` (must comply by)
- **Ongoing**: Can be open-ended until compliance achieved
- **No Financial Penalty**: Fines only if notice violation leads to prosecution (becomes a Case)

**Real-World Analogy**:
- **Case**: "You were found guilty of safety violations and fined £50,000"
- **Notice**: "Your machinery is unsafe - you must fix it within 30 days or we'll shut you down"

### 2. **Distinct Attribute Sets**

#### Case-Specific Fields (Cases Only)
```elixir
# Court proceedings
:offence_result          # "Guilty", "Not Guilty", "Appeal dismissed"
:offence_fine            # £50,000 - court-ordered fine
:offence_costs           # £12,500 - prosecution costs
:offence_hearing_date    # Date of court hearing
:case_reference          # Court case reference number
:related_cases           # Other cases in same prosecution

# EA-specific litigation fields
:ea_event_reference      # EA event tracking ID
:ea_total_violation_count # Number of separate violations prosecuted
:is_ea_multi_violation   # Boolean flag for multi-count cases
```

#### Notice-Specific Fields (Notices Only)
```elixir
# Regulatory compliance
:notice_date             # Date notice was issued
:operative_date          # Date notice comes into force
:compliance_date         # Deadline for compliance
:notice_body             # Full text of regulatory order
:offence_action_type     # "Improvement Notice", "Prohibition Notice", etc.
:regulator_ref_number    # Internal regulator reference

# EA-specific enforcement fields
:legal_act               # Which Act the notice is issued under
:legal_section           # Specific section of the Act
:regulator_event_reference # EA event tracking
```

#### Shared Fields (Both)
```elixir
# Common enforcement metadata
:agency_id              # HSE, EA, SEPA, etc.
:offender_id            # Company/individual receiving action
:regulator_id           # Agency's internal ID
:offence_action_date    # Date of the enforcement action
:offence_breaches       # Text description of violations
:environmental_impact   # EA: "none", "minor", "major"
:environmental_receptor # EA: "land", "water", "air"
:regulator_function     # Agency function (e.g., "Industrial", "Construction")
:url                    # Link to public register entry
```

**Analysis**: Only ~40% field overlap. Most critical fields are type-specific.

### 3. **Different Query Patterns & User Workflows**

#### Case-Focused Queries
```elixir
# Financial analysis
total_fines = Cases |> where([c], c.offence_fine > 100000) |> sum(:offence_fine)

# Outcome tracking
guilty_rate = Cases |> where([c], c.offence_result == "Guilty") |> count() / total_cases

# Court performance
avg_days_to_hearing = Cases |> avg(hearing_date - action_date)

# Benchmark analysis (for AI enrichment)
similar_fines = Cases |> where(industry: ^industry, breach_type: ^breach) |> select(:offence_fine)
```

#### Notice-Focused Queries
```elixir
# Active compliance monitoring
active_notices = Notices |> where([n], n.compliance_date > ^today)

# Notice type distribution
notice_types = Notices |> group_by(:offence_action_type) |> count()

# Enforcement escalation
repeat_offenders = Notices |> group_by(:offender_id) |> having(count() > 3)

# Regulator performance
avg_compliance_period = Notices |> avg(compliance_date - notice_date)
```

**User Personas with Different Needs**:
- **Compliance Officers**: Focus on open notices, compliance deadlines
- **Finance Teams**: Focus on cases, fine amounts, total costs
- **Legal Teams**: Focus on case outcomes, appeals, related prosecutions
- **Regulators**: Need both, but in different contexts

### 4. **Scraping & Processing Logic Differences**

#### HSE Case Processing (`case_processor.ex:67`)
```elixir
offence_action_type: "Court Case"  # Hardcoded - cases are always court cases
```

#### HSE Notice Processing (`notice_processor.ex:94`)
```elixir
offence_action_type: enriched_notice.offence_action_type  # Dynamic - varies by notice type
```

**Key Observation**: The `offence_action_type` field has completely different semantics:
- **Cases**: Always "Court Case" (discriminator for query filtering)
- **Notices**: Actual notice type ("Improvement Notice", "Prohibition Notice", etc.)

**If unified**, we'd need:
```elixir
:enforcement_type     # "case" or "notice" (discriminator)
:action_subtype       # "Court Case" OR "Improvement Notice" OR "Prohibition Notice"
```

This introduces:
- **Semantic confusion**: Same field, different meanings
- **Validation complexity**: Conditional validation based on discriminator
- **Query complexity**: Every query needs `where(enforcement_type: "case")` filter

### 5. **Relationship to Offences Table**

Both Cases and Notices relate to the unified `Offences` table:

```elixir
# offences.ex (Unified breach/violation tracking)
belongs_to :case, EhsEnforcement.Enforcement.Case
belongs_to :notice, EhsEnforcement.Enforcement.Notice
belongs_to :legislation, EhsEnforcement.Enforcement.Legislation

# Validation: At least one parent required
validate(fn changeset, _context ->
  if is_nil(case_id) and is_nil(notice_id) do
    {:error, "Offence must be associated with either a case or notice"}
  end
end)
```

**Why This Works**:
- Offences can be linked to Cases (prosecuted violations)
- Offences can be linked to Notices (violations requiring correction)
- Separate parent tables allow proper relationship semantics
- AI enrichment can analyze offences across both contexts

**If Unified**: We'd still need to distinguish "offences that went to court" from "offences requiring compliance" - essentially recreating the separation at the offence level.

---

## 🔧 Technical Considerations

### Database Constraints & Indexes

#### Cases Table Constraints
```sql
-- Financial validation
CHECK (offence_fine >= 0 OR offence_fine IS NULL)
CHECK (offence_costs >= 0 OR offence_costs IS NULL)

-- Logical date ordering
CHECK (offence_hearing_date >= offence_action_date OR offence_hearing_date IS NULL)

-- Unique court case per agency
UNIQUE (agency_id, regulator_id)
```

#### Notices Table Constraints
```sql
-- Compliance timeline validation
CHECK (compliance_date >= notice_date OR compliance_date IS NULL)
CHECK (operative_date >= notice_date OR operative_date IS NULL)

-- Unique notice per agency (when regulator_id present)
UNIQUE (regulator_id, agency_id) WHERE regulator_id IS NOT NULL
```

**Analysis**: Different business rules require different constraints. A unified table would need complex conditional constraints.

### ElectricSQL Sync Considerations

Both tables are in ElectricSQL publication:
```elixir
# cases.ex & notices.ex
postgres do
  # ...
end

# Publications
Publications:
  "electric_publication"
  "electric_publication_default"
```

**Sync Performance**:
- **Separate Tables**: Clients can selectively sync cases OR notices based on user role
- **Unified Table**: Would require syncing all enforcement actions even if user only needs one type

**Real-World Impact**:
- **SME Compliance Dashboard**: Only needs notices (active compliance requirements)
- **Legal/Finance Dashboard**: Only needs cases (financial penalties, outcomes)
- **Current Architecture**: Allows targeted sync, reducing bandwidth and local storage
- **Unified Architecture**: Forces unnecessary data transfer

### Query Performance & Indexing

#### Current Index Strategy
```sql
-- Cases: Optimized for financial analysis
CREATE INDEX cases_offence_fine_index ON cases(offence_fine);
CREATE INDEX cases_offence_action_date_index ON cases(offence_action_date);

-- Notices: Optimized for compliance tracking
CREATE INDEX notices_offence_action_type_index ON notices(offence_action_type);
CREATE INDEX notices_notice_body_gin_trgm ON notices(notice_body) USING GIN;
```

**Query Examples**:
```sql
-- Case query: Fast with dedicated index
SELECT * FROM cases WHERE offence_fine > 50000;

-- Notice query: Fast with dedicated index
SELECT * FROM notices WHERE offence_action_type = 'Improvement Notice';
```

**If Unified**:
```sql
-- Would need composite index on discriminator + filter field
CREATE INDEX enforcement_type_fine ON enforcement_actions(enforcement_type, offence_fine);

-- Every query needs discriminator filter
SELECT * FROM enforcement_actions
WHERE enforcement_type = 'case' AND offence_fine > 50000;
```

**Performance Cost**: Additional discriminator column in every index, larger index size, more complex query plans.

---

## 🤖 AI Context Generation Impact

### For GitHub Issue #2: AI Enrichment Feature

The AI enrichment service needs to:
1. Generate regulation cross-references
2. Calculate industry benchmarks
3. Identify historical patterns
4. Create plain language summaries

**How Schema Separation Helps**:

#### Benchmark Analysis
```elixir
# Cases: Financial benchmarks
def generate_benchmarks(%{case_id: id}) do
  case = Enforcement.get_case!(id)

  similar_cases =
    Case
    |> Ash.Query.filter(
      industry == ^case.offender.industry and
      not is_nil(offence_fine)
    )
    |> Ash.read!()

  %{
    average_fine: calculate_average(similar_cases, :offence_fine),
    percentile_ranking: calculate_percentile(case.offence_fine, similar_cases),
    max_fine: Enum.max_by(similar_cases, & &1.offence_fine)
  }
end

# Notices: Compliance pattern analysis
def generate_benchmarks(%{notice_id: id}) do
  notice = Enforcement.get_notice!(id)

  similar_notices =
    Notice
    |> Ash.Query.filter(
      offence_action_type == ^notice.offence_action_type and
      not is_nil(compliance_date)
    )
    |> Ash.read!()

  %{
    avg_compliance_period: calculate_avg_days(similar_notices),
    notice_escalation_rate: calculate_escalation_rate(similar_notices),
    repeat_offender_rate: calculate_repeat_rate(similar_notices)
  }
end
```

**Separate tables allow**:
- Type-specific benchmark calculations
- Cleaner AI prompts (no need to explain discriminator field)
- Simpler confidence scoring (no conditional logic)

#### Plain Language Summaries
```elixir
# Case summary (legal outcome focus)
"""
#{offender.name} was prosecuted by #{agency.name} for #{breach_summary}.
The court found them guilty on #{hearing_date} and imposed a fine of £#{fine}
plus £#{costs} in costs.
"""

# Notice summary (compliance focus)
"""
#{offender.name} was issued a #{notice_type} by #{agency.name} on #{notice_date}
requiring them to #{compliance_summary} by #{compliance_date}.
"""
```

**Unified table would require**:
```elixir
case enforcement_action.type do
  "case" -> generate_case_summary(enforcement_action)
  "notice" -> generate_notice_summary(enforcement_action)
end
```

This adds complexity without benefit - AI enrichment service would still need separate logic paths.

---

## 📊 Alternative Architectures Considered

### Option 1: Single Table Inheritance (STI)
```elixir
defmodule EnforcementAction do
  attribute :type, :atom  # :case or :notice

  # All fields from both tables as nullable
  attribute :offence_fine, :decimal          # NULL for notices
  attribute :offence_hearing_date, :date     # NULL for notices
  attribute :notice_date, :date              # NULL for cases
  attribute :compliance_date, :date          # NULL for cases
  # ...
end
```

**Problems**:
- ❌ 15+ nullable fields per record (sparse columns)
- ❌ Cannot enforce type-specific constraints in database
- ❌ Confusing for developers (which fields apply to which type?)
- ❌ Index bloat (indices include irrelevant NULL columns)
- ❌ Migration nightmare (existing data + references)

### Option 2: PostgreSQL Partitioning
```sql
CREATE TABLE enforcement_actions (...) PARTITION BY LIST (enforcement_type);
CREATE TABLE cases PARTITION OF enforcement_actions FOR VALUES IN ('case');
CREATE TABLE notices PARTITION OF enforcement_actions FOR VALUES IN ('notice');
```

**Problems**:
- ❌ Still have sparse column problem (shared schema)
- ❌ Ash Framework doesn't support partitioned tables well
- ❌ ElectricSQL sync complications with partitions
- ❌ Adds database complexity without solving semantic issues

### Option 3: Polymorphic Belongs-To Pattern
```elixir
defmodule Offence do
  # Instead of separate case_id and notice_id
  attribute :enforceable_type, :string  # "Case" or "Notice"
  attribute :enforceable_id, :uuid
end
```

**Problems**:
- ❌ Loses foreign key referential integrity
- ❌ Cannot use database-level cascading deletes
- ❌ Ash doesn't have built-in polymorphic relationship support
- ❌ Queries become significantly more complex

---

## ✅ Benefits of Current Two-Table Architecture

### 1. **Semantic Clarity**
- Code is self-documenting: `Case` = prosecution, `Notice` = compliance order
- New developers immediately understand the domain model
- No mental overhead for discriminator field management

### 2. **Type Safety**
- Compile-time guarantees: Can't accidentally query case-specific fields on notice
- Ash validations can be type-specific without conditional logic
- Database constraints enforce business rules at lowest level

### 3. **Query Simplicity**
```elixir
# Current (clean)
Enforcement.list_cases()
Enforcement.list_notices()

# Unified (complex)
Enforcement.list_enforcement_actions(type: :case)
Enforcement.list_enforcement_actions(type: :notice)

# Every query needs type filter
```

### 4. **Optimized Indexes**
- Indices tuned for specific query patterns
- No discriminator column overhead
- Better query planner performance

### 5. **Scraping Logic Separation**
```elixir
# Current: Clean separation
EhsEnforcement.Scraping.Hse.CaseProcessor
EhsEnforcement.Scraping.Hse.NoticeProcessor

# Unified: Would need conditionals everywhere
EhsEnforcement.Scraping.Hse.EnforcementProcessor
  |> process_by_type(:case)
  |> process_by_type(:notice)
```

### 6. **ElectricSQL Selective Sync**
- Clients can choose which table to sync
- Reduces bandwidth and storage for role-specific apps
- Simpler sync shape definitions

### 7. **Future Agency Expansion**
Different agencies may have different action types:
- **SEPA (Scottish EPA)**: May have unique notice types
- **Natural Resources Wales**: May have Welsh-specific legal actions
- **Future agencies**: May introduce new enforcement mechanisms

Separate tables allow adding agency-specific fields without affecting all enforcement actions.

---

## 🚨 Migration Risk Assessment

**If we unified the schema now:**

### Immediate Risks
- ❌ **Breaking Change**: All existing Ash resources, queries, and LiveViews need rewrite
- ❌ **Data Migration**: 293 notices + historical cases need type discriminator added
- ❌ **Foreign Key Hell**: Offences table references both `case_id` and `notice_id` - need polymorphic rewrite
- ❌ **ElectricSQL Reconfiguration**: Sync shapes would break for all clients
- ❌ **Scraping Pipeline Rewrite**: All HSE/EA scrapers and processors need refactoring

### Estimated Migration Cost
- **Development Time**: 2-3 weeks (rewrites + testing)
- **Risk**: High (breaking changes across entire system)
- **Benefit**: Minimal (no new functionality, marginal query simplification)
- **Opportunity Cost**: Delays AI enrichment feature (GitHub Issue #2)

### Rollback Complexity
Once unified, splitting back would be even more expensive. Current architecture is reversible if needed later.

---

## 📈 Recommendation: Maintain Separation

### Keep Current Schema ✅

**Rationale**:
1. **Domain Alignment**: Cases and Notices are fundamentally different regulatory concepts
2. **Query Clarity**: Separate tables = simpler, more performant queries
3. **Type Safety**: Compile-time guarantees and database constraints
4. **Migration Cost**: Zero (no breaking changes)
5. **AI Enrichment**: Can proceed immediately with type-specific enrichment logic
6. **ElectricSQL**: Maintains selective sync capability for role-based apps
7. **Future Flexibility**: Easier to add agency-specific fields per type

### For AI Context Generation (Issue #2)

The enrichment service should:
```elixir
defmodule EhsEnforcement.AI.EnrichmentService do
  def enrich_case(case_id) do
    case = Enforcement.get_case!(case_id)

    %{
      regulation_links: analyze_regulations(case.offence_breaches),
      benchmark_analysis: generate_case_benchmarks(case),  # Financial focus
      pattern_detection: find_similar_cases(case),
      layperson_summary: generate_case_summary(case),      # Legal outcome focus
      professional_summary: generate_legal_summary(case),
      confidence_scores: calculate_confidence()
    }
  end

  def enrich_notice(notice_id) do
    notice = Enforcement.get_notice!(notice_id)

    %{
      regulation_links: analyze_regulations(notice.offence_breaches),
      benchmark_analysis: generate_notice_benchmarks(notice),  # Compliance focus
      pattern_detection: find_similar_notices(notice),
      layperson_summary: generate_notice_summary(notice),      # Compliance focus
      professional_summary: generate_regulatory_summary(notice),
      confidence_scores: calculate_confidence()
    }
  end
end
```

**Benefits**:
- Type-specific enrichment logic (different benchmarks, different summaries)
- Cleaner AI prompts (no need to explain domain model complexity)
- Can add `CaseEnrichment` and `NoticeEnrichment` tables if different enrichment attributes needed

---

## 🔮 Future Considerations

### If Unified Table Becomes Necessary

**When might we reconsider?**
- If 80%+ of queries need both cases AND notices together
- If agencies start issuing hybrid actions that blur the distinction
- If type-specific fields drop below 20% of total schema

**How to revisit decision:**
1. Track query patterns in production
2. Monitor schema evolution over 6-12 months
3. Re-evaluate if business requirements change significantly

### Compromise: Unified Read Model (CQRS)

If unified querying becomes critical:
```elixir
# Keep separate write models (cases, notices)
# Add unified read model for cross-type queries
defmodule EnforcementActionView do
  # Materialized view or Ash calculation
  # Combines cases + notices for dashboard display
end
```

This gives benefits of both approaches:
- ✅ Maintains type-specific write models
- ✅ Provides unified read view for cross-type queries
- ✅ No breaking changes to existing schema

---

## 🎯 Action Items

### Immediate (For Issue #2 Implementation)
1. ✅ Proceed with AI enrichment using separate Case/Notice resources
2. ✅ Create `case_enrichments` table (linked to cases)
3. ✅ Create `notice_enrichments` table (linked to notices) OR use same enrichment table with polymorphic association
4. ✅ Implement type-specific benchmark calculations
5. ✅ Design type-specific AI prompts for summaries

### Future Monitoring
1. Track query patterns - are users frequently needing cross-type queries?
2. Monitor schema evolution - are type-specific fields growing or shrinking?
3. Evaluate after 6 months - has business domain understanding changed?

### Documentation Updates
1. Update CLAUDE.md to document schema separation rationale
2. Add comments in Case/Notice resources explaining relationship
3. Document AI enrichment approach for both types

---

## 📚 References

### Codebase Files Reviewed
- `lib/ehs_enforcement/enforcement/resources/case.ex` (862 lines)
- `lib/ehs_enforcement/enforcement/resources/notice.ex` (378 lines)
- `lib/ehs_enforcement/enforcement/resources/offence.ex` (298 lines - unified breaches)
- `lib/ehs_enforcement/enforcement/resources/offender.ex` (768 lines)
- `lib/ehs_enforcement/scraping/hse/case_processor.ex`
- `lib/ehs_enforcement/scraping/hse/notice_processor.ex`
- `lib/ehs_enforcement/scraping/CLAUDE.md` (scraping architecture)

### Database Analysis
- PostgreSQL schema inspection (both tables)
- Index analysis and performance implications
- Constraint validation and business rule enforcement
- ElectricSQL publication configuration

### External Context
- UK regulatory framework (HSE, EA, SEPA)
- Enforcement action legal definitions
- Compliance monitoring workflows
- Financial reporting requirements

---

**Document Version**: 1.0
**Author**: Claude (AI Assistant)
**Review Date**: 2025-11-20
**Next Review**: 2026-05-20 (6 months)
