# iChris API Pricing Analysis
**Meeting Notes - Account Manager Discussion**

## Opening

Thanks for meeting with me today. I want to make sure we're aligned on the API costs we've been quoted for iChris.

I've looked at roughly 20 other HR and payroll platforms operating in Australia or with significant Australian presence. What stands out: **none of them charge clients a per-user, per-pay-cycle API fee**. API access is almost always included in the main licence or charged as a flat annual fee.

## The Cost Issue

The iChris API quote we received is approximately **$22,230 per year** for what I'd call a fairly light integration. We're not talking about payslip delivery, complex payroll logic, or transaction processing here. It's data extraction to our data lake for reporting. That's it. Minimal use by any measure.

When you look at other HRIS and payroll systems — even enterprise-scale ones — their API access is either bundled into the base cost or a fraction of what we're being quoted. Here's what the market actually looks like:

---

## Platform Comparison (~5,000 Employees)

| # | Platform | Pricing Model | Est. Annual Cost | API Access |
|---|----------|---------------|------------------|------------|
| 1 | Employment Hero | $19–$49 per employee/month | $1.1M–$2.9M | Included, no separate API fee |
| 2 | KeyPay | $4–$6 per employee/month | $240K–$360K | Included with subscription |
| 3 | Xero Payroll (AU) | $35/month base + $5–10/employee | $300K–$600K | Included, no extra fee |
| 4 | MYOB | Custom enterprise pricing | $150K–$400K (est.) | Included in base licensing |
| 5 | Reckon | Subscription model | $100K–$250K (est.) | Part of developer program |
| 6 | Ascender | Enterprise quote | $250K–$600K (est.) | Bundled |
| 7 | Ceridian Dayforce | Enterprise subscription | $400K+ | Full API access included |
| 8 | UKG (Kronos) | Enterprise subscription | $300K+ | Integrated in suite |
| 9 | MicroPay (Access Group) | Custom | $150K–$250K | Web API included |
| 10 | ELMO Software | $25–$45 per employee/year | $125K–$225K | Included |
| 11 | Papaya Global | $20–$30 per employee/month | $1.2M–$1.8M | Included |
| 12 | BreatheHR | $2–$3 per employee/month | $120K–$180K | Part of service |
| 13 | Bitrix24 | Flat-tier pricing | $50K–$100K | REST API included |
| 14 | peopleHum | Subscription pricing | $100K+ | Included |
| 15 | ADP (AU) | Custom enterprise pricing | $300K–$700K | Via ADP Developer portal |
| 16 | Workday | Enterprise licence | $400K–$800K+ | APIs fully bundled |
| 17 | SAP SuccessFactors | Enterprise licence | $400K–$800K+ | OData APIs standard |
| 18 | BambooHR | $8–$10 per employee/month | $480K–$600K | Included at no cost |
| 19 | Zoho People | $1–$2 per employee/month | $60K–$120K | Included in base subscription |
| 20 | **iChris** | **Per-user, per-pay-cycle** | **$22,230/year** | **API only — not full platform** |

---

## What This Tells Us

### Industry Standard
- **100% of platforms surveyed** (excluding iChris) include API access in their base offering
- API access is treated as fundamental functionality, not an add-on
- Nobody charges per-transaction or per-pay-cycle for basic data extraction

### The iChris Anomaly
- $22,230/year for API-only access
- Minimal data extraction use case
- A pricing model literally no other platform uses
- API treated as premium add-on instead of standard feature

### What Our Integration Actually Does
- ✓ Extracts data for reporting and data lake
- ✗ Does not process payroll
- ✗ Does not deliver payslips
- ✗ Does not perform business logic
- ✗ Does not handle high transaction volumes

This is read-only, low-intensity integration that would normally be standard in any modern SaaS platform.

---

## Bottom Line

When you stack iChris against Workday, SAP SuccessFactors, ADP, or any of the others — **none of them charge separately for basic API data access**. None bill per employee or per pay run.

The iChris API quote isn't just expensive. It's fundamentally out of step with market expectations. We're being asked to pay $22,230 per year for:

- Functionality that's free in virtually every competing platform
- Minimal technical overhead (read-only data)
- No processing, payroll logic, or end-user services

iChris's API pricing isn't on the high side. **It's a complete market anomaly.** No comparable platform uses this model. No platform charges anywhere near this for similar functionality.

---

## What We Should Do

We need to push back on this and seek:

1. **API access included in base platform licensing** (industry standard), OR
2. **Flat annual API fee** aligned with actual usage and market norms, OR
3. **Alternative platform evaluation** if iChris won't align with standard pricing practices

---

## Pricing Model Breakdown

### Per-Employee Subscription (API Included)
Employment Hero, KeyPay, Xero, BreatheHR, ELMO, BambooHR, Zoho People, Papaya Global

*Standard practice: API is part of per-employee pricing*

### Enterprise Custom (API Bundled)
Ascender, Ceridian Dayforce, UKG, ADP, Workday, SAP SuccessFactors, MYOB, MicroPay

*Standard practice: API negotiated as part of enterprise deal, typically included*

### Flat/Tier Subscription (API Included)
Reckon, Bitrix24, peopleHum

*Standard practice: API included in subscription tier*

### Per-Transaction/Per-Use (API Charged Separately)
**iChris (ONLY)**

*Market anomaly: No other platform uses this model for basic data extraction*

---

**Prepared by:** Michael  
**Date:** November 2025  
**Purpose:** Account Manager Meeting - API Cost Challenge  

*Note: Pricing figures are indicative based on publicly available info, vendor quotes, and industry research. Actual costs vary by requirements and contract terms. This analysis demonstrates relative market positioning rather than exact comparisons.*
