---
name: chrome-devtools
description: Drives a real Chrome through the chrome-devtools MCP server for navigation, clicks and forms, DOM and network inspection, console, screenshots and performance traces. Use when WebFetch fails (client-side rendering, 403, redirect loops, captcha or access-denied stubs, logins), when debugging a live page, or when reading sites with anti-bot protection. Not for static pages WebFetch already reads.
---

# Chrome DevTools

The generic sections of this skill are adapted from the `chrome-devtools` skill in [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) (Apache-2.0). The WebFetch fallback, pacing and no-bypass rules are local additions.

`${CLAUDE_SKILL_DIR}` in this file is the folder that contains this SKILL.md. Claude Code substitutes it automatically, other agents should resolve it to that folder themselves. Machine setup (attaching to Chrome, MCP registration, useful flags) lives in `${CLAUDE_SKILL_DIR}/references/setup.md`. Read it only when the tools are missing or the browser does not start.

## When to switch from WebFetch to the browser

Try WebFetch first for ordinary pages. Move to the browser when one of these happens:

- The fetched HTML is an empty shell and the content is rendered client side.
- The response is 403 or 429, or WebFetch follows an endless redirect chain that ends in 403.
- The page is a captcha, a "confirm you are human" interstitial or an access-restricted stub.
- The content needs a login. The agent works in the human's own Chrome, so existing logins apply. If a site is not signed in, the human signs in in that window.
- The task needs rendered state: network requests, console output, screenshots, layout or a performance trace.

Tool names below assume the full tool set. A server started with `--slim` exposes only `navigate`, `evaluate` and `screenshot`, and this skill does not apply to it.

## Core concepts

The server attaches to the human's running Chrome (`--autoConnect`), it never launches its own browser or profile. If the tools fail to connect, ask the human to open Chrome and turn on remote debugging in `chrome://inspect/#remote-debugging`. Chrome shows a permission prompt on connect and a banner while it is controlled. Server flags are listed by `npx chrome-devtools-mcp@latest --help`. Optional tool groups need extra flags:

- Heap snapshot analysis needs `--memoryDebugging`. `take_heapsnapshot` itself works without it.
- Coordinate clicks (`click_at`) need `--experimentalVision`, screencasts need `--experimentalScreencast` and ffmpeg.

Page-scoped tools require a `pageId`. Get IDs from `list_pages` or from the result of `new_page`. `list_pages` returns every tab the human has open, including mail and account pages. Open your own tab with `new_page` for the task, do not navigate away or close the human's tabs, and do not repeat tab URLs in replies beyond what the task needs.

Interaction goes through `take_snapshot`, which returns the accessibility tree with a `uid` for every element. Pass that `uid` to `click`, `fill`, `hover` and the other input tools. When an element is not found, take a fresh snapshot, the page may have changed.

## Workflow patterns

### Before interacting with a page

1. Open it with `navigate_page` or `new_page`.
2. Call `wait_for` with a list of texts when you know what should appear. It resolves on the first match.
3. Call `take_snapshot` with the `pageId` to see the structure.
4. Act with `click`, `fill`, `fill_form`, `press_key` or `type_text`, passing the `uid` and the same `pageId`.

### Efficient data retrieval

- Write large outputs to files. `take_snapshot`, `take_screenshot`, `evaluate_script` and the performance trace tools take `filePath`, `get_network_request` takes `requestFilePath` and `responseFilePath`.
- A snapshot of a large page is around 100 KB (about 1100 lines of accessibility tree). Save it to a file and read only the parts you need.
- File paths must sit inside the MCP roots the client provides, which for Claude Code is the working directory. A path outside, for example `/private/tmp`, fails with `Access denied`. A client without roots support can write only to the OS temp directory.
- Page through long lists with `pageIdx` and `pageSize`. Filter console messages with `types` and network requests with `resourceTypes`.
- Input tools return no snapshot by default. Set `includeSnapshot: true` only when you need the updated state in the same call.
- For read-only scripts pass `waitForStableDom: false` to `evaluate_script`.

### Tool selection

- Use `take_snapshot` for automation. It is text based, faster and cheaper than an image.
- Use `take_screenshot` when someone needs to see the visual state.
- Use `evaluate_script` for data that is missing from the accessibility tree (JSON-LD, embedded state objects, computed values).
- Use `list_network_requests` and `get_network_request` to read the JSON the page loaded from its own API. This is often the cleanest data source.
- Use `list_console_messages` and `get_console_message` for errors and logs.

### Parallel execution

Tool calls can run in parallel, but keep the order navigate, wait, snapshot, interact within each page. Never run calls against one host in parallel, see the pacing rules below.

## Pacing (mandatory)

