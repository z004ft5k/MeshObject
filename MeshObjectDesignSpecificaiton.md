# Design Specification

NEUE

Design Specification for [Mesh Object]  
[Project ID]

重庆诺源工业软件科技有限公司  
2026年07月07日  
版本：V1.1

## Revision History

| 版本 | 日期 | 说明 |
|---|---|---|
| V1.0 | 2026-07-02 | 初版整理，结合现有讨论形成 MeshObject 设计方案 |
| V1.1 | 2026-07-07 | 补充 Meshes 节点归属（`eMeshesType`）；同步 §5.3/§5.4；对齐飞书 FS 术语 |

## 1. Introduction

### 1.1 项目背景

当前 NeueCAX 底层模型层尚未建立完整的 MeshObject 概念。网格数据主要以分散的节点、单元及相关底层存储结构存在，缺少一个能够被 Navigator 直接识别和展示的逻辑对象。因此，用户虽已具备网格创建能力，但在 Navigator 中仍无法以 Mesh 节点的形式查看、组织和操作对应网格对象。

本项目的目标是完成产品阶段一和阶段二的能力，即在现有底层模型基础上引入 MeshObject 概念，使 Navigator 能显示 MeshObject 节点，并支持基础操作，如 Info、Rename、Delete 和 Show-Hide。

### 1.2 设计目标和范围

1. 在 Src Layer 中建立 MeshObject 的数据模型、持久化结构和运行时管理机制。
2. 在 Entity 层建立对 MeshObject 的对象化封装，为上层提供稳定的访问与操作能力。
3. 明确 UI 层、Entity 层和 Src Layer 的职责划分与调用关系，为 Navigator 集成提供清晰边界。
4. 支持几何 Keep 和手工创建两类 MeshObject 来源，并保证 Save/Open 后数据可恢复。

### 1.3 产品阶段范围

#### 阶段一

- 几何 Keep 成功后自动创建 MeshObject
- Navigator 支持显示 MeshObject 节点
- Navigator 支持基础操作：Info / Rename / Delete / Show-Hide

#### 阶段二

- 手工创建节点、单元完成后，也可形成 MeshObject

## 2. Overview

### 2.1 用例分析

本设计围绕以下两类核心场景展开：

1. 用户通过几何 Keep 生成网格后，系统自动创建 MeshObject，并在 Navigator 中显示对应 Mesh 节点。
2. 用户通过手工方式创建节点、单元后，系统在一次操作完成时创建对应 MeshObject，并纳入统一管理。

在这两类场景下，用户后续都应能够在 Navigator 中对 MeshObject 执行查看信息、重命名、删除和显示控制等操作。

### 2.2 整体设计思路

本设计采用分层方式引入 MeshObject 能力：

- 在 Src 层中建立 MeshObject 的底层真相，包括运行时对象、持久化结构、成员归属字段和恢复机制。
- 在 Entity 层中对 MeshObject 进行对象化封装，向上提供稳定接口，屏蔽底层存储细节。
- 在 UI 层中将 MeshObject 作为 Navigator 节点展示，并通过 Entity 层完成操作转发。

整体原则如下：

1. `element.iMeshObjectId` 是成员关系唯一真相。
2. MeshObject 元数据与 component 列表独立持久化，不在 element 层重复保存成员列表。
3. UI 层不直接依赖持久化结构和底层存储接口。
4. 运行时缓存可重建，持久化数据应与 Save/Open 流程一致。

### 2.3 设计任务分解

| 任务 | 设计内容 |
|---|---|
| 数据模型设计 | 定义 MOHeapRecord、`element.iMeshObjectId`、component 列表等核心数据 |
| MeshObjectId 管理设计 | 定义 `femmgMeshObjectIdManager` 的职责与分配规则 |
| 持久化设计 | 设计 MOHEAP、MOTREE 和变长 record 布局；`femdaMOFSIProxy` 负责 FSI 读写 |
| 运行时管理设计 | 定义 `femmgMeshObjectManager` 的职责和运行时缓存 |
| Entity 封装设计 | 提供对象化接口，承接 UI 层调用 |
| Navigator 集成设计 | 定义 Mesh 节点显示和操作入口 |
| 生命周期设计 | 定义 Create、Delete、Save、Open 等主流程 |

