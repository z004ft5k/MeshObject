# MeshObject 讨论纪要 - 2026-07-06

本文档整理 2026-07-06 与 Cursor 的讨论结论，供下次继续。

---

## 1. 今日讨论主题概览

1. 以飞书 Wiki 为阅读标准，本地 DS + GitHub 为版本真相
2. Terminology 统一：`MeshObjectRecord` 为 Src 运行时 struct
3. 补充 User Case §5.1 打开 Mf1、§5.2 创建
4. 文档化 `femdaMOFSIProxy` FSI 访问层及与 Manager 集成
5. 重构 `femmgMeshObjectIdManager` API（`GetMeshObjectId` / `Allocate` 分离）
6. 简化 `femmgMeshObjectManager::Create` 接口
7. 建立 GitHub 仓库与 SSH 推送流程

---

## 2. 文档与协作约定

| 用途 | 位置 |
|---|---|
| 版本对照 / diff | GitHub：https://github.com/z004ft5k/MeshObject |
| 阅读与协作 | 飞书 Wiki：https://ycntm1ix2za7.feishu.cn/wiki/PwilwM9Ayi75pVkQqU0cutWQn1f |
| 本地编辑源文件 | `C:\Users\xin.zeng\Documents\CurProjects\MeshObject\` |

- 本地主文档：`MeshObjectDesignSpecificaiton.md`，当前 **V1.8**
- 每次讨论后：更新 DS → 写本讨论纪要 → `git commit` + `push`
- 公司内网 Git HTTPS 不稳定，已配置 **SSH**（`ssh.github.com:443`）推送

---

## 3. 今日 DS 变更摘要（V1.3 → V1.8）

| 版本 | 内容 |
|---|---|
| V1.3 | User Case §5.1 打开 Mf1 |
| V1.4 | `femdaMOFSIProxy` FSI 访问层；Manager 委托持久化 |
| V1.5 | User Case §5.2 创建 |
| V1.6 | `femmgMeshObjectIdManager`：`GetMeshObjectId` + `Allocate` 分离 |
| V1.7 | `Create(name, pComps, nCmp)`，MOId 在 Create 内部获取 |
| V1.8 | §5.2 修正 element 计数时机；精简 EHEAP 持久化描述 |

---

## 4. femdaMOFSIProxy（今日实现与文档化）

### 4.1 定位

- 位于 `femda` 层（`neuecax/src/femda/femdaMOFSIProxy.hxx` / `.cxx`）
- 类比 `femdaAccFSIProxy` 之于 EHEAP
- 由 `femmgMeshObjectManager` 持有，封装 MOHEAP / MOTREE 的 FSI 读写

### 4.2 接口

```cpp
class femdaMOFSIProxy
{
public:
    femdaMOFSIProxy(int hDb, int femId);
    void AddMeshObject(MeshObjectRecord& meshObj);
    void GetAllMeshObjects(std::vector<MeshObjectRecord>& meshObjs);
    // ...
};
```

### 4.3 与 Manager 集成

- **构造 / Open**：`GetAllMeshObjects()` → `RegisterFromRecord()` → `m_MOIdToRecordMap`
- **Create**：`AddMeshObject(record)` 写 MOHEAP / MOTREE

---

## 5. femmgMeshObjectIdManager API（今日重构）

### 5.1 变更动机

- Keep / 手工建网过程中会**多次**给 element 填 `iMeshObjectId`，应反复取**同一** MOId
- 原 `Allocate()` 取号即 `++`，不适合「先建 element、后 Create MO」的流程

### 5.2 新 API

```cpp
class femmgMeshObjectIdManager
{
public:
    void InitFromRecords(const std::map<int, MeshObjectRecord>& records);
    int  GetMeshObjectId() const;   // 只读，给 element 填 iMeshObjectId
    void Allocate();                // MO 创建成功后 ++m_iMeshObjectId

private:
    int m_iMeshObjectId;            // 当前待使用 / 进行中的 MOId
};
```

### 5.3 规则

| 方法 | 行为 |
|---|---|
| `InitFromRecords` | Open 后：`m_iMeshObjectId = max(iMeshObjectId) + 1`；无 record 则为 `1` |
| `GetMeshObjectId` | 返回当前值，不修改；Fortran 桥改名为 **`GetMeshObjectId`** |
| `Allocate` | `m_iMeshObjectId++`；在 **`femmgMeshObjectManager::Create()` 末尾**调用 |

- Keep 失败：不 `Create`、不 `Allocate`，`m_iMeshObjectId` 不变

---

## 6. femmgMeshObjectManager::Create（今日简化）

### 6.1 接口

```cpp
femStatus Create(const char* pszDisplayName, const fgm_TzCmp* pComps, int nCmp);
// 手工建网：Create(name, nullptr, 0)
```

- 调用方**不传 moId**，**不组装** `MeshObjectRecord`
- 只传 `name`、`pComps`（及 `nCmp`）

### 6.2 Create 内部流程

```text
moId = GetMeshObjectId()
组装 MeshObjectRecord
femdaMOFSIProxy->AddMeshObject(record)
m_MOIdToRecordMap[moId] = record
Allocate()
```

### 6.3 创建调用顺序（对外）

```text
1. element 创建：ElmAdd 前 iMeshObjectId = GetMeshObjectId()
2. ElmAdd 成功后：OnElementAdded(moId) → ++m_MOIdToElementCountMap
3. Keep 成功 / 手工完成：Create(name, pComps, nCmp)
4. Save（持久化细节见 §4.5.5 / §5.1，User Case 不写 EHEAP 细节）
```

---

## 7. element 计数缓存（今日澄清）

- `m_MOIdToElementCountMap` 在**每个 element `ElmAdd` 成功时**累加
- **不是**在 `Create()` 之后才更新
- 手工建网与几何 Keep 路径一致
- 权威仍是 `element.iMeshObjectId`；缓存不一致时可 rescan

---

## 8. User Case 进度

| 章节 | 状态 |
|---|---|
| §5.1 打开 Mf1 | ✅ 已完成 |
| §5.2 创建 | ✅ 已完成 |
| §5.3 删除 | 待写 |
| §5.4 改（Rename 等） | 待写 |

---

## 9. 工程与协作环境（今日搭建）

- GitHub 仓库：`z004ft5k/MeshObject`（Private 建议）
- 本地路径：`C:\Users\xin.zeng\Documents\CurProjects\MeshObject`（目录名无空格）
- 工具：GitHub Desktop + SSH（`~/.ssh/id_ed25519_github`，Host `github.com` → `ssh.github.com:443`）
- Git 查看改动：Desktop **History** 标签；网页 **Commits** / **Compare**

---

## 10. 待下次继续

### 10.1 设计待补充

| 项 | 状态 |
|---|---|
| User Case §5.3 删除 | 待写 |
| User Case §5.4 改（Rename） | 待写 |
| Copy FEM 的 MOId remap | 待补充 |
| CheckIn / CheckOut | 待补充 |
| 2606 前 mf1 / UNV 导入规则 | 待补充 |
| Model Entity 层详细设计 | 待写 |
| Navigator-UI 层详细设计 | 待写 |

### 10.2 实现待对齐

- 代码中 `femmgMeshObjectIdManager` 按新 API 实现（`m_iMeshObjectId`、`GetMeshObjectId`、`Allocate`）
- `femmgMeshObjectManager::Create(name, pComps, nCmp)` 及内部 `Allocate()`
- `GetMeshObjectId` C/Fortran 桥（替代 `GetNextMeshObjectId`）
- `ElmAdd` / `ElmRemove` 挂钩 `OnElementAdded` / `OnElementRemoved` 维护计数
- `femdaMOFSIProxy` 与 Manager 集成（用户已在 spike 分支实现）

### 10.3 建议下次讨论顺序

1. User Case §5.3 删除（几何 Keep vs 手工、空 Mesh 自动删除）
2. User Case §5.4 Rename
3. Entity 类名与 Adapter 接口表（若仍需要）
4. Copy FEM 与 AFEM remap 是否同一套机制

---

## 11. 关键一句话总结

> **`GetMeshObjectId` 供 element 反复取同一 MOId；`Create(name, pComps)` 内部组 record 并 `Allocate` 推进；`femdaMOFSIProxy` 管 MOHEAP/MOTREE；element 计数在 `ElmAdd` 时累加；DS 与纪要存 GitHub，飞书 Wiki 作阅读发布。**
