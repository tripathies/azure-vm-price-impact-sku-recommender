<#
.SYNOPSIS
  Read-only Azure VM price impact assessment and lower-cost SKU recommender.
.DESCRIPTION
  Inventories standalone VMs, estimates full-month PAYG compute run rate using explicit
  regional planning assumptions, and ranks cheaper same-region SKU candidates for review.
.REQUIREMENTS
  Static checks: GitHub Actions PowerShell parser and PSScriptAnalyzer.
  PowerShell 7+, Az.Accounts, Az.Compute, and HTTPS access to the Azure Retail Prices API.
#>
[CmdletBinding()]
param(
    [string[]]$SubscriptionId,
    [ValidateRange(0,100)][double]$DiscountPercent = 0,
    [ValidateRange(1,744)][double]$MonthlyHours = 730,
    [ValidateSet('USD','EUR','GBP','INR','AUD','CAD','JPY','SGD')][string]$CurrencyCode = 'USD',
    [string]$OutputPath = (Join-Path (Get-Location) ("Azure-VM-Price-Impact-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [switch]$RetailApiAlreadyIncludesIncrease,
    [switch]$ApplyLegacyV1V2Estimate,
    [ValidateRange(0,100)][double]$LegacyV1V2Percent = 25
)

$ErrorActionPreference = 'Stop'
$ReportId = [guid]::NewGuid().ToString()
$GeneratedUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$EffectiveDate = [datetime]'2027-02-01'
$RetailApiBase = 'https://prices.azure.com/api/retail/prices'

# Planning assumptions. Confirm the actual Service Health advisory and impacted resources in each tenant.
$RegionalPricing = @{
    northeurope   = @{ Uplift = 17; Area = 'Dublin, Ireland' }
    francecentral = @{ Uplift = 11; Area = 'Paris, France' }
    francesouth  = @{ Uplift = 11; Area = 'Marseille, France' }
    westeurope    = @{ Uplift = 9;  Area = 'Amsterdam, Netherlands' }
    norwayeast    = @{ Uplift = 9;  Area = 'Oslo hub, Norway' }
    norwaywest    = @{ Uplift = 9;  Area = 'Stavanger hub, Norway' }
    southeastasia = @{ Uplift = 8;  Area = 'Singapore' }
}
$ExcludedSeries = @('Bv1','Bsv1','Dv1','Dsv1','Fv1','Fsv1','Gv1','Gsv1','NPv1','NPsv1','Av2','Amv2','Dv2','Dsv2','Fsv2','Lsv2','Dsv7','Ddsv7','Dlsv7','Dldsv7','Esv7','Edsv7')
$LegacyV1V2Series = @('Bv1','Bsv1','Dv1','Dsv1','Fv1','Fsv1','Gv1','Gsv1','Lv1','Lsv1','NPv1','NPsv1','Av2','Amv2','Dv2','Dsv2','Fsv2','Lsv2')
$ManualReviewSeries = @('Lv1','Lsv1','HCv1','HCsv1','HCSv1')
$Audit = [System.Collections.Generic.List[object]]::new()
$Inventory = [System.Collections.Generic.List[object]]::new()
$Recommendations = [System.Collections.Generic.List[object]]::new()
$CandidateAudit = [System.Collections.Generic.List[object]]::new()
$RetailCache = @{}
$SkuCache = @{}

function Add-Audit {
    param([string]$Stage,[string]$Status,[string]$SubscriptionName='',[string]$Region='',[string]$Resource='',[string]$Detail='')
    $Audit.Add([pscustomobject]@{ ReportId=$ReportId; GeneratedUtc=$GeneratedUtc; Stage=$Stage; Status=$Status; Subscription=$SubscriptionName; Region=$Region; Resource=$Resource; Detail=$Detail })
}

function Get-VmSeries {
    param([Parameter(Mandatory)][string]$VmSize)
    $name = $VmSize -replace '^Standard_',''
    if ($name -match '^(?<family>[A-Za-z]+?)(?<size>\d+)(?<features>[a-z]*)_v(?<version>\d+)$') {
        $family = $Matches.family
        if ($family.ToUpperInvariant() -in @('NP','HC')) { $family = $family.ToUpperInvariant() }
        else { $family = $family.Substring(0,1).ToUpperInvariant() + $family.Substring(1).ToLowerInvariant() }
        return ($family + $Matches.features.ToLowerInvariant() + 'v' + $Matches.version)
    }
    return 'Unknown'
}

function Get-Impact {
    param([string]$Region,[string]$Series)
    $regional = $RegionalPricing[$Region.ToLowerInvariant()]
    if ($ApplyLegacyV1V2Estimate -and $LegacyV1V2Series -contains $Series) {
        return [pscustomobject]@{ Status='Legacy v1/v2 - partner-reported scenario'; Uplift=$LegacyV1V2Percent; Basis='Optional partner-reported estimate; disabled by default' }
    }
    if (-not $regional) { return [pscustomobject]@{ Status='Outside listed regions'; Uplift=0; Basis='No regional planning uplift configured' } }
    if ($Series -eq 'Unknown') { return [pscustomobject]@{ Status='Manual review required'; Uplift=$regional.Uplift; Basis='VM size family could not be normalized; verify exact SKU and tenant billing meter' } }
    if ($ManualReviewSeries -contains $Series) { return [pscustomobject]@{ Status='Manual review required'; Uplift=$regional.Uplift; Basis='Verify exact VM series and tenant billing meter' } }
    if ($ExcludedSeries -contains $Series) { return [pscustomobject]@{ Status='Named exclusion'; Uplift=0; Basis='Listed exclusion family; validate exact tenant meter' } }
    if ($RetailApiAlreadyIncludesIncrease) { return [pscustomobject]@{ Status='Potentially affected - API assumed updated'; Uplift=0; Basis='No additional uplift applied to avoid double counting' } }
    return [pscustomobject]@{ Status='Potentially affected'; Uplift=$regional.Uplift; Basis='Non-excluded series in listed region; confirm tenant advisory' }
}

function Get-RetailRates {
    param([string]$Region,[string]$Currency)
    $key = "$Region|$Currency"
    if ($RetailCache.ContainsKey($key)) { return $RetailCache[$key] }
    $filter = "serviceName eq 'Virtual Machines' and armRegionName eq '$Region' and priceType eq 'Consumption'"
    $uri = $RetailApiBase + '?api-version=2023-01-01-preview&currencyCode=' + $Currency + '&$filter=' + [uri]::EscapeDataString($filter)
    $items = [System.Collections.Generic.List[object]]::new()
    while ($uri) {
        $response = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 60
        foreach ($item in @($response.Items)) {
            if ($item.priceType -eq 'Consumption' -and $item.armSkuName -like 'Standard_*' -and $item.unitOfMeasure -match 'Hour' -and $item.meterName -notmatch '(?i)Spot|Low Priority|DevTest') { $items.Add($item) }
        }
        $uri = [string]$response.NextPageLink
    }
    $RetailCache[$key] = @($items)
    return $RetailCache[$key]
}

function Get-Rate {
    param([object[]]$Rates,[string]$VmSize,[string]$OsType)
    if ($OsType -notin @('Windows','Linux')) { return $null }
    $matches = @($Rates | Where-Object { $_.armSkuName -eq $VmSize })
    if ($OsType -eq 'Windows') { $matches = @($matches | Where-Object { $_.productName -match '(?i)Windows' -or $_.meterName -match '(?i)Windows' }) }
    else { $matches = @($matches | Where-Object { $_.productName -notmatch '(?i)Windows|SQL|Red Hat|SUSE' -and $_.meterName -notmatch '(?i)Windows|SQL|Red Hat|SUSE' }) }
    if (-not $matches) { return $null }
    $active = @($matches | Where-Object { $_.effectiveStartDate -and ([datetime]$_.effectiveStartDate -le [datetime]::UtcNow) })
    if ($active) { $matches = $active }
    $primary = @($matches | Where-Object { $_.isPrimaryMeterRegion -eq $true })
    if ($primary) { $matches = $primary }
    return ($matches | Sort-Object @{Expression={[datetime]$_.effectiveStartDate};Descending=$true} | Select-Object -First 1)
}

function Get-CapabilityMap {
    param($Sku)
    $map = @{}
    foreach ($capability in @($Sku.Capabilities)) { if ($capability.Name) { $map[[string]$capability.Name] = [string]$capability.Value } }
    return $map
}

function Get-BoolCapability {
    param([string]$Value)
    return ($Value -match '^(?i:true|1|yes)$')
}

function Get-SkusForRegion {
    param([string]$Region,$Context)
    if ($SkuCache.ContainsKey($Region)) { return $SkuCache[$Region] }
    $raw = @(Get-AzComputeResourceSku -Location $Region -DefaultProfile $Context | Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Locations -contains $Region })
    $result = foreach ($sku in $raw) {
        $caps = Get-CapabilityMap -Sku $sku
        $vcpus=0.0; $memory=0.0; $maxDisks=0
        [void][double]::TryParse($caps['vCPUs'],[ref]$vcpus)
        [void][double]::TryParse($caps['MemoryGB'],[ref]$memory)
        [void][int]::TryParse($caps['MaxDataDiskCount'],[ref]$maxDisks)
        $restricted = $false
        foreach ($restriction in @($sku.Restrictions)) {
            $values = @($restriction.Values | ForEach-Object { [string]$_ })
            if ($restriction.ReasonCode -match 'NotAvailableForSubscription' -or ($restriction.Type -eq 'Location' -and $values -contains $Region)) { $restricted=$true; break }
        }
        [pscustomobject]@{
            Name=[string]$sku.Name; Series=(Get-VmSeries -VmSize ([string]$sku.Name)); Vcpus=$vcpus; MemoryGB=$memory; MaxDataDisks=$maxDisks
            PremiumIO=(Get-BoolCapability $caps['PremiumIO'])
            Architecture=if ($caps.ContainsKey('CpuArchitectureType')) { $caps['CpuArchitectureType'] } else { 'Unknown' }
            Restricted=$restricted
        }
    }
    $SkuCache[$Region] = @($result)
    return $SkuCache[$Region]
}

foreach ($module in @('Az.Accounts','Az.Compute')) {
    if (-not (Get-Module -ListAvailable -Name $module)) { throw "Missing module $module. Install-Module $module -Scope CurrentUser" }
    Import-Module $module -ErrorAction Stop
}
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) { Connect-AzAccount | Out-Null }
$subscriptions = @(Get-AzSubscription | Where-Object State -eq 'Enabled')
if ($SubscriptionId) { $subscriptions = @($subscriptions | Where-Object { $SubscriptionId -contains $_.Id }) }
if (-not $subscriptions) { throw 'No enabled subscriptions matched the current identity and requested filter.' }
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
Add-Audit -Stage 'Initialisation' -Status 'Completed' -Detail "Subscriptions=$($subscriptions.Count); currency=$CurrencyCode; hours=$MonthlyHours; discount=$DiscountPercent%."

