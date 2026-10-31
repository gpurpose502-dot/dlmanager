# Download Manager

A personal iPad/iPhone download manager with a small built-in browser. Downloads keep running with the screen off, because they are handed to iOS's background download system instead of running inside the app.

## Features

**Downloader**
- Paste a link to download. If the link is a web page instead of a file, it opens in the browser.
- Background downloads that continue when the screen is locked or the app is closed
- Pause, resume, cancel, and retry
- Progress in %, speed, and time left for each download
- Saved history, grouped by day, that can be cleared
- Notifications when a download finishes or fails, plus a badge count on the app icon
- Files are saved to the Files app under DL Manager
- Wi-Fi only option

**Browser**
- Logged-in downloads work: the page's cookies, User-Agent, and Referer are passed to the background downloader
- Links that open in a new tab are followed. Pop-ups that open without a tap are blocked.
- Address bar tools: select all on tap, clear, paste and go, copy link
- Floating mini panel that shows active downloads

**Design**
- Minimal black and white look with a red accent, in light and dark mode
- Grid backdrop, monospace text, colored tags, and a floating navigation bar
- Smooth animations and haptics

## How it works

1. The browser spots a download (a file response or an attachment header) and cancels the page's own download.
2. It passes the URL and the session details to a background `URLSession`.
3. iOS handles the transfer and wakes the app when it finishes.

Resume works when the server supports it. Otherwise the download restarts from the beginning.

## Build

There is no need for a Mac. GitHub Actions does the build:

1. Push to `main`, or run the **Build IPA** workflow by hand from the Actions tab.
2. The workflow draws the app icon, generates the Xcode project with XcodeGen, and builds an unsigned IPA.
3. Download `DLManager.ipa` from the latest **Release** (or from the run's Artifacts).
4. Sign it with your own certificate and install it.

The IPA in this repo is unsigned. Never upload a signed IPA, certificates, or passwords to a public repo.

## Project layout

| Path | What it does |
| --- | --- |
| `project.yml` | XcodeGen project settings |
| `make_icon.swift` | Draws the app icon during the build |
| `Sources/App.swift` | App entry and background download hook |
| `Sources/DownloadManager.swift` | Background downloads, pause/resume, history storage, notifications |
| `Sources/Browser.swift` | Web view, download handoff, address bar |
| `Sources/LinkProbe.swift` | Checks whether a pasted link is a file or a web page |
| `Sources/DownloadsView.swift` | Downloads screen |
| `Sources/HistoryView.swift` | History screen |
| `Sources/SettingsView.swift` | Settings screen |
| `Sources/ContentView.swift` | Root view and floating navigation |
| `Sources/Theme.swift` | Colors, fonts, and shared UI parts |
| `Sources/Models.swift` | Download record data |

## Known limits

- Downloads built by JavaScript inside a page (`blob:` links) can't be handed to the background downloader. They are saved only while the app stays open.
- Force-quitting the app from the app switcher cancels background downloads.
- Downloads that need a form POST may not work.
- iOS has no status bar progress like Android. The badge, notifications, and in-app panel are used instead.

## Requirements

iOS or iPadOS 16 or later.

## Note

This is a personal project, built for my own use. It is provided as is, with no support or warranty.
