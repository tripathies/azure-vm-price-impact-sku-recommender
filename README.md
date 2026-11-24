# Azure VM Price Impact & SKU Recommender

> Discover Azure VMs that may be affected by the 1 February 2027 pricing update, estimate the monthly cost impact, and shortlist lower-cost VM SKU alternatives for engineering review.

![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white) ![Azure](https://img.shields.io/badge/Azure-Read--only%20assessment-0078D4?logo=microsoftazure) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Purpose

This project performs a first-pass, read-only assessment of deployed Azure virtual machines. It helps answer three questions:

1. Which deployed VMs are potentially in scope for the regional pricing adjustment?
2. What is the estimated monthly compute cost after the planning uplift, with an optional discount scenario?
3. Which lower-cost VM sizes in the same Azure region appear technically eligible for further review?

It does not resize, restart, deploy, deallocate, or otherwise modify Azure resources.

## Capabilities

- Discover enabled subscriptions visible to the signed-in Azure identity, or assess an explicitly supplied subscription list.
- Inventory standalone VMs and readable VM Scale Set instances.
- Classify Azure region and normalized VM series against the project's documented planning assumptions.
- Retrieve PAYG list-price data from the Microsoft Azure Retail Prices API.
- Calculate current and projected monthly compute cost using a configurable monthly-hours and discount scenario.
- Compare same-region VM sizes returned by Azure Compute Resource SKU metadata, with conservative capability checks.
- Export detailed CSVs, a recommendation CSV, candidate audit, run audit trail, regional summary, JSON manifest, and HTML dashboard.

## Workflow

1. Connect to Azure with a read-authorized identity.
2. Discover VMs and VM Scale Set instances.
3. Classify region and SKU series.
4. Retrieve retail rates and estimate the planning uplift.
5. Screen and rank lower-cost, region-available SKU candidates.
6. Export the reports and review them with the workload owner before any change.

## Prerequisites

- PowerShell 7.0 or later.
- Azure read permissions for the subscriptions and resources being assessed.
- Az.Accounts, Az.Compute, and Az.Network modules.
- HTTPS access to https://prices.azure.com/api/retail/prices.

Install modules:

    Install-Module Az.Accounts,Az.Compute,Az.Network -Scope CurrentUser
    Connect-AzAccount

## Run

Default USD list-price estimate, with no manual discount:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1

Apply a 15% discount scenario:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -DiscountPercent 15 -CurrencyCode USD

Assess one subscription:

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -SubscriptionId '<subscription-guid>' -DiscountPercent 10

Optional legacy v1/v2 partner-reported scenario (disabled by default):

    ./scripts/Azure-VM-Price-Impact-SKU-Recommender.ps1 -ApplyLegacyV1V2Estimate -LegacyV1V2Percent 25

The script writes timestamped reports to an output directory. Use -OutputPath to select another destination.

## Outputs

| File | Purpose |
|---|---|
| 01-VM-Cost-Impact-Detail-*.csv | Per-VM inventory, impact class, price estimates, discount scenario and best candidate |
| 02-VM-SKU-Recommendations-*.csv | Condensed SKU action list and estimated savings |
| 03-Alternative-Candidate-Audit-*.csv | Candidate sizes, regional checks, capability checks and pricing evidence |
| 04-Run-Audit-Trail-*.csv | Processing stages, statuses, scope and errors |
| 05-Regional-Cost-Summary-*.csv | Estimated cost grouped by Azure region |
| Azure-VM-Price-Impact-Dashboard-*.html | Executive HTML summary |
| Run-Manifest-*.json | Run ID, assumptions, counts, output files and scan errors |

## Important assumptions and limitations

Read [the assumptions and limitations](docs/assumptions-and-limitations.md) before using the output for budget or migration decisions.

- Regional percentages and named exclusions are planning inputs based on customer-facing Service Health advisory details discussed for this project. Confirm the advisory and **Impacted Resources** list in your own tenant.
- A non-excluded SKU is labelled **potentially affected**, not confirmed affected.
- The Azure Retail Prices API provides list-price information; it does not represent your EA, MCA, CSP, reservation, savings plan, Spot, Azure Hybrid Benefit, or invoice rates.
- A discount percentage is a user-entered what-if scenario, not an entitlement discovered by the script.
- The default 730 monthly hours is a run-rate assumption, not measured consumption.
- This is a compute-focused estimate. Storage, disks, network, backup, licensing, taxes, credits, and other invoice meters are not comprehensively modelled.
- VM alternative checks are advisory and do not prove application compatibility or capacity availability.
- The optional approximately 25% legacy v1/v2 scenario is partner-reported, disabled by default, and must not be stacked with the regional uplift for the same meter.

## Safety

The assessment is read-only. Never commit real tenant exports, subscription IDs, resource IDs, billing information, credentials, or generated customer reports to a public repository. Validate in a non-production subscription before operational use.

## Validation

GitHub Actions checks PowerShell syntax and runs PSScriptAnalyzer on pull requests and pushes affecting PowerShell scripts or the workflow. Static checks are not a substitute for authenticated testing in a non-production Azure subscription.

## References

- [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)
- [Get-AzComputeResourceSku](https://learn.microsoft.com/en-us/powershell/module/az.compute/get-azcomputeresourcesku)
- [Resize a virtual machine](https://learn.microsoft.com/en-us/azure/virtual-machines/resize-vm)
- [Troubleshoot SKU not available](https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-sku-not-available)

## License

Distributed under the [MIT License](LICENSE).

## Disclaimer

This is a community assessment utility, not a Microsoft product or official Microsoft pricing notice. Estimates are directional and must be checked against your tenant's Service Health advisory, current meters, contract, discounts, and actual invoice data. Approve infrastructure changes through your normal change process.