Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common.ps1')

function Get-Case20RepoRoot {
    param(
        [pscustomobject]$Context
    )

    if ($Context -and $Context.Root) {
        return (Join-Path $Context.Root 'References\ControlOperators')
    }

    $candidateRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    return (Join-Path $candidateRoot 'References\ControlOperators')
}

function Get-Case20UvPath {
    $uv = Resolve-ReferenceCommand -Name 'uv'
    if (-not $uv) {
        throw 'uv was not found on PATH.'
    }
    return $uv
}

function Get-Case20PythonDevice {
    param(
        [pscustomobject]$Context,
        [string]$RepoRoot = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $venvPython = Join-Path $RepoRoot '.venv\Scripts\python.exe'
        if (Test-Path $venvPython -PathType Leaf) {
            try {
                $deviceOutput = & $venvPython -c "import torch; print('cuda' if torch.cuda.is_available() else 'cpu')" 2>$null
                if ($LASTEXITCODE -eq 0 -and $deviceOutput) {
                    return ([string]($deviceOutput | Select-Object -Last 1)).Trim()
                }
            }
            catch {
            }
        }
    }

    $gpuNames = @()
    if ($Context -and $Context.PSObject.Properties.Match('Preflight').Count -gt 0 -and $Context.Preflight) {
        $gpuNames = @($Context.Preflight.gpu_names)
    }
    if ($gpuNames.Count -eq 0) {
        $gpuNames = @(Get-ReferenceGpuNames)
    }

    if (Resolve-ReferenceCommand -Name 'nvidia-smi' -and $gpuNames.Count -gt 0) {
        return 'cuda'
    }

    return 'cpu'
}

function Get-Case20VenvPythonPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $venvPython = Join-Path $RepoRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path $venvPython -PathType Leaf)) {
        throw "ControlOperators virtualenv python was not found at: $venvPython"
    }

    return $venvPython
}

function Invoke-Case20Uvx {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$WorkingDirectory = '',
        [string]$LogPath = '',
        [hashtable]$Environment = @{},
        [switch]$IgnoreExitCode
    )

    $uv = Get-Case20UvPath
    $pythonPath = Get-ReferenceCondaPythonPath -Context $Context
    $mergedEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $mergedEnvironment[$key] = $Environment[$key]
    }
    $mergedEnvironment['UV_PYTHON'] = $pythonPath
    $mergedEnvironment['UV_PYTHON_PREFERENCE'] = 'only-system'
    return Invoke-ReferenceCommand `
        -FilePath $uv `
        -ArgumentList $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -LogPath $LogPath `
        -Environment $mergedEnvironment `
        -IgnoreExitCode:$IgnoreExitCode
}

function Invoke-Case20Python {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$LogPath = '',
        [hashtable]$Environment = @{},
        [switch]$IgnoreExitCode
    )

    $python = Get-Case20VenvPythonPath -RepoRoot $RepoRoot
    return Invoke-ReferenceCommand `
        -FilePath $python `
        -ArgumentList $Arguments `
        -WorkingDirectory $RepoRoot `
        -LogPath $LogPath `
        -Environment $Environment `
        -IgnoreExitCode:$IgnoreExitCode
}

function Ensure-Case20ClipArchive {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $downloadsRoot = Ensure-ReferenceDirectory -Path (Join-Path $Context.ExternalsDir 'case-20')
    $zipPath = Join-Path $downloadsRoot 'CLIP-dcba3cb2e2827b402d2701e7e1c7d9fed8a20ef1.zip'
    if (-not (Test-Path $zipPath)) {
        Download-ReferenceFile `
            -Uri 'https://codeload.github.com/openai/CLIP/zip/dcba3cb2e2827b402d2701e7e1c7d9fed8a20ef1' `
            -Destination $zipPath | Out-Null
    }

    return $zipPath
}

