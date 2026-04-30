// Copyright 2020-2026 Naotsun. All Rights Reserved.

#include "GraphPrinterRemoteControl/Utilities/GraphPrinterRemoteControlSettings.h"
#include "GraphPrinterGlobals/GraphPrinterGlobals.h"

#if UE_5_01_OR_LATER
#include UE_INLINE_GENERATED_CPP_BY_NAME(GraphPrinterRemoteControlSettings)
#endif

UGraphPrinterRemoteControlSettings::FOnRemoteControlEnabled UGraphPrinterRemoteControlSettings::OnRemoteControlEnabled;
UGraphPrinterRemoteControlSettings::FOnRemoteControlDisabled UGraphPrinterRemoteControlSettings::OnRemoteControlDisabled;

UGraphPrinterRemoteControlSettings::UGraphPrinterRemoteControlSettings()
	: bEnableRemoteControl(false)
	, ServerURL(TEXT("ws://127.0.0.1:3000/"))
{
}

void UGraphPrinterRemoteControlSettings::Reconnect()
{
	OnRemoteControlDisabled.Broadcast();
	if (bEnableRemoteControl)
	{
		OnRemoteControlEnabled.Broadcast(ServerURL);
	}
}

void UGraphPrinterRemoteControlSettings::PostEditChangeProperty(FPropertyChangedEvent& PropertyChangedEvent)
{
	Super::PostEditChangeProperty(PropertyChangedEvent);

	if (PropertyChangedEvent.MemberProperty == nullptr)
	{
		Reconnect();
		return;
	}

	if (PropertyChangedEvent.MemberProperty->GetFName() == GET_MEMBER_NAME_CHECKED(UGraphPrinterRemoteControlSettings, bEnableRemoteControl) ||
		PropertyChangedEvent.MemberProperty->GetFName() == GET_MEMBER_NAME_CHECKED(UGraphPrinterRemoteControlSettings, ServerURL))
	{
		Reconnect();
	}
}

FString UGraphPrinterRemoteControlSettings::GetSettingsName() const
{
	return TEXT("RemoteControl");
}
