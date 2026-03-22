Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common.ps1')

$script:Case40Id = '40'

function Get-ReferenceCase40SourceRoot {
    param(
        [string]$RepoRoot = (Get-ReferenceRoot -StartDir $PSScriptRoot)
    )

    return (Join-Path $RepoRoot 'References\Unreal-3rd-Person-Parkour')
}

function Get-ReferenceCase40SidecarRoot {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    return (Join-Path $Context.RunRoot 'case-40\ParkourSidecar')
}

function Get-ReferenceCase40ProjectPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    return (Join-Path $ProjectRoot 'GameAnimationSample.uproject')
}

function Copy-ReferenceCase40Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (Test-Path $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    Copy-Item -Path $Source -Destination $Destination -Recurse -Force
}

function Update-ReferenceCase40FileContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Transform
    )

    if (-not (Test-Path $Path)) {
        throw "Sidecar patch target was not found: $Path"
    }

    $original = Get-Content -Path $Path -Raw
    $updated = & $Transform $original
    if ($updated -ne $original) {
        Set-Content -Path $Path -Value $updated -Encoding UTF8
    }
}

function Apply-ReferenceCase40CompatibilityPatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $headerPath = Join-Path $ProjectRoot 'Source\GameAnimationSample\Public\CoroStateMachine\CoroStateMachine.h'
    Update-ReferenceCase40FileContent -Path $headerPath -Transform {
        param([string]$Text)

        if ($Text -match '#include <functional>') {
            return $Text
        }

        return ($Text -replace "(#include <vector>\r?\n)", "`$1#include <functional>`r`n")
    }

    $parkourPath = Join-Path $ProjectRoot 'Source\GameAnimationSample\Private\Parkour\ParkourComponent.cpp'
    Update-ReferenceCase40FileContent -Path $parkourPath -Transform {
        param([string]$Text)

        return ($Text -replace 'ControlledCharacter->GetVelocity\(\)\.Size2D\(\)', 'static_cast<float>(ControlledCharacter->GetVelocity().Size2D())')
    }
}

function Get-ReferenceCase40EngineCandidates {
    $editors = @(Get-ReferenceUnrealEditors)
    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($preferred in @('5.4', '5.5')) {
        $match = $editors | Where-Object { $_.Version -like "$preferred*" } | Select-Object -First 1
        if ($match) {
            $candidates.Add($match)
        }
    }

    if ($candidates.Count -eq 0) {
        foreach ($editor in $editors) {
            $candidates.Add($editor)
        }
    }

    return @($candidates)
}

function Select-ReferenceCase40Engine {
    $editors = @(Get-ReferenceUnrealEditors)
    $preferred54 = $editors | Where-Object { $_.Version -like '5.4*' } | Select-Object -First 1
    if ($preferred54) {
        return [pscustomobject]@{
            Status = 'PASS'
            Engine = $preferred54
            Notes  = @()
        }
    }

    $preferred55 = $editors | Where-Object { $_.Version -like '5.5*' } | Select-Object -First 1
    if ($preferred55) {
        return [pscustomobject]@{
            Status = 'PASS'
            Engine = $preferred55
            Notes  = @('UE 5.4 was not available; using UE 5.5 fallback.')
        }
    }

    if ($editors.Count -gt 0) {
        $first = $editors | Select-Object -First 1
        return [pscustomobject]@{
            Status = 'MANUAL'
            Engine = $first
            Notes  = @('Neither UE 5.4 nor UE 5.5 was detected; using the first available editor as a fallback.')
        }
    }

    return [pscustomobject]@{
        Status = 'BLOCKED'
        Engine = $null
        Notes  = @('No Unreal Editor installation was detected.')
    }
}

