# SEPA Enforcement Notices

This guide describes the Scottish Environment Protection Agency (SEPA) enforcement notices available in the database, including data sources, structure, and legal considerations for use.

## Overview

SEPA is Scotland's principal environmental regulator, responsible for protecting and improving the environment. The database contains enforcement notices issued by SEPA under their civil penalties regime, which was introduced in 2019 as an alternative to criminal prosecution for certain environmental offences.

### Data Summary

| Metric | Value |
|--------|-------|
| Total SEPA Notices | 143 |
| Unique Offenders | 121 |
| Date Range | August 2019 - July 2025 |
| Primary Jurisdiction | Scotland |

### Notice Types

| Type | Count | Description |
|------|-------|-------------|
| Fixed Monetary Penalty (FMP) £600 | 73 | Standard FMP for moderate offences |
| Fixed Monetary Penalty (FMP) £300 | 28 | Lower-tier FMP for minor offences |
| Undertaking | 22 | Voluntary agreement to take corrective action |
| Costs Recovery | 12 | Recovery of SEPA's investigation/remediation costs |
| Variable Monetary Penalty (VMP) | 7 | Higher penalties for serious offences (variable amounts) |
| Fixed Monetary Penalty (FMP) £1000 | 1 | Upper-tier FMP |

## Data Source

All SEPA enforcement data is scraped from SEPA's official public register:

**Source URL**: https://www.sepa.org.uk/regulations/enforcement/enforcement-database/

SEPA publishes this information under their statutory duty to maintain a public register of enforcement actions. The data includes:

- Offender name and address (where not withheld)
- Date of penalty/undertaking
- Type of enforcement action
- Legislation breached
- Offence details
- Penalty amount (where applicable)
- Links to official documentation

## Data Structure

### Notice Record Fields

| Field | Description |
|-------|-------------|
| `regulator_id` | Unique identifier: `sepa_YYYYMMDD_hash` |
| `notice_date` | Date the penalty was issued |
| `offence_action_type` | Type of enforcement action (e.g., "SEPA FMP £600") |
| `penalty_amount` | Monetary value of penalty (where applicable) |
| `notice_body` | Description of the offence |
| `offence_breaches` | Legislation breached |
| `url` | Link to official SEPA documentation |

### Linked Records

Each notice is linked to:
- **Agency**: Scottish Environment Protection Agency (SEPA)
- **Offender**: Individual or organisation that received the penalty

## Legal Basis for Data Collection and Use

### Public Register Requirements

SEPA maintains its enforcement register under the following legislative framework:

1. **Environmental Regulation (Enforcement Measures) (Scotland) Order 2015** - Establishes SEPA's civil penalties regime
2. **The Regulatory Reform (Scotland) Act 2014** - Provides the overarching framework for regulatory enforcement
3. **Freedom of Information (Scotland) Act 2002** - Public bodies must make information available

### Right to Use

This data may be used under the following basis:

1. **Open Government Licence**: SEPA data published on gov.scot websites is typically available under the [Open Government Licence v3.0](http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/), which permits:
   - Copying, publishing, distributing and transmitting the information
   - Adapting the information
   - Exploiting the information commercially and non-commercially

2. **Public Interest**: Enforcement data serves the public interest by:
   - Enabling informed business decisions (supply chain due diligence)
   - Supporting environmental compliance awareness
   - Facilitating research into regulatory effectiveness

### Attribution Requirements

When using SEPA enforcement data, appropriate attribution should be provided:

> Source: Scottish Environment Protection Agency (SEPA) Enforcement Database
> https://www.sepa.org.uk/regulations/enforcement/enforcement-database/

## Privacy Considerations

### Personal Data

SEPA enforcement notices may contain personal data where the offender is an individual rather than a company. This data is processed on the following basis:

1. **Legitimate Interest**: Processing enforcement data serves legitimate interests in:
   - Environmental protection
   - Business due diligence
   - Regulatory transparency

2. **Public Task**: The data has been made public by SEPA in performance of their statutory duties

### Data Protection Principles

When handling SEPA notice data:

| Principle | Application |
|-----------|-------------|
| Lawfulness | Data obtained from official public register |
| Purpose Limitation | Use for compliance, due diligence, research purposes |
| Data Minimisation | Only relevant enforcement data collected |
| Accuracy | Data refreshed monthly via automated scraping |
| Storage Limitation | Historical records retained for trend analysis |
| Security | Database access controls and encryption in transit |

### Withheld Information

SEPA withholds offender details in certain cases, shown as "Information not published". This typically occurs when:
- The offender has successfully appealed
- Legal proceedings are ongoing
- Publication would be disproportionate to the offence

These records are stored with anonymised identifiers.

## Data Refresh Schedule

SEPA notices are automatically scraped on the **1st of each month** at 05:00 UTC via an Oban scheduled job. The scraper:

1. Fetches the current enforcement page from SEPA's website
2. Parses all penalty types (FMP, VMP, Undertakings, Costs Recovery)
3. Compares against existing records using `regulator_id`
4. Creates new records for any notices not already in the database
5. Logs results to the scrape session history

Manual scraping can also be triggered via the admin interface at `/admin/scrape`.

## Querying SEPA Data

### Via API

```bash
# Get all SEPA notices
GET /api/notices?filter[agency_code]=sepa

# Get recent SEPA penalties
GET /api/notices?filter[agency_code]=sepa&sort=-notice_date&page[limit]=20
```

### Via Database

```sql
SELECT 
  n.regulator_id,
  n.notice_date,
  n.offence_action_type,
  n.penalty_amount,
  o.name as offender_name
FROM notices n
JOIN offenders o ON n.offender_id = o.id
JOIN agencies a ON n.agency_id = a.id
WHERE a.code = 'sepa'
ORDER BY n.notice_date DESC;
```

## Limitations and Disclaimers

1. **Not Legal Advice**: This data is provided for informational purposes only and does not constitute legal advice

2. **Point-in-Time Accuracy**: Data reflects SEPA's published register at the time of scraping; appeals or corrections may not be immediately reflected

3. **Completeness**: Some historical records may have incomplete data where SEPA's original publication was limited

4. **Third-Party Verification**: For critical business decisions, users should verify enforcement status directly with SEPA

## Further Resources

- [SEPA Enforcement Policy](https://www.sepa.org.uk/regulations/enforcement/)
- [SEPA Civil Penalties Guidance](https://www.sepa.org.uk/regulations/enforcement/civil-penalties/)
- [Scottish Government Environmental Regulation](https://www.gov.scot/policies/environmental-regulation/)
- [Open Government Licence](http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)

## Contact

For questions about SEPA enforcement data in this system, contact the development team or raise an issue in the project repository.

For official SEPA enquiries:
- Website: https://www.sepa.org.uk/
- Email: registry@sepa.org.uk
