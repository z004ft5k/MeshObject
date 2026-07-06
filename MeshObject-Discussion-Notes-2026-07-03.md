# MeshObject 讨论纪要 - 2026-07-03

本文档整理 2026-07-03 关于 MeshObject DS、架构分层、命名与 `femmgMeshObjectIdManager` 的讨论结论，供下次继续。

---

## 1. 今日讨论主题概览

1. Model / Entity / Adapter / Src 四层架构是否合理，是否冗余
2. `meshObject` 命名与 `MeshObjectRecord` 定名
3. `MeshObjectRecord` 是否用 `vector` 还是 `nCmp + pComps`
4. `femmgMeshObjectIdManager` 设计与文档补充
5. DS 文档更新与 Wiki 目录结构对齐

---

## 2. 架构分层结论

### 2.1 四层关系

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

### 2.2 为什么需要 Entity 和 Adapter

- Src / Database 是 legacy C/Fortran + FSI，不能直接暴露现代 C++ OO 给 UI
- Entity：对 `MeshObject` 的对象化封装，提供 Create/Rename/Delete/Info 等语义
- Adapter：隔离编译依赖、语言边界、持久化格式与运行时对象，连接 Application Model 与 Src

### 2.3 避免冗余的原则

| 层 | 职责 | 不做什么 |
|---|---|---|
| **Entity** | 对象语义，面向 UI | 不是数据真相；不是 Manager 的简单翻版 |
| **Adapter** | 跨层翻译 (hDb,femId,moId) ↔ IEntity | 不存真相 |
| **femmgMeshObjectManager** | 管理 MeshObjectRecord、持久化、计数缓存 | 不分配 MOId |
| **femmgMeshObjectIdManager** | 分配 MOId | 不管理 MeshObject 业务数据 |

数据真相：
- 成员关系 → `element.iMeshObjectId`
- MeshObject 元数据 → `MeshObjectRecord` + MOHEAP/MOTREE

---

## 3. 命名约定（已确认）

| 概念 | 名称 |
|---|---|
| 逻辑概念 / UI 显示 | MeshObject / Mesh |
| Entity 层 | MeshObject Entity（概念描述，类名待定） |
| Src 运行时 struct | **MeshObjectRecord** |
| MOHEAP 持久化布局 | **MOHeapRecord** |
| Manager | femmgMeshObjectManager |
| Id 分配器 | **femmgMeshObjectIdManager** |
| Fortran/C 桥 | **GetNextMeshObjectId** |
| 字段 | element.iMeshObjectId / MOId |

**约定：MeshObject 缩写统一写 `MO`（两个字母均大写）**：MOHEAP、MOTREE、MOHeapRecord。

---

## 4. MeshObjectRecord 结构（已确认）

```cpp
struct MeshObjectRecord
{
    int          iMeshObjectId;
    char         szDisplayName[128];
    int          nCmp;
    fgm_TzCmp*   pComps;
};
```

要点：

- **不用** `std::vector<fgm_TzCmp>` 作为落盘 struct 字段；用 `nCmp + pComps` 更贴近 C/FSI 风格
- 运行时可在 Manager 内管理 `pComps` 内存；持久化为变长 MOHEAP record
- `pComps` 非空 → 几何 Keep；`pComps` 为空 → 手工创建
- **不需要**与 `mst_zRegion` 关联；手工 element 也通过 `iMeshObjectId` 归属

### femmgMeshObjectManager 运行时缓存

```cpp
std::map<int, MeshObjectRecord> m_MOIdToRecordMap;
std::map<int, int>              m_MOIdToElementCountMap;
```

---

## 5. femmgMeshObjectIdManager（今日重点）

### 5.1 定位

- **Fem 级**，挂在 `femmgModel` 下，与 `femmgMeshObjectManager` **并列**
- 只负责 **MOId 分配**，不管理 MeshObjectRecord 业务

```text
femmgModel
  ├── femmgMeshObjectIdManager
  └── femmgMeshObjectManager
```

### 5.2 API（精简）

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

- Fortran 入口：`GetNextMeshObjectId(hDb, femId, &moId)` → 内部调 `Allocate()`
- **不需要** `GetNextId()` 只读接口

### 5.3 分配规则

- `0` 保留为未归属
- MOId 从 `1` 开始**单调递增**，**不回收**
- Open 时：`m_iNextMeshObjectId = max(已有 record 的 iMeshObjectId) + 1`；无 record 则从 `1` 开始
- Save 时：只持久化各 `MeshObjectRecord`，**不写**单独的 nextId 字段
- Delete MeshObject：**不降低** `m_iNextMeshObjectId`

### 5.4 创建调用顺序（已确认）

