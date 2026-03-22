param(
    [string]$RepoRoot = '',
    [pscustomobject]$Context = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common.ps1')

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Get-ReferenceRoot -StartDir $PSScriptRoot
}

$script:CaseId = '31'
$script:Case31ReleaseVersion = 'v0.3.0'
$script:Case31ReleaseAsset = 'lmm-v0.3.0.zip'
$script:Case31ReleaseUrl = 'https://github.com/pau1o-hs/Learned-Motion-Matching/releases/download/v0.3.0/lmm-v0.3.0.zip'

function Get-Case31Paths {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $referenceRoot = (Resolve-Path $Root).Path
    $externalsRoot = Ensure-ReferenceDirectory -Path (Join-Path $referenceRoot 'Saved\ReferenceCases\externals')
    $caseExternalRoot = Ensure-ReferenceDirectory -Path (Join-Path $externalsRoot 'l31')
    $downloadsRoot = Ensure-ReferenceDirectory -Path (Join-Path $caseExternalRoot 'downloads')
    $extractRoot = Ensure-ReferenceDirectory -Path (Join-Path $referenceRoot 'Saved\_l31')
    $logsRoot = Ensure-ReferenceDirectory -Path (Join-Path $Context.LogsDir 'case-31')

    $trainingRepo = (Resolve-Path (Join-Path $referenceRoot 'References\Learned-Motion-Matching')).Path
    $trainingWorktree = (Resolve-Path (Join-Path $referenceRoot 'References\Learned_Motion_Matching_Training')).Path
    $unityEditor = Get-ReferenceUnityEditor -PreferredVersion '2021.1.22f1c1'

    [pscustomobject]@{
        Root             = $referenceRoot
        ExternalsRoot    = $externalsRoot
        CaseExternalRoot = $caseExternalRoot
        DownloadsRoot    = $downloadsRoot
        ExtractRoot      = $extractRoot
        LogsRoot         = $logsRoot
        TrainingRepo     = $trainingRepo
        TrainingWorktree = $trainingWorktree
        UnityEditor      = $unityEditor
        ReleaseAsset     = $script:Case31ReleaseAsset
        ReleaseUrl       = $script:Case31ReleaseUrl
        ReleaseVersion   = $script:Case31ReleaseVersion
    }
}

function Get-Case31LogPath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return Join-Path $Paths.LogsRoot "$Name.log"
}

function Write-Case31Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Find-Case31UnitySampleRoot {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    $searchRoots = @(
        $Paths.ExtractRoot,
        $Paths.CaseExternalRoot,
        $Paths.TrainingWorktree
    )

    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path $searchRoot)) {
            continue
        }

        foreach ($manifest in Get-ChildItem -Path $searchRoot -Recurse -Filter 'manifest.json' -File -ErrorAction SilentlyContinue) {
            $projectRoot = Split-Path (Split-Path $manifest.FullName -Parent) -Parent
            if ((Test-Path (Join-Path $projectRoot 'Packages\manifest.json')) -and
                (Test-Path (Join-Path $projectRoot 'ProjectSettings\ProjectVersion.txt'))) {
                $candidates.Add($projectRoot)
            }
        }
    }

    $unique = $candidates | Sort-Object -Unique
    return $unique | Select-Object -First 1
}

function Get-Case31TextArtifactNames {
    return @(
        'XData.txt',
        'YData.txt',
        'HierarchyData.txt',
        'YtxyData.txt',
        'QtxyData.txt',
        'ZData.txt'
    )
}

function Get-Case31OnnxArtifactNames {
    return @(
        'compressor.onnx',
        'decompressor.onnx',
        'projector.onnx',
        'stepper.onnx'
    )
}

function Get-Case31SampleCharacterRoots {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot
    )

    $charactersRoot = Join-Path $SampleRoot 'Assets\Motion Matching\Characters'
    if (-not (Test-Path $charactersRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -Path $charactersRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-Path (Join-Path $_.FullName 'Database')) -or
            (Test-Path (Join-Path $_.FullName 'ONNX'))
        } |
        Select-Object -ExpandProperty FullName
    )
}

function Copy-Case31DatabaseArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabaseDir,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDatabaseDir
    )

    if (-not (Test-Path $DestinationDatabaseDir)) {
        return
    }

    foreach ($file in Get-Case31TextArtifactNames) {
        $sourcePath = Join-Path $SourceDatabaseDir $file
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination (Join-Path $DestinationDatabaseDir $file) -Force
        }
    }
}

