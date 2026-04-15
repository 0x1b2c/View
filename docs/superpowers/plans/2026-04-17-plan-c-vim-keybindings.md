# Plan C: Vim Keybindings (JS Layer)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal Vim-style keymap that operates on web content via an injected `WKUserScript`. Users on non-whitelisted pages can scroll and navigate with familiar Vim keys. Whitelisted sites (Gmail, Twitter, etc.) receive zero interception so their own `j`/`k` shortcuts continue to work.

**Architecture:**
- Pure JS interception. No `NSEvent` local monitors, no native key handling, no message handler round trips for navigation actions.
- A single `WKUserScript` is installed on the `WKUserContentController` of the shared `WKWebViewConfiguration` at app start. Every tab's WebView inherits it.
- The script runs at `.atDocumentStart`, `forMainFrameOnly: false`. Injecting into every frame means `keydown` listeners exist wherever focus lands (main doc or same-origin iframe), and each frame's whitelist check runs against its own `location.hostname`, so embedded content decides for itself.
- Configuration (whitelist, enabled flag) is templated into the JS source at bundle time via string substitution in Swift, so the script has no runtime bridge to Swift.
- On every `keydown` (capture phase), the script:
  1. Bails out if `event.metaKey || event.altKey` — Cmd/Alt shortcuts always pass through untouched.
  2. Bails out if the event target is an editable element (`INPUT`, `TEXTAREA`, `SELECT`, or anything with `isContentEditable`).
  3. For `event.ctrlKey`: only `Ctrl-f` / `Ctrl-b` are intercepted (full-page down/up), **regardless of whitelist**. Any other Ctrl-combo is passed through so system shortcuts like `Ctrl-\`` reach macOS unaffected. `Ctrl+Shift+*` always passes through.
  4. For unmodified keys: `g`/`G` (jump to top/bottom) always run, regardless of whitelist — they're rare enough that colliding with a site's own shortcut is acceptable, and jumping to page extremes is useful on any long feed. For the remaining unmodified keys (`j/k/d/u/H/L/r`), bail out on whitelisted hosts; on non-whitelisted hosts dispatch the keymap and `preventDefault()` + `stopPropagation()` on match.
- Keymap actions are plain JS: `window.scrollBy`, `window.scrollTo`, `history.back/forward`, `location.reload`. No native bridge needed.
- `g` is a one-char prefix with a 1-second timeout (`gg` → scroll to top).

**Tech Stack:** Swift 5.9+, WebKit (WKUserScript, WKUserContentController), JavaScript (plain, no bundler).

**Spec reference:** `docs/superpowers/specs/2026-04-15-view-browser-design.md` §3.

**Important context from Plan A/B (already in place, do not re-design):**
- `Settings.vim.enabled: Bool` and `Settings.vim.whitelist: [String]` already exist in `Packages/ViewCore/Sources/ViewCore/Settings.swift` with sensible defaults.
- `AppDelegate.makeConfiguration(profile:)` currently returns a `WKWebViewConfiguration` with only the profile-scoped data store set. It is the single point where all WebViews' configuration is created, so installing the user script here reaches every tab.
- `Settings` is read once in `AppDelegate.applicationDidFinishLaunching` before `makeConfiguration` is called.

**Design decisions (confirmed during brainstorming):**
- **Keymap:** minimal only. `j/k` scroll down/up (~60px), `d/u` half-page down/up, `Ctrl-f` / `Ctrl-b` full-page down/up, `gg` top, `G` bottom, `H`/`L` history back/forward, `r` reload. No link hints, no page search, no visual mode. These are deferred.
- **Whitelist reload:** startup only. No hot reload, no file watcher. Editing `settings.toml` requires an app restart.
- **Testing:** manual only for Plan C. No Node/Bun/jsdom harness. Unit-testing a JS interception script that depends on `document`, `window`, `location`, and keyboard events is not worth the setup cost at this stage.
- **Toggle UI:** none. `enabled` is edited in `settings.toml` by hand. No menu item, no preference pane.
- **Mode indicator:** none. No UI for "vim mode active" and no progress hint for multi-key sequences (e.g., after pressing `g`). The user either hits the next key in time or the prefix silently resets.

---

## File Structure

```
View/
├── VimInjector.swift            (new: builds the WKUserScript from template + settings)
├── VimScript.swift              (new: Swift string literal holding the JS template)
└── AppDelegate.swift            (modified: install user script in makeConfiguration)
```

