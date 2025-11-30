# FRA Enforcement Notices

This guide describes the Fire and Rescue Authorities (FRA) enforcement notices available in the database, including data sources, structure, and legal considerations for use.

## Overview

Fire and Rescue Authorities in England and Wales are responsible for enforcing the Regulatory Reform (Fire Safety) Order 2005 (RRO 2005). The database contains enforcement notices issued by the 47 Fire and Rescue Services, aggregated through the National Fire Chiefs Council (NFCC) enforcement register.

### Data Summary

| Metric | Value |
|--------|-------|
| Total FRA Notices | ~7,700 |
| Fire & Rescue Services | 47 |
| Primary Jurisdiction | England and Wales |
| Data Source | NFCC Enforcement Register |

### Notice Types

| Type | Legal Basis | Description |
|------|-------------|-------------|
| Prohibition Notice | RRO 2005, Article 31 | Prohibits or restricts use of premises until fire safety issues are resolved |
| Enforcement Notice | RRO 2005, Article 30 | Requires specific fire safety improvements within a set timeframe |
| Alterations Notice | RRO 2005, Article 29 | Requires notification to FRA before changes affecting fire safety |

### Notice Status Values

| Status | Description |
|--------|-------------|
| In Force | Notice is currently active and requirements must be met |
| Complied | Responsible person has met all requirements |
| Withdrawn | Notice withdrawn by the issuing FRA |
| Appealed | Notice is subject to appeal proceedings |
| Cancelled | Notice cancelled (typically after successful appeal) |

### Common Premises Types

| Premises Type | Description |
|--------------|-------------|
| LICENSED PREMISES | Pubs, clubs, bars, restaurants |
| SHOP | Retail premises |
| FACTORY WAREHOUSE | Industrial and storage facilities |
| HOTEL | Hotels and guest accommodation |
| OFFICE | Commercial office buildings |
| RESIDENTIAL | Houses in Multiple Occupation (HMOs), care homes |
| EDUCATIONAL | Schools, colleges, training facilities |

## Data Source

FRA enforcement data is collected from the NFCC (National Fire Chiefs Council) enforcement register:

**Source URL**: https://nfcc.org.uk/our-services/enforcement-register/

The NFCC aggregates enforcement notices from all 47 Fire and Rescue Services in England and Wales into a single searchable register. The data is accessed via the wpDataTables AJAX API which provides:

- UPRN (Unique Property Reference Number)
- Fire and Rescue Service name
- Issue date
- Notice type
- Premises type
- Current status
- Full address
- Responsible person (notice served on)
- Compliance date (where applicable)
- Reasons for the notice
- Additional information/restrictions

### Data Publication Policy

According to NFCC guidance:
- Notices are added to the register **3 weeks after issue date** (to allow for appeals)
- Notices remain on the register for **3 years** unless:
  - Still in force
  - Deemed not complied with
  - Withdrawn by serving authority

## Data Structure

### Notice Record Fields

| Field | Description |
|-------|-------------|
| `regulator_id` | UPRN (Unique Property Reference Number) |
| `notice_date` | Date the notice was issued |
| `offence_action_type` | Type: "FRA Prohibition Notice", "FRA Enforcement Notice", "FRA Alterations Notice" |
| `notice_status` | Current status: `:in_force`, `:complied`, `:withdrawn`, `:appealed`, `:cancelled` |
| `premises_type` | Type of premises (SHOP, FACTORY WAREHOUSE, etc.) |
| `notice_body` | Detailed reasons for the notice |
| `offence_breaches` | Additional information/restrictions |
| `compliance_date` | Date requirements were met (if complied) |
| `url` | Link to NFCC register |

### Linked Records

Each notice is linked to:
- **Agency**: Fire and Rescue Authorities (FRA/NFCC)
- **Offender**: The "responsible person" the notice was served on

### Offender Data

| Field | Description |
|-------|-------------|
| `name` | Name of responsible person or organisation |
| `address` | Full premises address |
| `postcode` | Extracted UK postcode |
| `country` | "England" or "Wales" (determined from FRS name) |