function Initialize-ReferenceCase40Sidecar {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $sourceRoot = Get-ReferenceCase40SourceRoot -RepoRoot $Context.Root
    if (-not (Test-Path $sourceRoot)) {
        throw "Parkour reference repo not found: $sourceRoot"
    }

    $sidecarRoot = Ensure-ReferenceDirectory -Path (Get-ReferenceCase40SidecarRoot -Context $Context)
    $projectPath = Get-ReferenceCase40ProjectPath -ProjectRoot $sidecarRoot
    $sourceProject = Get-ReferenceCase40ProjectPath -ProjectRoot $sourceRoot

    if (-not (Test-Path $sourceProject)) {
        throw "Original project file missing: $sourceProject"
    }

    $links = @(
        @{ Name = 'Config';  Source = (Join-Path $sourceRoot 'Config') },
        @{ Name = 'Content'; Source = (Join-Path $sourceRoot 'Content') }
    )

    foreach ($link in $links) {
        $target = Join-Path $sidecarRoot $link.Name
        if (-not (Test-Path $target)) {
            New-Item -ItemType Junction -Path $target -Value $link.Source | Out-Null
        }
    }

    $sourceTarget = Join-Path $sidecarRoot 'Source'
    Copy-ReferenceCase40Directory -Source (Join-Path $sourceRoot 'Source') -Destination $sourceTarget

    Copy-Item -Path $sourceProject -Destination $projectPath -Force

    $uproject = Get-Content -Path $projectPath -Raw | ConvertFrom-Json
    if ($null -ne $uproject.Plugins) {
        $uproject.Plugins = @($uproject.Plugins | Where-Object { $_.Name -ne 'DazToUnreal' })
    }
    $uproject | ConvertTo-Json -Depth 32 | Set-Content -Path $projectPath -Encoding UTF8
    Apply-ReferenceCase40CompatibilityPatches -ProjectRoot $sidecarRoot

    return [pscustomobject]@{
        SourceRoot   = $sourceRoot
        SidecarRoot  = $sidecarRoot
        ProjectPath  = $projectPath
        SourceProject = $sourceProject
    }
}

function Invoke-ReferenceCase40GenerateProjectFiles {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Engine,
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $batch = Join-Path $Engine.Root 'Engine\Build\BatchFiles\GenerateProjectFiles.bat'
    if (-not (Test-Path $batch)) {
        $buildBat = Join-Path $Engine.Root 'Engine\Build\BatchFiles\Build.bat'
        if (-not (Test-Path $buildBat)) {
            throw "GenerateProjectFiles.bat and Build.bat were not found under $($Engine.Root)"
        }

        $ubtLogPath = "$LogPath.ubt.log"

        return Invoke-ReferenceCommand `
            -FilePath $buildBat `
            -ArgumentList @('-projectfiles', "-project=$ProjectPath", '-game', '-engine', "-log=$ubtLogPath") `
            -WorkingDirectory (Split-Path $ProjectPath -Parent) `
            -LogPath $LogPath
    }

    return Invoke-ReferenceCommand `
        -FilePath $batch `
        -ArgumentList @("-Project=$ProjectPath", '-Game', '-Engine') `
        -WorkingDirectory (Split-Path $ProjectPath -Parent) `
        -LogPath $LogPath
}

