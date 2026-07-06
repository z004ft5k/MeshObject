# Design Specification

NEUE

Design Specification for [Mesh Object]

重庆诺源工业软件科技有限公司  
2026年07月06日  
版本：V1.4

## Revision History

| 版本 | 日期 | 说明 |
|---|---|---|
| V1.0 | 2026-07-02 | 初版整理，结合现有讨论形成 MeshObject 设计方案 |
| V1.1 | 2026-07-03 | 根据手动修订同步命名、数据结构与章节结构 |
| V1.2 | 2026-07-03 | 补充 `femmgMeshObjectIdManager` 与 AFEM MOId 重分配设计 |
| V1.3 | 2026-07-06 | 补充 User Case §5.1 打开 Mf1 |
| V1.4 | 2026-07-06 | 补充 `femdaMOFSIProxy` FSI 访问层设计与 `femmgMeshObjectManager` 集成 |

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
3. UI 层通过 Entity 层访问 MeshObject。
4. 运行时缓存可重建，持久化数据应与 Save/Open 流程一致。

### 2.3 设计任务分解

| 任务 | 设计内容 |
|---|---|
| 数据模型设计 | 定义 `MeshObjectRecord`、`element.iMeshObjectId`、component 列表等核心数据 |
| MOId 管理设计 | 定义 `femmgMeshObjectIdManager` 的职责与分配规则 |
| 持久化设计 | 设计 `MOHEAP`、`MOTREE` 变长 record 布局；`femdaMOFSIProxy` 负责 FSI 读写 |
| 运行时管理设计 | 定义 `femmgMeshObjectManager` 的职责和运行时缓存 |
| Entity 封装设计 | 提供对象化接口，承接 UI 层调用 |
| Navigator 集成设计 | 定义 Mesh 节点显示和操作入口 |
| 生命周期设计 | 定义 Create、Delete、Save、Open、AFEM 合成等主流程 |

### 2.4 Terminology

| 术语 | 说明 |
|---|---|
| MeshObject | 逻辑概念名称 |
| Mesh | UI 中的显示名称 |
| MeshObjectRecord | Src Layer 中的运行时 struct |
| MOHeapRecord | `MOHEAP` 上的持久化 record 布局 |
| MeshObject Entity | Entity 层对象封装 |
| femmgMeshObjectManager | Fem 级 MeshObject 业务管理器 |
| femmgMeshObjectIdManager | Fem 级 MOId 分配器 |
| femdaMOFSIProxy | Fem 级 MOHEAP / MOTREE FSI 访问代理 |
| element.iMeshObjectId | 成员归属字段 |
| MOId | MeshObject 标识，对应 `iMeshObjectId` |

约定：凡表示 MeshObject 缩写时，统一使用 `MO`（两个字母均大写），如 `MOHEAP`、`MOTREE`、`MOHeapRecord`。

## 3. High Level Design

### 3.1 架构层次

本设计采用三层结构：

1. **UI 层**：负责 Navigator 节点显示和用户交互。
2. **Entity 层**：负责 MeshObject 的对象化封装，向 UI 层暴露稳定能力。
3. **Src 层**：负责底层数据模型、持久化、成员关系与运行时恢复。

Src 层内部结构如下：

```text
femmgModel
  ├── femmgMeshObjectIdManager
  └── femmgMeshObjectManager
        ↓
      femdaMOFSIProxy
        ↓
      MOHEAP / MOTREE / EHEAP
```

层间关系如下：

```text
Navigator / UI
    ↓
MeshObject Entity
    ↓
femmgMeshObjectManager
    ↓
femdaMOFSIProxy
    ↓
MOHEAP / MOTREE / EHEAP
```

Fortran / Keep 路径通过 C 桥获取 MOId：

