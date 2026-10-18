# context-mode role

`context-mode` installs one upstream tool, [context-mode](https://github.com/mksglu/context-mode),
into eight agents (Claude Code, Codex, OpenCode, pi, oh-my-pi, Gemini CLI, Copilot CLI, OpenClaw). Each agent gets it through its own installer, one task file per agent under `tasks/`,
in the shape of the `ponytail` role. `main.yml` first installs the `context-mode` CLI as a mise tool
(`npm:context-mode`, with a `~/.local/bin` stub), because the Gemini and Copilot hooks and MCP
servers run it. Omarchy does not install kimi-code (Q10), so there is no kimi half.

- **Skipped agents.** Hermes, Crush and Grok are left out: upstream has no adapter for them. An
  MCP-only entry would add the tools with no hooks or routing, which upstream does not test.
- **Idempotency markers and refresh diffs:**
  - Claude Code: `known_marketplaces.json` and `installed_plugins.json`; refresh diffs
    `gitCommitSha` around `claude plugin update`.
  - Codex: `[marketplaces.context-mode]` and `[plugins."context-mode@context-mode"]` in
    `~/.codex/config.toml`; refresh diffs the `revision` in
    `~/.codex/.tmp/marketplaces/context-mode/.codex-marketplace-install.json`. The reasons are in
    the ponytail README.
  - OpenCode: the bare `context-mode` entry in `plugin` resolves as `@latest`, so there is no
    refresh.
  - pi: the `~/.pi/agent/npm/node_modules/context-mode` directory; refresh diffs its
    `package.json` version around `pi update --extension npm:context-mode`.
  - oh-my-pi: `omp plugin list --json` against `npm view context-mode version`, the ponytail gate.
  - Copilot CLI: the cache directory under `~/.copilot/installed-plugins/_direct/`; refresh diffs
    the cached `.github/plugin/plugin.json` version around `copilot plugin update`.
  - OpenClaw: `openclaw plugins list --json`; refresh diffs the listed version around
    `openclaw plugins update`.
  - Gemini CLI: no installer, so the role edits its config file (next bullets).
- **The pi package entry lives in `roles/pi/files/agent/settings.json`.** The pi role copies that
  file over `~/.pi/agent/settings.json` on every run, so the same bare `npm:context-mode` is listed
  there. pi needs no `mcp.json`: the extension registers the tools through its own MCP bridge.
- **Gemini CLI: one merge into `~/.gemini/settings.json`.** The merge adds the `mcpServers` entry
  and appends the four upstream hooks to the existing hook lists (`list_merge='append_rp'`), so
  other tools' hooks stay. It runs only while no context-mode hook is present, and writes at 0600.
- **OpenClaw needs `--force` on install.** An npm source sits outside ClawHub review, so
  `openclaw plugins install` refuses without it. The flag also overwrites an existing plugin, so
  the install is gated on the list. The role uses OpenClaw's own installer rather than upstream's
  `npm run install:openclaw` script. It runs only once OpenClaw is onboarded (`~/.openclaw/openclaw.json`).
- **Codex hook trust is a one-time, per-host step the role does not perform**, as for ponytail. The
  role prints a reminder when it installs the plugin: open `/hooks` in `codex` and trust the six
  context-mode hooks. Without the trust, the MCP tools still work; only routing stays quiet.
- **Copilot prints a deprecation warning.** Direct repo installs are deprecated in favour of
  `plugin@marketplace`, but upstream ships no Copilot marketplace yet. Its Claude marketplace
  serves the Claude bundle, so `owner/repo:configs/copilot-cli` is still the documented path.
- **SQLite needs no native build here.** On Linux, Node >= 22.5 uses the built-in `node:sqlite`
  instead of `better-sqlite3`, so a skipped install script does no harm.
- **Left out on purpose:** upstream's optional routing-file copies (`AGENTS.md`, `GEMINI.md`) and
  the Claude Code `statusLine`. The hooks inject the routing instructions at session start.
