# Learned Motion Matching Training Pipeline Walkthrough

## 1. 这是什么

这是 `References/Learned_Motion_Matching_Training` 的离线训练链路说明文档。它不是 GASPALS 运行时，也不是要被直接嵌进宿主项目的代码；它的职责是把原始动作数据变成 `features.bin`、`latent.bin` 和三份 ONNX 模型，供后续 UE 侧运行时消费。

## 2. 指导源是什么（thesis / paper / blog / README / code）

- 标签：`README_DRIVEN`
- 实际主导来源：`docs/`
- 本轮主读材料：
  - `References/Learned_Motion_Matching_Training/README.md`
  - `References/Learned_Motion_Matching_Training/docs/RUNBOOK.md`
  - `References/Learned_Motion_Matching_Training/docs/LESSONS_LEARNED.md`
  - `References/Learned_Motion_Matching_Training/DataProcessing/Readme.txt`
  - `References/Learned_Motion_Matching_Training/ModelTraining/readme.txt`

## 3. 仓库最小运行目标

本仓的最小目标不是完整重训 50 万 iter，而是把链路和产物关系走通：

```text
FbxToBinConverter.cpp
-> generate_database.py
-> train_decompressor.py
-> train_projector.py
-> train_stepper.py
-> validate_onnx_models.py
```

当前最小可执行验证应优先分成两段：

1. `case-02-generate-db.ps1`
   - 直接使用 `ModelTraining/Data/` 里的三份 `.bin` fallback 数据。
2. `case-06-validate-inference.ps1`
   - 在已有 `Models/*.onnx` 和 `Database/latent.bin` 的前提下做一次 CPU 单步推理验证。

`case-01-dataprocess.ps1` 只在 FBX SDK 就绪后再跑。

## 4. 实际执行步骤

本轮已经实际完成的步骤：

1. 执行并记录：

```powershell
git submodule update --init --recursive
git submodule status --recursive
```

2. 检查训练链脚本：
   - `scripts/cases/case-01-dataprocess.ps1`
   - `scripts/cases/case-02-generate-db.ps1`
   - `scripts/cases/case-03-train-decompressor.ps1`
   - `scripts/cases/case-04-train-projector.ps1`
   - `scripts/cases/case-05-train-stepper.ps1`
   - `scripts/cases/case-06-validate-inference.ps1`
3. 确认 fallback 数据已在盘上：
   - `ModelTraining/Data/walk1_subject5.bin`
   - `ModelTraining/Data/run1_subject5.bin`
   - `ModelTraining/Data/pushAndStumble1_subject5.bin`
   - `ModelTraining/Data/boneParentInfo.bin`
4. 确认当前 shell blocker：
   - `$env:FBXSDK_ROOT` 为空。
   - `msbuild` 不在 PATH，但 `C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe` 存在，说明 `case-01` 的主要 blocker 是 FBX SDK，而不是 MSBuild 缺失。
   - 当前 base Python `torch=False`、`onnxruntime=False`，所以未在本轮直接运行 Python case。

如果现在继续最小验证，下一条推荐命令是：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\cases\case-02-generate-db.ps1 -InstallDeps
```

如果只想验证已有 ONNX 是否还能推理，下一条推荐命令是：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\cases\case-06-validate-inference.ps1 -InstallDeps
```

## 5. 关键输入 / 输出

### 输入

- 原始动作：
  - `Animations/LAFAN1BVH/*.bvh`
- 中间 FBX：
  - `Animations/LAFAN1FBX/*.fbx`
- 供训练使用的二进制动作：
  - `Animations/LAFAN1BIN/*.bin`
  - `Animations/LAFAN1BIN/boneParentInfo.bin`
- 当前仓库已经准备好的 fallback：
  - `ModelTraining/Data/*.bin`

### 中间产物

- `ModelTraining/Database/database.bin`
  - 骨骼位置、速度、旋转、角速度、父子层级、range、接触状态
- `ModelTraining/Database/features.bin`
  - 特征矩阵 + `feature_offset` + `feature_scale`
- `ModelTraining/Database/latent.bin`
  - 每帧 latent 向量

### 最终产物

- `ModelTraining/Models/decompressor.onnx`
- `ModelTraining/Models/projector.onnx`
- `ModelTraining/Models/stepper.onnx`

### 验证产物

- `ModelTraining/Misc/onnx_validation_report.md`
- `logs/case-0x-*.log`

## 6. 关键源码入口