function Ensure-Case20Dataset {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $datasetRoot = Ensure-ReferenceDirectory -Path (Join-Path $RepoRoot 'data\lafan1_resolved')
    $bvhRoot = Ensure-ReferenceDirectory -Path (Join-Path $datasetRoot 'bvh')
    $existing = @(Get-ChildItem -Path $bvhRoot -Filter '*.bvh' -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        return [pscustomobject]@{
            Status  = 'PASS'
            Summary = "Reused existing ControlOperators BVH cache in $bvhRoot"
        }
    }

    $localDatasetRoot = Join-Path $Context.Root 'References\Learned_Motion_Matching_Training\Animations\LAFAN1BVH'
    if (-not (Test-Path $localDatasetRoot)) {
        return [pscustomobject]@{
            Status  = 'MANUAL'
            Summary = "No local LAFAN1 cache was found at $localDatasetRoot"
        }
    }

    Copy-Item -Path (Join-Path $localDatasetRoot '*.bvh') -Destination $bvhRoot -Force
    $zeroZip = Join-Path $datasetRoot 'lafan1-resolved-bvh.zip'
    if ((Test-Path $zeroZip) -and ((Get-Item $zeroZip).Length -eq 0)) {
        Remove-Item -Path $zeroZip -Force
    }

    return [pscustomobject]@{
        Status  = 'PASS'
        Summary = "Seeded ControlOperators dataset from $localDatasetRoot"
    }
}

function Install-Case20FallbackDependencies {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $cpuPackages = @(
        'absl-py',
        'cffi',
        'colorama',
        'filelock',
        'fsspec',
        'ftfy',
        'grpcio',
        'jinja2',
        'markdown',
        'markupsafe',
        'mpmath',
        'networkx',
        'numpy',
        'packaging',
        'pillow',
        'protobuf',
        'pycparser',
        'python-dateutil',
        'pytz',
        'raylib',
        'regex',
        'scipy',
        'setuptools',
        'six',
        'sympy',
        'tensorboard',
        'tensorboard-data-server',
        'tqdm',
        'typing-extensions',
        'tzdata',
        'wcwidth',
        'werkzeug'
    )

    $clipArchive = Ensure-Case20ClipArchive -Context $Context
    Invoke-Case20Python -RepoRoot $RepoRoot -Arguments @('-m', 'ensurepip', '--upgrade') -LogPath $LogPath | Out-Null
    Invoke-Case20Python -RepoRoot $RepoRoot -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--upgrade', 'pip', 'wheel') -LogPath $LogPath | Out-Null
    Invoke-Case20Python -RepoRoot $RepoRoot -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', 'setuptools<81') -LogPath $LogPath | Out-Null
    Invoke-Case20Python -RepoRoot $RepoRoot -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--index-url', 'https://download.pytorch.org/whl/cu128', 'torch', 'torchvision') -LogPath $LogPath | Out-Null
    Invoke-Case20Python -RepoRoot $RepoRoot -Arguments (@('-m', 'pip', 'install', '--disable-pip-version-check') + $cpuPackages) -LogPath $LogPath | Out-Null
    Invoke-Case20Python -RepoRoot $RepoRoot -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--no-build-isolation', '--no-deps', $clipArchive) -LogPath $LogPath | Out-Null
}

function Ensure-Case20ControllerFiles {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $required = @(
        'data\lafan1_resolved\database.npz',
        'data\lafan1_resolved\X.npz',
        'data\lafan1_resolved\Z.npz',
        'data\lafan1_resolved\autoencoder.ptz',
        'data\lafan1_resolved\UberControlEncoder\controller.ptz'
    )

    foreach ($relative in $required) {
        $path = Join-Path $RepoRoot $relative
        if (-not (Test-Path $path)) {
            throw "Required ControlOperators artifact is missing: $path"
        }
    }
}

