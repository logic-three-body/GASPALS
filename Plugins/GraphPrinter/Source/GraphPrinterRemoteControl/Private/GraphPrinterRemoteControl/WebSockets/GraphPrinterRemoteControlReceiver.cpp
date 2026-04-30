// Copyright 2020-2026 Naotsun. All Rights Reserved.

#include "GraphPrinterRemoteControl/WebSockets/GraphPrinterRemoteControlReceiver.h"
#include "GraphPrinterRemoteControl/Utilities/GraphPrinterRemoteControlSettings.h"
#include "GraphPrinterGlobals/GraphPrinterGlobals.h"
#include "GraphPrinterEditorExtension/CommandActions/GraphPrinterCommands.h"
#include "GenericGraphPrinter/Types/PrintGraphOptions.h"
#include "GenericGraphPrinter/Utilities/GenericGraphPrinterUtils.h"
#include "GenericGraphPrinter/WidgetPrinters/GenericGraphPrinter.h"
#include "WidgetPrinter/IWidgetPrinterRegistry.h"
#include "WidgetPrinter/Utilities/WidgetPrinterUtils.h"
#include "Algo/Sort.h"
#include "BlueprintEditorModule.h"
#include "Containers/Ticker.h"
#include "Dom/JsonValue.h"
#include "EdGraph/EdGraph.h"
#include "EdGraph/EdGraphNode.h"
#include "EdGraph/EdGraphPin.h"
#include "EdGraphUtilities.h"
#include "EdGraphNode_Comment.h"
#include "Engine/Blueprint.h"
#include "GraphEditor.h"
#include "K2Node_Knot.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "SGraphEditorImpl.h"
#include "WebSocketsModule.h"
#include "IWebSocket.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "Misc/Guid.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "UObject/UnrealType.h"
#include "Framework/Application/SlateApplication.h"
#include "Widgets/SWindow.h"

namespace GraphPrinter
{
	namespace RemoteControlJson
	{
		static const FString CommandPrintAllAreaOfWidget = TEXT("PrintAllAreaOfWidget");
		static const FString CommandPrintGraphModules = TEXT("PrintGraphModules");
		static const FString TargetKindGraphOnly = TEXT("GraphOnly");

		static FString GetStringField(const TSharedPtr<FJsonObject>& JsonObject, const FString& FieldName, const FString& DefaultValue = TEXT(""))
		{
			FString Value;
			return (JsonObject.IsValid() && JsonObject->TryGetStringField(FieldName, Value)) ? Value : DefaultValue;
		}

		static bool GetBoolField(const TSharedPtr<FJsonObject>& JsonObject, const FString& FieldName, const bool bDefaultValue)
		{
			bool bValue = bDefaultValue;
			return (JsonObject.IsValid() && JsonObject->TryGetBoolField(FieldName, bValue)) ? bValue : bDefaultValue;
		}

		static int32 GetIntField(const TSharedPtr<FJsonObject>& JsonObject, const FString& FieldName, const int32 DefaultValue)
		{
			int32 Value = DefaultValue;
			return (JsonObject.IsValid() && JsonObject->TryGetNumberField(FieldName, Value)) ? Value : DefaultValue;
		}

		static FVector2D GetVector2DArrayField(const TSharedPtr<FJsonObject>& JsonObject, const FString& FieldName, const FVector2D& DefaultValue)
		{
			const TArray<TSharedPtr<FJsonValue>>* Values = nullptr;
			if (!JsonObject.IsValid() || !JsonObject->TryGetArrayField(FieldName, Values) || Values == nullptr || Values->Num() < 2)
			{
				return DefaultValue;
			}

			return FVector2D((*Values)[0]->AsNumber(), (*Values)[1]->AsNumber());
		}

		static void SendJsonResponse(
			const TSharedPtr<IWebSocket>& Socket,
			const FString& RequestId,
			const FString& Status,
			const FString& PrinterClass,
			const FString& Filename,
			const bool bTextChunkWritten,
			const FString& Error
		)
		{
			if (!Socket.IsValid())
			{
				return;
			}

			const TSharedRef<FJsonObject> Response = MakeShared<FJsonObject>();
			Response->SetStringField(TEXT("RequestId"), RequestId);
			Response->SetStringField(TEXT("Status"), Status);
			Response->SetStringField(TEXT("PrinterClass"), PrinterClass);
			Response->SetStringField(TEXT("Filename"), Filename);
			Response->SetBoolField(TEXT("bTextChunkWritten"), bTextChunkWritten);
			Response->SetStringField(TEXT("Error"), Error);

			FString SerializedResponse;
			const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&SerializedResponse);
			FJsonSerializer::Serialize(Response, Writer);
			Socket->Send(SerializedResponse);
		}

