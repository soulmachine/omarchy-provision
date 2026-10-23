# Omarchy Provision

使用 Ansible 自动化 [Omarchy](https://omarchy.org)（Arch Linux）开发环境配置。是 [soulmachine/macbook-provision](https://github.com/soulmachine/macbook-provision) 的 Omarchy 移植版：同一套工具，换成 Omarchy 的安装渠道。

软件分三层安装，每个 role 只用其中一层（详见 `docs/writing-roles.md`）：

1. **Omarchy 已经用 mise 管理的工具**（各家 coding agent 的 CLI、gh、cf、node、uv）以及 npm 全局包：走 mise，`~/.local/bin` 下的 stub 和 Omarchy 自己写的一模一样。
2. **Omarchy 自带安装器的东西**（`omarchy-install-*`）：调用那个安装器，它会顺带注册菜单项、主题和完成标记。
3. **Arch 官方仓库的包**：[pacman 模块](https://docs.ansible.com/ansible/latest/collections/community/general/pacman_module.html)。

唯一的 AUR 包是 orca role 的 `stably-orca-bin`（DECISIONS Q26）。做法见 `docs/writing-roles.md`（pacman 模块的 yay 模式看不到 AUR 包，DECISIONS Q3）。

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
| python | 用 uv 安装 Python 命令行工具：yamllint、ansible-lint（带 `--with ansible`）、ruff、pre-commit、httpie、pgcli（依赖 uv） |
| mise | mise 本身是 Omarchy 的 pacman 包 `mise-bin`，不能 `self-update`；本 role 跑**一次** `mise up` 升级全部 mise 工具（和 `omarchy-update` 调用的是同一条命令），各工具 role 只在工具缺失时安装 |
| go | Go（mise） |
| nodejs | Node.js（mise，`latest` 而非 LTS，与 Omarchy 自身一致） |
| bun | Bun（mise） |
| rust | Rust 工具链（官方 rustup；额外含 rust-src、rust-analyzer 组件） |
| jdk | JDK（mise `java`） |
| claude-code | Claude Code CLI（Omarchy 的 mise 工具 `claude`）及插件、marketplace 与 settings（依赖 nodejs） |
| claude-extras | Claude Code 周边工具：mise `npm:@inulute/cux`、uv 工具 `claude-swap`（依赖 nodejs、uv、claude-code） |
| typesafe | TypeSafe Jev 模型相关的一切：官方 `typesafe-ai` skill（不需要 key），以及两个 Claude Code 插件 fast-jev-compaction 与 claude-jev；把 `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` 与 `TYPESAFE_API_KEY` 写入 `~/.claude/settings.json` 的 `env`；环境中无 `TYPESAFE_API_KEY` 时只跳过插件部分（依赖 claude-code、nodejs） |
| 1password | 1Password 桌面 App 与官方 CLI `op`：pacman `1password-cli`（来自 Omarchy 自己的 `omarchy` 仓库）；有桌面会话时用 `omarchy-install-service-1password` 装 App，它同时装 1Password 的 Chromium 扩展；由 `omarchy-update` 升级；再装官方 Claude Code 插件 [`1password@1password`](https://github.com/1Password/1password-claude-plugin)；App 的 Settings → Developer 中「Integrate with 1Password CLI」与「Integrate with MCP clients」两个开关和登录需手动（依赖 claude-code） |
| bitwarden | Bitwarden 客户端（用于自建的 Vaultwarden），pacman `rbw`、mise `npm:@bitwarden/cli`（stub `~/.local/bin/bw`；pacman 的 `bitwarden-cli` 依赖 `nodejs-lts-jod`，与 Omarchy 的 `nodejs` 冲突）；有桌面会话（`/usr/share/xsessions` 或 `/usr/share/wayland-sessions` 下有 `.desktop`，Hyprland 自带）时再装官方 Electron 桌面 App（pacman `bitwarden`）；由 `omarchy-update` 升级；再把 `bw` 的 server 与 `rbw` 的 `base_url`/`email` 设为 `https://vaultwarden.soulmachine.me` 与 `soulmachine@gmail.com`（先读、不同才写）；桌面 App 的服务器与所有登录仍需手动（依赖 nodejs） |
| codex | OpenAI Codex CLI（Omarchy 的 mise 工具 `codex`）（依赖 nodejs） |
| opencode | OpenCode CLI（Omarchy 的 mise 工具 `opencode`）；并用 `npx oh-my-openagent` 写入 `~/.config/opencode/opencode.json`，由版本戳门控，避免每次 play 重装（依赖 nodejs） |
| omp | oh-my-pi（Omarchy 的 mise 工具，命令 `omp`） |
| pi | pi coding agent（Omarchy 的 mise 工具 `pi`），并下发 `~/.pi/agent/settings.json` |
| copilot | GitHub Copilot CLI（Omarchy 的 mise 工具 `copilot`）；走网关用的 `copilot-gw` 由 m2 上的 `cliproxy-tier` 写入 |
| crush | Crush（Charm，Omarchy 的 mise 工具 `crush`）；`~/.config/crush/crushrc` 里的网关 provider 由 `cliproxy-tier` 写入 |
| gemini | Gemini CLI（Omarchy 的 mise 工具 `gemini`）；`gemini-gw` 及其网关配置（`~/.gemini-gw`）由 `cliproxy-tier` 写入，`gemini` 本身保持原生（依赖 nodejs） |
| grok | Grok CLI（Omarchy 的 mise 工具 `npm:@xai-official/grok`）；`grok-gw` 及其网关配置（`~/.grok-gw`）由 `cliproxy-tier` 写入，`grok` 本身保持原生（依赖 nodejs） |
| openclaw | OpenClaw：`omarchy-install-openclaw-cli`（pacman `openclaw`）；onboarding 由 m2 上的 `cliproxy-tier` 负责，未 onboarding 时只打印提示；daemon 跑的 Node 或 OpenClaw 版本过期时用 `openclaw gateway install --force` 重写并重启 |
| dsh | DeepSeek Harness（mise 工具 `npm:@deepseek-ai/dsh`，另装 mise 工具 `pnpm`，因为 `dsh plugin` 靠 PATH 上的 pnpm 装插件）；按 `roles/dsh/vars/main.yml` 每次对 `web`、`tui` 两个 profile 的每个 npm 插件跑 `dsh plugin --profile <p> add <spec>@latest`：缺的就装，旧的就升级，且都经过 dsh 的兼容性检查（`update` 不检查）；git 插件 `dsh-purge` 装好后改用 `update dsh-purge` 拉到分支最新提交。按 `pnpm-lock.yaml` 前后校验和判断变更（不到一天的新版本被 pnpm 的 minimumReleaseAge 挡住，下次再装）。dsh 拒绝的插件（如与当前 dsh 不兼容的 `dsh-find-plugin`，或要求更新 dsh 的插件新版本）只打印警告并保留已装版本，等兼容版本发布后自动装上 |
| agent-sync | GitHub release 的二进制放到 `~/.local/bin/agent-sync`（AUR 只有过期的 0.1.0）；把 `~/.agents/` 扇出到各 agent；并托管每晚 02:17 的 `agent-sync sync` cron |
| skills | 用 `npx skills@latest add` 安装整源与只取指定技能的源，并扇出到各 agent 的 skills 目录；详见下文「Agent CLI 与技能」（依赖 claude-code、codex） |
| agent-reach | 多渠道触达工具；上游只提供面向 AI agent 的安装文档，故由 `claude-gw -p` 按文档驱动安装。`~/.local/bin/claude-gw` 由 mac-mini-m2 上的 `cliproxy-tier` 写入，缺失时 role 报错而**不自行创建**（依赖 claude-code、python） |
| playwright | 浏览器自动化：mise `npm:playwright`（依赖 nodejs） |
| playwright-cli | Playwright CLI：mise `npm:@playwright/cli`，并安装其 skill（依赖 playwright） |
| claude-mem | 移除用 role（2026-10-23 起）：跑 `npx -y claude-mem uninstall`，清掉它留在 Gemini、Codex、opencode 里的接线，删除 `~/.claude-mem`；所有主机跑过后删掉本 role（依赖 nodejs） |
| hermes | Hermes 个人 agent（Nous Research）的 CLI 版：`omarchy-install-hermes-cli`（mise pipx）；`~/.hermes/SOUL.md` 链接到 `~/.agents/AGENTS.md` |
| browseros-neo | [BrowserOS neo](https://browseros.com)（给 agent 用的 Chromium 浏览器）：pacman `fuse2`，下载上游 `https://cdn.browseros.com/download/BrowserOS_neo.AppImage` 到 `~/.local/share/browseros-neo/`（每次下载、内容变了才算变更），并写入启动器的 `.desktop`；把 MCP 端点 `http://127.0.0.1:9010/mcp`（neo 的 proxy 端口；文档里的 9200 不对）注册给每个已安装的 agent：Claude Code、codex、gemini、copilot、grok、hermes 用各自的 `mcp add`，kimi、omp、opencode、crush 合并进各自的 JSON 配置；URL 不对就替换（pi 不支持 MCP）；首次安装上游 `browseros-neo` skill，之后由运行中的 neo 自己更新。不开机自启（依赖 claude-code、nodejs） |
| ponytail | 给所有 agent 安装 [ponytail](https://github.com/DietrichGebert/ponytail) 插件：Claude Code / Codex / OpenCode / pi / oh-my-pi / Hermes 各用其原生安装方式 |
| context-mode | 给所有 agent 安装 [context-mode](https://github.com/mksglu/context-mode)：Claude Code / Codex / OpenCode / pi / oh-my-pi / Gemini CLI / Copilot CLI / OpenClaw 各用其原生安装方式；Hermes、Crush、Grok 上游没有适配，不装 |
| paseo | agent 多路复用：mise `npm:@getpaseo/cli`（CLI + daemon）；daemon 由本 role 管理的 systemd user unit `paseo-daemon.service`（`paseo daemon run`）常驻；开启 relay（配对仍需手动 `paseo daemon pair`），打开 `pluginsEnabled` 并安装插件 `npm:@oliexe/paseo-bots`；daemon 没在运行时在 play 末尾报错；tag `agent-multiplexer`（依赖 claude-code、codex） |
| orca | [Orca](https://onorca.dev)（多 agent IDE）：AUR `stably-orca-bin`（`pacman -Q` 探测，缺失时 `yay -S --needed --noconfirm`，由 `omarchy-update` 升级；包把 AppImage 解到 `/opt/stably-orca`，CLI 是 `/opt/stably-orca/resources/bin/orca-ide`，不在 PATH 上）；再用上游的 `orca-ide serve service install --port 6768` 装 systemd user unit `orca-serve`（`--supervise --no-pairing`），只在服务不是 `live` 时安装；当前 Orca 还没有这个子命令时跳过并提示；服务未 live 时在 play 末尾报错。配对仍需手动；tag `agent-multiplexer`（依赖 claude-code、codex） |
| ghostty | 终端模拟器：`omarchy-install-terminal ghostty`，同时把它设为 Omarchy 的默认终端（取代 foot） |
| obsidian | Obsidian（pacman，Omarchy 自带）+ mise `npm:defuddle`（依赖 claude-code） |
| cloudflare | Cloudflare CLI：Omarchy 的 mise 工具 `npm:cf`（依赖 claude-code） |
| multica-cli | 官方安装脚本，同 ubuntu-provision |
| purelymail | 同 ubuntu-provision；token 手工放在 `~/.profile`，`~/.bash_profile` 已加一行 source 它 |
| email | Himalaya 邮件 CLI 与 Proton Mail Bridge（pacman）+ ortie OAuth CLI（GitHub release 二进制，同 ubuntu-provision）；账号配置手工完成 |
| tailscale | `omarchy-install-service-tailscale` + systemd `tailscaled`；若环境中有 `TAILSCALE_AUTH_KEY` 则自动 `tailscale up`，可选通过 OAuth client 关闭 key 过期 |
| zellij | 终端复用器（pacman）；tag `terminal-multiplexer` |
| tmux | 终端复用器（pacman）；tag `terminal-multiplexer`（`pacman` role 的基础包里也有，重复无害） |
| herdr | Omarchy 自带的 pacman 包，本 role 只确认它在、装 herdr skill、在 `~/.bashrc` 加终端标题函数，并用 herdr-rename-hook skill 的 `install.sh` 接上 `/rename` 钩子（Claude Code 与 Codex 的 `/rename` 同步成 Herdr 的 agent、pane 和 tab 名）；tag `terminal-multiplexer` |
| eza | 在 `~/.bashrc` 末尾（Omarchy rc 之后）重定义 `ls`、`lt`：没给路径时补 `.`。否则 eza 在非 tty 的 stdin 上会读 stdin 里的文件名，agent 的 shell 卡住或什么都不列。辅助函数叫 `eza_ls`，不以 `_` 开头，因为 Claude Code 的 shell 快照会丢掉 `_` 开头的函数 |
| omarchy-cliproxy | 只在有 Agents bar（`/usr/bin/omarchy-agent-usage-update`）的网关主机（有 m2 写入的 `~/.local/bin/claude-gw`、没有原生 Claude 登录）上运行：装三个 Omarchy 补丁（`omarchy-agent` 启动器改走 `-gw` 包装器；Agents bar 的 Claude、Codex 用量采集器读网关的用量文件）、打补丁脚本 `/usr/local/bin/omarchy-cliproxy-patch` 和 pacman hook（Omarchy 升级后重新打补丁；补丁打不上时在 play 末尾报错）；再装 systemd user timer `omarchy-cliproxy-usage.timer`，每 5 分钟 ssh 到 mac-mini-m2，从 stdin 运行 `cliproxy-usage-probe`，m2 只返回用量结果、不返回 token，写入 `~/.local/state/cliproxy/{claude,codex}-usage.json` 并刷新 Agents bar |
| always-on | 常驻服务器配置：屏蔽五个 sleep target、在 Omarchy 菜单隐藏 Suspend、SDDM 自动重登（`/etc/sddm.conf.d/zz-relogin.conf`）、`/etc/sysctl.d/zz-always-on.conf`、移除旧的每周日 `omarchy-weekly-update` 重启检查（重启改由 `pacman` role 负责）、屏保延迟 86400 秒、sudoers 的 `verifypw=any` |

### 不移植的内容

这些东西留在 mac-mini-2018-omarchy 上手工维护，记录在 `~/.agents/docs/fleet-ssh.md`，因为它们属于这一台机器而不是每台 Omarchy 主机：

- **`~/.local/bin/*-gw` 包装器**和各 agent 的网关 settings：由 mac-mini-m2 上的 `cliproxy-tier-host.py` 写入。本仓库**从不**写这些文件。`/usr/bin/omarchy-agent` 的补丁归 `omarchy-cliproxy` role。
- **arch-mact2** 的 pre-refresh hook（只有 T2 硬件需要）。
- **Sunshine**：Omarchy 的安装器有 bug，unit、web app 和 ufw 规则是手工做的一次性工作。

macbook-provision 里没有移植的 role：`host-facts`、`shell`、`omarchy`（Omarchy 自身就是这三者）、`apple-container`、`cua`、`cmux`、`moshi`（没有 Linux 版）、`cc-switch`、`intellij-idea`、`kimi-code`、`lcu`（需要 ChatGPT 桌面应用与 X11 桌面；Omarchy 是 Wayland，LCU 不支持，Q18）、`removemacai`（关闭 macOS 的 Apple Intelligence 等设置，Linux 没有对应物，上游 Q229，Q19）、`macos-connectors`（Apple 自带 App 的 CLI，上游 Q236，Q24）、`ego-browser`（Ego Lite 没有 Linux 版，上游 Q239，Q24）以及 `homebrew` 里的 Sublime Text（去掉：无头服务器用不上，2026-10-11 首次运行装上后又卸掉了）。OpenCLI（agent-reach 的 X 后备）也不装，见 `roles/agent-reach/README.md`。

### Agent CLI 与技能

`main.yml` 里有十来个 role 装的是各家 coding agent 的 CLI 和它们共用的技能。上面的表格每个 role 只有一行，而这一块有几处「一行说不清」的地方，集中写在这里。

#### 安装渠道

和 Mac 上五花八门的渠道不同，这里几乎全是 mise，因为 Omarchy 自己就是这么装它们的（OpenClaw 例外，它是 Omarchy 仓库里的 pacman 包）：

| 工具 | 安装渠道 | 落地位置 / 命令名 |
|------|----------|-------------------|
| claude-code | mise `claude` | stub `~/.local/bin/claude` |
| codex | mise `codex` | stub `~/.local/bin/codex` |
| opencode | mise `opencode` | stub `~/.local/bin/opencode` |
| omp | mise（GitHub release） | stub `~/.local/bin/omp` |
| pi | mise `pi` | stub `~/.local/bin/pi` |
| copilot | mise `copilot`（aqua） | stub `~/.local/bin/copilot` |
| crush | mise `crush`（aqua） | stub `~/.local/bin/crush` |
| gemini | mise `gemini`（npm） | stub `~/.local/bin/gemini` |
| grok | mise `npm:@xai-official/grok` | stub `~/.local/bin/grok`；首次运行时原生二进制下载到 `~/.grok/bin`；经网关用 `grok-gw` |
| openclaw | `omarchy-install-openclaw-cli`（pacman `openclaw`） | `/usr/bin/openclaw` |
| dsh | mise `npm:@deepseek-ai/dsh`（加 `pnpm`） | stub `~/.local/bin/dsh`；插件在 `~/.dsh/profiles/<profile>/` |
| hermes | `omarchy-install-hermes-cli`（mise pipx） | `~/.local/bin/hermes` |
| agent-reach | **没有包管理器**，见下 | 由 `claude-gw -p` 按上游文档安装 |

stub 是 `omarchy-mise-install` 写的那种：先 `mise use -g`、再 `mise x`，第一次调用时装好工具。**升级统一由 `mise` role 的一次 `mise up` 完成**，各工具 role 没有自己的 update 步骤。

Omarchy 支持的 agent 里，**Cursor CLI 和 Muse Code 不装**：前者的模型调用都在 Cursor 自己的服务器上，后者只接受 Meta 目录里的模型，都走不了 CLIProxyAPI（DECISIONS Q11）。

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
- 某个「只取几个技能」的源里的技能被上游改名或下架时，CLI 会退出 1 并打印 `● Available skills:` 加一整份清单，**读起来像帮助信息，其实是错误**。用 `npx skills@latest add <源> -l` 看上游现在有什么（`-l` 只列不装），然后改 `roles/skills/vars/main.yml`。这类失败**推迟到整个 play 的末尾**才抛出，但 PLAY RECAP 里依然是 `failed=1`。
- **`omarchy-update` 需要重启时**，`pacman` role 通知一个 handler：最后一个 role 跑完后，它用 `systemd-run` 安排 5 分钟后重启。这样每晚的 sweep 先读到 PLAY RECAP，再重启；`/tmp` 是 tmpfs，重启后 `/tmp/provision.log` 就没了（DECISIONS Q14）。

#### role 代劳不了、需要人工的步骤

- **Codex 的 hook 信任**是一次性的、每台机器各做一次：跑 `codex`、打开 `/hooks`，审核并信任 ponytail 的三个生命周期 hook，然后开一个新 thread。
- **opencode 的 provider 认证**没有做：安装器带的是 `--skip-auth`。
- **新装的 agent 要在 m2 上跑一次 `cliproxy-tier <host>`。** `copilot-gw`、`gemini-gw`、`grok-gw`、`kimi-gw`、crush、openclaw 的网关配置以及 OpenClaw 的 onboarding 都由它完成，而它只处理已经装好的 agent。
- **rename 钩子装上或更新后**，Codex 下次启动会问是否信任这个钩子，选「Trust all and continue」；已经在跑的 Claude Code 会话要打开一次 `/hooks` 或重启才会用上。
- **agent-reach 只配好了零配置的渠道。** 其余渠道要 cookie 或点一下浏览器扩展。要补齐就自己交互式跑一次 `agent-reach doctor`。
- **paseo 的配对**：`paseo daemon pair`。
- **Tailscale 首次登录**：没有 `TAILSCALE_AUTH_KEY` 时手工 `sudo tailscale up --accept-dns --accept-routes --operator=$USER`。

## 致谢

本项目是 [soulmachine/macbook-provision](https://github.com/soulmachine/macbook-provision) 的移植，后者参考了 [hayajo/macbook-provision](https://github.com/hayajo/macbook-provision)。
