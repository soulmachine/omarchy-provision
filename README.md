# Omarchy Provision

使用 Ansible 自动化 [Omarchy](https://omarchy.org)（Arch Linux）开发环境配置。是 [soulmachine/macbook-provision](https://github.com/soulmachine/macbook-provision) 的 Omarchy 移植版：同一套工具，换成 Omarchy 的安装渠道。

软件分三层安装，每个 role 只用其中一层（详见 `docs/writing-roles.md`）：

1. **Omarchy 已经用 mise 管理的工具**（各家 coding agent 的 CLI、gh、cf、node、uv）以及 npm 全局包：走 mise，`~/.local/bin` 下的 stub 和 Omarchy 自己写的一模一样。
2. **Omarchy 自带安装器的东西**（`omarchy-install-*`）：调用那个安装器，它会顺带注册菜单项、主题和完成标记。
3. **Arch 官方仓库的包**：[pacman 模块](https://docs.ansible.com/ansible/latest/collections/community/general/pacman_module.html)。

目前没有 AUR 包。需要时的做法见 `docs/writing-roles.md`（pacman 模块的 yay 模式看不到 AUR 包，DECISIONS Q3）。

## 语言运行时

和 Omarchy 自身一样，语言运行时（Go、Node.js、Bun、JDK）用 [mise](https://github.com/jdx/mise) 安装，也就是 `omarchy-install-dev-env` 给每种语言跑的那条 `mise use -g <tool>@latest`。Rust 用官方 rustup。mise 本身是 Omarchy 的 pacman 包 `mise-bin`。

## 使用方法

### 1. 安装 Ansible

```bash
./bootstrap.sh
```

该脚本只做两件事：配置免密 sudo，用 pacman 安装 Arch 的 `ansible` 包（系统 Python 上的 collections 全集，不用 pip、不用 mise 的 Python）。其它一切都交给 playbook。

> **关于免密 sudo**：脚本在 `/etc/sudoers.d/zz-<用户名>-nopasswd` 写入 `<用户名> ALL=(ALL) NOPASSWD: ALL` 和 `Defaults:<用户名> verifypw=any` 两行（权限 0440，`visudo -cf` 校验失败自动回滚）。文件名带 `zz-` 前缀，排在 Omarchy 自己的 drop-in 之后：sudo 取最后一条匹配规则，所以 Omarchy 之后新加的带密码规则压不过它。`verifypw=any` 让 `sudo -v` 也免密：Omarchy 的 asdcontrol 规则不是 NOPASSWD，而 `omarchy-update` 内部会跑 `sudo -v`，没有这一行无人值守的更新会永远停在密码提示上。
>
> 首次运行会一次性提示输入用户密码，之后所有 `sudo` 调用都免密。`always-on` role 还会每次确认 `verifypw=any` 那一行在，所以早期用旧版脚本 bootstrap 的机器也会收敛。
>
> **安全提示**：`NOPASSWD: ALL` 意味着以当前用户身份运行的任何进程都能静默取得 root 权限。

### 2. 运行 Playbook

```bash
ansible-playbook main.yml
```

运行单个 role：

```bash
ansible localhost -m include_role -a name=hermes
```

所有 Omarchy 主机都是常年开机的服务器，所以没有 `host-facts` role，也没有任何按机型的开关：`hermes`、`ponytail` 的 Hermes 部分、`paseo` 的 daemon 在每台机器上都装。

### 3. 试运行（不修改系统）

```bash
ansible-playbook main.yml --check
```

### 4. 可选：Tailscale 配置

`roles/tailscale` 用 `omarchy-install-service-tailscale` 安装（pacman `tailscale` + 启用 `tailscaled`）。

> **使用范围说明**：本 role 只把 Tailscale 当作**网络连接层**使用（私有 mesh + MagicDNS），**不启用 Tailscale SSH**。远程 shell 仍然走标准 OpenSSH。role 里没有 `--ssh` flag、没有 ACL tag、没有 `tagOwners` 自动管理。

#### 环境变量

将 `.env.example` 复制为 `.env`，按需填写以下变量，然后 `direnv allow`，最后运行 `ansible-playbook main.yml`。`dotenv` role 会把 `.env` 里的变量导出到 `~/.bashrc`，所以之后每个 shell 都能看到它们。

| 变量 | 作用 | 必填 |
|------|------|------|
| `TAILSCALE_AUTH_KEY` | 自动执行 `sudo tailscale up --accept-dns --accept-routes --operator=$USER --auth-key=...` 把本机加入 tailnet。在 https://login.tailscale.com/admin/settings/keys 创建一个 **Reusable** key 即可。 | 否（不设则需手工 `tailscale up`） |
| `TAILSCALE_OAUTH_CLIENT_ID` + `TAILSCALE_OAUTH_CLIENT_SECRET` | 通过 Tailscale REST API 关闭本机 node-key 过期（避免节点定期下线）。在 https://login.tailscale.com/admin/settings/trust-credentials 创建 OAuth client，勾选 `devices:core` 写权限。两个变量要么都设，要么都不设；只设一个会让 play 直接失败。OAuth client 看不到本机时跳过。 | 否 |
| `TYPESAFE_API_KEY` | `typesafe` role 用它给 fast-jev-compaction 与 claude-jev 两个 Claude Code 插件授权。在 Frank 的机器上**不要写进 `.env`**：jev-fleet 已经把它写进 `~/.bashrc`，role 从环境变量读取。没有 jev-fleet 的机器可以在这里设。 | 否（不设则跳过这两个插件；`typesafe-ai` skill 仍会安装） |

`GITHUB_TOKEN` 同理不在 `.env` 里：gh-token-fleet 写入 `~/.bashrc`，`github` role 从环境变量读取。一个变量只能有一个主人。

`tailscale up` flag 说明：

- `--accept-dns`：启用 MagicDNS（需提前在 https://login.tailscale.com/admin/dns 的 tailnet 层面启用一次）。
- `--accept-routes`：接受其它节点广播的 subnet route。这个 flag 是**必须写全**的：`tailscale up` 不允许悄悄丢掉上一次带过的非默认 flag，所以 role 里必须原样列出。
- `--operator=$USER`：把当前用户登记为 operator，之后跑 `tailscale status`、`tailscale set` 等命令不再需要 `sudo`。

> `TAILSCALE_API_ACCESS_TOKEN`（个人 API access token）**不支持**：它没有 scope 且 90 天过期。请配上面的 OAuth client。

### 5. 可选：启用 pre-commit 检查

```bash
pre-commit install
```

仓库自带三条 `repo: local` 检查，和 macbook-provision 相同：`ansible-lint`（production profile）、`DECISIONS.md` 编号连续性、README role 表与 `main.yml` 的顺序一致性。

`pre-commit install` 写入的是 `.git/hooks/pre-commit`，**git 不携带这个文件**，所以每个 clone 都要各自执行一次。想手工跑一遍全部检查：

```bash
pre-commit run --all-files
```

## 包含的 Roles

### Playbook 中的 Roles（`main.yml`）

按 `main.yml` 中的执行顺序排列。

| Role | 说明 |
|------|------|
| pacman | 先跑 `omarchy-update -y` 升级一切（仓库包、AUR、mise 工具、Omarchy 迁移），失败时记录下来、在 play 末尾才报错，不阻断后面的 role；需要重启时只提示，从不重启；然后装基础包 git、curl、wget、jq、ripgrep、fd、tree、htop、docker、ffmpeg、gnupg、tmux；VS Code 用 `omarchy-install-editor-vscode`（Claude、Gemini、ChatGPT 桌面版与 pearcleaner 没有 Linux 版；Sublime Text 已去掉） |
| github | gh CLI（Omarchy 的 mise 工具）；若环境中有 `GITHUB_TOKEN`（由 `gh-token-fleet` 写入 `~/.bashrc`，不来自 `.env`），另外配置 SSH key 与 git 签名 |
| direnv | 目录级环境变量管理（pacman `direnv`）；hook 写入 `~/.bashrc` |
| dotenv | 不装任何软件；把 `.env` 以托管块写入 `~/.bashrc` 的交互守卫之上，让非交互式 shell（`ssh host 'bash -lc cmd'`、git hook、cron）也能读到其中的变量 |
| uv | Python 包与工具管理器（Omarchy 的 mise 工具）；bash 补全写入 `~/.bashrc` |
| python | 用 uv 安装 Python 命令行工具：yamllint、ansible-lint（带 `--with ansible`）、ruff、pre-commit、httpie（依赖 uv） |
| mise | mise 本身是 Omarchy 的 pacman 包 `mise-bin`，不能 `self-update`；本 role 跑**一次** `mise up` 升级全部 mise 工具（和 `omarchy-update` 调用的是同一条命令），各工具 role 只在工具缺失时安装 |
| go | Go（mise） |
| nodejs | Node.js（mise，`latest` 而非 LTS，与 Omarchy 自身一致） |
| bun | Bun（mise） |
| rust | Rust 工具链（官方 rustup；额外含 rust-src、rust-analyzer 组件） |
| jdk | JDK（mise `java`） |
| claude-code | Claude Code CLI（Omarchy 的 mise 工具 `claude`）及插件、marketplace 与 settings（依赖 nodejs） |
| claude-extras | Claude Code 周边工具：mise `npm:@inulute/cux`、uv 工具 `claude-swap`（依赖 nodejs、uv、claude-code） |
| typesafe | TypeSafe Jev 模型相关的一切：官方 `typesafe-ai` skill（不需要 key），以及两个 Claude Code 插件 fast-jev-compaction 与 claude-jev；把 `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` 与 `TYPESAFE_API_KEY` 写入 `~/.claude/settings.json` 的 `env`；环境中无 `TYPESAFE_API_KEY` 时只跳过插件部分（依赖 claude-code、nodejs） |
| codex | OpenAI Codex CLI（Omarchy 的 mise 工具 `codex`），并安装 [open-pstack](https://github.com/ericlitman/open-pstack) 的 `pstack` 插件（Claude Code 那一半在 claude-code role 的插件列表里；`/pstack:setup-pstack` 需手动运行）（依赖 nodejs） |
| opencode | OpenCode CLI（Omarchy 的 mise 工具 `opencode`）；并用 `npx oh-my-openagent` 写入 `~/.config/opencode/opencode.json`，由版本戳门控，避免每次 play 重装（依赖 nodejs） |
| omp | oh-my-pi（Omarchy 的 mise 工具，命令 `omp`） |
| pi | pi coding agent（Omarchy 的 mise 工具 `pi`），并下发 `~/.pi/agent/settings.json` |
| agent-sync | GitHub release 的二进制放到 `~/.local/bin/agent-sync`（AUR 只有过期的 0.1.0）；把 `~/.agents/` 扇出到各 agent；并托管每晚 02:17 的 `agent-sync sync` cron |
| skills | 用 `npx skills@latest add` 安装整源与只取指定技能的源，并扇出到各 agent 的 skills 目录；详见下文「Agent CLI 与技能」（依赖 claude-code、codex） |
| agent-reach | 多渠道触达工具；上游只提供面向 AI agent 的安装文档，故由 `claude-gw -p` 按文档驱动安装。`~/.local/bin/claude-gw` 由 mac-mini-m2 上的 `cliproxy-tier` 写入，缺失时 role 报错而**不自行创建**（依赖 claude-code、python） |
| playwright | 浏览器自动化：mise `npm:playwright`（依赖 nodejs） |
| playwright-cli | Playwright CLI：mise `npm:@playwright/cli`，并安装其 skill（依赖 playwright） |
| claude-mem | Claude 记忆插件；`npx -y claude-mem install` 为 claude-code / codex-cli / opencode 三者接线（依赖 nodejs、bun、uv） |
| hermes | Hermes 个人 agent（Nous Research）的 CLI 版：`omarchy-install-hermes-cli`（mise pipx）；`~/.hermes/SOUL.md` 链接到 `~/.agents/AGENTS.md` |
| ponytail | 给所有 agent 安装 [ponytail](https://github.com/DietrichGebert/ponytail) 插件：Claude Code / Codex / OpenCode / pi / oh-my-pi / Hermes 各用其原生安装方式 |
| paseo | agent 多路复用：mise `npm:@getpaseo/cli`（CLI + daemon）；daemon 由本 role 管理的 systemd user unit `paseo-daemon.service`（`paseo daemon run`）常驻；开启 relay（配对仍需手动 `paseo daemon pair`），打开 `pluginsEnabled` 并安装插件 `npm:@oliexe/paseo-bots`；daemon 没在运行时在 play 末尾报错；tag `agent-multiplexer`（依赖 claude-code、codex） |
| ghostty | 终端模拟器：`omarchy-install-terminal ghostty`，同时把它设为 Omarchy 的默认终端（取代 foot） |
| obsidian | Obsidian（pacman，Omarchy 自带）+ mise `npm:defuddle`（依赖 claude-code） |
| cloudflare | Cloudflare CLI：Omarchy 的 mise 工具 `npm:cf`（依赖 claude-code） |
| multica-cli | 官方安装脚本，同 ubuntu-provision |
| tailscale | `omarchy-install-service-tailscale` + systemd `tailscaled`；若环境中有 `TAILSCALE_AUTH_KEY` 则自动 `tailscale up`，可选通过 OAuth client 关闭 key 过期 |
| zellij | 终端复用器（pacman）；tag `terminal-multiplexer` |
| tmux | 终端复用器（pacman）；tag `terminal-multiplexer`（`pacman` role 的基础包里也有，重复无害） |
| herdr | Omarchy 自带的 pacman 包，本 role 只确认它在、装 herdr skill 并在 `~/.bashrc` 加终端标题函数；tag `terminal-multiplexer` |
| always-on | 常驻服务器配置：屏蔽五个 sleep target、在 Omarchy 菜单隐藏 Suspend、SDDM 自动重登（`/etc/sddm.conf.d/zz-relogin.conf`）、`/etc/sysctl.d/zz-always-on.conf`、每周日 04:30 的 `omarchy-weekly-update` 重启检查脚本及其 cron（更新本身由每晚的 `pacman` role 做）、屏保延迟 86400 秒、sudoers 的 `verifypw=any` |

### 不移植的内容

这些东西留在 mac-mini-2018-omarchy 上手工维护，记录在 `~/.agents/docs/fleet-ssh.md`，因为它们属于这一台机器而不是每台 Omarchy 主机：

- **CLIProxyAPI 的 agent 用量条补丁**（`gateway/omarchy/` 仍在 macbook-provision 里，由 pacman hook 在 Omarchy 升级后重新打上）。
- **`~/.local/bin/*-gw` 包装器**、各 agent 的网关 settings 和 `/usr/bin/omarchy-agent` 的补丁：由 mac-mini-m2 上的 `cliproxy-tier-host.py` 写入。本仓库**从不**写这些文件。
- **arch-mact2** 的 pre-refresh hook（只有 T2 硬件需要）。
- **Sunshine**：Omarchy 的安装器有 bug，unit、web app 和 ufw 规则是手工做的一次性工作。

macbook-provision 里没有移植的 role：`host-facts`、`shell`、`omarchy`（Omarchy 自身就是这三者）、`apple-container`、`cua`、`cmux`、`moshi`（没有 Linux 版）、`cc-switch`、`intellij-idea`、`kimi-code` 以及 `homebrew` 里的 Sublime Text（去掉：无头服务器用不上，2026-10-11 首次运行装上后又卸掉了）。OpenCLI（agent-reach 的 X 后备）也不装，见 `roles/agent-reach/README.md`。

### Agent CLI 与技能

`main.yml` 里有十来个 role 装的是各家 coding agent 的 CLI 和它们共用的技能。上面的表格每个 role 只有一行，而这一块有几处「一行说不清」的地方，集中写在这里。

#### 安装渠道

和 Mac 上五花八门的渠道不同，这里全是 mise，因为 Omarchy 自己就是这么装它们的：

| 工具 | 安装渠道 | 落地位置 / 命令名 |
|------|----------|-------------------|
| claude-code | mise `claude` | stub `~/.local/bin/claude` |
| codex | mise `codex` | stub `~/.local/bin/codex` |
| opencode | mise `opencode` | stub `~/.local/bin/opencode` |
| omp | mise（GitHub release） | stub `~/.local/bin/omp` |
| pi | mise `pi` | stub `~/.local/bin/pi` |
| hermes | `omarchy-install-hermes-cli`（mise pipx） | `~/.local/bin/hermes` |
| claude-mem | `npx -y claude-mem install` | 不是独立命令，而是 Claude Code 插件，同时接线 codex-cli 和 opencode |
| agent-reach | **没有包管理器**，见下 | 由 `claude-gw -p` 按上游文档安装 |

stub 是 `omarchy-mise-install` 写的那种：先 `mise use -g`、再 `mise x`，第一次调用时装好工具。**升级统一由 `mise` role 的一次 `mise up` 完成**，各工具 role 没有自己的 update 步骤。

#### 每次运行都会被覆盖的配置文件

**`~/.pi/agent/settings.json` 每次 play 都会被仓库里的版本整个覆盖。** `pi` role 用 `copy` 下发整个 `~/.pi/agent/` 目录，没有任何 gate，所以在 pi 里通过 `/settings` 改的东西会在下一次 provisioning 时被抹掉。要让改动活下来，得改 `roles/pi/files/agent/` 里的文件。这是一次**合并**而不是同步：`~/.pi/agent/` 下面没被 payload 覆盖到的东西（尤其是 `skills` role 维护的 `~/.pi/agent/skills/`）不受影响。

另一处是 `~/.config/opencode/opencode.json`，由 `npx oh-my-openagent` 重写。这一步有 gate：配置里没有 `oh-my-openagent` 字样，或者 npm 上的版本与 `~/.config/opencode/.oh-my-openagent-version` 记录的不一致时才跑。

#### 技能：一个存储 + 符号链接扇出

所有技能只存在一份，在 `~/.agents/skills/`。`skills` role 用 `npx skills@latest add` 安装「整源」和「只取其中某几个技能」的源，然后由 CLI 扇出到各 agent。

**不是每个 agent 都拿符号链接**：Claude Code、pi、Hermes 的技能目录是指回存储的符号链接农场；而 Codex、OpenCode、Kimi Code 属于 CLI 所说的「universal agent」，它们**直接读 `~/.agents/skills/`**，永远不会收到链接。所以 `~/.codex/skills/` 里没有链接是正常的。

这个 role **故意不加 gate**，每次 play 都重新跑一遍安装器：这是唯一能把上游改动拉下来的机制。`changed` 由前后对 `~/.agents/skills/` 做校验和指纹比对得出。代价是每个源一次网络请求，是整个 playbook 里最慢的 role 之一。另外 `skills add` **从不删除**任何东西，上游下架的技能会作为孤儿目录留在存储里。

扇出（`agent-sync sync`）由 `agent-sync status` 的退出码门控。排在 `skills` 之后的 role（playwright-cli、multica-cli、herdr）也会往存储里加技能，所以**全新机器上第二次运行会再扇出一次**，第三次起才是 `changed=0`（mac-mini-2018-omarchy 实测，2026-10-11）。

#### 看起来像报错、其实是预期输出

- **每个技能源都会报两个 per-agent 失败**（Eve 和 PromptScript 拒绝全局安装）。属于正常噪音。
- **Hermes 拒绝安装 ponytail**，理由是插件扫描器给出 `dangerous` 判定（`--force` 也压不住）。role 把这一种失败明确放行并打印补救办法，其它任何错误仍然会让 play 失败。要接受这些发现，得自己在 `~/.hermes/config.yaml` 里设 `plugins.scan_on_install: false`，role 不替你做。
- **claude-mem 每次都报 changed。** 它的安装器无论有没有实际动作都退出 0 并打印 "installed successfully"，所以 role 直接写死 `changed_when: true`。
- 某个「只取几个技能」的源里的技能被上游改名或下架时，CLI 会退出 1 并打印 `● Available skills:` 加一整份清单，**读起来像帮助信息，其实是错误**。用 `npx skills@latest add <源> -l` 看上游现在有什么（`-l` 只列不装），然后改 `roles/skills/vars/main.yml`。这类失败**推迟到整个 play 的末尾**才抛出，但 PLAY RECAP 里依然是 `failed=1`。
- **`omarchy-update` 需要重启时**，`pacman` role 只打印一条提示。play 从不重启；周日的 `omarchy-weekly-update` 只做重启检查，按同样的条件重启（DECISIONS Q9）。

#### role 代劳不了、需要人工的步骤

- **Codex 的 hook 信任**是一次性的、每台机器各做一次：跑 `codex`、打开 `/hooks`，审核并信任 ponytail 的三个生命周期 hook，然后开一个新 thread。
- **opencode 的 provider 认证**没有做：安装器带的是 `--skip-auth`。
- **agent-reach 只配好了零配置的渠道。** 其余渠道要 cookie 或点一下浏览器扩展。要补齐就自己交互式跑一次 `agent-reach doctor`。
- **`claude-mem` 的模型 id 要手工升级。** `roles/claude-mem/vars/main.yml` 里的 `claude_mem_model` 只认完整 id，id 一旦下架就是一个硬错误 `Fatal error: Unknown Claude model`，**会让 play 失败**。
- **paseo 的配对**：`paseo daemon pair`。
- **Tailscale 首次登录**：没有 `TAILSCALE_AUTH_KEY` 时手工 `sudo tailscale up --accept-dns --accept-routes --operator=$USER`。

## 致谢

本项目是 [soulmachine/macbook-provision](https://github.com/soulmachine/macbook-provision) 的移植，后者参考了 [hayajo/macbook-provision](https://github.com/hayajo/macbook-provision)。
