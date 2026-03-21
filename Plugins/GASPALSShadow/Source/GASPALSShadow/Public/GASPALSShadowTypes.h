#pragma once

#include "CoreMinimal.h"
#include "GASPALSShadowTypes.generated.h"

UENUM(BlueprintType)
enum class EGASPALSShadowControlMode : uint8
{
    Unknown UMETA(DisplayName = "Unknown"),
    Uncontrolled UMETA(DisplayName = "Uncontrolled"),
    VelocityFacing UMETA(DisplayName = "Velocity Facing"),
    Trajectory UMETA(DisplayName = "Trajectory")
};

USTRUCT(BlueprintType)
struct GASPALSSHADOW_API FGASPALSShadowInputSample
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    EGASPALSShadowControlMode ControlMode = EGASPALSShadowControlMode::Unknown;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector2D MoveStick = FVector2D::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector2D LookStick = FVector2D::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    float LeftTrigger = 0.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    float RightTrigger = 0.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bDesiredStrafe = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bDesiredWalk = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bDesiredSprint = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bJumpPressed = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bCrouchRequested = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FRotator ControlRotation = FRotator::ZeroRotator;
};

USTRUCT(BlueprintType)
struct GASPALSSHADOW_API FGASPALSShadowMovementSample
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector ActorLocation = FVector::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FRotator ActorRotation = FRotator::ZeroRotator;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector Velocity = FVector::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector Acceleration = FVector::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector AngularVelocity = FVector::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString MovementMode = TEXT("Unknown");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    uint8 CustomMovementMode = 0;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    float Speed = 0.0f;
};

USTRUCT(BlueprintType)
struct GASPALSSHADOW_API FGASPALSShadowTrajectoryPoint
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector LocalPosition = FVector::ZeroVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FVector LocalDirection = FVector::ForwardVector;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    float HorizonSeconds = 0.0f;
};

USTRUCT(BlueprintType)
struct GASPALSSHADOW_API FGASPALSShadowAnimationSample
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString AnimInstanceClass;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString SkeletalMesh;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString OverlayBase;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString OverlayPose;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString ActiveMontage;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    TArray<FString> ObservedTags;
};

USTRUCT(BlueprintType)
struct GASPALSSHADOW_API FGASPALSShadowTraversalSample
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bTraversalRequested = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    bool bTraversalAvailable = false;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString TraversalState;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString LastChooserResult;
};

USTRUCT(BlueprintType)
struct GASPALSSHADOW_API FGASPALSShadowFrameRecord
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString SchemaVersion = TEXT("gaspals_shadow/v1");

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    int64 FrameIndex = 0;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    double WorldTimeSeconds = 0.0;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    float DeltaSeconds = 0.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FString ActorName;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FGASPALSShadowInputSample Input;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FGASPALSShadowMovementSample Movement;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    TArray<FGASPALSShadowTrajectoryPoint> Trajectory;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FGASPALSShadowAnimationSample Animation;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    FGASPALSShadowTraversalSample Traversal;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    TMap<FString, float> NamedFloats;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GASPALSShadow")
    TMap<FString, FString> NamedStrings;
};