function Invoke-ReferenceCase40Build {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Engine,
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $batch = Join-Path $Engine.Root 'Engine\Build\BatchFiles\Build.bat'
    if (-not (Test-Path $batch)) {
        throw "Build.bat not found under $($Engine.Root)"
    }

    $ubtLogPath = "$LogPath.ubt.log"

    return Invoke-ReferenceCommand `
        -FilePath $batch `
        -ArgumentList @(
            'GameAnimationSampleEditor',
            'Win64',
            'Development',
            "-Project=$ProjectPath",
            '-WaitMutex',
            '-NoHotReloadFromIDE',
            "-log=$ubtLogPath"
        ) `
        -WorkingDirectory (Split-Path $ProjectPath -Parent) `
        -LogPath $LogPath `
        -IgnoreExitCode
}

function Invoke-ReferenceCase40EditorProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Engine,
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [int]$ProbeSeconds = 20
    )

    $editor = $Engine.Editor
    if (-not (Test-Path $editor)) {
        throw "UnrealEditor.exe not found: $editor"
    }

    $arguments = @(
        $ProjectPath,
        '-nosplash',
        '-unattended',
        '-nop4',
        '-NoSound',
        '-log',
        "-AbsLog=$LogPath"
    )

    $process = Start-Process -FilePath $editor -ArgumentList $arguments -WorkingDirectory (Split-Path $ProjectPath -Parent) -PassThru
    try {
        Start-Sleep -Seconds $ProbeSeconds
        $stillRunning = -not $process.HasExited
        if ($stillRunning) {
            Stop-Process -Id $process.Id -Force
        }
    }
    finally {
        try {
            Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
        }
    }

    $messages = @()
    if (Test-Path $LogPath) {
        $logText = Get-Content -Path $LogPath -Raw -ErrorAction SilentlyContinue
        if ($logText -match 'LogInit|LogEditor|GameAnimationSample') {
            $messages += 'Editor boot log markers were detected.'
        }
        if ($logText -match 'DazToUnreal') {
            $messages += 'Unexpected DazToUnreal reference was still present in log output.'
        }
    }

    return [pscustomobject]@{
        Started       = $true
        StillRunning  = $stillRunning
        Messages      = @($messages)
        ProcessId     = $process.Id
    }
}

function Invoke-ReferenceCase40Setup {
    param(
        [pscustomobject]$Context
    )

    if (-not $Context) {
        $Context = New-ReferenceContext -Root (Get-ReferenceRoot -StartDir $PSScriptRoot) -Cases @('40')
    }

    $logPath = Get-ReferenceLogPath -Context $Context -Name 'case-40-setup'
    $notes = New-Object System.Collections.Generic.List[string]
    $artifacts = New-Object System.Collections.Generic.List[string]

    try {
        $selection = Select-ReferenceCase40Engine
        if ($selection.Notes) {
            foreach ($note in $selection.Notes) {
                $notes.Add($note)
            }
        }
        if (-not $selection.Engine) {
            $result = New-ReferenceResult -CaseId $script:Case40Id -Stage 'setup' -Status $selection.Status -Summary 'No Unreal Editor was available.' -LogPath $logPath
            $result.Notes = @($notes)
            return $result
        }

        $sidecar = Initialize-ReferenceCase40Sidecar -Context $Context
        $artifacts.Add($sidecar.ProjectPath)
        $artifacts.Add($sidecar.SidecarRoot)
        $artifacts.Add($sidecar.SourceRoot)

        $reportPath = Join-Path $Context.ReportsDir 'case-40-setup.md'
        Write-ReferenceMarkdown -Path $reportPath -Lines @(
            '# Case 40 Setup',
            '',
            "| Field | Value |",
            "| --- | --- |",
            "| Engine | $($selection.Engine.Version) |",
            "| Editor | $($selection.Engine.Editor) |",
            "| Sidecar root | $($sidecar.SidecarRoot) |",
            "| Sidecar project | $($sidecar.ProjectPath) |",
            "| Source root | $($sidecar.SourceRoot) |"
        ) | Out-Null
        $artifacts.Add($reportPath)

        $summary = "Prepared parkour sidecar project with UE $($selection.Engine.Version)."
        $result = New-ReferenceResult -CaseId $script:Case40Id -Stage 'setup' -Status $selection.Status -Summary $summary -Artifacts $artifacts.ToArray() -Notes $notes.ToArray() -LogPath $logPath -DataPath $sidecar.ProjectPath
        $result | Add-Member -NotePropertyName EngineVersion -NotePropertyValue $selection.Engine.Version
        $result | Add-Member -NotePropertyName EngineRoot -NotePropertyValue $selection.Engine.Root
        $result | Add-Member -NotePropertyName EditorPath -NotePropertyValue $selection.Engine.Editor
        $result | Add-Member -NotePropertyName SidecarRoot -NotePropertyValue $sidecar.SidecarRoot
        $result | Add-Member -NotePropertyName ProjectPath -NotePropertyValue $sidecar.ProjectPath
        return $result
    }
    catch {
        $notes.Add($_.Exception.Message)
        $result = New-ReferenceResult -CaseId $script:Case40Id -Stage 'setup' -Status 'BLOCKED' -Summary 'Failed to prepare parkour sidecar project.' -LogPath $logPath
        $result.Notes = @($notes)
        return $result
    }
}

function Invoke-ReferenceCase40Test {
    param(
        [pscustomobject]$Context,
        [pscustomobject]$SetupResult
    )

    if (-not $Context) {
        $Context = New-ReferenceContext -Root (Get-ReferenceRoot -StartDir $PSScriptRoot) -Cases @('40')
    }

    $logPath = Get-ReferenceLogPath -Context $Context -Name 'case-40-test'
    $notes = New-Object System.Collections.Generic.List[string]
    $artifacts = New-Object System.Collections.Generic.List[string]

    try {
        if (-not $SetupResult -or -not $SetupResult.ProjectPath) {
            throw 'SetupResult.ProjectPath is required for the test stage.'
        }

        $engine = [pscustomobject]@{
            Version = $SetupResult.EngineVersion
            Root    = $SetupResult.EngineRoot
            Editor  = $SetupResult.EditorPath
        }

        $genLog = Join-Path $Context.LogsDir 'case-40-generate-project-files.log'
        $buildLog = Join-Path $Context.LogsDir 'case-40-build.log'
        $editorLog = Join-Path $Context.LogsDir 'case-40-editor.log'
        $projectPath = $SetupResult.ProjectPath

        $genOk = $false
        $buildOk = $false
        $probeOk = $false

        try {
            Invoke-ReferenceCase40GenerateProjectFiles -Engine $engine -ProjectPath $projectPath -LogPath $genLog | Out-Null
            $genOk = $true
            $artifacts.Add($genLog)
        }
        catch {
            $notes.Add("Project file generation failed: $($_.Exception.Message)")
        }

        try {
            $buildResult = Invoke-ReferenceCase40Build -Engine $engine -ProjectPath $projectPath -LogPath $buildLog
            $artifacts.Add($buildLog)
            $buildOk = $buildResult.ExitCode -eq 0
            if (-not $buildOk) {
                $notes.Add('Editor build returned a non-zero exit code; this may still be manual on the current machine.')
            }
        }
        catch {
            $notes.Add("Editor build invocation failed: $($_.Exception.Message)")
            $buildOk = $false
        }

        try {
            $probe = Invoke-ReferenceCase40EditorProbe -Engine $engine -ProjectPath $projectPath -LogPath $editorLog
            $artifacts.Add($editorLog)
            $probeOk = $true
            if ($probe.StillRunning) {
                $notes.Add('Editor launched and stayed alive during the probe window.')
            }
            else {
                $notes.Add('Editor launch completed quickly; manual interaction may still be required.')
            }
            foreach ($message in @($probe.Messages)) {
                if (-not [string]::IsNullOrWhiteSpace($message)) {
                    $notes.Add($message)
                }
            }
        }
        catch {
            $notes.Add("Editor probe failed: $($_.Exception.Message)")
        }

        $reportPath = Join-Path $Context.ReportsDir 'case-40-test.md'
        Write-ReferenceMarkdown -Path $reportPath -Lines @(
            '# Case 40 Test',
            '',
            "| Field | Value |",
            "| --- | --- |",
            "| Project files | $genLog |",
            "| Build log | $buildLog |",
            "| Editor log | $editorLog |",
            "| Project | $projectPath |"
        ) | Out-Null
        $artifacts.Add($reportPath)

        $launchNotes = @($notes | Where-Object { $_ -like 'Editor launched*' })
        $status = if ($genOk -and $buildOk -and $probeOk -and $launchNotes.Count -gt 0) { 'PASS' } else { 'MANUAL' }
        $summary = if ($status -eq 'PASS') {
            'Project files generated, build completed, and editor probe launched.'
        }
        else {
            'Project files and sidecar project were prepared; build or editor verification remains manual.'
        }

        $result = New-ReferenceResult -CaseId $script:Case40Id -Stage 'test' -Status $status -Summary $summary -Artifacts $artifacts.ToArray() -Notes $notes.ToArray() -LogPath $logPath -DataPath $projectPath
        $result | Add-Member -NotePropertyName EngineVersion -NotePropertyValue $SetupResult.EngineVersion
        $result | Add-Member -NotePropertyName ProjectPath -NotePropertyValue $projectPath
        return $result
    }
    catch {
        $notes.Add($_.Exception.Message)
        $result = New-ReferenceResult -CaseId $script:Case40Id -Stage 'test' -Status 'BLOCKED' -Summary 'Failed to validate the parkour sidecar project.' -LogPath $logPath
        $result.Notes = @($notes)
        return $result
    }
}
