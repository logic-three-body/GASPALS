# Reference to GASPALS Master Map

## 定位对比表

> 原始任务描述里写的是“五个参考项目”，但当前实际工作区包含 6 个需要纳入决策的参考单元，因为 `Learned_Motion_Matching_UE5` 已经被拆成独立运行时 companion。

| Reference | Primary Role | Best Module To Learn | Upstream / Downstream Relation To GASPALS | Current Action |
| --- | --- | --- | --- | --- |
| `Motion-Matching` | 算法与数据结构直觉样机 | query feature、search、`projector/stepper/decompressor` 职责切分 | 位于 Control contract 与 UE runtime 之间，负责解释算法中间层 | 学习与映射，不接管 |
| `Learned_Motion_Matching_Training` | 离线训练与 artifact 生产线 | `features.bin`、`latent.bin`、ONNX 产物链路 | 是未来 Shadow LMM 的离线模型上游 | 学习、验证、生成模型，不接管 |
| `Learned_Motion_Matching_UE5` | UE5 LMM 运行时 companion | `AnimNode_Learned_MM`、`FModelInstance`、`FFeatures` | 消费 training 仓输出，展示未来 UE 运行时形态 | 学习与映射，不接管 |
| `ControlOperators` | 控制 schema 与 encoder 参考 | `UberControlEncoder`、`trajectory` control payload | 位于 GASPALS 宿主输入与 future LMM feature construction 之间 | 学习与映射，优先冻结 contract |
| `Unreal-3rd-Person-Parkour` | Game Animation Sample 的 C++ 组织参考 | 输入层、组件边界、chooser/traversal 组织 | 与 GASPALS 同属 UE 宿主层，但只提供结构启发 | 学习与映射，不接管 |
| `Learned-Motion-Matching` | Unity + PyTorch + ONNX 的替代算法参考系 | artifact vocabulary、ONNX/Barracuda 路线 | 主要用于交叉校验 LMM 模型职责，不直接进入当前 UE 主线 | 学习与映射，不接管 |

## 每个项目最适合学习的模块

| Reference | Most Useful Module |
| --- | --- |
| `Motion-Matching` | `database.h` 的 feature/query/search 组织，`lmm.h` 的三段式推理职责 |
| `Learned_Motion_Matching_Training` | `generate_database.py`、`feature_extraction.py`、`train_decompressor.py`、`train_projector.py`、`train_stepper.py` |
| `Learned_Motion_Matching_UE5` | `AnimNode_Learned_MM.*`、`AnimGraphNode_Learned_MM.*`、`FModelInstance`、`FFeatures` |
| `ControlOperators` | `control_operators.py`、`control_encoder.py`、`gameplay_input.py` |
| `Unreal-3rd-Person-Parkour` | `EnhancedPlayerInputComponent`、`GameInputConfiguration`、`ParkourComponent`、`TraversableActor` |
| `Learned-Motion-Matching` | `decompressor.py`、`projector.py`、`stepper.py`、`CustomFunctions.py` |

## 与 GASPALS 的上下游关系

```text
GASPALS host input / character state
-> ControlOperators (control schema / encoder reference)
-> Motion-Matching (algorithm intuition, feature/query/search reference)
-> Learned_Motion_Matching_Training (offline dataset -> features/latent/onnx)
-> Learned_Motion_Matching_UE5 (UE runtime consumption pattern)
-> future GASPALSShadow live inference experiment
```

并行的交叉验证线：

```text
Learned-Motion-Matching
-> alternate LMM artifact vocabulary and ONNX deployment sanity check
```

结构参考线：

```text
Unreal-3rd-Person-Parkour
-> future GASPALS C++ organization reference
```

## 推荐接入顺序

1. `Motion-Matching`
   - 先把 feature/query/search/LMM 三段职责看明白。
2. `Learned_Motion_Matching_Training`
   - 再把这些概念映射到当前实际训练脚本和产物格式。
3. `Learned_Motion_Matching_UE5`
   - 然后看 UE 侧如何消费这些产物。
4. `ControlOperators`
   - 在运行时接入前冻结 control contract，先统一输入语义。
5. `Unreal-3rd-Person-Parkour`
   - 最后再借它的组件边界和输入组织做 GASPALS C++ 化启发。
6. `Learned-Motion-Matching`
   - 作为补充算法参考和 artifact vocabulary 对照，不作为主线。

## 当前明确只做“学习与映射”，不做接管

当前只做学习与映射，不做接管的项目：

- `Motion-Matching`
  - 原因：raylib demo，不是 UE host。
- `Learned_Motion_Matching_Training`
  - 原因：离线训练线，不是 runtime host。
- `Learned_Motion_Matching_UE5`
  - 原因：现在只拿来对照，不替换 GASPALS 正式 AnimBP。
- `ControlOperators`
  - 原因：先冻结 schema，再考虑推理。
- `Unreal-3rd-Person-Parkour`
  - 原因：只借结构，不接管宿主玩法和 traversal 逻辑。
- `Learned-Motion-Matching`
  - 原因：Unity/Barracuda 路线不是当前 UE 主线。

## 当前结论

- GASPALS 仍然是唯一正式宿主。
- `ControlOperators` 负责 control contract 的上游语义。
- `Motion-Matching` 负责算法直觉。
- `Learned_Motion_Matching_Training` 负责 offline artifacts。
- `Learned_Motion_Matching_UE5` 负责 UE runtime 形态参照。
- `Unreal-3rd-Person-Parkour` 负责未来 C++ 化组织启发。
- `Learned-Motion-Matching` 只作为补充参考，不进入当前主线决策。
