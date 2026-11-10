# Charms

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

**Latest release:** v<!-- version -->0.1.0<!-- /version --> · [Download](https://github.com/L-K-M/Charms/releases/latest)

Charms is a small Mac menu-bar utility for typing the characters your keyboard
does not have: arrows, symbols, punctuation and emoji. Press a shortcut where
you are typing, type a name, press Return, and keep typing.

What sets it apart is where it opens. The picker appears on the display that
holds your typing, right beside the text cursor, and never on top of the line
you are writing, wherever the mouse happens to be.

```text
┌──────────────────────────────────────────┐
│ Search arrows, symbols, emoji…       esc │
├──────────────────────────────────────────┤
│ Favourites                               │
│  →    ✓    —    ∞    👍    😊    ❤️    🎉  │
│ Recent                                   │
│  ←    °    ≠    •    ✨    😂    ⌘    ↗   │
├──────────────────────────────────────────┤
│ Rightwards arrow  U+2192  ↵ Insert · ⌘↵ Copy │
└──────────────────────────────────────────┘
```

## Using it

| Key | What it does |
| --- | --- |
| `⌃P` (configurable) | Open the picker; press again to close it. |
| Typing | Search by name, keyword or alias: `arrow`, `check`, `infinity`, `cmd`, `->`, `nbsp`. A pasted character or `U+2192` finds it exactly. |
| `→` at the end of the search, `↓`, `Tab` | Move into the results. Arrow keys then move between cells; `↑` from the first row returns to the search. |
| `↵` | Insert the selected character where you were typing. The first one is selected as soon as the picker opens: your first favourite, or the best match once you search. |
| `⌘↵` | Copy it instead. |
| `⌘D` | Add the selected character to your favourites, or remove it. |
| `⌃↵` | Open the selected character's menu: skin tones, moving a favourite, Copy. |
| `esc` | Close without changing anything. |

Before you search, the picker shows your favourites and the characters you
used most recently.

### Typing `::` instead of the shortcut

Switch this on in Settings or in the menu-bar menu. Then type two colons at
the start of a field or after a space and keep going: `::arrow`, Return. The
colons and the name are replaced by the character. Escape closes the picker
and leaves the colons in your text; the name you typed into the picker is not
put there. It is off by default, and off in terminals, code editors,
password managers and applications that have their own `:shortcodes:`; the
list is yours to edit.

### Applications that hide their text fields

Some applications, those built with Electron among them, do not report where
you are typing unless an app requests it. Charms can then only copy. The
first time it meets such an application it asks whether to turn this on for
that application. If you agree, Charms requests it then and each time the
application starts; it takes about two seconds to take effect, and the
application may use a little more memory and processor time. Your answers
are listed under Settings, General, where Ask Again forgets them.

### Permission

Charms asks for one permission, Accessibility, and explains it before the
system prompt appears. (macOS 27 lists it as Device Control and Data Access.)
It uses it to find the field you are typing in and to send the chosen
character there. Without it Charms still opens, searches and copies; you paste
yourself. Nothing leaves your Mac: see [PRIVACY.md](PRIVACY.md).

## Installing

Download the `.dmg` from the [latest release](https://github.com/L-K-M/Charms/releases/latest),
drag Charms to Applications, and open it. Releases are not signed with a
Developer ID or notarized, so macOS refuses the first launch. On macOS 15 or
later, try to open Charms once, dismiss the warning, then click Open Anyway
under Privacy & Security in System Settings. On macOS 14, Control-click the
app, choose Open, then Open. Requires macOS 14 or later.

If another utility already uses Control-P, for example PopChar, quit it or
change one of the two shortcuts; whichever registered first wins.

To remove Charms, switch off "Open Charms at login" in its Settings, quit it,
delete the app, and optionally delete `~/Library/Application Support/Charms`
(favourites and recents) and the Accessibility entry in System Settings.

What has been tested, and on which systems, is recorded in
[docs/compatibility.md](docs/compatibility.md).

## Building

```sh
swift build                       # the package
swift test                        # CharmsCore and catalogue tests
swift run CharmsCatalogTool check # the committed catalogue matches the pinned data
./scripts/build-app.sh            # dist/Charms.app, ad-hoc signed (--debug, --universal)
./scripts/e2e.sh                  # drives the built app with real keys (see below)
```

`scripts/e2e.sh` starts the built app with a temporary home directory, opens
a test window (`CharmsHarness`), and checks insertion, Undo, Escape, copying,
placement, the typed `::` and the password-field rule with real key events. It
needs a terminal that has the Accessibility permission and uses the keyboard
for about a minute.

`scripts/build.sh` / `scripts/release.sh` wrap the shared `lkm-build` /
`lkm-release` engines; releases are cut by tagging. See [CICD.md](CICD.md).
Requires macOS 14+ and Xcode 26 (any Xcode 16+ builds the package; CI pins the
toolchain). There are no dependencies.

macOS ties the Accessibility grant to the app's signature, and an ad-hoc
signature is different in every build. For a build you rebuild often, sign
with a stable identity so the grant survives:

```sh
CODE_SIGN_IDENTITY="Apple Development" ./scripts/build-app.sh
```

The character catalogue (`Resources/catalog.txt`) is generated from the
Unicode and CLDR files pinned under `Data/` and from the curated aliases in
`Data/aliases.tsv`. After changing either, run
`swift run CharmsCatalogTool generate` and commit the result.

The design, and the measurements behind it, are in [PLAN.md](PLAN.md).

## License

Charms's own code is released under the [Unlicense](LICENSE). The character
names and keywords in the bundled catalogue come from the Unicode Character
Database, Unicode Emoji data and CLDR, which keep their own license; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
