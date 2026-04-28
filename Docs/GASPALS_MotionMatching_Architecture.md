# GASPALS 运动匹配 (Motion Matching) 架构分析报告

本报告详细解析了 **GASPALS (Game Animation Sample with ALS Overlays)** 项目中核心的运动匹配 (Motion Matching / Pose Search) 系统架构。该系统利用虚幻引擎 5 (UE5) 底层的 `PoseSearch` 插件，结合模块化的蓝图与叠加层 (Overlay) 架构，实现极其自然的移动表现。

---

## 1. 整体系统架构 (Architecture Overview)

GASPALS 采用了层次化的设计：底层使用 Motion Matching 处理基础移动与根运动，中层使用动作重定向 (Retargeting) 适配不同骨骼，顶层使用 ALS Overlay 系统处理上半身的姿态叠加。

```mermaid
graph TD
    %% Input Layer
    subgraph Input ["输入层 (Character Blueprint)"]
        A[玩家输入 (Player Input)] --> B[轨迹预测器 (Trajectory Component)]
        A --> C[移动组件 (Character Movement)]
    end

    %% State Layer
    subgraph State ["状态分发 (Chooser Tables)"]
        B --> D{Chooser Table (CHT_PoseSearchData)}
        C --> D
        D -- 蹲伏/行走/奔跑 --> E[Locomotion 数据库]
        D -- 起步/急停 --> F[Pivots 数据库]
        D -- 跳跃/空中 --> G[Jumps/Falls 数据库]
    end

    %% Database Layer
    subgraph Databases ["运动匹配核心 (Pose Search Databases)"]
        E --> H[PSD_Dense_LocoLoops]
        F --> I[PSD_Dense_Stand_Run_Pivots]
        G --> J[PSD_Dense_Jumps]
    end

    %% AnimBP Layer
    subgraph AnimBP ["动画图表 (AnimBP)"]
        H --> K((Motion Matching Node))
        I --> K
        J --> K
        K --> L[Inertialization 惯性混合]
        L --> M[Animation Warping 动作扭曲]
    end

    %% Overlay Layer
    subgraph Overlay ["ALS 叠加层 (Layer Blending)"]
        M --> N[基础姿态 (Base Pose)]
        O[Overlay 蓝图 (如 Rifle/Barrel)] --> P[上半身混合 (Blend per bone)]
        N --> P
    end

    P --> Q[Final Pose]

    style K fill:#ff9900,stroke:#333,stroke-width:4px
    style D fill:#66ccff,stroke:#333,stroke-width:2px
```

---

## 2. 核心算法解析与伪代码 (Algorithm Pseudo-code)

运动匹配的核心不在于“播放动画”，而在于**在每一帧，通过“代价函数 (Cost Function)”在数据库中寻找与当前状态和未来轨迹最匹配的动作帧**。

### 核心公式
$$ Cost = Cost_{Pose} + Cost_{Trajectory} $$
引擎会遍历选定 PSD 中的所有动画帧，选出 $Cost$ 最小的那一帧跳转过去。

### 算法伪代码 (结合 UE5 PoseSearch 逻辑)

```python
# 1. Trajectory Prediction (轨迹预测)
def UpdateTrajectory(CurrentTime, InputVector):
    # 根据玩家输入和当前加速度，预测未来 0.5s, 1s, 1.5s 的角色位置、朝向和速度
    PredictedTrajectory = PredictFutureStates(TimeSamples=[0.5, 1.0, 1.5])
    return PredictedTrajectory

# 2. Database Selection (状态分发)
def EvaluateChooserTable(CharacterState):
    if CharacterState.IsJumping:
        return Database_Jumps
    elif CharacterState.IsPivoting:
        return Database_Pivots
    else:
        return Database_Locomotion

# 3. Pose Search (运动匹配查找)
def FindBestPose(CurrentPose, PredictedTrajectory, ActiveDatabase):
    BestFrame = None
    MinCost = Infinity
    
    for AnimFrame in ActiveDatabase.GetAllFrames():
        # 1. 姿态惩罚：比较脚部位置、重心高度、当前速度等 (根据 Schema 定义)
        PoseCost = CalculateDifference(CurrentPose, AnimFrame.Pose) * Weight_Pose
        
        # 2. 轨迹惩罚：比较未来的运动轨迹是否吻合
        TrajectoryCost = CalculateDifference(PredictedTrajectory, AnimFrame.FutureTrajectory) * Weight_Trajectory
        
        # 3. 总体代价
        TotalCost = PoseCost + TrajectoryCost
        
        if TotalCost < MinCost:
            MinCost = TotalCost
            BestFrame = AnimFrame
            
    return BestFrame

# 4. 惯性混合与播放 (Inertial Blending)
def UpdateAnimation(DeltaTime):
    Database = EvaluateChooserTable(CurrentState)
    Trajectory = UpdateTrajectory(DeltaTime, Input)
    
    TargetFrame = FindBestPose(CurrentPose, Trajectory, Database)
    
    # 触发惯性混合，平滑过渡到新选出的帧
    BlendTo(TargetFrame, Method="Inertialization", BlendTime=0.2)
```

