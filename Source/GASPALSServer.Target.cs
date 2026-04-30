using UnrealBuildTool;
using System.Collections.Generic;

public class GASPALSServerTarget : TargetRules
{
	public GASPALSServerTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Server;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("GASPALS");
	}
}
