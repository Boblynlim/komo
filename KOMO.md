# komo — a browser that knows you

## What is this
A native macOS browser built in Swift + SwiftUI + WKWebView. Sidebar-first, lightweight, with a built-in link saver and an AI discovery feed (Pulse) planned for v2. Currently a WKWebView prototype — a Helium (Chromium) fork is being built in CI to become the real engine.

## Repo
- **komo (this repo)**: https://github.com/Boblynlim/komo
- **Helium fork**: https://github.com/Boblynlim/helium-macos (Chromium-based, builds in CI)
- **Helium core fork**: https://github.com/Boblynlim/helium

## Project structure
```
main/                          ← git worktree (branch: master)
├── Package.swift              ← Swift Package Manager config
├── project.yml                ← xcodegen spec (optional)
├── komo.xcodeproj/            ← generated Xcode project
├── scripts/
│   └── bundle.sh              ← builds .app bundle from CLI
├── komo/
│   ├── komoApp.swift          ← app entry point
│   ├── komo.entitlements      ← network permissions
│   ├── Assets.xcassets/       ← app icon placeholder
│   ├── Models/
│   │   ├── Tab.swift          ← tab model (WKWebView wrapper, favorites, session)
│   │   ├── TabFolder.swift    ← folder model for grouping tabs
│   │   ├── TabManager.swift   ← tab lifecycle, folders, session save/restore, content blocker
│   │   ├── SavedLink.swift    ← saved link data model
│   │   ├── LinkStore.swift    ← link persistence, tags, search, archive
│   │   ├── DownloadManager.swift ← WKDownload handling, progress, file management
│   │   ├── PulseEngine.swift  ← Claude API client for recommendations (v2, scaffolded)
│   │   └── TasteGraph.swift   ← interest profiling from saved links (v2, scaffolded)
│   └── Views/
│       ├── BrowserWindow.swift    ← main layout (NavigationSplitView + toolbar)
│       ├── SidebarView.swift      ← tab list, folders, pinned, downloads, new tab button
│       ├── URLBar.swift           ← Arc-style compact URL pill + nav buttons
│       ├── WebViewContainer.swift ← NSViewRepresentable WKWebView + download delegate
│       ├── CommandBar.swift       ← ⌘K file-browser style search (tabs, folders, tags, links)
│       ├── BrowserCommands.swift  ← keyboard shortcuts + notification names
│       ├── LinkLibraryView.swift  ← SaveThisOne-style link library (inbox, archive, tags, date groups)
│       ├── SaveLinkPanel.swift    ← ⌘D save dialog (title, tags, notes, suggestions)
│       ├── DownloadPopupCard.swift ← bottom-right download notification card
│       └── PulseView.swift        ← discovery feed UI (v2, scaffolded)
```

## How to build and run
No Xcode needed. Just Swift CLI tools:
```bash
cd ~/src/tries/browser/main
pkill -f komo; bash scripts/bundle.sh && open build/komo.app
```

## What's built (v0.1)

### Browser
- WKWebView with HTTPS upgrade and navigation delegation
- Sidebar-first layout (NavigationSplitView), collapsible with ⌘\
- Arc-style compact URL pill (shows domain only, expands on click/⌘L)
- Tab management: create, close, switch from sidebar
- Folders: group tabs, drag and drop, rename, delete
- Favorites: star any tab (⭐ replaces globe icon), works inside folders
- Content blocker (WKContentRuleList) — blocks Google Analytics, DoubleClick, FB pixel, popups
- Session restore — tabs, folders, favorites persist across quit/relaunch (saved to ~/Library/Application Support/komo/session.json)

### ⌘K Command Bar
- File-browser style: sections for Open Tabs, Folders, Saved Link Tags, Saved Links
- Click a folder → browse tabs inside it (breadcrumb nav)
- Click a tag → browse saved links with that tag
- Type URL → navigates in new tab. Type search → DuckDuckGo
- Arrow keys + Enter navigation, Escape to go back/close
- Purple accent highlight on selected row
- ⌘T opens ⌘K without creating empty tabs — tab only created on navigate

### Link Saver
- ⌘D to save current page (title, tags, notes)
- Auto-tag suggestions based on domain + history
- FlowLayout tag pills with inline editing
- ⌘⇧B to open Link Library view (replaces browser view)
- Library has: Inbox, Archive, Tags sidebar + links grouped by date
- Fuzzy search across title, URL, tags, notes
- Right-click tags to rename/delete
- Persists to ~/Library/Application Support/komo/saved-links.json

### Downloads
- WKDownloadDelegate handles file downloads to ~/Downloads
- Sidebar bottom-left icon → popover showing recent downloads
- Bottom-right popup card appears for 10 seconds on new download
- File type icons, progress bars, "reveal in Finder" on click

### Keyboard Shortcuts
- ⌘T — new tab (opens ⌘K)
- ⌘W — close tab
- ⌘L — focus URL bar
- ⌘K — command bar
- ⌘\ — toggle sidebar
- ⌘D — save link
- ⌘⇧B — toggle link library

## What's NOT built (waiting on Helium/Chromium)
These come free with Chromium — don't rebuild in WKWebView:
- Find-in-page (⌘F)
- History
- Favicons
- DevTools
- Chrome extensions
- Zoom, print, password autofill
- PDF viewer

## Helium (Chromium fork) status
- Forked to https://github.com/Boblynlim/helium-macos
- CI build triggered via GitHub Actions (workflow_dispatch)
- Build takes 4-6 hours across 10 sequential jobs
- Previous build failed due to sccache crash, retried
- Check status: `gh run list --repo Boblynlim/helium-macos`
- Once built, download .dmg artifact from Actions tab

## Pulse — v2 plan (saved, not built)
AI-powered weekly discovery feed. Plan at `~/.claude/plans/jiggly-wandering-bachman.md`

**Content sources (combined):**
1. RSS feeds — user curates blogs/newsletters, Claude filters for taste
2. HN/Reddit/Product Hunt — weekly scrape, Claude picks what matches
3. "Feed me" inbox — paste cool links from X/Instagram as seeds

**How it works:**
- Claude Haiku 4.5 as taste filter (not content source) — ~$0.005/month
- Weekly batch every Monday, auto-opens Pulse tab on launch
- Cold start: interest picker bootstraps taste graph
- Folder exclusion: mark folders as "work" to exclude from taste profile
- Resource impact: <5MB storage, <1MB network/week, zero background CPU

## Architecture notes
- The root `/Users/jazulynn/src/tries/browser/` is a bare-ish git repo
- `main/` is a git worktree on the `master` branch — all work happens here
- `helium-macos/` is the Helium fork clone (separate repo)
- `helium/` is the Helium core clone (separate repo)
- The plan is: komo features (sidebar, link saver, Pulse, ⌘K) get ported as the UI layer on top of Helium's Chromium engine

## User preferences (for future agents)
- No Xcode — build from CLI only (`swift build` + `scripts/bundle.sh`)
- Prefers Arc-style UI: compact URL pill, sidebar-first, no tab bar
- Wants SaveThisOne-style link saving with tags
- Dislikes: overrated/mainstream recommendations, bloat, wasted tokens
- Favorites over pinned tabs (star within folders, not separate section)
- ⌘T should open ⌘K, not create empty tabs
- Tabs should have padding/spacing in sidebar, not edge-to-edge blue
- Purple accent color for selections
- Weekly Pulse refresh, not daily — Monday auto-open
