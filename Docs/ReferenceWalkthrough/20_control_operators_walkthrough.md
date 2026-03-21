# Control Operators Walkthrough

## 1. 这是什么

这是 `References/ControlOperators` 的 paper-driven walkthrough。它不是 Unreal 运行时本体，而是一个把 control schema、control encoder 和 flow-matching controller 放进 Python demo 的参考实现。

对 GASPALS 来说，这个仓最重要的不是 raylib viewer，而是：

- control schema 如何定义
- training controls 如何从动作数据集构造
- runtime controls 如何从游戏输入构造

## 2. 指导源是什么（thesis / paper / blog / README / code）

- 标签：`PAPER_DRIVEN`
- 本轮主读材料：
  - `References/ControlOperators/README.md`
  - `https://theorangeduck.com/page/control-operators-interactive-character-animation`
  - `https://theorangeduck.com/page/implementing-control-operators`
  - `References/ControlOperators/control_operators.py`
  - `References/ControlOperators/control_encoder.py`
  - `References/ControlOperators/controller.py`
  - `References/ControlOperators/train.py`

## 3. 仓库最小运行目标

本仓的最小目标锁定为 `trajectory` 控制案例，而不是 `velocity_facing`：

- 原因 1：`trajectory` 和 GASPALS 当前 `control_to_lmm/v1` 契约最接近。
- 原因 2：`UberControlEncoder` 已经把 `trajectory` 固定成 3 个 future samples，正好对应 `20/40/60` 帧。
- 原因 3：这条路径最容易映射到 UE 蓝图/Shadow log 的未来轨迹载荷。

最小可运行目标分两层：

1. 标准路径：
   - `uv sync`
   - 准备 `data/lafan1_resolved/*`
   - `uv run controller.py`
2. 训练路径：
   - `uv run train.py`
   - 由 `train.py` 自动下载 `lafan1-resolved` 并训练 autoencoder + control model

## 4. 实际执行步骤

本轮已经实际完成的步骤：

1. 静态阅读：
   - `control_operators.py`
   - `control_encoder.py`
   - `gameplay_input.py`
   - `controller.py`
   - `train.py`
2. 环境确认：
   - `uv.exe` 本机可用
   - `python --version` 为 `3.13.5`
3. blocker 确认：
   - 当前 base Python 缺失 `torch`、`raylib`、`pyray`
   - 工作区内没有 `data/lafan1_resolved/`
   - `controller.py` 要求以下文件齐备，否则退回 bind pose mode：
     - `autoencoder.ptz`
     - `database.npz`
     - `X.npz`
     - `Z.npz`
     - `UberControlEncoder/controller.ptz`
4. 训练路径事实确认：
   - `train.py` 内部 `ensure_lafan1(...)` 会自动下载 `https://theorangeduck.com/media/uploads/Geno/lafan1-resolved/bvh.zip`
   - `args.output_dir` 会把阶段性模型写到 `outputs/<RUN_NAME>/models/`
   - 正式 controller 权重会写到 `data/lafan1_resolved/UberControlEncoder/controller.ptz`

如果现在继续最小验证，推荐命令是：

```powershell
uv sync
uv run train.py --niterations 1000 --batch_size 64 --device cpu --expr_name smoke
```

如果只想跑 viewer，需要先满足 README 的 demo 数据布局，再执行：

```powershell
uv run controller.py
```

## 5. 关键输入 / 输出

### 输入

- 运行时输入：
  - `GameplayInput.gamepad_stick_left`
  - `GameplayInput.gamepad_stick_right`
  - `GameplayInput.current_position`
  - `GameplayInput.current_rotation`
  - `GameplayInput.current_velocity`
  - `GameplayInput.current_angular_velocity`
- 训练数据：
  - `data/lafan1_resolved/database.npz`
  - `data/lafan1_resolved/X.npz`
  - `data/lafan1_resolved/Z.npz`

### 中间产物

- `data/lafan1_resolved/autoencoder.ptz`
- `data/lafan1_resolved/X.npz`
- `data/lafan1_resolved/Z.npz`

### 最终控制模型

- `data/lafan1_resolved/UberControlEncoder/controller.ptz`

### runtime control payload

