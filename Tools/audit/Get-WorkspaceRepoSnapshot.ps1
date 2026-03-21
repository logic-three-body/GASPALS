[CmdletBinding()]
param(
    [switch]$AsJson
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$repos = @(
    @{ Name = 'GASPALS'; Path = (Join-Path $repoRoot ''); UpstreamBranch = 'main' },
    @{ Name = 'ControlOperators'; Path = (Join-Path $repoRoot 'References\ControlOperators'); UpstreamBranch = 'main' },
    @{ Name = 'Motion-Matching'; Path = (Join-Path $repoRoot 'References\Motion-Matching'); UpstreamBranch = 'main' },
    @{ Name = 'Learned-Motion-Matching'; Path = (Join-Path $repoRoot 'References\Learned-Motion-Matching'); UpstreamBranch = 'master' },
    @{ Name = 'Unreal-3rd-Person-Parkour'; Path = (Join-Path $repoRoot 'References\Unreal-3rd-Person-Parkour'); UpstreamBranch = 'main' },
    @{ Name = 'Learned_Motion_Matching_Training'; Path = (Join-Path $repoRoot 'References\Learned_Motion_Matching_Training'); UpstreamBranch = 'main' },
    @{ Name = 'Learned_Motion_Matching_UE5'; Path = (Join-Path $repoRoot 'References\Learned_Motion_Matching_Training\Learned_Motion_Matching_UE5'); UpstreamBranch = 'main' }
)

function Get-GitOutput {
    param(
        [string]$Path,
        [string[]]$Arguments
    )

    $output = & git -C $Path @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return ($output -join "`n").Trim()
}

$rows = foreach ($repo in $repos) {
    if (-not (Test-Path $repo.Path)) {
        continue
    }

    $origin = Get-GitOutput -Path $repo.Path -Arguments @('remote', 'get-url', 'origin')
    $branch = Get-GitOutput -Path $repo.Path -Arguments @('branch', '--show-current')
    $sha = Get-GitOutput -Path $repo.Path -Arguments @('rev-parse', 'HEAD')
    $upstreamUrl = Get-GitOutput -Path $repo.Path -Arguments @('remote', 'get-url', 'upstream')
    $upstreamSha = if ($upstreamUrl) {
        Get-GitOutput -Path $repo.Path -Arguments @('rev-parse', "upstream/$($repo.UpstreamBranch)")
    }
    else {
        $null
    }

    $status = if ($upstreamSha) {
        if ($sha -eq $upstreamSha) { 'exact-match' } else { 'diverged' }
    }
    else {
        'no-upstream'
    }

    [PSCustomObject]@{
        Name = $repo.Name
        Path = $repo.Path
        Origin = $origin
        Branch = $branch
        Head = $sha
        Upstream = $upstreamUrl
        UpstreamBranch = $repo.UpstreamBranch
        UpstreamHead = $upstreamSha
        Status = $status
    }
}

if ($AsJson) {
    $rows | ConvertTo-Json -Depth 4
}
else {
    $rows | Format-Table -AutoSize
}
