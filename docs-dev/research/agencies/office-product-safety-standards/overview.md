# Office for Product Safety and Standards (OPSS) Enforcement Data

## Overview

The Office for Product Safety and Standards (OPSS) is part of the Department for Business and Trade (DBT). OPSS is the national regulator for product safety and construction products, providing scientific and technical capability, and enforcing in relation to cases that are nationally significant, novel or contentious.

**Main Enforcement Page:** https://www.gov.uk/government/publications/opss-enforcement-actions

**Answer: Yes, OPSS publishes enforcement actions.** They have been publishing enforcement data since April 2020, with bi-annual reports available in HTML and PDF format.

---

## Data Availability Summary

| Data Type | Date Range | Format | Volume |
|-----------|------------|--------|--------|
| **Enforcement Actions** | April 2020 - Present | HTML (recent), PDF (older) | ~20-40 per 6-month period |
| **Enforcement Undertakings** | 2021 - Present | HTML + PDF summaries | ~70 total (EV charging) |

**Data Retention:** Published enforcement actions are removed from GOV.UK after **5 years** but remain available via the National Archives.

---

## Types of Enforcement Actions Published

OPSS publishes the following enforcement action types:

### 1. Regulatory Notices
| Notice Type | Description |
|-------------|-------------|
| **Compliance Notice** | Requires business to take corrective action |
| **Stop Notice** | Prohibits placing products on market |
| **Prohibition Notice** | Prohibits supply of specific products |
| **Withdrawal Notice** | Requires removal from supply chain |
| **Recall Notice** | Requires recall of products from consumers |
| **Seizure Notice** | Confiscation of non-compliant goods |

### 2. Criminal Prosecutions
- Convictions with fines, imprisonment, director disqualification
- Confiscation and deprivation orders

### 3. Enforcement Undertakings
- Voluntary commitments to address non-compliance
- Completion certificates issued when fulfilled
- Currently focused on EV Smart Charge Point regulations

---

## Data Fields Per Enforcement Action

Each enforcement action record contains:

| Field | Description | Example |
|-------|-------------|---------|
| Business Name | Company or individual | CVS Energy Ltd t/a Clearview Stoves |
| Action Type | Type of enforcement | Compliance Notice, Recall Notice, Prosecution |
| Date | When action taken | 21 August 2024 |
| Products | Specific products affected | Pioneer 400, Solution 500SB stoves |
| Legislation Breached | Specific regulations violated | Ecodesign Regulations 2010, Reg 14(1) |
| Outcome | Result of enforcement | Notice issued, Fine imposed, Products seized |
| Category | Regulatory area | Product Safety, Timber, Environmental Protection |

### For Prosecutions (Additional Fields)
| Field | Description | Example |
|-------|-------------|---------|
| Court/Date | Sentencing details | 21 June 2024 |
| Penalty | Fine amount | £240,000 |
| Imprisonment | Custodial sentence | 12 months suspended for 18 months |
| Director Disqualification | Ban from directorships | 2 years |
| Costs | Legal costs awarded | £51,619.96 |
| Confiscation | Asset recovery | £66,950.64 |

---

## Regulatory Categories

OPSS enforcement spans multiple regulatory areas:

| Category | Typical Legislation |
|----------|---------------------|
| **Product Safety** | General Product Safety Regulations 2005, Toy (Safety) Regulations 2011, PPE Regulations 2018 |
| **Construction Products** | Construction Products Regulations 2013 |
| **Environmental Protection** | Ecodesign for Energy-Related Products Regulations 2010, Energy Information Regulations 2011 |
| **Timber** | Timber and Timber Products Regulations 2013 (illegal logging) |
| **EV Charging** | Electric Vehicle (Smart Charge Points) Regulations 2021 |
| **Consumer Protection** | Consumer Protection from Unfair Trading Regulations 2008 |

---

## Published Reports

### Available Periods

