Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReferenceCase10Paths {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $trainingRoot = Join-Path $Context.Root 'References\Learned_Motion_Matching_Training'
    $ueRoot = Join-Path $trainingRoot 'Learned_Motion_Matching_UE5'
    return [pscustomobject]@{
        TrainingRoot  = $trainingRoot
        CasesRoot     = Join-Path $trainingRoot 'scripts\cases'
        ModelRoot     = Join-Path $trainingRoot 'ModelTraining'
        ModelsRoot    = Join-Path $trainingRoot 'ModelTraining\Models'
        DatabaseRoot  = Join-Path $trainingRoot 'ModelTraining\Database'
        UeRoot        = $ueRoot
        UProject      = Join-Path $ueRoot 'Testing.uproject'
        ImportLmmRoot = Join-Path $ueRoot 'Import\LMM'
    }
}

function Get-ReferenceDetectedFbxSdkRoot {
    $candidateRoots = @(
        $env:FBXSDK_ROOT,
        'C:\Program Files\Autodesk\FBX\FBX SDK\2020.3.2',
        'C:\Program Files\Autodesk\FBX\FBX SDK\2020.3.9',
        'C:\Program Files\Autodesk\FBX\FBX SDK\2020.2.1',
        'C:\Program Files\Side Effects Software\Houdini 21.0.512',
        'C:\Program Files\Side Effects Software\Houdini 20.5.278'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($root in $candidateRoots) {
        if (Test-Path $root) {
            return $root
        }
    }
    return $null
}

function Try-ReferenceFbxSdkBootstrap {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $existing = Get-ReferenceDetectedFbxSdkRoot
    if ($existing) {
        return [pscustomobject]@{
            Status = 'PASS'
            Root   = $existing
            Notes  = @("Detected FBX SDK root: $existing")
        }
    }

    $fbxDir = Ensure-ReferenceDirectory -Path (Join-Path $Context.ExternalsDir 'AutodeskFBX')
    $pagePath = Join-Path $fbxDir 'fbx-sdk-page.html'
    Download-ReferenceFile -Uri 'https://aps.autodesk.com/developer/overview/fbx-sdk' -Destination $pagePath | Out-Null

    $html = Get-Content -Path $pagePath -Raw
    $url = [regex]::Match(
        $html,
        'https://[^"]+/fbx202032_fbxsdk_[^"]+_win\.exe',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    ).Value

    if ([string]::IsNullOrWhiteSpace($url)) {
        return [pscustomobject]@{
            Status = 'MANUAL'
            Root   = ''
            Notes  = @(
                "Downloaded Autodesk FBX SDK landing page to $pagePath",
                'Could not resolve a direct Windows installer URL for FBX SDK 2020.3.2 automatically.'
            )
        }
    }

    $installerPath = Join-Path $fbxDir (Split-Path $url -Leaf)
    if (-not (Test-Path $installerPath)) {
        Download-ReferenceFile -Uri $url -Destination $installerPath | Out-Null
    }

    $installLog = Join-Path $Context.LogsDir 'fbxsdk-install.log'
    try {
        Invoke-ReferenceCommand -FilePath $installerPath -ArgumentList @('/S') -LogPath $installLog -IgnoreExitCode | Out-Null
    }
    catch {
    }

    $installed = Get-ReferenceDetectedFbxSdkRoot
    if ($installed) {
        $env:FBXSDK_ROOT = $installed
        return [pscustomobject]@{
            Status = 'PASS'
            Root   = $installed
            Notes  = @(
                "Downloaded FBX SDK installer to $installerPath",
                "Detected installed FBX SDK root: $installed"
            )
        }
    }

    return [pscustomobject]@{
        Status = 'MANUAL'
        Root   = ''
        Notes  = @(
            "Downloaded FBX SDK installer to $installerPath",
            "Silent install did not yield a detectable FBX SDK root. See $installLog"
        )
    }
}

function Copy-ReferenceLmmArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths
    )

    Ensure-ReferenceDirectory -Path $Paths.ImportLmmRoot | Out-Null

    $copyPlan = @(
        @{ Source = Join-Path $Paths.ModelsRoot 'decompressor.onnx'; Target = Join-Path $Paths.ImportLmmRoot 'decompressor.onnx' },
        @{ Source = Join-Path $Paths.ModelsRoot 'projector.onnx';    Target = Join-Path $Paths.ImportLmmRoot 'projector.onnx' },
        @{ Source = Join-Path $Paths.ModelsRoot 'stepper.onnx';      Target = Join-Path $Paths.ImportLmmRoot 'stepper.onnx' },
        @{ Source = Join-Path $Paths.DatabaseRoot 'features.bin';    Target = Join-Path $Paths.ImportLmmRoot 'features.bin' }
    )

    $artifacts = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $copyPlan) {
        if (Test-Path $entry.Source) {
            Copy-Item -Path $entry.Source -Destination $entry.Target -Force
            $artifacts.Add($entry.Target)

            $sourceData = $entry.Source + '.data'
            $targetData = $entry.Target + '.data'
            if (Test-Path $sourceData) {
                Copy-Item -Path $sourceData -Destination $targetData -Force
                $artifacts.Add($targetData)
            }
            elseif (Test-Path $targetData) {
                Remove-Item -Path $targetData -Force -ErrorAction SilentlyContinue
                $targetDataMeta = $targetData + '.meta'
                if (Test-Path $targetDataMeta) {
                    Remove-Item -Path $targetDataMeta -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    return @($artifacts)
}

function Invoke-ReferenceCase10Setup {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $paths = Get-ReferenceCase10Paths -Context $Context
    $log = Get-ReferenceLogPath -Context $Context -Name 'case-10-setup'
    $notes = New-Object System.Collections.Generic.List[string]

    Ensure-ReferenceCondaEnv -Context $Context | Out-Null

    $git = Resolve-ReferenceCommand -Name 'git'
    Invoke-ReferenceCommand -FilePath $git -ArgumentList @('submodule', 'update', '--init', '--recursive') -WorkingDirectory $Context.Root -LogPath $log | Out-Null
    Invoke-ReferenceCommand -FilePath $git -ArgumentList @('lfs', 'pull') -WorkingDirectory $paths.TrainingRoot -LogPath $log | Out-Null

    $fbxBootstrap = Try-ReferenceFbxSdkBootstrap -Context $Context
    foreach ($note in @($fbxBootstrap.Notes)) {
        $notes.Add($note)
    }
    if ($fbxBootstrap.Root) {
        $env:FBXSDK_ROOT = $fbxBootstrap.Root
    }

    $status = if ($fbxBootstrap.Status -eq 'PASS') { 'PASS' } else { 'MANUAL' }
    return New-ReferenceResult -CaseId '10' -Stage 'setup' -Status $status -Summary 'Prepared training repo, git-lfs payloads, and FBX SDK bootstrap attempt.' -Notes @($notes) -LogPath $log -DataPath $paths.TrainingRoot
}

function Invoke-ReferenceCase10Test {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $paths = Get-ReferenceCase10Paths -Context $Context
    $log = Get-ReferenceLogPath -Context $Context -Name 'case-10-test'
    $notes = New-Object System.Collections.Generic.List[string]
    $artifacts = New-Object System.Collections.Generic.List[string]

    Ensure-ReferenceCondaEnv -Context $Context | Out-Null
    $fbxRoot = Get-ReferenceDetectedFbxSdkRoot

    $commands = @()
    if ($fbxRoot) {
        $commands += @{
            Script = Join-Path $paths.CasesRoot 'case-01-dataprocess.ps1'
            Args   = @('-RepoRoot', $paths.TrainingRoot, '-FbxSdkRoot', $fbxRoot)
            UseConda = $false
            UseCommandInvocation = $true
        }
    }
    else {
        $notes.Add('FBX SDK not detected; skipping case-01-dataprocess and expecting downstream steps to fall back where supported.')
    }

    $smokeNIter = if ($Context.Smoke) { '20' } else { '500000' }
    $smokeBatch = if ($Context.Smoke) { '64' } else { '32' }
    $saveEvery = if ($Context.Smoke) { '10' } else { '1000' }
    $device = Get-ReferenceDefaultDevice

    $commands += @(
        @{ Script = Join-Path $paths.CasesRoot 'case-02-generate-db.ps1'; Args = @('-RepoRoot', $paths.TrainingRoot, '-InstallDeps'); UseConda = $true },
        @{ Script = Join-Path $paths.CasesRoot 'case-03-train-decompressor.ps1'; Args = @('-RepoRoot', $paths.TrainingRoot, '-InstallDeps', '-NIter', $smokeNIter, '-Device', $device, '-BatchSize', $smokeBatch, '-SaveEvery', $saveEvery); UseConda = $true },
        @{ Script = Join-Path $paths.CasesRoot 'case-04-train-projector.ps1'; Args = @('-RepoRoot', $paths.TrainingRoot, '-InstallDeps', '-NIter', $smokeNIter, '-Device', $device, '-BatchSize', $smokeBatch, '-SaveEvery', $saveEvery); UseConda = $true },
        @{ Script = Join-Path $paths.CasesRoot 'case-05-train-stepper.ps1'; Args = @('-RepoRoot', $paths.TrainingRoot, '-InstallDeps', '-NIter', $smokeNIter, '-Device', $device, '-BatchSize', $smokeBatch, '-SaveEvery', $saveEvery); UseConda = $true },
        @{ Script = Join-Path $paths.CasesRoot 'case-06-validate-inference.ps1'; Args = @('-RepoRoot', $paths.TrainingRoot, '-InstallDeps'); UseConda = $true }
    )

    $caseEnvironment = @{}
    if ($fbxRoot) {
        $caseEnvironment['FBXSDK_ROOT'] = $fbxRoot
    }

    try {
        foreach ($entry in $commands) {
            $commandArgs = ((@('-ExecutionPolicy', 'Bypass', '-File', $entry.Script)) + $entry.Args)
            if ($entry.UseConda) {
                Invoke-ReferenceConda `
                    -Context $Context `
                    -Executable 'powershell' `
                    -Arguments $commandArgs `
                    -WorkingDirectory $paths.TrainingRoot `
                    -LogPath $log `
                    -Environment $caseEnvironment | Out-Null
            }
            else {
                if ($entry.UseCommandInvocation) {
                    $escapedScript = $entry.Script.Replace("'", "''")
                    $escapedRepoRoot = $paths.TrainingRoot.Replace("'", "''")
                    $escapedFbxRoot = $fbxRoot.Replace("'", "''")
                    $commandText = "& '$escapedScript' -RepoRoot '$escapedRepoRoot' -FbxSdkRoot '$escapedFbxRoot'"
                    Invoke-ReferenceCommand `
                        -FilePath 'powershell' `
                        -ArgumentList @('-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
                        -WorkingDirectory $paths.TrainingRoot `
                        -LogPath $log `
                        -Environment $caseEnvironment | Out-Null
                }
                else {
                    Invoke-ReferenceCommand `
                        -FilePath 'powershell' `
                        -ArgumentList $commandArgs `
                        -WorkingDirectory $paths.TrainingRoot `
                        -LogPath $log `
                        -Environment $caseEnvironment | Out-Null
                }
            }
        }
    }
    catch {
        $notes.Add($_.Exception.Message)
        return New-ReferenceResult -CaseId '10' -Stage 'test' -Status 'BLOCKED' -Summary 'Training pipeline failed before all case scripts completed.' -Notes @($notes) -LogPath $log -DataPath $paths.ModelRoot
    }

    foreach ($artifact in Copy-ReferenceLmmArtifacts -Paths $paths) {
        $artifacts.Add($artifact)
    }

    $validationReport = Join-Path $paths.ModelRoot 'Misc\onnx_validation_report.md'
    if (Test-Path $validationReport) {
        $artifacts.Add($validationReport)
    }

    $status = if ($fbxRoot) { 'PASS' } else { 'MANUAL' }
    $summary = if ($fbxRoot) {
        'Ran the full LMM training pipeline and synced generated artifacts into the UE5 companion import folder.'
    }
    else {
        'Ran LMM case-02..06 and synced generated artifacts, but full case-01 validation remains manual until FBX SDK is configured.'
    }

    return New-ReferenceResult -CaseId '10' -Stage 'test' -Status $status -Summary $summary -Artifacts @($artifacts) -Notes @($notes) -LogPath $log -DataPath $paths.ModelRoot
}

function Invoke-ReferenceCase11Setup {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $paths = Get-ReferenceCase10Paths -Context $Context
    $ue53 = Get-ReferenceUnrealEditor -PreferredVersions @('5.3')
    $notes = @()
    if (-not $ue53) {
        $notes += 'UE 5.3 was not detected. Case 11 test will be blocked until UE 5.3.x is installed.'
        $status = 'BLOCKED'
    }
    else {
        $notes += "Using UE editor at $($ue53.Editor)"
        $status = 'PASS'
    }

    return New-ReferenceResult -CaseId '11' -Stage 'setup' -Status $status -Summary 'Prepared UE5 companion validation prerequisites.' -Notes $notes -DataPath $paths.UProject
}

function Invoke-ReferenceCase11Test {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $paths = Get-ReferenceCase10Paths -Context $Context
    $log = Get-ReferenceLogPath -Context $Context -Name 'case-11-test'
    $notes = New-Object System.Collections.Generic.List[string]
    $ue53 = Get-ReferenceUnrealEditor -PreferredVersions @('5.3')
    if (-not $ue53) {
        return New-ReferenceResult -CaseId '11' -Stage 'test' -Status 'BLOCKED' -Summary 'UE 5.3.x is required for the companion project validation.' -LogPath $log -DataPath $paths.UProject
    }

    if (-not (Test-Path $paths.UProject)) {
        return New-ReferenceResult -CaseId '11' -Stage 'test' -Status 'BLOCKED' -Summary 'Testing.uproject was not found.' -LogPath $log -DataPath $paths.UProject
    }

    $buildBat = Join-Path $ue53.Root 'Engine\Build\BatchFiles\Build.bat'
    if (-not (Test-Path $buildBat)) {
        return New-ReferenceResult -CaseId '11' -Stage 'test' -Status 'BLOCKED' -Summary 'UE Build.bat was not found.' -LogPath $log -DataPath $paths.UProject
    }

    $selectedConfig = $null
    $selectedCompilerVersion = ''
    $buildSucceeded = $false
    foreach ($config in @('Debug', 'DebugGame', 'Development')) {
        foreach ($compilerVersion in @('', '14.38.33130')) {
            $buildArgs = @('TestingEditor', 'Win64', $config, $paths.UProject, '-WaitMutex', '-FromMsBuild')
            if (-not [string]::IsNullOrWhiteSpace($compilerVersion)) {
                $buildArgs += "-CompilerVersion=$compilerVersion"
            }

            try {
                Invoke-ReferenceCommand -FilePath $buildBat -ArgumentList $buildArgs -WorkingDirectory $paths.UeRoot -LogPath $log | Out-Null
                $selectedConfig = $config
                $selectedCompilerVersion = $compilerVersion
                $buildSucceeded = $true
                break
            }
            catch {
                $compilerLabel = if ([string]::IsNullOrWhiteSpace($compilerVersion)) { 'default compiler selection' } else { "CompilerVersion=$compilerVersion" }
                $notes.Add("UE build configuration $config with $compilerLabel failed: $($_.Exception.Message)")
            }
        }

        if ($buildSucceeded) {
            break
        }
    }

    if (-not $buildSucceeded) {
        return New-ReferenceResult -CaseId '11' -Stage 'test' -Status 'BLOCKED' -Summary 'UE editor build failed for every tested configuration.' -Notes @($notes) -LogPath $log -DataPath $paths.UProject
    }

    $process = Start-Process -FilePath $ue53.Editor -ArgumentList @($paths.UProject, '-NullRHI', '-NoSplash', '-NoSound', '-NoP4', '-Unattended') -WorkingDirectory $paths.UeRoot -PassThru
    Start-Sleep -Seconds 20

    if ($process.HasExited) {
        $notes.Add("UnrealEditor exited early with code $($process.ExitCode). Inspect $log for details.")
        return New-ReferenceResult -CaseId '11' -Stage 'test' -Status 'BLOCKED' -Summary 'UE companion project exited before headless startup validation completed.' -Notes @($notes) -LogPath $log -DataPath $paths.UProject
    }

    Stop-Process -Id $process.Id -Force
    if ([string]::IsNullOrWhiteSpace($selectedCompilerVersion)) {
        $notes.Add("Headless editor launch succeeded long enough to confirm startup using UE build configuration $selectedConfig.")
    }
    else {
        $notes.Add("Headless editor launch succeeded long enough to confirm startup using UE build configuration $selectedConfig and CompilerVersion=$selectedCompilerVersion.")
    }
    $status = 'PASS'
    $summary = if ($selectedConfig -eq 'Debug') {
        if ([string]::IsNullOrWhiteSpace($selectedCompilerVersion)) {
            'Built the UE5 companion in Debug and verified a headless editor startup path.'
        }
        else {
            "Built the UE5 companion in Debug with CompilerVersion=$selectedCompilerVersion and verified a headless editor startup path."
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($selectedCompilerVersion)) {
            "Validated the UE5 companion with fallback configuration $selectedConfig after Debug failed on the current binary engine install."
        }
        else {
            "Validated the UE5 companion with fallback configuration $selectedConfig and CompilerVersion=$selectedCompilerVersion after Debug failed on the current binary engine install."
        }
    }
    return New-ReferenceResult -CaseId '11' -Stage 'test' -Status $status -Summary $summary -Notes @($notes) -LogPath $log -DataPath $paths.UProject
}