```text
GetNextMeshObjectId(hDb, femId, &moId)
    → femmgMeshObjectIdManager::Allocate()
```

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
struct MeshObjectRecord
{
    int          iMeshObjectId;
    char         szDisplayName[128];
    int          nCmp;
    fgm_TzCmp*   pComps;
};
```

其中：

- `iMeshObjectId`：MeshObject 标识
- `szDisplayName`：显示名称
- `nCmp` / `pComps`：几何关联 component 列表

#### 3.3.2 Src 层运行时缓存

```cpp
class femmgMeshObjectManager
{
private:
    std::map<int, MeshObjectRecord> m_MOIdToRecordMap;
    std::map<int, int>              m_MOIdToElementCountMap;
};
```

- `m_MOIdToRecordMap`：按 MOId 管理全部 `MeshObjectRecord`
- `m_MOIdToElementCountMap`：按 MOId 缓存 element 数量

#### 3.3.3 MOId 管理器

```cpp
class femmgMeshObjectIdManager
{
public:
    void InitFromRecords(const std::map<int, MeshObjectRecord>& records);
    int  Allocate();

private:
    int m_iNextMeshObjectId;
};
```

- `femmgMeshObjectIdManager` 挂在 `femmgModel` 下，与 `femmgMeshObjectManager` 并列
- `0` 保留为未归属
- MOId 从 `1` 开始单调递增

#### 3.3.4 element 归属字段

`element.iMeshObjectId` 作为 element 的正式字段：

- 存放于 `femElem`
- 位于 `iADPtr` 后
- 存放于 EHEAP common 区
- 由调用方在 `ElmAdd` 前填写

### 3.4 各层职责

#### UI 层
- 显示 MeshObject 节点
- 响应 Info、Rename、Delete、Show-Hide

#### Entity 层
- 对 MeshObject 进行对象化封装
- 对外暴露名称、components、element 数量等能力
- 将操作委托给 `femmgMeshObjectManager`

#### Src 层
- `femmgMeshObjectIdManager` 负责 MOId 分配
- `femmgMeshObjectManager` 负责 `MeshObjectRecord` 管理与运行时缓存
- `femdaMOFSIProxy` 负责 `MOHEAP` / `MOTREE` 的 FSI 读写
- 协调 Open/Save 与运行时恢复

## 4. Detailed Design

### 4.1 Src 层设计

#### 4.1.1 管理器职责

`femmgMeshObjectManager` 是 Fem 级 MeshObject 业务入口，负责：

- 管理全部 `MeshObjectRecord` 运行时副本（`m_MOIdToRecordMap`）
- 创建、删除、重命名 `MeshObjectRecord`
- 维护运行时 element 数量缓存
- 在 Open 后恢复运行时状态
- 将持久化读写委托给 `femdaMOFSIProxy`

`femmgMeshObjectManager` 不直接调用 `fsihpio` / `fsitrop` 等 FSI 接口。

#### 4.1.2 FSI 访问层：femdaMOFSIProxy

`femdaMOFSIProxy` 位于 `femda` 层，专门封装 MeshObject 相关的 FSI 操作，职责类比 `femdaAccFSIProxy` 之于 EHEAP。

**定位**

- Fem 级，由 `femmgMeshObjectManager` 持有并调用
- 只负责 `MOHEAP` / `MOTREE` 的打开、读写与关闭
- 不管理 MOId 分配，不维护 element 归属

**类接口（当前实现）**

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

**与 Manager 的集成**

```text
femmgMeshObjectManager 构造:
  m_femdaMOFSIProxy = new femdaMOFSIProxy(hDb, femId)
  m_femdaMOFSIProxy->GetAllMeshObjects(allRecords)
  对每条 record 调用 RegisterFromRecord() → m_MOIdToRecordMap

femmgMeshObjectManager::Create():
  组装 MeshObjectRecord
  m_femdaMOFSIProxy->AddMeshObject(record)   // 写 MOHEAP / MOTREE
  m_MOIdToRecordMap[moId] = record            // 写内存
```

#### 4.1.3 MOId 管理器职责

`femmgMeshObjectIdManager` 是 Fem 级 MOId 分配器，负责：

- 在 Open 后根据已有 `MeshObjectRecord` 初始化 `m_iNextMeshObjectId`
- 在 Keep、Manual Mesh、AFEM 合成等场景分配新的 MOId
- 为 Fortran / C 桥提供 `GetNextMeshObjectId` 支撑

初始化规则：

```text
Open Fem:
  读取全部 MeshObjectRecord
  m_iNextMeshObjectId = max(iMeshObjectId) + 1
  若没有 record，则 m_iNextMeshObjectId = 1
```

分配规则：

```text
Allocate():
  返回当前 m_iNextMeshObjectId
  m_iNextMeshObjectId++
