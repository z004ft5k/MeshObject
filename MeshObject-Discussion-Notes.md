# MeshObject 讨论纪要

本文档累积 MeshObject 设计与 DS 协作的讨论结论。**后续每次讨论在文末「讨论记录」追加新日期章节，并更新文首「最新状态」。**

---

## 最新状态（截至 2026-07-08 晚）

### DS 版本

- 本地主文档：`MeshObjectDesignSpecificaiton.md`，**与飞书 Wiki 同步**（封面 `Vx.x`；权威来源为飞书）
- GitHub 最新：`e631a6e`（`docs(ds): align local DS with Feishu Wiki as authoritative source`）
- 讨论纪要：单一文件 `MeshObject-Discussion-Notes.md`（本文件）

### MMF & RoadMap（2612）

- 飞书规划文档：[MMF & RoadMap](https://ycntm1ix2za7.feishu.cn/wiki/Vx4ywFX5qiJXe8kzaqacyyvTndh)
- 已填：**MMF1**（Navigator 右键 + Non-Current）、**MMF2**（Force 子实例）、**MMF3**（其余 Load/Constraint Set）
- 待填：**MMF4**（Mesh Object 阶段一）、**MMF5**（阶段二手工建网 + AFEM 汇入）
- 本地导出：`mmf-roadmap-sheets.md`（飞书嵌入 Sheet 快照）

### MMF4 / MMF5 Story 草案（用户可感知）

| MMF | Story | 说明 |
|---|---|---|
| MMF4-S1 | Keep 后 Navigator 出现 Mesh | 含 XD Meshes 树、默认命名；Src 层为实现任务，非独立 Story |
| MMF4-S2 | Navigator Delete 整包删 Mesh | P0 |
| MMF4-S3 | Info | P1 |
| MMF4-S4 | Rename | P1 |
| MMF4-S5 | Show/Hide | P1 |
| MMF4-S6 | Save/Open 持久化 | P0 |
| MMF5-S1 | 手工建网完成后 Navigator 出现 Mesh | 操作语义与 MMF4 一致 |
| MMF5-S2 | AFem Update 汇入 Mesh 节点树 | |

### User Case 进度

| 章节 | 状态 |
|---|---|
| §5.1 打开 mf1 | ✅ |
| §5.2 创建 | ✅（路径 A 几何网格 Keep / 路径 B 手工网格） |
| §5.3 删除 | ✅ |
| §5.4 改（Rename） | ✅ |
| §5.5 AFEM Map | 待补充 |
| §5.6 Copy FEM | 待补充 |
| §5.7 几何修改 / Remesh | 待补充 |
| Info / Show-Hide | 待补充 |

### 设计待补充

| 项 | 状态 |
|---|---|
| §5.5 AFEM Map | 待补充 |
| §5.6 Copy FEM | 待补充 |
| §5.7 几何修改 / Remesh | 待补充 |
| Info / Show-Hide User Case | 待补充 |
| Model Entity 层（§6.4） | 待写 |
| Navigator-UI 层（§6.4） | 待写 |
| CheckIn / CheckOut | 待补充 |
| 2606 前 mf1 / UNV 导入规则 | 待补充 |

### 实现待对齐

- `MeshObjectDelete` 编排函数（位置待定）
- `ElemRemove` 挂钩维护 `m_MOIdToElementCountMap`
- `RemoveMeshObject`（元数据 + MOHEAP）
- `GetCurrentMeshObjectId` C/Fortran 桥（命名与 DS 一致）
- `femmgMeshObjectIdAllocator` 按新 API 实现（`GetMeshObjectId` / `Allocate`）
- `femmgMeshObjectManager::Create(pComps, nCmp, eType)` 及内部 `GenerateDefaultDisplayName()`、`Allocate()`
- `femdaMOFSIProxy` 与 Manager 集成

### 建议下次讨论顺序

1. 将 MMF4/MMF5 填入飞书 MMF 列表 Sheet 并排 Roadmap Sprint
2. §5.5 AFEM Map 或 §5.6 Copy FEM（择一）
3. Info User Case（若阶段一需要）
4. 补充 `eMeshObjectType` 更多类型及与手工入口的映射

### 关键一句话

> **飞书 Wiki 为 DS 权威来源；MMF4=阶段一几何 Mesh 全套 Navigator 管理，MMF5=手工建网+AFEM；Story 只写用户可感知行为，Src/Entity 为实现子项。**

---

## 文档与协作约定

| 用途 | 位置 |
|---|---|
| 版本真相 | GitHub：https://github.com/z004ft5k/MeshObject |
| 阅读与协作 | 飞书 Wiki：https://ycntm1ix2za7.feishu.cn/wiki/PwilwM9Ayi75pVkQqU0cutWQn1f |
| 本地编辑 | `C:\Users\xin.zeng\Documents\CurProjects\MeshObject\` |

- 每次讨论后：更新 DS（仅改确认内容）→ 更新本文档 → `git commit` + `push`
- **编辑原则**：只改用户明确要求或已共同确认的内容；占位仅写「待补充」，不展开、不联想、不擅自改其他章节术语
- Git CLI：可用仓库内 `scripts/git.ps1` / `push-to-github.ps1`（捆绑 GitHub Desktop 的 git）
- 公司内网 Git HTTPS 不稳定，已配置 **SSH**（`ssh.github.com:443`）推送
- 飞书 MCP **无法直接修改** Wiki 已有 docx；读文档须同时检查 **嵌入 Sheet（block_type 30）** 与 **白板/UML（block_type 43）**，不能仅用 `rawContent`

---

## 已确认核心设计（累积结论）

### 产品阶段

- 阶段一：几何 Keep + Navigator（Info / Rename / Delete / Show-Hide）
- 阶段二：手工建网也形成 MeshObject
- 当前重点：先把底层模型层建立起来，为 Navigator 和后续操作提供支撑

### 架构分层

```text
UI::Navigator (MeshObjectNode)
    ↓
Model::EntityMeshObject
    ↓
FEDataModelAdapter
    ↓
Src: femmgMeshObjectManager + MeshObjectRecord
    ↓
Database: MOHEAP / MOTREE / EHEAP
```

| 层 | 职责 | 不做什么 |
|---|---|---|
| **Entity** | 对象语义，面向 UI | 不是数据真相；不是 Manager 的简单翻版 |
| **Adapter** | 跨层翻译 (hDb,femId,moId) ↔ IEntity | 不存真相 |
| **femmgMeshObjectManager** | 管理 MeshObjectRecord、持久化、计数缓存 | 不分配 MOId |
| **femmgMeshObjectIdAllocator** | 分配 MOId | 不管理 MeshObject 业务数据 |

- Entity 层是对 `meshObject` / `MeshObjectRecord` 的封装，**不是**对 `femmgMeshObjectManager` 的封装
- Entity 层不暴露 IdAlloc

**数据真相：**
- 成员关系 → `element.iMeshObjectId`
- MeshObject 元数据 → `MeshObjectRecord` + MOHEAP/MOTREE

### 命名约定

| 概念 | 名称 |
|---|---|
| 逻辑概念 / UI 显示 | MeshObject / Mesh |
| Entity 层 | MeshObject Entity（概念描述，类名待定） |
| Src 运行时 struct | **MeshObjectRecord** |
| MOHEAP 持久化布局 | **MOHeapRecord** |
| Manager | femmgMeshObjectManager |
| Id 分配器 | **femmgMeshObjectIdAllocator** |
| Fortran/C 桥 | **GetMeshObjectId** / **GetCurrentMeshObjectId**（以 DS 为准） |
| 字段 | element.iMeshObjectId / MOId |

**约定：MeshObject 缩写统一写 `MO`（两个字母均大写）**：MOHEAP、MOTREE、MOHeapRecord。

### MeshObjectRecord 结构

```cpp
struct MeshObjectRecord
{
    int                 iMeshObjectId;
    char                szDisplayName[128];
    int                 nCmp;
    fgm_TzCmp*          pComps;
    femmgMeshObjectType eMeshObjectType;   // Create() 时写入 MOHEAP
};
```

- 用 `nCmp + pComps`，不用 `std::vector` 作为落盘 struct 字段
- `pComps` 非空 → 几何 Keep；`pComps` 为空 → 手工创建
- 不需要与 `mst_zRegion` 关联

**Manager 运行时缓存：**

```cpp
std::map<int, MeshObjectRecord> m_MOIdToRecordMap;
std::map<int, int>              m_MOIdToElementCountMap;
```

### element 归属

- `iMeshObjectId` 在 `femElem`，EHEAP common 区，`iADPtr` 后
- 调用方在 `ElmAdd` 前填写；**不改** `ElmAdd` 签名
- `element.iMeshObjectId` 是成员归属的**唯一真相**；`m_MOIdToElementCountMap` 是运行时缓存
- Open 后扫描全部 element 重建 `m_MOIdToElementCountMap`
- 一个 element 最多归属一个 MeshObject

### femmgMeshObjectIdAllocator

- **Fem 级**，挂在 `femmgModel` 下，与 `femmgMeshObjectManager` **并列**
- `0` 保留为未归属；MOId 从 `1` 开始单调递增，**不回收**
- Open：`m_iMeshObjectId = max(iMeshObjectId) + 1`；无 record 则为 `1`
- Delete MeshObject：**不降低** `m_iMeshObjectId`
- Save：只持久化各 `MeshObjectRecord`，**不写**单独的 nextId 字段

**当前 API（2026-07-06 重构后）：**

```cpp
class femmgMeshObjectIdAllocator
{
public:
    void InitFromRecords(const std::map<int, MeshObjectRecord>& records);
    int  GetMeshObjectId() const;   // 只读，给 element 填 iMeshObjectId
    void Allocate();                // MO 创建成功后 ++m_iMeshObjectId

private:
    int m_iMeshObjectId;
};
```

| 方法 | 行为 |
|---|---|
| `GetMeshObjectId` | 返回当前值，不修改 |
| `Allocate` | `m_iMeshObjectId++`；在 **`femmgMeshObjectManager::Create()` 末尾**调用 |
| Keep 失败 | 不 `Create`、不 `Allocate`，`m_iMeshObjectId` 不变 |

### femmgMeshObjectType 与默认命名

```cpp
enum femmgMeshObjectType
{
    FEMMG_MO_TYPE_UNKNOWN = 0,
    // 1D：1..100
    FEMMG_MO_TYPE_BEAM    = 1,
    // 2D：101..200
    FEMMG_MO_TYPE_SHELL   = 101,
    // 3D：201..300
    FEMMG_MO_TYPE_SOLID   = 201,
    // Others：301..400
    FEMMG_MO_TYPE_RIGID      = 301,
    FEMMG_MO_TYPE_CONSTRAINT = 302
    // 更多类型待产品确定
};
```

**静态映射表 `g_MOTypeInfoTable`（DS §3.3.1）：**

```cpp
{ FEMMG_MO_TYPE_BEAM,       1, "1d",    "beam",       "1D Meshes",     "Beam" },
{ FEMMG_MO_TYPE_SHELL,      2, "2d",    "shell",      "2D Meshes",     "Shell" },
{ FEMMG_MO_TYPE_SOLID,      3, "3d",    "solid",      "3D Meshes",     "Solid" },
{ FEMMG_MO_TYPE_RIGID,      4, "other", "rigid",      "Others Meshes", "Rigid" },
{ FEMMG_MO_TYPE_CONSTRAINT, 4, "other", "constraint", "Others Meshes", "Constraint" },
{ FEMMG_MO_TYPE_UNKNOWN,    4, "other", "unknown",    "Others Meshes", "Unknown" },
```

- 每个 xD Meshes 区间预留 **100** 个枚举空位供扩展
- **不**单独定义 MeshesCollector 枚举；Navigator 分组由枚举值区间派生（1/2/3/4 → 1D/2D/3D/Others Meshes）
- `eMeshObjectType` 由 **Create 调用方传入**（Keep / 手工上下文），Manager 不推断
- 混合维度 / 无法判定 → `FEMMG_MO_TYPE_UNKNOWN` → Others，默认名 `other_unknown_N`
- 默认名：`{维度前缀}_{类型段}_{序号}`（FS §3.3.4）；Others 用 `other_*`；序号取**最小可用空位**（补空位，如 1,2,4 → 3）
- Fem 内显示名唯一；Rename 重名拒绝

### femmgMeshObjectManager::Create

```cpp
femStatus Create(const fgm_TzCmp* pComps, int nCmp, femmgMeshObjectType eType);
// 手工建网：Create(nullptr, 0, eType)
```

**Create 内部流程：**

```text
moId = GetCurrentMeshObjectId()
szDisplayName = GenerateDefaultDisplayName(eType)
组装 MeshObjectRecord
femdaMOFSIProxy->AddMeshObject(record)
m_MOIdToRecordMap[moId] = record
Allocate()
```

**对外创建调用顺序：**

```text
1. element 创建：ElmAdd 前 iMeshObjectId = GetCurrentMeshObjectId()
2. ElmAdd 成功后：OnElementAdded(moId) → ++m_MOIdToElementCountMap
3. Keep 成功 / 手工完成：Create(pComps, nCmp, eType)
4. Save
```

- Create 是**显式操作**；不在 `ElmAdd` 中自动创建 MeshObject
- 无 Bind/Unbind API
- Preview 不创建 MeshObject；只有 Keep 成功后才创建

### element 计数缓存

- `m_MOIdToElementCountMap` 在**每个 element `ElmAdd` 成功时**累加
- **不是**在 `Create()` 之后才更新
- 手工建网与几何 Keep 路径一致

### femdaMOFSIProxy

- 位于 `femda` 层（`neuecax/src/femda/femdaMOFSIProxy.hxx` / `.cxx`）
- 类比 `femdaAccFSIProxy` 之于 EHEAP
- 由 `femmgMeshObjectManager` 持有，封装 MOHEAP / MOTREE 的 FSI 读写
- **构造 / Open**：`GetAllMeshObjects()` → `RegisterFromRecord()` → `m_MOIdToRecordMap`
- **Create**：`AddMeshObject(record)` 写 MOHEAP / MOTREE

### 删除设计（§5.3，2026-07-07 确认）

**三类入口，统一收尾：**

| 入口 | 到达 ElemRemove 的方式 |
|---|---|
| Navigator 整包删除 | `MeshObjectDelete` → 几何网格 `GeoMeshDel` 或手工网格 O(N) 扫描 + 逐个 `ElemRemove` |
| 几何网格删除 | 已有删几何 API 内部级联 `ElemRemove` |
| 逐 element 删除 | 直接 `ElemRemove` |

元数据收尾统一在 **`ElemRemove` 挂钩**：`--m_MOIdToElementCountMap[moId]`，count ≤ 0 → `RemoveMeshObject(moId)`。

**调用分层（与 Create 对称）：**

- `MeshObjectDelete` 为编排入口（Entity / Adapter 放置待定）
- `femmgMeshObjectManager` **不**在整包删除里上调已有删几何 / 删 element API
- Manager 的 `RemoveMeshObject` 由挂钩触发，非 Navigator 直接调用
- 删除一致性：底层 element 或 geometry 删除成功后，才删除 MeshObject 元数据

**删除性能：**

| 场景 | 成本 | 说明 |
|---|---|---|
| 逐 element 删除 / 几何级联删除 | 低 | 删前读 `iMeshObjectId`；挂钩 map 递减；无需 rescan |
| Navigator 整包删**手工网格** | O(N) | `ElmCreateIter` 找出归属 element 再逐个删 |
| Navigator 整包删**几何网格** | 不走 O(N) | `GeoMeshDel(pComps)` 级联 `ElemRemove` |

阶段一决策：手工整包删除接受 O(N)；后续可选 `m_MOIdToElementPtrs` 索引优化。

### Meshes / eMeshObjectType

- Navigator：`Fem → 1D/2D/3D/Others Meshes → Mesh`（无额外 Meshes 父级）
- `eMeshObjectType` 在 `Create()` 时由调用方传入并写入 MOHEAP；Rename / element 变化不改变
- Meshes Collector 分组由枚举区间派生，不单独持久化

### 持久化

- MOHEAP + MOTREE，FEM Record Field 2
- 变长 record：`iMeshObjectId` + name + `eMeshObjectType` + `nCmp` + `fgm_TzCmp[]`
- MOHEAP record **不包含** `femId`（由 FEM 上下文承担）
- Save：MOHEAP/MOTREE + EHEAP 中 `element.iMeshObjectId`
- Open：恢复 MeshObject 元数据 + 扫描 element 重建关系与计数

### AFEM 合成（待细化）

- AFEM 有独立的 `femmgMeshObjectIdAllocator`
- 必须为 AFEM **重新分配 MOId**
- 维护 remap：`(sourceFemId, oldMOId) -> newMOId`
- 拷贝 element 时更新 AFEM 侧 `element.iMeshObjectId`

### DS 结构与写作原则

- 章节风格：Introduction → Overview → High Level Design → Detailed Design → User Case → Appendix
- 正文写「设计结果」，不保留 Spike 过程
- **不做的事情，除非很重要，否则不写进文档**；用正向表述
- §5 User Case 用语：几何网格 / 手工网格（仅第五章）；§1–§4 保留「几何 Keep」「手工建网」等原有表述

---

## 讨论记录

### 2026-07-02

**主题：** 对比 Wiki / Markdown / 实现思路，收敛正式设计方向；明确各层职责；形成 DS 初稿。

**主要结论：**

- 产品阶段以 Wiki 为准；阶段一支持 Navigator 显示 MeshObject 及 Info / Rename / Delete / Show-Hide
- 运行时 struct 采用 `meshObject`（后更名为 `MeshObjectRecord`）；持久化 MOHEAP + MOTREE
- `zComps` 非空 = 几何 Keep；为空 = 手工创建
- `iMeshObjectId` 入 `femElem` EHEAP common 区；`ElmAdd` 前由调用方填写
- `femmgMeshObjectManager` 为 Fem 级业务入口；Entity 层封装 `meshObject` 而非 Manager
- 删除两条路径：空 Mesh 自动删除 + Navigator 主动 Delete
- DS 去掉 OOF / NX 参考 / Spike 过程 / `fKeepDef` 讨论

**DS 修订意见：** 强调阶段一目标；设计范围含手工节点；取消 `QueryById`；Entity 不封装 Manager。

**下次建议：** Copy FEM / CheckIn-Out / 2606 导入；Entity / Navigator 详细设计；Adapter 接口。

---

### 2026-07-03

**主题：** 四层架构合理性；`MeshObjectRecord` 定名与结构；`femmgMeshObjectIdAllocator` 设计；DS 与 Wiki 目录对齐。

**主要结论：**

- 确认四层架构及职责边界（见上文「已确认核心设计」）
- `MeshObjectRecord` 用 `nCmp + pComps`；`femmgMeshObjectIdAllocator` Fem 级并列挂 `femmgModel`
- 创建顺序（旧版）：`Allocate()` → `Create()` → 填 `iMeshObjectId` → Save（**07-06 已重构，见上**）
- AFEM remap 机制初论
- DS 本地 V1.2；Wiki 目录结构对齐

**下次建议：** Copy FEM 与 AFEM remap；Entity 类名与 Adapter 接口；User Case §5.1 打开 Mf1。

---

### 2026-07-06

**主题：** User Case §5.1/§5.2；`femdaMOFSIProxy` 文档化；IdAllocator / Create API 重构；GitHub 仓库与 SSH 推送。

**DS 变更（V1.3 → V1.8）：**

| 版本 | 内容 |
|---|---|
| V1.3 | User Case §5.1 打开 Mf1 |
| V1.4 | `femdaMOFSIProxy` FSI 访问层；Manager 委托持久化 |
| V1.5 | User Case §5.2 创建 |
| V1.6 | IdAllocator：`GetMeshObjectId` + `Allocate` 分离 |
| V1.7 | `Create(name, pComps, nCmp)`，MOId 在 Create 内部获取 |
| V1.8 | §5.2 修正 element 计数时机；精简 EHEAP 持久化描述 |

**主要结论：**

- `GetMeshObjectId` 供 element 反复取同一 MOId；`Allocate` 在 `Create` 末尾推进
- element 计数在 `ElmAdd` 时累加，非 `Create` 之后
- GitHub 仓库 `z004ft5k/MeshObject`；SSH 推送 `ssh.github.com:443`

**User Case 进度：** §5.1 ✅、§5.2 ✅；§5.3/§5.4 待写。

**下次建议：** §5.3 删除；§5.4 Rename；Copy FEM / AFEM remap。

---

### 2026-07-07

**主题：** §5.3 删除、§5.4 Rename DS 落稿；`eMeshesType` / Navigator Meshes 归属；飞书 vs GitHub 对照；§5.5–§5.7 占位；删除性能澄清。

**DS 变更（V1.1 → V1.2）：**

| 版本 | 内容 |
|---|---|
| V1.1 | `eMeshesType`；§4.3 Meshes 归属；§5.3 删除、§5.4 Rename；对齐飞书 FS |
| V1.2 | §5.5–§5.7 占位；§5.2/§5.3 User Case 用语改为几何网格 / 手工网格 |
| V1.3 | `eMeshObjectType`；`Create(pComps, nCmp, eType)`；FS 默认命名与 Fem 内唯一性 |

**刻意未改：** §1–§4 仍保留「几何 Keep」「手工建网」等原有表述。

**主要结论：**

- 删除三类入口统一 `ElemRemove` 挂钩收尾（详见上文）
- 手工网格整包删除 O(N)；几何网格走 `GeoMeshDel`
- 协作约定强化：未确认内容不主动补充进 DS
- 飞书可能仍缺：Info、Show/Hide、AFEM Map UI、2606/UNV 导入、Copy FEM、CheckIn/Out 等

**User Case 进度：** §5.1–§5.4 ✅；§5.5–§5.7 待补充。

**下次建议：** §5.5 AFEM Map 或 §5.6 Copy FEM；Info User Case；飞书与 GitHub V1.2 同步。

**同日续：**

- 将 07-02 / 07-03 / 07-06 / 07-07 四份讨论纪要合并为 `MeshObject-Discussion-Notes.md`
- `femmgMeshObjectIdManager` 更名为 **`femmgMeshObjectIdAllocator`**（DS §3.3.3、§4.1.3 及全文类名同步）

**同日续（命名与类型）：**

- 对齐 FS §3.3.4：`Create` 去掉 `name`，改为 `Create(pComps, nCmp, eType)`；默认名在 Manager 内生成
- `eMeshesType` 改为 **`eMeshObjectType`**（beam/shell/solid/rigid/constraint/unknown）；每类 xD Meshes 枚举区间预留 100 空位
- 不单独定义 MeshesCollector 枚举；Navigator 分组由 `eMeshObjectType` 区间派生
- 混合 / 无法判定 → `UNKNOWN` → Others，`other_unknown_N`；Fem 内显示名唯一
- 更多网格类型待产品确定后补充枚举与映射表
- 默认名序号：**补空位**（最小未占用编号），不用高水位计数器

---

### 2026-07-08

**主题：** 讨论纪要合并；IdAllocator 重命名；家里 SSH 配置；默认命名与 `eMeshObjectType` 重构；FS 对齐。

**工程与协作：**

- 四份按日期的讨论纪要合并为 **`MeshObject-Discussion-Notes.md`**，后续只在此文件追加
- 家里 PC 配置 SSH（`~/.ssh/config` → `ssh.github.com:443`）；remote 改为 `git@github.com:...`；Cursor 命令行可 push
- GitHub 最新：`0ce1542`（main）

**DS 变更（V1.2 → V1.4）：**

| 版本 | 内容 |
|---|---|
| （commit） | 纪要合并；`femmgMeshObjectIdManager` → **`femmgMeshObjectIdAllocator`** |
| V1.3 | `eMeshObjectType` 取代 `eMeshesType`；`Create(pComps, nCmp, eType)`；FS 默认命名；Fem 内唯一 |
| V1.4 | 默认名序号**补空位**；补充 **`g_MOTypeInfoTable`** 静态映射表 |

**命名与 Create（已确认）：**

| 项 | 结论 |
|---|---|
| `Create` 接口 | `Create(pComps, nCmp, eType)`，**无** `name` 参数 |
| 默认名生成 | `femmgMeshObjectManager::GenerateDefaultDisplayName(eType)` |
| IdAllocator | **不**承担命名，只管 MOId |
| `eType` 来源 | **调用方传入**（Keep / 手工上下文）；Manager 不从 element 或划分设置推断 |
| 混合 / 无法判定 | `FEMMG_MO_TYPE_UNKNOWN` → Others，`other_unknown_N` |
| Fem 内重名 | Create 自动命名与 Rename 均校验；Rename 重名拒绝 |
| 序号策略 | **补空位**：`1,2,4` → 下一个是 `3`；不用高水位计数器 |

**`eMeshObjectType`（已确认）：**

- 单一枚举，**不**单独定义 MeshesCollector 枚举
- 每类 xD Meshes 预留 **100** 个枚举空位：`1..100`（1D）、`101..200`（2D）、`201..300`（3D）、`301..400`（Others）
- 当前已定义：BEAM(1)、SHELL(101)、SOLID(201)、RIGID(301)、CONSTRAINT(302)、UNKNOWN(0)
- **更多类型待产品确定**
- 静态表 `g_MOTypeInfoTable`：含 `iCollectorGroup`、默认名前缀/类型段、Navigator / Info 展示串（DS §3.3.1）

**参考文档：**

- FS 本地副本：`C:\Downloads\Function Specification\Function Specification.md`（默认名 §3.3.4）

**待下次继续：**

- §5.5 AFEM Map / §5.6 Copy FEM
- Info User Case
- 补充更多 `eMeshObjectType` 与手工入口映射
- 飞书 Wiki 与 GitHub V1.4 同步

---

### 2026-07-08（下午：Git 同步、MMF 规划）

**主题：** 从 GitHub 拉取 MeshObject；DS 与飞书双向同步；MMF4/MMF5 与 Roadmap 规划；飞书文档阅读方法修正。

**Git / DS 同步：**

| 操作 | 结果 |
|---|---|
| `git pull` MeshObject | `9e5f4a1` → `eb91e18`（V1.4，5 commits） |
| 按飞书 Wiki 更新本地 DS（V1.5 草案） | commit `c295eb2`：orphan Node、AFEM map、会议反馈 |
| 用户精简飞书后，**以飞书为唯一权威**覆盖本地 | commit `e631a6e`：恢复 `Vx.x`、精简 Terminology/附录；移除冗余 §4.3 等 |
| README | 权威来源改为飞书 Wiki 优先 |

**飞书文档阅读（教训）：**

- `docx_v1_document_rawContent` **读不到**嵌入电子表格与白板/UML
- MMF & RoadMap 的「MMF列表」「Roadmap」为嵌入 Sheet（`Vn0VsQsVohKXVCtKJqHcRUdgnfd`）
- 「MMF 拆分逻辑」为白板块（`PQZkwgPN7hqatObdX4IcNtdIn3g`），内容：`2606 MVP` → 三条线（右键菜单、Load&Constraint Object、Mesh Object）
- 已添加 Cursor 用户规则：**Feishu docs: check sheets and boards**

**MMF 规划结论：**

| MMF | 范围 | 状态 |
|---|---|---|
| MMF1 | Navigator 右键 + Non-Current FE Studies（S1–S8） | 飞书已填；Sprint 2–6 |
| MMF2 | LoadSet Force 几何&网格子实例（S1–S4） | 飞书已填；Sprint 2–5 |
| MMF3 | 其余 Load/Constraint Set（S1–S5） | 飞书已填；Sprint 5–10 |
| **MMF4** | Mesh Object **阶段一**（几何 Keep + Navigator 全套） | **待填入飞书 Sheet** |
| **MMF5** | Mesh Object **阶段二**（手工建网）+ **AFEM 汇入** | **待填入飞书 Sheet** |

**Story 拆分修正：**

- ❌ 不应将「Src 层对象模型」单独列为 User Story（用户不可感知，且为 S1 前置实现）
- ✅ MMF4 Story 按用户操作划分：S1 Keep 后出现 Mesh → S2 Delete → S3 Info → S4 Rename → S5 Show/Hide → S6 Save/Open
- ✅ MMF5：S1 手工建网出现 Mesh；S2 AFem Update 汇入；手工 Mesh 的 Info/Rename 等复用 MMF4，写入 DoD 即可

**参考链接：**

- DS（飞书）：https://ycntm1ix2za7.feishu.cn/wiki/PwilwM9Ayi75pVkQqU0cutWQn1f
- FS（飞书）：https://ycntm1ix2za7.feishu.cn/wiki/DqwgwzkjKiBZsHktQm8cfG4knUf
- MMF & RoadMap：https://ycntm1ix2za7.feishu.cn/wiki/Vx4ywFX5qiJXe8kzaqacyyvTndh

**待下次继续：**

- 将 MMF4/MMF5 写入飞书 MMF 列表 Sheet 并排 Roadmap Sprint
- MMF4/MMF5 与团队确认后锁定优先级与 Freeze 范围

---

### 2026-07-08（下午：Git 同步、MMF 规划）

**主题：** 从 GitHub 拉取 MeshObject；DS 与飞书双向同步；MMF4/MMF5 与 Roadmap 规划；飞书文档阅读方法修正。

**Git / DS 同步：**

| 操作 | 结果 |
|---|---|
| `git pull` MeshObject | `9e5f4a1` → `eb91e18`（V1.4，5 commits） |
| 按飞书 Wiki 更新本地 DS（V1.5 草案） | commit `c295eb2`：orphan Node、AFEM map、会议反馈 |
| 用户精简飞书后，**以飞书为唯一权威**覆盖本地 | commit `e631a6e`：恢复 `Vx.x`、精简 Terminology/附录；移除冗余 §4.3 等 |
| README | 权威来源改为飞书 Wiki 优先 |

**飞书文档阅读（教训）：**

- `docx_v1_document_rawContent` **读不到**嵌入电子表格与白板/UML
- MMF & RoadMap 的「MMF列表」「Roadmap」为嵌入 Sheet（`Vn0VsQsVohKXVCtKJqHcRUdgnfd`）
- 「MMF 拆分逻辑」为白板块（`PQZkwgPN7hqatObdX4IcNtdIn3g`），内容：`2606 MVP` → 三条线（右键菜单、Load&Constraint Object、Mesh Object）
- 已添加 Cursor 用户规则：**Feishu docs: check sheets and boards**

**MMF 规划结论：**

| MMF | 范围 | 状态 |
|---|---|---|
| MMF1 | Navigator 右键 + Non-Current FE Studies（S1–S8） | 飞书已填；Sprint 2–6 |
| MMF2 | LoadSet Force 几何&网格子实例（S1–S4） | 飞书已填；Sprint 2–5 |
| MMF3 | 其余 Load/Constraint Set（S1–S5） | 飞书已填；Sprint 5–10 |
| **MMF4** | Mesh Object **阶段一**（几何 Keep + Navigator 全套） | **待填入飞书 Sheet** |
| **MMF5** | Mesh Object **阶段二**（手工建网）+ **AFEM 汇入** | **待填入飞书 Sheet** |

**Story 拆分修正：**

- ❌ 不应将「Src 层对象模型」单独列为 User Story（用户不可感知，且为 S1 前置实现）
- ✅ MMF4 Story 按用户操作划分：S1 Keep 后出现 Mesh → S2 Delete → S3 Info → S4 Rename → S5 Show/Hide → S6 Save/Open
- ✅ MMF5：S1 手工建网出现 Mesh；S2 AFem Update 汇入；手工 Mesh 的 Info/Rename 等复用 MMF4，写入 DoD 即可

**参考链接：**

- DS（飞书）：https://ycntm1ix2za7.feishu.cn/wiki/PwilwM9Ayi75pVkQqU0cutWQn1f
- FS（飞书）：https://ycntm1ix2za7.feishu.cn/wiki/DqwgwzkjKiBZsHktQm8cfG4knUf
- MMF & RoadMap：https://ycntm1ix2za7.feishu.cn/wiki/Vx4ywFX5qiJXe8kzaqacyyvTndh

**待下次继续：**

- 将 MMF4/MMF5 写入飞书 MMF 列表 Sheet 并排 Roadmap Sprint
- MMF4/MMF5 与团队确认后锁定优先级与 Freeze 范围