function Copy-Case31OnnxArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceOnnxDir,
        [Parameter(Mandatory = $true)]
        [string]$DestinationOnnxDir
    )

    if (-not (Test-Path $DestinationOnnxDir)) {
        return
    }

    foreach ($file in Get-Case31OnnxArtifactNames) {
        $sourcePath = Join-Path $SourceOnnxDir $file
        if (-not (Test-Path $sourcePath)) {
            continue
        }

        $prefix = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $existing = Get-ChildItem -Path $DestinationOnnxDir -Filter "$prefix*.onnx" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $targetPath = if ($existing) { $existing.FullName } else { Join-Path $DestinationOnnxDir $file }
        Copy-Item -Path $sourcePath -Destination $targetPath -Force

        $sourceDataPath = Join-Path $SourceOnnxDir ($file + '.data')
        if (Test-Path $sourceDataPath) {
            $canonicalDataTarget = Join-Path $DestinationOnnxDir ([System.IO.Path]::GetFileName($sourceDataPath))
            Copy-Item -Path $sourceDataPath -Destination $canonicalDataTarget -Force

            $targetDataPath = $targetPath + '.data'
            if ([System.IO.Path]::GetFullPath($targetDataPath) -ine [System.IO.Path]::GetFullPath($canonicalDataTarget)) {
                Copy-Item -Path $sourceDataPath -Destination $targetDataPath -Force
            }
        }
        else {
            foreach ($stalePath in @(
                (Join-Path $DestinationOnnxDir ($file + '.data')),
                ($targetPath + '.data')
            ) | Select-Object -Unique) {
                if (Test-Path $stalePath) {
                    Remove-Item -Path $stalePath -Force -ErrorAction SilentlyContinue
                }
                $staleMeta = $stalePath + '.meta'
                if (Test-Path $staleMeta) {
                    Remove-Item -Path $staleMeta -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Ensure-Case31UnityManifestBarracuda {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $manifestPath = Join-Path $ProjectRoot 'Packages\manifest.json'
    if (-not (Test-Path $manifestPath)) {
        return $null
    }

    $raw = Get-Content -Path $manifestPath -Raw
    $manifest = $raw | ConvertFrom-Json
    if ($null -eq $manifest.dependencies) {
        $manifest | Add-Member -NotePropertyName dependencies -NotePropertyValue ([ordered]@{}) -Force
    }

    $dependencies = [ordered]@{}
    foreach ($property in $manifest.dependencies.PSObject.Properties) {
        $dependencies[$property.Name] = [string]$property.Value
    }

    if (-not $dependencies.Contains('com.unity.barracuda')) {
        $dependencies['com.unity.barracuda'] = '3.1.0'
        $manifest.dependencies = $dependencies
        ($manifest | ConvertTo-Json -Depth 20) | Set-Content -Path $manifestPath -Encoding UTF8
        return 'added'
    }

    return 'present'
}

function Ensure-Case31AutomationScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot
    )

    $editorRoot = Ensure-ReferenceDirectory -Path (Join-Path $SampleRoot 'Assets\Editor')
    $scriptPath = Join-Path $editorRoot 'Case31Automation.cs'
    $scriptText = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using Unity.Barracuda;
using UnityEngine;

public static class Case31Automation
{
    private static string ResultPath => Environment.GetEnvironmentVariable("CASE31_RESULT_PATH");

    private static void WriteResult(string status, IEnumerable<string> lines)
    {
        if (string.IsNullOrWhiteSpace(ResultPath))
        {
            return;
        }

        var payload = new List<string> { status };
        if (lines != null)
        {
            payload.AddRange(lines.Where(line => !string.IsNullOrWhiteSpace(line)));
        }

        Directory.CreateDirectory(Path.GetDirectoryName(ResultPath) ?? ".");
        File.WriteAllLines(ResultPath, payload);
    }

    private static void Fail(Exception ex)
    {
        WriteResult("FAIL", new[] { ex.ToString() });
        EditorApplication.Exit(1);
    }

    private static string ResolveScenePath()
    {
        var projectRoot = Path.GetDirectoryName(Application.dataPath) ?? ".";
        var exactScene = Path.Combine(projectRoot, "Assets", "Scenes", "Motion Matching.unity");
        if (File.Exists(exactScene))
        {
            return "Assets/Scenes/Motion Matching.unity";
        }

        var sceneGuid = AssetDatabase.FindAssets("t:Scene")
            .FirstOrDefault(guid => AssetDatabase.GUIDToAssetPath(guid).EndsWith(".unity", StringComparison.OrdinalIgnoreCase));
        if (string.IsNullOrWhiteSpace(sceneGuid))
        {
            throw new FileNotFoundException("Could not resolve a Unity scene for case 31 automation.");
        }

        return AssetDatabase.GUIDToAssetPath(sceneGuid);
    }

    private static Gameplay[] FindGameplays()
    {
        return Resources.FindObjectsOfTypeAll<Gameplay>()
            .Where(gameplay => gameplay != null && gameplay.gameObject.scene.IsValid())
            .OrderBy(gameplay => gameplay.name)
            .ToArray();
    }

    private static Gameplay[] SelectTargetGameplays(Gameplay[] gameplays)
    {
        var preferred = gameplays
            .Where(gameplay =>
            {
                var prefabPath = gameplay.mm?.prefab != null ? AssetDatabase.GetAssetPath(gameplay.mm.prefab) : string.Empty;
                return prefabPath.IndexOf("/Lafan/", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       gameplay.name.IndexOf("lafan", StringComparison.OrdinalIgnoreCase) >= 0;
            })
            .ToArray();

        if (preferred.Length > 0)
        {
            return preferred;
        }

        return gameplays.Take(1).ToArray();
    }

    private static string GetPrefabPath(Gameplay gameplay)
    {
        return gameplay.mm?.prefab != null ? AssetDatabase.GetAssetPath(gameplay.mm.prefab) : string.Empty;
    }

    private static string GetOnnxDirectory(Gameplay gameplay)
    {
        var prefabPath = GetPrefabPath(gameplay);
        if (string.IsNullOrWhiteSpace(prefabPath))
        {
            return string.Empty;
        }

        var relativeDir = Path.GetDirectoryName(prefabPath) ?? string.Empty;
        return Path.Combine(relativeDir, "ONNX").Replace("\\", "/");
    }

    private static NNModel LoadModelAsset(string prefix, string onnxDir, List<string> lines)
    {
        if (string.IsNullOrWhiteSpace(onnxDir) || !AssetDatabase.IsValidFolder(onnxDir))
        {
            throw new DirectoryNotFoundException("Could not resolve an ONNX directory for prefix '" + prefix + "'.");
        }

        var assetPath = AssetDatabase.FindAssets(prefix, new[] { onnxDir })
            .Select(AssetDatabase.GUIDToAssetPath)
            .Where(path =>
                path.EndsWith(".onnx", StringComparison.OrdinalIgnoreCase) &&
                Path.GetFileNameWithoutExtension(path).StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .OrderBy(path => path.Length)
            .FirstOrDefault();

        if (string.IsNullOrWhiteSpace(assetPath))
        {
            throw new FileNotFoundException("Could not resolve ONNX asset for prefix '" + prefix + "'.", onnxDir);
        }

        AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
        var model = AssetDatabase.LoadAssetAtPath<NNModel>(assetPath);
        if (model == null)
        {
            var mainAsset = AssetDatabase.LoadMainAssetAtPath(assetPath);
            var assetType = mainAsset != null ? mainAsset.GetType().FullName : "null";
            throw new NullReferenceException("ONNX asset '" + assetPath + "' did not import as NNModel. Main asset type: " + assetType);
        }

        lines.Add(prefix + "=" + assetPath);
        return model;
    }

    private static void EnsureGameplayInferenceAssets(Gameplay gameplay, List<string> lines)
    {
        var onnxDir = GetOnnxDirectory(gameplay);
        lines.Add("Prefab=" + GetPrefabPath(gameplay));
        lines.Add("OnnxDir=" + onnxDir);

        gameplay.mm.decompressorParams = LoadModelAsset("decompressor", onnxDir, lines);
        gameplay.mm.projectorParams = LoadModelAsset("projector", onnxDir, lines);
        gameplay.mm.stepperParams = LoadModelAsset("stepper", onnxDir, lines);
    }

    public static void ExtractDataFromSample()
    {
        try
        {
            var scenePath = ResolveScenePath();
            EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
            var gameplays = FindGameplays();
            if (gameplays.Length == 0)
            {
                throw new InvalidOperationException("No Gameplay components were found in the loaded scene.");
            }

            var selectedGameplays = SelectTargetGameplays(gameplays);

            var lines = new List<string> { "Scene=" + scenePath };
            var projectRoot = Path.GetDirectoryName(Application.dataPath) ?? ".";

            foreach (var gameplay in selectedGameplays)
            {
                gameplay.ExtractData();
                if (gameplay.mm?.prefab == null)
                {
                    throw new InvalidOperationException("Gameplay '" + gameplay.name + "' does not have a prefab assigned.");
                }

                var prefabPath = AssetDatabase.GetAssetPath(gameplay.mm.prefab);
                if (string.IsNullOrWhiteSpace(prefabPath))
                {
                    throw new InvalidOperationException("Gameplay '" + gameplay.name + "' prefab path could not be resolved.");
                }

                var relativeDir = Path.GetDirectoryName(prefabPath) ?? string.Empty;
                var databaseDir = Path.Combine(projectRoot, relativeDir, "Database");
                var required = new[] { "XData.txt", "YData.txt", "HierarchyData.txt" };
                foreach (var requiredFile in required)
                {
                    var filePath = Path.Combine(databaseDir, requiredFile);
                    if (!File.Exists(filePath))
                    {
                        throw new FileNotFoundException("Expected extracted file was not generated.", filePath);
                    }
                }

                lines.Add("Gameplay=" + gameplay.name);
                lines.Add("Database=" + databaseDir);
            }

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceUpdate);
            WriteResult("PASS", lines);
            EditorApplication.Exit(0);
        }
        catch (Exception ex)
        {
            Fail(ex);
        }
    }

    public static void ValidateInference()
    {
        try
        {
            var scenePath = ResolveScenePath();
            EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceUpdate);

            var gameplays = FindGameplays();
            if (gameplays.Length == 0)
            {
                throw new InvalidOperationException("No Gameplay components were found in the loaded scene.");
            }

            var selectedGameplays = SelectTargetGameplays(gameplays);

            var lines = new List<string> { "Scene=" + scenePath };
            foreach (var gameplay in selectedGameplays)
            {
                if (gameplay.mm == null)
                {
                    throw new InvalidOperationException("Gameplay '" + gameplay.name + "' is missing MotionMatching configuration.");
                }

                if (gameplay.input == null)
                {
                    gameplay.input = new MMInput.MMInput();
                }

                if (gameplay.input.trajectory == null || gameplay.input.trajectory.Length != 3)
                {
                    gameplay.input.trajectory = new Vector3[3];
                }

                gameplay.input.defaultLength = gameplay.input.defaultLength > 0f ? gameplay.input.defaultLength : 1f;
                gameplay.input.acc = gameplay.input.acc > 0f ? gameplay.input.acc : 4f;
                gameplay.input.decc = gameplay.input.decc > 0f ? gameplay.input.decc : 4f;
                gameplay.input.trajectory[0] = new Vector3(0.15f, 0f, 0.25f);
                gameplay.input.trajectory[1] = new Vector3(0.30f, 0f, 0.50f);
                gameplay.input.trajectory[2] = new Vector3(0.45f, 0f, 0.75f);

                gameplay.mm.enableDecompressor = true;
                gameplay.mm.enableProjector = true;
                gameplay.mm.enableStepper = true;
                gameplay.mm.projectorFreq = 1f;
                EnsureGameplayInferenceAssets(gameplay, lines);

                gameplay.mm.Build(gameplay.gameObject);
                gameplay.mm.Matching(ref gameplay.input);
                gameplay.mm.Matching(ref gameplay.input);
                gameplay.mm.DisposeTensors();

                lines.Add("Gameplay=" + gameplay.name);
            }

            WriteResult("PASS", lines);
            EditorApplication.Exit(0);
        }
        catch (Exception ex)
        {
            Fail(ex);
        }
    }
}
'@

    $current = if (Test-Path $scriptPath) { Get-Content -Path $scriptPath -Raw } else { '' }
    if ($current -ne $scriptText) {
        Write-Case31Utf8NoBom -Path $scriptPath -Content $scriptText
    }

    return $scriptPath
}

function Test-Case31SelectedZipEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryName
    )

    $normalized = $EntryName.Replace('\', '/')
    $keepPrefixes = @(
        'Learned Motion Matching/Assets/',
        'Learned Motion Matching/Packages/',
        'Learned Motion Matching/ProjectSettings/'
    )
    if ($normalized -eq 'Learned Motion Matching/.collabignore') {
        return $true
    }
    foreach ($prefix in $keepPrefixes) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Expand-Case31ReleaseZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            if (-not (Test-Case31SelectedZipEntry -EntryName $entry.FullName)) {
                continue
            }

            $targetPath = Join-Path $Destination ($entry.FullName -replace '/', '\')
            if ([string]::IsNullOrEmpty($entry.Name)) {
                Ensure-ReferenceDirectory -Path $targetPath | Out-Null
                continue
            }

            Ensure-ReferenceDirectory -Path (Split-Path $targetPath -Parent) | Out-Null
            $input = $entry.Open()
            try {
                $output = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try {
                    $input.CopyTo($output)
                }
                finally {
                    $output.Dispose()
                }
            }
            finally {
                $input.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    return $Destination
}

function Ensure-Case31ReleaseExtracted {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths
    )

    $zipPath = Join-Path $Paths.DownloadsRoot $Paths.ReleaseAsset
    if (-not (Test-Path $zipPath)) {
        Download-ReferenceFile -Uri $Paths.ReleaseUrl -Destination $zipPath | Out-Null
    }

    $marker = Join-Path $Paths.ExtractRoot '.extracted'
    if (-not (Test-Path $marker)) {
        if (Test-Path $Paths.ExtractRoot) {
            Remove-Item -Path $Paths.ExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Ensure-ReferenceDirectory -Path $Paths.ExtractRoot | Out-Null
        Expand-ReferenceZip -ArchivePath $zipPath -Destination $Paths.ExtractRoot | Out-Null
        Set-Content -Path $marker -Value $zipPath -Encoding UTF8
    }

    $sampleRoot = Find-Case31UnitySampleRoot -Paths $Paths
    if (-not $sampleRoot) {
        $sampleRoot = $Paths.ExtractRoot
    }

    return $sampleRoot
}

function Apply-Case31SampleCompatibilityPatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot
    )

    $artifacts = New-Object System.Collections.Generic.List[string]

    $manifestPath = Join-Path $SampleRoot 'Packages\manifest.json'
    if (Test-Path $manifestPath) {
        $manifestRaw = Get-Content -Path $manifestPath -Raw
        $manifest = $manifestRaw | ConvertFrom-Json
        $manifestChanged = $false
        if ($null -ne $manifest.dependencies -and $manifest.dependencies.PSObject.Properties.Name -contains 'com.unity.render-pipelines.universal') {
            $dependencies = [ordered]@{}
            foreach ($property in $manifest.dependencies.PSObject.Properties) {
                if ($property.Name -ne 'com.unity.render-pipelines.universal') {
                    $dependencies[$property.Name] = [string]$property.Value
                }
            }
            $manifest.dependencies = $dependencies
            $manifestChanged = $true
        }

        $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
        $hasUtf8Bom = $manifestBytes.Length -ge 3 -and $manifestBytes[0] -eq 239 -and $manifestBytes[1] -eq 187 -and $manifestBytes[2] -eq 191
        if ($manifestChanged -or $hasUtf8Bom) {
            Write-Case31Utf8NoBom -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 20)
            if (-not $artifacts.Contains($manifestPath)) {
                $artifacts.Add($manifestPath)
            }
        }
    }

    $packageManagerSettingsPath = Join-Path $SampleRoot 'ProjectSettings\PackageManagerSettings.asset'
    if (Test-Path $packageManagerSettingsPath) {
        $packageSettingsOriginal = Get-Content -Path $packageManagerSettingsPath -Raw
        $packageSettingsPatched = $packageSettingsOriginal -replace 'https://packages\.unity\.com', 'https://packages.unity.cn'
        if ($packageSettingsPatched -ne $packageSettingsOriginal) {
            Write-Case31Utf8NoBom -Path $packageManagerSettingsPath -Content $packageSettingsPatched
            $artifacts.Add($packageManagerSettingsPath)
        }
    }

    $motionMatchingPath = Join-Path $SampleRoot 'Assets\Motion Matching\Scripts\MotionMatching.cs'
    if (-not (Test-Path $motionMatchingPath)) {
        return @($artifacts)
    }

    $original = Get-Content -Path $motionMatchingPath -Raw
    $patched = $original
    $oldLine = "                    clip.curvesInfo[curBone].boneRelative = GameObject.Find(targetBones.character.name + '/' + binding.path).transform;"
    $brokenLine = '                        throw new NullReferenceException(""Could not resolve bone path ''{binding.path}'' for character ''{targetBones.character?.name}''."");'
    $existingBlockPattern = '(?ms)^ {20}GameObject boneObject = null;\r?\n.*?^ {20}clip\.curvesInfo\[curBone\]\.boneRelative = boneObject\.transform;'
    $exportFunctionPattern = '(?ms)^\s*void ExportData\(\)\r?\n\s*\{\r?\n.*?^\s*\}\r?\n\r?\n\s*float updater = -1;'
    $newBlock = @"
                    GameObject boneObject = null;
                    if (string.IsNullOrWhiteSpace(binding.path))
                    {
                        boneObject = targetBones.character != null ? targetBones.character.gameObject : null;
                    }
                    else if (targetBones.character != null)
                    {
                        var relativePaths = new List<string>();
                        relativePaths.Add(binding.path.Replace('\\', '/'));

                        string[] originalSegments = binding.path.Split('/');
                        if (originalSegments.Length > 1)
                        {
                            if (targetBones.character.name == originalSegments[0] || (targetBones.root != null && targetBones.root.name == originalSegments[0]))
                            {
                                relativePaths.Add(string.Join("/", originalSegments.Skip(1).ToArray()));
                            }
                        }

                        foreach (string relativePath in relativePaths.Where(pathCandidate => !string.IsNullOrWhiteSpace(pathCandidate)).Distinct())
                        {
                            var relativeTransform = targetBones.character.Find(relativePath);
                            if (relativeTransform == null && targetBones.root != null)
                            {
                                relativeTransform = targetBones.root.Find(relativePath);
                            }
                            if (relativeTransform != null)
                            {
                                boneObject = relativeTransform.gameObject;
                                break;
                            }
                        }
                    }
                    if (boneObject == null && !string.IsNullOrWhiteSpace(binding.path))
                    {
                        boneObject = GameObject.Find(targetBones.character.name + '/' + binding.path);
                    }
                    if (boneObject == null && targetBones.root != null && !string.IsNullOrWhiteSpace(binding.path))
                    {
                        boneObject = GameObject.Find(targetBones.root.name + '/' + binding.path);
                    }
                    if (boneObject == null && !string.IsNullOrWhiteSpace(binding.path))
                    {
                        boneObject = GameObject.Find(binding.path);
                    }
                    if (boneObject == null && targetBones.character != null)
                    {
                        string[] pathSegments = binding.path.Split('/');
                        string targetName = pathSegments.Length > 0 ? pathSegments[pathSegments.Length - 1] : curBone;
                        boneObject = targetBones.character
                            .GetComponentsInChildren<Transform>(true)
                            .FirstOrDefault(t => t.name == targetName)
                            ?.gameObject;
                    }
                    if (boneObject == null)
                    {
                        throw new NullReferenceException($"Could not resolve bone path '{binding.path}' for character '{targetBones.character?.name}' root '{targetBones.root?.name}'.");
                    }
                    clip.curvesInfo[curBone].boneRelative = boneObject.transform;
"@
    $exportFunction = @'
		void ExportData()
		{
			string pathDatabase  = Application.dataPath.Substring(0, Application.dataPath.LastIndexOf('/') + 1) + folder + "/Database";

            int yDataLen = (clipInfo[idleClip.name].curvesInfo.Count * 13);
			int poseLen = (clipInfo[idleClip.name].curvesInfo.Count * 7);

			Debug.Log("Y Length:    " + yDataLen);
            Debug.Log("Clips count: " + clipInfo.Count);
			Debug.Log("Bones count: " + clipInfo[idleClip.name].curvesInfo.Count);
			foreach(var clip in clipInfo)
				Debug.Log(clip.Key + ": " + clip.Value.frames + " frames");

			bool generateDatabase = true;
            Directory.CreateDirectory(pathDatabase);

			if (generateDatabase)
			{
                List<float> input = new List<float>();
                List<float> output = new List<float>();

                string path1;
				string content;

				#region Features Database
				path1 = pathDatabase + "/XData.txt";
                using (var writer = new StreamWriter(path1, false))
                {
				    foreach (var clip in clipInfo)
				    {
					    for (int i = 0; i < clip.Value.frames; i++)
					    {
						    content = "";

						    // STORING DATA
						    GatherXData(clip.Key, i, ref input);

						    // WRITTING DATA TO FILE
						    for (int j = 0; j < input.Count - 1; j++)
							    content += input[j].ToString().Replace(",", ".") + " ";
						    content += input[input.Count - 1].ToString().Replace(",", ".");

                            writer.WriteLine(content);
					    }

                        writer.WriteLine();
				    }
                }
                #endregion

                #region Compressor Database
                path1 = pathDatabase + "/YData.txt";
                using (var writer = new StreamWriter(path1, false))
                {
				    foreach (var clip in clipInfo)
				    {
					    for (int i = 0; i < clip.Value.frames; i++)
					    {
						    content = "";

						    // STORING DATA
						    GatherYData(clip.Key, i, ref input);

						    // WRITTING DATA TO FILE
						    for (int j = 0; j < input.Count - 1; j++)
							    content += input[j].ToString().Replace(",", ".") + " ";
						    content += input[input.Count - 1].ToString().Replace(",", ".");

                            writer.WriteLine(content);
					    }

                        writer.WriteLine();
				    }
                }
                #endregion

                #region Hierarchy Database
                path1 = pathDatabase + "/HierarchyData.txt";
                using (var writer = new StreamWriter(path1, false))
                {
				    content = "";

				    // STORING DATA
				    GatherHierarchyData(idleClip.name, ref input);

				    // WRITTING DATA TO FILE
				    for (int j = 0; j < input.Count; j++)
					    content += input[j].ToString() + "\n";

                    writer.Write(content);
                }

				#endregion
			}
        }

		float updater = -1;
'@

    if ($patched.Contains($oldLine)) {
        $patched = $patched.Replace($oldLine, $newBlock.TrimEnd("`r", "`n"))
    }
    elseif ([regex]::IsMatch($patched, $existingBlockPattern)) {
        $patched = [regex]::Replace($patched, $existingBlockPattern, $newBlock.TrimEnd("`r", "`n"), 1)
    }
    elseif ($patched.Contains($brokenLine)) {
        $pattern = [regex]::Escape('                    GameObject boneObject = null;') +
            '(?s).*?' +
            [regex]::Escape('                    clip.curvesInfo[curBone].boneRelative = boneObject.transform;')
        $patched = [regex]::Replace($patched, $pattern, $newBlock.TrimEnd("`r", "`n"), 1)
    }

    if ([regex]::IsMatch($patched, $exportFunctionPattern)) {
        $patched = [regex]::Replace($patched, $exportFunctionPattern, $exportFunction.TrimEnd("`r", "`n"), 1)
    }

    if ($patched -ne $original) {
        Write-Case31Utf8NoBom -Path $motionMatchingPath -Content $patched
        $artifacts.Add($motionMatchingPath)
    }

    return @($artifacts)
}