function Start-Case20ControllerProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [Parameter(Mandatory = $true)]
        [string]$Device,
        [int]$TimeoutSeconds = 20
    )

    $python = Get-Case20VenvPythonPath -RepoRoot $RepoRoot
    $stdout = "$LogPath.stdout"
    $stderr = "$LogPath.stderr"
    $args = @(
        '-u',
        'controller.py'
    )

    $process = Start-Process `
        -FilePath $python `
        -ArgumentList $args `
        -WorkingDirectory $RepoRoot `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }

    if (-not $process.HasExited) {
        try {
            $process.Kill()
        }
        catch {
        }
    }

    $null = Start-Sleep -Milliseconds 250
    $combined = @()
    foreach ($path in @($stdout, $stderr)) {
        if (Test-Path $path) {
            $combined += Get-Content -Path $path -ErrorAction SilentlyContinue
        }
    }
    if ($combined.Count -gt 0) {
        $combined | Set-Content -Path $LogPath -Encoding UTF8
    }

    return [pscustomobject]@{
        Process  = $process
        StdOut   = $stdout
        StdErr   = $stderr
        LogPath  = $LogPath
        Exited   = [bool]$process.HasExited
        ExitCode = if ($process.HasExited) { $process.ExitCode } else { $null }
    }
}

function Setup-ReferenceWalkthroughCase20 {
    param(
        [pscustomobject]$Context
    )

    if (-not $Context) {
        $Context = New-ReferenceContext
    }

    $repoRoot = Get-Case20RepoRoot -Context $Context
    if (-not (Test-Path $repoRoot)) {
        throw "ControlOperators repository was not found at: $repoRoot"
    }

    $envName = Ensure-ReferenceCondaEnv -Context $Context
    $setupLog = Get-ReferenceLogPath -Context $Context -Name 'case-20-setup'
    $pythonPath = Get-ReferenceCondaPythonPath -Context $Context
    $notes = New-Object System.Collections.Generic.List[string]
    $venvRoot = Join-Path $repoRoot '.venv'
    $venvPython = Join-Path $venvRoot 'Scripts\python.exe'
    if ((Test-Path $venvRoot -PathType Container) -and -not (Test-Path $venvPython -PathType Leaf)) {
        Remove-Item -LiteralPath $venvRoot -Recurse -Force -ErrorAction Stop
    }
    if (-not (Test-Path $venvPython -PathType Leaf)) {
        Invoke-ReferenceCommand -FilePath $pythonPath -ArgumentList @('-m', 'venv', $venvRoot) -WorkingDirectory $repoRoot -LogPath $setupLog | Out-Null
    }

    $datasetSeed = Ensure-Case20Dataset -Context $Context -RepoRoot $repoRoot
    $notes.Add($datasetSeed.Summary)

    $syncMode = 'uv sync'
    try {
        $uvSync = Invoke-Case20Uvx `
            -Context $Context `
            -Arguments @('sync', '--python', $pythonPath) `
            -WorkingDirectory $repoRoot `
            -LogPath $setupLog
    }
    catch {
        Install-Case20FallbackDependencies -Context $Context -RepoRoot $repoRoot -LogPath $setupLog
        $uvSync = [pscustomobject]@{
            ExitCode = 0
            Output   = @()
            LogPath  = $setupLog
        }
        $syncMode = 'fallback pip install'
        $notes.Add('uv sync failed; installed dependencies directly into .venv using pip plus a codeload CLIP archive fallback.')
    }

    $result = New-ReferenceResult `
        -CaseId '20' `
        -Stage 'setup' `
        -Status 'PASS' `
        -Summary "Prepared ControlOperators case in conda env '$envName' using $syncMode." `
        -Artifacts @(
            (Join-Path $repoRoot 'uv.lock'),
            (Join-Path $repoRoot 'pyproject.toml'),
            $venvPython
        ) `
        -Notes $notes.ToArray() `
        -LogPath $setupLog `
        -DataPath $repoRoot

    return [pscustomobject]@{
        Context = $Context
        RepoRoot = $repoRoot
        SetupLog = $setupLog
        UvSync = $uvSync
        Result = $result
    }
}

