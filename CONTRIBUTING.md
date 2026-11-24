# Contributing

Thank you for helping improve this project. Keep contributions focused on accurate price-impact analysis, defensible SKU comparisons, readable reports, and safe read-only operation.

## Before opening a pull request

1. Explain the problem and expected behaviour change.
2. Keep pricing assumptions and exclusion classifications explicit, dated, and traceable to a source. Do not present a tenant advisory or partner-reported estimate as a universal Microsoft announcement.
3. Preserve read-only behaviour. Do not add resize, restart, deployment, purchase, or billing-changing operations to the assessment script.
4. Avoid logging secrets or customer-sensitive identifiers. Never include real tenant exports or generated customer reports in commits.
5. Run the PowerShell parser and PSScriptAnalyzer checks locally where possible.
6. Update the README and assumptions/limitations documentation when behaviour or inputs change.

## Pull requests

Use a focused branch and describe the change, validation performed, known limitations, and any change to pricing assumptions. A passing static workflow is not proof of Azure tenant compatibility.