### Country Determination

The country is determined from the Fire and Rescue Service name:
- **Wales**: Mid and West Wales FRS, North Wales FRS, South Wales FRS
- **England**: All other FRS (West Yorkshire, London Fire Brigade, etc.)

## Legal Basis for Data Collection and Use

### Public Register Requirements

The NFCC enforcement register is maintained as a public resource to:

1. **Promote Fire Safety**: Enable the public to make informed decisions about premises they visit
2. **Support Due Diligence**: Allow businesses to assess fire safety compliance of supply chain partners
3. **Ensure Transparency**: Provide visibility of regulatory enforcement actions

### Regulatory Framework

Fire safety enforcement in England and Wales is governed by:

1. **Regulatory Reform (Fire Safety) Order 2005** - The primary legislation
2. **Fire Safety Act 2021** - Amendments following Grenfell Tower inquiry
3. **Fire Safety (England) Regulations 2022** - Additional requirements for high-rise buildings

### Right to Use

This data may be used under the following basis:

1. **Public Register**: The NFCC publishes this register specifically for public access and use

2. **Public Interest**: Enforcement data serves legitimate purposes:
   - Fire safety awareness
   - Property due diligence (purchase, lease, insurance)
   - Supply chain risk assessment
   - Regulatory research and analysis

### Attribution Requirements

When using FRA enforcement data, appropriate attribution should be provided:

> Source: National Fire Chiefs Council (NFCC) Enforcement Register
> https://nfcc.org.uk/our-services/enforcement-register/

## Privacy Considerations

### Personal Data

FRA enforcement notices contain the name of the "responsible person" under fire safety law. This may be:
- A company name (no personal data concerns)
- An individual's name (personal data)
- A trading name (e.g., "John Smith T/A Smith Properties")

### Legal Basis for Processing

Personal data is processed on the following basis:

1. **Legitimate Interest**: Processing enforcement data serves legitimate interests in:
   - Fire safety protection
   - Business due diligence
   - Regulatory transparency

2. **Public Register**: The data has been made public by NFCC to fulfil public safety objectives

### Data Protection Principles

| Principle | Application |
|-----------|-------------|
| Lawfulness | Data obtained from official public register |
| Purpose Limitation | Use for compliance, due diligence, safety research |
| Data Minimisation | Only relevant enforcement data collected |
| Accuracy | Data refreshed weekly via automated scraping |
| Storage Limitation | Historical records retained for trend analysis |
| Security | Database access controls and encryption in transit |

## Data Refresh Schedule

FRA notices are automatically scraped **weekly** via an Oban scheduled job. The scraper:

1. Fetches the nonce token from the NFCC register page
2. Calls the wpDataTables API with pagination (100 records per page)
3. Parses all notice data from the JSON response
4. Uses UPRN as the `regulator_id` for deduplication
5. Creates new records for notices not already in the database
6. Updates existing records if status has changed
7. Logs results to the scrape session history

Manual scraping can also be triggered via the admin interface at `/admin/scrape`.

## Querying FRA Data

### Via API

```bash
# Get all FRA notices
GET /api/notices?filter[agency_code]=fra

# Get recent FRA notices
GET /api/notices?filter[agency_code]=fra&sort=-notice_date&page[limit]=20

# Get Prohibition notices only
GET /api/notices?filter[agency_code]=fra&filter[offence_action_type]=FRA%20Prohibition%20Notice

# Get notices still in force
GET /api/notices?filter[agency_code]=fra&filter[notice_status]=in_force
```

### Via Database

```sql
SELECT 
  n.regulator_id as uprn,
  n.notice_date,
  n.offence_action_type,
  n.notice_status,
  n.premises_type,
  o.name as responsible_person,
  o.address,
  o.country
FROM notices n
JOIN offenders o ON n.offender_id = o.id
JOIN agencies a ON n.agency_id = a.id
WHERE a.code = 'fra'
ORDER BY n.notice_date DESC;
```

