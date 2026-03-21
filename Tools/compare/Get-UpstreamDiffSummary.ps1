[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [string]$UpstreamBranch = 'main'
)

$resolvedRepo = (Resolve-Path $RepoPath).Path

function Get-GitOutput {
    param(
        [string]$Path,
        [string[]]$Arguments
    )

    $output = & git -C $Path @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed: git -C $Path $($Arguments -join ' ')"
    }

    return ($output -join "`n").Trim()
}

$head = Get-GitOutput -Path $resolvedRepo -Arguments @('rev-parse', 'HEAD')
$upstream = Get-GitOutput -Path $resolvedRepo -Arguments @('rev-parse', "upstream/$UpstreamBranch")

if ($head -eq $upstream) {
    [PSCustomObject]@{
        RepoPath = $resolvedRepo
        Head = $head
        Upstream = $upstream
        Status = 'exact-match'
        Diff = @()
    }
    return
}

$summary = Get-GitOutput -Path $resolvedRepo -Arguments @('diff', '--shortstat', "upstream/$UpstreamBranch", 'HEAD')
$files = Get-GitOutput -Path $resolvedRepo -Arguments @('diff', '--name-status', "upstream/$UpstreamBranch", 'HEAD')

[PSCustomObject]@{
    RepoPath = $resolvedRepo
    Head = $head
    Upstream = $upstream
    Status = 'diverged'
    Summary = $summary
    Diff = $files -split "`n"
}
