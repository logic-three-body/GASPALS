// Copyright 2020-2026 Naotsun. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "WidgetPrinter/Types/PrintWidgetOptions.h"
#include "PrintGraphOptions.generated.h"

class UEdGraphNode;

/**
 * An optional class to specify when printing the graph editor.
 */
UCLASS()
class GENERICGRAPHPRINTER_API UPrintGraphOptions : public UPrintWidgetOptions
{
	GENERATED_BODY()

public:
	// Constructor.
	UPrintGraphOptions();

	// UPrintWidgetOptions interface.
	virtual UPrintWidgetOptions* Duplicate(const TSubclassOf<UPrintWidgetOptions>& DestinationClass) const override;
	// End of UPrintWidgetOptions interface.

public:
	// The margins when drawing the graph editor.
	float Padding;
	
	// Whether to hide the title bar of the graph editor and the text of the graph type in the lower right.
	bool bDrawOnlyGraph;

	// If non-empty and PrintScope is Selected, these nodes are selected temporarily for printing.
	TArray<TWeakObjectPtr<UEdGraphNode>> ExplicitNodesToPrint;

	// If non-empty, this value is used as the output filename base instead of the graph title.
	FString FilenameBaseOverride;
};