**Responsibilities:**
- **`VimScript`**: a Swift `enum` (namespace) exposing a single `static let template: String` constant containing the full JS source. The template has two placeholder tokens that `VimInjector` replaces: `__VIM_WHITELIST_JSON__` (a JSON array of hostnames) and `__VIM_ENABLED__` (`true` or `false`). The JS is stored as a Swift string literal — not a resource file — to avoid Xcode resource-bundling and path-loading concerns.
- **`VimInjector`**: `static func makeUserScript(settings: Settings) -> WKUserScript`. Serializes the whitelist to JSON, performs string replacement on the template, and returns a `WKUserScript(source:injectionTime:.atDocumentStart, forMainFrameOnly: true)`.
- **`AppDelegate.makeConfiguration`**: takes a new `settings: Settings` parameter, builds a `WKUserContentController`, calls `VimInjector.makeUserScript(settings:)`, adds it, and assigns the controller to the configuration.

---

## Task 1: Add `VimScript.swift` with the JS Template

**Files:**
- Create: `View/VimScript.swift`

- [ ] **Step 1.1: Write `VimScript.swift`**

```swift
import Foundation

enum VimScript {
    static let template: String = #"""
    (function () {
      'use strict';

      const ENABLED = __VIM_ENABLED__;
      const WHITELIST = __VIM_WHITELIST_JSON__;

      if (!ENABLED) return;

      function hostMatches(host) {
        for (const entry of WHITELIST) {
          if (host === entry) return true;
          if (host.endsWith('.' + entry)) return true;
        }
        return false;
      }

      if (hostMatches(location.hostname)) return;

      function isEditable(target) {
        if (!target) return false;
        const tag = target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
        if (target.isContentEditable) return true;
        return false;
      }

      const SCROLL_STEP = 60;

      let prefix = null;
      let prefixTimer = null;

      function clearPrefix() {
        prefix = null;
        if (prefixTimer) {
          clearTimeout(prefixTimer);
          prefixTimer = null;
        }
      }

      function armPrefix(ch) {
        prefix = ch;
        if (prefixTimer) clearTimeout(prefixTimer);
        prefixTimer = setTimeout(clearPrefix, 1000);
      }

      function halfViewport() {
        return Math.max(100, Math.floor(window.innerHeight / 2));
      }

      function dispatch(key, event) {
        // Two-char sequences beginning with 'g'.
        if (prefix === 'g') {
          clearPrefix();
          if (key === 'g') {
            window.scrollTo({ top: 0, behavior: 'auto' });
            return true;
          }
          return false;
        }

        switch (key) {
          case 'j':
            window.scrollBy(0, SCROLL_STEP);
            return true;
          case 'k':
            window.scrollBy(0, -SCROLL_STEP);
            return true;
          case 'd':
            window.scrollBy(0, halfViewport());
            return true;
          case 'u':
            window.scrollBy(0, -halfViewport());
            return true;
          case 'g':
            armPrefix('g');
            return true;
          case 'G':
            window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'auto' });
            return true;
          case 'H':
            history.back();
            return true;
          case 'L':
            history.forward();
            return true;
          case 'r':
            location.reload();
            return true;
          default:
            return false;
        }
      }

      window.addEventListener('keydown', function (event) {
        if (event.ctrlKey || event.metaKey || event.altKey) return;
        if (isEditable(event.target)) return;
        if (event.key.length !== 1 && event.key !== 'g') return;

        const handled = dispatch(event.key, event);
        if (handled) {
          event.preventDefault();
          event.stopPropagation();
        } else {
          clearPrefix();
        }
      }, true);
    })();
    """#
}
```

Note: the template uses Swift's raw-string literal (`#"""`) so the JS can contain `\` and `"` freely. The two tokens `__VIM_ENABLED__` and `__VIM_WHITELIST_JSON__` are replaced by `VimInjector` at configuration time.

- [ ] **Step 1.2: Format and build**

```bash
make fmt && make debug 2>&1 | tail -5
```

Expected: build succeeds. This file is a pure data holder with no callers yet, so nothing else should change.

- [ ] **Step 1.3: Commit**

```bash
git add View/VimScript.swift
git commit -m "Add Vim keybinding JS template as a Swift string literal"
```

---

## Task 2: Add `VimInjector.swift`

**Files:**
- Create: `View/VimInjector.swift`

- [ ] **Step 2.1: Write `VimInjector.swift`**