function Test-ReferenceWalkthroughCase20 {
    param(
        [pscustomobject]$Context,
        [pscustomobject]$SetupState
    )

    if (-not $Context) {
        $Context = New-ReferenceContext
    }
    if (-not $SetupState) {
        $SetupState = Setup-ReferenceWalkthroughCase20 -Context $Context
    }

    $repoRoot = $SetupState.RepoRoot
    $smokeLog = Get-ReferenceLogPath -Context $Context -Name 'case-20-train-smoke'
    $device = Get-Case20PythonDevice -Context $Context -RepoRoot $repoRoot
    $trainArgs = @(
        'train.py',
        '--niterations', '1000',
        '--batch_size', '64',
        '--device', $device,
        '--expr_name', 'smoke'
    )

    $trainResult = Invoke-Case20Python `
        -RepoRoot $repoRoot `
        -Arguments $trainArgs `
        -LogPath $smokeLog

    Ensure-Case20ControllerFiles -Context $Context -RepoRoot $repoRoot

    $controllerLog = Get-ReferenceLogPath -Context $Context -Name 'case-20-controller'
    $controllerResult = Start-Case20ControllerProcess `
        -RepoRoot $repoRoot `
        -LogPath $controllerLog `
        -Device $device `
        -TimeoutSeconds 45

    $logText = ''
    if (Test-Path $controllerLog) {
        $logText = Get-Content -Path $controllerLog -Raw -ErrorAction SilentlyContinue
    }
    $neuralMarker = $logText -match 'Starting render loop in NEURAL NETWORK mode'
    $bindMarker = $logText -match 'Running in BIND POSE mode|MODE: Bind Pose|Missing controller files'
    $gamepadNames = @()
    if ($Context -and $Context.PSObject.Properties.Match('Preflight').Count -gt 0 -and $Context.Preflight) {
        $gamepadNames = @($Context.Preflight.gamepad_names)
    }
    if ($gamepadNames.Count -eq 0) {
        $gamepadNames = @(Get-ReferenceGamepadNames)
    }

    $status = 'BLOCKED'
    $notes = @()
    if ($gamepadNames.Count -eq 0) {
        $status = 'MANUAL-HARDWARE'
        $notes += 'No controller/gamepad device could be confirmed on this machine.'
    }
    elseif ($trainResult.ExitCode -eq 0 -and $neuralMarker -and -not $bindMarker) {
        $status = 'PASS'
        $notes += 'Training completed and controller started in neural mode.'
    }
    elseif ($trainResult.ExitCode -ne 0) {
        $status = 'BLOCKED'
        $notes += "Training failed with exit code $($trainResult.ExitCode)."
    }
    elseif ($bindMarker) {
        $status = 'BLOCKED'
        $notes += 'Controller fell back to bind pose mode.'
    }
    else {
        $status = 'BLOCKED'
        $notes += 'Controller did not emit a neural mode marker within the timeout window.'
    }

    $result = New-ReferenceResult `
        -CaseId '20' `
        -Stage 'test' `
        -Status $status `
        -Summary "Device=$device; training exit=$($trainResult.ExitCode); controller exited=$($controllerResult.Exited)." `
        -Artifacts @(
            (Join-Path $repoRoot 'data\lafan1_resolved\database.npz'),
            (Join-Path $repoRoot 'data\lafan1_resolved\X.npz'),
            (Join-Path $repoRoot 'data\lafan1_resolved\Z.npz'),
            (Join-Path $repoRoot 'data\lafan1_resolved\autoencoder.ptz'),
            (Join-Path $repoRoot 'data\lafan1_resolved\UberControlEncoder\controller.ptz')
        ) `
        -Notes $notes `
        -LogPath $controllerLog `
        -DataPath $repoRoot

    return [pscustomobject]@{
        Context = $Context
        RepoRoot = $repoRoot
        Device = $device
        TrainLog = $smokeLog
        TrainResult = $trainResult
        ControllerLog = $controllerLog
        ControllerResult = $controllerResult
        Result = $result
    }
}

if ($MyInvocation.InvocationName -eq '.') {
    return
}

$context = New-ReferenceContext
$setup = Setup-ReferenceWalkthroughCase20 -Context $context
$test = Test-ReferenceWalkthroughCase20 -Context $context -SetupState $setup
Write-Output $setup.Result
Write-Output $test.Result