		static void SendJsonObject(const TSharedPtr<IWebSocket>& Socket, const TSharedRef<FJsonObject>& Response)
		{
			if (!Socket.IsValid())
			{
				return;
			}

			FString SerializedResponse;
			const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&SerializedResponse);
			FJsonSerializer::Serialize(Response, Writer);
			Socket->Send(SerializedResponse);
		}
	}

	namespace GraphModules
	{
		struct FRequestOptions
		{
			FString RequestId;
			FString PackageName;
			FString OutputDirectory;
			FString SplitMode = TEXT("SemanticModules");
			int32 MaxModuleNodes = 40;
			FVector2D MaxModulePixels = FVector2D(6000.f, 6000.f);
			bool bRequireTextChunk = true;
		};

		struct FExternalEdgeSummary
		{
			int32 Incoming = 0;
			int32 Outgoing = 0;
			int32 LinkedNodeCount = 0;
		};

		struct FModuleRecovery
		{
			bool bAttempted = false;
			bool bRecovered = false;
			FString OriginalGraphName;
			FString OriginalGraphPath;
			FString ContainerGraphName;
			FString ContainerNodeClass;
			FString ContainerNodeTitle;
			FString FailureReason;
			FTextChunkDiagnostics OriginalDiagnostics;
			FTextChunkDiagnostics CandidateDiagnostics;
		};

		struct FModuleWorkItem
		{
			TWeakObjectPtr<UEdGraph> Graph;
			FString GraphName;
			FString ModuleId;
			FString ModuleTitle;
			FString FilenameBase;
			TArray<TWeakObjectPtr<UEdGraphNode>> NodesToPrint;
			int32 NodeCount = 0;
			FSlateRect Bounds;
			FExternalEdgeSummary ExternalEdges;
			FTextChunkDiagnostics Diagnostics;
			FModuleRecovery Recovery;
			bool bSkipPrintDueToTextChunkPreflight = false;
			FString PreflightFailureError;
		};

		struct FModuleResult
		{
			FString ModuleId;
			FString ModuleTitle;
			FString GraphName;
			int32 NodeCount = 0;
			FSlateRect Bounds;
			FExternalEdgeSummary ExternalEdges;
			FString Filename;
			bool bTextChunkWritten = false;
			FString Status;
			FString Error;
			FTextChunkDiagnostics Diagnostics;
			FModuleRecovery Recovery;
		};

		static FString SanitizeSlug(const FString& Source, const FString& Fallback)
		{
			FString Result;
			Result.Reserve(Source.Len());
			bool bPreviousWasSeparator = false;
			for (const TCHAR Character : Source)
			{
				const bool bAllowed =
					FChar::IsAlnum(Character) ||
					Character == TEXT('_') ||
					Character == TEXT('-');
				if (bAllowed)
				{
					Result.AppendChar(Character);
					bPreviousWasSeparator = false;
				}
				else if (!bPreviousWasSeparator)
				{
					Result.AppendChar(TEXT('_'));
					bPreviousWasSeparator = true;
				}
			}

			Result.TrimStartAndEndInline();
			while (Result.StartsWith(TEXT("_")))
			{
				Result.RightChopInline(1);
			}
			while (Result.EndsWith(TEXT("_")))
			{
				Result.LeftChopInline(1);
			}
			if (Result.IsEmpty())
			{
				Result = Fallback;
			}
			return Result.Left(120);
		}

		static FString GetNodeStableTitle(const UEdGraphNode* Node)
		{
			if (!IsValid(Node))
			{
				return TEXT("Node");
			}

			const FString Title = Node->GetNodeTitle(ENodeTitleType::ListView).ToString();
			return Title.IsEmpty() ? Node->GetName() : Title;
		}

		static void SortNodesByPath(TArray<UEdGraphNode*>& Nodes)
		{
			Algo::Sort(
				Nodes,
				[](const UEdGraphNode* Left, const UEdGraphNode* Right)
				{
					return GetPathNameSafe(Left) < GetPathNameSafe(Right);
				}
			);
		}

		static TArray<UEdGraphNode*> ResolveNodes(const TArray<TWeakObjectPtr<UEdGraphNode>>& WeakNodes)
		{
			TArray<UEdGraphNode*> Nodes;
			for (const TWeakObjectPtr<UEdGraphNode>& WeakNode : WeakNodes)
			{
				if (UEdGraphNode* Node = WeakNode.Get())
				{
					Nodes.Add(Node);
				}
			}
			SortNodesByPath(Nodes);
			return Nodes;
		}

		static FTextChunkDiagnostics BuildTextChunkDiagnostics(const UEdGraph* Graph, const TArray<UEdGraphNode*>& Nodes)
		{
			FTextChunkDiagnostics Diagnostics;
			if (IsValid(Graph))
			{
				Diagnostics.GraphClass = Graph->GetClass()->GetName();
				Diagnostics.GraphPath = Graph->GetPathName();
			}

			TArray<UEdGraphNode*> SortedNodes = Nodes;
			SortNodesByPath(SortedNodes);
			Diagnostics.NodeCount = SortedNodes.Num();

			FGraphPanelSelectionSet Selection;
			for (UEdGraphNode* Node : SortedNodes)
			{
				if (!IsValid(Node))
				{
					continue;
				}

				Diagnostics.NodeClasses.Add(GetNameSafe(Node->GetClass()));
				Diagnostics.NodeTitles.Add(GetNodeStableTitle(Node));
				if (IsValid(Graph) && Node->GetGraph() == Graph)
				{
					Selection.Add(Node);
				}
			}

			FString ExportedText;
			FEdGraphUtilities::ExportNodesToText(Selection, ExportedText);
			Diagnostics.ExportedTextLength = ExportedText.Len();
			Diagnostics.bExportedTextEmpty = ExportedText.IsEmpty();
			Diagnostics.bCanImportNodesFromText =
				IsValid(Graph) &&
				!ExportedText.IsEmpty() &&
				FEdGraphUtilities::CanImportNodesFromText(Graph, ExportedText);

			if (!IsValid(Graph))
			{
				Diagnostics.FailureStage = TEXT("InvalidGraph");
			}
			else if (ExportedText.IsEmpty())
			{
				Diagnostics.FailureStage = TEXT("ExportNodesToTextEmpty");
			}
			else if (!Diagnostics.bCanImportNodesFromText)
			{
				Diagnostics.FailureStage = TEXT("CanImportNodesFromTextFalse");
			}
			else
			{
				Diagnostics.FailureStage = TEXT("OK");
			}

			return Diagnostics;
		}

		static bool IsTextChunkPreflightOk(const FTextChunkDiagnostics& Diagnostics)
		{
			return
				Diagnostics.FailureStage == TEXT("OK") &&
				!Diagnostics.bExportedTextEmpty &&
				Diagnostics.bCanImportNodesFromText;
		}

		static bool IsCommentNode(const UEdGraphNode* Node)
		{
			return IsValid(Node) && Node->IsA<UEdGraphNode_Comment>();
		}

		static bool IsKnotNode(const UEdGraphNode* Node)
		{
			return IsValid(Node) && Node->IsA<UK2Node_Knot>();
		}

		static bool IsActualNode(const UEdGraphNode* Node)
		{
			return IsValid(Node) && !IsCommentNode(Node) && !IsKnotNode(Node);
		}

		static FSlateRect CalculateBounds(const TArray<UEdGraphNode*>& Nodes)
		{
			bool bHasAnyNode = false;
			float Left = 0.f;
			float Top = 0.f;
			float Right = 0.f;
			float Bottom = 0.f;

			for (const UEdGraphNode* Node : Nodes)
			{
				if (!IsValid(Node))
				{
					continue;
				}

				const float NodeLeft = static_cast<float>(Node->NodePosX);
				const float NodeTop = static_cast<float>(Node->NodePosY);
				const float NodeRight = NodeLeft + FMath::Max(1.f, static_cast<float>(Node->NodeWidth));
				const float NodeBottom = NodeTop + FMath::Max(1.f, static_cast<float>(Node->NodeHeight));
				if (!bHasAnyNode)
				{
					Left = NodeLeft;
					Top = NodeTop;
					Right = NodeRight;
					Bottom = NodeBottom;
					bHasAnyNode = true;
				}
				else
				{
					Left = FMath::Min(Left, NodeLeft);
					Top = FMath::Min(Top, NodeTop);
					Right = FMath::Max(Right, NodeRight);
					Bottom = FMath::Max(Bottom, NodeBottom);
				}
			}

			return bHasAnyNode ? FSlateRect(Left, Top, Right, Bottom) : FSlateRect();
		}

		static TArray<UEdGraphNode*> SetToSortedArray(const TSet<UEdGraphNode*>& Nodes)
		{
			TArray<UEdGraphNode*> SortedNodes = Nodes.Array();
			Algo::Sort(
				SortedNodes,
				[](const UEdGraphNode* Left, const UEdGraphNode* Right)
				{
					if (Left->NodePosX != Right->NodePosX)
					{
						return Left->NodePosX < Right->NodePosX;
					}
					if (Left->NodePosY != Right->NodePosY)
					{
						return Left->NodePosY < Right->NodePosY;
					}
					return Left->GetPathName() < Right->GetPathName();
				}
			);
			return SortedNodes;
		}

		static void AddConnectedKnotNodes(TSet<UEdGraphNode*>& Selection)
		{
			TArray<UEdGraphNode*> Queue = Selection.Array();
			for (int32 Index = 0; Index < Queue.Num(); ++Index)
			{
				UEdGraphNode* Node = Queue[Index];
				if (!IsValid(Node))
				{
					continue;
				}

				for (UEdGraphPin* Pin : Node->Pins)
				{
					if (Pin == nullptr)
					{
						continue;
					}
					for (UEdGraphPin* LinkedPin : Pin->LinkedTo)
					{
						UEdGraphNode* LinkedNode = (LinkedPin != nullptr) ? LinkedPin->GetOwningNode() : nullptr;
						if (IsKnotNode(LinkedNode) && LinkedNode->GetGraph() == Node->GetGraph() && !Selection.Contains(LinkedNode))
						{
							Selection.Add(LinkedNode);
							Queue.Add(LinkedNode);
						}
					}
				}
			}
		}

		static FExternalEdgeSummary BuildExternalEdgeSummary(const TSet<UEdGraphNode*>& Selection)
		{
			FExternalEdgeSummary Summary;
			TSet<UEdGraphNode*> LinkedExternalNodes;
			for (UEdGraphNode* Node : Selection)
			{
				if (!IsValid(Node))
				{
					continue;
				}

				for (UEdGraphPin* Pin : Node->Pins)
				{
					if (Pin == nullptr)
					{
						continue;
					}
					for (UEdGraphPin* LinkedPin : Pin->LinkedTo)
					{
						UEdGraphNode* LinkedNode = (LinkedPin != nullptr) ? LinkedPin->GetOwningNode() : nullptr;
						if (!IsValid(LinkedNode) || LinkedNode->GetGraph() != Node->GetGraph() || Selection.Contains(LinkedNode))
						{
							continue;
						}

						LinkedExternalNodes.Add(LinkedNode);
						if (Pin->Direction == EGPD_Input)
						{
							Summary.Incoming++;
						}
						else
						{
							Summary.Outgoing++;
						}
					}
				}
			}
			Summary.LinkedNodeCount = LinkedExternalNodes.Num();
			return Summary;
		}

		static bool IsTooLarge(const TArray<UEdGraphNode*>& ActualNodes, const TSet<UEdGraphNode*>& Selection, const FRequestOptions& Options)
		{
			if (Options.MaxModuleNodes > 0 && ActualNodes.Num() > Options.MaxModuleNodes)
			{
				return true;
			}

			const TArray<UEdGraphNode*> SelectionNodes = SetToSortedArray(Selection);
			const FSlateRect Bounds = CalculateBounds(SelectionNodes);
			const FVector2D Size = Bounds.GetSize();
			return
				Options.MaxModulePixels.X > 0.f &&
				Options.MaxModulePixels.Y > 0.f &&
				(Size.X > Options.MaxModulePixels.X || Size.Y > Options.MaxModulePixels.Y);
		}

		struct FModuleSeed
		{
			FString Title;
			TArray<UEdGraphNode*> ActualNodes;
			TArray<UEdGraphNode*> AnchorNodes;
		};

		class FModuleBuilder
		{
		public:
			FModuleBuilder(
				const FRequestOptions& InOptions,
				const FString& InAssetSlug,
				TArray<FModuleWorkItem>& InOutWorkItems
			)
				: Options(InOptions)
				, AssetSlug(InAssetSlug)
				, WorkItems(InOutWorkItems)
			{
			}

			void AppendSeed(UEdGraph* Graph, const FString& GraphSlug, const FModuleSeed& Seed)
			{
				TArray<UEdGraphNode*> ActualNodes = Seed.ActualNodes;
				SortNodes(ActualNodes, true);
				SplitAndAppend(Graph, GraphSlug, Seed.Title, Seed.AnchorNodes, ActualNodes);
			}

		private:
			void SplitAndAppend(
				UEdGraph* Graph,
				const FString& GraphSlug,
				const FString& Title,
				const TArray<UEdGraphNode*>& AnchorNodes,
				TArray<UEdGraphNode*> ActualNodes
			)
			{
				if (!IsValid(Graph) || ActualNodes.Num() == 0)
				{
					return;
				}

				TSet<UEdGraphNode*> Selection;
				for (UEdGraphNode* Node : ActualNodes)
				{
					if (IsValid(Node) && Node->GetGraph() == Graph)
					{
						Selection.Add(Node);
					}
				}
				for (UEdGraphNode* Node : AnchorNodes)
				{
					if (IsValid(Node) && Node->GetGraph() == Graph)
					{
						Selection.Add(Node);
					}
				}
				AddConnectedKnotNodes(Selection);

				if (ActualNodes.Num() > 1 && IsTooLarge(ActualNodes, Selection, Options))
				{
					const FSlateRect Bounds = CalculateBounds(ActualNodes);
					const bool bSplitByX = Bounds.GetSize().X >= Bounds.GetSize().Y;
					SortNodes(ActualNodes, bSplitByX);

					const int32 Midpoint = FMath::Clamp(ActualNodes.Num() / 2, 1, ActualNodes.Num() - 1);
					TArray<UEdGraphNode*> Left;
					TArray<UEdGraphNode*> Right;
					for (int32 Index = 0; Index < ActualNodes.Num(); ++Index)
					{
						(Index < Midpoint ? Left : Right).Add(ActualNodes[Index]);
					}
					SplitAndAppend(Graph, GraphSlug, Title, AnchorNodes, Left);
					SplitAndAppend(Graph, GraphSlug, Title, AnchorNodes, Right);
					return;
				}

				AppendModule(Graph, GraphSlug, Title, ActualNodes, Selection);
			}

			void AppendModule(
				UEdGraph* Graph,
				const FString& GraphSlug,
				const FString& Title,
				const TArray<UEdGraphNode*>& ActualNodes,
				const TSet<UEdGraphNode*>& Selection
			)
			{
				const int32 ModuleNumber = ++ModuleCounterByGraph.FindOrAdd(Graph);
				const FString TitleSlug = SanitizeSlug(Title, TEXT("module"));
				const FString ModuleId = FString::Printf(TEXT("%s_M%03d"), *GraphSlug, ModuleNumber);

				FModuleWorkItem Item;
				Item.Graph = Graph;
				Item.GraphName = Graph->GetName();
				Item.ModuleId = ModuleId;
				Item.ModuleTitle = Title;
				Item.FilenameBase = FString::Printf(TEXT("%s_%s_M%03d_%s"), *AssetSlug, *GraphSlug, ModuleNumber, *TitleSlug);
				Item.NodeCount = ActualNodes.Num();
				Item.ExternalEdges = BuildExternalEdgeSummary(Selection);

				const TArray<UEdGraphNode*> SelectionNodes = SetToSortedArray(Selection);
				Item.Bounds = CalculateBounds(SelectionNodes);
				for (UEdGraphNode* Node : SelectionNodes)
				{
					Item.NodesToPrint.Add(Node);
				}
				WorkItems.Add(Item);
			}

			static void SortNodes(TArray<UEdGraphNode*>& Nodes, const bool bByX)
			{
				Algo::Sort(
					Nodes,
					[bByX](const UEdGraphNode* Left, const UEdGraphNode* Right)
					{
						const int32 LeftPrimary = bByX ? Left->NodePosX : Left->NodePosY;
						const int32 RightPrimary = bByX ? Right->NodePosX : Right->NodePosY;
						if (LeftPrimary != RightPrimary)
						{
							return LeftPrimary < RightPrimary;
						}

						const int32 LeftSecondary = bByX ? Left->NodePosY : Left->NodePosX;
						const int32 RightSecondary = bByX ? Right->NodePosY : Right->NodePosX;
						if (LeftSecondary != RightSecondary)
						{
							return LeftSecondary < RightSecondary;
						}

						return Left->GetPathName() < Right->GetPathName();
					}
				);
			}

		private:
			const FRequestOptions& Options;
			FString AssetSlug;
			TArray<FModuleWorkItem>& WorkItems;
			TMap<TWeakObjectPtr<UEdGraph>, int32> ModuleCounterByGraph;
		};

		static TSharedRef<FJsonObject> BoundsToJson(const FSlateRect& Bounds)
		{
			const TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
			Object->SetNumberField(TEXT("Left"), Bounds.Left);
			Object->SetNumberField(TEXT("Top"), Bounds.Top);
			Object->SetNumberField(TEXT("Right"), Bounds.Right);
			Object->SetNumberField(TEXT("Bottom"), Bounds.Bottom);
			Object->SetNumberField(TEXT("Width"), Bounds.GetSize().X);
			Object->SetNumberField(TEXT("Height"), Bounds.GetSize().Y);
			return Object;
		}

		static TSharedRef<FJsonObject> ExternalEdgesToJson(const FExternalEdgeSummary& ExternalEdges)
		{
			const TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
			Object->SetNumberField(TEXT("Incoming"), ExternalEdges.Incoming);
			Object->SetNumberField(TEXT("Outgoing"), ExternalEdges.Outgoing);
			Object->SetNumberField(TEXT("LinkedNodeCount"), ExternalEdges.LinkedNodeCount);
			return Object;
		}

		static TArray<TSharedPtr<FJsonValue>> StringArrayToJsonValues(const TArray<FString>& Values)
		{
			TArray<TSharedPtr<FJsonValue>> JsonValues;
			for (const FString& Value : Values)
			{
				JsonValues.Add(MakeShared<FJsonValueString>(Value));
			}
			return JsonValues;
		}

		static TSharedRef<FJsonObject> DiagnosticsToJson(const FTextChunkDiagnostics& Diagnostics)
		{
			const TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
			Object->SetStringField(TEXT("GraphClass"), Diagnostics.GraphClass);
			Object->SetStringField(TEXT("GraphPath"), Diagnostics.GraphPath);
			Object->SetArrayField(TEXT("NodeClasses"), StringArrayToJsonValues(Diagnostics.NodeClasses));
			Object->SetArrayField(TEXT("NodeTitles"), StringArrayToJsonValues(Diagnostics.NodeTitles));
			Object->SetNumberField(TEXT("NodeCount"), Diagnostics.NodeCount);
			Object->SetNumberField(TEXT("ExportedTextLength"), Diagnostics.ExportedTextLength);
			Object->SetBoolField(TEXT("bExportedTextEmpty"), Diagnostics.bExportedTextEmpty);
			Object->SetBoolField(TEXT("bCanImportNodesFromText"), Diagnostics.bCanImportNodesFromText);
			Object->SetStringField(TEXT("FailureStage"), Diagnostics.FailureStage);
			return Object;
		}

		static TSharedRef<FJsonObject> RecoveryToJson(const FModuleRecovery& Recovery)
		{
			const TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
			Object->SetBoolField(TEXT("bAttempted"), Recovery.bAttempted);
			Object->SetBoolField(TEXT("bRecovered"), Recovery.bRecovered);
			Object->SetStringField(TEXT("OriginalGraphName"), Recovery.OriginalGraphName);
			Object->SetStringField(TEXT("OriginalGraphPath"), Recovery.OriginalGraphPath);
			Object->SetStringField(TEXT("ContainerGraphName"), Recovery.ContainerGraphName);
			Object->SetStringField(TEXT("ContainerNodeClass"), Recovery.ContainerNodeClass);
			Object->SetStringField(TEXT("ContainerNodeTitle"), Recovery.ContainerNodeTitle);
			Object->SetStringField(TEXT("FailureReason"), Recovery.FailureReason);
			Object->SetObjectField(TEXT("OriginalDiagnostics"), DiagnosticsToJson(Recovery.OriginalDiagnostics));
			Object->SetObjectField(TEXT("CandidateDiagnostics"), DiagnosticsToJson(Recovery.CandidateDiagnostics));
			return Object;
		}

		static TSharedRef<FJsonObject> ModuleResultToJson(const FModuleResult& Result)
		{
			const TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
			Object->SetStringField(TEXT("ModuleId"), Result.ModuleId);
			Object->SetStringField(TEXT("ModuleTitle"), Result.ModuleTitle);
			Object->SetStringField(TEXT("GraphName"), Result.GraphName);
			Object->SetNumberField(TEXT("NodeCount"), Result.NodeCount);
			Object->SetObjectField(TEXT("Bounds"), BoundsToJson(Result.Bounds));
			Object->SetObjectField(TEXT("ExternalEdges"), ExternalEdgesToJson(Result.ExternalEdges));
			Object->SetStringField(TEXT("Filename"), Result.Filename);
			Object->SetBoolField(TEXT("bTextChunkWritten"), Result.bTextChunkWritten);
			Object->SetStringField(TEXT("Status"), Result.Status);
			Object->SetStringField(TEXT("Error"), Result.Error);
			Object->SetObjectField(TEXT("Diagnostics"), DiagnosticsToJson(Result.Diagnostics));
			if (Result.Recovery.bAttempted || Result.Recovery.bRecovered)
			{
				Object->SetObjectField(TEXT("Recovery"), RecoveryToJson(Result.Recovery));
			}
			return Object;
		}

		static void AddSkippedGraphResult(TArray<FModuleResult>& Results, const UEdGraph* Graph, const FString& Error)
		{
			FModuleResult Result;
			Result.ModuleId = IsValid(Graph) ? FString::Printf(TEXT("%s_SKIP"), *SanitizeSlug(Graph->GetName(), TEXT("graph"))) : TEXT("SKIP_NO_GRAPH");
			Result.ModuleTitle = TEXT("SKIP_NO_GRAPH");
			Result.GraphName = IsValid(Graph) ? Graph->GetName() : TEXT("");
			Result.Status = TEXT("SKIP_NO_GRAPH");
			Result.Error = Error;
			if (IsValid(Graph))
			{
				Result.Diagnostics.GraphClass = Graph->GetClass()->GetName();
				Result.Diagnostics.GraphPath = Graph->GetPathName();
			}
			Result.Diagnostics.FailureStage = TEXT("SKIP_NO_GRAPH");
			Results.Add(Result);
		}

		static TArray<UEdGraphNode*> GetCommentContainedNodes(UEdGraph* Graph, UEdGraphNode_Comment* Comment)
		{
			TArray<UEdGraphNode*> ContainedNodes;
			if (!IsValid(Graph) || !IsValid(Comment))
			{
				return ContainedNodes;
			}

			for (UObject* Object : Comment->GetNodesUnderComment())
			{
				UEdGraphNode* Node = Cast<UEdGraphNode>(Object);
				if (IsActualNode(Node) && Node->GetGraph() == Graph)
				{
					ContainedNodes.AddUnique(Node);
				}
			}

			if (ContainedNodes.Num() > 0)
			{
				return ContainedNodes;
			}

			const int32 Left = Comment->NodePosX;
			const int32 Top = Comment->NodePosY;
			const int32 Right = Left + Comment->NodeWidth;
			const int32 Bottom = Top + Comment->NodeHeight;
			for (UEdGraphNode* Node : Graph->Nodes)
			{
				if (!IsActualNode(Node))
				{
					continue;
				}
				if (Node->NodePosX >= Left && Node->NodePosX <= Right && Node->NodePosY >= Top && Node->NodePosY <= Bottom)
				{
					ContainedNodes.AddUnique(Node);
				}
			}
			return ContainedNodes;
		}

		static void BuildGraphModules(
			UEdGraph* Graph,
			const FString& AssetSlug,
			const FRequestOptions& Options,
			TArray<FModuleWorkItem>& WorkItems,
			TArray<FModuleResult>& Results
		)
		{
			if (!IsValid(Graph))
			{
				AddSkippedGraphResult(Results, Graph, TEXT("SKIP_NO_GRAPH: invalid graph."));
				return;
			}

			TArray<UEdGraphNode*> ActualNodes;
			TArray<UEdGraphNode_Comment*> Comments;
			for (UEdGraphNode* Node : Graph->Nodes)
			{
				if (IsActualNode(Node))
				{
					ActualNodes.Add(Node);
				}
				else if (UEdGraphNode_Comment* Comment = Cast<UEdGraphNode_Comment>(Node))
				{
					Comments.Add(Comment);
				}
			}

			if (ActualNodes.Num() == 0)
			{
				AddSkippedGraphResult(Results, Graph, TEXT("SKIP_NO_GRAPH: graph has no printable nodes."));
				return;
			}

			Algo::Sort(
				Comments,
				[](const UEdGraphNode_Comment* Left, const UEdGraphNode_Comment* Right)
				{
					if (Left->NodePosY != Right->NodePosY)
					{
						return Left->NodePosY < Right->NodePosY;
					}
					if (Left->NodePosX != Right->NodePosX)
					{
						return Left->NodePosX < Right->NodePosX;
					}
					return Left->GetPathName() < Right->GetPathName();
				}
			);

			const FString GraphSlug = SanitizeSlug(Graph->GetName(), TEXT("Graph"));
			FModuleBuilder ModuleBuilder(Options, AssetSlug, WorkItems);
			TSet<UEdGraphNode*> NodesCoveredByComments;

			for (UEdGraphNode_Comment* Comment : Comments)
			{
				TArray<UEdGraphNode*> ContainedNodes = GetCommentContainedNodes(Graph, Comment);
				if (ContainedNodes.Num() == 0)
				{
					continue;
				}

				for (UEdGraphNode* Node : ContainedNodes)
				{
					NodesCoveredByComments.Add(Node);
				}

				FModuleSeed Seed;
				Seed.Title = GetNodeStableTitle(Comment);
				Seed.ActualNodes = ContainedNodes;
				Seed.AnchorNodes.Add(Comment);
				ModuleBuilder.AppendSeed(Graph, GraphSlug, Seed);
			}

			TSet<UEdGraphNode*> UncoveredActualNodes;
			for (UEdGraphNode* Node : ActualNodes)
			{
				if (!NodesCoveredByComments.Contains(Node))
				{
					UncoveredActualNodes.Add(Node);
				}
			}

			TSet<UEdGraphNode*> VisitedNodes;
			TArray<UEdGraphNode*> SortedUncoveredNodes = SetToSortedArray(UncoveredActualNodes);
			int32 FallbackIndex = 0;
			for (UEdGraphNode* StartNode : SortedUncoveredNodes)
			{
				if (!IsValid(StartNode) || VisitedNodes.Contains(StartNode))
				{
					continue;
				}

				TArray<UEdGraphNode*> Queue;
				TArray<UEdGraphNode*> ComponentActualNodes;
				Queue.Add(StartNode);
				VisitedNodes.Add(StartNode);

				for (int32 QueueIndex = 0; QueueIndex < Queue.Num(); ++QueueIndex)
				{
					UEdGraphNode* Node = Queue[QueueIndex];
					if (!IsValid(Node))
					{
						continue;
					}
					if (IsActualNode(Node))
					{
						ComponentActualNodes.AddUnique(Node);
					}

					for (UEdGraphPin* Pin : Node->Pins)
					{
						if (Pin == nullptr)
						{
							continue;
						}
						for (UEdGraphPin* LinkedPin : Pin->LinkedTo)
						{
							UEdGraphNode* LinkedNode = (LinkedPin != nullptr) ? LinkedPin->GetOwningNode() : nullptr;
							if (!IsValid(LinkedNode) || LinkedNode->GetGraph() != Graph || IsCommentNode(LinkedNode))
							{
								continue;
							}
							if (IsActualNode(LinkedNode) && !UncoveredActualNodes.Contains(LinkedNode))
							{
								continue;
							}
							if (!VisitedNodes.Contains(LinkedNode))
							{
								VisitedNodes.Add(LinkedNode);
								Queue.Add(LinkedNode);
							}
						}
					}
				}

				if (ComponentActualNodes.Num() > 0)
				{
					FModuleSeed Seed;
					Seed.Title = FString::Printf(TEXT("Fallback_%03d"), ++FallbackIndex);
					Seed.ActualNodes = ComponentActualNodes;
					ModuleBuilder.AppendSeed(Graph, GraphSlug, Seed);
				}
			}
		}

		static bool NodeReferencesGraph(const UEdGraphNode* Node, const UEdGraph* TargetGraph)
		{
			if (!IsValid(Node) || !IsValid(TargetGraph))
			{
				return false;
			}

			for (TFieldIterator<FProperty> PropertyIt(Node->GetClass()); PropertyIt; ++PropertyIt)
			{
				const FProperty* Property = *PropertyIt;
				if (const FObjectPropertyBase* ObjectProperty = CastField<FObjectPropertyBase>(Property))
				{
					if (ObjectProperty->PropertyClass->IsChildOf(UEdGraph::StaticClass()))
					{
						if (ObjectProperty->GetObjectPropertyValue_InContainer(Node) == TargetGraph)
						{
							return true;
						}
					}
				}
				else if (const FArrayProperty* ArrayProperty = CastField<FArrayProperty>(Property))
				{
					const FObjectPropertyBase* InnerObjectProperty = CastField<FObjectPropertyBase>(ArrayProperty->Inner);
					if (InnerObjectProperty == nullptr || !InnerObjectProperty->PropertyClass->IsChildOf(UEdGraph::StaticClass()))
					{
						continue;
					}

					FScriptArrayHelper ArrayHelper(ArrayProperty, ArrayProperty->ContainerPtrToValuePtr<void>(Node));
					for (int32 Index = 0; Index < ArrayHelper.Num(); ++Index)
					{
						if (InnerObjectProperty->GetObjectPropertyValue(ArrayHelper.GetRawPtr(Index)) == TargetGraph)
						{
							return true;
						}
					}
				}
			}

			return false;
		}

		static UEdGraphNode* FindOuterContainerNode(const UEdGraph* TargetGraph)
		{
			if (!IsValid(TargetGraph))
			{
				return nullptr;
			}

			for (UObject* Outer = TargetGraph->GetOuter(); IsValid(Outer); Outer = Outer->GetOuter())
			{
				if (UEdGraphNode* Node = Cast<UEdGraphNode>(Outer))
				{
					if (IsValid(Node->GetGraph()) && Node->GetGraph() != TargetGraph)
					{
						return Node;
					}
				}
			}

			return nullptr;
		}

		static UEdGraphNode* FindContainerNodeForGraph(const UBlueprint* Blueprint, const UEdGraph* TargetGraph)
		{
			if (!IsValid(TargetGraph))
			{
				return nullptr;
			}

			if (UEdGraphNode* OuterNode = FindOuterContainerNode(TargetGraph))
			{
				return OuterNode;
			}

			if (!IsValid(Blueprint))
			{
				return nullptr;
			}

			TArray<UEdGraph*> AllGraphs;
			Blueprint->GetAllGraphs(AllGraphs);
			for (UEdGraph* Graph : AllGraphs)
			{
				if (!IsValid(Graph) || Graph == TargetGraph)
				{
					continue;
				}

				for (UEdGraphNode* Node : Graph->Nodes)
				{
					if (IsValid(Node) && NodeReferencesGraph(Node, TargetGraph))
					{
						return Node;
					}
				}
			}

			return nullptr;
		}

		static UObject* LoadAssetFromPackageName(const FString& PackageName)
		{
			if (PackageName.IsEmpty())
			{
				return nullptr;
			}

			FString ObjectPath = PackageName;
			if (!ObjectPath.Contains(TEXT(".")))
			{
				ObjectPath = FString::Printf(TEXT("%s.%s"), *PackageName, *FPackageName::GetShortName(PackageName));
			}
			return StaticLoadObject(UObject::StaticClass(), nullptr, *ObjectPath);
		}

		static TSharedPtr<SGraphEditorImpl> FindVisibleGraphEditorForGraph(const UEdGraph* TargetGraph)
		{
			if (!IsValid(TargetGraph) || !FSlateApplication::IsInitialized())
			{
				return nullptr;
			}

			TArray<TSharedRef<SWindow>> Windows;
			FSlateApplication::Get().GetAllVisibleWindowsOrdered(Windows);
			for (const TSharedRef<SWindow>& Window : Windows)
			{
				TSharedPtr<SGraphEditorImpl> FoundGraphEditor;
				FWidgetPrinterUtils::EnumerateChildWidgets(
					Window,
					[TargetGraph, &FoundGraphEditor](const TSharedPtr<SWidget> ChildWidget) -> bool
					{
						const TSharedPtr<SGraphEditorImpl> GraphEditor = FGenericGraphPrinterUtils::FindNearestChildGraphEditor(ChildWidget);
						if (GraphEditor.IsValid() && GraphEditor->GetCurrentGraph() == TargetGraph)
						{
							FoundGraphEditor = GraphEditor;
							return false;
						}
						return true;
					}
				);
				if (FoundGraphEditor.IsValid())
				{
					return FoundGraphEditor;
				}
			}

			return nullptr;
		}

		static int32 GetGraphSortRank(const UBlueprint* Blueprint, const UEdGraph* Graph)
		{
			if (!IsValid(Blueprint) || !IsValid(Graph))
			{
				return 100;
			}

			if (Blueprint->UbergraphPages.Contains(Graph))
			{
				return Graph->GetName().Equals(TEXT("EventGraph"), ESearchCase::IgnoreCase) ? 0 : 1;
			}
			if (FBlueprintEditorUtils::FindUserConstructionScript(Blueprint) == Graph)
			{
				return 2;
			}
			if (Blueprint->FunctionGraphs.Contains(Graph))
			{
				return 3;
			}
			if (Blueprint->MacroGraphs.Contains(Graph))
			{
				return 4;
			}
			if (Graph->GetName().Contains(TEXT("Anim"), ESearchCase::IgnoreCase))
			{
				return 5;
			}
			return 10;
		}
	}

	class FPrintGraphModulesJob : public TSharedFromThis<FPrintGraphModulesJob>
	{
	public:
		DECLARE_DELEGATE(FOnFinished);

		FPrintGraphModulesJob(
			const GraphModules::FRequestOptions& InOptions,
			const TWeakPtr<IWebSocket>& InSocket,
			const FOnFinished& InOnFinished
		)
			: Options(InOptions)
			, WeakSocket(InSocket)
			, OnFinished(InOnFinished)
		{
		}

		void Start()
		{
			if (!Prepare())
			{
				Finish();
				return;
			}

			TickerHandle = FTSTicker::GetCoreTicker().AddTicker(
				FTickerDelegate::CreateSP(AsShared(), &FPrintGraphModulesJob::Tick),
				0.f
			);
		}

	private:
		enum class EState : uint8
		{
			OpenGraph,
			WaitGraph,
			PrintModule,
			WaitPrint,
			Complete
		};

		bool Prepare()
		{
			UObject* LoadedObject = nullptr;
			if (!Options.PackageName.IsEmpty())
			{
				LoadedObject = GraphModules::LoadAssetFromPackageName(Options.PackageName);
				Blueprint = Cast<UBlueprint>(LoadedObject);
				if (!Blueprint.IsValid())
				{
					AppendFailure(TEXT("Failed to load a Blueprint asset from PackageName."), TEXT(""));
					return false;
				}
				AssetName = Blueprint->GetName();
				BuildWorkItemsFromBlueprint();
			}
			else
			{
				const TSharedPtr<SGraphEditorImpl> ActiveGraphEditor = FGenericGraphPrinterUtils::GetActiveGraphEditor();
				UEdGraph* CurrentActiveGraph = ActiveGraphEditor.IsValid() ? ActiveGraphEditor->GetCurrentGraph() : nullptr;
				if (!IsValid(CurrentActiveGraph))
				{
					GraphModules::AddSkippedGraphResult(Results, nullptr, TEXT("SKIP_NO_GRAPH: no active graph editor."));
					return false;
				}

				Blueprint = FBlueprintEditorUtils::FindBlueprintForGraph(CurrentActiveGraph);
				AssetName = Blueprint.IsValid() ? Blueprint->GetName() : CurrentActiveGraph->GetOuter()->GetName();
				const FString AssetSlug = GraphModules::SanitizeSlug(AssetName, TEXT("Asset"));
				GraphsToOpen.Add(CurrentActiveGraph);
				GraphModules::BuildGraphModules(CurrentActiveGraph, AssetSlug, Options, WorkItems, Results);
			}

			if (WorkItems.Num() == 0)
			{
				if (Results.Num() == 0)
				{
					GraphModules::AddSkippedGraphResult(Results, nullptr, TEXT("SKIP_NO_GRAPH: blueprint has no printable graphs."));
				}
				return false;
			}

			PrepareTextChunkPreflightAndRecovery();
			DisambiguateWorkItems();
			State = EState::OpenGraph;
			return true;
		}

		void BuildWorkItemsFromBlueprint()
		{
			TArray<UEdGraph*> AllGraphs;
			Blueprint->GetAllGraphs(AllGraphs);

			TSet<UEdGraph*> UniqueGraphs;
			for (UEdGraph* Graph : AllGraphs)
			{
				if (IsValid(Graph))
				{
					UniqueGraphs.Add(Graph);
				}
			}

			GraphsToOpen = UniqueGraphs.Array();
			Algo::Sort(
				GraphsToOpen,
				[this](const UEdGraph* Left, const UEdGraph* Right)
				{
					const int32 LeftRank = GraphModules::GetGraphSortRank(Blueprint.Get(), Left);
					const int32 RightRank = GraphModules::GetGraphSortRank(Blueprint.Get(), Right);
					if (LeftRank != RightRank)
					{
						return LeftRank < RightRank;
					}
					return Left->GetPathName() < Right->GetPathName();
				}
			);

			const FString AssetSlug = GraphModules::SanitizeSlug(AssetName, TEXT("Asset"));
			for (UEdGraph* Graph : GraphsToOpen)
			{
				GraphModules::BuildGraphModules(Graph, AssetSlug, Options, WorkItems, Results);
			}
		}

		void PrepareTextChunkPreflightAndRecovery()
		{
			if (!Options.bRequireTextChunk)
			{
				return;
			}

			for (GraphModules::FModuleWorkItem& WorkItem : WorkItems)
			{
				UEdGraph* OriginalGraph = WorkItem.Graph.Get();
				TArray<UEdGraphNode*> OriginalNodes = GraphModules::ResolveNodes(WorkItem.NodesToPrint);
				WorkItem.Diagnostics = GraphModules::BuildTextChunkDiagnostics(OriginalGraph, OriginalNodes);
				if (GraphModules::IsTextChunkPreflightOk(WorkItem.Diagnostics))
				{
					continue;
				}

				WorkItem.PreflightFailureError = WorkItem.Diagnostics.FailureStage;
				if (WorkItem.NodeCount != 1)
				{
					WorkItem.bSkipPrintDueToTextChunkPreflight = true;
					continue;
				}

				WorkItem.Recovery.bAttempted = true;
				WorkItem.Recovery.OriginalGraphName = WorkItem.GraphName;
				WorkItem.Recovery.OriginalGraphPath = IsValid(OriginalGraph) ? OriginalGraph->GetPathName() : FString();
				WorkItem.Recovery.OriginalDiagnostics = WorkItem.Diagnostics;

				UEdGraphNode* ContainerNode = GraphModules::FindContainerNodeForGraph(Blueprint.Get(), OriginalGraph);
				UEdGraph* ContainerGraph = IsValid(ContainerNode) ? ContainerNode->GetGraph() : nullptr;
				if (!IsValid(ContainerNode) || !IsValid(ContainerGraph))
				{
					WorkItem.Recovery.FailureReason = TEXT("NoRecoverableContainerNode");
					WorkItem.PreflightFailureError = WorkItem.Recovery.FailureReason;
					WorkItem.bSkipPrintDueToTextChunkPreflight = true;
					continue;
				}

				TArray<UEdGraphNode*> CandidateNodes;
				CandidateNodes.Add(ContainerNode);
				WorkItem.Recovery.CandidateDiagnostics = GraphModules::BuildTextChunkDiagnostics(ContainerGraph, CandidateNodes);
				WorkItem.Recovery.ContainerGraphName = ContainerGraph->GetName();
				WorkItem.Recovery.ContainerNodeClass = GetNameSafe(ContainerNode->GetClass());
				WorkItem.Recovery.ContainerNodeTitle = GraphModules::GetNodeStableTitle(ContainerNode);

				if (!GraphModules::IsTextChunkPreflightOk(WorkItem.Recovery.CandidateDiagnostics))
				{
					WorkItem.Recovery.FailureReason = WorkItem.Recovery.CandidateDiagnostics.FailureStage;
					WorkItem.PreflightFailureError = WorkItem.Recovery.FailureReason;
					WorkItem.bSkipPrintDueToTextChunkPreflight = true;
					continue;
				}

				WorkItem.Graph = ContainerGraph;
				WorkItem.NodesToPrint.Reset();
				WorkItem.NodesToPrint.Add(ContainerNode);
				WorkItem.NodeCount = 1;
				WorkItem.Bounds = GraphModules::CalculateBounds(CandidateNodes);
				TSet<UEdGraphNode*> CandidateSelection;
				CandidateSelection.Add(ContainerNode);
				WorkItem.ExternalEdges = GraphModules::BuildExternalEdgeSummary(CandidateSelection);
				WorkItem.Diagnostics = WorkItem.Recovery.CandidateDiagnostics;
				WorkItem.Recovery.bRecovered = true;
				WorkItem.Recovery.FailureReason = TEXT("");
				WorkItem.bSkipPrintDueToTextChunkPreflight = false;
				WorkItem.PreflightFailureError = TEXT("");
			}
		}

		void DisambiguateWorkItems()
		{
			TSet<FString> UsedModuleIds;
			TSet<FString> UsedFilenameBases;
			for (GraphModules::FModuleWorkItem& WorkItem : WorkItems)
			{
				const FString BaseModuleId = WorkItem.ModuleId;
				const FString BaseFilename = WorkItem.FilenameBase;
				int32 Suffix = 1;
				while (UsedModuleIds.Contains(WorkItem.ModuleId) || UsedFilenameBases.Contains(WorkItem.FilenameBase))
				{
					WorkItem.ModuleId = FString::Printf(TEXT("%s_D%03d"), *BaseModuleId, Suffix);
					WorkItem.FilenameBase = FString::Printf(TEXT("%s_D%03d"), *BaseFilename, Suffix);
					Suffix++;
				}
				UsedModuleIds.Add(WorkItem.ModuleId);
				UsedFilenameBases.Add(WorkItem.FilenameBase);
			}
		}

		bool Tick(float)
		{
			switch (State)
			{
			case EState::OpenGraph:
				OpenCurrentGraph();
				return true;

			case EState::WaitGraph:
				WaitForCurrentGraph();
				return true;

			case EState::PrintModule:
				PrintCurrentModule();
				return true;

			case EState::WaitPrint:
				return true;

			case EState::Complete:
				Finish();
				return false;

			default:
				return false;
			}
		}

		void OpenCurrentGraph()
		{
			if (!WorkItems.IsValidIndex(CurrentWorkIndex))
			{
				State = EState::Complete;
				return;
			}

			const GraphModules::FModuleWorkItem& WorkItem = WorkItems[CurrentWorkIndex];
			if (WorkItem.bSkipPrintDueToTextChunkPreflight)
			{
				AppendResult(WorkItem, TEXT("FAIL"), TEXT(""), false, WorkItem.PreflightFailureError);
				CurrentWorkIndex++;
				State = EState::OpenGraph;
				return;
			}

			UEdGraph* TargetGraph = WorkItem.Graph.Get();
			if (!IsValid(TargetGraph))
			{
				AppendResult(WorkItem, TEXT("FAIL"), TEXT(""), false, TEXT("Target graph was destroyed or unloaded."));
				CurrentWorkIndex++;
				return;
			}

			if (ActiveGraph.Get() == TargetGraph)
			{
				State = EState::PrintModule;
				return;
			}

			if (Blueprint.IsValid())
			{
				BlueprintEditor = FKismetEditorUtilities::GetIBlueprintEditorForObject(Blueprint.Get(), true);
				if (!BlueprintEditor.IsValid())
				{
					AppendResult(WorkItems[CurrentWorkIndex], TEXT("FAIL"), TEXT(""), false, TEXT("Failed to open Blueprint editor."));
					CurrentWorkIndex++;
					return;
				}
				BlueprintEditor->OpenGraphAndBringToFront(TargetGraph, true);
			}

			WaitGraphTicks = 0;
			State = EState::WaitGraph;
		}

		void WaitForCurrentGraph()
		{
			UEdGraph* TargetGraph = WorkItems.IsValidIndex(CurrentWorkIndex) ? WorkItems[CurrentWorkIndex].Graph.Get() : nullptr;
			const TSharedPtr<SGraphEditorImpl> ActiveGraphEditor = FGenericGraphPrinterUtils::GetActiveGraphEditor();
			if (ActiveGraphEditor.IsValid() && ActiveGraphEditor->GetCurrentGraph() == TargetGraph)
			{
				ActiveGraph = TargetGraph;
				ActiveGraphEditorWidget = ActiveGraphEditor;
				State = EState::PrintModule;
				return;
			}

			const TSharedPtr<SGraphEditorImpl> VisibleGraphEditor = GraphModules::FindVisibleGraphEditorForGraph(TargetGraph);
			if (VisibleGraphEditor.IsValid())
			{
				ActiveGraph = TargetGraph;
				ActiveGraphEditorWidget = VisibleGraphEditor;
				State = EState::PrintModule;
				return;
			}

			WaitGraphTicks++;
			if (WaitGraphTicks > 600)
			{
				AppendResult(WorkItems[CurrentWorkIndex], TEXT("SKIP_NO_GRAPH"), TEXT(""), false, TEXT("SKIP_NO_GRAPH: timed out waiting for target graph editor."));
				CurrentWorkIndex++;
				State = EState::OpenGraph;
			}
		}

		void PrintCurrentModule()
		{
			if (!WorkItems.IsValidIndex(CurrentWorkIndex))
			{
				State = EState::Complete;
				return;
			}

			const GraphModules::FModuleWorkItem& WorkItem = WorkItems[CurrentWorkIndex];
			if (WorkItem.bSkipPrintDueToTextChunkPreflight)
			{
				AppendResult(WorkItem, TEXT("FAIL"), TEXT(""), false, WorkItem.PreflightFailureError);
				CurrentWorkIndex++;
				State = EState::OpenGraph;
				return;
			}

			UWidgetPrinter* WidgetPrinter = NewObject<UGenericGraphPrinter>(GetTransientPackage(), UGenericGraphPrinter::StaticClass());
			if (!IsValid(WidgetPrinter))
			{
				AppendResult(WorkItem, TEXT("FAIL"), TEXT(""), false, TEXT("Failed to create GenericGraphPrinter."));
				CurrentWorkIndex++;
				State = EState::OpenGraph;
				return;
			}

			auto* PrintOptions = Cast<UPrintGraphOptions>(WidgetPrinter->CreateDefaultPrintOptions(
				UPrintWidgetOptions::EPrintScope::Selected,
				UPrintWidgetOptions::EExportMethod::ImageFile
			));
			if (!IsValid(PrintOptions))
			{
				AppendResult(WorkItem, TEXT("FAIL"), TEXT(""), false, TEXT("Failed to create graph print options."));
				CurrentWorkIndex++;
				State = EState::OpenGraph;
				return;
			}

			PrintOptions->SearchTarget = ActiveGraphEditorWidget.Pin();
			PrintOptions->OutputDirectoryPath = Options.OutputDirectory;
			PrintOptions->bFailIfWidgetInfoNotWritten = Options.bRequireTextChunk;
			PrintOptions->MaxImageSize = Options.MaxModulePixels;
			PrintOptions->FilenameBaseOverride = WorkItem.FilenameBase;
			PrintOptions->ExplicitNodesToPrint = WorkItem.NodesToPrint;
			PrintOptions->TextChunkDiagnostics = WorkItem.Diagnostics;
			PrintOptions->ImageWriteOptions.Format = EDesiredImageFormat::PNG;
			PrintOptions->ImageWriteOptions.bOverwriteFile = true;
#ifdef WITH_TEXT_CHUNK_HELPER
			PrintOptions->bIsIncludeWidgetInfoInImageFile = true;
#endif

			TWeakPtr<FPrintGraphModulesJob> WeakJob = AsShared();
			PrintOptions->OnPrintFinished = FOnPrintWidgetFinished::CreateLambda(
				[WeakJob, WorkItem](const FPrintWidgetResult& Result)
				{
					if (const TSharedPtr<FPrintGraphModulesJob> This = WeakJob.Pin())
					{
						This->HandlePrintFinished(WorkItem, Result);
					}
				}
			);

			State = EState::WaitPrint;
			WidgetPrinter->PrintWidget(PrintOptions);
		}

		void HandlePrintFinished(const GraphModules::FModuleWorkItem& WorkItem, const FPrintWidgetResult& Result)
		{
			if (Result.bSucceeded && (!Options.bRequireTextChunk || Result.bTextChunkWritten))
			{
				AppendResult(WorkItem, TEXT("OK"), Result.Filename, Result.bTextChunkWritten, FString(), &Result.TextChunkDiagnostics);
			}
			else
			{
				FString Error = Result.Error;
				if (Error.IsEmpty() && Options.bRequireTextChunk && !Result.bTextChunkWritten)
				{
					Error = TEXT("Required GraphEditor TextChunk was not written.");
				}
				AppendResult(WorkItem, TEXT("FAIL"), Result.Filename, Result.bTextChunkWritten, Error, &Result.TextChunkDiagnostics);
			}

			CurrentWorkIndex++;
			State = EState::OpenGraph;
		}

		void AppendFailure(const FString& Error, const FString& GraphName)
		{
			GraphModules::FModuleResult Result;
			Result.ModuleId = TEXT("FAIL");
			Result.GraphName = GraphName;
			Result.Status = TEXT("FAIL");
			Result.Error = Error;
			Result.Diagnostics.FailureStage = TEXT("RequestFailure");
			Results.Add(Result);
		}

		void AppendResult(
			const GraphModules::FModuleWorkItem& WorkItem,
			const FString& Status,
			const FString& Filename,
			const bool bTextChunkWritten,
			const FString& Error,
			const FTextChunkDiagnostics* PrintDiagnostics = nullptr
		)
		{
			GraphModules::FModuleResult Result;
			Result.ModuleId = WorkItem.ModuleId;
			Result.ModuleTitle = WorkItem.ModuleTitle;
			Result.GraphName = WorkItem.GraphName;
			Result.NodeCount = WorkItem.NodeCount;
			Result.Bounds = WorkItem.Bounds;
			Result.ExternalEdges = WorkItem.ExternalEdges;
			Result.Filename = Filename;
			Result.bTextChunkWritten = bTextChunkWritten;
			Result.Status = Status;
			Result.Error = Error;
			Result.Diagnostics = (PrintDiagnostics != nullptr && !PrintDiagnostics->FailureStage.IsEmpty()) ? *PrintDiagnostics : WorkItem.Diagnostics;
			Result.Recovery = WorkItem.Recovery;
			Results.Add(Result);
		}

		void Finish()
		{
			if (bFinished)
			{
				return;
			}
			bFinished = true;

			int32 OkCount = 0;
			int32 SkipCount = 0;
			int32 FailCount = 0;
			for (const GraphModules::FModuleResult& Result : Results)
			{
				if (Result.Status == TEXT("OK"))
				{
					OkCount++;
				}
				else if (Result.Status == TEXT("SKIP_NO_GRAPH"))
				{
					SkipCount++;
				}
				else
				{
					FailCount++;
				}
			}

			FString Status = TEXT("Failed");
			if (OkCount > 0 && FailCount == 0)
			{
				Status = TEXT("Succeeded");
			}
			else if (OkCount > 0)
			{
				Status = TEXT("Partial");
			}
			else if (SkipCount > 0 && FailCount == 0)
			{
				Status = TEXT("Skipped");
			}

			const TSharedRef<FJsonObject> Response = MakeShared<FJsonObject>();
			Response->SetStringField(TEXT("RequestId"), Options.RequestId);
			Response->SetStringField(TEXT("Status"), Status);
			Response->SetStringField(TEXT("Command"), RemoteControlJson::CommandPrintGraphModules);
			Response->SetStringField(TEXT("AssetName"), AssetName);
			Response->SetStringField(TEXT("PackageName"), Options.PackageName);

			const TSharedRef<FJsonObject> Summary = MakeShared<FJsonObject>();
			Summary->SetNumberField(TEXT("GraphCount"), GraphsToOpen.Num());
			Summary->SetNumberField(TEXT("ModuleCount"), Results.Num());
			Summary->SetNumberField(TEXT("OK"), OkCount);
			Summary->SetNumberField(TEXT("SKIP"), SkipCount);
			Summary->SetNumberField(TEXT("FAIL"), FailCount);
			Response->SetObjectField(TEXT("Summary"), Summary);

			TArray<TSharedPtr<FJsonValue>> ModuleValues;
			for (const GraphModules::FModuleResult& Result : Results)
			{
				ModuleValues.Add(MakeShared<FJsonValueObject>(GraphModules::ModuleResultToJson(Result)));
			}
			Response->SetArrayField(TEXT("Modules"), ModuleValues);

			RemoteControlJson::SendJsonObject(WeakSocket.Pin(), Response);
			OnFinished.ExecuteIfBound();
		}

	private:
		GraphModules::FRequestOptions Options;
		TWeakPtr<IWebSocket> WeakSocket;
		FOnFinished OnFinished;
		FTSTicker::FDelegateHandle TickerHandle;
		EState State = EState::Complete;
		TWeakObjectPtr<UBlueprint> Blueprint;
		TSharedPtr<IBlueprintEditor> BlueprintEditor;
		FString AssetName;
		TArray<UEdGraph*> GraphsToOpen;
		TArray<GraphModules::FModuleWorkItem> WorkItems;
		TArray<GraphModules::FModuleResult> Results;
		int32 CurrentWorkIndex = 0;
		int32 WaitGraphTicks = 0;
		TWeakObjectPtr<UEdGraph> ActiveGraph;
		TWeakPtr<SGraphEditorImpl> ActiveGraphEditorWidget;
		bool bFinished = false;
	};

	void FGraphPrinterRemoteControlReceiver::Register()
	{
		Instance = MakeUnique<FGraphPrinterRemoteControlReceiver>();
		check(Instance.IsValid());
		
		UGraphPrinterRemoteControlSettings::OnRemoteControlEnabled.AddRaw(
			Instance.Get(), &FGraphPrinterRemoteControlReceiver::ConnectToServer
		);
		UGraphPrinterRemoteControlSettings::OnRemoteControlDisabled.AddRaw(
			Instance.Get(), &FGraphPrinterRemoteControlReceiver::DisconnectFromServer
		);

		const auto& Settings = GetSettings<UGraphPrinterRemoteControlSettings>();
		if (Settings.bEnableRemoteControl)
		{
			Instance->ConnectToServer(Settings.ServerURL);
		}
	}

	void FGraphPrinterRemoteControlReceiver::Unregister()
	{
		UGraphPrinterRemoteControlSettings::OnRemoteControlEnabled.RemoveAll(Instance.Get());
		UGraphPrinterRemoteControlSettings::OnRemoteControlDisabled.RemoveAll(Instance.Get());

		Instance.Reset();
	}

	void FGraphPrinterRemoteControlReceiver::ConnectToServer(const FString ServerURL)
	{
		DisconnectFromServer();
		
		Socket = FWebSocketsModule::Get().CreateWebSocket(ServerURL);
		check(Socket.IsValid());

		Socket->OnConnected().AddRaw(
			this, &FGraphPrinterRemoteControlReceiver::HandleOnConnected,
			ServerURL
		);
		Socket->OnConnectionError().AddRaw(this, &FGraphPrinterRemoteControlReceiver::HandleOnConnectionError);
		Socket->OnClosed().AddRaw(this, &FGraphPrinterRemoteControlReceiver::HandleOnClosed);
		Socket->OnMessage().AddRaw(this, &FGraphPrinterRemoteControlReceiver::HandleOnMessage);

		Socket->Connect();
	}

	void FGraphPrinterRemoteControlReceiver::DisconnectFromServer()
	{
		if (Socket.IsValid())
		{
			Socket->Close();
		}
		Socket.Reset();
	}

	void FGraphPrinterRemoteControlReceiver::HandleOnConnected(const FString ServerURL)
	{
		UE_LOG(LogGraphPrinter, Log, TEXT("Connected to server (URL: %s)"), *ServerURL);
	}

	void FGraphPrinterRemoteControlReceiver::HandleOnConnectionError(const FString& Error)
	{
		UE_LOG(LogGraphPrinter, Error, TEXT("Occurred connection error : %s"), *Error);
		UE_LOG(LogGraphPrinter, Error, TEXT("Make sure the server is up and re-enable remote control."));
	}

	void FGraphPrinterRemoteControlReceiver::HandleOnClosed(int32 StatusCode, const FString& Reason, bool bWasClean)
	{
		UE_LOG(LogGraphPrinter, Log, TEXT("Dissconnected from server (Status Code: %d | Reason: %s)"), StatusCode, *Reason);
	}

	void FGraphPrinterRemoteControlReceiver::HandleOnMessage(const FString& Message)
	{
		FString TrimmedMessage = Message;
		TrimmedMessage.TrimStartAndEndInline();
		if (TrimmedMessage.StartsWith(TEXT("{")))
		{
			HandleJsonMessage(TrimmedMessage);
			return;
		}

		HandleLegacyMessage(Message);
	}

	void FGraphPrinterRemoteControlReceiver::HandleLegacyMessage(const FString& Message)
	{
		FName CommandName = NAME_None;
		{
			TArray<FString> ParsedMessage;
			Message.ParseIntoArray(ParsedMessage, TEXT("-"));
			if (ParsedMessage.Num() == 3)
			{
				CommandName = *ParsedMessage[2];
			}
		}
		
		const auto& Commands = FGraphPrinterCommands::Get();
		const TSharedPtr<FUICommandInfo>& CommandToExecute = Commands.FindCommandByName(CommandName);
		if (CommandToExecute.IsValid())
		{
			Commands.CommandBindings->ExecuteAction(CommandToExecute.ToSharedRef());
			UE_LOG(LogGraphPrinter, Log, TEXT("Received request from server : %s"), *CommandName.ToString());
		}
		else
		{
			UE_LOG(LogGraphPrinter, Error, TEXT("Received invalid message from server : %s"), *Message);
		}
	}

	void FGraphPrinterRemoteControlReceiver::HandleJsonMessage(const FString& Message)
	{
		TSharedPtr<FJsonObject> Request;
		const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Message);
		if (!FJsonSerializer::Deserialize(Reader, Request) || !Request.IsValid())
		{
			RemoteControlJson::SendJsonResponse(Socket, TEXT(""), TEXT("Failed"), TEXT(""), TEXT(""), false, TEXT("Invalid JSON request."));
			UE_LOG(LogGraphPrinter, Error, TEXT("Received invalid JSON message from server : %s"), *Message);
			return;
		}

		FString RequestId = RemoteControlJson::GetStringField(Request, TEXT("RequestId"));
		if (RequestId.IsEmpty())
		{
			RequestId = FGuid::NewGuid().ToString(EGuidFormats::DigitsWithHyphens);
		}

		const FString CommandName = RemoteControlJson::GetStringField(Request, TEXT("Command"));
		const FString TargetKind = RemoteControlJson::GetStringField(Request, TEXT("TargetKind"));
		const FString OutputDirectory = RemoteControlJson::GetStringField(Request, TEXT("OutputDirectory"));

		if (CommandName.Equals(RemoteControlJson::CommandPrintGraphModules, ESearchCase::IgnoreCase))
		{
			if (ActiveModulesJob.IsValid())
			{
				RemoteControlJson::SendJsonResponse(Socket, RequestId, TEXT("Failed"), TEXT(""), TEXT(""), false, TEXT("Busy: PrintGraphModules job is already running."));
				return;
			}

			const bool bGraphOnly = TargetKind.IsEmpty() || TargetKind.Equals(RemoteControlJson::TargetKindGraphOnly, ESearchCase::IgnoreCase);
			if (!bGraphOnly)
			{
				RemoteControlJson::SendJsonResponse(Socket, RequestId, TEXT("Failed"), TEXT(""), TEXT(""), false, TEXT("PrintGraphModules only supports TargetKind=GraphOnly."));
				return;
			}

			GraphModules::FRequestOptions Options;
			Options.RequestId = RequestId;
			Options.PackageName = RemoteControlJson::GetStringField(Request, TEXT("PackageName"));
			Options.OutputDirectory = OutputDirectory;
			Options.SplitMode = RemoteControlJson::GetStringField(Request, TEXT("SplitMode"), TEXT("SemanticModules"));
			Options.MaxModuleNodes = FMath::Max(1, RemoteControlJson::GetIntField(Request, TEXT("MaxModuleNodes"), 40));
			Options.MaxModulePixels = RemoteControlJson::GetVector2DArrayField(Request, TEXT("MaxModulePixels"), FVector2D(6000.f, 6000.f));
			Options.bRequireTextChunk = RemoteControlJson::GetBoolField(Request, TEXT("RequireTextChunk"), true);
			if (Options.OutputDirectory.IsEmpty())
			{
				Options.OutputDirectory = FPaths::ProjectSavedDir() / TEXT("Screenshots/_staging");
			}
			IFileManager::Get().MakeDirectory(*Options.OutputDirectory, true);

			ActiveModulesJob = MakeShared<FPrintGraphModulesJob>(
				Options,
				Socket,
				FPrintGraphModulesJob::FOnFinished::CreateLambda(
					[this]()
					{
						ActiveModulesJob.Reset();
					}
				)
			);
			ActiveModulesJob->Start();
			UE_LOG(LogGraphPrinter, Log, TEXT("Received JSON request from server : %s (%s)"), *CommandName, *RequestId);
			return;
		}

		if (!CommandName.Equals(RemoteControlJson::CommandPrintAllAreaOfWidget, ESearchCase::IgnoreCase))
		{
			RemoteControlJson::SendJsonResponse(Socket, RequestId, TEXT("Failed"), TEXT(""), TEXT(""), false, FString::Printf(TEXT("Unsupported command: %s"), *CommandName));
			return;
		}

		auto* ProbeOptions = CreateDefaultPrintOptions<UWidgetPrinter>(
			UPrintWidgetOptions::EPrintScope::All,
			UPrintWidgetOptions::EExportMethod::ImageFile
		);
		if (!IsValid(ProbeOptions))
		{
			RemoteControlJson::SendJsonResponse(Socket, RequestId, TEXT("Failed"), TEXT(""), TEXT(""), false, TEXT("Failed to create print options."));
			return;
		}

		if (!OutputDirectory.IsEmpty())
		{
			IFileManager::Get().MakeDirectory(*OutputDirectory, true);
			ProbeOptions->OutputDirectoryPath = OutputDirectory;
		}

		const bool bGraphOnly = TargetKind.Equals(RemoteControlJson::TargetKindGraphOnly, ESearchCase::IgnoreCase);
		if (bGraphOnly)
		{
			// Automation should follow the active graph tab, not the mouse cursor or an unrelated details/viewport panel.
			ProbeOptions->SearchTarget = nullptr;
		}

		UWidgetPrinter* WidgetPrinter = nullptr;
		if (bGraphOnly)
		{
			WidgetPrinter = IWidgetPrinterRegistry::Get().FindAvailableWidgetPrinter(
				ProbeOptions,
				[](const TSubclassOf<UWidgetPrinter>& WidgetPrinterClass)
				{
					return IsValid(WidgetPrinterClass) && WidgetPrinterClass->IsChildOf(UGenericGraphPrinter::StaticClass());
				}
			);
		}
		else
		{
			WidgetPrinter = IWidgetPrinterRegistry::Get().FindAvailableWidgetPrinter(ProbeOptions);
		}

		if (!IsValid(WidgetPrinter))
		{
			const FString Error = bGraphOnly ? TEXT("SKIP_NO_GRAPH: no graph editor printer is available for the active widget.") : TEXT("No printer is available for the active widget.");
			RemoteControlJson::SendJsonResponse(Socket, RequestId, bGraphOnly ? TEXT("Skipped") : TEXT("Failed"), TEXT(""), TEXT(""), false, Error);
			return;
		}

		auto* PrintOptions = WidgetPrinter->CreateDefaultPrintOptions(
			UPrintWidgetOptions::EPrintScope::All,
			UPrintWidgetOptions::EExportMethod::ImageFile
		);
		if (!IsValid(PrintOptions))
		{
			RemoteControlJson::SendJsonResponse(Socket, RequestId, TEXT("Failed"), GetNameSafe(WidgetPrinter->GetClass()), TEXT(""), false, TEXT("Failed to create printer-specific print options."));
			return;
		}

		PrintOptions->SearchTarget = ProbeOptions->SearchTarget;
		if (!OutputDirectory.IsEmpty())
		{
			PrintOptions->OutputDirectoryPath = OutputDirectory;
		}
		PrintOptions->bFailIfWidgetInfoNotWritten = bGraphOnly;
