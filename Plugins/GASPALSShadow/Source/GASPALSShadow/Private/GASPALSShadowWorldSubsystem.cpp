#include "GASPALSShadowWorldSubsystem.h"

#include "JsonObjectConverter.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/ScopeLock.h"

void UGASPALSShadowWorldSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
    Super::Initialize(Collection);
    EnsureSessionDirectory();
    WriteSessionManifest();
}

FString UGASPALSShadowWorldSubsystem::GetActiveSessionDirectory() const
{
    return SessionDirectory;
}

bool UGASPALSShadowWorldSubsystem::AppendFrameRecord(const FGASPALSShadowFrameRecord& Record)
{
    EnsureSessionDirectory();

    FString JsonLine;
    if (!FJsonObjectConverter::UStructToJsonObjectString(Record, JsonLine))
    {
        return false;
    }

    JsonLine.AppendChar(TEXT('\n'));

    FScopeLock Guard(&WriteLock);
    return FFileHelper::SaveStringToFile(
        JsonLine,
        *LogFilePath,
        FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,
        &IFileManager::Get(),
        FILEWRITE_Append);
}

void UGASPALSShadowWorldSubsystem::EnsureSessionDirectory()
{
    if (!SessionDirectory.IsEmpty())
    {
        return;
    }

    const FString Timestamp = FDateTime::Now().ToString(TEXT("%Y%m%d_%H%M%S"));
    SessionDirectory = FPaths::Combine(FPaths::ProjectLogDir(), TEXT("GASPALSShadow"), Timestamp);
    LogFilePath = FPaths::Combine(SessionDirectory, TEXT("frames.jsonl"));

    IFileManager::Get().MakeDirectory(*SessionDirectory, true);
}

void UGASPALSShadowWorldSubsystem::WriteSessionManifest()
{
    EnsureSessionDirectory();

    const FString WorldName = GetWorld() ? GetWorld()->GetMapName() : TEXT("UnknownWorld");
    const FString Manifest = FString::Printf(
        TEXT("{\n")
        TEXT("  \"schema_version\": \"gaspals_shadow/v1\",\n")
        TEXT("  \"created_at\": \"%s\",\n")
        TEXT("  \"world\": \"%s\",\n")
        TEXT("  \"frames\": \"frames.jsonl\"\n")
        TEXT("}\n"),
        *FDateTime::Now().ToIso8601(),
        *WorldName);

    const FString ManifestPath = FPaths::Combine(SessionDirectory, TEXT("session.json"));
    FFileHelper::SaveStringToFile(Manifest, *ManifestPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}
