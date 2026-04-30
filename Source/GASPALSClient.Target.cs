using UnrealBuildTool;
using System.Collections.Generic;

public class GASPALSClientTarget : TargetRules
{
	public GASPALSClientTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Client;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("GASPALS");
	}
}