function Invoke-Case31UnityAutomation {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths,
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot,
        [Parameter(Mandatory = $true)]
        [string]$MethodName,
        [Parameter(Mandatory = $true)]
        [string]$LogStem,
        [int]$TimeoutSeconds = 3600,
        [switch]$BatchMode
    )

    if (-not $Paths.UnityEditor) {
        throw 'Unity 2021.1.22f1c1 editor was not found on this machine.'
    }

    Ensure-Case31AutomationScript -SampleRoot $SampleRoot | Out-Null

    $logPath = Get-Case31LogPath -Paths $Paths -Name $LogStem
    $resultPath = Join-Path $Paths.LogsRoot "$LogStem.result.txt"
    if (Test-Path $resultPath) {
        Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
    }

    $argParts = New-Object System.Collections.Generic.List[string]
    if ($BatchMode) {
        $argParts.Add('-batchmode')
    }
    $argParts.Add("-projectPath `"$SampleRoot`"")
    $argParts.Add("-executeMethod $MethodName")
    $argParts.Add("-logFile `"$logPath`"")
    $argParts.Add('-quit')
    $argumentString = [string]::Join(' ', $argParts)

    $previousResultPath = [Environment]::GetEnvironmentVariable('CASE31_RESULT_PATH', 'Process')
    [Environment]::SetEnvironmentVariable('CASE31_RESULT_PATH', $resultPath, 'Process')
    try {
        $process = Start-Process -FilePath $Paths.UnityEditor.Editor -ArgumentList $argumentString -WorkingDirectory $SampleRoot -PassThru
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
            catch {
            }
            throw "Unity automation timed out after $TimeoutSeconds seconds while running $MethodName."
        }
        $exitCode = $process.ExitCode
    }
    finally {
        [Environment]::SetEnvironmentVariable('CASE31_RESULT_PATH', $previousResultPath, 'Process')
    }

    if (-not (Test-Path $resultPath)) {
        throw "Unity automation did not produce a result marker for $MethodName. See $logPath"
    }

    $lines = @(Get-Content -Path $resultPath -ErrorAction Stop)
    $status = if ($lines.Count -gt 0) { $lines[0] } else { 'FAIL' }
    $details = if ($lines.Count -gt 1) { @($lines[1..($lines.Count - 1)]) } else { @() }

    if ($exitCode -ne 0 -or $status -ne 'PASS') {
        $detailText = if ($details.Count -gt 0) { $details -join '; ' } else { 'No details were recorded.' }
        throw "Unity automation $MethodName failed with exit code $exitCode. $detailText See $logPath"
    }

    return [pscustomobject]@{
        LogPath    = $logPath
        ResultPath = $resultPath
        Details    = $details
    }
}

