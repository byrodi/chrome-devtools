# Setup

How the two `chrome-devtools` MCP servers are installed and configured for this skill. `chrome-devtools` launches a separate agent browser and is the default. `chrome-personal` attaches to the Chrome you use every day and is used only when a task needs your logins.

## Requirements

- Node.js 22 or newer with `npx` on the PATH.
- Google Chrome 144 or newer, current stable. Other Chromium browsers are not supported upstream.
- `chrome-devtools-mcp`, fetched by `npx` on every start (`@latest`).
- `jq` for the Claude Code pacing hook. It ships with macOS 15 and newer.

## Agent browser

The `chrome-devtools` server starts Chrome itself on the first tool call. `--isolated` gives it a temporary profile that is deleted when the browser closes, so every client session gets a clean browser of its own. A fixed `--userDataDir` would keep logins between sessions, but only one Chrome process can use a profile at a time, and a second agent session running in parallel would fail to start its browser.

The window is visible and fixed at 1440x900, so a human can solve a captcha there and screenshots stay comparable between runs. The browser runs as a separate Chrome instance next to your everyday one, with its own Dock icon.

## Everyday browser

The `chrome-personal` server attaches to your running Chrome with `--autoConnect`. In that Chrome open `chrome://inspect/#remote-debugging` and turn on remote debugging. The setting stays on across restarts. The server does not start Chrome, so the tools fail until Chrome is open. Chrome may ask for permission when the server connects and shows a banner while it is controlled. The agent sees every tab and cookie in that browser and acts under your own accounts.

The server attaches to every open tab. Chrome freezes background tabs, and a frozen or busy tab does not answer DevTools commands, so `list_pages` and `new_page` hang for about three minutes and fail with `Network.enable timed out`. Upstream documents it in [troubleshooting](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/troubleshooting.md) and [issue #1230](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/1230). Fewer open tabs help. `scripts/stuck-tabs.mjs` lists the tabs that do not answer, opening or closing them clears the hang:

```sh
node scripts/stuck-tabs.mjs
node scripts/stuck-tabs.mjs "$HOME/Library/Application Support/Google/Chrome Beta"
```

The optional argument is the Chrome user data directory. Without it the script uses the default stable profile directory for the platform.

## Register the MCP servers

Claude Code, user scope (available in every project):

```sh
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --isolated --viewport 1440x900
claude mcp add chrome-personal --scope user -- \
  npx -y chrome-devtools-mcp@latest --autoConnect
```

Codex:

```sh
codex mcp add chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest --isolated --viewport 1440x900
codex mcp add chrome-personal -- \
  npx -y chrome-devtools-mcp@latest --autoConnect
```

Check the result with `claude mcp list` or `codex mcp list`.

Clients load MCP tools only at session start. Restart Claude Code or Codex after adding or changing a server. Sessions that were already open keep the old servers until they restart.

## Pacing hook (Claude Code)

`scripts/throttle-hook.sh` runs `throttle.sh` before every `navigate_page` and `new_page` on both servers, so pacing does not depend on the model remembering it. Over the session budget it asks you to confirm each further load. Add it to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__chrome-(devtools|personal)__(navigate_page|new_page)",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/skills/chrome-devtools/skills/chrome-devtools/scripts/throttle-hook.sh\"",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

The path assumes the symlink from the README. Hooks load at session start, restart Claude Code after adding it. Codex has no equivalent, there the agent calls `throttle.sh` itself as SKILL.md describes.

Counters live in `${TMPDIR:-/tmp}/chrome-devtools-throttle`. Delete a host's file there to reset its budget early.

## Optional flags

Append these to the server arguments when needed. Flags that change how Chrome starts apply only to the agent browser.

- `--categoryExtensions` for extension tools, `--memoryDebugging` for heap snapshot analysis.
- `--headless` to run the agent browser without a window. Avoid it when a human has to log in or solve a captcha.
- `--acceptInsecureCerts` for local development servers with self-signed certificates.
- `--filesystemRoot <dir>` to let file-writing tools save outside the client's roots.
- `--no-usage-statistics` to opt out of Google's usage statistics, `--no-performance-crux` to stop sending trace URLs to the CrUX API.

The full list is in `npx chrome-devtools-mcp@latest --help` and in the upstream [configuration guide](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md).

## Current install

Checked on 2026-09-25 with chrome-devtools-mcp 1.10.1 and Chrome 154 on macOS (Apple Silicon). Claude Code runs both servers and the pacing hook. With 47 tabs open in the everyday Chrome, three frozen background tabs made every `--autoConnect` call hang, which is why the agent browser became the default.

`npx -y ...@latest` checks npm on every start, so a slow network can push startup past the client timeout and the server shows as failed to connect. Start the session again, or raise the limit: `MCP_TIMEOUT` (milliseconds) in the environment for Claude Code, `startup_timeout_sec` under `[mcp_servers.<name>]` in `~/.codex/config.toml` for Codex.