```swift
import Foundation
import ViewCore
import WebKit

enum VimInjector {
    static func makeUserScript(settings: Settings) -> WKUserScript {
        let source = buildSource(settings: settings)
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    static func buildSource(settings: Settings) -> String {
        let whitelistJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: settings.vim.whitelist, options: []),
            let text = String(data: data, encoding: .utf8)
        {
            whitelistJSON = text
        } else {
            whitelistJSON = "[]"
        }
        let enabledToken = settings.vim.enabled ? "true" : "false"

        return
            VimScript.template
            .replacingOccurrences(of: "__VIM_WHITELIST_JSON__", with: whitelistJSON)
            .replacingOccurrences(of: "__VIM_ENABLED__", with: enabledToken)
    }
}
```

Note: `buildSource` is exposed (not private) so it can be exercised by a future test without round-tripping through `WKUserScript`.

- [ ] **Step 2.2: Format and build**

```bash
make fmt && make debug 2>&1 | tail -5
```

- [ ] **Step 2.3: Commit**

```bash
git add View/VimInjector.swift
git commit -m "Add VimInjector that templates whitelist/enabled into the JS"
```

---

## Task 3: Install the User Script in `AppDelegate.makeConfiguration`

**Files:**
- Modify: `View/AppDelegate.swift`

- [ ] **Step 3.1: Thread `Settings` into `makeConfiguration`**

Change the signature of `makeConfiguration` from `(profile: Profile)` to `(profile: Profile, settings: Settings)`, and update the single caller in `applicationDidFinishLaunching` accordingly:

```swift
let configuration = Self.makeConfiguration(profile: profile, settings: settings)
```

- [ ] **Step 3.2: Install the user content controller with the Vim script**

Replace the body of `makeConfiguration` with:

```swift
private static func makeConfiguration(profile: Profile, settings: Settings) -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    if let uuid = UUID(uuidString: profile.dataStoreUUID) {
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
    }

    let userContent = WKUserContentController()
    userContent.addUserScript(VimInjector.makeUserScript(settings: settings))
    config.userContentController = userContent

    return config
}
```

- [ ] **Step 3.3: Build**

```bash
make fmt && make debug 2>&1 | tail -10
```

Expected: build succeeds. Every WebView created through this configuration will now get the Vim script injected at document start.

- [ ] **Step 3.4: Commit**

```bash
git add View/AppDelegate.swift
git commit -m "Install Vim user script on the shared WKWebViewConfiguration"
```

---

## Task 4: Manual Acceptance

- [ ] **Step 4.1: Relaunch cleanly**

```bash
pkill -x View 2>/dev/null || true
.build/Build/Products/Debug/View.app/Contents/MacOS/View &
sleep 2
```

- [ ] **Step 4.2: Non-whitelisted page — keymap active**

In the first tab's address bar type `en.wikipedia.org/wiki/Vim_(text_editor)` and press Enter. After the page loads, click once on the page body to take focus away from the address bar, then:

- Press `j` repeatedly — the page scrolls down.
- Press `k` — scrolls up.
- Press `d` — half-page down.
- Press `u` — half-page up.
- Press `Ctrl-f` — full-page (viewport) down.
- Press `Ctrl-b` — full-page (viewport) up.
- Press `G` (Shift+g) — jumps to the bottom.
- Press `g` then `g` within 1 second — jumps to the top.
- Press `g`, wait >1 second, press `g` — no jump happens. The first `g` prefix timed out and was cleared; the second `g` simply re-arms the prefix (silently), waiting for a follow-up key that never comes.
- Click a link to navigate somewhere. Press `H` — navigates back. Press `L` — navigates forward.
- Press `r` — page reloads.

Expected: every key works. None of them type characters into any page field.

- [ ] **Step 4.3: Editable element — passthrough**

On the same Wikipedia page, click the search box in the article header (or any `<input>` on the page). Press `j`. Expected: the letter `j` is typed into the field, the page does not scroll. Press Escape / click outside the input, press `j` again. Expected: scroll resumes.

- [ ] **Step 4.4: Whitelisted site — unmodified keys pass through, Ctrl-f/Ctrl-b still work**

Open a new tab (Cmd-T) and navigate to `mail.google.com`. Sign in if necessary. In the Gmail inbox view, press `j` and `k`. Expected: Gmail's own keybindings advance/retreat through the message list. The browser must not scroll the page. Verify also on `twitter.com` or `x.com` — `j` and `k` should advance tweets.

