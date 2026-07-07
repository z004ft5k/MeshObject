# MeshObject 实现讨论总结

> 本文档汇总 2026-06 期间关于 MeshObject 阶段 2 Spike 及后期真正实现的设计讨论与代码结论。  
> 功能规格与早期架构讨论见 [Mesh-Object-Design-Discussion.md](./Mesh-Object-Design-Discussion.md)。

**文档版本：** 讨论稿 v1  
**最后更新：** 2026-06-25

---

## 1. 阶段划分（共识）

| 阶段 | 内容 |
|------|------|
| **阶段 1** | 只改 `element.iMeshObjectId`；Keep 写 `moId=1`；Open 后扫 element 建内存 MeshObject |
| **阶段 2（当前）** | 增加最小 MO_META 段（MOHEAP），只存 `moId + name`；Save/Open 一致 |
| **阶段 3** | 再加 `mst.iMeshObjectId`、Navigator、Delete、geom、mstRef、MOTREE 等 |

---

## 2. 核心数据分工

| 存什么 | 存哪里 | 说明 |
|--------|--------|------|
| Mesh 元数据（moId、name…） | **MOHEAP**（Heap Segment） | 阶段 2 仅 `{ moId, name }` |
| 单元归属 | **`element.iMeshObjectId`** | **唯一真相**；0 = 未归属 |
| 划分参数 | mst HAM bucket | 阶段 3 加 `iMeshObjectId` 反向关联 |
| 节点归属 | 不存 | 从 element 连接性推导 |

**不在 MOHEAP 存 element 列表**，避免与 EHeap 双写不一致。

---

## 3. 唯一数据结构：`MoHeapRecord`

讨论结论：**阶段 2 不需要单独的 `femmgMeshObject` C++ class**。

`MoHeapRecord` 是 C++、Fortran、MOHEAP 共用的唯一 struct：

```cpp
struct MoHeapRecord
{
    int  iMeshObjectId;
    char szDisplayName[FEMMG_K_MAX_DISPLAY_NAME];  // 256
};
```

- FSI 只读写 `MoHeapRecord`（via `fsihpio`）
- Open 时用 record 构造内存对象（即 `map<int, MoHeapRecord>`）
- 与 Element 侧一致：`femElem` 是 struct，没有 `femdaElemObject` class

**代码位置：** `neuecax/src/femmg/MoHeapRecord.hxx`

---

## 4. FSI 段类型：Heap，不是 Array

| 实体 | FSI 段类型 | 创建 API |
|------|-----------|----------|
| Node | **Array Segment** | `fsiarcr()` |
| Element | **Heap Segment** | `fsihpcr()` → EHeap、EAHeap |
| **MeshObject** | **Heap Segment (MOHEAP)** | `fsihpcr()` |

MeshObject 与 Element 同属 **Heap + Tree** 模式（阶段 3 加 MOTREE），不是 Node 那种定长 Array。

Element 侧两棵 Tree（`fmielmi`）：

| 段 | 含义 |
|----|------|
| **EMTree** | Element **Model** Tree：Label → Element ptr |
| **EGTree** | Element **Group** Tree：Group → Element 列表 |

MeshObject 阶段 3 对应 **MOTREE**（按 moId 查 MOHEAP 记录）；阶段 2 可顺序读，记录少时不必建 Tree。

---

## 5. 代码分层（对齐 femdaAccIC）

```
MoHeapRecord                    ← 唯一 struct（C++ / Fortran / 磁盘）
    │
    ├─ femmgMoFSIProxy          ← 读写 MOHEAP（类比 femdaAccFSIProxy / EHeap）
    ├─ femmgMeshObjectManager   ← map<int, MoHeapRecord> + 编排写盘/写内存
    ├─ femmgModel / femmgModelManager  ← 按 (hDb, femId) 查找 Manager
    ├─ femmgMoIdMgr (C)         ← 进程级 Id 分配
    └─ femmgMoBridge            ← Fortran 入口 fmmocre_ / fmimoin_ / fmmoidal_
```

### 5.1 Manager 职责（阶段 2）

```cpp
class femmgMeshObjectManager
{
    femStatus Create(int iMeshObjectId, const char* pszDisplayName);
    femStatus LoadFromFSI();
    const MoHeapRecord* QueryById(int iMeshObjectId, femStatus* pStat) const;
    // ...
    std::map<int, MoHeapRecord> m_zMeshObjects;
    femmgMoFSIProxy* m_pzMoFSI;
};
```

**Create 流程：**

