#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "GASPALSShadowTypes.h"
#include "GASPALSShadowObserverComponent.generated.h"

UCLASS(ClassGroup = (GASPALSShadow), BlueprintType, Blueprintable, meta = (BlueprintSpawnableComponent))
class GASPALSSHADOW_API UGASPALSShadowObserverComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    UGASPALSShadowObserverComponent();

    virtual void BeginPlay() override;
    virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bAutoCaptureOwnerState = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow", meta = (ClampMin = "0.0"))
    float CaptureIntervalSeconds = 0.0f;

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    FGASPALSShadowFrameRecord BuildOwnerSnapshot() const;

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    bool RecordFrame(const FGASPALSShadowFrameRecord& Record);

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    void SetNamedFloat(FName Name, float Value);

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    void SetNamedString(FName Name, const FString& Value);

    UFUNCTION(BlueprintCallable, Category = "GASPALSShadow")
    void ClearNamedMetadata();

private:
    int64 CaptureCounter = 0;
    float TimeSinceLastCapture = 0.0f;

    UPROPERTY(Transient)
    TMap<FString, float> PendingNamedFloats;

    UPROPERTY(Transient)
    TMap<FString, FString> PendingNamedStrings;
};
