# Learned Motion Matching UE5 Thesis Walkthrough

## 1. 这是什么

这是 `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5` 的 thesis-driven walkthrough。它描述的不是 GASPALS 宿主工程，而是一套独立的 UE5 Learned Motion Matching 运行时实现，用来回答三个问题：

1. thesis 里的章节，在工程里分别落到了哪些文件。
2. UE 侧动画节点、特征更新、模型加载和动画图接入点在哪里。
3. 未来 GASPALS 若做 Shadow LMM，对照面应该选哪些类，哪些边界现在绝不能碰。

## 2. 指导源是什么（thesis / paper / blog / README / code）

- 标签：`THESIS_DRIVEN`
- 本轮主读材料：
  - `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5/thesis.pdf`
  - `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5/README.md`
  - `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5/Source/Testing/*`
  - `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5/Plugins/FeatureExtraction/*`
  - `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5/Import/*`
- thesis 关键章节：
  - `1.2.1 Motion Capture Data Extraction`
  - `1.2.2 Model Training`
  - `1.2.3 Character Controller in Unreal Engine`
  - `3.3 Character Controller`
  - `4.3.3 Character Controller`

## 3. 仓库最小运行目标

当前 phase 的最小目标不是编译工程，而是完成下面这四件事：

1. 用 thesis 章节解释工程结构。
2. 找到自定义 Anim Graph 节点入口。
3. 找到特征更新入口和模型加载入口。
4. 说明它与 GASPALS 当前 `PoseSearch + AnimBP + Shadow observer` 架构的未来对照关系。

## 4. 实际执行步骤

本轮已经实际完成的步骤：

1. 使用 `pdftotext -layout thesis.pdf -` 抽取 thesis 目录和章节标题，确认 thesis 的三段主线是：
   - `Motion Capture Data Extraction`
   - `Model Training`
   - `Character Controller in Unreal Engine`
2. 静态阅读：
   - `Source/Testing/Public/AnimNode_Learned_MM.h`
   - `Source/Testing/Private/AnimNode_Learned_MM.cpp`
   - `Source/Testing/Public/AnimGraphNode_Learned_MM.h`
   - `Source/Testing/Private/AnimGraphNode_Learned_MM.cpp`
   - `Plugins/FeatureExtraction/Source/FeatureExtraction/*`
3. 确认输入资产：
   - `Import/LMM/decompressor.onnx`
   - `Import/LMM/projector.onnx`
   - `Import/LMM/stepper.onnx`
   - `Import/LMM/features.bin`
4. 确认依赖模块：
   - `Testing.Build.cs` 依赖 `NNE`、`PoseSearch`、`MotionTrajectory`

本轮未执行 compile；原因不是计划缺失，而是当前 phase 目标是 thesis-to-code mapping，不是 UE 运行时接管。

## 5. 关键输入 / 输出

### 输入

- ONNX 模型：
  - `Import/LMM/decompressor.onnx`
  - `Import/LMM/projector.onnx`
  - `Import/LMM/stepper.onnx`
- 特征数据库：
  - `Import/LMM/features.bin`
- 轨迹输入：
  - `FPoseSearchQueryTrajectory Trajectory`
- 节点公开参数：
  - `UNNEModelData* Decompressor`
  - `UNNEModelData* Stepper`
  - `UNNEModelData* Projector`

### 运行时状态

- 当前 feature：
  - `TArray<float> FeaturesCurrent`
- 当前 latent：
  - `TArray<float> LatentCurrent`
- 当前 pose：
  - `FPose_LMM PoseCurrent`
- 过渡器：
  - `FInertializer Inertializer`

### 输出

- `Evaluate_AnyThread(...)` 最终把骨骼位置与旋转写回 `FPoseContext Output`
- 输出路径不是 montage，也不是 Pose Search database selection，而是直接构造一帧动画 pose

## 6. 关键源码入口

### 章节到工程文件映射

| Thesis 章节 | 工程落点 | 说明 |
| --- | --- | --- |
| `Motion Capture Data Extraction` | 本仓只保留消费结果；真正实现位于 companion repo `Learned_Motion_Matching_Training/DataProcessing/*` | 这里没有完整 extractor，只有 `Import/` 中的已导入资产与示例 FBX。 |
| `Model Training` | 本仓只保留消费结果；真正实现位于 companion repo `Learned_Motion_Matching_Training/ModelTraining/*` | 本仓通过 `Import/LMM/*` 消费训练结果。 |
| `Character Controller in Unreal Engine` | `AnimNode_Learned_MM.*`, `AnimGraphNode_Learned_MM.*`, `Testing.Build.cs` | 真正的 thesis runtime 核心都在这里。 |

### UE 侧动画节点入口

- 动画图编辑器入口：
  - `Source/Testing/Public/AnimGraphNode_Learned_MM.h`
  - `Source/Testing/Private/AnimGraphNode_Learned_MM.cpp`
- 运行时节点入口：
  - `Source/Testing/Public/AnimNode_Learned_MM.h`
  - `Source/Testing/Private/AnimNode_Learned_MM.cpp`
- 关键函数：
  - `FAnimNode_Learned_MM::Initialize_AnyThread(...)`
  - `FAnimNode_Learned_MM::Evaluate_AnyThread(...)`
  - `FAnimNode_Learned_MM::ProjectorEvaluate(...)`
  - `FAnimNode_Learned_MM::StepperEvaluate(...)`
  - `FAnimNode_Learned_MM::DecompressorEvaluate(...)`

### 特征提取入口