### Filtering by Status

```sql
-- Get all notices currently in force
SELECT * FROM notices n
JOIN agencies a ON n.agency_id = a.id
WHERE a.code = 'fra' AND n.notice_status = 'in_force';

-- Get notices that have been complied with
SELECT * FROM notices n
JOIN agencies a ON n.agency_id = a.id
WHERE a.code = 'fra' AND n.notice_status = 'complied';
```

### Filtering by Premises Type

```sql
-- Get all notices for licensed premises
SELECT * FROM notices n
JOIN agencies a ON n.agency_id = a.id
WHERE a.code = 'fra' AND n.premises_type = 'LICENSED PREMISES';
```

## UPRN (Unique Property Reference Number)

The `regulator_id` field contains the UPRN, a unique identifier assigned to every addressable location in Great Britain. This provides:

1. **Unique Identification**: Each property has one UPRN
2. **Deduplication**: Prevents duplicate notices for the same property
3. **Cross-Reference**: Can be used to link with other property datasets (e.g., Land Registry, Council Tax)

Example UPRNs:
- `83224833` (F1 Tyres, Dewsbury)
- `72553388` (Yeadon Cricket Club, Leeds)
- `100040712592` (Chicken Cottage, Bournemouth)

## Fire and Rescue Services

The 47 FRAs covered include:

### England (44 FRS)
Avon, Bedfordshire, Buckinghamshire, Cambridgeshire, Cheshire, Cleveland, Cornwall, County Durham, Cumbria, Derbyshire, Devon & Somerset, Dorset & Wiltshire, East Sussex, Essex, Gloucestershire, Greater Manchester, Hampshire, Hereford & Worcester, Hertfordshire, Humberside, Isle of Wight, Isles of Scilly, Kent, Lancashire, Leicestershire, Lincolnshire, London, Merseyside, Norfolk, North Yorkshire, Northamptonshire, Northumberland, Nottinghamshire, Oxfordshire, Royal Berkshire, Shropshire, South Yorkshire, Staffordshire, Suffolk, Surrey, Tyne & Wear, Warwickshire, West Midlands, West Sussex, West Yorkshire

### Wales (3 FRS)
Mid and West Wales, North Wales, South Wales

## Limitations and Disclaimers

1. **Not Legal Advice**: This data is provided for informational purposes only and does not constitute legal advice

2. **Point-in-Time Accuracy**: Data reflects the NFCC register at the time of scraping; recent changes may not be immediately reflected

3. **3-Week Delay**: New notices appear on the register 3 weeks after issue (to allow for appeals)

4. **3-Year Retention**: Complied notices are removed after 3 years unless still in force

5. **Appeal Outcomes**: Successful appeals may result in notices being withdrawn; historical records may not reflect appeal outcomes

6. **Third-Party Verification**: For critical business decisions (property purchase, insurance), verify enforcement status directly with the relevant Fire and Rescue Service

## Further Resources

- [NFCC Enforcement Register](https://nfcc.org.uk/our-services/enforcement-register/)
- [Using the Enforcement Register](https://nfcc.org.uk/using-the-enforcement-register/)
- [Regulatory Reform (Fire Safety) Order 2005](https://www.legislation.gov.uk/uksi/2005/1541)
- [Fire Safety Act 2021](https://www.legislation.gov.uk/ukpga/2021/24)
- [Fire Safety (England) Regulations 2022](https://www.legislation.gov.uk/uksi/2022/547)
- [Government Fire Safety Guidance](https://www.gov.uk/government/collections/fire-safety-law-and-guidance-documents-for-business)

## Contact

For questions about FRA enforcement data in this system, contact the development team or raise an issue in the project repository.

For official NFCC enquiries:
- Website: https://nfcc.org.uk/
- Address: NFCC, 71-75 Shelton Street, Covent Garden, London, WC2H 9JQ

For enquiries about specific notices, contact the relevant Fire and Rescue Service directly.
