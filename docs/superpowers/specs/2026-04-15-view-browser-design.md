# View Browser: MVP Design

**Status:** Draft
**Date:** 2026-04-15
**Scope:** Initial architecture and MVP feature design for View, a Safari-based macOS browser.

## 1. Goals and Non-Goals

### MVP Goals

1. **WKWebView-based browser shell.** Native macOS app built on `WebKit.framework`, full control over windows, tabs, keybindings, and storage.
2. **Multiple windows with system-native cycling.** Preserve the macOS default `Ctrl-\`` behavior for cycling application windows. The browser must not intercept this key.
3. **Vertical tabs only.** No horizontal tab layout, no per-window toggle. One layout, less code, less configuration.
4. **Vim-style keybindings on page content.** Injected via `WKUserScript`, scoped to the web page (not app-level). Known sites that define their own `j/k` style shortcuts (Gmail, Twitter, Reddit, YouTube, etc.) are whitelisted and receive no interception at all.
5. **Global page zoom.** A single preference applied to every `WKWebView`. New tabs and new windows inherit it. Changes propagate to all live WebViews immediately.
6. **Session persistence.** Windows, tabs, and selection state restore across app launches.

### Explicit Non-Goals for MVP

- Userscript support (listed in the original draft, deferred).
- Horizontal tab layout.
- Tab forward/back history restoration across launches.
- Scroll position or form state restoration across launches.
- Bookmarks, history browser UI, downloads manager UI.
- Multi-profile switching UI (data layout supports it; UI deferred).
- CI pipeline.

## 2. Architecture

### 2.1 Component Layout

```
AppDelegate
  WindowManager                  manages N BrowserWindow instances
    BrowserWindow (NSWindow)
      TabSidebar                 vertical tab list, left side
      WebContainer               hosts the active tab's WKWebView
        WKWebView                one instance per Tab, never reused

AppSettings (singleton)          reads and writes settings.toml
ProfileManager                   resolves active profile, manages data store
SessionStore                     reads and writes view.sqlite via GRDB
SiteWhitelist                    Vim passthrough list (bundled plus user)
```

### 2.2 Tab-to-WebView Relationship

**One `WKWebView` per tab, never reused.** Switching tabs swaps the current WebView in and out of the container view. Closing a tab destroys its WebView.

Rationale: reusing a single WebView across tabs would force page reloads on every switch, losing in-memory state (form input, video playback, scroll position, WebSocket connections) and mangling the forward and back history. No real browser works that way. Per-tab WebView costs memory but preserves the behavior users expect.

### 2.3 Shared Browser State

All WebViews within a profile share:

- A single `WKProcessPool` (enables cookie sharing within the profile).
- A single `WKWebsiteDataStore(forIdentifier:)` keyed to the active profile's UUID. This stores cookies, localStorage, IndexedDB, Service Worker caches, and all other Web platform storage.

**Critical:** The data store is constructed via `WKWebsiteDataStore(forIdentifier:)`, never `WKWebsiteDataStore.default`. This is required from day one so that future multi-profile work does not require migrating cookies out of the shared system store.

### 2.4 Global Page Zoom

A single `Double` preference (`view.zoom`) is read by `AppSettings` on launch. Every new `WKWebView` applies it via `pageZoom` at construction. When the user changes the preference, `AppSettings` posts a notification that every live `BrowserWindow` observes to update its WebViews.

## 3. Vim Keybindings

### 3.1 Layer

Vim keybindings are implemented **only** at the JavaScript layer via `WKUserScript`. They apply to web content, not to the app. App-level shortcuts (new tab, switch tab, address bar, new window) use standard macOS `NSMenu` `keyEquivalent` bindings and are handled by the system.

No `NSEvent` local monitors. No native-layer key interception. This keeps the design simple and guarantees that system shortcuts like `Ctrl-\`` are never affected by the browser.

### 3.2 Injection

One `WKUserScript` registered on the shared `WKUserContentController`, injected `atDocumentStart`, `forMainFrameOnly: false`. The script listens for `keydown` on `window` in the capture phase.

### 3.3 Decision Tree

For each `keydown` event, the injected script decides whether to handle the key or let it pass:

1. If the current page's hostname matches an entry in `SiteWhitelist`, do nothing. The entire event is passed through to the site.
2. If `document.activeElement` is an `<input>`, `<textarea>`, or `[contenteditable]`, do nothing.
3. Otherwise, dispatch the key according to the Vim keymap (scroll, search, link hints, etc.). Call `preventDefault()` and `stopPropagation()`.

### 3.4 Site Whitelist

A starter list bundled with the app, persisted in `settings.toml` under `[vim.whitelist]`:

- `mail.google.com`
- `twitter.com`, `x.com`
- `reddit.com`
- `youtube.com`

The user can edit `settings.toml` to add entries. A dedicated UI is deferred.

### 3.5 System Shortcut Constraint

The Vim layer must never capture keys that carry `Meta`, `Control`, or `Alt` modifiers matching macOS system shortcuts. Specifically, `Ctrl-\`` must reach the system for window cycling. Since interception happens in JavaScript, modifier combinations that reach JS are naturally passed through when the script's keymap does not match them. The keymap is defined to include only unmodified letter keys and a few `g`-prefix sequences; it never matches modifier-laden events.