### 2.4 Terminology

| 术语 | 说明 |
|---|---|
| MeshObject | 逻辑概念名称 |
| Mesh | UI 中的显示名称（单个 MeshObject 节点） |
| Meshes 节点 | Navigator 中按维度组织的逻辑容器：`1D Meshes` / `2D Meshes` / `3D Meshes` / `Others Meshes` |
| `eMeshesType` | MeshObject 归属的 Meshes 类型，Create 时写入 MOHEAP，Rename 不改变 |
| MeshObjectRecord | Src Layer 中的运行时 struct |
| MeshObject Entity | Entity 层对象封装 |
| femmgMeshObjectManager | Fem 级 MeshObject 管理器 |
| element.iMeshObjectId | 成员归属字段 |

## 3. High Level Design

### 3.1 架构层次

本设计采用三层结构：

1. **UI 层**：负责 Navigator 节点显示和用户交互。
2. **Entity 层**：负责 MeshObject 的对象化封装，向 UI 层暴露稳定能力。
3. **Src 层**：负责底层数据模型、持久化、成员关系与运行时恢复。

### 3.2 核心语义

- 一次 Keep 生成的一组单元对应一个 MeshObject。
- 一次手工创建完成的一组节点、单元也对应一个 MeshObject。
- 一个 element 最多归属一个 MeshObject。
- `element.iMeshObjectId` 是成员归属唯一真相。
- Preview 不创建 MeshObject，只有 Keep 成功后才创建。
- `pComps` 非空表示几何 Keep 来源，`pComps` 为空表示手工创建来源。

### 3.3 核心数据结构

#### 3.3.1 Src 层运行时对象

```cpp
enum femmgMeshObjectMeshesType
{
    FEMMG_MO_MESHES_1D     = 1,
    FEMMG_MO_MESHES_2D     = 2,
    FEMMG_MO_MESHES_3D     = 3,
    FEMMG_MO_MESHES_OTHERS = 4
};

struct MeshObjectRecord
{
    int                       iMeshObjectId;
    char                      szDisplayName[128];
    int                       nCmp;
    fgm_TzCmp*                pComps;
    femmgMeshObjectMeshesType eMeshesType;
};
```

其中：

- `iMeshObjectId`：MeshObject 标识
- `szDisplayName`：显示名称
- `pComps`：几何关联 component 列表
- `eMeshesType`：归属的 Meshes 类型（`1D` / `2D` / `3D` / `Others`），Create 时确定并持久化

#### 3.3.2 Src 层运行时缓存

```cpp
class femmgMeshObjectManager
{
private:
    std::map<int, MeshObjectRecord> m_MOIdToRecordMap;
    std::map<int, int>              m_MOIdToElementCountMap;
    // 可选，整包删除
    // std::map<int, std::vector<int>> m_MOIdToElementPtrs;
};
```

- `m_MOIdToRecordMap`：按 MOId 管理全部 `MeshObjectRecord`
- `m_MOIdToElementCountMap`：按 MOId 缓存 element 数量

#### 3.3.3 MeshObjectId 管理器

```cpp
class femmgMeshObjectIdManager
{
public:
    void InitFromRecords(const std::map<int, MeshObjectRecord>& records);
    int  GetCurrentMeshObjectId() const;

private:
    // 仅 femmgMeshObjectManager 可调用
    int  Allocate();
    int  m_iCurrentMeshObjectId;
};
```

- `femmgMeshObjectIdManager` 挂在 `femmgModel` 下，与 `femmgMeshObjectManager` 并列
- `0` 保留为未归属
- MOId 从 `1` 开始单调递增
- `GetCurrentMeshObjectId()` 与 `Allocate()` 分离：取 Id 与消耗 Id 各司其职

#### 3.3.4 element 归属字段

`element.iMeshObjectId` 作为 element 的正式字段：

- 存放于 `femElem`
- 位于 `iADPtr` 后
- 存放于 EHEAP common 区
- 由调用方在 `ElmAdd` 前填写，取值来自 `femmgMeshObjectIdManager::GetCurrentMeshObjectId()`

### 3.4 各层职责

#### UI 层

- 显示 MeshObject 节点
- 响应 Info、Rename、Delete、Show-Hide
- 不处理底层持久化和成员关系