> [!TIP]
> **为什么要用 Chooser？**
> 虽然可以直接把所有动画放进一个巨型数据库，但代价函数计算会非常慢。GASPALS 使用了 `Chooser` 插件，先通过简单的条件（如角色处于空中还是地面）将搜索范围缩小到特定的 `PSD`，极大提高了搜索性能。

---

## 3. 资产索引与目录结构 (Asset Indexing)

要理解和修改 GASPALS，你需要知道不同类型的资产存放的具体位置：

### 📁 核心逻辑与组件
- **基础角色蓝图**: `Content/Blueprints/CBP_SandboxCharacter`
  *处理玩家输入、碰撞、移动组件配置以及更新轨迹信息。*
- **基础动画蓝图**: `Content/Blueprints/ABP_SandboxCharacter`
  *主控动画图表，包含了 Chooser Node 和 Motion Matching Node。*

### 📁 运动匹配数据 (Motion Matching Data)
路径：`Content/Characters/UEFN_Mannequin/Animations/MotionMatchingData/`

1. **Schemas (架构定义)**
   - 决定算法去匹配哪些骨骼。例如匹配左右脚踝（RightAnkle, LeftAnkle）以避免滑步，匹配 Root 的线速度和角速度等。
2. **Pose Search Databases (PSD)**
   - **`PSD_Dense_Idles` / `PSD_Dense_LocoLoops`**：包含高密度的常态行走、奔跑动画切片。
   - **`PSD_Dense_Stand_Run_Pivots`**：包含急停、折返跑的动作切片。
   - **`PSD_Sparse_...`**：稀疏数据库，通常用于动作幅度大、不需要精细轨迹匹配的过渡动作。
3. **Choosers (CHT 选择器表)**
   - **`CHT_PoseSearchData`**：核心的路由表。它就像一组 IF-ELSE 规则，决定当前帧使用哪个 PSD。

### 📁 叠加层系统 (ALS Overlay System)
路径：`Content/OverlaySystem/`
- **层混合动画图表**: `ABP_LayerBlending` 负责将叠加层的姿势应用到底层移动上。
- **具体的 Overlay (姿势/武器)**: 
  - `Overlays/Poses/Rifle/ABP_Overlay_Rifle` (持步枪姿态)
  - `Overlays/Poses/Box/ABP_Overlay_Box` (抱箱子姿态)
  *这些蓝图并不包含移动逻辑，只包含上半身的覆盖动画。*

---

## 4. 使用与扩展指南 (Usage Guide)

### 💡 场景 1: 如何添加一套全新的移动动画（如：受伤瘸腿移动）

1. **导入动画序列 (AnimSequence)**
   将受了伤的行走、跑步、待机动画导入项目中。
2. **创建/复用 Schema**
   使用现有的标准 Locomotion Schema，确保它追踪了脚踝和骨盆的速度。
3. **创建新的 Pose Search Database (PSD)**
   - 右键创建新的 `PoseSearch Database`，命名为 `PSD_Injured_Locomotion`。
   - 将你的受伤动画序列拖入其中。
   - 打开 PSD，点击顶部的 **Build** 生成轨迹特征数据。
4. **修改 Chooser 表**
   - 打开 `CHT_PoseSearchData`。
   - 添加一个条件行（如 `CharacterState.IsInjured == True`）。
   - 将该行返回的资源指向你刚创建的 `PSD_Injured_Locomotion`。

### 💡 场景 2: 如何添加一个新的上半身武器姿态（如：双持冲锋枪）

由于项目引入了 ALS 风格的 Overlay 系统，你**不需要**重新制作带有双持冲锋枪的跑步动画。
1. **复制现有 Overlay**：进入 `Content/OverlaySystem/Overlays/Poses/`，复制 `ABP_Overlay_Pistol1H`，重命名为 `ABP_Overlay_DualSMG`。
2. **替换姿态**：在你的新 Overlay 蓝图中，替换持枪的基础闲置动作 (Idle Pose)。
3. **设置角色状态**：在角色蓝图或输入逻辑中，调用设置 Overlay 状态的函数，将当前 Overlay 切换为 `DualSMG` 即可。底层的运动匹配会继续用原有的腿部动作跑动，而上半身会自动混合双持的姿态。

---
**版本说明**：本报告基于 UE 5.4+ 的原生 Motion Matching 功能编写，所有引用路径均基于 GASPALS 主分支当前结构。
