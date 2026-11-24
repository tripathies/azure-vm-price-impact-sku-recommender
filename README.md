# Azure VM Price Impact & SKU Recommender

> Read-only PowerShell assessment to identify Azure VMs potentially exposed to the 1 February 2027 regional compute price adjustment, estimate monthly run-rate impact, and rank lower-cost VM size candidates for human review.

![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white) ![Azure](https://img.shields.io/badge/Azure-Read--only%20assessment-0078D4?logo=microsoftazure&logoColor=white) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## What this project does

The script inventories standalone Azure virtual machines in enabled subscriptions visible to the signed-in identity. It classifies VM sizes against the documented regional planning assumptions, retrieves Azure Retail Prices API consumption rates, estimates current and projected monthly compute run rate, and searches for lower-cost candidate VM sizes in the same region.

It answers three operational questions:

1. Which deployed VMs are potentially in scope, excluded, or require manual classification review?
2. What is the modelled monthly compute run-rate change, using a configurable discount scenario?
3. Which lower-cost same-region VM sizes pass basic SKU screening and should be checked by the workload owner?

The script does not resize, restart, stop, deploy, or otherwise modify Azure resources.

## Features

- Read-only discovery of standalone VMs across enabled subscriptions, with an optional subscription ID filter.
- Region and VM-series classification against explicit planning inputs and named exclusion families.
- PAYG consumption-rate lookup through the Microsoft Azure Retail Prices API, including effective-date and primary-meter selection.
- Current and projected monthly compute run-rate using a configurable number of hours (default: 730).
- Optional percentage discount scenario; this is user input, not a detected commercial entitlement.
- Same-region SKU candidates screened for regional availability/restrictions, vCPU, memory, data-disk count and premium-storage capability; CPU architecture is matched when exposed by the source SKU metadata.
- Detailed CSVs, candidate audit, run audit trail, regional summary, JSON manifest and HTML dashboard.
- GitHub Actions PowerShell parser and PSScriptAnalyzer static checks.

## Workflow

1. Discover standalone VMs in the selected subscriptions.
2. Classify region and VM series against the documented planning assumptions.
3. Retrieve the matching PAYG compute rate and retain meter/SKU evidence.
4. Calculate current and projected monthly run rate.
5. Screen same-region lower-cost VM size candidates.
6. Export CSV reports, an HTML dashboard and an audit manifest.
7. Have the workload owner validate and approve any proposed change.

The editable workflow diagram is in docs/price-impact-workflow.mmd.

## Repository layout

- scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 — main assessment script
- docs/assumptions-and-limitations.md — pricing assumptions and boundaries
- docs/price-impact-workflow.mmd — workflow diagram source
- docs/LINKEDIN-POST.md — optional launch post draft
- .github/workflows/powershell-validation.yml — parser and static analysis checks

## Prerequisites

- PowerShell 7.0 or later.
- Azure sign-in with read permissions for the subscriptions and VM resources being assessed.
- PowerShell modules Az.Accounts and Az.Compute.
- HTTPS access to https://prices.azure.com/api/retail/prices.

Install modules:

    Install-Module Az.Accounts,Az.Compute -Scope CurrentUser
    Connect-AzAccount

## Run

Default USD list-price run-rate, without a discount scenario:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1

Apply a 15% discount scenario:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -DiscountPercent 15 -CurrencyCode USD

Assess one subscription:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -SubscriptionId '<subscription-guid>' -DiscountPercent 10

If the Retail Prices API data already reflects the regional change for the meters being modelled, avoid applying the uplift twice:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -RetailApiAlreadyIncludesIncrease

The optional legacy v1/v2 scenario is partner-reported, separate from the regional uplift and disabled by default:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -ApplyLegacyV1V2Estimate -LegacyV1V2Percent 25

Use the OutputPath parameter to select another report directory and MonthlyHours to change the full-month run-rate assumption.

## Report outputs

| File | Purpose |
|---|---|
| 01-VM-Cost-Impact-Detail-*.csv | Per-VM inventory, impact status, rate evidence and projected run rate |
| 02-VM-SKU-Recommendations-*.csv | Best lower-cost candidate per VM, estimated savings and review notes |
| 03-Alternative-Candidate-Audit-*.csv | Screened lower-cost candidates and meter/capability evidence |
| 04-Run-Audit-Trail-*.csv | Discovery and lookup stages, status and error detail |
| 05-Regional-Cost-Summary-*.csv | Modelled totals grouped by Azure region |
| Azure-VM-Price-Impact-Dashboard-*.html | Executive HTML summary and top VM impacts |
| Run-Manifest-*.json | Run ID, inputs, assumptions, totals and output file list |

Generated reports may contain subscription, resource and cost details. They are excluded by .gitignore; keep them out of public commits.

## Important assumptions and limitations

Read docs/assumptions-and-limitations.md before using the output for a budget or migration decision.

- The percentage increases and exclusions are planning assumptions from customer-facing Service Health advisory details discussed for this project. Confirm the actual advisory and Impacted Resources list in your own tenant.
- A VM not matching a named exclusion is classified as potentially affected, not confirmed affected.
- The estimate uses a full-month compute run-rate scenario (default 730 hours) for VMs not currently deallocated. A VM observed as deallocated at inventory time is not assigned a current compute rate; historical state and actual billed hours are not reconstructed.
- The Retail Prices API returns public retail list-price information. It does not represent EA/MCA/CSP negotiated rates, reservations, savings plans, Azure Hybrid Benefit, Spot prices or your invoice.
- The discount percentage is a manual what-if input.
- Candidate screening uses regional SKU metadata and basic compute/storage capability checks. It is not proof of workload, OS/image, network, zone, quota, capacity or application compatibility.
- The optional legacy v1/v2 percentage is partner-reported, disabled by default, and must not be stacked with the regional increase for the same meter.
- This utility assesses standalone VMs and compute pricing only. It does not model VM Scale Sets, storage-account meters, disks as separate invoice items, networking, backups, licensing, taxes, credits or other Azure services.

## Validate before action

1. Compare classifications with the tenant's Service Health advisory and impacted-resource list.
2. Compare rate and meter IDs with Cost Management and the applicable customer contract.
3. Check each alternative against workload performance, OS/image, CPU architecture, disks, network, zones, quota, regional capacity, reservations and support requirements.
4. Obtain workload-owner and change-management approval before any resize.
5. Test the script in a non-production subscription before broad rollout.

GitHub Actions runs a PowerShell parser check and PSScriptAnalyzer on changes to scripts or the workflow. Static checks are not a substitute for authenticated Azure testing. The script is not tenant-validated solely because the workflow passes.

## References

- Azure Retail Prices API: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
- Get-AzComputeResourceSku: https://learn.microsoft.com/en-us/powershell/module/az.compute/get-azcomputeresourcesku
- Resize a virtual machine: https://learn.microsoft.com/en-us/azure/virtual-machines/resize-vm
- Troubleshoot SKU not available errors: https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-sku-not-available

## License

Distributed under the MIT License. See LICENSE.

## Disclaimer

This is a community assessment utility, not a Microsoft product or official Microsoft pricing notice. Estimates are directional, require tenant and billing validation, and must not be treated as a quote or invoice forecast. Infrastructure changes must follow your normal approval and change-control process.