#### Entity 层

- 对 MeshObject 进行对象化封装
- 对外暴露名称、components、element 数量等能力
- 将操作委托给 `femmgMeshObjectManager`

#### Src 层

- 管理 `MeshObjectRecord`
- 负责 Create / Delete / Rename / LoadFromFSI
- 维护 `m_MOIdToRecordMap` 和 `m_MOIdToElementCountMap`
- 负责 MeshObjectId 分配，`femmgMeshObjectIdManager.Allocate()`
- 协调持久化与运行时恢复

## 4. Detailed Design

### 4.1 Src 层设计

#### 4.1.1 管理器职责

`femmgMeshObjectManager` 是 Fem 级 MeshObject 业务入口，负责：

- 管理全部 `MeshObjectRecord`
- 创建、删除、重命名 `MeshObjectRecord`
- 维护持久化读写
- 维护运行时 element 数量缓存
- 在 Open 后恢复运行时状态

设计原则如下：

- 不引入单独的 `femmgMeshObject` 底层 class
- 所有对象级操作先集中在 `femmgMeshObjectManager`
- `m_MOIdToElementCountMap` 是运行时缓存，不是成员关系真相

`Create` 接口：

```cpp
femStatus Create(const char* pszDisplayName, const fgm_TzCmp* pComps, int nCmp);
```

- 调用方传入名称和 component 列表；手工建网时 `pComps = nullptr`、`nCmp = 0`
- `iMeshObjectId` 在 `Create` 内部通过 `GetCurrentMeshObjectId()` 获取，不由调用方传入
- `Create` 成功后内部调用 `Allocate()` 推进 Id 计数器

#### 4.1.2 FSI 访问层：femdaMOFSIProxy

`femdaMOFSIProxy` 位于 `femda` 层，专门封装 MeshObject 相关的 FSI 操作，职责类比 `femdaAccFSIProxy` 之于 EHEAP。

**定位**

- Fem 级，由 `femmgMeshObjectManager` 持有并调用
- 只负责 `MOHEAP` / `MOTREE` 的打开、读写与关闭
- 不管理 MOId 分配，不维护 element 归属

```cpp
class femdaMOFSIProxy
{
public:
    femdaMOFSIProxy(int hDb, int femId);
    ~femdaMOFSIProxy();

    void AddMeshObject(MeshObjectRecord& meshObj);
    void GetAllMeshObjects(std::vector<MeshObjectRecord>& meshObjs);

private:
    int m_hDb;
    int m_iFemId;
    int m_moHeapSegId;
    int m_moTreeSegId;
    int m_hMOHeap;
    int m_hMOTree;
};
```

**构造与析构**

构造时：

1. 通过 `stbidf` 从 FEM Record Field 2 获取 `MOHEAP`、`MOTREE` 段 ID
2. `fsihpop` 打开 `MOHEAP`，`fsitrop` 打开 `MOTREE`

析构时：

1. `fsihpcl` 关闭 `MOHEAP`
2. `fsitrcl` 关闭 `MOTREE`

**AddMeshObject**

写入一条 MeshObject 记录到持久化层：

1. 计算变长 record 大小（`iMeshObjectId`、名称长度、名称字符串）
2. `fsihpal` 在 `MOHEAP` 分配 record
3. `fsihpio` 写入 record 内容
4. `fsitrad` 在 `MOTREE` 建立 `iMeshObjectId → record` 索引

**GetAllMeshObjects**

从持久化层读取全部 MeshObject：

1. `fsitrpc` / `fsitric` 遍历 `MOTREE`
2. 按 record 指针从 `MOHEAP` 读取数据（`fsihpio`）
3. 反序列化为 `MeshObjectRecord` 并返回

#### 4.1.3 MeshObjectId 管理器职责

`femmgMeshObjectIdManager` 是 Fem 级 MeshObjectId 分配器，负责：

- 在 Open 后根据已有 `MeshObjectRecord` 初始化 `m_iCurrentMeshObjectId`
- 在 Keep、Manual Mesh、AFEM 合成等场景分配新的 MeshObjectId
- 为 Fortran / C 桥提供 `GetCurrentMeshObjectId` 支撑

**初始化规则**