### 3.6 Initial Keymap

Deferred to implementation. The design commits only to the decision tree above and the whitelist mechanism. An initial keymap proposal will be part of the implementation plan.

## 4. Persistence

### 4.1 Storage Choice

- **SQLite** (via GRDB.swift) for session data. WAL mode is enabled by default, providing crash safety without custom atomic-rename logic. GRDB supports `Codable`, migrations, and concurrent access.
- **TOML** for user-editable settings. Chosen for comment support, permissive syntax, and clear sections. Parser: `swift-toml` (or equivalent mature Swift TOML library; final choice in implementation plan).

### 4.2 Directory Layout

```
~/Library/Application Support/View/
  Local State.toml
  Profiles/
    Default/
      view.sqlite
      settings.toml
      WebData/
```

**`Local State.toml`** is global, outside any profile. It lists known profiles and the active one:

```toml
active_profile = "Default"

[[profiles]]
id = "Default"
name = "Default"
data_store_uuid = "..."
```

**`Profiles/Default/`** contains all data for the Default profile. Future profiles become sibling directories with identical internal structure. No schema migration required when adding profiles: directory isolation replaces any profile_id column that would otherwise be needed.

**`Profiles/Default/WebData/`** is the filesystem location used by `WKWebsiteDataStore(forIdentifier:)`. Cookies, localStorage, IndexedDB, and Service Worker data live here.

### 4.3 SQLite Schema

```sql
CREATE TABLE sessions (
  id          INTEGER PRIMARY KEY,
  created_at  TEXT NOT NULL,
  closed_at   TEXT,                       -- NULL means currently active
  label       TEXT                        -- reserved for future manual naming
);

CREATE TABLE windows (
  id          INTEGER PRIMARY KEY,
  session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  frame_x     REAL NOT NULL,
  frame_y     REAL NOT NULL,
  frame_w     REAL NOT NULL,
  frame_h     REAL NOT NULL,
  z_order     INTEGER NOT NULL
);

CREATE TABLE tabs (
  id          INTEGER PRIMARY KEY,
  window_id   INTEGER NOT NULL REFERENCES windows(id) ON DELETE CASCADE,
  url         TEXT NOT NULL,
  title       TEXT,
  position    INTEGER NOT NULL,
  is_active   INTEGER NOT NULL DEFAULT 0  -- boolean
);
```

### 4.4 Session Lifecycle

- **Active session:** the row in `sessions` where `closed_at IS NULL`. Exactly one row at a time while the app is running. All window and tab mutations write into this session.
- **On quit:** set `closed_at = CURRENT_TIMESTAMP` on the active session. Archived.
- **On launch:** inspect the `startup.mode` setting.
  - `resume` (default): find the most recent session (by `created_at`), reopen it, set `closed_at = NULL`, rebuild its windows and tabs.
  - `blank`: insert a new session row as the new active session, open one window with one blank tab. Prior archived sessions are untouched.
- **First launch** (no sessions at all): insert a new session, open one blank window, one blank tab.

Historic sessions accumulate in the database and are recallable in the future once UI is built. See Future Work.

### 4.5 Write Cadence

- **Session data:** debounced at one second. Triggers include opening and closing windows, opening and closing tabs, switching tabs, completing a navigation (`didFinish`), and moving or resizing a window. Debouncing prevents rapid user actions from causing write storms.
- **Settings:** written immediately on any change. Volume is negligible.

### 4.6 What is Not Persisted

- Forward and back history inside each tab. `WKBackForwardList` does not expose a clean serialization path, and implementing it by hand would be incomplete (POST requests, form state, scroll position cannot be replayed).
- Scroll position.
- Form field contents.

Web platform storage (cookies, localStorage, IndexedDB, Service Workers) is persisted automatically by `WKWebsiteDataStore` and is unaffected by this section.

### 4.7 Settings File

`Profiles/Default/settings.toml`:

```toml
[view]
zoom = 1.0

[startup]
mode = "resume"  # "resume" or "blank"

[vim]
enabled = true
whitelist = [
  "mail.google.com",
  "twitter.com",
  "x.com",
  "reddit.com",
  "youtube.com",
]
```

## 5. Error Handling

### 5.1 Web Content Process Termination

`WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:)` fires when a tab's renderer crashes. The tab displays an inline placeholder showing the current URL and a reload button. Other tabs and windows are unaffected. Automatic reload is not performed, to avoid crash loops.

### 5.2 Navigation and Network Errors

`didFailProvisionalNavigation` and `didFail` load a bundled error page via `loadHTMLString`. The page shows the error code, description, and a retry button. It does not redirect to any external service.

`NSURLErrorCancelled` (code -999) is ignored. It indicates user-initiated cancellation, not a real failure.

### 5.3 SQLite Corruption at Launch

If opening `view.sqlite` fails (corruption, unknown schema, disk issue):

