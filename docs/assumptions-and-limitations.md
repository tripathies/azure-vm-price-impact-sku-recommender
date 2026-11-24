# Pricing assumptions, data sources and limitations

## Regional planning assumptions

The script uses the following planning inputs, based on customer-facing Azure Service Health advisory details discussed for this assessment:

| Azure region ID | City / hub reference | Planning uplift |
|---|---|---:|
| northeurope | Dublin, Ireland | 17% |
| francecentral | Paris, France | 11% |
| francesouth | Marseille, France | 11% |
| westeurope | Amsterdam, Netherlands | 9% |
| norwayeast | Oslo hub, Norway | 9% |
| norwaywest | Stavanger hub, Norway | 9% |
| southeastasia | Singapore | 8% |

The city/hub labels are descriptive references only. The script uses Azure region IDs for inventory and price lookups. Confirm the actual advisory, dates, affected meters and impacted resources in the relevant tenant before using these figures.

## VM classification

The script treats non-excluded VM series in the seven listed regions as potentially affected. It does not claim that every non-excluded VM has a confirmed increase.

The static exclusions discussed for the regional advisory include:

- Legacy v1 examples: Bv1, Dv1, Fv1, Gv1, NPv1 and their identified size-feature variants. L/Ls and HC/HCS names are flagged for manual review because exact series and meter naming needs tenant verification.
- v2: Av2, Amv2, Dv2, Dsv2, Fsv2 and Lsv2.
- Six named Intel v7 series: Dsv7, Ddsv7, Dlsv7, Dldsv7, Esv7 and Edsv7.

Do not infer a blanket exclusion for all v7 processors. AMD v7 is not included in the six named Intel v7 exclusions. The tenant advisory and exact billing meter take precedence over this static list. The script's classification table is a planning aid and should be reviewed against SKU inventory and billing meter IDs.

## Price model

- The script queries the Microsoft Azure Retail Prices API for Virtual Machines consumption rates by Azure region and requested currency.
- It selects a matching OS-specific meter, prefers a primary meter-region result and uses the latest effective rate that has started.
- The model applies the configured uplift to that retrieved rate unless the RetailApiAlreadyIncludesIncrease switch is supplied.
- Default monthly run rate is 730 hours. This is a full-month scenario, not actual hours measured from Azure Monitor, VM power state or billing data.
- The discount percentage is a user-entered what-if scenario, not a discovered contract entitlement.
- The optional legacy v1/v2 25% scenario is partner-reported, disabled by default and separate from the listed regional uplift. Do not combine both uplifts for the same meter.
- Retail API rate selection may not reproduce every customer billing meter. Validate returned meter ID, SKU ID and effective date against Cost Management and the applicable commercial agreement.

## Not an invoice forecast

The estimate can differ from an invoice because of EA/MCA/CSP rates, reservations, savings plans, Azure Hybrid Benefit, Spot, OS/software licensing, measured hours, burst/baseline behaviour, disks, storage, network egress, backups, taxes, currency conversion, credits and other meter-specific terms. Storage price changes are not modelled by this VM compute utility.

## Alternative SKU screening

Candidates are drawn from regional Azure Compute Resource SKU metadata and are screened for subscription/location restrictions, known vCPU and memory being no lower than the source VM, enough data-disk slots for the attached disk count, premium-storage support when detected, and CPU architecture match when the source architecture is exposed.

The script does not certify compatibility. It does not fully validate accelerated networking requirements, OS/image support, Hyper-V generation, zones, availability sets, disk caching/IOPS/throughput, application/vendor support, quota, capacity, licensing or workload performance. Candidate rows must be treated as review leads, not resize instructions. A named price exclusion is not automatically the best alternative.

## Scope

- Standalone Azure VMs only; VM Scale Sets are not inventoried.
- Compute retail rates only; storage-account, managed-disk, network, backup and other non-compute meters are not comprehensively modelled.
- Azure resource operations are read-only. Set-AzContext changes the local PowerShell command context but no Azure resource configuration.

## References

- Azure Retail Prices API: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
- Get-AzComputeResourceSku: https://learn.microsoft.com/en-us/powershell/module/az.compute/get-azcomputeresourcesku
- Resize a virtual machine: https://learn.microsoft.com/en-us/azure/virtual-machines/resize-vm
