# Contract Pre-Qualification Intelligence

**Duration**: 3 weeks | **Priority**: Phase 2 (Intelligence) | **Revenue**: Enterprise Feature

> **Vision**: Transform how procurement teams evaluate supplier EHS compliance - from checkbox exercises to evidence-based risk intelligence.

---

## 📋 Executive Summary

### The Problem

Every major contract in construction, manufacturing, utilities, and public sector includes EHS pre-qualification requirements. Bidders must declare:

- *"Have you been subject to any enforcement action in the past 5 years?"*
- *"List any prosecutions, improvement notices, or prohibition notices"*
- *"Describe corrective actions taken following any enforcement"*

**Current Reality**:
- **Bidders**: Can understate or omit enforcement history (no verification)
- **Procurement Teams**: Manual Google searches, no systematic verification
- **Outcome**: Risky suppliers slip through; compliant suppliers can't demonstrate value

### The Solution

**Pre-Qualification Intelligence** gives procurement teams instant access to:
1. **Verified enforcement history** for any UK company
2. **AI-enriched context** explaining what happened and why it matters
3. **Offender responses** - what the company says about their incidents
4. **Comparative benchmarking** - how does this supplier compare to industry peers?
5. **Risk scoring** - quantified assessment for tender evaluation

---

## 🎯 User Stories

### Epic: Procurement Team Intelligence

#### Story 1: Supplier Enforcement Lookup
**As a** procurement officer evaluating tender submissions,
**I want to** search for a company's enforcement history by name or Companies House number,
**So that** I can verify their PQQ declarations are accurate and complete.

**Acceptance Criteria**:
- Search by company name (fuzzy matching)
- Search by Companies House number (exact match)
- Search by trading name / subsidiary names
- Display all enforcement actions (prosecutions, notices, court cases)
- Show timeline of enforcement activity
- Export results to PDF for tender documentation

#### Story 2: Declaration Verification
**As a** procurement officer,
**I want to** compare a supplier's self-declared enforcement history against our database,
**So that** I can identify omissions or discrepancies.

**Acceptance Criteria**:
- Upload PQQ response (PDF or structured data)
- AI extracts declared enforcement history
- System matches against known enforcement records
- Highlight discrepancies (missing cases, incorrect dates, understated fines)
- Generate verification report with findings
- Flag severity (minor discrepancy vs material omission)

#### Story 3: Supplier Risk Score
**As a** procurement manager,
**I want to** see a quantified risk score for each supplier,
**So that** I can make consistent, defensible decisions across the tender panel.

**Acceptance Criteria**:
- Composite risk score (0-100)
- Breakdown by dimension:
  - Enforcement frequency (last 5 years)
  - Severity (fines, fatalities, prohibition notices)
  - Recency (more recent = higher risk)
  - Sector-adjusted (compare to industry baseline)
  - Response quality (have they submitted context?)
- Score explanation in plain language
- Comparison to other bidders (anonymized)

#### Story 4: Offender Context Review
**As a** tender evaluator,
**I want to** read verified company responses to their enforcement actions,
**So that** I can assess their safety culture and corrective actions.

**Acceptance Criteria**:
- View company-submitted context for each enforcement action
- See AI-structured narrative (what happened, why, what changed)
- Review supporting evidence (certifications, audit reports)
- Star rating from other procurement professionals
- Timeline showing improvement journey
- Professional commentary from EHS experts

#### Story 5: Industry Benchmarking
**As a** procurement director,
**I want to** understand how a supplier's enforcement record compares to industry norms,
**So that** I can set realistic expectations for different sectors.

**Acceptance Criteria**:
- Sector-specific benchmarks (construction, waste, manufacturing, etc.)
- Percentile ranking within sector
- Trend analysis (improving/declining vs peers)
- "Red flags" alert for outliers (>2 standard deviations)
- Contextual factors (company size, geographic spread, project complexity)

---

### Epic: Supplier Self-Service

#### Story 6: Pre-Qualification Portfolio
**As a** supplier bidding for contracts,
**I want to** maintain a verified enforcement portfolio,
**So that** I can respond to PQQ questions quickly and credibly.

**Acceptance Criteria**:
- Dashboard showing all linked enforcement records
- Add context/response to each record
- Upload supporting documents (IOSH certificates, audit reports, HSE letters)
- Generate pre-formatted PQQ response
- Track which procurement teams have viewed profile
- Request professional endorsements