```text
Open Fem:
  读取全部 MeshObjectRecord
  m_iCurrentMeshObjectId = max(iMeshObjectId) + 1
  若没有 record，则 m_iCurrentMeshObjectId = 1
```

**取 Id 与推进规则**

```text
GetCurrentMeshObjectId():
  返回当前 m_iCurrentMeshObjectId（只读，不修改）

// Private，仅 femmgMeshObjectManager 可调用
Allocate():
  m_iCurrentMeshObjectId++（在 Create() 成功后调用）
```

Fortran / Keep 路径：

```c
GetCurrentMeshObjectId(hDb, femId, &moId);
```

#### 4.1.4 AFEM 合成与 MOId 重分配

当多个 FEM 合成一个 AFEM 时，AFEM 需要建立独立的 MOId 空间，并对来源 MeshObject 重新分配 MOId。

```text
FEM-A: MO #1, #2
FEM-B: MO #3
        ↓
AFEM:  MO #1, #2, #3（AFEM 自己的 Id 空间）
```

处理原则：

1. AFEM 拥有独立的 `femmgMeshObjectIdManager`
2. 从每个源 FEM 复制 `MeshObjectRecord` 时，为 AFEM 分配新的 MOId
3. 维护 remap 关系：`(sourceFemId, oldMOId) -> newMOId`
4. 拷贝 element 到 AFEM 时，按 remap 更新 `element.iMeshObjectId`

#### 4.1.5 成员关系恢复

Open 后，通过扫描全部 element，根据 `element.iMeshObjectId` 重建：

- MeshObject 的运行时成员关系
- `m_MOIdToElementCountMap` 缓存

因此，运行时缓存可丢失，但成员关系不能脱离 element 层单独定义。

### 4.2 Entity 层设计

#### 4.2.1 角色定位

Entity 层用于对 `MeshObjectRecord` 进行对象化封装。它不是新的数据真相来源，而是面向 UI 和上层逻辑提供统一对象语义。

#### 4.2.2 典型能力

Entity 层支持以下能力：

- Create
- Rename
- Delete
- GetName
- GetComponents
- GetElementCount
- GetMeshesType

其中，具体实现最终由 `femmgMeshObjectManager` 提供支撑。

### 4.3 UI / Navigator 集成设计

#### 4.3.1 节点树结构

Navigator 中 MeshObject 按 Meshes 类型组织，**Fem 直接挂 Meshes 节点**（无额外 `Meshes` 父级）：

```text
Fem
├── 1D Meshes          （无 Mesh 时可隐藏）
├── 2D Meshes
├── 3D Meshes
├── Others Meshes
│   └── Mesh           （MeshObject，显示名 szDisplayName）
```

- Meshes 节点为**逻辑容器**，用户不可新建 / 删除 / 重命名
- UI 显示名使用 `1D Meshes`、`2D Meshes` 等；规格与代码中使用 `eMeshesType` 标识归属
- Navigator 构建：`QueryAllMeshObjects()` → 按 `eMeshesType` 分组 → 某类无 Mesh 时隐藏对应 Meshes 节点

#### 4.3.2 节点显示

- Mesh 节点显示名称来自 `MeshObjectRecord.szDisplayName`
- Mesh 归属的 Meshes 类型来自 `MeshObjectRecord.eMeshesType`（Information 中展示为 Meshes / Dimension）

#### 4.3.3 Meshes 归属规则

| 规则 | 说明 |
|---|---|
| Create 时确定 | `eMeshesType` 在 `Create()` 成功时写入，持久化到 MOHEAP |
| Rename 不改变 | 重命名只改 `szDisplayName`，`eMeshesType` 不变 |
| element 变化不改变 | Remesh、部分删 element 等不导致 Mesh 在 Meshes 节点间迁移 |
| 几何 Keep | 依据 Define Mesh / 划分设置的主维度或单元族判定（Beam→1D，Shell→2D，Solid→3D） |
| 手工建网 | 依据本次归属 element 的主维度；混合维度归入 `Others` |
| 无法判定 | 默认 `FEMMG_MO_MESHES_OTHERS` |

#### 4.3.4 用户操作

Navigator 对 MeshObject 节点提供以下操作：

- Info
- Rename
- Delete
- Show-Hide

其中：