```text
1. moId = femmgMeshObjectIdManager.Allocate()
2. femmgMeshObjectManager.Create(moId, record...)
3. element.iMeshObjectId = moId
4. Save
```

### 5.5 AFEM 合成（已讨论，待细化实现）

多个 FEM 合成一个 AFEM 时：

- AFEM 有独立的 `femmgMeshObjectIdManager`
- 必须为 AFEM **重新分配 MOId**
- 维护 remap：`(sourceFemId, oldMOId) -> newMOId`
- 拷贝 element 时更新 AFEM 侧 `element.iMeshObjectId`

```text
FEM-A: MO #1, #2
FEM-B: MO #3
        ↓
AFEM:  MO #1, #2, #3（AFEM 自己的 Id 空间）
```

---

## 6. 继承自 2026-07-02 且仍有效的结论

### element 归属（B 类）
- `iMeshObjectId` 在 `femElem`，EHEAP common 区，`iADPtr` 后
- 调用方在 `ElmAdd` 前填写；不改 `ElmAdd` 签名
- Open 后扫描 element 重建 `m_MOIdToElementCountMap`

### Manager / Delete（C 类）
- Create 显式；不在 `ElmAdd` 里自动创建 MeshObject
- 无 Bind/Unbind API
- Delete：几何路径用 `pComps` + `mstudel`；手工路径按 `iMeshObjectId` 删 element
- 删除一致性：底层删除成功后才移除 MeshObject 元数据
- Entity 层不暴露 IdMgr

### 产品阶段
- 阶段一：Keep + Navigator（Info/Rename/Delete/Show-Hide）
- 阶段二：手工建网也形成 MeshObject

### 持久化
- MOHEAP + MOTREE，FEM Record Field 2
- 变长 record：iMeshObjectId + name + nCmp + fgm_TzCmp[]

---

## 7. DS 文档状态

### 7.1 本地主文档

`MeshObject/MeshObjectDesignSpecificaiton.md`（**V1.2**）

### 7.2 Wiki 目录结构（用户手动调整后应对齐）

```text
1. Introduction
2. Overview（含 2.4 Terminology）
3. High Level Design
   3.1 架构层次
   3.2 核心语义
   3.3 核心数据结构（含 3.3.3 MOId 管理器）
   3.4 各层职责
4. Detailed Design
   4.1 Src 层设计（含 IdManager、AFEM）
   4.2 Entity 层设计
   4.3 UI / Navigator
   4.4 Persistence Design
   4.5 Lifecycle Design
5. User Case（5.1–5.4）
6. Appendix
```

### 7.3 文档写作原则（用户要求）

- **不做的事情，除非很重要，否则不写进文档**
- 用正向表述（写什么），少写「不采用 xxx」

### 7.4 飞书限制

- MCP **无法直接修改** Wiki 已有 docx 目录/正文，只能导入新 docx
- 更新 Wiki 建议：以本地 `MeshObjectDesignSpecificaiton.md` 为准复制粘贴

### 7.5 Wiki 链接

- 用户维护的 Wiki：https://ycntm1ix2za7.feishu.cn/wiki/PwilwM9Ayi75pVkQqU0cutWQn1f

---

## 8. 待下次继续的事项

### 8.1 设计待补充

| 项 | 状态 |
|---|---|
| Copy FEM 的 MOId remap | 待补充 |
| CheckIn / CheckOut | 待补充 |
| 2606 前 mf1 / UNV 导入规则 | 待补充 |
| Model Entity 层详细设计 | 待写 |
| Navigator-UI 层详细设计 | 待写 |
| Adapter (`FEDataModelAdapter`) 接口清单 | 待写 |
| User Case 5.1–5.4 具体内容 | 待写 |

### 8.2 实现待对齐

- 代码中 `femmgMoIdMgr` 需重命名/重构为 `femmgMeshObjectIdManager`（Fem-based，挂 femmgModel）
- `MoHeapRecord` → `MeshObjectRecord` 命名统一
- 实现 `GetNextMeshObjectId` C 桥

### 8.3 建议下次讨论顺序

1. Copy FEM 与 AFEM remap 细节是否同一套机制
2. Entity 类名与 Adapter 接口表
3. Navigator 节点创建/刷新/删除的事件链路
4. User Case 5.1 打开 Mf1 的完整流程

---

## 9. 关键一句话总结

> **MeshObjectRecord 存元数据与 pComps，element.iMeshObjectId 存归属；femmgMeshObjectIdManager（Fem 级）分配 MOId，femmgMeshObjectManager 管记录与持久化；Entity/Adapter 服务 UI，Open 时扫描 record 初始化 nextMOId。**
