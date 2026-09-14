# chrome-devtools

Agent skill that drives a real Chrome through chrome-devtools-mcp when WebFetch cannot read a page.

A skill for Claude Code and Codex. The agent switches to the browser for client-rendered pages, blocks, captchas and logins, and reads rate-limited marketplaces at a human pace.

## What you get

- Efficient use of the [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) tools: snapshots, network, console, traces
- Clear rules for when to leave WebFetch for the browser
- Paced reading of Ozon, Avito and Wildberries without getting blocked
- A checklist for diagnosing blocks, starting with VPN and IP
- No captcha solvers, proxy rotation or fingerprint spoofing

## Usage

Run `/chrome-devtools:chrome-devtools` or let the agent pick it up from a request:

```text
find the price of this product on Ozon
WebFetch returns 403 on this page, open it in the browser
check the console errors on localhost:3000
```

Before every marketplace page load the skill runs a throttle script that spaces loads per host and warns when a session budget is used up:

```sh
bash skills/chrome-devtools/scripts/throttle.sh ozon.ru 6
```

## Requirements

- Node.js LTS with `npx`
- Google Chrome, current stable
- Claude Code or Codex CLI

## Install

Clone the repository:

```sh
git clone https://github.com/byrodi/chrome-devtools ~/IdeaProjects/skills/chrome-devtools
```

Then register the MCP server with a dedicated Chrome profile, so logins survive between sessions, and link the skill.

Claude Code:

```sh
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --userDataDir "$HOME/chrome-agent" --viewport 1440x900
ln -s ~/IdeaProjects/skills/chrome-devtools ~/.claude/skills/chrome-devtools
```

Codex:

```sh
codex mcp add chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest --userDataDir "$HOME/chrome-agent" --viewport 1440x900
ln -s ~/IdeaProjects/skills/chrome-devtools/skills/chrome-devtools ~/.agents/skills/chrome-devtools
```

Restart the client afterwards, MCP tools load only at session start. Update with `git pull` in the clone. Profile details, optional flags and timeout notes are in [setup.md](skills/chrome-devtools/references/setup.md).

## Credits and license

The generic tool guidance in SKILL.md is adapted from the `chrome-devtools` skill in [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp), Copyright 2026 Google LLC, Apache-2.0. [NOTICE](NOTICE) lists the upstream commit and the modifications.

Released under the [Apache License 2.0](LICENSE).