1. `m_pzMoFSI->MoAdd(zRec)` → 写 MOHEAP  
2. `RegisterInMemory(zRec)` → 写入 `m_zMeshObjects`

**Open 流程：**

1. `MoReadAll()` → 逐条 `RegisterInMemory`  
2. （单元归属从 `element.iMeshObjectId` 扫，不存 MOHEAP）

### 5.2 Fortran 与 C++ 统一入口

Fortran **禁止**直接写 MOHEAP，必须走 C 桥，保证内存与磁盘同步：

```fortran
CALL fmmoidal(hDb, femId, moId, ierr)      ! 分配 id（或阶段 2 写死 moId=1）
CALL fmmocre(hDb, femId, moId, moName, 256, ierr)  ! Create
```

C++ 侧同样：

```cpp
femmgModelManager::Instance()
    .GetMeshObjectManager(hDb, femId, &stat)
    ->Create(moId, name);
```

段创建（`fsihpcr`）可留在 Fortran（`fmimoin_`，类比 `fmielmi`）；**写单条 MeshObject 记录**统一走 `fmmocre_`。

---

## 6. MeshObjectId 分配器（C）

进程级单例，按 `(hDb, femId)` 分桶；Id 从 1 开始，0 保留为未归属。

**代码位置：** `neuecax/src/femmg/femmgMoIdMgr.h` / `.c`

| API | 用途 |
|-----|------|
| `femmgMoIdMgrAllocate` | Keep 时分配新 moId |
| `femmgMoIdMgrSetNextId` | Open 时从 MOHEAP 段头恢复 |
| `femmgMoIdMgrGetNextId` | Save 时写入段头 |
| `fmmoidal_` | Fortran 分配入口 |

阶段 2 可写死 `moId=1`；接 IdAllocator 后每次 Keep 自动递增。

---

## 7. 两层存储模型（Open / Save）

与 `femElem` / EHEAP 分工一致：

| 层 | 内容 |
|----|------|
| **持久化（FSI / MOHEAP）** | `MoHeapRecord` POD；fsihpio 读写 |
| **运行时（内存）** | `map<int, MoHeapRecord>`；Open 时从 MOHEAP 加载 |

Open 不一致处理（设计原则）：

- MOHEAP 有 record 但无 element → 按 FS 空 Mesh 规则丢弃  
- element 有 moId 但 MOHEAP 无 record → FS-MO-L-I01 补建（旧文件）

---

## 8. 后期真正实现：Element 生命周期

### 8.1 删除 — 在 `deleteElm` 单入口挂钩 ✅

不禁止原有删除路径；底层只有一个 `deleteElm`，适合集中拦截。

```
ElmRemoveByPtr(iElPtr):
  1. Query element → 读出 iMeshObjectId（删前必须读）
  2. 执行原有 deleteElm
  3. if (moId > 0) OnElementRemoved(moId)
       --m_zElementCount[moId]
       if (count <= 0) Delete(moId)   // MOHEAP + 内存
```

**行为：**

- Mesh 有 10 个 element，删 2 个 → MeshObject 仍在  
- 10 个全删 → MeshObject 自动删除（FS 空 Mesh 规则）

**性能：** `map<int,int>` 增减相对 EHeap/Tree 可忽略；无实质性能问题。

### 8.2 创建 — 不在 `addElm` 里推断 MeshObject

`addElm` 不知道 element 属于哪个 Mesh；**Create MeshObject 是显式业务操作**（Keep / Manual Done），不在 add 里自动创建。

**推荐：在 `femElem` 上增加 `iMeshObjectId` 字段**

```cpp
// 调用方填好再 ElmAdd；不必改 addElm 签名
femElem elem;
elem.iMeshObjectId = moId;   // Keep 时
// 或 = 0（非 Keep / 未归属）
ElmAdd(elem, &iElPtr);
```

| 方案 | 评价 |
|------|------|
| `femElem.iMeshObjectId` + ElmAdd | **推荐** |
| 改 `addElm(..., moId)` 签名 | 改动面大 |
| Add 后 Modify 写 moId | Spike 可用，略繁琐 |
| KeepSession（见下） | Keep 批量建网时的便利层 |

**创建入口对称挂钩：**

```
ElmAdd 成功后:
  if (elem.iMeshObjectId > 0)
      OnElementAdded(moId);   // ++m_zElementCount[moId]
```

### 8.3 单元计数缓存

```cpp
std::map<int, int> m_zElementCount;  // moId → count
```

