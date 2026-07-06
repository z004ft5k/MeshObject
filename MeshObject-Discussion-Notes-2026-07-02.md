# MeshObject Discussion Notes - 2026-07-02

本文档整理 2026-07-02 关于 `MeshObject` 设计方案的讨论结论，供后续继续完善 DS 和实现时参考。

## 1. 本次讨论目标

本次讨论的主要目标是：

1. 对比 Wiki、已有 Markdown 文档和当前实现思路，收敛 `MeshObject` 的正式设计方向。
2. 明确 `MeshObject` 在 src layer、Entity 层和 UI / Navigator 层中的职责边界。
3. 形成一版正式 DS，并持续修正文风、术语和章节结构。

## 2. 总体结论

- 产品阶段定义以 Wiki 为准。
- 当前项目目标是完成阶段一能力：支持 Navigator 显示 `MeshObject` 节点，并支持 `Info`、`Rename`、`Delete`、`Show-Hide` 等基础操作。
- 当前重点不是一次性做完全部能力，而是先把底层模型层建立起来，为 Navigator 和后续操作提供支撑。
- 最终 DS 不再保留 Spike 过程描述。

## 3. A 类结论：存储与持久化模型

### 3.1 `meshObject` 运行时结构

采用方案 B：

```cpp
struct meshObject
{
    int  iMeshObjectId;
    char szDisplayName[FEMMG_K_MAX_DISPLAY_NAME];
    std::vector<fgm_TzCmp> zComps;
};
```

说明：

- `meshObject` 是 **C++ 运行时 struct**。
- 它不是 C++ / Fortran / FSI 之间原样共享的落盘结构。
- `zComps` 可直接存在运行时对象中。

### 3.2 `zComps` 的语义

- `zComps` **非空**：表示该 `MeshObject` 来源于几何 Keep。
- `zComps` **为空**：表示该 `MeshObject` 来源于手工创建。

### 3.3 持久化方式

- 采用 `MOHEAP + MOTREE`。
- 二者位于 FEM Record 的第二个 Field 中。
- `meshObject` 不直接原样落盘。
- `MOHEAP` 采用 **变长 record** 方式保存。

每条 `MOHEAP` record 至少包含：

- `iMeshObjectId`
- 名称信息
- `nCmp`
- `fgm_TzCmp[]`

每个 `fgm_TzCmp` 记录：

- `eCmpTyp`
- `iCmpId`
- `iNlId`

### 3.4 `femId`

- `MOHEAP` record **不包含** `femId`。
- `femId` 由 FEM 上下文和 Manager 所在作用域承担。

### 3.5 不采用的方案

- 当前设计 **不依赖** `mst bucket.iMeshObjectId` 作为必要关联方式。
- 不在 `MeshObject` 中重复存划分参数副本。
- 暂不讨论 `fKeepDef`。

## 4. B 类结论：element 归属模型

### 4.1 `iMeshObjectId` 的位置

- `iMeshObjectId` 放入 `femElem`。
- 存放于 **EHEAP common 区**。
- 位于 `iADPtr` 后。

### 4.2 写入方式

采用方案 A：

- 由调用方在 `ElmAdd` 前填写 `elem.iMeshObjectId`。
- **不修改** `ElmAdd` 的接口签名。

### 4.3 成员关系真相

- `element.iMeshObjectId` 是 `MeshObject` 成员归属的**唯一真相**。
- `m_zElementCount` 只是运行时缓存，不是主数据。

### 4.4 Open 恢复

Open 后通过扫描全部 element：

- 重建 `MeshObject` 成员关系
- 恢复 `m_zElementCount`

### 4.5 暂不展开内容

- Beam / `piBS` / `piNL` 的详细偏移影响，本次先不展开。

## 5. C 类结论：Manager、Entity 与删除逻辑

### 5.1 `femmgMeshObjectManager`

确认 `femmgMeshObjectManager` 作为 Fem 级 MeshObject 业务入口，负责：

- 管理全部 `meshObject`
- `Create`
- `Delete`
- `Rename`
- `LoadFromFSI`
- 持久化协调
- 运行时缓存管理

### 5.2 不采用的接口

- 不单独设计 `Bind / Unbind` API。

### 5.3 创建语义

- Create 是**显式操作**。
- 不在 `ElmAdd` 中自动创建 `MeshObject`。
- 触发来源主要包括：
  - Geometry Keep
  - Manual Mesh 完成

### 5.4 删除语义

保留两条删除路径：

1. **空 Mesh 自动删除**
2. **Navigator 主动 Delete Mesh**

其中：

- Geometry Keep 类型：基于 `zComps` 调用现有几何删除接口
- Manual 类型：基于 `element.iMeshObjectId` 删除归属 element

### 5.5 删除一致性原则

- Delete Mesh 是复合操作。
- 仅在底层 element 或 geometry 删除成功后，才删除对应 MeshObject 元数据。
- 若底层删除失败，则保留 MeshObject 元数据。

### 5.6 Entity 层定位

Entity 层不是 `femmgMeshObjectManager` 的封装，而是 **对 `meshObject` 的封装**。

Entity 层：

- 提供对象化接口
- 暴露上层所需能力
- 具体实现最终调用 `femmgMeshObjectManager`

当前讨论中保留的典型能力包括：

- `Create`
- `Rename`
- `Delete`
- `GetName`
- `GetComponents`
- `GetElementCount`

