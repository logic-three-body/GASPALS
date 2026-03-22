param(
    [string[]]$Cases = @('all'),
    [switch]$Smoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

function Get-ReferenceCaseScriptPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaseId
    )

    switch ($CaseId) {
        '10' { return Join-Path $PSScriptRoot 'cases\Case-10-11-LMM.ps1' }
        '11' { return Join-Path $PSScriptRoot 'cases\Case-10-11-LMM.ps1' }
        '20' { return Join-Path $PSScriptRoot 'cases\Case-20-ControlOperators.ps1' }
        '30' { return Join-Path $PSScriptRoot 'cases\Case-30-MotionMatching.ps1' }
        '31' { return Join-Path $PSScriptRoot 'cases\Case-31-LearnedMotionMatching.ps1' }
        '40' { return Join-Path $PSScriptRoot 'cases\Case-40-Parkour.ps1' }
        default { throw "Unsupported case id: $CaseId" }
    }
}

function Resolve-ReferenceSetupHandler {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaseId
    )

    $candidates = @(
        "Invoke-ReferenceCase${CaseId}Setup",
        "Setup-ReferenceWalkthroughCase${CaseId}"
    )

    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Name
        }
    }

    throw "No setup handler was found for case $CaseId"
}

function Normalize-ReferenceResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    if ($null -ne $Value.PSObject.Properties['Result']) {
        return $Value.Result
    }

    return $Value
}

$context = New-ReferenceContext -Root (Get-ReferenceRoot) -Cases $Cases -Smoke:$Smoke
$preflight = Get-ReferencePreflight -Context $context
$context | Add-Member -NotePropertyName Preflight -NotePropertyValue $preflight -Force
$preflightReport = Write-ReferencePreflightReport -Context $context -Preflight $preflight

$loadedScripts = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($caseId in $context.Cases) {
    $scriptPath = Get-ReferenceCaseScriptPath -CaseId $caseId
    if (-not $loadedScripts.Contains($scriptPath)) {
        if ((Split-Path $scriptPath -Leaf) -eq 'Case-31-LearnedMotionMatching.ps1') {
            . $scriptPath -RepoRoot $context.Root -Context $context
        }
        else {
            . $scriptPath
        }
        $loadedScripts.Add($scriptPath) | Out-Null
    }
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($caseId in $context.Cases) {
    try {
        $handler = Resolve-ReferenceSetupHandler -CaseId $caseId
        $result = Normalize-ReferenceResult (& $handler -Context $context)
        $results.Add($result)
    }
    catch {
        $results.Add((New-ReferenceResult -CaseId $caseId -Stage 'setup' -Status 'BLOCKED' -Summary $_.Exception.Message))
    }
}

$summaryReport = Write-ReferenceSummaryReport -Context $context -Results $results.ToArray() -Name 'setup-summary'
Write-Host "Preflight report: $preflightReport"
Write-Host "Setup summary: $summaryReport"
