# Motion-Matching Demo Walkthrough

## 1. 这是什么

这是 `References/Motion-Matching` 的博客驱动 demo walkthrough。它是一个算法和数据结构直觉样机，不是 UE runtime。对 GASPALS 的价值在于把下面三层放在一个最小可读 demo 里：

- Motion Matching query/search
- Learned Motion Matching 的 `projector + stepper + decompressor`
- 轨迹预测、惯性过渡、脚接触/IK 等 supporting loop

## 2. 指导源是什么（thesis / paper / blog / README / code）

- 标签：`BLOG_DRIVEN`
- 本轮主读材料：
  - `References/Motion-Matching/README.md`
  - `https://theorangeduck.com/page/code-vs-data-driven-displacement`
  - `https://theorangeduck.com/page/learned-motion-matching`
  - `References/Motion-Matching/controller.cpp`
  - `References/Motion-Matching/database.h`
  - `References/Motion-Matching/lmm.h`
  - `References/Motion-Matching/nnet.h`

## 3. 仓库最小运行目标

本仓的最小目标不是把 demo 完整编译出来，而是确认三件事：

1. Motion Matching 的 query/search 数据结构怎么组织。
2. Learned Motion Matching 在 demo 里如何切换成 `projector + stepper + decompressor`。
3. 哪些概念可以迁到 GASPALS / Pose Search，哪些只能停留在 demo 层。

如果本机 raylib toolchain 就绪，额外目标才是编译 `controller.cpp`。

## 4. 实际执行步骤

本轮已经实际完成的步骤：

1. 阅读：
   - `README.md`
   - `Makefile`
   - `controller.cpp`
   - `database.h`
   - `lmm.h`
   - `nnet.h`
2. 环境检查：
   - `C:\raylib=False`
   - `make` 不在 PATH
3. 资源确认：
   - `resources/database.bin`
   - `resources/features.bin`
   - `resources/latent.bin`
   - `resources/decompressor.bin`
   - `resources/projector.bin`
   - `resources/stepper.bin`
   已经全部在盘上

当前最直接的 blocker 不是缺数据，而是缺编译环境。若要继续，下一条命令应先修 raylib：

```powershell
# 安装 raylib 到 C:\raylib，并让 make 可用后再进入仓库执行
make
```

## 5. 关键输入 / 输出

### 输入

- 动画数据库：
  - `resources/database.bin`
- matching 特征：
  - `resources/features.bin`
- LMM latent：
  - `resources/latent.bin`
- LMM 网络：
  - `resources/decompressor.bin`
  - `resources/projector.bin`
  - `resources/stepper.bin`
- 运行时 query：
  - 足部位置
  - 足部速度
  - hip velocity
  - trajectory positions
  - trajectory directions

### 输出

- 非 LMM 路径：
  - `database_search(...)` 选中的最佳 frame index
- LMM 路径：
  - `projector_evaluate(...)` 给出 `features_proj + latent_proj`
  - `stepper_evaluate(...)` 更新 `features_curr + latent_curr`
  - `decompressor_evaluate(...)` 还原 pose
- 最终输出：
  - 当前骨骼 pose
  - 接触状态
  - 经过 inertialization / adjustment / IK 的可显示角色姿态

## 6. 关键源码入口

### 数据结构层

- `database.h`
  - `struct database`
  - `database_load(...)`
  - `database_build_matching_features(...)`
  - `database_search(...)`
  - `motion_matching_search(...)`

关键事实：

- `compute_trajectory_position_feature(...)` 与 `compute_trajectory_direction_feature(...)` 固定使用未来 `20/40/60` 帧。
- matching 特征由：
  - left foot position
  - right foot position
  - left foot velocity
  - right foot velocity
  - hip velocity
  - trajectory positions
  - trajectory directions
 组成。

### LMM 推理层

- `lmm.h`
  - `decompressor_evaluate(...)`
  - `stepper_evaluate(...)`
  - `projector_evaluate(...)`

这三个函数就是 demo 版 LMM 的核心运行时循环。

### 网络格式层

- `nnet.h`
  - `struct nnet`
  - `nnet_load(...)`
  - `nnet_evaluate(...)`

这里的 `.bin` 网络格式是 demo 自定义格式，不是 ONNX，不应直接映射到 UE NNE。

### 主循环层

- `controller.cpp`
  - `database_load(...)`
  - `database_build_matching_features(...)`
  - query 组装：
    - `query_compute_trajectory_position_feature(...)`
    - `query_compute_trajectory_direction_feature(...)`
  - 轨迹预测：
    - `trajectory_desired_rotations_predict(...)`
    - `trajectory_desired_velocities_predict(...)`
    - `trajectory_positions_predict(...)`
  - LMM/非 LMM 分支：
    - `if (lmm_enabled) { ... } else { ... }`

## 7. 它在 GASPALS 联合架构中的位置

它位于 GASPALS 联合架构中的“算法直觉中间层”：

- 上游：
  - `ControlOperators` 提供 control schema 和 trajectory idea
- 中间：
  - 本仓把 query、search、projection、step、decompress 关系讲透
- 下游：
  - `Learned_Motion_Matching_Training`
  - `Learned_Motion_Matching_UE5`
  - 未来 GASPALS Shadow LMM

它最适合用来回答“算法上到底发生了什么”，不适合回答“UE 里该把代码挂在哪”。

## 8. 未来是否适合作为

| 用途 | 结论 | 原因 |
| --- | --- | --- |
| Shadow Mode 输入层 | 不适合 | 它不定义宿主输入 contract，只消费已经整理好的 query。 |
| LMM 替换点 | 适合做概念参考 | `projector/stepper/decompressor` 的职责边界很清楚，但实现形式不是 UE-ready。 |
| Control Operators 编码层 | 间接适合 | trajectory horizon 和 query 语义可对齐，但本仓不负责 control encoding。 |
| C++ 重构模板 | 不适合 | 这是 raylib demo，不是 Unreal module 组织模板。 |

### 可迁移到 GASPALS / Pose Search 的概念

- future trajectory 使用 `20/40/60` 帧 horizon
- feature normalization / offset / scale 的语义
- query 与 database feature 必须同构
- search timer 与 force search timer
- projector transition cost 的概念

### 不应直接迁移的内容

- `nnet.h` 自定义网络格式
- raylib 渲染和输入循环
- demo 中直接手写数组和裸数据布局
- demo 的 adjustment / IK 参数原样照搬

## 9. 当前不建议做的事情

- 不要把 `database.h`/`lmm.h` 原样硬搬进 UE module。
- 不要把 `.bin` 神经网络格式作为 GASPALS 的未来模型接口。
- 不要把这个仓当成 Pose Search 资产配置模板。
- 不要在没有 raylib 环境时把“编译失败”误判成“算法资料不足”。

## 10. 下一步建议

1. 先把本仓的 feature 语义与 `10_lmm_training_pipeline.md` 中的 `features.bin` 语义逐项对齐。
2. 再把 `trajectory 20/40/60` 与 `Docs/DataContract_Control_to_LMM.md` 做术语统一。
3. 最后再到 `11_lmm_ue5_thesis_walkthrough.md` 看这些概念如何被塞进 UE `AnimNode` 和 `FPoseSearchQueryTrajectory`。
