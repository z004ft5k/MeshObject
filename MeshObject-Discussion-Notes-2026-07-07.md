# MeshObject 讨论纪要 - 2026-07-07

本文档整理 2026-07-07 与 Cursor 的讨论结论，供下次继续。承接 [2026-07-06 纪要](MeshObject-Discussion-Notes-2026-07-06.md)。

---

## 1. 今日讨论主题概览

1. 继续 §5.3 删除、§5.4 Rename 设计与 DS 落稿（V1.1 已含精简版）
2. 补充 `eMeshesType` / Navigator Meshes 节点归属（§4.3）
3. 本地 DS 与飞书 Wiki 对照；GitHub 为版本真相
4. §5 User Case 增补占位：§5.5 AFEM Map、§5.6 Copy FEM、§5.7 几何修改 / Remesh
5. §5.2 / §5.3 User Case 术语：几何网格 Keep、手工网格（仅第五章）
6. 协作约定：未确认内容不主动补充进 DS
7. 删除路径性能澄清（挂钩 vs 整包 O(N)）

---

## 2. 文档与协作约定（今日强化）

| 用途 | 位置 |
|---|---|
| 版本真相 | GitHub：https://github.com/z004ft5k/MeshObject |
| 阅读与协作 | 飞书 Wiki DS / FS |
| 本地编辑 | `C:\Users\xin.zeng\Documents\CurProjects\MeshObject\` |

- 本地主文档：`MeshObjectDesignSpecificaiton.md`，当前 **V1.2**
- 每次讨论后：更新 DS（仅改确认内容）→ 写本讨论纪要 → `git commit` + `push`
- **编辑原则**：只改用户明确要求或已共同确认的内容；占位仅写「待补充」，不展开、不联想、不擅自改其他章节术语
- Git CLI：可用仓库内 `scripts/git.ps1` / `push-to-github.ps1`（捆绑 GitHub Desktop 的 git）

---

## 3. 今日 DS 变更摘要（V1.1 → V1.2）

| 版本 | 内容 |
|---|---|
| V1.1 | `eMeshesType`；§4.3 Meshes 归属；§5.3 删除、§5.4 Rename；对齐飞书 FS |
| V1.2 | §5.5–§5.7 占位；§5.2/§5.3 User Case 用语改为几何网格 / 手工网格 |

**刻意未改**：§1–§4 仍保留「几何 Keep」「手工建网」等原有表述（用户要求不擅自扩写）。

---

## 4. User Case 进度

| 章节 | 状态 |
|---|---|
| §5.1 打开 mf1 | ✅ |
| §5.2 创建 | ✅（路径 A 几何网格 Keep / 路径 B 手工网格） |
| §5.3 删除 | ✅ |
| §5.4 改（Rename） | ✅ |
| §5.5 AFEM Map | 待补充 |
| §5.6 Copy FEM | 待补充 |
| §5.7 几何修改 / Remesh | 待补充 |

---

## 5. §5.3 删除（已确认设计）

### 5.1 三类入口，统一收尾

| 入口 | 到达 ElemRemove 的方式 |
|---|---|
| Navigator 整包删除 | `MeshObjectDelete` → 几何网格 `GeoMeshDel` 或手工网格 O(N) 扫描 + 逐个 `ElemRemove` |
| 几何网格删除 | 已有删几何 API 内部级联 `ElemRemove` |
| 逐 element 删除 | 直接 `ElemRemove` |

元数据收尾统一在 **`ElemRemove` 挂钩**：`--m_MOIdToElementCountMap[moId]`，count ≤ 0 → `RemoveMeshObject(moId)`。

### 5.2 调用分层（与 Create 对称）

- `MeshObjectDelete` 为编排入口（Entity / Adapter 放置待定）
- `femmgMeshObjectManager` **不**在整包删除里上调已有删几何 / 删 element API
- Manager 的 `RemoveMeshObject` 由挂钩触发，非 Navigator 直接调用

### 5.3 删除性能（今日澄清）

**为何谈到性能**：`MeshObjectRecord` 不存 element 列表，只有 `m_MOIdToElementCountMap`（数量，不能反查 elPtr）。

| 场景 | 成本 | 说明 |
|---|---|---|
| 逐 element 删除 / 几何级联删除 | 低 | 删前读当前 element 的 `iMeshObjectId`；挂钩 map 递减；**无需**每次 rescan 全表 |
| Navigator 整包删**手工网格** | O(N) | 须 `ElmCreateIter` 找出 `iMeshObjectId == moId` 的 element 再逐个删 |
| Navigator 整包删**几何网格** | 不走 O(N) 枚举 | `GeoMeshDel(pComps)` 由已有链路级联 `ElemRemove` |

**阶段一决策**：手工整包删除接受 O(N)；后续可选 `m_MOIdToElementPtrs` 索引优化（DS §4 已注释为可选）。

详细性能结论另见：`Mesh-Object-Implementation-Summary.md` §8.1。

---

## 6. Meshes / `eMeshesType`（V1.1 已入 DS）

- Navigator：`Fem → 1D/2D/3D/Others Meshes → Mesh`（无额外 Meshes 父级）
- `eMeshesType` 在 `Create()` 时写入 MOHEAP；Rename / element 变化不改变
- FS 用语：UI 显示「XD Meshes」；代码字段 `eMeshesType`

---

## 7. 飞书 vs GitHub 差异（待用户同步飞书）

GitHub 较新：§4.3、`eMeshesType`、§5.3/§5.4 细节、`GetCurrentMeshObjectId`、MOId 从 1 开始等。

飞书可能仍缺或与 GitHub 不一致项：Info、Show/Hide、AFEM Map UI、2606/UNV 导入、Copy FEM、CheckIn/Out 等（见当日对照讨论）。

---

## 8. 待下次继续

### 8.1 设计待补充

| 项 | 状态 |
|---|---|
| §5.5 AFEM Map | 待补充 |
| §5.6 Copy FEM | 待补充 |
| §5.7 几何修改 / Remesh | 待补充 |
| Info / Show-Hide User Case | 待补充 |
| Model Entity 层 | 待写（§6.4） |
| Navigator-UI 层 | 待写（§6.4） |

### 8.2 实现待对齐

- `MeshObjectDelete` 编排函数（位置待定）
- `ElemRemove` 挂钩维护 `m_MOIdToElementCountMap`
- `RemoveMeshObject`（元数据 + MOHEAP）
- `GetCurrentMeshObjectId` C/Fortran 桥（命名与 DS 一致）

### 8.3 建议下次讨论顺序

1. §5.5 AFEM Map 或 §5.6 Copy FEM（择一）
2. Info User Case（若阶段一需要）
3. 飞书 Wiki 与 GitHub V1.2 同步

---

## 9. 关键一句话总结

> **删除统一走 `ElemRemove` 挂钩 + map 计数收尾；仅手工网格整包删除编排为 O(N)；DS 只写已确认内容；GitHub 为版本真相，讨论纪要接续 07-06。**
