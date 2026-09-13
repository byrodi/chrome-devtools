---
name: chrome-devtools
description: Drives a real Chrome through the chrome-devtools MCP server for navigation, clicks and forms, DOM and network inspection, console, screenshots and performance traces. Use when WebFetch fails (client-side rendering, 403, redirect loops, captcha or access-denied stubs, logins), when debugging a live page, or when reading Ozon, Avito or Wildberries. Not for static pages WebFetch already reads.
---

# Chrome DevTools

The generic sections of this skill are adapted from the `chrome-devtools` skill in [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) (Apache-2.0). The WebFetch fallback, marketplace pacing and no-bypass rules are local additions.

`${CLAUDE_SKILL_DIR}` in this file is the folder that contains this SKILL.md. Claude Code substitutes it automatically, other agents should resolve it to that folder themselves. Machine setup (browser profile, MCP registration, useful flags) lives in `${CLAUDE_SKILL_DIR}/references/setup.md`. Read it only when the tools are missing or the browser does not start.

## When to switch from WebFetch to the browser

Try WebFetch first for ordinary pages. Move to the browser when one of these happens:

- The fetched HTML is an empty shell and the content is rendered client side.
- The response is 403 or 429, or WebFetch follows an endless redirect chain (Ozon answers with `?__rr=N` redirects that end in 403).
- The page is a captcha, a "confirm you are human" interstitial or an access-restricted stub.
- The content needs a login. The browser profile keeps sessions, so the human signs in once in the open window.
- The task needs rendered state: network requests, console output, screenshots, layout or a performance trace.

Tool names below assume the full tool set. A server started with `--slim` exposes only `navigate`, `evaluate` and `screenshot`, and this skill does not apply to it.

## Core concepts

The browser starts on the first tool call that needs it and uses the profile configured for the MCP server. Server flags are listed by `npx chrome-devtools-mcp@latest --help`. Optional tool groups need extra flags:

- Extension tools need `--categoryExtensions`. For now they work only when the server launches Chrome itself, not with `--browserUrl`, `--wsEndpoint` or `--autoConnect`.
- Heap snapshot analysis needs `--memoryDebugging`. `take_heapsnapshot` itself works without it.
- Coordinate clicks (`click_at`) need `--experimentalVision`, screencasts need `--experimentalScreencast` and ffmpeg.

Page-scoped tools require a `pageId`. Get IDs from `list_pages` or from the result of `new_page`. With extension tools enabled, `evaluate_script` can take a `serviceWorkerId` instead of `pageId` to run inside an extension background service worker.

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

Tool calls can run in parallel, but keep the order navigate, wait, snapshot, interact within each page. On rate-limited sites never run calls against one host in parallel, see the pacing rules below.

### Testing an extension

