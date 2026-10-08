# Yomu

An iPhone reader for a [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), laid out like [Mihon](https://github.com/mihonapp/mihon): Library, Updates, History, Browse and More, with the same manga screen and reader, in iOS 26's Liquid Glass.

The server runs the Mihon extensions and holds the library. Yomu only talks to its GraphQL API, so nothing here loads extension code.

## What works

- **Library**: categories, four display modes, filter and sort, pull down to check for new chapters.
- **Updates** and **History**, grouped by day.
- **Browse**: sources with Popular, Latest and search, a search across every source, and installing, updating and removing extensions.
- **Manga**: details, chapter list with filter and sort, read and bookmark marks, chapters saved to the phone.
- **Reader**: paged (right to left, left to right, vertical) and long strip (with or without gaps), pinch and double-tap zoom, tap zones, a mode remembered per series, progress saved to the server. Mihon's reader settings: background colour, rotation lock, scale type, crop borders, custom brightness, colour filter, grayscale and invert. Swipe in from the left edge to slide the reader away.
- **Offline**: saved chapters, the library and its covers stay on the phone, so they open with no server. Pages read that way are noted on the phone and sent to the server when it's back.

Servers behind basic auth are supported; the login is kept in the Keychain.

Not there yet: source filters and trackers.

## Where the phone keeps things

Saved chapters, the library copy and unsent progress live in the app's Application Support folder. iOS doesn't clear it, and installing a new build over the old one from Xcode leaves it alone. Deleting the app from the phone deletes it.

## Building

```sh
brew install xcodegen
xcodegen generate
open Yomu.xcodeproj
```

Put your signing team in a `Local.xcconfig` beside `project.yml` (`DEVELOPMENT_TEAM = ABCDE12345`) before generating, or pick it under Signing & Capabilities, then run on a phone or the simulator. On first launch, give it the server's address, such as `192.168.1.3:4567`.

`Typecheck/check.sh` typechecks everything but the two UIKit files against the macOS SDK, for a Mac that only has the Command Line Tools.

## License

MIT
