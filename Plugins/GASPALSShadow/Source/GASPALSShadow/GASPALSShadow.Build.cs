using UnrealBuildTool;

public class GASPALSShadow : ModuleRules
{
    public GASPALSShadow(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(
            new[]
            {
                "Core",
                "CoreUObject",
                "Engine"
            });

        PrivateDependencyModuleNames.AddRange(
            new[]
            {
                "Json",
                "JsonUtilities"
            });
    }
}
