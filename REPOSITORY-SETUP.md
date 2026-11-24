# Repository workflow

This repository is already created on GitHub. Clone it before making changes:

    git clone https://github.com/tripathies/azure-vm-price-impact-sku-recommender.git
    cd azure-vm-price-impact-sku-recommender

Create a feature branch, update the files, and push your branch:

    git switch -c feature/<short-description>
    git add .
    git commit -m "Describe the change"
    git push -u origin HEAD

Open a pull request and review the PowerShell validation workflow before merging.

Do not commit tenant exports, subscription IDs, resource IDs, billing data, credentials, generated reports, or customer-identifiable information.