#ifdef WITH_TEXT_CHUNK_HELPER
		if (bGraphOnly)
		{
			PrintOptions->bIsIncludeWidgetInfoInImageFile = true;
			PrintOptions->ImageWriteOptions.Format = EDesiredImageFormat::PNG;
		}
#endif

		const TWeakPtr<IWebSocket> WeakSocket = Socket;
		PrintOptions->OnPrintFinished = FOnPrintWidgetFinished::CreateLambda(
			[WeakSocket, RequestId, bGraphOnly](const FPrintWidgetResult& Result)
			{
				FString Status = Result.bSucceeded ? TEXT("Succeeded") : TEXT("Failed");
				FString Error = Result.Error;
				if (
					bGraphOnly &&
					!Result.bSucceeded &&
					(
						Error.Equals(TEXT("No widget is selected."), ESearchCase::IgnoreCase) ||
						Error.Equals(TEXT("Failed to find target widget."), ESearchCase::IgnoreCase)
					)
				)
				{
					Status = TEXT("Skipped");
					Error = TEXT("SKIP_NO_GRAPH: no printable graph editor is available for the active widget.");
				}

				RemoteControlJson::SendJsonResponse(
					WeakSocket.Pin(),
					RequestId,
					Status,
					Result.PrinterClassName,
					Result.Filename,
					Result.bTextChunkWritten,
					Error
				);
			}
		);

		WidgetPrinter->PrintWidget(PrintOptions);
		UE_LOG(LogGraphPrinter, Log, TEXT("Received JSON request from server : %s (%s)"), *CommandName, *RequestId);
	}

	TUniquePtr<FGraphPrinterRemoteControlReceiver> FGraphPrinterRemoteControlReceiver::Instance;
}
