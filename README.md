# chrome-devtools

A skill for Claude Code and Codex that drives a real Chrome through [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp). It tells the agent how to use the DevTools tools efficiently, when to leave WebFetch for the browser, and how to read rate-limited Russian marketplaces without getting blocked.

## Features

- Usage guide for the chrome-devtools-mcp tools, based on the upstream skill and checked against the current tool reference.
- Clear triggers for switching from WebFetch to the browser: client-side rendering, 403 or 429, redirect loops, captcha and access-denied stubs, pages behind a login.
- Pacing rules for Ozon, Avito and Wildberries with a small throttle script that spaces page loads per host and warns when a session budget is exceeded.
- A checklist for diagnosing blocks (VPN or datacenter IP first, then pace, then cold session).
- A hard rule against captcha solvers, anti-detect browsers, proxy rotation and fingerprint spoofing.

## Requirements

- Node.js LTS with `npx`
- Google Chrome, current stable
- chrome-devtools-mcp, started through `npx`
- Claude Code or Codex CLI
- bash, for `scripts/throttle.sh`

## MCP server setup

Register the server with a dedicated, persistent Chrome profile. Logins made in that profile survive between sessions.

Claude Code:

```sh
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --userDataDir "$HOME/chrome-agent" --viewport 1440x900
```

Codex:

```sh
codex mcp add chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest --userDataDir "$HOME/chrome-agent" --viewport 1440x900
```

Restart the client afterwards, MCP tools load only at session start. Profile details, optional flags and timeout notes are in [skills/chrome-devtools/references/setup.md](skills/chrome-devtools/references/setup.md).

## Install for Claude Code

```sh
git clone https://github.com/stependiant/chrome-devtools ~/IdeaProjects/skills/chrome-devtools
ln -s ~/IdeaProjects/skills/chrome-devtools ~/.claude/skills/chrome-devtools
```

Claude Code loads the folder as the plugin `chrome-devtools@skills-dir`. The model picks the skill up from its description, or you invoke it explicitly with `/chrome-devtools:chrome-devtools`.

## Install for Codex

Codex needs the skill folder itself, not the plugin root:

```sh
ln -s ~/IdeaProjects/skills/chrome-devtools/skills/chrome-devtools ~/.agents/skills/chrome-devtools
```

SKILL.md refers to bundled files as `${CLAUDE_SKILL_DIR}/...`. Claude Code substitutes the variable, and the skill tells other agents that it means the folder containing SKILL.md.

## Pacing rules in short

- Run `throttle.sh <host> <min_seconds>` before every page load on a marketplace. Avito needs 10 seconds, Ozon and Wildberries 6.
- Keep one tab per domain and navigate sequentially. No parallel calls against one host.
- Follow links from search results by clicking, and extract data from the loaded page (JSON-LD, embedded state, network responses) before opening more pages.
- Open product pages only for the final two or three candidates.
- After a block, stop, back off for a few minutes and try once. If that fails, hand the browser to the human.
- When the stub mentions VPN or IP, check the external IP before touching the pace.

## Layout

```
chrome-devtools/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── chrome-devtools/
│       ├── SKILL.md
│       ├── references/
│       │   └── setup.md
│       └── scripts/
│           └── throttle.sh
├── LICENSE
├── NOTICE
└── README.md
```

## Credits and license

The generic tool guidance in SKILL.md is adapted from the `chrome-devtools` skill in [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp), Copyright 2026 Google LLC, licensed under Apache-2.0. [NOTICE](NOTICE) lists the upstream commit and the modifications.

This repository is licensed under the [Apache License 2.0](LICENSE).
