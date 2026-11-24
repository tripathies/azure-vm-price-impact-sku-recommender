# LinkedIn announcement draft

🚨 **Azure VM pricing update from 1 February 2027: do you know which workloads may cost more?**

I built a read-only PowerShell Azure VM Price Impact & SKU Recommender to help cloud and FinOps teams answer three practical questions:

1. Which deployed standalone VMs may be in scope for the regional price adjustment?
2. What could the revised monthly compute run rate look like, including a configurable discount scenario?
3. Is there a lower-cost VM size in the same region that passes an initial capability and availability screen?

The tool inventories standalone Azure VMs, classifies regions and VM series against documented planning assumptions, checks named exclusion families, queries Azure Retail Prices, models the regional uplift, and compares lower-cost VM size candidates.

It produces corporate-style HTML and auditable CSV reports:

- VM cost impact detail
- SKU recommendations
- Alternative candidate audit
- Run audit trail
- Regional cost summary
- JSON run manifest

One important distinction: a VM not matching a named exclusion is treated as **potentially affected**, not tenant-confirmed impact. Validate the actual Azure Service Health advisory, impacted resources, billing meter and contract before making a budget or architecture decision.

The script is **read-only**. It recommends candidates; it does not resize or modify production VMs. Any proposed change still needs workload compatibility checks, approval, a maintenance plan and rollback.

This is a first-pass assessment utility, not an invoice forecast. Retail list prices, 730 assumed monthly hours and manual discount inputs are modelling assumptions. It currently assesses standalone VM compute only; VM Scale Sets and non-compute charges are outside scope.

Repository: https://github.com/tripathies/azure-vm-price-impact-sku-recommender

What are you using today to identify price exposure and lower-cost VM size options across your Azure estate?

#MicrosoftAzure #Azure #FinOps #CloudArchitecture #CloudCostOptimization #PowerShell #AzureVM #DevOps


## Suggested visuals in this repository

- Hero/banner: [docs/images/hero-banner.svg](images/hero-banner.svg)
- Assessment flow: [docs/images/solution-flow.svg](images/solution-flow.svg)
- Generation exclusions: [docs/images/generation-exclusions.svg](images/generation-exclusions.svg)
- Monthly cost model: [docs/images/cost-impact-model.svg](images/cost-impact-model.svg)

Use the workflow and exclusion visuals as separate carousel slides. The generated graphic pack is a visual aid; preserve the documented SKU exclusions and AMD v7 clarification when adapting it.