#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "GASPALSShadowTypes.h"
#include "GASPALSShadowWorldSubsystem.generated.h"

UCLASS()
class GASPALSSHADOW_API UGASPALSShadowWorldSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()

public:
    virtual void Initialize(FSubsystemCollectionBase& Collection) override;

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    FString GetActiveSessionDirectory() const;

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    bool AppendFrameRecord(const FGASPALSShadowFrameRecord& Record);

private:
    void EnsureSessionDirectory();
    void WriteSessionManifest();

    FString SessionDirectory;
    FString LogFilePath;
    FCriticalSection WriteLock;
};