function Get-Case31DatabaseSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot,
        [Parameter(Mandatory = $true)]
        [string]$TrainingRepo
    )

    $required = @('XData.txt', 'YData.txt', 'HierarchyData.txt')
    $candidateDirs = @(
        Get-Case31SampleCharacterRoots -SampleRoot $SampleRoot |
        ForEach-Object { Join-Path $_ 'Database' }
    ) | Where-Object { Test-Path $_ }

    $validDirs = New-Object System.Collections.Generic.List[string]
    foreach ($candidateDir in $candidateDirs) {
        $allPresent = $true
        foreach ($requiredFile in $required) {
            if (-not (Test-Path (Join-Path $candidateDir $requiredFile))) {
                $allPresent = $false
                break
            }
        }
        if ($allPresent) {
            $validDirs.Add($candidateDir)
        }
    }

    $sampleDatabase = @($validDirs) |
        Sort-Object { if ($_ -like '*\Lafan\Database') { 0 } else { 1 } } |
        Select-Object -First 1

    if ($sampleDatabase) {
        return $sampleDatabase
    }

    $legacyDatabase = Join-Path $SampleRoot 'Assets\Motion Matching\Database'
    if (Test-Path $legacyDatabase) {
        if (($required | Where-Object { Test-Path (Join-Path $legacyDatabase $_) }).Count -eq $required.Count) {
            return $legacyDatabase
        }
    }

    return (Join-Path $TrainingRepo 'database')
}

