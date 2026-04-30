using UnrealBuildTool;
using System.Collections.Generic;

public class GASPALSEditorTarget : TargetRules
{
	public GASPALSEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V6;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("GASPALS");
	}
}