```

#### 4.1.4 创建调用顺序

```text
1. moId = femmgMeshObjectIdManager.Allocate()
2. femmgMeshObjectManager.Create(moId, record...)
3. element.iMeshObjectId = moId
4. Save
```

Fortran / Keep 路径：

```c
GetNextMeshObjectId(hDb, femId, &moId);
```

#### 4.1.5 AFEM 合成与 MOId 重分配

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

#### 4.1.6 成员关系恢复

Open 后，通过扫描全部 element，根据 `element.iMeshObjectId` 重建：

- MeshObject 的运行时成员关系
- `m_MOIdToElementCountMap` 缓存

### 4.2 Entity 层设计

#### 4.2.1 角色定位

Entity 层用于对 MeshObject 进行对象化封装，面向 UI 和上层逻辑提供统一对象语义。

#### 4.2.2 典型能力

Entity 层支持以下能力：

- Create
- Rename
- Delete
- GetName
- GetComponents
- GetElementCount

其中，具体实现最终由 `femmgMeshObjectManager` 提供支撑。

### 4.3 UI / Navigator 集成设计

#### 4.3.1 节点显示

Navigator 中新增 MeshObject 节点：

- 节点显示名称来自 `MeshObjectRecord.szDisplayName`
- 节点集合来自当前 FEM 下全部可见 MeshObject

#### 4.3.2 用户操作

Navigator 对 MeshObject 节点提供以下操作：

- Info
- Rename
- Delete
- Show-Hide

Info / Rename / Delete 通过 Entity 层转发到底层。

### 4.4 Persistence Design

#### 4.4.1 持久化结构

MeshObject 持久化采用：

- `MOHEAP`
- `MOTREE`

二者位于 FEM Record 的第二个 Field 中。

#### 4.4.2 持久化原则

- `femdaMOFSIProxy` 负责 `MOHEAP` / `MOTREE` 的 FSI 读写
- `MeshObjectRecord` 通过变长 record 序列化到 `MOHEAP`
- `MOTREE` 负责 `iMeshObjectId -> record` 的索引
- `element.iMeshObjectId` 随 EHEAP 持久化
- Save 时持久化各 `MeshObjectRecord` 的具体内容

#### 4.4.3 MOHEAP record 布局

每条 MOHEAP record 至少包含：

- `iMeshObjectId`
- 名称信息
- `nCmp`
- `fgm_TzCmp[]`

其中每个 `fgm_TzCmp` 记录：

- `eCmpTyp`
- `iCmpId`
- `iNlId`

### 4.5 Lifecycle Design

#### 4.5.1 Geometry Keep

几何 Keep 成功后：

1. `moId = femmgMeshObjectIdManager.Allocate()`
2. 创建 `MeshObjectRecord`
3. 设置名称
4. 记录本次 Keep 对应的 `pComps`
5. 本次新生成 element 写入 `iMeshObjectId = moId`
6. 保存到 `MOHEAP` / `MOTREE`
7. Navigator 中出现对应 MeshObject 节点

#### 4.5.2 Manual Mesh

手工创建路径中：

1. 创建节点、单元时按当前操作上下文形成一组对象
2. 创建 element 时由调用方填写 `elem.iMeshObjectId`
3. 一次手工建网操作完成时，显式创建对应 `MeshObjectRecord`
4. 该对象的 `pComps` 为空
5. 保存到 `MOHEAP` / `MOTREE`

#### 4.5.3 Delete Mesh

##### 几何 Keep 类型
若 `pComps` 非空，则基于 `pComps` 调用现有几何删除接口。

##### 手工类型
若 `pComps` 为空，则基于 `element.iMeshObjectId` 找出归属 element 并执行删除。

##### 一致性原则
Delete Mesh 是复合操作。仅在底层 element 或 geometry 删除成功后，才完成对应 MeshObject 元数据移除；若底层删除失败，则保留 MeshObject 元数据。

#### 4.5.4 空 Mesh 自动删除

若 element 删除后某个 MeshObject 不再拥有任何归属 element，则应自动删除该 MeshObject 的运行时对象和持久化记录。

#### 4.5.5 Save / Open

##### Save
- `femdaMOFSIProxy::AddMeshObject()` 写入 `MeshObjectRecord` 到 `MOHEAP` / `MOTREE`
- 保存 EHEAP 中的 `element.iMeshObjectId`

##### Open
- `femdaMOFSIProxy::GetAllMeshObjects()` 从 `MOHEAP` / `MOTREE` 恢复全部 `MeshObjectRecord`
- `femmgMeshObjectManager` 填充 `m_MOIdToRecordMap`
- 调用 `femmgMeshObjectIdManager.InitFromRecords()` 初始化 MOId 分配器
- 扫描全部 element
- 根据 `element.iMeshObjectId` 重建运行时关系和 `m_MOIdToElementCountMap`

## 5. User Case

### 5.1 打开 Mf1

#### 5.1.1 场景描述

用户通过 **File → Open** 打开一个已保存的 mf1 文件。该文件在先前 Save 时已写入 MeshObject 元数据（`MOHEAP` / `MOTREE`）以及 element 侧的 `iMeshObjectId` 归属信息。打开成功后，系统应恢复全部 MeshObject 运行时状态，并在 Navigator 中显示对应的 Mesh 节点。

本用例描述 **支持 MeshObject 的 mf1** 的标准打开路径。2606 之前的历史 mf1 及 UNV 导入规则见 §6.3.7。

#### 5.1.2 前置条件

- mf1 文件格式有效，可正常加载 FEM 数据库。
- 目标 FEM 的 Field 2 中存在 `MOHEAP` 与 `MOTREE` 段。
- `EHEAP` 中 element 已包含 `iMeshObjectId` 字段（位于 `iADPtr` 之后）。

#### 5.1.3 参与组件

| 层 / 组件 | 打开时的职责 |
|---|---|
| 文件 / FSI 层 | 读取 mf1，挂载 FEM Record，加载各 Heap / Tree 段 |
| `femdaMOFSIProxy` | 打开 `MOHEAP` / `MOTREE`，读取并反序列化 `MeshObjectRecord` |
| `femmgMeshObjectManager` | 调用 `GetAllMeshObjects()`，填充 `m_MOIdToRecordMap` |
| `femmgMeshObjectIdManager` | 调用 `InitFromRecords()`，初始化 `m_iNextMeshObjectId` |
| Element 遍历 | 扫描 `EHEAP`，按 `iMeshObjectId` 重建 `m_MOIdToElementCountMap` |
| MeshObject Entity | 基于 Manager 查询结果，为 UI 提供对象化访问 |
| Navigator / UI | 刷新 Mesh 节点列表，显示 `szDisplayName` |

#### 5.1.4 主流程

```text
用户选择 mf1 文件
    ↓