#### Story 7: Improvement Journey Showcase
**As a** supplier with past enforcement,
**I want to** demonstrate my safety improvements over time,
**So that** procurement teams see we've learned and improved.

**Acceptance Criteria**:
- Timeline visualization of enforcement → response → improvement
- Upload evidence of corrective actions
- Link to safety certifications (ISO 45001, SafeContractor, CHAS)
- Display safety KPIs (incident rates over time)
- Professional testimonials (EHS consultants, auditors)
- AI-generated improvement narrative

---

### Epic: Enterprise Integration

#### Story 8: Tender Management System Integration
**As an** enterprise procurement team,
**I want to** integrate pre-qualification intelligence into our existing tender system,
**So that** verification happens automatically within our workflow.

**Acceptance Criteria**:
- API endpoint: `POST /api/v1/prequalification/verify`
- Webhook notifications for new enforcement data
- Bulk company lookup (CSV upload)
- Integration guides for: SAP Ariba, Oracle Procurement, Jaggaer
- SSO/SAML authentication
- Audit trail for compliance

#### Story 9: Custom Risk Weighting
**As an** enterprise customer,
**I want to** configure risk scoring weights for our organization,
**So that** the assessment reflects our specific risk appetite.

**Acceptance Criteria**:
- Configurable weight sliders for each risk dimension
- Custom penalty thresholds (e.g., "any fatality = auto-fail")
- Sector-specific profiles (different weights for high-risk vs office work)
- Save organizational presets
- Override individual assessments with justification

---

## 🏗️ Technical Architecture

### Data Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pre-Qualification System                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐         ┌─────────────────┐               │
│  │   Companies     │────────▶│  Enforcement    │               │
│  │   (Offenders)   │         │  Cases/Notices  │               │
│  └────────┬────────┘         └────────┬────────┘               │
│           │                           │                         │
│           │                           ▼                         │
│           │                  ┌─────────────────┐               │
│           │                  │  AI Enrichment  │               │
│           │                  │  (Context)      │               │
│           │                  └────────┬────────┘               │
│           │                           │                         │
│           ▼                           ▼                         │
│  ┌─────────────────┐         ┌─────────────────┐               │
│  │   Supplier      │         │  Offender       │               │
│  │   Portfolios    │◀───────▶│  Responses      │               │
│  └────────┬────────┘         └─────────────────┘               │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐         ┌─────────────────┐               │
│  │   Risk Scores   │         │  Verification   │               │
│  │   (Calculated)  │         │  Reports        │               │
│  └─────────────────┘         └─────────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### New Ash Resources

```elixir
# Supplier portfolio linking company to enforcement records
defmodule EhsEnforcement.PreQualification.SupplierPortfolio do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :companies_house_number, :string
    attribute :company_name, :string
    attribute :trading_names, {:array, :string}
    attribute :sector, :atom  # :construction, :manufacturing, :waste, etc.
    attribute :employee_count, :integer
    attribute :annual_turnover, :decimal
    attribute :verified_at, :utc_datetime
    attribute :verification_method, :atom  # :companies_house, :manual, :sso
  end

  relationships do
    has_many :enforcement_links, EnforcementLink
    has_many :portfolio_documents, PortfolioDocument
    has_many :risk_assessments, RiskAssessment
    belongs_to :claiming_user, User  # Who manages this portfolio
  end
end

# Link between portfolio and enforcement records
defmodule EhsEnforcement.PreQualification.EnforcementLink do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :link_confidence, :float  # AI confidence in company match
    attribute :link_method, :atom  # :exact_match, :fuzzy_match, :manual
    attribute :disputed, :boolean, default: false
    attribute :dispute_reason, :string
  end

  relationships do
    belongs_to :portfolio, SupplierPortfolio
    belongs_to :case, Case
    belongs_to :notice, Notice
    has_one :offender_response, OffenderResponse
  end
end

# Calculated risk assessment
defmodule EhsEnforcement.PreQualification.RiskAssessment do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :overall_score, :integer  # 0-100
    attribute :frequency_score, :integer
    attribute :severity_score, :integer
    attribute :recency_score, :integer
    attribute :sector_adjusted_score, :integer
    attribute :response_quality_score, :integer
    attribute :score_explanation, :string  # AI-generated plain language
    attribute :red_flags, {:array, :string}
    attribute :assessed_at, :utc_datetime
    attribute :valid_until, :utc_datetime
  end

  relationships do
    belongs_to :portfolio, SupplierPortfolio
    belongs_to :assessed_by, User  # null = system-generated
  end
end

# Verification report for tender documentation
defmodule EhsEnforcement.PreQualification.VerificationReport do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :declared_records, {:array, :map}  # What supplier claimed
    attribute :found_records, {:array, :map}     # What we found
    attribute :discrepancies, {:array, :map}     # Differences
    attribute :verdict, :atom  # :verified, :discrepancies_found, :material_omission
    attribute :report_pdf_url, :string
    attribute :generated_at, :utc_datetime
  end

  relationships do
    belongs_to :portfolio, SupplierPortfolio
    belongs_to :generated_by, User
  end
end
```