| 时机 | 操作 |
|------|------|
| Open | 扫 element 初始化 count（一次） |
| ElmAdd | `moId > 0` → `++` |
| ElmRemove | 删前读 moId → `--`；为 0 → Delete Mesh |
| Import / Copy | 重建或 rescan |
| Modify moId（若允许） | 旧 mo `--`，新 mo `++` |

权威仍是 `element.iMeshObjectId`；count 是缓存，不一致时可 rescan 修复。

### 8.4 创建 vs 删除的不对称（合理）

| 操作 | 方式 |
|------|------|
| **Create MeshObject** | 显式：Keep / Manual Done 时 `Allocate` + `Create` |
| **Delete MeshObject** | 隐式：`deleteElm` 挂钩，最后一个 element 没了才删 |
| **绑定 element** | 创建时写 `iMeshObjectId` |
| **解绑 element** | deleteElm 自动（element 已不存在） |

---

## 9. KeepSession（可选，后期）

**不是现有代码**，是一种可选设计模式：Keep 期间的 **Fem 级「当前 moId」上下文**。

```
Keep 开始:
  moId = Allocate()
  Create(moId, name)
  KeepContext.Begin(hDb, femId, moId)

  ... 大量 ElmAdd，底层读 GetCurrentMoId() 自动填 iMeshObjectId ...

Keep 结束:
  KeepContext.End(hDb, femId)
```

**作用：** 拿 moId 更方便，Fortran/C++ 不用层层传参，也不必改 `addElm` 签名。

**限制：**

- 只解决「写 element 时填哪个 moId」  
- **何时 Begin/End、何时 Allocate 新 id，仍由 Keep 流程显式控制**  
- 删 element、空 Mesh 自动删除 → 仍靠 `deleteElm` 挂钩，与 KeepSession 无关  

阶段 2 可不用 KeepSession，Keep 写死 `moId=1` 或调用方直接填 `femElem.iMeshObjectId`。

---

## 10. Keep 完整流程（后期目标）

```
mstKeepMesh:
  1. moId = femmgMoIdMgrAllocate(hDb, femId)
  2. Manager.Create(moId, name)
  3. [可选] KeepContext.Begin(hDb, femId, moId)
  4. 本次 mst bucket: iMeshObjectId = moId        （阶段 3）
  5. 本次新单元: femElem.iMeshObjectId = moId → ElmAdd → OnElementAdded
  6. [可选] KeepContext.End(hDb, femId)
  7. Navigator 出现 Mesh 节点                             （阶段 3）
```

---

## 11. 已生成代码清单

| 文件 | 说明 |
|------|------|
| `MoHeapRecord.hxx` / `.cxx` | MeshObject 唯一 struct |
| `femmgMeshObjectManager.hxx` / `.cxx` | 内存 map + Create / LoadFromFSI |
| `femmgMoFSIProxy.hxx` / `.cxx` | MOHEAP FSI 层（fsihpio TODO） |
| `femmgModel.hxx` / `.cxx` | Fem 级，持有 Manager |
| `femmgModelManager.hxx` / `.cxx` | 进程单例，按 (hDb, femId) 查找 |
| `femmgMoBridge.hxx` / `.cxx` | `fmmocre_` / `fmimoin_` |
| `femmgMoIdMgr.h` / `.c` | C 语言 Id 分配器 + `fmmoidal_` |

**已删除：** `femmgMeshObject` class、`femmgTypes.hxx`（阶段 2 不需要）

---

## 12. 待办（Spike → 阶段 3）

| 项 | 说明 |
|----|------|
| `fsihpcr` / `fsihpio` 接 MOHEAP | `femmgMoFSIProxy` TODO |
| `femElem.iMeshObjectId` | EHEAP 或 ElemAD slot |
| `deleteElm` / `ElmAdd` 挂钩 | OnElementRemoved / OnElementAdded + count |
| MOHEAP 段头 `nextMeshObjectId` | Open/Save 与 IdAlloc 同步 |
| MOTREE | 阶段 3 |
| KeepSession | 可选，Keep 批量建网 |
| Navigator / Delete / Show-Hide | 阶段 3 |

---

## 13. 关键原则（一句话）

> **MoHeapRecord 是唯一 MeshObject struct；MOHEAP 存元数据，element.iMeshObjectId 存归属；Create Mesh 显式、Delete Mesh 在 deleteElm 推导；Id 由 femmgMoIdMgr 按 Fem 分配；C++ 与 Fortran 统一走 Manager + Bridge，不直接写 MOHEAP。**