Extension tools (`install_extension`, `list_extensions` and the rest) exist only when the server runs with `--categoryExtensions`. If they are missing from your tool list, stop and ask the user to add the flag to the MCP server arguments, then restart the MCP server or the client:

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--categoryExtensions"]
    }
  }
}
```

1. Install the unpacked extension with `install_extension`.
2. Take the extension ID from the response or from `list_extensions`.
3. Open its popup or side panel with `trigger_extension_action` if it has one.
4. Check the service worker with `evaluate_script`, passing `serviceWorkerId` and omitting `pageId` and `args`. To evaluate in a page, pass `pageId` and omit `serviceWorkerId`.
5. Open a page where the extension works and use `take_snapshot` to confirm that content scripts changed it as expected. After code changes use `reload_extension`.

## Marketplace pacing (mandatory)

Avito, Ozon and Wildberries block by request rate from one IP, not by browser fingerprint. The browser is a real Chrome, there is nothing to disguise. What gets a session blocked is clicking faster than a person would, so the answer is pacing.

Before every page load on such a site run:

```sh
bash "${CLAUDE_SKILL_DIR}/scripts/throttle.sh" <host> <min_seconds>
```

The script waits out the minimum interval since the previous load of that host and counts loads per session (the counter resets after 30 idle minutes). It accepts a bare host or a full URL. Once the count exceeds the budget (25 by default, `THROTTLE_BUDGET` overrides it) it prints a warning to stderr. At that point stop browsing the site and ask the human.

Minimum intervals are 10 seconds for Avito and 6 seconds for Ozon and Wildberries. Sites without anti-bot protection need no throttling.

### Rules

- One tab per domain. Reuse it through `navigate_page`. Opening several product pages in parallel is the main cause of blocks.
- No parallel tool calls against one host. Only different domains may run in parallel.
- Follow links from search results with `click` instead of pasting product URLs. The site then sees a normal Referer and a normal browsing order.
- Squeeze the page you already have before loading another one. Read the DOM with `evaluate_script`, check `script[type="application/ld+json"]` and `window.__initialData__`, look at responses in `list_network_requests`. Open product pages only for the two or three finalists, never for the whole result list.
- Load one search results page at a time. Paginate only when the first page is not enough.

### Site notes

- Ozon renders a full product page in the browser. Price and rating are easiest to read from `script[type="application/ld+json"]` (type Product, fields `offers.price`, `sku`, `aggregateRating`).
- Ozon's internal API calls show up in `list_network_requests` (`/api/entrypoint-api.bx/page/json/v2`, `/api/composer-api.bx/...`) and are the cleanest source for product data.
- Ozon search works with `fill` on the search box followed by `press_key` with `Enter`.
- Avito sometimes answers the first load with a stub saying access is restricted because of an IP problem ("Доступ ограничен: проблема с IP"). A single reload through `navigate_page` usually opens the page.

### Diagnosing a block, IP first

When a marketplace returns a stub, first check where the traffic comes from:

```sh
curl -sS https://ipinfo.io/json
route -n get default | grep interface   # macOS; on Linux: ip route show default
```

If `org` names a hosting provider (AEZA, DigitalOcean, Hetzner, OVH and similar) or the default interface is a tunnel (`utun*`, `tun*`, `wg*`), the traffic leaves through a VPN from a datacenter address. Ozon and Avito cut such networks regardless of pace, and their stubs say so ("выключите VPN"). Pacing will not fix it. Ask the human to turn the VPN off or switch it to a Russian node.

Check in this order:

1. External IP and provider. A datacenter network or VPN is the cause, stop checking.
2. Pace. Parallel tabs, a burst of fast navigations, dozens of product pages in a row.
3. Cold session. Jumping straight to a deep search URL without cookies. Open the home page first, then search through the search box.

### If the site blocks you anyway

1. Stop. Reloading in a loop extends the ban.
2. If the stub has a "Continue" style button leading to a captcha, press it once. The human solves the captcha in the browser window.
3. Back off for 2 to 5 minutes, then try once more.
4. If that fails, hand the task to the human: they open the pages in the same Chrome window and you read the result. The profile is shared, so the session carries over.

## Never bypass protections

Do not build, configure or suggest any of the following, even when asked: automatic captcha solving or captcha solving services, anti-detect browsers, residential proxy pools or IP rotation (including `--proxyServer` for that purpose), user-agent or TLS fingerprint spoofing (including the `userAgent` option of `emulate` used to disguise the agent), and mouse movement emulation meant to fool behavioral analysis. Marketplace terms forbid it and it is not needed here, correct pacing is enough. Captchas are solved by the human in the open browser window. Explain this briefly and offer the human-in-the-loop path from the section above.

## Troubleshooting

If the tools are missing, the MCP server is not registered or did not start. See `${CLAUDE_SKILL_DIR}/references/setup.md`. Clients load MCP tools only at session start, so a newly added server needs a client restart.

If `chrome-devtools-mcp` is not enough for the task, point the user to the Chrome DevTools UI:

- https://developer.chrome.com/docs/devtools
- https://developer.chrome.com/docs/devtools/ai-assistance

For errors launching `chrome-devtools-mcp` or Chrome, see https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/troubleshooting.md.