### Risk Scoring Algorithm

```elixir
defmodule EhsEnforcement.PreQualification.RiskCalculator do
  @moduledoc """
  Calculate composite risk score for supplier pre-qualification.
  
  Score Components (default weights):
  - Frequency (25%): Number of enforcement actions per year
  - Severity (30%): Fine amounts, fatalities, prohibition notices
  - Recency (20%): Time since most recent enforcement
  - Sector-Adjusted (15%): Comparison to industry baseline
  - Response Quality (10%): Has supplier provided context?
  """

  @default_weights %{
    frequency: 0.25,
    severity: 0.30,
    recency: 0.20,
    sector_adjusted: 0.15,
    response_quality: 0.10
  }

  def calculate(portfolio, opts \\ []) do
    weights = Keyword.get(opts, :weights, @default_weights)
    lookback_years = Keyword.get(opts, :lookback_years, 5)
    
    enforcement_records = get_enforcement_records(portfolio, lookback_years)
    sector_baseline = get_sector_baseline(portfolio.sector)
    
    scores = %{
      frequency: calculate_frequency_score(enforcement_records, lookback_years),
      severity: calculate_severity_score(enforcement_records),
      recency: calculate_recency_score(enforcement_records),
      sector_adjusted: calculate_sector_score(enforcement_records, sector_baseline),
      response_quality: calculate_response_score(enforcement_records)
    }
    
    overall = weighted_average(scores, weights)
    red_flags = identify_red_flags(enforcement_records)
    explanation = generate_explanation(scores, red_flags)
    
    %{
      overall_score: overall,
      component_scores: scores,
      red_flags: red_flags,
      explanation: explanation
    }
  end

  defp calculate_severity_score(records) do
    # Weighted by: fatalities (critical), prohibition notices (high), 
    # improvement notices (medium), fines (scaled)
  end

  defp identify_red_flags(records) do
    flags = []
    
    # Fatality in last 5 years
    if Enum.any?(records, &has_fatality?/1), do: flags ++ ["FATALITY_RECORDED"]
    
    # Multiple prohibition notices
    prohibition_count = Enum.count(records, &is_prohibition?/1)
    if prohibition_count >= 2, do: flags ++ ["MULTIPLE_PROHIBITION_NOTICES"]
    
    # Repeat offender (same regulation violated multiple times)
    if has_repeat_violations?(records), do: flags ++ ["REPEAT_VIOLATIONS"]
    
    # Recent enforcement (within 12 months)
    if has_recent_enforcement?(records, 12), do: flags ++ ["RECENT_ENFORCEMENT"]
    
    # Fine > £500k
    if has_major_fine?(records, 500_000), do: flags ++ ["MAJOR_FINE"]
    
    flags
  end
end
```

### API Endpoints

```elixir
# New routes for pre-qualification
scope "/api/v1/prequalification", EhsEnforcementWeb.API do
  pipe_through [:api, :authenticated]
  
  # Company lookup
  get "/search", PreQualificationController, :search
  get "/company/:companies_house_number", PreQualificationController, :show_company
  
  # Risk assessment
  post "/assess", PreQualificationController, :assess_risk
  get "/assessment/:portfolio_id", PreQualificationController, :get_assessment
  
  # Verification
  post "/verify", PreQualificationController, :verify_declaration
  get "/verification/:id/report", PreQualificationController, :download_report
  
  # Portfolio management (for suppliers)
  resources "/portfolios", PortfolioController
  post "/portfolios/:id/claim", PortfolioController, :claim_portfolio
  post "/portfolios/:id/documents", PortfolioController, :upload_document
  
  # Enterprise bulk operations
  post "/bulk/search", PreQualificationController, :bulk_search
  post "/bulk/assess", PreQualificationController, :bulk_assess
end
```