Anti-bot systems mostly block by request rate from one IP, not by browser fingerprint. The browser is a real Chrome under the human's own profile, there is nothing to disguise. What gets a session blocked is loading pages faster than a person would, so the answer is pacing on every site.

Every page load goes through `scripts/throttle.sh`. Before each load it picks a random interval between 1 and 5 seconds and waits until that much time has passed since the previous load of the same site, so loads never come at a fixed machine rhythm. Subdomains share the counter of their site. Local targets (localhost, loopback, private addresses, `file:`, `chrome:`) pass without a wait. `THROTTLE_MIN` and `THROTTLE_MAX` change the range.

The script also counts loads per site and session (the counter resets after 30 idle minutes). Once a site exceeds the budget (25 loads by default, `THROTTLE_BUDGET` overrides it) the script prints a warning and exits with 3. At that point stop browsing the site and ask the human.

A site that answers with captchas, 429 or access stubs at this pace needs fewer loads, not a longer script. Follow "If the site blocks you anyway" below.

In Claude Code a PreToolUse hook runs the script before every `navigate_page` and `new_page` (reload, back and forward reuse the previous host), so do not call it yourself for those tools. Call it by hand in these cases:

- Before a `click`, `press_key` or form submit that loads a new page. Pass the target URL, or no argument to reuse the host of the previous load.
- Before each `fetch` against the site from `evaluate_script`. A request to the site's API counts as a load.
- Before every page load in clients without the hook, for example Codex.

```sh
bash "${CLAUDE_SKILL_DIR}/scripts/throttle.sh" [host-or-url]
```

### Rules

- One tab per domain. Reuse it through `navigate_page`. Opening several pages of one site in parallel is the main cause of blocks.
- No parallel tool calls against one host. Only different domains may run in parallel.
- Follow links from lists and search results with `click` instead of pasting deep URLs. The site then sees a normal Referer and a normal browsing order.
- Squeeze the page you already have before loading another one. Read the DOM with `evaluate_script`, check `script[type="application/ld+json"]` and embedded state objects such as `__NEXT_DATA__`, look at responses in `list_network_requests`. Open detail pages only for the two or three finalists, never for the whole list.
- Load one page of results at a time. Paginate only when the first page is not enough.
- No loops of `fetch` calls over a site's API from `evaluate_script`. If the task needs many records, ask the human first.

### Diagnosing a block, IP first

When a site returns a stub, a captcha or 403 and 429 responses, first check where the traffic comes from:

```sh
curl -sS https://ipinfo.io/json
route -n get default | grep interface   # macOS; on Linux: ip route show default
```

If `org` names a hosting provider or the default interface is a tunnel (`utun*`, `tun*`, `wg*`), the traffic leaves through a VPN from a datacenter address. Many sites cut such networks regardless of pace, and regional sites also cut foreign addresses. Their stubs often say so and ask to turn the VPN off. Pacing will not fix it. Ask the human to turn the VPN off or switch it to a node in the site's country.

Check in this order:

1. External IP and provider. A datacenter network or VPN is the cause, stop checking.
2. Pace. Parallel tabs, a burst of fast navigations, dozens of detail pages in a row, a loop of API requests.
3. Cold session. Jumping straight to a deep search URL without cookies. Open the home page first, then search through the search box.

### If the site blocks you anyway

1. Stop. Reloading in a loop extends the ban.
2. If the stub has a "Continue" style button leading to a captcha, press it once. The human solves the captcha in the browser window.
3. Back off for 2 to 5 minutes, then try once more.
4. If that fails, hand the task to the human: they open the pages in the same Chrome window and you read the result. It is the same browser, so the session carries over.

## Never bypass protections

Do not build, configure or suggest any of the following, even when asked: automatic captcha solving or captcha solving services, anti-detect browsers, residential proxy pools or IP rotation (including `--proxyServer` for that purpose), user-agent or TLS fingerprint spoofing (including the `userAgent` option of `emulate` used to disguise the agent), and mouse movement emulation meant to fool behavioral analysis. Site terms forbid it and it is not needed here, correct pacing is enough. Captchas are solved by the human in the open browser window. Explain this briefly and offer the human-in-the-loop path from the section above.

## Troubleshooting

If the tools are missing, the MCP server is not registered or did not start. See `${CLAUDE_SKILL_DIR}/references/setup.md`. Clients load MCP tools only at session start, so a newly added server needs a client restart.

If `chrome-devtools-mcp` is not enough for the task, point the user to the Chrome DevTools UI:

- https://developer.chrome.com/docs/devtools
- https://developer.chrome.com/docs/devtools/ai-assistance

For errors launching `chrome-devtools-mcp` or Chrome, see https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/troubleshooting.md.
