# Parkour C++ Reference Walkthrough

## 1. 这是什么

这是 `References/Unreal-3rd-Person-Parkour` 的 C++ 组织参考 walkthrough。当前 phase 不把它当 parkour 学习项目，而把它当 “Game Animation Sample 的 C++ 化参考样板”。

## 2. 指导源是什么（thesis / paper / blog / README / code）

- 标签：`CODE_DRIVEN`
- 本轮主读材料：
  - `References/Unreal-3rd-Person-Parkour/README.md`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/GameAnimationSample.Build.cs`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/Public/Input/EnhancedPlayerInputComponent.h`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/Public/Input/GameInputConfiguration.h`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/Private/Player/EnhancedPlayerController.cpp`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/Public/Parkour/ParkourComponent.h`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/Private/Parkour/ParkourComponent.cpp`
  - `References/Unreal-3rd-Person-Parkour/Source/GameAnimationSample/Public/Traversables/TraversableActor.h`

## 3. 仓库最小运行目标

当前 phase 的最小目标不是打开 UE 编译全工程，而是静态回答：

1. 输入从哪里被组织成 gameplay tags / actions。
2. Character / Movement 层状态由谁维护。
3. Traversal 和 Montage 由谁触发。
4. Motion Matching / Chooser 在哪一层被调用。

## 4. 实际执行步骤

本轮已经实际完成的步骤：

1. 阅读 README 和 `GameAnimationSample.Build.cs`，确认模块依赖包括：
   - `EnhancedInput`
   - `PoseSearch`
   - `MotionWarping`
   - `Chooser`
2. 阅读输入边界：
   - `EnhancedPlayerController.cpp`
   - `EnhancedPlayerInputComponent.h`
   - `GameInputConfiguration.h`
3. 阅读运行时边界：
   - `ParkourComponent.h`
   - `ParkourComponent.cpp`
   - `TraversableActor.h`

本轮不编译工程，因为当前目标是抽取 C++ 结构启发，而不是跑起 sample。

## 5. 关键输入 / 输出

### 输入层

- `UGameInputConfiguration::AbilityInputActions`
- `UEnhancedPlayerInputComponent::BindAbilityActions(...)`
- `AEnhancedPlayerController::SetupInputComponent()`

### Character / Movement 层

- `UParkourComponent`
  - `CurrentDesiredGait`
  - `bWantsToWalk`
  - `bWantsToSprint`
  - `bWantsToStrafe`
  - `bWantsToAim`

### Traversal 层

- `FTraversableCheckResult`
- `ATraversableActor::GetLedgeTransforms(...)`
- `UParkourComponent::PerformTraversalCheck(...)`
- `UParkourComponent::DetermineParkourAction(...)`

### 动画输出层

- `UParkourComponent::SelectParkourMontage(...)`
- `UPoseSearchLibrary::MotionMatch(...)`
- `AnimInstance->Montage_Play(...)`
- `UMotionWarpingComponent` target 更新

## 6. 关键源码入口

### 输入层

- `Public/Input/GameInputConfiguration.h`
  - `FGameInputAction`
  - `UGameInputConfiguration`
- `Public/Input/EnhancedPlayerInputComponent.h`
  - `BindAbilityActions(...)`
- `Private/Player/EnhancedPlayerController.cpp`
  - `BeginPlay()`
  - `SetupInputComponent()`

这条链路把：

`Input Mapping Context -> InputAction -> GameplayTag -> Callback`

做成了清晰的 C++ 边界。

### Character / Movement 层

- `Public/Parkour/ParkourComponent.h`
  - `Move(...)`
  - `Look(...)`
  - `WalkToggle(...)`
  - `Sprint(...)`
  - `StrafeToggle(...)`
  - `Aim(...)`
  - `CalculateMaxSpeed()`
  - `UpdateRotation(...)`
- `Private/Parkour/ParkourComponent.cpp`
  - gait、速度、朝向、输入绑定都在这里落地

### 动画更新层

- `UParkourComponent::SelectParkourMontage(...)`
  - 先构造 `FMovementChooserParams`
  - 再走 `UChooserTable::EvaluateChooser(...)`
  - 最后走 `UPoseSearchLibrary::MotionMatch(...)`
- `UParkourComponent::OnAnimInstanceMontageEndOrAbort(...)`
  - 管 movement mode 和 montage 生命周期收尾

### Motion Matching 接入点

最核心的接入点不在独立 AnimNode，而是在 `ParkourComponent` 内完成：

- `UChooserTable::EvaluateChooser(...)`
- `UPoseSearchLibrary::MotionMatch(...)`

这意味着该仓更像 “gameplay component 决定动画入口”，而不是 “自定义 Anim Graph node 决定动画入口”。

## 7. 它在 GASPALS 联合架构中的位置

它在 GASPALS 联合架构中的位置是 “未来 C++ 化重构样板”，尤其适合对照以下边界：

- 输入层如何从 `InputAction` 走到 gameplay semantic
- traversal 逻辑如何被组件化
- Chooser / PoseSearch 如何被组件驱动而不是散落在 blueprint 里

对照 `Docs/RuntimeInsertionPoints.md`，它最有价值的不是替换 GASPALS 宿主，而是帮助以后把以下观测面 C++ 化：

- input aggregation
- traversal boundary
- motion matching request boundary

## 8. 未来是否适合作为

| 用途 | 结论 | 原因 |
| --- | --- | --- |
| Shadow Mode 输入层 | 间接适合 | 输入绑定和状态聚合方式对未来 observer/component 设计有启发。 |
| LMM 替换点 | 不适合 | 本仓核心是 PoseSearch + traversal montage 组织，不是 LMM runtime。 |
| Control Operators 编码层 | 不适合 | 不涉及 control schema / encoder。 |
| C++ 重构模板 | 非常适合 | 这是本仓对 GASPALS 的主价值。 |

### 对 GASPALS C++ 化的启发清单

- 把输入语义收敛到 `DataAsset + GameplayTag + InputComponent`，不要把输入散落在多个 blueprint graph。
- 把 traversal、chooser、pose search 请求收敛到组件边界，而不是让角色蓝图直接堆逻辑。
- 把 montage 生命周期和 movement mode 切换放到同一组件，减少状态分裂。
- 用明确定义的 struct 承载 chooser 输入，例如 `FMovementChooserParams` 和 `FTraversableCheckResult`。

## 9. 当前不建议做的事情

- 不要把整个 sample 当成 GASPALS 宿主替代品。
- 不要把 parkour traversal 逻辑和 GASPALS 的主 locomotion 直接混合。
- 不要因为它是 C++ 重写版，就跳过当前 GASPALS 的 Shadow Mode 和文档化阶段。

## 10. 下一步建议

1. 先从这个仓抽“结构启发”，不要抽“玩法逻辑”。
2. 若以后开始 GASPALS C++ 化，优先借鉴：
   - `GameInputConfiguration`
   - `EnhancedPlayerInputComponent`
   - `ParkourComponent`
   的组织方式。
3. 与当前 GASPALS 文档对齐时，优先把启发写成组件边界，而不是写成“把这个类直接抄过去”。
