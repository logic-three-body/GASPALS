#include "GASPALSShadowObserverComponent.h"

#include "Animation/AnimInstance.h"
#include "Components/SkeletalMeshComponent.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/Controller.h"
#include "GameFramework/Pawn.h"
#include "GASPALSShadowWorldSubsystem.h"

UGASPALSShadowObserverComponent::UGASPALSShadowObserverComponent()
{
    PrimaryComponentTick.bCanEverTick = true;
    PrimaryComponentTick.bStartWithTickEnabled = true;
}

void UGASPALSShadowObserverComponent::BeginPlay()
{
    Super::BeginPlay();
    TimeSinceLastCapture = CaptureIntervalSeconds;
}

void UGASPALSShadowObserverComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
    Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

    if (!bAutoCaptureOwnerState)
    {
        return;
    }

    TimeSinceLastCapture += DeltaTime;
    if (TimeSinceLastCapture < CaptureIntervalSeconds)
    {
        return;
    }

    TimeSinceLastCapture = 0.0f;
    RecordFrame(BuildOwnerSnapshot());
}

FGASPALSShadowFrameRecord UGASPALSShadowObserverComponent::BuildOwnerSnapshot() const
{
    FGASPALSShadowFrameRecord Record;

    const AActor* Owner = GetOwner();
    const UWorld* World = GetWorld();

    Record.FrameIndex = CaptureCounter;
    Record.WorldTimeSeconds = World ? World->GetTimeSeconds() : 0.0;
    Record.DeltaSeconds = World ? World->GetDeltaSeconds() : 0.0f;
    Record.ActorName = Owner ? Owner->GetName() : TEXT("None");

    if (!Owner)
    {
        return Record;
    }

    Record.Movement.ActorLocation = Owner->GetActorLocation();
    Record.Movement.ActorRotation = Owner->GetActorRotation();
    Record.Movement.Velocity = Owner->GetVelocity();
    Record.Movement.Speed = Record.Movement.Velocity.Size();

    if (const APawn* Pawn = Cast<APawn>(Owner))
    {
        if (const AController* Controller = Pawn->GetController())
        {
            Record.Input.ControlRotation = Controller->GetControlRotation();
        }
    }

    for (const FName& Tag : Owner->Tags)
    {
        Record.Animation.ObservedTags.Add(Tag.ToString());
    }

    if (const ACharacter* Character = Cast<ACharacter>(Owner))
    {
        if (const UCharacterMovementComponent* MovementComponent = Character->GetCharacterMovement())
        {
            Record.Movement.Acceleration = MovementComponent->GetCurrentAcceleration();
            Record.Movement.MovementMode = UEnum::GetValueAsString(MovementComponent->MovementMode);
            Record.Movement.CustomMovementMode = MovementComponent->CustomMovementMode;
        }

        if (const USkeletalMeshComponent* Mesh = Character->GetMesh())
        {
            if (const UAnimInstance* AnimInstance = Mesh->GetAnimInstance())
            {
                Record.Animation.AnimInstanceClass = AnimInstance->GetClass()->GetName();
                if (const UAnimMontage* ActiveMontage = AnimInstance->GetCurrentActiveMontage())
                {
                    Record.Animation.ActiveMontage = ActiveMontage->GetName();
                }
            }

            if (const UObject* SkeletalMesh = Mesh->GetSkeletalMeshAsset())
            {
                Record.Animation.SkeletalMesh = SkeletalMesh->GetName();
            }
        }
    }

    Record.NamedFloats = PendingNamedFloats;
    Record.NamedStrings = PendingNamedStrings;

    return Record;
}

bool UGASPALSShadowObserverComponent::RecordFrame(const FGASPALSShadowFrameRecord& Record)
{
    if (UWorld* World = GetWorld())
    {
        if (UGASPALSShadowWorldSubsystem* Subsystem = World->GetSubsystem<UGASPALSShadowWorldSubsystem>())
        {
            ++CaptureCounter;
            return Subsystem->AppendFrameRecord(Record);
        }
    }

    return false;
}

void UGASPALSShadowObserverComponent::SetNamedFloat(FName Name, float Value)
{
    PendingNamedFloats.Add(Name.ToString(), Value);
}

void UGASPALSShadowObserverComponent::SetNamedString(FName Name, const FString& Value)
{
    PendingNamedStrings.Add(Name.ToString(), Value);
}

void UGASPALSShadowObserverComponent::ClearNamedMetadata()
{
    PendingNamedFloats.Reset();
    PendingNamedStrings.Reset();
}
