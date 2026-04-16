# View

A minimalist macOS browser built on `WKWebView`, intended as a lightweight alternative to Chromium-based main browsers.

## Why

Main browsers accumulate massive sessions over time — hundreds of tabs, deep history, heavy memory footprint. View is designed to stay small on purpose: a focused, narrow-session browser that reduces cognitive load on both the user and the machine. It is not meant to replace your main browser; it is meant to be the *other* browser you switch to when you want to think clearly.

## Design

- Single native AppKit binary, no Electron, no Chromium fork
- Vertical tab sidebar only — no horizontal tab strip, no tab overflow
- Minimal address bar with Google fallback and history autocomplete
- Vim-style keybindings on web content, with a per-site whitelist so apps like Gmail / Twitter / YouTube keep their native shortcuts
- Native scroll animation for page navigation: `Ctrl-f` / `Ctrl-b` and `gg` / `G` go through the same AppKit scroll path as Space / Shift-Space / Cmd-↑ / Cmd-↓, so the feel is identical
- Event-driven session persistence — windows, tabs, sidebar width all restore on relaunch with no debounce / no timer
- Multi-window sidebar width sync via in-process notifications
- Favicon display in the sidebar
- Follows system Dark Mode automatically (including blank pages)

## Keyboard

### App-level (AppKit)

| Shortcut | Action |
| --- | --- |
| `Cmd-T` | New tab (focus address bar) |
| `Cmd-N` | New window |
| `Cmd-L` | Focus address bar |
| `Cmd-W` | Close window |
| `Cmd-[` / `Cmd-]` | Back / Forward |
| `Cmd-R` | Reload |
| `Cmd-1`…`Cmd-8` | Switch to tab N |
| `Cmd-9` | Last tab |
| `Cmd-Shift-]` / `Cmd-Shift-[` | Next / Previous tab |
| `Ctrl-Tab` / `Ctrl-Shift-Tab` | Next / Previous tab |
| `Ctrl-f` / `Ctrl-b` | Page down / up (native) |

### Vim layer (JS, page content)

| Key | Action |
| --- | --- |
| `j` / `k` | Scroll down / up |
| `d` / `u` | Half page down / up |
| `gg` / `G` | Top / Bottom (native) |
| `H` / `L` | History back / forward |
| `r` | Reload |

The Vim layer passes through on whitelisted sites (`mail.google.com`, `twitter.com`, `x.com`, `reddit.com`, `youtube.com` by default) for unmodified keys. `Ctrl-f`/`Ctrl-b` and `gg`/`G` stay active everywhere because they do not collide with web app shortcuts.

## Building

```
make          # debug build (single-arch, ~3s incremental)
make build    # release build (universal binary)
make run      # debug build and launch
make test     # run unit tests
make fmt      # swift-format in place
```

Requires Xcode and macOS 15.0 or newer.

## Status

Personal project, MVP. Usable as a daily light-duty browser for the author. Many polish items are still open.
