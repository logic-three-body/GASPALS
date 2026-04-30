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
    private const float BoundsRatioMin = 0.6f;
    private const float BoundsRatioMax = 1.6f;
    private const float ChainRatioMin = 0.6f;
    private const float ChainRatioMax = 1.4f;

    private static readonly string[] RequiredGameplays = { "Lafan", "Bunny" };

    private static string ResultPath => Environment.GetEnvironmentVariable("CASE31_RESULT_PATH");

    private sealed class ValidationLogScope : IDisposable
    {
        public readonly List<string> BlockingMessages = new List<string>();

        public ValidationLogScope()
        {
            Application.logMessageReceived += OnLogMessageReceived;
        }

        public void Dispose()
        {
            Application.logMessageReceived -= OnLogMessageReceived;
        }

        private void OnLogMessageReceived(string condition, string stackTrace, LogType type)
        {
            if (type != LogType.Error && type != LogType.Assert && type != LogType.Exception)
            {
                return;
            }

            var text = string.IsNullOrWhiteSpace(stackTrace) ? condition : condition + " | " + stackTrace;
            BlockingMessages.Add(Sanitize(text));
        }
    }

    private sealed class PoseMetrics
    {
        public float BoundsMagnitude;
        public readonly Dictionary<string, float> ChainLengths = new Dictionary<string, float>(StringComparer.OrdinalIgnoreCase);
    }

    private sealed class GameplayRunResult
    {
        public string Gameplay;
        public string Mode;
        public string Status;
        public string Issue;
        public string Detail;
        public string PrefabPath;
        public string OnnxDirectory;
        public string ModelAssets;
        public float? BoundsRatio;
        public float? ChainMinRatio;
        public float? ChainMaxRatio;
    }

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

    private static string GetGameplayKind(Gameplay gameplay)
    {
        var prefabPath = gameplay.mm?.prefab != null ? AssetDatabase.GetAssetPath(gameplay.mm.prefab) : string.Empty;
        if (prefabPath.IndexOf("/Lafan/", StringComparison.OrdinalIgnoreCase) >= 0 ||
            gameplay.name.IndexOf("lafan", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return "Lafan";
        }

        if (prefabPath.IndexOf("/Cenoura/", StringComparison.OrdinalIgnoreCase) >= 0 ||
            prefabPath.IndexOf("bunny", StringComparison.OrdinalIgnoreCase) >= 0 ||
            gameplay.name.IndexOf("bunny", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return "Bunny";
        }

        return "Other";
    }

    private static Dictionary<string, Gameplay> GetRequiredGameplays()
    {
        var gameplays = FindGameplays();
        if (gameplays.Length == 0)
        {
            throw new InvalidOperationException("No Gameplay components were found in the loaded scene.");
        }

        var selected = gameplays
            .Select(gameplay => new { Gameplay = gameplay, Kind = GetGameplayKind(gameplay) })
            .Where(item => RequiredGameplays.Contains(item.Kind, StringComparer.OrdinalIgnoreCase))
            .GroupBy(item => item.Kind, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Gameplay, StringComparer.OrdinalIgnoreCase);

        foreach (var required in RequiredGameplays)
        {
            if (!selected.ContainsKey(required))
            {
                throw new InvalidOperationException("Could not resolve required Gameplay '" + required + "' in the loaded scene.");
            }
        }

        return selected;
    }

    private static Gameplay OpenGameplay(string scenePath, string gameplayKind)
    {
        EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh(ImportAssetOptions.ForceUpdate);

        var selected = GetRequiredGameplays();
        return selected[gameplayKind];
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

    private static void EnsureInput(Gameplay gameplay)
    {
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
    }

    private static void UpdateInput(Gameplay gameplay, int frameIndex)
    {
        var scale = 1f + (0.05f * frameIndex);
        gameplay.input.trajectory[0] = new Vector3(0.15f * scale, 0f, 0.25f * scale);
        gameplay.input.trajectory[1] = new Vector3(0.30f * scale, 0f, 0.50f * scale);
        gameplay.input.trajectory[2] = new Vector3(0.45f * scale, 0f, 0.75f * scale);
    }

    private static void SafeDispose(MM.MotionMatching motionMatching)
    {
        if (motionMatching == null)
        {
            return;
        }

        try
        {
            motionMatching.DisposeTensors();
        }
        catch
        {
        }
    }

    private static string Sanitize(string value)
    {
        return (value ?? string.Empty)
            .Replace("\r", " ")
            .Replace("\n", " ")
            .Replace(";", ",")
            .Trim();
    }

    private static void AddRecord(List<string> lines, IDictionary<string, string> fields)
    {
        var payload = fields
            .Where(pair => !string.IsNullOrWhiteSpace(pair.Value))
            .Select(pair => pair.Key + "=" + Sanitize(pair.Value));
        lines.Add(string.Join(";", payload));
    }

    private static void AddStageRecord(List<string> lines, string stage, string gameplay, string mode, string status, string issue, string detail)
    {
        AddRecord(lines, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Stage"] = stage,
            ["Gameplay"] = gameplay,
            ["Mode"] = mode,
            ["Status"] = status,
            ["Issue"] = issue,
            ["Detail"] = detail
        });
    }

    private static void AddVisualRecord(List<string> lines, string gameplay, string mode, string status, string issue, string detail, float boundsRatio, float chainMin, float chainMax)
    {
        AddRecord(lines, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Stage"] = "Visual",
            ["Gameplay"] = gameplay,
            ["Mode"] = mode,
            ["Status"] = status,
            ["Issue"] = issue,
            ["Detail"] = detail,
            ["BoundsRatio"] = boundsRatio.ToString("F4"),
            ["ChainMinRatio"] = chainMin.ToString("F4"),
            ["ChainMaxRatio"] = chainMax.ToString("F4")
        });
    }

    private static void AddAssetRecord(List<string> lines, GameplayRunResult result)
    {
        AddRecord(lines, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Stage"] = "ValidateAssets",
            ["Gameplay"] = result.Gameplay,
            ["Mode"] = result.Mode,
            ["Status"] = "INFO",
            ["Prefab"] = result.PrefabPath,
            ["OnnxDir"] = result.OnnxDirectory,
            ["Models"] = result.ModelAssets
        });
    }

    private static Transform FindRequiredRelative(Transform character, string relativePath)
    {
        var transform = character.Find(relativePath);
        if (transform == null)
        {
            throw new MissingReferenceException("Could not resolve Bunny transform '" + relativePath + "'.");
        }

        return transform;
    }

    private static float GetChainLength(params Transform[] chain)
    {
        if (chain == null || chain.Length < 2)
        {
            return 0f;
        }

        float total = 0f;
        for (var i = 1; i < chain.Length; i++)
        {
            total += Vector3.Distance(chain[i - 1].position, chain[i].position);
        }

        return total;
    }

    private static SkinnedMeshRenderer GetPrimaryRenderer(Gameplay gameplay)
    {
        return gameplay.GetComponentsInChildren<SkinnedMeshRenderer>(true)
            .Where(renderer => renderer != null && renderer.sharedMesh != null)
            .OrderByDescending(renderer => renderer.sharedMesh.bounds.size.sqrMagnitude)
            .FirstOrDefault();
    }

    private static PoseMetrics CaptureBunnyMetrics(Gameplay gameplay)
    {
        var character = gameplay.mm?.targetBones?.character;
        if (character == null)
        {
            throw new InvalidOperationException("Bunny gameplay is missing targetBones.character.");
        }

        var metrics = new PoseMetrics();
        var renderer = GetPrimaryRenderer(gameplay);
        if (renderer == null)
        {
            throw new MissingComponentException("Could not resolve a SkinnedMeshRenderer for Bunny.");
        }

        metrics.BoundsMagnitude = renderer.bounds.size.magnitude;

        var root = FindRequiredRelative(character, "Bunny.game_rig/root");
        var spine = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine");
        var spine1 = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001");
        var spine2 = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002");
        var spine3 = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003");
        var neck = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-neck");
        var head = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-neck/DEF-head");

        var leftUpperLeg = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-upper_leg.L");
        var leftLowerLeg = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-upper_leg.L/DEF-upper_leg.L.001/DEF-lower_leg.L");
        var leftFoot = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-upper_leg.L/DEF-upper_leg.L.001/DEF-lower_leg.L/DEF-lower_leg.L.001/DEF-foot.L");
        var rightUpperLeg = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-upper_leg.R");
        var rightLowerLeg = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-upper_leg.R/DEF-upper_leg.R.001/DEF-lower_leg.R");
        var rightFoot = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-upper_leg.R/DEF-upper_leg.R.001/DEF-lower_leg.R/DEF-lower_leg.R.001/DEF-foot.R");

        var leftShoulder = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.L");
        var leftUpperArm = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.L/DEF-upper_arm.L");
        var leftForearm = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.L/DEF-upper_arm.L/DEF-upper_arm.L.001/DEF-forearm.L");
        var leftHand = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.L/DEF-upper_arm.L/DEF-upper_arm.L.001/DEF-forearm.L/DEF-forearm.L.001/DEF-hand.L");
        var rightShoulder = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.R");
        var rightUpperArm = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.R/DEF-upper_arm.R");
        var rightForearm = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.R/DEF-upper_arm.R/DEF-upper_arm.R.001/DEF-forearm.R");
        var rightHand = FindRequiredRelative(character, "Bunny.game_rig/root/DEF-spine/DEF-spine.001/DEF-spine.002/DEF-spine.003/DEF-shoulder.R/DEF-upper_arm.R/DEF-upper_arm.R.001/DEF-forearm.R/DEF-forearm.R.001/DEF-hand.R");

        metrics.ChainLengths["root-spine"] = GetChainLength(root, spine);
        metrics.ChainLengths["spine-head"] = GetChainLength(spine, spine1, spine2, spine3, neck, head);
        metrics.ChainLengths["left-leg"] = GetChainLength(leftUpperLeg, leftLowerLeg, leftFoot);
        metrics.ChainLengths["right-leg"] = GetChainLength(rightUpperLeg, rightLowerLeg, rightFoot);
        metrics.ChainLengths["left-arm"] = GetChainLength(leftShoulder, leftUpperArm, leftForearm, leftHand);
        metrics.ChainLengths["right-arm"] = GetChainLength(rightShoulder, rightUpperArm, rightForearm, rightHand);

        return metrics;
    }

    private static List<string> EvaluateBunnyMetrics(PoseMetrics baseline, PoseMetrics current, out float boundsRatio, out float chainMinRatio, out float chainMaxRatio)
    {
        var issues = new List<string>();

        if (baseline == null || current == null)
        {
            boundsRatio = 0f;
            chainMinRatio = 0f;
            chainMaxRatio = 0f;
            issues.Add("Missing pose metrics.");
            return issues;
        }

        boundsRatio = baseline.BoundsMagnitude > 1e-6f ? current.BoundsMagnitude / baseline.BoundsMagnitude : 0f;
        chainMinRatio = float.MaxValue;
        chainMaxRatio = float.MinValue;

        if (!float.IsFinite(boundsRatio) || boundsRatio < BoundsRatioMin || boundsRatio > BoundsRatioMax)
        {
            issues.Add("Bounds ratio out of range: " + boundsRatio.ToString("F4"));
        }

        foreach (var pair in baseline.ChainLengths)
        {
            if (!current.ChainLengths.TryGetValue(pair.Key, out var currentLength))
            {
                issues.Add("Missing chain metric: " + pair.Key);
                continue;
            }

            var ratio = pair.Value > 1e-6f ? currentLength / pair.Value : 0f;
            chainMinRatio = Mathf.Min(chainMinRatio, ratio);
            chainMaxRatio = Mathf.Max(chainMaxRatio, ratio);

            if (!float.IsFinite(ratio) || ratio < ChainRatioMin || ratio > ChainRatioMax)
            {
                issues.Add("Chain ratio out of range for " + pair.Key + ": " + ratio.ToString("F4"));
            }
        }

        if (chainMinRatio == float.MaxValue)
        {
            chainMinRatio = 0f;
        }

        if (chainMaxRatio == float.MinValue)
        {
            chainMaxRatio = 0f;
        }

        return issues;
    }

    private static GameplayRunResult RunGameplayInference(string scenePath, string gameplayKind, string mode, bool enableDecompressor, int frames, bool checkVisualStability)
    {
        var result = new GameplayRunResult
        {
            Gameplay = gameplayKind,
            Mode = mode,
            Status = "PASS",
            Issue = string.Empty,
            Detail = string.Empty,
            BoundsRatio = 1f,
            ChainMinRatio = 1f,
            ChainMaxRatio = 1f
        };

        MM.MotionMatching motionMatching = null;

        try
        {
            var gameplay = OpenGameplay(scenePath, gameplayKind);
            motionMatching = gameplay.mm;
            if (motionMatching == null)
            {
                throw new InvalidOperationException("Gameplay '" + gameplay.name + "' is missing MotionMatching configuration.");
            }

            var setupLines = new List<string>();
            EnsureGameplayInferenceAssets(gameplay, setupLines);
            EnsureInput(gameplay);
            result.PrefabPath = GetPrefabPath(gameplay);
            result.OnnxDirectory = GetOnnxDirectory(gameplay);
            result.ModelAssets = string.Join(" | ", setupLines.Where(line => !line.StartsWith("Prefab=", StringComparison.OrdinalIgnoreCase) && !line.StartsWith("OnnxDir=", StringComparison.OrdinalIgnoreCase)));

            PoseMetrics baseline = null;
            if (checkVisualStability)
            {
                baseline = CaptureBunnyMetrics(gameplay);
            }

            motionMatching.enableDecompressor = enableDecompressor;
            motionMatching.enableProjector = true;
            motionMatching.enableStepper = true;
            motionMatching.projectorFreq = 1f;
            motionMatching.Build(gameplay.gameObject);

            using (var logScope = new ValidationLogScope())
            {
                for (var frameIndex = 0; frameIndex < frames; frameIndex++)
                {
                    UpdateInput(gameplay, frameIndex);
                    motionMatching.Matching(ref gameplay.input);
                }

                if (logScope.BlockingMessages.Count > 0)
                {
                    result.Status = "FAIL";
                    result.Issue = "RuntimeLog";
                    result.Detail = string.Join(" | ", logScope.BlockingMessages.Take(3));
                    return result;
                }
            }

            if (checkVisualStability)
            {
                var current = CaptureBunnyMetrics(gameplay);
                var issues = EvaluateBunnyMetrics(baseline, current, out var boundsRatio, out var chainMin, out var chainMax);
                result.BoundsRatio = boundsRatio;
                result.ChainMinRatio = chainMin;
                result.ChainMaxRatio = chainMax;

                if (issues.Count > 0)
                {
                    result.Status = "FAIL";
                    result.Issue = "VisualStability";
                    result.Detail = string.Join(" | ", issues);
                }
            }

            return result;
        }
        catch (Exception ex)
        {
            result.Status = "FAIL";
            result.Issue = "Exception";
            result.Detail = Sanitize(ex.ToString());
            return result;
        }
        finally
        {
            SafeDispose(motionMatching);
        }
    }

    public static void ExtractDataFromSample()
    {
        try
        {
            var scenePath = ResolveScenePath();
            EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
            var selectedGameplays = GetRequiredGameplays();

            var lines = new List<string> { "Scene=" + scenePath };
            var projectRoot = Path.GetDirectoryName(Application.dataPath) ?? ".";

            foreach (var gameplayKind in RequiredGameplays)
            {
                var gameplay = selectedGameplays[gameplayKind];
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

                AddRecord(lines, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    ["Stage"] = "Extract",
                    ["Gameplay"] = gameplayKind,
                    ["Status"] = "PASS",
                    ["Database"] = databaseDir
                });
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
            var lines = new List<string> { "Scene=" + scenePath };

            var lafanResult = RunGameplayInference(scenePath, "Lafan", "predicted", true, 6, false);
            AddAssetRecord(lines, lafanResult);
            AddStageRecord(lines, "Validate", lafanResult.Gameplay, lafanResult.Mode, lafanResult.Status, lafanResult.Issue, lafanResult.Detail);
            if (!string.Equals(lafanResult.Status, "PASS", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Lafan validation failed: " + lafanResult.Detail);
            }

            var bunnyGroundTruth = RunGameplayInference(scenePath, "Bunny", "ground-truth", false, 6, true);
            AddAssetRecord(lines, bunnyGroundTruth);
            AddStageRecord(lines, "Validate", bunnyGroundTruth.Gameplay, bunnyGroundTruth.Mode, bunnyGroundTruth.Status, bunnyGroundTruth.Issue, bunnyGroundTruth.Detail);
            AddVisualRecord(
                lines,
                bunnyGroundTruth.Gameplay,
                bunnyGroundTruth.Mode,
                bunnyGroundTruth.Status,
                bunnyGroundTruth.Issue,
                bunnyGroundTruth.Detail,
                bunnyGroundTruth.BoundsRatio ?? 0f,
                bunnyGroundTruth.ChainMinRatio ?? 0f,
                bunnyGroundTruth.ChainMaxRatio ?? 0f);

            var bunnyPredicted = RunGameplayInference(scenePath, "Bunny", "predicted", true, 6, true);
            AddAssetRecord(lines, bunnyPredicted);
            AddStageRecord(lines, "Validate", bunnyPredicted.Gameplay, bunnyPredicted.Mode, bunnyPredicted.Status, bunnyPredicted.Issue, bunnyPredicted.Detail);
            AddVisualRecord(
                lines,
                bunnyPredicted.Gameplay,
                bunnyPredicted.Mode,
                bunnyPredicted.Status,
                bunnyPredicted.Issue,
                bunnyPredicted.Detail,
                bunnyPredicted.BoundsRatio ?? 0f,
                bunnyPredicted.ChainMinRatio ?? 0f,
                bunnyPredicted.ChainMaxRatio ?? 0f);

            WriteResult("PASS", lines);
            EditorApplication.Exit(0);
        }
        catch (Exception ex)
        {
            Fail(ex);
        }
    }
}