| Period | Format | URL |
|--------|--------|-----|
| Apr 2025 - Sep 2025 | HTML | `/opss-enforcement-actions-1-april-2025-to-30-september-2025` |
| Oct 2024 - Mar 2025 | HTML | `/opss-enforcement-actions-1-october-2024-to-31-march-2025` |
| Apr 2024 - Sep 2024 | HTML | `/opss-enforcement-actions-1-april-2024-to-30-september-2024` |
| Oct 2023 - Mar 2024 | HTML | `/opss-enforcement-actions-january-2024` |
| Apr 2023 - Sep 2023 | HTML | `/opss-enforcement-actions-1-april-2023-to-30-september-2023` |
| Oct 2022 - Mar 2023 | HTML | `/opss-enforcement-actions-1-october-to-2022-to-31-march-2023` |
| Apr 2022 - Sep 2022 | HTML | Published |
| Sep 2021 - Mar 2022 | PDF | `opss-enforcement-actions-october-2021-march-2022.pdf` |
| Apr 2021 - Sep 2021 | PDF | Published |
| Apr 2020 - Mar 2021 | PDF | `opss-enforcement-actions-april-2020-march-2021.pdf` |

### Sample Data Volume

| Period | Actions |
|--------|---------|
| Apr-Sep 2024 | 27 |
| Oct 2024 - Mar 2025 | 6 |

---

## Data Access Options

### Option 1: HTML Scraping (Recommended)

**Complexity:** Low-Medium  
**Reliability:** High  
**Data Coverage:** April 2020 - Present

Recent reports (2022 onwards) are published as HTML pages with structured content organized by category.

**Advantages:**
- Consistent structure across reports
- Well-organized by category (Product Safety, Timber, etc.)
- GOV.UK is stable and reliable
- Clear field separation

**Implementation:**
```elixir
defmodule EhsEnforcement.Scraping.Opss.EnforcementScraper do
  @base_url "https://www.gov.uk/government/publications/opss-enforcement-actions"
  
  def scrape_period(period_slug) do
    # Fetch HTML page for period
    # Parse by category sections
    # Extract enforcement action records
  end
end
```

### Option 2: PDF Parsing (Historical Data)

**Complexity:** Medium-High  
**Data Coverage:** April 2020 - March 2022

Older reports are PDF-only. Same structure as HTML but requires PDF text extraction.

### Option 3: API Access (NOT Available)

**Status:** No public API exists

- No CSV/JSON download options
- No data.gov.uk dataset for OPSS enforcement
- Would require FOI request for bulk data

---

## Enforcement Undertakings (Separate Data Source)

### Source URL
https://www.gov.uk/guidance/regulations-enforcement-undertakings-accepted-by-opss

### What Are They?
Voluntary commitments by businesses to address non-compliance, with completion certificates issued when fulfilled.

### Current Scope
Focused on **Electric Vehicle (Smart Charge Points) Regulations 2021**:
- 31 active undertakings
- 12 completion certificates issued
- 24 expired undertakings

### Data Fields
- Business name and registration number
- Start and end dates
- Link to detailed summary PDF

This is a **separate data source** that could be scraped independently.

---

## Comparison with Existing Data Sources

| Source | Data Type | Volume/6mo | Access | Historical |
|--------|-----------|------------|--------|------------|
| **HSE** | Cases & Notices | ~500+ | Scraping | Multi-year |
| **EA** | Cases & Notices | ~250+ | API + Scraping | Multi-year |
| **FRA (NFCC)** | Notices | ~100+ | Scraping | 3 years |
| **ORR** | Prosecutions + Notices | ~10-15 | Scraping | 2006+ |
| **MCA** | Prosecutions | ~5-10/year | HTML/PDF | 2010+ |
| **OPSS** | All types | ~20-40 | Scraping | 2020+ |

---

## Database Schema Mapping

### Prosecutions → Case Resource

| OPSS Field | Existing Field | Notes |
|------------|----------------|-------|
| Business Name | offender.name | Via Offender relationship |
| Date | offence_hearing_date | Sentencing date |
| Legislation Breached | offence_breaches | Regulation reference |
| Fine | offence_fine | £ amount |
| Costs | offence_costs | £ amount |
| Products | *(new or in details)* | Product description |
| Category | *(agency_type or tag)* | Product Safety, Timber, etc. |

### Notices → Notice Resource

| OPSS Field | Existing Field | Notes |
|------------|----------------|-------|
| Business Name | offender.name | Via Offender relationship |
| Date | notice_date | Action date |
| Action Type | offence_action_type | Recall, Compliance, Prohibition, etc. |
| Legislation | offence_breaches | Regulation reference |
| Products | notice_body | Product details |
| Outcome | *(new or status)* | Notice result |

### Proposed Schema Additions

