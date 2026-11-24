# LinkedIn launch post

## Azure VM price impact: know what is exposed before the bill changes

A regional Azure compute price adjustment is planned to take effect on **1 February 2027**. One question cloud and FinOps teams should be able to answer before then:

**Which VMs may be in scope, what could the monthly impact look like, and are there lower-cost alternatives in the same region?**

I built the **Azure VM Price Impact & SKU Recommender** — a read-only PowerShell assessment utility designed to help answer those questions with an auditable workflow.

### What it does

- Discovers standalone Azure VMs across enabled subscriptions visible to your signed-in identity.
- Classifies deployed VM sizes against the project's regional planning assumptions and explicit generation exclusions.
- Looks up public PAYG compute rates through the Azure Retail Prices API.
- Models current and projected monthly compute run rate, with configurable monthly hours and an optional manual discount scenario.
- Screens lower-cost VM SKU candidates in the **same Azure region**, using basic capability and regional availability metadata.
- Exports per-VM cost detail, SKU recommendations, alternative-candidate audit, regional summary, run audit trail, JSON manifest and an HTML dashboard.

### The exclusion logic matters

The project makes the named exclusions explicit:

- **v1:** Bv1, D, Ds, F, Fs, G, Gs, L, NP, HCS
- **v2:** Av2, Amv2, Dv2, Dsv2, Fsv2, Lsv2
- **Intel v7:** Dsv7, Ddsv7, Dlsv7, Dldsv7, Esv7, Edsv7

**Important:** the v7 exclusions name six Intel series. **AMD v7 is not automatically excluded** just because it belongs to generation v7. The exact deployed SKU and the advisory in your own tenant must be checked.

### Built for assessment, not blind automation

The script is read-only. It does not resize, stop, restart, deploy or modify VMs. A recommended SKU is a candidate for engineering review — not an automatic change instruction.

A few boundaries are important:
- A VM not matching a named exclusion is classified as **potentially affected**, not confirmed affected.
- The model uses public retail pricing and a default 730-hour monthly run-rate assumption. It does not reproduce your invoice or negotiated EA/MCA/CSP rates, reservations, Savings Plans or Azure Hybrid Benefit.
- Candidate screening is an initial filter, not proof of application, OS/image, performance, quota, zone or capacity compatibility.
- The utility covers standalone VM compute; it does not model VM Scale Sets or other Azure service and infrastructure charges.

The regional assumptions and exclusion matrix are based on customer-facing Service Health advisory details used for this project. This is a community-built assessment utility — **not a Microsoft product or an official Microsoft pricing announcement**. Always validate the actual advisory, impacted resources, meter IDs and contract terms in your tenant before making a budget or architecture decision.

### Explore the project

🔗 GitHub repository: https://github.com/tripathies/azure-vm-price-impact-sku-recommender

The repository includes the PowerShell script, assumptions and limitations, editable workflow source, visual diagrams, sample run guidance and GitHub Actions static validation.

I’d value feedback from Azure architects, platform engineers and FinOps practitioners:

**How are you identifying price exposure and evaluating right-sized, same-region VM alternatives across your Azure estate?**

#MicrosoftAzure #Azure #FinOps #CloudCostOptimization #CloudArchitecture #PowerShell #AzureVM #CloudEngineering