---

## 💰 Revenue Model

### Pricing Tiers

| Feature | Free | Professional | Enterprise |
|---------|------|--------------|------------|
| Company search | 5/month | Unlimited | Unlimited |
| Risk scores | View only | Full breakdown | Custom weights |
| Verification reports | - | 10/month | Unlimited |
| Offender responses | Read | Read | Read + Contact |
| API access | - | - | ✓ (10k/month) |
| Bulk operations | - | - | ✓ |
| Custom integrations | - | - | ✓ |
| **Price** | Free | £29/month | £299/month |

### Enterprise Add-ons

| Add-on | Price | Description |
|--------|-------|-------------|
| Tender System Integration | £2,000 setup + £200/month | SAP Ariba, Oracle, Jaggaer connectors |
| Custom Risk Model | £5,000 one-time | Tailored scoring for your industry |
| White-label Portal | £500/month | Branded pre-qual portal for your supply chain |
| Priority Data Refresh | £100/month | Daily enforcement data updates (vs weekly) |

### Supplier Tier (B2B2B)

| Feature | Basic | Premium |
|---------|-------|---------|
| Portfolio page | ✓ | ✓ |
| Add enforcement responses | ✓ | ✓ |
| Document uploads | 5 | Unlimited |
| Professional endorsements | - | ✓ |
| Analytics (who viewed) | - | ✓ |
| Featured in search | - | ✓ |
| **Price** | Free | £99/month |

---

## 🔗 Integration with Other Features

### AI Case Context Enrichment
Pre-qualification leverages enriched data:
- **Regulation links**: Show which regulations were violated
- **Benchmark analysis**: "This fine was in the 85th percentile for construction"
- **Professional summaries**: Technical context for evaluators
- **Pattern detection**: "This company has 3 fall-from-height cases"

### Offender Breach Expansion
Supplier responses become pre-qualification content:
- **Company narrative**: "What we learned and how we improved"
- **Evidence uploads**: Certifications, audit reports, HSE letters
- **Community validation**: Other professionals rate the response quality

### AI Predictive Risk Intelligence
Forward-looking risk assessment:
- **Trend prediction**: "Based on patterns, this company's risk is increasing"
- **Sector trends**: "Construction enforcement is up 15% this quarter"
- **Early warning**: Alert when supplier's risk profile changes

### Expert Commentary System
Professional insights on enforcement actions:
- **Expert analysis**: Lawyers/consultants comment on case significance
- **Precedent value**: "This case set a new standard for sentencing"
- **Industry impact**: "This affected the entire waste sector"

### Regulator Scorecard System
Context for enforcement patterns:
- **Regulator behavior**: "HSE has increased construction site inspections"
- **Regional variations**: "This supplier operates in a high-enforcement region"
- **Fairness context**: "The regulator has a 4.2/5 fairness rating"

---

## 🏢 Target Market: EHS Pre-Qualification Schemes

### Major UK Pre-Qualification Bodies

| Scheme | Members | Focus | Integration Opportunity |
|--------|---------|-------|------------------------|
| **SafeContractor** | 50,000+ | Multi-sector | API partnership |
| **CHAS** | 60,000+ | Construction | Data verification |
| **Constructionline** | 45,000+ | Construction | Risk scoring |
| **Achilles UVDB** | 10,000+ | Utilities | Enterprise integration |
| **RISQS** | 4,000+ | Rail | Compliance verification |
| **Avetta** | Global | Multi-sector | UK enforcement data |
| **ISNetworld** | Global | Multi-sector | UK enforcement data |

### Public Sector Opportunities

| Body | Procurement Value | EHS Requirements |
|------|-------------------|------------------|
| **Crown Commercial Service** | £30B+/year | Mandatory PQQ |
| **NHS Supply Chain** | £8B/year | Clinical + EHS |
| **Network Rail** | £5B/year | RISQS mandatory |
| **Highways England** | £4B/year | High-risk works |
| **Local Authorities** | £100B+ combined | Variable requirements |

### Private Sector Verticals

| Sector | Pre-Qual Intensity | Key Players |
|--------|-------------------|-------------|
| **Oil & Gas** | Very High | BP, Shell, TotalEnergies |
| **Construction** | High | Balfour Beatty, Kier, Morgan Sindall |
| **Utilities** | High | National Grid, SSE, United Utilities |
| **Manufacturing** | Medium | Unilever, GSK, JLR |
| **Retail** | Medium | Tesco, Sainsbury's, Amazon |