真正参与每帧特征更新的不是 `Plugins/FeatureExtraction`，而是：

- `FFeatures::Initialize(...)`
- `FFeatures::Update(...)`
- `FFeatures::GetTrajectoryData(...)`
- `FFeatures::GetTrajectoryPositions(...)`
- `FFeatures::GetTrajectoryDirection(...)`
- `FFeatures::GetFeatureParameters(...)`

`Plugins/FeatureExtraction` 当前只是 editor shell：

- `SFeatureExtractionMenu.cpp` 只有一个 test button
- 它不能被视为 production-ready 的 feature extractor

### 模型加载入口

- `FModelInstance` 构造函数
  - 从 `UNNEModelData` 创建 `IModelCPU`
  - 再创建 `IModelInstanceCPU`
  - 自动分配 input/output tensor buffer
- `FAnimNode_Learned_MM::Initialize_AnyThread(...)`
  - `UE::NNE::GetRuntime<INNERuntimeCPU>("NNERuntimeORTCpu")`
  - 分别创建 `DecompressorInstance`
  - `StepperInstance`
  - `ProjectorInstance`

### 动画图接入方式

- `UAnimGraphNode_Learned_MM::GetMenuCategory()` 返回 `Learned Motion Matching`
- `UAnimGraphNode_Learned_MM::GetNodeTitle()` 返回 `Learned Motion Matching`
- README 明确要求把 `Private/Public` 中的节点代码加入项目后，在角色 Anim Graph 中添加该 node

### Character Trajectory 依赖

- `AnimNode_Learned_MM.h` 直接包含 `PoseSearch/PoseSearchTrajectoryTypes.h`
- 节点成员直接持有 `FPoseSearchQueryTrajectory Trajectory`
- `Testing.Build.cs` 明确依赖：
  - `PoseSearch`
  - `MotionTrajectory`
- `FFeatures::GetTrajectoryData(...)` 假设 `Trajectory.Samples.Num() > 3`

这说明它不是一个独立于 Character Trajectory 的黑盒节点，而是显式依赖 UE 轨迹采样。

## 7. 它在 GASPALS 联合架构中的位置

它处于 GASPALS 联合架构中的“未来 live shadow inference 参考实现”位置：

- 与 `Docs/RuntimeInsertionPoints.md` 对照：
  - GASPALS 当前正式决策面仍是 `CBP_SandboxCharacter` 和 `ABP_SandboxCharacter`
  - 这个仓则展示了“如果未来把 LMM 作为一个自定义 AnimNode 插进 Anim Graph，会是什么结构”
- 与 `Docs/RepoRoleMap.md` 对照：
  - 它是 `Learned_Motion_Matching_Training` 的运行时 companion
  - 不是当前宿主，不做直接 takeover

未来可对照 GASPALS 的类：

- `FAnimNode_Learned_MM`
  - 对照未来可能的 `GASPALSShadow` LMM AnimNode
- `FModelInstance`
  - 对照未来统一的 ONNX/NNE model wrapper
- `FFeatures`
  - 对照未来从宿主轨迹/骨骼状态构造 LMM query 的 feature bridge
- `FInertializer`
  - 对照未来 takeover 前后 pose smoothing 的过渡层

## 8. 未来是否适合作为

| 用途 | 结论 | 原因 |
| --- | --- | --- |
| Shadow Mode 输入层 | 部分适合 | `FFeatures` 和 `FPoseSearchQueryTrajectory` 的接线方式值得借鉴，但它本身不是宿主输入层。 |
| LMM 替换点 | 适合 | `FAnimNode_Learned_MM`、`FModelInstance`、`FFeatures` 共同定义了一个完整 LMM runtime slice。 |
| Control Operators 编码层 | 不适合 | 本仓只消费 trajectory-style features，不提供 control schema/encoder。 |
| C++ 重构模板 | 部分适合 | 自定义 AnimGraph node、NNE 包装和 pose 写回方式可借鉴，但不能整体搬到 GASPALS。 |

明确的 Shadow Mode 安全边界：

- 现在可以借鉴：
  - `FModelInstance`
  - `FFeatures` 的 query 更新思路
  - `FInertializer` 的 pose transition 处理
- 现在不要碰：
  - 直接用此节点替换 GASPALS 正式 AnimBP 主线
  - 直接绕过 GASPALS 当前 Pose Search/overlay 结构

## 9. 当前不建议做的事情

- 不要把 `Plugins/FeatureExtraction` 当成完整特征提取工具，它目前只是测试 UI。
- 不要忽略 Character Trajectory 依赖；没有 `FPoseSearchQueryTrajectory`，该节点就缺少关键输入。
- 不要直接把 `FAnimNode_Learned_MM` 粘到 GASPALS 主工程里做 Big Bang 接管。
- 不要在没完成 Shadow Mode 对照面之前，试图直接替换 `ABP_SandboxCharacter` 主动画决策面。
- 不要忽略 README 里的限制：作者明确提到该项目更适合从 IDE 的 debug 模式运行。

## 10. 下一步建议

1. 在 GASPALS 侧先只抽取对照接口：
   - 轨迹采样
   - feature bridge
   - NNE wrapper
2. 把 `FAnimNode_Learned_MM` 切分成未来可复用的三块概念：
   - `Feature Update`
   - `Model Execution`
   - `Pose Reconstruction + Inertialization`
3. 继续把 thesis 第 `3.3.1`、`3.3.2`、`3.3.3` 与 companion training repo 的 `generate_database.py`、`train_*` 脚本对齐，形成一条完整的 thesis-to-artifact-to-runtime 追踪链。