- Info / Rename / Delete 通过 Entity 层转发到底层
- Show-Hide 保留为产品行为，本设计不进一步下沉为 Manager 核心 API

### 4.4 Persistence Design

#### 4.4.1 持久化结构

MeshObject 持久化采用：

- `MOHEAP`
- `MOTREE`

二者位于 FEM Record 的第二个 Field 中。

#### 4.4.2 持久化原则

- `MeshObjectRecord` 不是原样落盘结构
- 持久化使用变长 record
- `MOTREE` 负责 `iMeshObjectId -> record` 的索引
- `element.iMeshObjectId` 随 EHEAP 持久化

#### 4.4.3 MOHEAP record 布局

每条 MOHEAP record 至少包含：

- `iMeshObjectId`
- 名称信息
- `eMeshesType`
- `nCmp`
- `fgm_TzCmp[]`

其中每个 `fgm_TzCmp` 记录：

- `eCmpTyp`
- `iCmpId`
- `iNlId`

### 4.5 Lifecycle Design

#### 4.5.1 Geometry Keep

几何 Keep 成功后：

1. 本次新生成 element 在 `ElmAdd` 前写入 `iMeshObjectId = GetCurrentMeshObjectId()`
2. `femmgMeshObjectManager.Create(name, pComps, nCmp)`（内部获取 MOId、判定 `eMeshesType` 并调用 `Allocate()`）
3. Navigator 中对应 Meshes 节点下出现新 Mesh 节点（原先隐藏的 Meshes 节点变为可见）

#### 4.5.2 Manual Mesh

手工创建路径中：

1. 创建 element 时由调用方填写 `elem.iMeshObjectId = GetCurrentMeshObjectId()`
2. 一次手工建网操作完成时，调用 `Create(name, nullptr, 0)`
3. `Create` 内部获取 MOId、判定 `eMeshesType`、组装 record 并调用 `Allocate()`

#### 4.5.3 Delete Mesh

Delete Mesh 分为两条路径：

**几何 Keep 类型**

若 `pComps` 非空，则基于 `pComps` 调用现有几何删除接口。

**手工类型**

若 `pComps` 为空，则基于 `element.iMeshObjectId` 找出归属 element 并执行删除。

**一致性原则**

Delete Mesh 是复合操作。仅在底层 element 或 geometry 删除成功后，才完成对应 MeshObject 元数据移除；若底层删除失败，则保留 MeshObject 元数据。

#### 4.5.4 空 Mesh 自动删除

若 element 删除后某个 MeshObject 不再拥有任何归属 element，则应自动删除该 MeshObject 的运行时对象和持久化记录。

#### 4.5.5 Save / Open

**Save**

- 保存 `MeshObjectRecord` 元数据与 `pComps` 到 `MOHEAP`
- 保存 `iMeshObjectId -> record` 索引到 `MOTREE`
- 保存 EHEAP 中的 `element.iMeshObjectId`

**Open**

- 从 `MOHEAP` / `MOTREE` 恢复全部 `MeshObjectRecord`
- 调用 `femmgMeshObjectIdManager.InitFromRecords()` 初始化 MOId 分配器
- 扫描全部 element
- 根据 `element.iMeshObjectId` 重建运行时关系和 `m_MOIdToElementCountMap`

## 5. User Case

### 5.1 打开 mf1

```text
用户选择 mf1 文件
    ↓
打开 Fem（OpenModel）：
    ① femmgMeshObjectManager 构造函数
         - femdaMOFSIProxy->GetAllMeshObjects()
         - 经 MOTREE 遍历 MOHEAP，反序列化为 MeshObjectRecord
         - 写入 m_MOIdToRecordMap
    ② femmgMeshObjectIdManager.InitFromRecords(m_MOIdToRecordMap)
         - m_iCurrentMeshObjectId = max(iMeshObjectId) + 1
         - 若无 record，则 m_iCurrentMeshObjectId = 1
    ③ 扫描全部 element（ElmCreateIter）
         - 读取 element.iMeshObjectId
         - 累加 m_MOIdToElementCountMap
    ④ 一致性校验
    ↓
Entity 构建 MeshObjectEntity 对象视图
    ↓
Navigator 按 eMeshesType 分组刷新：Fem → 1D/2D/3D/Others Meshes → Mesh
```

### 5.2 创建