1. Rename the bad file to `view.sqlite.corrupt-<ISO8601>`.
2. Create a fresh database with the current schema.
3. Present an `NSAlert` explaining that session data was corrupted, naming the backup file.
4. Proceed as a first-launch: one blank window, one blank tab.

### 5.4 SQLite Runtime Write Failure

A persistent quiet indicator (see Observability) turns red when any write fails. Errors are logged via `os_log`. No modal alert, no notification center, no automatic retry. The indicator is the user's signal to open Console.app and investigate.

### 5.5 settings.toml Corruption at Launch

Parse failure: rename the bad file with the same `.corrupt-<ISO8601>` suffix, write a fresh file with default values, present an `NSAlert`.

## 6. Observability and Debugging

No in-app log viewer. All observability is built on native macOS tooling.

### 6.1 Logging

`os.Logger` with subsystem `io.protoss.view` and categories per subsystem (`persistence`, `vim`, `webview`, `window`, `settings`). Logs are simultaneously written to `~/Library/Logs/View/view.log`, rotated daily, retained for seven days.

Viewing options:

- **Console.app** with a filter on subsystem `io.protoss.view`. Native live streaming, filtering, search, export.
- **Tail the log file** with any terminal tool or editor.

### 6.2 Quiet Status Indicator

A small circular indicator at the bottom of the tab sidebar. Default state: invisible or neutral. When any error occurs, it turns red. It does not move, flash, or interrupt. Hover reveals a tooltip with the latest error summary. Clicking opens a popover listing recent errors and the log file path.

### 6.3 Debug Menu

A top-level `Debug` menu with these items:

- **Reveal Data Directory in Finder:** opens `~/Library/Application Support/View/`.
- **Dump State to Log:** serializes the current window, tab, session, and profile state into `os_log` output for inspection in Console.app.
- **Open Logs in Console:** launches Console.app, pre-filtered on the subsystem if the API permits.
- **Copy Data Directory Path:** writes the absolute path to the clipboard.

### 6.4 Web Page Debugging

Every `WKWebView` sets `isInspectable = true` (macOS 13.3+). The standard Safari Web Inspector is launched via right-click Inspect Element or the keyboard shortcut. This is the tool for DOM, Network, Sources, and page-level Console inspection. No attempt is made to replicate or embed it.

## 7. Testing Strategy

### 7.1 What Is Tested

- **Persistence layer:** SQLite schema correctness, session write and restore, TOML read and write, first-launch initialization, corruption fallback paths. Unit tests use GRDB's in-memory database.
- **Vim injection script:** loaded into a jsdom environment, driven with synthetic keydown events. Verifies whitelist matching, input-element detection, and keymap dispatch. No `WKWebView` required.

### 7.2 What Is Not Tested

- `WKWebView` behavior itself (system component).
- AppKit UI layer (manual testing is faster and more reliable).
- End-to-end browser flows.

### 7.3 Manual Acceptance Checklist

1. Open Gmail. Pressing `j` and `k` moves between messages in Gmail. The browser does not scroll.
2. Open Twitter. Pressing `j` and `k` moves between tweets. The browser does not scroll.
3. Open a non-whitelisted page (e.g., Wikipedia). Pressing `j` and `k` triggers Vim scrolling in the browser.
4. Open three windows. `Ctrl-\`` cycles between them via the macOS default behavior. The browser does not intercept the key.
5. All `Cmd-*` system shortcuts continue to function.
6. Set global zoom to 1.5. New windows and new tabs inherit the zoom.
7. Quit and relaunch in `resume` mode. All windows, tabs, and the active tab per window are restored.
8. Switch startup mode to `blank`, quit, relaunch. One blank window appears. The previous session remains in `view.sqlite` (verified via `sqlite3`).
9. Trigger a renderer crash. The affected tab shows the crash placeholder; other tabs are unaffected.
10. Corrupt `view.sqlite` manually. Relaunch. The app starts in a blank state, the corrupt file is renamed with a timestamp suffix, and the Debug menu reveals a log entry describing the event.

### 7.4 CI

None in MVP. Run `swift test` locally.

## 8. Future Work

Tracked here so that MVP-scope decisions do not foreclose these directions.

- **Userscript support.** Compatible with a Tampermonkey-style API surface. Scope and API coverage to be designed separately.
- **Multi-profile UI.** Data layout already supports it via directory isolation. Requires a profile switcher menu, a new-profile flow, and handling of runtime profile switching.
- **Session history recall UI.** Archived sessions are queryable today. A UI for browsing and reopening old sessions is not in MVP.
- **Session history cleanup.** The `sessions` table grows without bound. Future work: a `session.history_limit` preference, an eviction policy based on `closed_at`, and optional pinning.
- **Cross-launch forward/back history.** Requires a custom per-tab history model on top of `WKBackForwardList`. Incomplete without also restoring POST bodies, form state, and scroll position, which are all non-trivial.
- **Vim whitelist editing UI.** Users currently edit `settings.toml` by hand.
- **Bookmarks, history browser, downloads manager.** Out of MVP scope.
- **Initial Vim keymap.** The decision tree and whitelist mechanism are committed here. The specific keymap is deferred to the implementation plan.
- **CI.** Add when project complexity justifies the setup cost.