- `('uncontrolled', None)`
- `('velocity_facing', {...})`
- `('trajectory', [ {location, direction}, ... ])`

## 6. 关键源码入口

### 论文思想层

- `control_operators.py`
  - `ControlOperator`
  - `And`
  - `Or`
  - `FixedArray`
  - `Optional`
  - `Encoded`

这部分定义的是 control schema algebra，不是某个特定游戏项目的输入实现。

### 标准 encoder 入口

- `control_encoder.py`
  - `ControlEncoderBase.build_control_schema(...)`
  - `ControlEncoderBase.training_controls(...)`
  - `ControlEncoderBase.runtime_controls(...)`
  - `UberControlEncoder.build_control_schema(...)`
  - `UberControlEncoder.training_controls(...)`
  - `UberControlEncoder.runtime_controls(...)`

`UberControlEncoder.build_control_schema(...)` 当前固定为三种模式：

- `uncontrolled`
- `velocity_facing`
- `trajectory`

`trajectory` 的 shape 是固定长度 3 的 `FixedArray`，每个元素都包含：

- `location`
- `direction`

### 最小 trajectory 案例的关键路径

- runtime 输入解释：
  - `gameplay_input.py`
  - `movement_direction_world`
  - `facing_direction_world`
  - `root_acceleration`
- trajectory 生成：
  - `UberControlEncoder.runtime_controls(...)`
  - `trajectory_spring_position(...)`
  - `trajectory_spring_rotation(...)`
  - `Ttimes = np.array([20, 40, 60]) / 60.0`

### Python demo 层

- `controller.py`
  - 加载模型与数据库
  - 缺文件时切回 bind pose
  - 有文件时走 `GameplayInput -> control_encoder -> denoiser -> decoder`
- `train.py`
  - `ensure_lafan1(...)`
  - autoencoder 训练
  - flow-matching controller 训练

## 7. 它在 GASPALS 联合架构中的位置

它是 GASPALS 联合架构中的 control contract 上游，不是宿主运行时：

- 对 `Docs/DataContract_Control_to_LMM.md` 的直接价值：
  - control mode vocabulary
  - trajectory payload shape
  - future horizon 语义
- 对 `Docs/RuntimeInsertionPoints.md` 的直接价值：
  - 告诉我们 Shadow log 里必须采哪些输入字段，才能重建 `trajectory` controls

应把它视为：

- GASPALS input/trajectory sampling 的 schema 参考
- future encoder layer 的算法参考

不应把它视为：

- UE runtime drop-in
- gameplay framework reference

## 8. 未来是否适合作为

| 用途 | 结论 | 原因 |
| --- | --- | --- |
| Shadow Mode 输入层 | 非常适合 | `GameplayInput` 与 `UberControlEncoder.runtime_controls(...)` 给出了输入采样到 canonical control payload 的直接映射。 |
| LMM 替换点 | 不适合 | 它不解决 UE 动画图、模型消费或 pose reconstruction。 |
| Control Operators 编码层 | 非常适合 | 这正是本仓的主价值。 |
| C++ 重构模板 | 不适合 | Python + raylib demo 不是 GASPALS 宿主 runtime template。 |

## 9. 当前不建议做的事情

- 不要优先做 `velocity_facing`；当前 GASPALS 对齐面应该先锁 `trajectory`。
- 不要把 `controller.py` 的 raylib viewer 当成 UE 接入模板。
- 不要把 `UberControlEncoder` 的输出直接塞进 GASPALS 运行时，而不先经过 `control_to_lmm/v1` 契约冻结。
- 不要在还没完成 Shadow log 采样前就去训练正式 controller 模型。

## 10. 下一步建议

1. 在 `Tools/export/` 下实现一个 GASPALS shadow log 到 `trajectory` payload 的导出器。
2. 导出 shape 必须与 `UberControlEncoder.runtime_controls(...)` 对齐：
   - 3 个 future samples
   - 每个 sample 都含 `location` 和 `direction`
3. 之后再决定是否需要补一个最小 smoke 训练：
   - `uv run train.py --niterations 1000 --device cpu`
4. 在 GASPALS 正式侧，先落 schema 和日志字段，不要先落 live inference。
