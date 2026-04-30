// Copyright 2020-2026 Naotsun. All Rights Reserved.

using System.IO;
using UnrealBuildTool;

public class GraphPrinterRemoteControl : ModuleRules
{
    public GraphPrinterRemoteControl(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
#if UE_5_2_OR_LATER
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
#endif

        PublicDependencyModuleNames.AddRange(
            new string[]
            {
                "Core",
            }
        );

        PrivateDependencyModuleNames.AddRange(
            new string[]
            {
                "CoreUObject",
                "Engine",
                "Slate",
                "SlateCore",
                "WebSockets",
                "Json",
                "UnrealEd",
                "Kismet",
                "BlueprintGraph",
                "GraphEditor",
                
                "GraphPrinterGlobals",
                "GraphPrinterEditorExtension",
                "WidgetPrinter",
                "GenericGraphPrinter",
                "ClipboardImageExtension",
                "TextChunkHelper",
            }
        );

        PrivateIncludePaths.AddRange(
            new string[]
            {
                Path.Combine(EngineDirectory, "Source", "Editor", "GraphEditor", "Private"),
            }
        );
    }
}