---

## 📊 Success Metrics

### Product Metrics

| Metric | Target (6 months) | Target (12 months) |
|--------|-------------------|-------------------|
| Company searches | 10,000/month | 50,000/month |
| Risk assessments | 2,000/month | 15,000/month |
| Verification reports | 500/month | 3,000/month |
| Supplier portfolios | 1,000 | 10,000 |
| API integrations | 5 | 25 |

### Business Metrics

| Metric | Target |
|--------|--------|
| Enterprise customers | 20 (Year 1) |
| Enterprise ARR | £72k (Year 1) |
| Supplier Premium subscribers | 500 (Year 1) |
| Supplier ARR | £50k (Year 1) |
| Pre-qual scheme partnerships | 3 |

### Quality Metrics

| Metric | Target |
|--------|--------|
| Company match accuracy | >95% |
| Risk score correlation (vs actual incidents) | >0.7 |
| Verification report accuracy | >98% |
| User satisfaction (NPS) | >50 |

---

## 📅 Implementation Roadmap

### Week 1-2: Data Foundation
- [ ] Company name → enforcement record matching algorithm
- [ ] Companies House API integration
- [ ] Fuzzy matching for trading names
- [ ] Ash resources for portfolios and links

### Week 2-3: Risk Scoring
- [ ] Risk calculation engine
- [ ] Sector baseline data
- [ ] Red flag identification
- [ ] AI explanation generation

### Week 3: Verification & Reporting
- [ ] Declaration parsing (PDF extraction)
- [ ] Discrepancy detection
- [ ] PDF report generation
- [ ] API endpoints

### Post-MVP: Enterprise Features
- [ ] Bulk operations
- [ ] Custom risk weights
- [ ] Tender system integrations
- [ ] Supplier self-service portal

---

## ⚠️ Risks & Mitigations

### Data Accuracy
**Risk**: Incorrect company matching leads to false accusations
**Mitigation**: 
- Confidence scores on all matches
- "Disputed" flag for companies to contest
- Human review queue for low-confidence matches
- Clear liability disclaimer

### Legal Exposure
**Risk**: Defamation claims from companies with negative scores
**Mitigation**:
- All data sourced from public enforcement records
- "Right of reply" for all companies
- Professional legal review of risk language
- Insurance coverage

### Competitive Response
**Risk**: SafeContractor/CHAS build their own
**Mitigation**:
- First-mover advantage with enriched data
- Partner rather than compete (API licensing)
- Unique offender response content they can't replicate

### Data Freshness
**Risk**: Outdated enforcement data leads to incorrect assessments
**Mitigation**:
- Weekly scraping of regulator websites
- "Last updated" prominently displayed
- Alerting when supplier's profile changes

---

## 🎯 Competitive Advantage

### Why We Win

1. **AI Enrichment**: Raw enforcement data becomes actionable intelligence
2. **Offender Responses**: Unique content competitors can't replicate
3. **Professional Validation**: Verified expert commentary on significance
4. **Real-time Updates**: ElectricSQL enables instant sync
5. **Local-first**: Works offline on construction sites
6. **API-first**: Integrates into existing procurement workflows

### Competitive Landscape

| Competitor | Offering | Our Advantage |
|------------|----------|---------------|
| SafeContractor | Self-declared compliance | We verify against actual records |
| CHAS | Accreditation scheme | We provide context, not just pass/fail |
| Creditsafe | Company credit data | We specialize in EHS enforcement |
| Duedil | Company intelligence | We have enriched enforcement context |
| Google Search | Manual research | We aggregate, enrich, and score |

---

## 📚 Related Documentation

- [AI Case Context Enrichment](./ai-case-context-enrichment.md) - Foundation for enriched pre-qual data
- [Offender Breach Expansion](./offender-breach-expansion.md) - Supplier response system
- [AI Predictive Risk Intelligence](./ai-predictive-risk-intelligence.md) - Forward-looking risk assessment
- [Expert Commentary System](./expert-commentary-system.md) - Professional validation
- [Elevator Pitch](./elevator-pitch.md) - Overall product vision

---

**Summary**: Contract Pre-Qualification Intelligence transforms a broken, trust-based system into evidence-based supplier risk assessment. By combining verified enforcement data, AI enrichment, and offender responses, we help procurement teams make better decisions while helping compliant suppliers demonstrate their value.