function Sync-Case31DatabaseToSample {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabaseDir,
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot,
        [Parameter(Mandatory = $true)]
        [string]$TrainingRepo
    )

    $repoDatabaseDir = Join-Path $TrainingRepo 'database'
    $repoOnnxDir = Join-Path $TrainingRepo 'onnx'
    $sourceFull = [System.IO.Path]::GetFullPath($SourceDatabaseDir)
    $repoDatabaseFull = [System.IO.Path]::GetFullPath($repoDatabaseDir)

    if ($sourceFull -ine $repoDatabaseFull) {
        Copy-Case31DatabaseArtifacts -SourceDatabaseDir $SourceDatabaseDir -DestinationDatabaseDir $repoDatabaseDir
    }

    if ($sourceFull -ieq $repoDatabaseFull) {
        $characterRoots = @(Get-Case31SampleCharacterRoots -SampleRoot $SampleRoot)
        foreach ($characterRoot in $characterRoots) {
            $databaseTarget = Join-Path $characterRoot 'Database'
            $onnxTarget = Join-Path $characterRoot 'ONNX'
            Copy-Case31DatabaseArtifacts -SourceDatabaseDir $repoDatabaseDir -DestinationDatabaseDir $databaseTarget
            Copy-Case31OnnxArtifacts -SourceOnnxDir $repoOnnxDir -DestinationOnnxDir $onnxTarget
        }

        $legacyDatabase = Join-Path $SampleRoot 'Assets\Motion Matching\Database'
        if (Test-Path $legacyDatabase) {
            Copy-Case31DatabaseArtifacts -SourceDatabaseDir $repoDatabaseDir -DestinationDatabaseDir $legacyDatabase
        }

        $legacyOnnx = Join-Path $SampleRoot 'Assets\Motion Matching\ONNX'
        if (Test-Path $legacyOnnx) {
            Copy-Case31OnnxArtifacts -SourceOnnxDir $repoOnnxDir -DestinationOnnxDir $legacyOnnx
        }
    }
}

