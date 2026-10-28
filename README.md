# chrome-devtools

Agent skill that drives a real Chrome through chrome-devtools-mcp when WebFetch cannot read a page.

A skill for Claude Code and Codex. The agent switches to the browser for client-rendered pages, blocks, captchas and logins, and loads every site at a human pace so anti-bot systems do not trip. By default it works in a separate Chrome with a temporary profile and touches your everyday Chrome only when a task needs your logins.

## What you get

- Efficient use of the [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) tools: snapshots, network, console, traces
- Clear rules for when to leave WebFetch for the browser
- A separate agent browser by default, your own Chrome only for tasks that need your session
- A script that finds the frozen tabs that make an attached Chrome hang
- Paced page loads on every site with a random 1 to 5 second interval per site
- A Claude Code hook that applies the pacing to every navigation automatically
- A checklist for diagnosing blocks, starting with VPN and IP
- No captcha solvers, proxy rotation or fingerprint spoofing

## Usage

Run `/chrome-devtools:chrome-devtools` or let the agent pick it up from a request:

```text
find the price of this product on a marketplace
WebFetch returns 403 on this page, open it in the browser
check the console errors on localhost:3000
```

Before every page load the skill runs a throttle script that keeps a random 1 to 5 second interval between loads of one site and stops at a session budget. In Claude Code a PreToolUse hook calls it for every `navigate_page` and `new_page`, in other clients the agent calls it itself:

```sh
bash skills/chrome-devtools/scripts/throttle.sh https://example.com/
```

## Requirements

- Node.js 22 or newer
- Google Chrome 144 or newer. For your everyday browser turn on remote debugging in `chrome://inspect/#remote-debugging`
- Claude Code or Codex CLI
- `jq` for the Claude Code hook (ships with macOS 15 and newer)

## Install

Clone the repository:

```sh
git clone https://github.com/byrodi/chrome-devtools ~/IdeaProjects/skills/chrome-devtools
```

Then register the two MCP servers and link the skill. `chrome-devtools` launches a separate Chrome with a temporary profile and is the default. `chrome-personal` attaches to your everyday Chrome with its logins.

Claude Code:

```sh
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --isolated --viewport 1440x900
claude mcp add chrome-personal --scope user -- \
  npx -y chrome-devtools-mcp@latest --autoConnect
ln -s ~/IdeaProjects/skills/chrome-devtools ~/.claude/skills/chrome-devtools
```

Codex:

```sh
codex mcp add chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest --isolated --viewport 1440x900
codex mcp add chrome-personal -- \
  npx -y chrome-devtools-mcp@latest --autoConnect
ln -s ~/IdeaProjects/skills/chrome-devtools/skills/chrome-devtools ~/.agents/skills/chrome-devtools
```

For Claude Code also add the pacing hook from [setup.md](skills/chrome-devtools/references/setup.md#pacing-hook-claude-code) to `~/.claude/settings.json`. Restart the client afterwards, MCP tools load only at session start. Update with `git pull` in the clone. Details on both browsers, optional flags and timeout notes are in [setup.md](skills/chrome-devtools/references/setup.md).

## Credits and license

The generic tool guidance in SKILL.md is adapted from the `chrome-devtools` skill in [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp), Copyright 2026 Google LLC, Apache-2.0. [NOTICE](NOTICE) lists the upstream commit and the modifications.

Released under the [Apache License 2.0](LICENSE).
