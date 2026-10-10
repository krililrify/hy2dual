# Hysteria22 双节点部署器

从原 `ansible-main/Hysteria22` 项目提取的双 HY2 节点部署脚本。它直接在目标 VPS 上运行，不再通过 SSH 连接另一台机器，因此不需要目标 VPS 的 IP 和 SSH 密码，也不需要 Ansible 控制端。

脚本会把两组面板、节点、域名和 Cloudflare DNS 参数写入 `xboard-node` 配置，再通过 Docker Compose 启动服务。

## 前置条件

- Debian 或 Ubuntu VPS，使用 systemd。
- 以 `root` 身份运行。
- VPS 已安装并启动 Docker，且 `docker compose` 可用。
- 需要两个面板的 URL、Token、Node ID，以及每个域名对应的邮箱和 Cloudflare API Token。

脚本会在缺少 Git 时通过 APT 安装 Git，并将 `cedar2025/xboard-node` 的 `compose` 分支克隆到 `/root/xboard-node`。

## 运行方式

### 命令行参数

参数顺序如下：

```text
面板A URL, 面板A Token, A节点ID, A域名, A邮箱, A域名的Cloudflare API Token,
面板B URL, 面板B Token, B节点ID, B域名, B邮箱, B域名的Cloudflare API Token
```

把下面命令中的示例值替换成你的配置。使用 `curl | bash -s --` 从 GitHub 下载并运行脚本；`--` 后面的 12 项会作为安装参数传入：

```bash
curl -fsSL https://raw.githubusercontent.com/krililrify/hy2dual/main/install.sh | bash -s -- 'https://panel-a.example.com' 'PANEL_A_TOKEN' '101' 'a.example.com' 'admin@example.com' 'CF_TOKEN_A' 'https://panel-b.example.com' 'PANEL_B_TOKEN' '202' 'b.example.com' 'admin@example.com' 'CF_TOKEN_B'
```

必须传入完整的 12 个参数。少传或不传时，脚本会显示用法并退出，不会提示交互输入。

面板 Token 和 Cloudflare API Token 会作为命令行参数传入，可能被 shell 记录在历史中，也可能短暂出现在进程列表里。运行前确认 VPS 的 shell 历史策略，并避免在共享终端中执行。

## 配置和管理

- 配置文件：`/root/xboard-node/config/config.yml`，权限为 `600`，其中包含面板和 Cloudflare 凭证。请勿公开分享或提交。
- Compose 项目目录：`/root/xboard-node`。
- 查看容器：`cd /root/xboard-node && docker compose ps`
- 查看日志：`cd /root/xboard-node && docker compose logs -f`
- 重启服务：`cd /root/xboard-node && docker compose restart`
- 停止服务：`cd /root/xboard-node && docker compose down`

重复运行会覆盖双节点配置并执行 `docker compose up -d`。首次运行时，脚本会克隆上游 `compose` 分支；如果 `/root/xboard-node` 已存在但不是 Git 仓库，脚本会停止，不会删除该目录。

## 上传到 GitHub

请使用公开仓库 `krililrify/hy2dual`，把 `install.sh` 和 `README.md` 放在仓库根目录，然后推送到 `main` 分支。若使用其他仓库名或账号，请相应修改上面的 `raw.githubusercontent.com` 地址。

从本地仓库目录执行：

```bash
git init
git add install.sh README.md
git commit -m "Add Hysteria22 dual-node installer"
git branch -M main
git remote add origin https://github.com/krililrify/hy2dual.git
git push -u origin main
```

上传完成后，先确认下面地址能打开脚本，再从 VPS 运行安装命令：

```text
https://raw.githubusercontent.com/krililrify/hy2dual/main/install.sh
```

## 安全说明

此安装器以 root 身份运行，会克隆并执行上游 `xboard-node` Compose 项目，并在 VPS 本地保存密钥。运行前请审阅脚本和上游项目。建议先在测试 VPS 验证，再部署到正式服务器；不要把真实面板 Token 或 Cloudflare Token 写入 GitHub。
