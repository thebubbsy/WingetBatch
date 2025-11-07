# Meeting Brief: API Cost Context – iChris vs Market Benchmarks

## Executive Summary

This briefing document provides a comprehensive analysis of iChris API pricing compared to industry benchmarks across 20+ HRIS and payroll platforms operating in the Australian market. The analysis reveals that iChris's per-user, per-pay-cycle API pricing model is a significant market anomaly.

---

## Michael's Presentation Script

### Opening Context

"Thanks for meeting with me today. I want to ensure we're all on the same page regarding the API costs we've been quoted for iChris."

"I've conducted a thorough analysis of approximately 20 other HR and payroll platforms that either operate in Australia or have a significant presence in the Australian market. What I've found is striking: **none of them charge their clients a per-user, per-pay-cycle API fee**. In fact, API access is almost universally included in the main licence or charged as a straightforward flat annual fee."

### Cost Context

"To put this in proper perspective, the iChris API quote we received — approximately **$22,230 per year** — is for what I would characterize as a fairly light integration. This isn't a system that's delivering payslips, handling complex payroll logic, or processing transactions. It's simply moving data out to our data lake for reporting purposes. That's minimal use by any standard."

### Market Comparison

"When you examine other HRIS and payroll systems, even those operating at enterprise scale, their API access is either bundled into the base platform cost or represents a fraction of what we're being quoted. Let me show you what the market actually looks like for systems of comparable class and scale."

---

## Comparative API & Platform Pricing Analysis

**Baseline: ~5,000 Employees**

| # | Platform | Pricing Model | Estimated Annual Cost (5,000 Employees) | API Access Model |
|---|----------|--------------|----------------------------------------|------------------|
| 1 | **Employment Hero** | $19–$49 per employee/month | $1.1M–$2.9M (full platform) | ✅ API access included. No separate API fee. |
| 2 | **KeyPay** | $4–$6 per employee/month | $240K–$360K (full platform) | ✅ API included with subscription. |
| 3 | **Xero (Payroll AU)** | $35/month base + $5–10/employee/month | $300K–$600K (full platform) | ✅ API included. No extra fee. |
| 4 | **MYOB** | Custom enterprise pricing | $150K–$400K (est.) | ✅ API included in base licensing. |
| 5 | **Reckon** | Subscription (SMB focus) | $100K–$250K (est.) | ✅ API part of developer program. |
| 6 | **Ascender** | Enterprise quote only | $250K–$600K (est.) | ✅ API access bundled. |
| 7 | **Ceridian Dayforce** | Enterprise quote only | $400K+ | ✅ Full API access included. |
| 8 | **UKG (Kronos)** | Enterprise subscription | $300K+ | ✅ API integrated in suite. |
| 9 | **MicroPay (Access Group)** | Custom | $150K–$250K | ✅ Web API included in product. |
| 10 | **ELMO Software** | $25–$45 per employee/year | $125K–$225K | ✅ API access included. |
| 11 | **Papaya Global** | $20–$30 per employee/month | $1.2M–$1.8M (full global payroll) | ✅ API included. |
| 12 | **BreatheHR** | $2–$3 per employee/month | $120K–$180K | ✅ API part of service. |
| 13 | **Bitrix24** | Flat-tier pricing | $50K–$100K | ✅ REST API included. |
| 14 | **peopleHum** | Subscription pricing | $100K+ | ✅ API included. |
| 15 | **ADP (AU)** | Custom enterprise pricing | $300K–$700K | ✅ API access via ADP Developer portal. |
| 16 | **Workday** | Enterprise licence | $400K–$800K+ | ✅ APIs fully bundled. |
| 17 | **SAP SuccessFactors** | Enterprise licence | $400K–$800K+ | ✅ OData APIs standard. |
| 18 | **BambooHR** | $8–$10 per employee/month | $480K–$600K | ✅ API included at no cost. |
| 19 | **Zoho People** | $1–$2 per employee/month | $60K–$120K | ✅ API included in base subscription. |
| 20 | **iChris (Current Quote)** | ⚠️ Per-user, per-pay-cycle model | ⚠️ **$22,230/year** | ❌ **API only**, not full platform — completely out of line with market practice. |

---

## Key Findings & Analysis

### Market Standard Practice
- **100% of surveyed platforms** (excluding iChris) include API access as part of their base platform offering
- API access is treated as a **fundamental platform capability**, not an add-on service
- No platform charges per-transaction or per-pay-cycle fees for basic data extraction

### iChris Cost Anomaly
The iChris API quote represents:
- **API-only access** at $22,230/year for minimal data extraction use
- A pricing model that **no other platform in the market** employs
- A cost structure that treats API access as a premium add-on rather than a standard platform feature

### Functional Context
The iChris integration in question:
- ✅ **Does:** Extract data for reporting and data lake population
- ❌ **Does not:** Process payroll, deliver payslips, or perform business logic
- ❌ **Does not:** Handle high transaction volumes or complex operations

This is a **read-only, low-intensity integration** that would typically be included in any modern SaaS platform's standard offering.

---

## Closing Argument

### Michael's Conclusion

"So when you compare iChris against every other platform here — including major enterprise systems like Workday, SAP SuccessFactors, and ADP — **none of them charge separately for basic API data access**, and **none bill per employee or per pay run**."

"The iChris API quote is not just expensive for what it does — it's fundamentally misaligned with market expectations. We're being asked to pay $22,230 per year for functionality that:
1. Is included free in virtually every competing platform
2. Represents minimal technical overhead (read-only data extraction)
3. Doesn't deliver any processing, payroll logic, or end-user services"

"In short, **iChris's API pricing is not just on the high side — it's a complete anomaly in the HRIS market.** No comparable platform uses this pricing model, and no platform charges anywhere near this amount for similar functionality."

### Recommendation

We should challenge this pricing structure and seek either:
1. **Inclusion of API access** in our base platform licensing (industry standard)
2. **Flat annual API fee** that aligns with our actual usage and market norms
3. **Alternative platform consideration** if iChris cannot align with market-standard pricing practices

---

## Appendix: Pricing Model Categories

### Category A: Per-Employee Subscription (API Included)
- Employment Hero, KeyPay, Xero, BreatheHR, ELMO, BambooHR, Zoho People, Papaya Global
- **Industry Standard:** API access is part of per-employee pricing

### Category B: Enterprise Custom (API Bundled)
- Ascender, Ceridian Dayforce, UKG, ADP, Workday, SAP SuccessFactors, MYOB, MicroPay
- **Industry Standard:** API access negotiated as part of enterprise agreement, typically included

### Category C: Flat/Tier Subscription (API Included)
- Reckon, Bitrix24, peopleHum
- **Industry Standard:** API access included in subscription tier

### Category D: Per-Transaction/Per-Use (API Charged Separately)
- **iChris (ONLY)**
- **Market Anomaly:** No other platform uses this model for basic data extraction

---

## Document Control

**Prepared by:** Michael  
**Date:** November 2025  
**Purpose:** Account Manager Meeting - API Cost Justification  
**Classification:** Internal Analysis  
**Version:** 1.0

---

**Note:** All pricing figures are indicative and based on publicly available information, vendor quotes, and industry research. Actual pricing may vary based on specific requirements, contract terms, and negotiation. The purpose of this analysis is to demonstrate relative market positioning rather than exact cost comparisons.
