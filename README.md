<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon.png" width="120" alt="Yomu icon">
</p>

<h1 align="center">Yomu</h1>

<p align="center">
  A native iPhone manga reader for <a href="https://github.com/Suwayomi/Suwayomi-Server">Suwayomi-Server</a>,<br>
  laid out like <a href="https://github.com/mihonapp/mihon">Mihon</a> and built in iOS 26's Liquid Glass.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-26%2B-black" alt="iOS 26+">
  <img src="https://img.shields.io/badge/SwiftUI-no%20dependencies-orange" alt="SwiftUI, no dependencies">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

## Why

Mihon can't be ported to iOS: its sources are Android packages loaded at runtime. Suwayomi-Server solves the hard half by running those same extensions on a machine you own and exposing the library over an API. Its web interface works, but it doesn't feel like an app on a phone.

Yomu is the other half: a SwiftUI client with Mihon's screens and reader, native navigation, and chapters you can keep on the phone.

```
iPhone (Yomu)  ──GraphQL──▶  Suwayomi-Server  ──extensions──▶  sources
   offline copy                your library
```

Yomu loads no extension code and ships with no sources. Everything it shows comes from the server you point it at.

## Features

**Library**
- Categories, four display modes (compact, comfortable, cover-only, list), adjustable columns
- Three-way filters (downloaded, unread, started, bookmarked, completed) and seven sort orders
- Unread and download badges, pull down to check for new chapters

**Updates and History**
- New chapters and reading history grouped by day, with resume and download from the row

**Browse**
- Sources with Popular, Latest and search, pinned sources, search across every source
- Install, update and remove extensions, manage extension repos

**Manga**
- Details, chapter list with filter and sort, read and bookmark marks, mark previous as read
- Add to library with categories

**Reader**
- Five modes: paged right to left, left to right, vertical, long strip, long strip with gaps
- Mode and rotation remembered per series
- Pinch and double-tap zoom, six tap-zone layouts with inversion
- Scale type, zoom start position, crop borders, side padding for strips
- Background colour, page number, keep screen on, fullscreen
- Custom brightness that goes below the system minimum, colour filter with blend modes, grayscale, invert
- Long press a page to save or share it
- Swipe in from the left edge to slide the reader away

**Offline**
- Download chapters to the phone and read them with no server
- The library, covers and chapter lists are kept on the phone too
- Pages read offline are recorded locally and sent to the server when it's reachable again
- Downloaded-only and incognito modes

**More**
- Download queue, category management, reading statistics

**Server**
- Works with basic auth; the login is kept in the Keychain
- Local network or any public address (a tunnel, a VPS, Tailscale)

## Requirements

- An iPhone on iOS 26 or later
- A Mac with Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A running [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) (developed against v2.4)

## Building

```sh
git clone https://github.com/kalki-kgp/yomu.git
cd yomu
brew install xcodegen
echo "DEVELOPMENT_TEAM = ABCDE12345" > Local.xcconfig   # your team ID
xcodegen generate
open Yomu.xcodeproj
```

Pick your phone as the run destination and press Run. `Local.xcconfig` is gitignored; you can also skip it and choose the team under Signing & Capabilities.

A free Apple ID is enough. The catch is that builds signed with one expire after 7 days, so you install again from Xcode each week. Install over the existing app rather than deleting it and nothing is lost (see below).

On first launch, enter the server's address, such as `192.168.1.3:4567` or `https://manga.example.com`. If the server asks for a login, the screen will ask for it.

## Where the phone keeps things

Downloaded chapters, the library copy and unsent progress live in the app's Application Support folder. iOS doesn't purge it the way it purges caches, and installing a new build over the old one leaves it alone. Deleting the app deletes it.

Downloaded chapters are left out of iCloud backup. Downloads run while the app is open.

## Not built yet

- Source filters in Browse
- Trackers (AniList, MyAnimeList and others)
- Migrating a series between sources
- Dual-page split and rotate, zoom in long strip
- Multi-select in lists (context menus stand in for it)

## Project layout

```
App/
  API/       GraphQL client, models, every server call
  Kit/       offline store, downloads, image cache, preferences, shared views
  Library/   Updates/   History/   Browse/   Manga/   More/
  Reader/    reader, zoom, reader settings
Typecheck/   typechecks the app against the macOS SDK without Xcode
project.yml  XcodeGen project definition
```

There are no third-party dependencies. `Typecheck/check.sh` typechecks everything except the two UIKit files, which is handy on a Mac with only the Command Line Tools.

## Credits

- [Mihon](https://github.com/mihonapp/mihon), for the design this follows
- [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), which does the real work

Yomu is not affiliated with either project. It hosts and provides no content; what you read through it depends on the server and extensions you set up yourself.

## License

[MIT](LICENSE)