function Ensure-Case31PythonPrereqs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths
    )

    $condaEnv = Ensure-ReferenceCondaEnv -Context $Context
    $requirements = @(
        'numpy',
        'scipy',
        'matplotlib',
        'torch',
        'torch_optimizer',
        'onnx',
        'onnxruntime',
        'scikit-learn',
        'tensorboard'
    )
    $moduleNames = @(
        'numpy',
        'scipy',
        'matplotlib',
        'torch',
        'torch_optimizer',
        'onnx',
        'onnxruntime',
        'sklearn',
        'tensorboard'
    )

    $installLog = Get-Case31LogPath -Paths $Paths -Name 'setup-python-prereqs'
    $probeScriptPath = Join-Path (Split-Path $installLog -Parent) 'probe-imports.py'
    $probeScript = @"
import importlib.util
import sys

mods = $(ConvertTo-Json $moduleNames -Compress)
missing = [m for m in mods if importlib.util.find_spec(m) is None]
print(",".join(missing))
sys.exit(1 if missing else 0)
"@
    Write-Case31Utf8NoBom -Path $probeScriptPath -Content $probeScript

    $probe = Invoke-ReferenceConda -Context $Context -Executable 'python' -Arguments @($probeScriptPath) -LogPath $installLog -IgnoreExitCode
    if ($probe.ExitCode -ne 0) {
        $pipUpgrade = Invoke-ReferenceConda -Context $Context -Executable 'python' -Arguments @('-m', 'pip', 'install', '--upgrade', 'pip') -LogPath $installLog
        if ($pipUpgrade.ExitCode -ne 0) {
            Add-Content -Path $installLog -Value 'pip upgrade failed; continuing with dependency installation because the environment may already be usable.'
        }

        $install = Invoke-ReferenceConda -Context $Context -Executable 'python' -Arguments (@('-m', 'pip', 'install') + $requirements) -LogPath $installLog
        if ($install.ExitCode -ne 0) {
            throw 'case 31 python prerequisite installation failed'
        }
    }

    return $condaEnv
}

