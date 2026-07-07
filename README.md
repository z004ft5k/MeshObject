# MeshObject Design

MeshObject 设计文档与讨论纪要的版本库。

| 文档 | 说明 |
|---|---|
| [MeshObjectDesignSpecificaiton.md](./MeshObjectDesignSpecificaiton.md) | 主设计规格（DS），当前 V1.3 |
| [MeshObject-Discussion-Notes.md](./MeshObject-Discussion-Notes.md) | 讨论纪要（累积，每次讨论追加） |
| [Mesh-Object-Design-Discussion.md](./Mesh-Object-Design-Discussion.md) | 早期架构讨论 |
| [Mesh-Object-Implementation-Summary.md](./Mesh-Object-Implementation-Summary.md) | 实现讨论总结 |

## 权威来源

- **版本对照**：本 GitHub 仓库（commit / diff / history）
- **阅读与协作**：[飞书 Wiki](https://ycntm1ix2za7.feishu.cn/wiki/PwilwM9Ayi75pVkQqU0cutWQn1f)

## 日常更新

本机未单独安装 Git 时，使用 **GitHub Desktop 自带的 git**（脚本会自动查找）。

每次与 Cursor 讨论并更新 DS 后：

```powershell
cd "C:\Users\xin.zeng\Documents\CurProjects\MeshObject"
.\scripts\git.ps1 add .
.\scripts\git.ps1 commit -m "docs: 简要说明本次改了什么"
.\scripts\git.ps1 push origin main
```

或一键提交并推送所有 `.md`：

```powershell
.\push-to-github.ps1
```

GitHub Desktop 的 **History** 标签也可查看 diff 与推送状态。
