# Setup

How the `chrome-devtools` MCP server is installed and configured for this skill. SKILL.md does not depend on these exact values, adjust them to your machine.

## Requirements

- Node.js LTS with `npx` on the PATH.
- Google Chrome, current stable. Chrome for Testing also works, other Chromium browsers are not supported upstream.
- `chrome-devtools-mcp`, fetched by `npx` on every start (`@latest`).

## Browser profile

The server launches Chrome with a dedicated, persistent profile at `~/chrome-agent`. A separate profile is required: since Chrome 136 remote debugging is refused on the default profile, and a dedicated profile also keeps your personal cookies away from the agent.

Cookies and logins stay in that profile between sessions, so a human signs in to a site once, in the window the agent opens. Only one Chrome process can use a profile at a time. To sign in before the agent runs, open Chrome on the profile, log in and quit it before starting a session:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --user-data-dir="$HOME/chrome-agent" \
  --no-first-run --no-default-browser-check
```

Without `--userDataDir` the server uses `~/.cache/chrome-devtools-mcp/chrome-profile`. With `--isolated` it creates a throwaway profile that is deleted when the browser closes, which loses logins.

## Register the MCP server

The viewport is fixed at 1440x900 so screenshots and layouts stay comparable between runs.

Claude Code, user scope (available in every project):

```sh
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --userDataDir "$HOME/chrome-agent" --viewport 1440x900
```

Codex:

```sh
codex mcp add chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest --userDataDir "$HOME/chrome-agent" --viewport 1440x900
```

The shell expands `$HOME`, so the stored configuration holds an absolute path. Check the result with `claude mcp get chrome-devtools` or `codex mcp list`.

Clients load MCP tools only at session start. Restart Claude Code or Codex after adding or changing the server.

## Optional flags

Append these to the server arguments when needed:

- `--categoryExtensions` for extension tools, `--memoryDebugging` for heap snapshot analysis.
- `--headless` to run without a window. Avoid it when a human has to log in or solve a captcha.
- `--browserUrl http://127.0.0.1:9222` or `--autoConnect` to attach to a Chrome you started yourself instead of launching one.
- `--filesystemRoot <dir>` to let file-writing tools save outside the client's roots.
- `--acceptInsecureCerts` for local development servers with self-signed certificates.
- `--no-usage-statistics` to opt out of Google's usage statistics, `--no-performance-crux` to stop sending trace URLs to the CrUX API.

The full list is in `npx chrome-devtools-mcp@latest --help` and in the upstream [configuration guide](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md).

## Current install

Last checked on 2026-09-14 with Claude Code 2.1.270, Codex CLI 0.154.0 and chrome-devtools-mcp 1.9.0 on macOS (Apple Silicon). Both clients use the registration above.

`npx -y ...@latest` checks npm on every start, so a slow network can push startup past the client timeout and the server shows as failed to connect. Start the session again, or raise the limit: `MCP_TIMEOUT` (milliseconds) in the environment for Claude Code, `startup_timeout_sec` under `[mcp_servers.chrome-devtools]` in `~/.codex/config.toml` for Codex.