function Invoke-Case31Training {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths,
        [Parameter(Mandatory = $true)]
        [string]$SampleRoot
    )

    $databaseSource = Get-Case31DatabaseSource -SampleRoot $SampleRoot -TrainingRepo $Paths.TrainingRepo
    Sync-Case31DatabaseToSample -SourceDatabaseDir $databaseSource -SampleRoot $SampleRoot -TrainingRepo $Paths.TrainingRepo

    $repoDatabaseDir = Join-Path $Paths.TrainingRepo 'database'
    $repoOnnxDir = Join-Path $Paths.TrainingRepo 'onnx'
    $runsDir = Ensure-ReferenceDirectory -Path (Join-Path $Context.RunRoot 'case-31-runs')

    $epochs = if ($Context.Smoke) { '8' } else { '10000' }
    $commonArgs = @(
        '--epochs', $epochs,
        '--batchsize', '32',
        '--device', (Get-ReferenceDefaultDevice),
        '--database-dir', $repoDatabaseDir,
        '--onnx-dir', $repoOnnxDir,
        '--runs-dir', $runsDir,
        '--seed', '1234',
        '--log-frequency', '25'
    )
    $pythonEnvironment = @{
        PYTHONUTF8       = '1'
        PYTHONIOENCODING = 'utf-8'
    }

    $decompressorLog = Get-Case31LogPath -Paths $Paths -Name 'decompressor'
    $projectorLog = Get-Case31LogPath -Paths $Paths -Name 'projector'
    $stepperLog = Get-Case31LogPath -Paths $Paths -Name 'stepper'

    $decompressor = Invoke-ReferenceConda -Context $Context -Executable 'python' -Arguments (@('decompressor.py') + $commonArgs) -WorkingDirectory $Paths.TrainingRepo -LogPath $decompressorLog -Environment $pythonEnvironment
    if ($decompressor.ExitCode -ne 0) {
        throw 'decompressor.py failed'
    }

    $projector = Invoke-ReferenceConda -Context $Context -Executable 'python' -Arguments (@('projector.py') + $commonArgs) -WorkingDirectory $Paths.TrainingRepo -LogPath $projectorLog -Environment $pythonEnvironment
    if ($projector.ExitCode -ne 0) {
        throw 'projector.py failed'
    }

    $stepper = Invoke-ReferenceConda -Context $Context -Executable 'python' -Arguments (@('stepper.py') + $commonArgs) -WorkingDirectory $Paths.TrainingRepo -LogPath $stepperLog -Environment $pythonEnvironment
    if ($stepper.ExitCode -ne 0) {
        throw 'stepper.py failed'
    }

    Sync-Case31DatabaseToSample -SourceDatabaseDir $repoDatabaseDir -SampleRoot $SampleRoot -TrainingRepo $Paths.TrainingRepo

    $artifacts = @(
        (Join-Path $repoOnnxDir 'compressor.onnx'),
        (Join-Path $repoOnnxDir 'decompressor.onnx'),
        (Join-Path $repoOnnxDir 'projector.onnx'),
        (Join-Path $repoOnnxDir 'stepper.onnx'),
        (Join-Path $repoDatabaseDir 'YtxyData.txt'),
        (Join-Path $repoDatabaseDir 'QtxyData.txt'),
        (Join-Path $repoDatabaseDir 'ZData.txt')
    ) | Where-Object { Test-Path $_ }

    return [pscustomobject]@{
        DatabaseSource = $databaseSource
        Artifacts      = $artifacts
    }
}