foreach ($sub in $subscriptions) {
    try {
        $context = Set-AzContext -SubscriptionId $sub.Id -TenantId $sub.TenantId -ErrorAction Stop
        $vms = @(Get-AzVM -Status -DefaultProfile $context -ErrorAction Stop)
        Add-Audit -Stage 'VM inventory' -Status 'Completed' -SubscriptionName $sub.Name -Detail "Standalone VMs discovered: $($vms.Count)."
    } catch {
        Add-Audit -Stage 'VM inventory' -Status 'Failed' -SubscriptionName $sub.Name -Detail $_.Exception.Message
        continue
    }
    foreach ($vm in $vms) {
        $region = ([string]$vm.Location).ToLowerInvariant()
        $size = [string]$vm.HardwareProfile.VmSize
        $series = Get-VmSeries -VmSize $size
        $osType = [string]$vm.StorageProfile.OsDisk.OsType
        if ($osType -notin @('Windows','Linux')) { $osType='Unknown' }
        $power = ($vm.Statuses | Where-Object Code -like 'PowerState/*' | Select-Object -First 1 -ExpandProperty DisplayStatus)
        $impact = Get-Impact -Region $region -Series $series
        $area = if ($RegionalPricing.ContainsKey($region)) { $RegionalPricing[$region].Area } else { '' }
        $currentRate=$null; $rates=@(); $currentGross=$null; $futureGross=$null; $currentNet=$null; $futureNet=$null; $delta=$null
        $dataDiskCount = @($vm.StorageProfile.DataDisks).Count
        $storageTypes = @($vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType) + @($vm.StorageProfile.DataDisks | ForEach-Object { $_.ManagedDisk.StorageAccountType })
        $needsPremiumIO = [bool](@($storageTypes | Where-Object { $_ -match '^(Premium|Ultra)' }).Count)
        try {
            if ($power -match '(?i)deallocated') {
                Add-Audit -Stage 'Retail price lookup' -Status 'Skipped - deallocated' -SubscriptionName $sub.Name -Region $region -Resource $vm.Name -Detail 'VM is deallocated at inventory time; no current compute run rate is assigned. Historical usage is not modelled.'
            } else {
                $rates = Get-RetailRates -Region $region -Currency $CurrencyCode
                $currentRate = Get-Rate -Rates $rates -VmSize $size -OsType $osType
                if ($currentRate) {
                    $currentGross=[math]::Round(([double]$currentRate.retailPrice*$MonthlyHours),2)
                    $futureGross=[math]::Round(($currentGross*(1+($impact.Uplift/100))),2)
                    $currentNet=[math]::Round(($currentGross*(1-($DiscountPercent/100))),2)
                    $futureNet=[math]::Round(($futureGross*(1-($DiscountPercent/100))),2)
                    $delta=[math]::Round(($futureNet-$currentNet),2)
                }
                Add-Audit -Stage 'Retail price lookup' -Status $(if ($currentRate) {'Completed'} else {'No exact match'}) -SubscriptionName $sub.Name -Region $region -Resource $vm.Name -Detail $(if ($currentRate) {"Meter=$($currentRate.meterId); SKU=$($currentRate.skuId); hourly=$($currentRate.retailPrice) $CurrencyCode"} else {"No exact OS-specific hourly meter for $size / $osType"})
            }
        } catch {
            Add-Audit -Stage 'Retail price lookup' -Status 'Failed' -SubscriptionName $sub.Name -Region $region -Resource $vm.Name -Detail $_.Exception.Message
        }

        $candidates = [System.Collections.Generic.List[object]]::new()
        if ($currentRate -and $impact.Status -notlike 'Outside*') {
            try {
                $skus = Get-SkusForRegion -Region $region -Context $context
                $sourceSku = $skus | Where-Object Name -eq $size | Select-Object -First 1
                if ($sourceSku) {
                    foreach ($candidate in $skus) {
                        if ($candidate.Name -eq $size -or $candidate.Restricted) { continue }
                        if ($sourceSku.Vcpus -le 0 -or $sourceSku.MemoryGB -le 0 -or $candidate.Vcpus -le 0 -or $candidate.MemoryGB -le 0) { continue }
                        if ($candidate.Vcpus -lt $sourceSku.Vcpus -or $candidate.MemoryGB -lt $sourceSku.MemoryGB -or $candidate.MaxDataDisks -lt $dataDiskCount) { continue }
                        if ($needsPremiumIO -and -not $candidate.PremiumIO) { continue }
                        if ($sourceSku.Architecture -ne 'Unknown' -and $candidate.Architecture -ne $sourceSku.Architecture) { continue }
                        $candidateImpact = Get-Impact -Region $region -Series $candidate.Series
                        $candidateRate = Get-Rate -Rates $rates -VmSize $candidate.Name -OsType $osType
                        if (-not $candidateRate) { continue }
                        $candidateCost=[math]::Round(([double]$candidateRate.retailPrice*$MonthlyHours*(1+($candidateImpact.Uplift/100))*(1-($DiscountPercent/100))),2)
                        $savings=[math]::Round(($futureNet-$candidateCost),2)
                        if ($savings -le 0) { continue }
                        $candidateRow=[pscustomobject]@{ReportId=$ReportId;Subscription=$sub.Name;Region=$region;VmName=$vm.Name;CurrentSku=$size;CandidateSku=$candidate.Name;CandidateSeries=$candidate.Series;CandidateImpact=$candidateImpact.Status;Vcpus=$candidate.Vcpus;MemoryGB=$candidate.MemoryGB;MaxDataDisks=$candidate.MaxDataDisks;PremiumIO=$candidate.PremiumIO;Architecture=$candidate.Architecture;EstimatedMonthlyAfterDiscount=$candidateCost;EstimatedMonthlySavings=$savings;CandidateMeterId=$candidateRate.meterId;CandidateSkuId=$candidateRate.skuId;Review='Screened for region availability, vCPU, memory, attached data-disk count, premium-storage capability and architecture when exposed. Manually validate OS/image, networking, zones, quota, capacity and workload compatibility.'}
                        $candidates.Add($candidateRow); $CandidateAudit.Add($candidateRow)
                    }
                } else { Add-Audit -Stage 'SKU recommendation' -Status 'Manual review' -SubscriptionName $sub.Name -Region $region -Resource $vm.Name -Detail "Current SKU $size not found in regional SKU metadata." }
            } catch { Add-Audit -Stage 'SKU recommendation' -Status 'Failed' -SubscriptionName $sub.Name -Region $region -Resource $vm.Name -Detail $_.Exception.Message }
        }
        $best = $candidates | Sort-Object EstimatedMonthlyAfterDiscount | Select-Object -First 1
        $Inventory.Add([pscustomobject]@{
            ReportId=$ReportId;GeneratedUtc=$GeneratedUtc;EffectiveDate=$EffectiveDate.ToString('yyyy-MM-dd');Subscription=$sub.Name;ResourceGroup=$vm.ResourceGroupName;VmName=$vm.Name;Region=$region;RegionArea=$area;VmSize=$size;VmSeries=$series;OsType=$osType;PowerState=$power
            ImpactStatus=$impact.Status;UpliftPercent=$impact.Uplift;ImpactBasis=$impact.Basis;CurrentHourlyRetailPrice=if ($currentRate) {$currentRate.retailPrice} else {$null};Currency=$CurrencyCode;CurrentMeterName=if ($currentRate) {$currentRate.meterName} else {''};CurrentMeterId=if ($currentRate) {$currentRate.meterId} else {''};CurrentSkuId=if ($currentRate) {$currentRate.skuId} else {''};MonthlyHoursAssumption=$MonthlyHours
            CurrentMonthlyGross=$currentGross;ProjectedMonthlyGross=$futureGross;DiscountScenarioPercent=$DiscountPercent;CurrentMonthlyAfterDiscount=$currentNet;ProjectedMonthlyAfterDiscount=$futureNet;EstimatedMonthlyIncreaseAfterDiscount=$delta;EstimatedAnnualIncreaseAfterDiscount=if ($null -ne $delta) {[math]::Round($delta*12,2)} else {$null}
            BestAlternativeSku=if ($best) {$best.CandidateSku} else {''};BestAlternativeImpact=if ($best) {$best.CandidateImpact} else {''};BestAlternativeMonthlyCost=if ($best) {$best.EstimatedMonthlyAfterDiscount} else {$null};EstimatedMonthlySavings=if ($best) {$best.EstimatedMonthlySavings} else {$null};AlternativeStatus=if ($best) {'Candidate found - validate manually'} else {'No lower-cost candidate identified'}
        })
        if ($best) { $Recommendations.Add($best) }
    }
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$detailCsv=Join-Path $OutputPath "01-VM-Cost-Impact-Detail-$stamp.csv"
$recommendCsv=Join-Path $OutputPath "02-VM-SKU-Recommendations-$stamp.csv"
$candidateCsv=Join-Path $OutputPath "03-Alternative-Candidate-Audit-$stamp.csv"
$auditCsv=Join-Path $OutputPath "04-Run-Audit-Trail-$stamp.csv"
$summaryCsv=Join-Path $OutputPath "05-Regional-Cost-Summary-$stamp.csv"
$htmlPath=Join-Path $OutputPath "Azure-VM-Price-Impact-Dashboard-$stamp.html"
$manifestPath=Join-Path $OutputPath "Run-Manifest-$stamp.json"
$Inventory | Sort-Object Subscription,Region,VmName | Export-Csv -NoTypeInformation -Encoding utf8 -Path $detailCsv
$Recommendations | Export-Csv -NoTypeInformation -Encoding utf8 -Path $recommendCsv
$CandidateAudit | Sort-Object Subscription,Region,VmName,EstimatedMonthlyAfterDiscount | Export-Csv -NoTypeInformation -Encoding utf8 -Path $candidateCsv
$Audit | Export-Csv -NoTypeInformation -Encoding utf8 -Path $auditCsv
$summary=foreach ($group in ($Inventory | Group-Object Region)) {
    $priced=@($group.Group | Where-Object { $null -ne $_.CurrentMonthlyGross })
    [pscustomobject]@{ReportId=$ReportId;Region=$group.Name;VmCount=$group.Count;PricedVmCount=$priced.Count;CurrentMonthlyGross=[math]::Round((($priced | Measure-Object CurrentMonthlyGross -Sum).Sum),2);ProjectedMonthlyGross=[math]::Round((($priced | Measure-Object ProjectedMonthlyGross -Sum).Sum),2);EstimatedMonthlyIncreaseAfterDiscount=[math]::Round((($priced | Measure-Object EstimatedMonthlyIncreaseAfterDiscount -Sum).Sum),2)}
}
$summary | Export-Csv -NoTypeInformation -Encoding utf8 -Path $summaryCsv
$totalCurrent=[math]::Round((($Inventory | Measure-Object CurrentMonthlyAfterDiscount -Sum).Sum),2)
$totalFuture=[math]::Round((($Inventory | Measure-Object ProjectedMonthlyAfterDiscount -Sum).Sum),2)
$totalDelta=[math]::Round(($totalFuture-$totalCurrent),2)
$manifest=[pscustomobject]@{ReportId=$ReportId;GeneratedUtc=$GeneratedUtc;EffectiveDate=$EffectiveDate.ToString('yyyy-MM-dd');SubscriptionsScanned=$subscriptions.Count;VmCount=$Inventory.Count;DiscountScenarioPercent=$DiscountPercent;MonthlyHoursAssumption=$MonthlyHours;Currency=$CurrencyCode;RetailApiAlreadyIncludesIncrease=[bool]$RetailApiAlreadyIncludesIncrease;LegacyScenarioEnabled=[bool]$ApplyLegacyV1V2Estimate;LegacyV1V2Percent=if ($ApplyLegacyV1V2Estimate) {$LegacyV1V2Percent} else {$null};CurrentMonthlyAfterDiscount=$totalCurrent;ProjectedMonthlyAfterDiscount=$totalFuture;EstimatedMonthlyIncrease=$totalDelta;ReadOnly=$true;Files=@($detailCsv,$recommendCsv,$candidateCsv,$auditCsv,$summaryCsv,$htmlPath)}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding utf8
$style='<style>body{font-family:Segoe UI,Arial,sans-serif;background:#f3f6fa;color:#172338;margin:0;padding:24px}h1{background:#102b4e;color:#fff;padding:22px;border-radius:10px}table{border-collapse:collapse;width:100%;background:#fff;margin:18px 0}th,td{border:1px solid #d9e2ec;padding:8px;text-align:left;font-size:12px}th{background:#e9f0f7}.note{padding:14px;background:#fff4d6;border-left:4px solid #d69e2e}</style>'
$summaryHtml=$summary | ConvertTo-Html -Fragment -PreContent '<h2>Regional summary</h2>'
$topHtml=$Inventory | Sort-Object EstimatedMonthlyIncreaseAfterDiscount -Descending | Select-Object -First 50 Subscription,Region,VmName,VmSize,ImpactStatus,UpliftPercent,CurrentMonthlyAfterDiscount,ProjectedMonthlyAfterDiscount,EstimatedMonthlyIncreaseAfterDiscount,BestAlternativeSku | ConvertTo-Html -Fragment -PreContent '<h2>VM impact detail (top 50)</h2>'
$html=ConvertTo-Html -Title 'Azure VM Price Impact & SKU Recommender' -Head $style -Body "<h1>Azure VM Price Impact &amp; SKU Recommender</h1><p>Report $ReportId | Generated UTC $GeneratedUtc | Modelled effective date $($EffectiveDate.ToString('yyyy-MM-dd')) | Currency $CurrencyCode | Discount scenario $DiscountPercent%</p><div class='note'><b>Read-only planning estimate.</b> Validate tenant advisory, billing meter, negotiated rate and candidate workload compatibility. No Azure resource was modified.</div><h2>Summary</h2><p>VMs: $($Inventory.Count) | Current monthly after discount: $totalCurrent $CurrencyCode | Projected monthly after discount: $totalFuture $CurrencyCode | Estimated monthly change: $totalDelta $CurrencyCode</p>$summaryHtml$topHtml<p>CSV and JSON audit files are stored alongside this dashboard.</p>"
$html | Set-Content -Path $htmlPath -Encoding utf8
Write-Host "Assessment complete. Report ID: $ReportId" -ForegroundColor Green
Write-Host "VMs discovered: $($Inventory.Count); recommendations: $($Recommendations.Count); candidate audit rows: $($CandidateAudit.Count)"
Write-Host "Estimated monthly increase after discount: $totalDelta $CurrencyCode"
Write-Host "Output folder: $OutputPath"
Write-Host 'Estimate is a full-month run-rate scenario and is not based on observed usage hours or VM power state.' -ForegroundColor Yellow
Write-Host 'Read-only assessment complete. No Azure resource was modified.' -ForegroundColor Yellow