Now on the same whitelisted page press `Ctrl-f` and `Ctrl-b`. Expected: the Vim layer scrolls the page one viewport at a time. Whitelist must **not** disable `Ctrl-f`/`Ctrl-b` — these bindings run on every site because Ctrl-prefixed keys don't collide with web-app shortcuts.

Still on the whitelisted page, press `G` — expected jump to the bottom of the page. Press `gg` — expected jump to the top. `g`/`G` are also forced active on every site for parity with page extremes navigation.

- [ ] **Step 4.5: Modifier keys — system shortcuts still work**

With a non-whitelisted page focused:
- Press `Cmd-T` — new blank tab opens (menu item still fires).
- Press `Cmd-L` — address bar focuses.
- Press `Cmd-W` — current tab closes.
- Press `Cmd-Shift-]` / `Cmd-Shift-[` — tab cycles.
- Press `Ctrl-`` (backtick) — macOS cycles browser windows (system behavior).

None of these should be swallowed or blocked by the Vim script.

- [ ] **Step 4.6: `enabled = false` disables the whole layer**

Quit the app. Edit `~/Library/Application Support/View/Profiles/Default/settings.toml` and set `enabled = false` under `[vim]`. Relaunch. On a non-whitelisted page, press `j`. Expected: nothing happens (no scroll, no error). Quit, set `enabled = true` again, relaunch.

- [ ] **Step 4.7: Custom whitelist entry takes effect**

Quit the app. Edit `settings.toml` and add `"en.wikipedia.org"` to `whitelist`. Relaunch. Navigate to Wikipedia. Press `j`. Expected: no scroll (whitelisted, script bails out). Remove the entry, quit, relaunch.

---

## Done Criteria for Plan C

1. `make debug` succeeds.
2. Plan B unit tests still pass: `make test-core`.
3. Plan B regression sanity: Cmd-T, Cmd-N, Cmd-W, tab switching, drag reorder, and session restore still work after the `makeConfiguration` signature change (touched once in `AppDelegate`; verified during Task 4 manual run).
3. On any non-whitelisted page, `j/k/d/u/gg/G/H/L/r` behave as specified.
4. On any whitelisted site (`mail.google.com`, `twitter.com`, `x.com`, `reddit.com`, `youtube.com` by default), the Vim script does not intercept `j/k/d/u/H/L/r`. `Ctrl-f`, `Ctrl-b`, `gg`, and `G` remain active on whitelisted sites — Ctrl-prefixed keys don't collide with web-app shortcuts, and page-extreme navigation is useful everywhere.
5. Typing into `<input>`, `<textarea>`, `<select>`, or a contenteditable element is never intercepted.
6. No Vim-layer interception ever fires for events carrying `Cmd` or `Alt` modifiers. `Ctrl` is only intercepted for `Ctrl-f` and `Ctrl-b`; all other `Ctrl-*` combos (including `Ctrl-\``) pass through to the system.
7. Setting `[vim].enabled = false` in `settings.toml` disables the layer globally on next launch.
8. No `NSEvent` monitors, no native-layer key handling, no message-handler bridge — implementation is JS-only.

---

## Known Limitations (Accepted for MVP)

- **PDF viewer.** WKWebView's built-in PDF preview runs in a plugin process that does not receive injected user scripts. `j/k` will not scroll a PDF; use trackpad / arrow keys.
- **Fullscreen `<video>` on non-whitelisted sites.** If a video element has focus in fullscreen and the user presses `r`, the page will reload (the script does not detect `<video>` as editable). YouTube is already whitelisted; add any other video site to `[vim].whitelist` to avoid this.
- **Cross-origin iframes with their own hostname rules.** Each frame independently evaluates the whitelist against its own `location.hostname`. A whitelisted top-level site embedding a non-whitelisted iframe (or vice versa) will have mixed behavior depending on which frame has focus. This matches the spec's "scoped to web content" contract.

---

## Out of Scope for Plan C (Deferred)

- **Link hints** (`f` / `F`) — requires DOM walk, overlay rendering, and label allocation.
- **Page search** (`/`) — requires a find-in-page overlay.
- **Visual mode / selection** — not MVP.
- **Hot reload of whitelist or `enabled`** — requires file watching and re-injection. Startup read only.
- **Mode indicator / prefix progress UI** — spec explicitly defers.
- **Toggle menu item or preference pane** — TOML editing only.
- **Scroll animation / smooth scrolling options** — fixed `auto` behavior for now.
- **Per-site keymap overrides** — whitelist is on/off, not granular.
- **Unit tests via jsdom / Bun** — deferred until Plan D or later when the test cost is justified.
