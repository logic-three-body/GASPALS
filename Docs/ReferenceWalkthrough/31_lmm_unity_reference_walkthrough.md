# Learned-Motion-Matching Unity Reference Walkthrough

## 1. 这是什么

这是 `References/Learned-Motion-Matching` 的算法参考 walkthrough。它的定位是“Unity 提取 + PyTorch 训练 + ONNX/Barracuda 推理”的另一条 LMM 参考系，而不是 UE 接入模板。

## 2. 指导源是什么（thesis / paper / blog / README / code）

- 标签：`PAPER_DRIVEN`
- 本轮主读材料：
  - `References/Learned-Motion-Matching/README.md`
  - Ubisoft La Forge paper: `https://dl.acm.org/doi/10.1145/3386569.3392440`
  - `References/Learned-Motion-Matching/decompressor.py`
  - `References/Learned-Motion-Matching/projector.py`
  - `References/Learned-Motion-Matching/stepper.py`
  - `References/Learned-Motion-Matching/misc/CustomFunctions.py`
  - `References/Learned-Motion-Matching/misc/NNModels.py`

## 3. 仓库最小运行目标

当前最小目标不是重建 Unity sample project，而是走通这条两段式流程的语义：

```text
Unity 提取
-> XData.txt / YData.txt / HierarchyData.txt
-> PyTorch 训练
-> ZData.txt / YtxyData.txt / QtxyData.txt
-> ONNX 导出
-> Unity Barracuda 推理
```

在当前工作区里，最小“可走通”目标是：

- 确认仓库已经带了 `database/*.txt`
- 确认仓库已经带了 `onnx/*.onnx`
- 解释训练脚本如何从文本数据产生这些产物

## 4. 实际执行步骤

本轮已经实际完成的步骤：

1. 阅读：
   - `README.md`
   - `decompressor.py`
   - `projector.py`
   - `stepper.py`
   - `misc/CustomFunctions.py`
   - `misc/NNModels.py`
2. 资产确认：
   - `database/HierarchyData.txt`
   - `database/XData.txt`
   - `database/YData.txt`
   - `database/ZData.txt`
   - `onnx/compressor.onnx`
   - `onnx/decompressor.onnx`
   - `onnx/projector.onnx`
   - `onnx/stepper.onnx`
3. blocker 确认：
   - 当前工作区没有 Unity sample project
   - 当前 base Python 缺少 `torch`
   - `misc/NNModels.py` 里直接写了 `device = torch.device("cuda")`，说明脚本更偏实验性质

因此本轮不尝试重新训练，只保留 artifact walkthrough。

## 5. 关键输入 / 输出

### Unity 侧输入

- `XData.txt`
  - 特征向量文本
- `YData.txt`
  - pose 信息文本
- `HierarchyData.txt`
  - 骨骼层级文本

### PyTorch 侧中间产物

- `database/YtxyData.txt`
- `database/QtxyData.txt`
- `database/ZData.txt`

### ONNX 输出

- `onnx/compressor.onnx`
- `onnx/decompressor.onnx`
- `onnx/projector.onnx`
- `onnx/stepper.onnx`

### Unity 侧最终消费

- README 说明目标目录是 Unity 的：
  - `/Assets/Motion Matching/ONNX`
  - `/Assets/Motion Matching/Database`

## 6. 关键源码入口

### 数据读写与 FK 工具

- `misc/CustomFunctions.py`
  - `LoadData(...)`
  - `Quat_ForwardKinematics(...)`
  - `Xform_ForwardKinematics(...)`
  - `to_xform_xy(...)`
  - `from_xy(...)`

### decompressor 路径

- `decompressor.py`
  - 读取 `XData`, `YData`, `HierarchyData`
  - 计算 character-space / two-column rotation 表示
  - 训练 `Compressor` 与 `Decompressor`
  - 写出：
    - `database/YtxyData.txt`
    - `database/QtxyData.txt`
    - `database/ZData.txt`
    - `onnx/compressor.onnx`
    - `onnx/decompressor.onnx`

### stepper 路径

- `stepper.py`
  - 输入 `XData + ZData`
  - 学习 `X` 与 `Z` 的时间导数
  - 导出 `onnx/stepper.onnx`

### projector 路径

- `projector.py`
  - 输入 noisy feature `Xhat`
  - 用 `BallTree` 找最近邻监督
  - 学习 `X -> (X, Z)` 的投影器
  - 导出 `onnx/projector.onnx`

### 网络定义

- `misc/NNModels.py`
  - `Compressor`
  - `Decompressor`
  - `Stepper`
  - `Projector`

## 7. 它在 GASPALS 联合架构中的位置

它在 GASPALS 联合架构中属于“替代算法参考系”：

- 与 `Motion-Matching` 相比：
  - 这里更像 Unity/PyTorch/ONNX 的实验线
- 与 `Learned_Motion_Matching_Training` 相比：
  - 这里给出另一套 artifact vocabulary，但不是当前 UE 接入主线
- 与 GASPALS 的关系：
  - 主要用来校验 LMM 的模型职责划分是否一致
  - 不用来指导 UE 运行时接线

## 8. 未来是否适合作为

| 用途 | 结论 | 原因 |
| --- | --- | --- |
| Shadow Mode 输入层 | 不适合 | 它不处理宿主输入采样，也不定义 control contract。 |
| LMM 替换点 | 间接适合 | `decompressor/projector/stepper` 的职责划分和 ONNX 导出可作为参考。 |
| Control Operators 编码层 | 不适合 | 完全不涉及 control schema。 |
| C++ 重构模板 | 不适合 | 这是 Unity + PyTorch + Barracuda 路线。 |

### 值得在 UE 里借鉴的思路

- 明确把模型分成：
  - `compressor/decompressor`
  - `projector`
  - `stepper`
- 用文本/中间文件明确数据边界
- ONNX 作为推理交换格式

### 可以直接忽略的部分

- Barracuda 运行时细节
- Unity Inspector 里的提取按钮工作流
- `device = cuda` 的硬编码实验脚本风格

## 9. 当前不建议做的事情

- 不要把它当成 UE 接入模板。
- 不要在缺失 Unity sample project 的情况下，试图先恢复整套 Unity 流水线。
- 不要把这里的文本数据格式直接当成 GASPALS 未来正式数据合同。

## 10. 下一步建议

1. 只把它作为“LMM 模型职责和 artifact vocabulary”的对照仓。
2. 对照项优先级：
   - `decompressor/projector/stepper` 职责边界
   - `ZData` 的语义
   - ONNX 导出方式
3. 真正的 UE 侧接入和训练链路仍以：
   - `10_lmm_training_pipeline.md`
   - `11_lmm_ue5_thesis_walkthrough.md`
   为主。