FSI 加载 FEM 数据库（含 EHEAP、MOHEAP、MOTREE）
    ↓
对每个已打开的 Fem：
    ① femmgMeshObjectManager 构造 / LoadFromFSI()
         - femdaMOFSIProxy->GetAllMeshObjects()
         - 经 MOTREE 遍历 MOHEAP，反序列化为 MeshObjectRecord
         - 写入 m_MOIdToRecordMap
    ② femmgMeshObjectIdManager.InitFromRecords(m_MOIdToRecordMap)
         - m_iNextMeshObjectId = max(iMeshObjectId) + 1
         - 若无 record，则 m_iNextMeshObjectId = 1
    ③ 扫描全部 element（ElmCreateIter）
         - 读取 element.iMeshObjectId
         - 累加 m_MOIdToElementCountMap
    ④ 一致性校验（见 §5.1.6）
    ↓
Entity 层基于 Manager 查询结果构建 MeshObject 对象视图
    ↓
Navigator 刷新，显示当前 Fem 下全部 Mesh 节点
```

#### 5.1.5 持久化数据读取

打开时，MeshObject 相关数据从以下三处恢复：

| 数据源 | 恢复内容 | 说明 |
|---|---|---|
| `MOHEAP` | `iMeshObjectId`、名称、`nCmp`、`fgm_TzCmp[]` | 变长 record，经 `MOHeapRecord` 布局反序列化 |
| `MOTREE` | `iMeshObjectId` → MOHEAP record 索引 | 用于按 MOId 定位 record |
| `EHEAP` | 各 element 的 `iMeshObjectId` | 成员归属唯一真相，Open 时扫描重建计数缓存 |

`m_MOIdToElementCountMap` 是运行时缓存，不在 mf1 中单独持久化；Open 后通过 element 扫描一次性重建。

`m_iNextMeshObjectId` 同样不在 mf1 中持久化；Open 时由已有 `MeshObjectRecord` 的 MOId 最大值推导。

#### 5.1.6 一致性处理

Open 完成后，对 `MeshObjectRecord` 与 element 归属进行校验：

| 情况 | 处理 |
|---|---|
| MOHEAP 有 record，但无 element 归属 | 按空 Mesh 规则自动删除该 MeshObject 的运行时对象；下次 Save 时不写入 |
| element 的 `iMeshObjectId > 0`，但 MOHEAP 无对应 record | 按导入规则补建 `MeshObjectRecord`（默认名称，空 `pComps`）；详见 §6.3.7 |
| element 的 `iMeshObjectId == 0` | 视为未归属，不计入任何 MeshObject 的 element 数量 |
| 同一 MOId 在 MOHEAP 与 element 侧均存在 | 正常恢复；`pComps` 非空为几何 Keep 来源，为空为手工创建来源 |

校验与修复在 Src 层完成，Entity 层和 Navigator 仅消费修复后的 Manager 状态。

#### 5.1.7 打开后状态

打开成功后，系统应满足：

1. `m_MOIdToRecordMap` 包含当前 Fem 下全部有效 MeshObject。
2. `m_MOIdToElementCountMap` 与 element 扫描结果一致。
3. `femmgMeshObjectIdManager` 已就绪，后续 Keep / 手工建网可调用 `Allocate()` 分配新 MOId。
4. Navigator 中每个 Mesh 节点显示名称来自 `MeshObjectRecord.szDisplayName`。
5. 用户可对 Mesh 节点执行 Info / Rename / Delete / Show-Hide（阶段一能力）。

#### 5.1.8 多 Fem 场景

一个 mf1 可包含多个 FEM。打开时，每个 FEM 独立执行 §5.1.4 的恢复流程：

- 各 Fem 拥有独立的 `femmgMeshObjectIdManager` 与 `femmgMeshObjectManager`。
- MOId 空间按 Fem 隔离，不同 Fem 之间的 MOId 数值可以重复。
- Navigator 按当前活动 Fem 显示对应的 Mesh 节点集合。

AFEM 打开与 MOId remap 不在本用例范围内，见 §4.1.5。

### 5.2 创建

### 5.3 删除

### 5.4 改

## 6. Appendix

### 6.1 相关实现位置

建议重点关注以下实现位置：

- `MeshObjectRecord` 定义文件
- `femmgMeshObjectIdManager`
- `femmgMeshObjectManager`
- `femdaMOFSIProxy`（`neuecax/src/femda/femdaMOFSIProxy.hxx` / `.cxx`）
- `GetNextMeshObjectId`
- `femElem` 定义
- `ElmAdd` / `ElmQuery` / `ElmModify` 相关路径
- Open 恢复路径（`femdaMOFSIProxy::GetAllMeshObjects` + element 扫描）

### 6.2 关键实现约束

`element.iMeshObjectId` 的设计约束如下：

1. `iMeshObjectId` 放入 `femElem`
2. 存放于 EHEAP common 区
3. 位于 `iADPtr` 后
4. 由调用方在 `ElmAdd` 前填写
5. Open 后通过扫描 element 重建成员关系与计数缓存

### 6.3 关键问题

1. **Src 层 MeshObject 对象存放什么数据？如何关联手动创建的 node 和 element？**
   - `MeshObjectRecord` 保存 `iMeshObjectId`、名称和 `pComps`
   - 手动创建的 element 通过 `iMeshObjectId` 归属到 MeshObject
   - 节点集合通过 element 连接性推导

2. **如何支持 MeshObject 的创建和删除？**
   - 创建：`Allocate()` 分配 MOId，再 `Create()` 建立 `MeshObjectRecord`
   - 删除：统一 element 删除入口，结合 `m_MOIdToElementCountMap` 判断 MeshObject 是否为空

3. **如何支持 AFEM？**
   - 多个 FEM 合成 AFEM 时，为 AFEM 重新分配 MOId
   - 通过 `(sourceFemId, oldMOId) -> newMOId` remap 更新 AFEM 侧 element 归属

4. **如何支持 Copy FEM 操作？**
   - 待补充

5. **如何支持 CheckIn、CheckOut 操作？**
   - 待补充

6. **如何支持保存 mf1、打开 mf1？**
   - 在 FEM 的 Field 2 新建 `MOHEAP` 和 `MOTREE` 段

7. **如何支持打开 2606 之前的 mf1 和 unv，创建导入规则？**
   - 待补充

### 6.4 后续设计章节

- Model Entity 层
- Navigator-UI 层
