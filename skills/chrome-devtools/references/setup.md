# Setup

How the `chrome-devtools` MCP server is installed and configured for this skill. The server attaches to the Chrome you use every day, with its tabs and logins. It never launches a separate browser or profile.

## Requirements

- Node.js LTS with `npx` on the PATH.
- Google Chrome 144 or newer, current stable. Other Chromium browsers are not supported upstream.
- `chrome-devtools-mcp`, fetched by `npx` on every start (`@latest`).
- `jq` for the Claude Code pacing hook. It ships with macOS 15 and newer.

## Enable remote debugging

In your Chrome open `chrome://inspect/#remote-debugging` and turn on remote debugging. The setting stays on across restarts.

Chrome asks for permission when the server connects and shows a banner while it is controlled. The server does not start Chrome, so the tools fail until Chrome is open. Screenshots follow the window size.

The agent sees every tab and cookie in that browser and acts under your own accounts. The pacing hook below keeps page loads at a human rate on every site.

## Register the MCP server

Claude Code, user scope (available in every project):

```sh
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --autoConnect
```

Codex:

```sh
codex mcp add chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest --autoConnect
```

Check the result with `claude mcp get chrome-devtools` or `codex mcp list`.

Clients load MCP tools only at session start. Restart Claude Code or Codex after adding or changing the server.

## Pacing hook (Claude Code)

`scripts/throttle-hook.sh` runs `throttle.sh` before every `navigate_page` and `new_page`, so pacing does not depend on the model remembering it. Over the session budget it asks you to confirm each further load. Add it to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__chrome-devtools__navigate_page|mcp__chrome-devtools__new_page",
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

Append these to the server arguments when needed:

- `--memoryDebugging` for heap snapshot analysis.
- `--filesystemRoot <dir>` to let file-writing tools save outside the client's roots.
- `--no-usage-statistics` to opt out of Google's usage statistics, `--no-performance-crux` to stop sending trace URLs to the CrUX API.

The full list is in `npx chrome-devtools-mcp@latest --help` and in the upstream [configuration guide](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md).

## Current install

Checked on 2026-09-21 with chrome-devtools-mcp 1.9.0 and Chrome 153 on macOS (Apple Silicon). Claude Code and Codex both attach with `--autoConnect`, Claude Code runs the pacing hook.

`npx -y ...@latest` checks npm on every start, so a slow network can push startup past the client timeout and the server shows as failed to connect. Start the session again, or raise the limit: `MCP_TIMEOUT` (milliseconds) in the environment for Claude Code, `startup_timeout_sec` under `[mcp_servers.chrome-devtools]` in `~/.codex/config.toml` for Codex.