function Invoke-ReferenceCase31Setup {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $paths = Get-Case31Paths -Context $Context -Root $Context.Root
    $sampleRoot = Ensure-Case31ReleaseExtracted -Paths $paths
    $automationScript = Ensure-Case31AutomationScript -SampleRoot $sampleRoot
    $compatibilityArtifacts = @(Apply-Case31SampleCompatibilityPatches -SampleRoot $sampleRoot)
    $barracudaState = Ensure-Case31UnityManifestBarracuda -ProjectRoot $sampleRoot
    $condaEnv = Ensure-Case31PythonPrereqs -Context $Context -Paths $paths

    $notes = New-Object System.Collections.Generic.List[string]
    $notes.Add("Release extracted to: $sampleRoot")
    $notes.Add("Automation script prepared at: $automationScript")
    foreach ($artifact in $compatibilityArtifacts) {
        $notes.Add("Sample compatibility patch applied: $artifact")
    }
    $notes.Add("Conda env prepared: $condaEnv")
    if ($paths.UnityEditor) {
        $notes.Add("Unity editor found: $($paths.UnityEditor.Editor)")
    }
    else {
        $notes.Add('Unity 2021.1.22f1c1 editor was not found on this machine.')
    }

    if ($barracudaState -eq 'added') {
        $notes.Add('Barracuda dependency inserted into Packages/manifest.json.')
    }
    elseif ($barracudaState -eq 'present') {
        $notes.Add('Barracuda dependency already present in Packages/manifest.json.')
    }
    else {
        $notes.Add('No manifest.json was found; Barracuda could not be injected automatically.')
    }

    $status = if ($paths.UnityEditor) { 'PASS' } else { 'BLOCKED' }
    $summary = if ($paths.UnityEditor) {
        'Downloaded the release sample, prepared Python prereqs, and prepared Unity automation hooks.'
    }
    else {
        'Downloaded the release sample and prepared Python prereqs, but Unity automation is blocked because the required editor is missing.'
    }
    return New-ReferenceResult -CaseId $script:CaseId -Stage 'setup' -Status $status -Summary $summary -Notes $notes.ToArray() -Artifacts @($sampleRoot + $compatibilityArtifacts)
}

function Invoke-ReferenceCase31Test {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    $paths = Get-Case31Paths -Context $Context -Root $Context.Root
    $sampleRoot = Ensure-Case31ReleaseExtracted -Paths $paths
    $compatibilityArtifacts = @(Apply-Case31SampleCompatibilityPatches -SampleRoot $sampleRoot)
    $extractRun = Invoke-Case31UnityAutomation -Paths $paths -SampleRoot $sampleRoot -MethodName 'Case31Automation.ExtractDataFromSample' -LogStem 'unity-extract'
    $train = Invoke-Case31Training -Context $Context -Paths $paths -SampleRoot $sampleRoot
    $validateRun = Invoke-Case31UnityAutomation -Paths $paths -SampleRoot $sampleRoot -MethodName 'Case31Automation.ValidateInference' -LogStem 'unity-validate'

    $notes = New-Object System.Collections.Generic.List[string]
    foreach ($detail in @($extractRun.Details)) {
        $notes.Add("[extract] $detail")
    }
    $notes.Add("Database source used: $($train.DatabaseSource)")
    foreach ($detail in @($validateRun.Details)) {
        $notes.Add("[validate] $detail")
    }

    $sampleDatabase = Join-Path $sampleRoot 'Assets\Motion Matching\Database'
    $sampleArtifacts = @()
    foreach ($dir in @($sampleDatabase, (Join-Path $sampleRoot 'Assets\Motion Matching\ONNX')) + (Get-Case31SampleCharacterRoots -SampleRoot $sampleRoot)) {
        if (Test-Path $dir) {
            $sampleArtifacts += $dir
        }
    }

    $summary = 'Ran Unity extraction, trained the parameterized Python models, synced outputs back to the sample, and validated Unity-side inference initialization.'
    return New-ReferenceResult -CaseId $script:CaseId -Stage 'test' -Status 'PASS' -Summary $summary -Notes $notes.ToArray() -Artifacts @($train.Artifacts + $sampleArtifacts + $compatibilityArtifacts + @($extractRun.LogPath, $extractRun.ResultPath, $validateRun.LogPath, $validateRun.ResultPath))
}

if ($null -eq $Context -and $MyInvocation.InvocationName -ne '.') {
    $Context = New-ReferenceContext -Root $RepoRoot -Cases @('31')
}
$script:Context = $Context

function Setup-ReferenceWalkthroughCase31 {
    param([pscustomobject]$Context = $script:Context)
    return Invoke-ReferenceCase31Setup -Context $Context
}

function Test-ReferenceWalkthroughCase31 {
    param([pscustomobject]$Context = $script:Context)
    return Invoke-ReferenceCase31Test -Context $Context
}

if ($MyInvocation.InvocationName -ne '.') {
    $setup = Setup-ReferenceWalkthroughCase31 -Context $Context
    $test = Test-ReferenceWalkthroughCase31 -Context $Context
    Write-ReferenceSummaryReport -Context $Context -Results @($setup, $test) -Name 'case-31-summary' | Out-Null
    $setup
    $test
}