- 数据预处理入口：
  - `DataProcessing/FbxToBinConverter.cpp`
  - `convertAssetsToBvh(...)`
  - `ExtractPoses(...)`
  - `files`
  - `bonesToExtract`
- 数据库构建入口：
  - `ModelTraining/generate_database.py`
  - `database_binaries`
  - `build_feature_vector(...)`
- 特征定义：
  - `ModelTraining/feature_extraction.py`
  - `get_position_feature(...)`
  - `get_velocity_feature(...)`
  - `get_trajectory_position_feature(...)`
  - `get_trajectory_direction_feature(...)`
- 数据格式读写：
  - `ModelTraining/train_common.py`
  - `load_database(...)`
  - `load_features(...)`
  - `load_latent(...)`
  - `save_onnx_network(...)`
- 模型训练：
  - `ModelTraining/train_decompressor.py`
  - `ModelTraining/train_projector.py`
  - `ModelTraining/train_stepper.py`
- 一步推理验证：
  - `ModelTraining/validate_onnx_models.py`

关键实现事实：

- `FbxToBinConverter.cpp` 的 `files` 列表决定要转换哪些动作，`bonesToExtract` 决定输出哪些骨骼。
- `generate_database.py` 当前只拿三条训练二进制做最小数据库：
  - `pushAndStumble1_subject5.bin`
  - `run1_subject5.bin`
  - `walk1_subject5.bin`
- `feature_extraction.py` 当前 feature 组成是：
  - 位置骨骼索引 `[4, 8]`
  - 速度骨骼索引 `[4, 8, 1]`
  - 未来轨迹位置 `20/40/60` 帧
  - 未来轨迹方向 `20/40/60` 帧
  - 权重 `[0.75, 1, 1, 1.5]`
- `train_decompressor.py` 会先写 `Database/latent.bin`，然后导出 `Models/decompressor.onnx`。
- `train_projector.py` 和 `train_stepper.py` 都依赖 `latent.bin`，所以 decompressor 必须先完成。

## 7. 它在 GASPALS 联合架构中的位置

它位于 GASPALS 联合架构的离线训练侧，作用是为未来的 Shadow LMM 或实验性接管提供模型和数据库语义：

- 上游输入：
  - 原始动作资产或预处理后二进制动作
- 本仓输出：
  - `features.bin`
  - `latent.bin`
  - `decompressor.onnx`
  - `projector.onnx`
  - `stepper.onnx`
- 下游消费者：
  - `Learned_Motion_Matching_UE5`
  - 未来的 `Plugins/GASPALSShadow` 离线对比工具

它与 `Docs/RepoRoleMap.md` 的定位一致：训练参考，不是宿主运行时。

## 8. 未来是否适合作为

| 用途 | 结论 | 原因 |
| --- | --- | --- |
| Shadow Mode 输入层 | 不适合 | 这里处理的是离线动作数据库和模型训练，不是宿主输入采样层。 |
| LMM 替换点 | 适合 | `features.bin + latent.bin + 3x ONNX` 正是未来 UE LMM 运行时的模型侧替换面。 |
| Control Operators 编码层 | 间接适合 | 它不提供 control schema，但未来可以消费由 `ControlOperators` 导出的 canonical trajectory/features。 |
| C++ 重构模板 | 不适合 | 仓库核心是 C++ 预处理 + Python 训练脚本，不是宿主运行时模块化模板。 |

## 9. 当前不建议做的事情

- 不要在没有设置 `FBXSDK_ROOT` 的情况下强跑 `case-01`。
- 不要一上来把 `LMM_NITER` 保持在默认 `500000` 做完整重训。
- 不要在 walkthrough 完成前，把 `Models/*.onnx` 或 `features.bin` 直接接入 GASPALS 主运行时。
- 不要把 `ModelTraining/Data/*.bin` 当成正式数据治理方案，它只是最小 fallback。

## 10. 下一步建议

1. 先跑 `case-06-validate-inference.ps1 -InstallDeps`，验证当前 shipped ONNX 在本机可推理。
2. 再跑 `case-02-generate-db.ps1 -InstallDeps`，利用 `ModelTraining/Data/` fallback 重新生成 `database.bin` 与 `features.bin`。
3. 仅在 case-02 成功后，按 smoke 参数运行：
   - `case-03-train-decompressor.ps1`
   - `case-04-train-projector.ps1`
   - `case-05-train-stepper.ps1`
4. 最后把这套 artifact vocabulary 对齐到 `11_lmm_ue5_thesis_walkthrough.md` 中的 UE 运行时消费点。
