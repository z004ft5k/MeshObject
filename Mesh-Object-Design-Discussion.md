# MeshObject 设计讨论总结

> 本文档汇总 MeshObject 数据结构、Spike 实施与相关代码机制的讨论结论。  
> 功能行为规格见 [Mesh-Object-FS-v0.2.md](./Mesh-Object-FS-v0.2.md)；技术调研见飞书 [Mesh Spike](https://ycntm1ix2za7.feishu.cn/wiki/OUc5wKwT7iSwAnkFQFUc8yYcnNh)。

**文档版本：** 讨论稿 v2  
**最后更新：** 2026-06-23

---

## 1. 背景与目标

### 1.1 问题

NeueCAX 当前网格以分散的节点、单元和 mst 划分设置存在，缺少与 NX 对等的 **MeshObject**（UI 显示名：**Mesh**）抽象。用户无法「一次 Keep、一次整包删除/隐藏/查询」。

### 1.2 阶段范围

| 阶段 | 内容 |
|------|------|
| **阶段一** | Define / Preview / Generate / Keep 不变；Keep 成功自动创建 MeshObject；Navigator 支持 Info / Rename / Delete / Show-Hide |
| **阶段二** | 手工建节点 + 建单元也产生 MeshObject |

### 1.3 核心语义

- **一次 Keep = 一个 MeshObject**（多个 Face/Region 同属一个）
- **一个单元最多归属一个 MeshObject**
- **删除 MeshObject** → 删全部归属单元 + 仅被这些单元使用的节点 + 划分设置；**不删几何**
- Preview 未 Keep **不产生** MeshObject

---

## 2. 对象模型与 ID

### 2.1 三个 ID

| ID | 粒度 | 存储位置 | 作用 |
|----|------|----------|------|
| **iMeshId** | 每个 Face/Region | mst HAM bucket | 划分参数 bucket（已有） |
| **MeshObjectId** | 每次 Keep | MOHEAP + element + mst bucket | 逻辑 Mesh 整包 |
| **Element/Node Label** | 每个实体 | EHEAP / NARRAY | FEM 基础实体 |

### 2.2 存储分工（共识）

| 存什么 | 存哪里 | 说明 |
|--------|--------|------|
| 划分参数 | mst HAM bucket | 权威；加 `iMeshObjectId` 反向关联 |
| MeshObject 元数据 | MOHEAP（`MoHeapRecord`） | moId、name；后续可扩展 collector 等 |
| 单元归属 | **element.iMeshObjectId** | **成员关系唯一真相** |
| 节点 | 不存 MeshObjectId | 从 element.piNL[] 推导 |
| element 列表 | **不存 MOHEAP** | Open 后扫描 element 分组重建 |

**修订：** MOHEAP **不必**存 mstRef、划分参数副本、全量 element 列表；有 `bucket.iMeshObjectId` 后可反向查 bucket；geom 摘要可 Keep 时写入或按需从 mst 推导。

### 2.3 一次 Keep 示例

```
MeshObject #1 (3d_solid_1)
├── Face A: mst bucket, iMeshId=101, iMeshObjectId=1
├── Face B: mst bucket, iMeshId=102, iMeshObjectId=1
├── Element #1001.. (iMeshObjectId=1)
└── Element #2001.. (iMeshObjectId=1)
```

---

## 3. 架构：Element 层 vs MeshObject 层

### 3.1 两层职责

```
Element 层（现有）                    MeshObject 层（新增）
─────────────────                    ─────────────────
femElem (struct, POD)                MoHeapRecord (POD, MOHEAP)
    ↑↓                                   ↔
femdaIAcc / ElmAdd / feucre            femmgMeshObjectManager
FEM 基础 CRUD                          逻辑整包管理 + Navigator 语义
```

- **`femElem`**：FSI 扁平记录，一堆函数通过 `femdaIAcc` 操作 struct
- **MeshObject**：建在 Element 之上的**逻辑管理层**，面向 Keep/Delete/Rename/Navigator
- **不是**替代 Element 存储，而是 **element.iMeshObjectId + MO 元数据** 表达「整包」

### 3.2 当前代码实现（Stage 2）

```
neuecax/src/femmg/
├── MoHeapRecord.hxx/cxx     // POD：iMeshObjectId + szDisplayName
├── femmgMoFSIProxy          // MOHEAP fsihpio 读写
└── femmgMeshObjectManager   // Fem 级 map<moId, MoHeapRecord>
```

**实现选择：** 当前 **不单独做 `femmgMeshObject` class**，`MoHeapRecord` 为 C++/Fortran/FSI 共用唯一表示；Manager 持内存副本并委托 `femmgMoFSIProxy` 持久化。

讨论中曾设计 `femmgMeshObject` class + `MoHeapRecord` 双层；轻量阶段可只用 `MoHeapRecord`，后续若需 Rename/缓存 element 列表再包 class。

### 3.3 Manager 与 IdManager

| 组件 | 层级 | 说明 |
|------|------|------|
| **MeshObjectIdManager** | 进程单例 | `Allocate/Release/Save/Open`；Id 空间按 `(hDb, femId)` 分桶 |
| **MeshObjectManager** | Fem 级 | 挂 `femmgModel`；`Create` / `LoadFromFSI` / `QueryById` |

不需要单独 `MeshObjectId` class，Id 就是 `int`。

### 3.4 Open / Save 流程

**Save：**

```
Manager 遍历 MoHeapRecord → femmgMoFSIProxy → MOHEAP
element.iMeshObjectId / mst.iMeshObjectId 已在各自路径持久化
```

**Open：**

```
1. LoadFromFSI() → 读 MO_META 到 m_zMeshObjects
2. 扫描 element（ElmCreateIter + Filter）按 iMeshObjectId 分组
3. （可选）BindElement 建内存索引
4. mst bucket 通过 iMeshObjectId 反查
```

**轻量持久化 + Open 重建：** 不必持久化完整 MeshObject 对象；**必须**持久化 moId + name 等元数据；成员关系靠 element 重建。

---

## 4. femElem 与 Spike ②（element.iMeshObjectId）

### 4.1 EHEAP 布局

```
[ common ints: fem_kNUMCOM 个 ]
[ beam: piBS, 长度 fem_kBEAMLEN ]   // 仅 IsBeam 时
[ node labels: piNL, 长度 nNod ]
```

**`fem_kNUMCOM = 7` 的原因：** 只统计写入 EHEAP common 区的 int，**不含 `nNod`**：

```
heap[0] iLabel
heap[1] iMask
heap[2] iFeDsc
heap[3] iColor
heap[4] iPid
heap[5] iMid
heap[6] iADPtr
heap[7..] beam + piNL 数据
```

`nNod` 是运行时字段，读回时用 `iNumBytes - fem_kNUMCOM - iBeamStore` 推算。

### 4.2 新增 iMeshObjectId 的推荐位置

```c
Integer iMid;
Integer iADPtr;         // heap[6]，保持不动
Integer iMeshObjectId;  // heap[7]，新增
Integer nNod;           // 不进 heap
Integer* piBS;
Integer* piNL;
#define fem_kNUMCOM  8
```

**不要放在 `iADPtr` 前面**（会把 `iADPtr` 挤到 heap[7]，需改 `6*sizeof(int)` 等硬编码）。

### 4.3 ElmAdd / ElmQuery / ElmModify 必须对称

凡使用 `fem_kNUMCOM` 的路径都要改：

- `femdaAccFSIProxy::ElmAdd` — 分配、`memcpy`、写入字节数
- `ElmQueryByPtr` — 读 common、算 nNod、读 piBS/piNL 偏移
- `ElmModify` — 同上
- `femdaAccIC` 若有独立实现，一并改

### 4.4 相关字段说明

| 字段 | 含义 |
|------|------|
| **piNL** | 节点 label 连接表 |
| **piBS** | Beam 单元额外 int 数组；非梁时长度为 0 |
| **iADPtr** | 指向 **EADHeap** 附加数据的指针；与 MeshObjectId 无关 |

Beam 路径布局：`[common 8][piBS][piNL]`。若 `fem_kNUMCOM` 未改或 struct 字段顺序错，**piBS 与 iMeshObjectId 会冲突**。

### 4.5 其它常量

- **`femda_kAVG_ELEM_SIZE = 15`**：InCore 列表预分配估计值，建议改为 **16**（+1 common int）；**不会**导致乱码，只影响预分配效率
- **`sizeof(femElem)` 相关常量**：编译期自动更新；**`fem_kNUMCOM` 必须手改**

### 4.6 乱码根因（已验证）

只改 `femElem` 不改 `fem_kNUMCOM` → `iMeshObjectId` 未写入 EHEAP → 读回 garbage。

---

## 5. Spike ①：mst bucket

### 5.1 mst_TzRegion 加字段

```c
Integer iMeshObjectId;  /* 0 = none；C struct 里不能写 = 1 */
```

Spike 时在 Keep 路径写 `= 1`；Define OK 时 `= 0`。

### 5.2 msta3d1 流程摘要

Region 网格参数主访问：`QUERY / MODIFY / DELETE`。

```
参数校验 → fhmagh1 查 HAM → 未定义则 mstard1 读默认
→ 已定义：Free→tqmare，Mapped→mpmare1 → MODIFY 时 mstuinc/mstudec
```

Spike ① 还要在 **tqmare/mpmare1 的 bucket 读写** 里同步 `iMeshObjectId`。

---

## 6. Spike ③：MOHEAP

### 6.1 MoHeapRecord（当前）

```cpp
struct MoHeapRecord {
    int  iMeshObjectId;
    char szDisplayName[FEMMG_K_MAX_DISPLAY_NAME];  // 256
};
```

FSI 通过 `femmgMoFSIProxy::MoAdd` / `MoReadAll` 读写；**不能**把整个 C++ class 写入 FSI。

### 6.2 struct vs class

| | femElem / MoHeapRecord | MeshObject 管理 |
|--|------------------------|-----------------|
| 类型 | struct（POD） | Manager（class）；可选再包 femmgMeshObject |
| 持久化 | 扁平 int/char 数组 | MoHeapRecord |
| FSI | ✅ | ✅（仅 POD 记录） |

### 6.3 Spike 顺序（用户确定）

| 顺序 | 内容 |
|------|------|
| ① | mst bucket `iMeshObjectId` |
| ② | element `iMeshObjectId` + `fem_kNUMCOM` |
| ③ 最小 | MOHEAP 读写 1 条 record |
| ③ 大 | MOTREE、collector、nextMoId 等 |
| 串联 | 等单项完成后再做 |

---

## 7. 代码机制参考（谈话中梳理）

### 7.1 FindNextMeshID / iMeshId

- 非单例；扫 HAM bucket 取 max+1
- 作用域 `(hDb, femId)`
- **MeshObjectId** 应用 MOHEAP nextId，不必扫 HAM

### 7.2 tqmStoreMesh / tqmFinalElementAccess

- **tqm**：生成期；Final Element 存 **FHS 或 FSI 临时树**（`tqmFsiTreeFlag`）
- **tqmFinalElementAccess**：Final Element 的 CRUD + 迭代（iOpt 0=Store, 1=Query, 2=Delete, 4=Next, 5=Rewind）
- **Store 后**：`fmnddb→femdaAddNode`，`fmeldb→feucre→femdaAddElem` 进应用 IDF
- FHS/FSI 临时库 ≠ 最终 mf1；MeshObject 应挂在 **FSI 应用层**

### 7.3 femmgModel / TeBuildView

| TeBuildView | 含义 |
|-------------|------|
| eNone | 仅 femmgModel |
| eAccessOnly | + femdaIAcc |
| eFreeFace | + femdaFaceView（自由单元面，外表面） |
| eFeatureEdge | + femdaEdgeView |

**无 FreeRegion**：Region 是 mst/几何划分参数，不是从单元推导的拓扑视图。

Face/Edge View 用途：显示外壳、拾取、按面/边删网格；与 MeshObject 不同层。

### 7.4 NX Mesh / Collector 行为（仅 NX，不对标实现）

- 一次 mesh 操作 ≈ 一个 **Mesh** 叶子节点
- **具名 Mesh Collector**（如 3dCollector1）绑 **Physical Property Table**；其下 Mesh **共享** PPT（材料通常也一致）
- **不是**按材料自动分组；用户把 Mesh 放进绑了对应 PPT 的 Collector
- 维度 Collector（1D/2D/3D）≠ 按材料分

---

## 8. 创建流程（Define + Solid Keep）

```
Define OK  → mst_TzRegion (iMeshId=0, iMeshObjectId=0)
Preview/Generate → 临时单元；未 Keep 无 MeshObject
Keep (mstKeepMesh):
  1. moId = Allocate (或 Spike 硬编码 1)
  2. MeshObjectManager.Create(moId, name)
  3. mst bucket.iMeshObjectId = moId
  4. 新单元.iMeshObjectId = moId (ElmAdd 路径)
```

---

## 9. 查询与性能

| 操作 | 方式 |
|------|------|
| 某 Mesh 的 element | `ElmCreateIter` + Filter(moId)；或内存 `map<moId, elPtrs>` |
| 某 Mesh 的 node | 对 element.piNL 并集 |
| Information 名称 | `MoHeapRecord.szDisplayName` |
| 划分设置 | 查 mst bucket，不在 MO 重复存 |

---

## 10. 已达成共识

1. element.iMeshObjectId 为成员归属唯一真相；节点不存 moId
2. MOHEAP 存轻量元数据（MoHeapRecord）；不存 element 列表
3. mst bucket 加 iMeshObjectId；划分参数仍在 bucket
4. MeshObjectManager Fem 级；IdManager 进程单例 + 按 Fem 分桶
5. iMeshObjectId 放在 iADPtr 后、nNod 前；fem_kNUMCOM 7→8
6. FSI 不能直接存 C++ class；持久化用 POD
7. Open 后可从 element 分组重建逻辑关系；元数据仍须 Save
8. Spike 顺序：① mst → ② element → ③最小 → ③大 → 串联

---

## 11. 待后续

| 项 | 说明 |
|----|------|
| IdManager 完整实现 | Allocate、Copy remap |
| BindElement / Delete / Rename | Manager API |
| Collector、Source 写入 MoHeapRecord | ③ 大 |
| mst Spike ① bucket 下标 | mst_kCOM_MESHOBJECTID |
| Beam 路径全量回归 | piBS 偏移 |
| Copy FEM / AFem / UNV | mstucp2、FS-MO-L-I01 |
| 是否恢复 femmgMeshObject class | 视 Navigator 复杂度 |

---

## 12. 关键原则（一句话）

> **element 存归属，MOHEAP 存元数据，mst 存划分设置；Manager 管逻辑整包；FSI 只存 POD；Open 后扫描 element 重建成员关系。**

---

## 13. 相关文件

| 路径 | 说明 |
|------|------|
| `neuecax/src/femmg/MoHeapRecord.hxx` | MO 持久化 struct |
| `neuecax/src/femmg/femmgMeshObjectManager.hxx/cxx` | Fem 级 Manager |
| `neuecax/src/femmg/femmgMoFSIProxy` | MOHEAP FSI 代理 |
| `neuecax/src/femdai/femdaIAcc.hxx` | Element CRUD 接口 |
| `femdaAccFSIProxy::ElmAdd/ElmQueryByPtr` | EHEAP 读写 |
| `mstmshid.c` | FindNextMeshID |
| `msta3d1` | Region bucket 访问 |

---

## 14. 讨论索引

| 主题 | 结论 |
|------|------|
| MO 是否还要存 mstRef/划分参数 | 不必；bucket 反向关联 + 按需读 |
| 能否只持久化 element.moId | 不行；name 等元数据要 MOHEAP |
| MoHeapRecord vs class | 当前仅 MoHeapRecord；FSI 存 POD |
| fem_kNUMCOM=7 | 不含 nNod；加 moId 后=8 |
| piBS / Beam 冲突 | common 长度/顺序必须一致 |
| iADPtr | EADHeap 附加数据指针 |
| CRUD | Create/Read/Update/Delete |
| NX 具名 Collector | 绑 PPT，非按材料自动分 |