```elixir
# May benefit from additional fields:
attribute(:products_affected, :string, description: "Products subject to enforcement")
attribute(:regulatory_category, :string, description: "Product Safety, Timber, Construction, etc.")
```

### Agency Record

Single Agency record needed:
- Name: "Office for Product Safety and Standards"
- Code: `:opss`
- Type: "product_safety_regulator"

---

## Implementation Recommendations

### Phase 1: HTML Scraper (Priority)

Scrape all HTML reports (2022 onwards).

```elixir
defmodule EhsEnforcement.Scraping.Opss.EnforcementScraper do
  @moduledoc """
  Scrapes OPSS enforcement actions from GOV.UK.
  """
  
  @periods [
    "opss-enforcement-actions-1-april-2025-to-30-september-2025",
    "opss-enforcement-actions-1-october-2024-to-31-march-2025",
    "opss-enforcement-actions-1-april-2024-to-30-september-2024",
    # ... etc
  ]
  
  def scrape_all do
    Enum.flat_map(@periods, &scrape_period/1)
  end
  
  def scrape_period(period_slug) do
    # 1. Fetch HTML page
    # 2. Parse category sections
    # 3. Extract individual actions
    # 4. Return structured data
  end
end
```

**Effort:** 1-2 days

### Phase 2: PDF Parser (Historical)

Add support for older PDF reports (2020-2022) if historical completeness needed.

**Effort:** 1-2 days (additional)

### Phase 3: Undertakings Scraper (Optional)

Scrape EV charging enforcement undertakings as separate dataset.

**Effort:** 0.5 days

### Phase 4: Scheduled Updates

- Bi-annual scrape when new reports published
- Low frequency (2 reports per year)
- Could monitor RSS or check publication dates

---

## Effort Estimate

| Task | Estimate |
|------|----------|
| HTML structure analysis | 2-4 hours |
| HTML scraper implementation | 1-2 days |
| PDF parser (optional) | 1-2 days |
| Schema migration | 2-4 hours |
| Agency seed data | 1 hour |
| Testing & validation | 4-8 hours |
| **Total (HTML only)** | **2-3 days** |
| **Total (with PDF)** | **4-5 days** |

---

## Legal & Compliance Considerations

### Data Status
- **Public data:** Published on GOV.UK for transparency
- **Government policy:** OPSS revised publication policy in February 2021 to increase transparency
- **5-year retention:** Actions removed after 5 years (National Archives backup)

### Scraping Compliance
- GOV.UK standard robots.txt
- Implement rate limiting
- Low frequency updates needed (bi-annual reports)

### GDPR Considerations
- Some prosecutions name individuals (business owners/directors)
- Same handling as HSE/EA offender data
- Public interest basis for enforcement transparency

---

## Unique Characteristics

### Multi-Category Regulator
Unlike single-focus regulators (ORR for rail, MCA for maritime), OPSS covers diverse product categories:
- Consumer products (toys, electronics)
- Construction materials
- Energy products (stoves, EV chargers)
- Timber/forestry

### International Enforcement
Many enforcement actions target:
- Chinese online sellers (Amazon, AliExpress, Temu, Wish)
- International supply chains
- Marketplace removals

### Escalating Enforcement Model
OPSS uses compressed 35-day enforcement process:
1. Letters sent
2. Information Notices issued
3. Written submissions exchanged
4. Enforcement position taken

---

## Next Steps

1. [ ] Inspect HTML structure of recent report (developer tools)
2. [ ] Create spike to parse single period
3. [ ] Map OPSS categories to existing schema
4. [ ] Decision: Proceed with implementation

---

## References

- [OPSS Enforcement Actions](https://www.gov.uk/government/publications/opss-enforcement-actions)
- [OPSS Enforcement Policy](https://www.gov.uk/government/publications/safety-and-standards-enforcement-enforcement-policy/opss-enforcement-policy)
- [National Regulation Enforcement Services](https://www.gov.uk/guidance/national-regulation-enforcement-services)
- [Enforcement Undertakings (EV Charging)](https://www.gov.uk/guidance/regulations-enforcement-undertakings-accepted-by-opss)
- [OPSS About Page](https://www.gov.uk/government/organisations/office-for-product-safety-and-standards/about)
- [General Product Safety Regulations 2005](https://www.legislation.gov.uk/uksi/2005/1803/contents/made)
- [Construction Products Regulations 2013](https://www.legislation.gov.uk/uksi/2013/1387/contents/made)