已取消：

- `QueryById`

## 6. D 类结论：主流程与对外语义

### 6.1 核心语义

- 一次 Keep 生成的一组单元对应一个 `MeshObject`
- 一次手工创建完成的一组节点、单元也对应一个 `MeshObject`
- 一个 element 最多归属一个 `MeshObject`
- Preview 不创建 `MeshObject`
- 只有 Keep 成功后才创建 `MeshObject`

### 6.2 Geometry Keep

几何 Keep 成功后：

1. 分配新的 `moId`
2. 创建 `meshObject`
3. 设置名称
4. 记录本次 Keep 对应的 `zComps`
5. 本次新生成 element 写入 `iMeshObjectId = moId`
6. 保存到 `MOHEAP / MOTREE`
7. Navigator 中出现对应 `MeshObject` 节点

### 6.3 Manual Mesh

手工创建路径中：

1. 创建节点、单元时按当前操作上下文形成一组对象
2. 创建 element 时由调用方填写 `elem.iMeshObjectId`
3. 一次手工建网操作完成时，显式创建对应 `meshObject`
4. `zComps` 为空
5. 保存到 `MOHEAP / MOTREE`

### 6.4 Save / Open

Save：

- 保存 `meshObject` 元数据与 `zComps` 到 `MOHEAP`
- 保存 `iMeshObjectId -> record` 索引到 `MOTREE`
- 保存 EHEAP 中的 `element.iMeshObjectId`

Open：

- 从 `MOHEAP / MOTREE` 恢复全部 `MeshObject`
- 恢复名称与 `zComps`
- 扫描全部 element
- 根据 `element.iMeshObjectId` 重建运行时关系和 `m_zElementCount`

## 7. E 类结论：文档边界与写法

### 7.1 已去掉的内容

- OOF 支持讨论
- NX 参考行为正文
- Spike 过程
- `fKeepDef` 相关讨论

### 7.2 保留方式

- 代码位置保留为附录
- 一些实现约束保留在附录
- 正文尽量写“设计结果”，不写成“讨论纪要”

### 7.3 术语统一

- `MeshObject`：逻辑概念
- `Mesh`：UI 显示名
- `meshObject`：src layer 运行时 struct
- `MeshObject Entity`：Entity 层对象封装
- `femmgMeshObjectManager`：Fem 级 MeshObject 管理器
- `element.iMeshObjectId`：成员归属字段

## 8. DS 结构结论

最终 DS 采用中文章节名，并包含 UI 层、Entity 层和 src layer。

后续形成的正式结构大体包括：

1. 背景与目标 / Introduction
2. 范围
3. 架构总览 / Overview
4. 核心语义
5. src layer 设计
6. Entity 层设计
7. UI / Navigator 集成设计
8. 持久化设计
9. 主生命周期与流程
10. 各层职责划分
11. 术语约定
12. 附录

后续又参考了另外两篇飞书 DS，进一步将章节风格收敛为：

- `Introduction`
- `Overview`
- `High Level Design`
- `Detailed Design`
- `Persistence Design`
- `Lifecycle Design`
- `Terminology`
- `Appendix`

## 9. 本次 DS 修订意见记录

在生成 DS 过程中，用户额外明确了以下修订要求：

1. 背景与目标要强调：当前项目目标是完成**阶段一**，并包含 `Rename`、`Delete` 等能力，虽然这些不是当前重点。
2. 核心目标中原第 4 点不需要单独写。
3. 设计范围需要包括**手工节点**相关操作。
4. 不需要写“不展开内容”章节。
5. Entity 层是对 `meshObject` 的封装，不是对 `femmgMeshObjectManager` 的封装。
6. 先取消 `QueryById`。

## 10. 飞书文档相关记录

### 10.1 参考文档

本次主要参考和比对了以下飞书文档：

- `MeshObject 设计方案`
- `DS`
- `Simulation Navigator DS`

### 10.2 导出的飞书 DS 版本

本次讨论过程中，导入了两个飞书 docx 版本：

1. 初版整理版
2. 参考 DS 模板后的精修版

后续若继续改写，应以最新精修版为基准继续修订。

## 11. femmgMeshObjectIdManager 结论（2026-07-03 补充）

- 名称统一：`femmgMeshObjectIdManager`（DS 与代码一致）
- Fortran 入口：`GetNextMeshObjectId(hDb, femId, &moId)`
- 挂在 `femmgModel` 下，与 `femmgMeshObjectManager` 并列
- Fem-based，非进程单例
- API：`InitFromRecords()`、`Allocate()`
- Open 时扫描 record 初始化 `m_iNextMeshObjectId = max(iMeshObjectId) + 1`
- 创建顺序：先 `Allocate()`，再 `Create()`
- AFEM：多 FEM 合成时 remap `(sourceFemId, oldMOId) -> newMOId`
- Src struct 命名：`MeshObjectRecord`；持久化布局：`MOHeapRecord`
- `MO` 缩写统一两个字母大写

## 12. 下次讨论建议议题

下次可以优先继续以下内容：

1. Copy FEM / CheckIn-Out / 2606 前 mf1 导入规则
2. Model Entity 层与 Navigator-UI 层详细设计
3. Adapter 层接口定义
4. 明确 Navigator 节点构造、刷新、删除时与 Entity / Manager 的事件链路