#### 5.2.4 主流程

##### 路径 A：几何 Keep（阶段一）

```text
用户对几何执行 Keep
    ↓
Keep 过程中 / 成功后生成 element：
    - element.iMeshObjectId = GetCurrentMeshObjectId()
      （Fortran 路径：GetCurrentMeshObjectId(hDb, femId, &moId)）
    - ElmAdd 成功后更新 m_MOIdToElementCountMap
    ↓
Keep 成功：
    femmgMeshObjectManager.Create(name, pComps, nCmp)
      - 内部 moId = GetCurrentMeshObjectId()
      - 判定 eMeshesType（划分主维度 / 单元族）
      - 组装 MeshObjectRecord 并写入 MOHEAP / MOTREE / 内存 map
      - 内部调用 Allocate()
    ↓
Navigator 刷新，对应 Meshes 节点下显示新 Mesh 节点
```

##### 路径 B：手工建网（阶段二）

```text
用户开始一次手工建网操作（形成操作上下文）
    ↓
创建 node / element 过程中：
    - element.iMeshObjectId = GetCurrentMeshObjectId()
    - 更新 m_MOIdToElementCountMap
    ↓
本次手工建网操作完成时：
    femmgMeshObjectManager.Create(name, nullptr, 0)
      - 内部 moId = GetCurrentMeshObjectId()
      - 判定 eMeshesType（本次 element 主维度）
      - pComps 为空，表示手工来源
      - 内部调用 Allocate()
    ↓
Navigator 刷新，对应 Meshes 节点下显示新 Mesh 节点
```

### 5.3 删除

#### 场景描述

删除 MeshObject 元数据的前提是：其归属 element 已全部删除。element 的删除统一走已有 `ElemRemove` 路径；MeshObject 侧在 `ElemRemove` 挂钩处维护计数，当某 `moId` 的 element 全部删完时，自动移除对应 MeshObject 元数据。

用户侧有三类触发入口，但元数据收尾机制相同——均由 `ElemRemove` 挂钩判定：

| 入口 | 触发方式 | 如何到达 ElemRemove |
|---|---|---|
| 整包删除 | Navigator Delete Mesh 节点 | `MeshObjectDelete` 编排：geo 调 `GeoMeshDel`，手工 O(N) 扫描后逐个 `ElemRemove` |
| 几何网格删除 | 用户通过已有几何删除路径删几何 | 已有删几何 API 内部级联 `ElemRemove` |
| 逐 element 删除 | 用户通过已有 element 删除路径删单元 | 直接 `ElemRemove` |

#### 主流程

##### 统一收尾：ElemRemove 挂钩（几何删除 / 逐 element 删除 / 整包删除共用）

```text
ElemRemove：
    1. 读出 moId = iMeshObjectId
    2. 执行原有 element 删除（含关联 node 清理）
    3. if (moId > 0) --m_MOIdToElementCountMap[moId]
         if (m_MOIdToElementCountMap[moId] <= 0) RemoveMeshObject(moId)（callback 删除 meshObject 节点）
```

##### 入口 A：几何删除

```text
用户通过已有路径删除几何网格（非 Navigator 整包删除）
    ↓
已有删几何网格 API
    → 内部级联 ElemRemove
    → 每个 element 走上述挂钩
    → 某 MeshObject 的 element 全部删完时：RemoveMeshObject(moId)
```

##### 入口 B：逐 element 删除

```text
用户通过已有路径删除单个 / 部分 element
    ↓
ElemRemove
    → 走上述挂钩
    → 未删光：Mesh 节点保留
    → 删光：RemoveMeshObject(moId)
```

##### 入口 C：Navigator 整包删除（MeshObjectDelete）

```text
用户在 Navigator 选择 Delete Mesh 节点
    ↓
MeshObjectDelete(hDb, femId, moId)
    ↓
record = femmgMeshObjectManager.QueryById(moId)
    ↓
路径 A（几何 Keep，pComps 非空）：
    GeoMeshDel(record.pComps, record.nCmp)     // 已有删几何网格 API
      → 内部级联 ElemRemove（同入口 A）
    ↓
路径 B（手工建网，pComps 为空）：
    扫描全部 element（O(N)，阶段一接受）
      filter: element.iMeshObjectId == moId
      → 逐个 ElemRemove(elPtr)              // 同入口 B
    ↓
每次 ElemRemove 均走统一挂钩；最后一个 element 删完时 RemoveMeshObject(moId)
    ↓
Navigator 刷新，Mesh 节点消失
```

### 5.4 改

#### 场景描述

阶段一「改」仅包含 **Rename**（重命名 Mesh 节点显示名称）。用户在 Navigator 中对 Mesh 节点执行 Rename，修改 `MeshObjectRecord.szDisplayName`；`iMeshObjectId`、`eMeshesType`、`pComps`、element 归属及 `m_MOIdToElementCountMap` 均不变。

Info 为只读查询（`QueryById`），Show-Hide 为 UI 层产品行为，不在本用例范围内。

#### 主流程

```text
用户在 Navigator 选择 Rename Mesh 节点，输入新名称
    ↓
Entity 层转发（具体放置 Entity / Adapter 待定）
    ↓
femmgMeshObjectManager.Rename(moId, pszDisplayName)
    - 校验 moId 存在于 m_MOIdToRecordMap
    - 更新 m_MOIdToRecordMap[moId].szDisplayName
    - femdaMOFSIProxy 更新 MOHEAP 中对应 record（MOTREE 索引不变）
    ↓
Navigator 刷新，节点显示新名称
```

Manager 接口（示意）：

```cpp
femStatus Rename(int moId, const char* pszDisplayName);
```

#### 规则

| 规则 | 说明 |
|---|---|
| 仅改名称 | Rename 只修改 `szDisplayName`；不修改 `iMeshObjectId`、`eMeshesType`、`pComps`、element 归属 |
| MOId 不变 | Rename 不触发 `Allocate()`，不影响 `m_iCurrentMeshObjectId` |
| 调用分层 | Rename 为纯元数据操作，由 `femmgMeshObjectManager` 直接完成；不需调用 element / 几何层 API |
| 持久化 | Rename 成功时同步更新 MOHEAP record；下次 Save 与运行时一致 |
| 失败回滚 | 校验失败（moId 不存在、名称为空等）则不修改 map 与 MOHEAP |

## 6. Appendix

### 6.1 相关实现位置

建议重点关注以下实现位置：

- `MeshObjectRecord` 定义文件
- `femmgMeshObjectManager`
- MOHEAP / MOTREE 访问代理
- `femElem` 定义
- `ElmAdd` / `ElmQuery` / `ElmModify` 相关路径
- `LoadFromFSI` 与 Open 恢复路径

### 6.2 关键实现约束

`element.iMeshObjectId` 的设计约束如下：

1. `iMeshObjectId` 放入 `femElem`
2. 存放于 EHEAP common 区
3. 位于 `iADPtr` 后
4. 由调用方在 `ElmAdd` 前填写
5. Open 后通过扫描 element 重建成员关系与计数缓存

### 6.3 关键问题

1. **Src 层需要构建 MeshObject 对象，对象应该存放什么数据？（与 mst_zRegion 关联？怎么关联手动创建的 node 和 element？）**
   - 手动创建的 element 也会有 `iMeshObjectId`，meshObject 不需要和 `mst_zRegion` 关联

2. **mst_zRegion / mst_zFace / mst_zEdge 如何存放 meshObjectId？**
   - 不需要存放，只要有 element 和 `iMeshObjectId` 就行

3. **如何支持 MeshObject 对应到 RibbonBar 的创建和删除操作，部分删除，全删除？**
   - 删除 element 的入口是统一的，只要在最后检查删除的 element 的 `iMeshObjectId` 对应的 meshObject 还有没有 element 就行
   - 缓存 `map<int, int> m_MOIdToElementCountMap;  // MOId → count`

4. **如何支持 AFEM？**
   - 待补充

5. **如何支持 Copy FEM 操作？**
   - 待补充

6. **如何支持 CheckIn、CheckOut 操作？**
   - 待补充

7. **如何支持保存 mf1、打开 mf1？**
   - 在 fem 的 field2 新建两个段存放 heap 和 tree

8. **如何支持打开 2606 之前的 mf1 和 unv，创建导入规则？**
   - 待补充

### 6.4 后续设计章节

- Model Entity 层
- Navigator-UI 层
