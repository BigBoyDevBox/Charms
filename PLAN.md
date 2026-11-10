# Charms implementation plan

Status: implemented through M4; first release (M5) not yet cut. What was verified, and what was not, is in `docs/compatibility.md`.

Updated: 10 November 2026 (implementation results recorded in §11, §15 and §16; final review: project setup aligned with the owner's other Mac apps, native spike results recorded, data releases pinned; see `docs/reviews/2026-11-10-final-plan-review.md`)

## 1. Product direction

Charms is a small native macOS utility for inserting arrows, unusual symbols, punctuation, and emoji into the app where the user is typing. Its defining behaviour is that the picker opens on the display containing the typing focus, preferably beside the text caret, even when the mouse is on another display.

The product name is **Charms**. The selected interface direction is the **first, compact grid design** from the initial concept: a search field, generous character cells, favourites, recents, and a quiet detail/footer area. The alternative named-results list is not the default design.

### Alternatives considered

- **macOS Character Viewer:** already searches and inserts symbols/emoji, with favourites and frequently used items. It has compact and expanded presentations. Charms must earn its place through the chosen compact workflow and demonstrably reliable focus/display placement, not claims that the built-in picker lacks these existing features. [Apple guide](https://support.apple.com/en-jo/guide/mac-help/mchlp1560).
- **PopChar:** the user's current character-entry tool, with font browsing, search, favourites, and recents. The user's reasons for considering Charms are its window placement in their setup and the complexity of the interface. Those are the design problems to validate; do not claim that PopChar lacks favourites or that its insertion always succeeds. PopChar 11.0 (9 November 2026) added a compact grid-only view and an Insert button that names the receiving app; its documentation says nothing about which display the window opens on, so placement remains the reason for Charms. [PopChar help](https://help.popchar.ergonis.com/hc/en-us/articles/23108918963100-How-to-start-with-PopChar).
- **Rocket:** a direct inspiration for typed invocation. It provides Slack-style emoji autocomplete, and its Pro edition also offers a search/browse window and custom shortcuts/symbols. Charms combines the requested optional `::` invocation with a shortcut and the same compact symbol/emoji grid. [Rocket](https://matthewpalmer.net/rocket/).
- **Named-results list:** considered in the initial concept; the user preferred the first compact grid. Keep names available in the footer and to assistive technology without treating relative scanning speed as an established fact.
- **Browser character pickers:** useful copy-based alternatives. Charms aims to remove that extra application/clipboard step where its validated direct-insertion transport works; browser tools do not universally require a mouse or cover the same repertoire.

These are design context, not measured competitive or compatibility results. Record actual supported app behaviour in §12.3 and `docs/compatibility.md`.

At the planning baseline the repository contained the license but no application implementation. The native spike ran on 10 November 2026 (macOS 27.0.1, Apple Silicon, Swiss German keyboard layout). Its results are written into the sections they settle and summarized in §15; they are measurements from that one machine, not claims about every Mac. `docs/compatibility.md` lists what was verified and what was not.

### Success criteria

- Press the configured shortcut, type a familiar name, select a character, and continue typing without moving the mouse.
- Opening the picker never chooses the mouse display over a usable caret or focused-window display.
- Escape restores the original typing context without modifying text or the clipboard.
- Enter inserts the exact selected Unicode string, including complete emoji sequences, into the intended input field.
- A stale or uncertain target produces a clear copy-only outcome instead of inserting somewhere else.
- The default interface remains useful without choosing a font, Unicode block, output format, or category.
- Searching, favourites, and recents work offline, without an account.
- An optional typed `::` trigger opens the same picker, alongside the global shortcut, without leaving the trigger behind after insertion.
- VoiceOver and keyboard-only users can search, select, favourite, insert, copy, and dismiss.
- The app requests only the accessibility access it needs; browse/copy remains usable when that access is missing or revoked.

## 2. Scope and initial platform choices

| Area | Initial decision |
| --- | --- |
| Platform | macOS 14 or later, the deployment target of the owner's other Mac apps. Developed and verified on macOS 27; behaviour on macOS 14 to 26 stays unverified until it is tested there. |
| Hardware | A universal build (arm64 and x86_64), which the shared build scripts produce for every app. Only Apple Silicon is verified. The Intel slice is built and checked for presence in CI but has not run on Intel hardware; the release notes and `docs/compatibility.md` say so instead of implying support. Apple has said macOS 26 Tahoe is the last release for Intel Macs, so that slice can only ever serve macOS 14–26. |
| Language and UI | Swift, AppKit for application/window integration, SwiftUI for the picker and settings where it behaves reliably. |
| Application style | Menu-bar accessory app (`Info.plist` `LSUIElement`), with no persistent Dock icon or ordinary document window. Settings/About use the accessory lifecycle; only one process may own the hot key and optional observer. |
| Shortcut | Offer the user's preferred Control-P (`⌃P`), configurable and subject to successful registration. A shortcut is a key position; its label follows the active keyboard layout. Explain that registration shadows existing app bindings, including previous-line/history commands; an optional per-app pass-through list can release it (§5). |
| Typed trigger | Optional `::` recognition, enabled explicitly. Its observer runs under the Accessibility access that insertion already needs (§7.5); the shortcut remains available independently. |
| Distribution | Direct distribution through GitHub releases built by the shared release workflow: a universal app as zip and dmg, ad-hoc signed and not notarized, like the owner's other apps. Local builds are signed with the machine's Apple Development identity so permission grants survive rebuilds. Developer ID signing and notarization are deferred until an account is supplied (§14). |
| Runtime dependencies | Prefer Apple frameworks and a bundled local catalogue; introduce external packages only for a concrete unmet need. |
| Interface language | English interface and search annotations initially; use localizable strings and keep the data format ready for additional locales. |
| Storage | Local settings and versioned local files; no server or synchronization service. |
| Project setup | The same as the owner's other Mac apps: a Swift package without an Xcode project, a pure `CharmsCore` library under test, shared build/release scripts, and the shared CI, release, and review workflows (§5, §14). |

### Included in the first usable release

- Global shortcut, menu-bar invocation, and optional typed `::` invocation.
- Focus-aware placement with explicit fallbacks.
- Search for ordinary symbols and emoji using names, aliases, literal characters, and code points.
- Keyboard and mouse selection, direct insertion, and an explicit copy action.
- Favourites, recents, and emoji variants supported by the bundled catalogue.
- Accessibility onboarding, optional launch at login, and a small settings window.
- Defined compatibility behaviour for native apps, browser fields, rich web editors, and Electron apps.

### Deferred

- Font inspection, font comparison, font-specific private-use glyph collections, and typographic alternate selection.
- Drawing recognition, AI search, GIFs, stickers, snippets, and general-purpose text expansion.
- Arbitrary trigger languages and automatic conversion of ordinary words; v1 recognizes only the optional `::` marker.
- Cloud accounts, cross-device synchronization, usage analytics, and remote search.
- HTML/CSS/source-code output formats, a full Unicode inspector, and custom themes.
- Mac App Store distribution and an automatic updater; evaluate these after direct distribution works reliably.

## 3. The primary user journey

1. The user places the caret in a document, message, or other editable field.
2. The user presses `⌃P`, or their configured replacement.
3. Charms captures the original target and its geometry **before** presenting its own UI.
4. A compact picker opens beside the caret, or at the best available location on the focused window's display.
5. The search field has keyboard focus. With an empty query, favourites and recent characters are visible.
6. The user types a query such as `arrow`, `check`, `infinity`, `cmd`, `happy`, `->`, or `U+2192`.
7. Arrow keys select a result. The footer shows its understandable name and code point or sequence.
8. Enter closes the picker and dispatches one insertion to the revalidated original target.
9. Typing continues in that field. Move the selected item to the front of recents after a committed dispatch or an explicit Copy, without claiming unverified delivery.

Escape, clicking outside the panel, or pressing the shortcut again cancels the picker. Cancellation does not modify the document, recents, or clipboard.

### Alternate journey: type `::`

1. The user enables the typed-trigger option and grants the access it needs.
2. In an eligible text field, the user types `::` at the start of a field or after whitespace. Opening punctuation is not an initial boundary, avoiding cases such as `arr[::2]`; expand this grammar only with evidence from use.
3. The two colons enter the source normally. After confirming committed text in the original field, Charms opens the same search-focused picker beside them.
4. The user can continue typing without an intentional pause. For `::arrow`, any query prefix that reaches the source during focus transfer is tracked and becomes the beginning of the picker query; later query characters go directly into the picker.
5. On Enter, Charms validates the original field and exact tracked range, returns keyboard focus, and replaces the marker plus any verified source-side query prefix with the chosen string once.
6. On Escape, the source is unchanged: the literal `::` and any prefix typed there before the picker took focus remain. Query text entered inside the picker is not written back to the source.

The shortcut path inserts at the existing selection. The typed-trigger path replaces a tracked activation range. Keep those operations distinct even though they share the same picker. A listening observer cannot hold keys back, so the handoff in §7.6 reconciles what reached the source; the spike measured that method at key gaps down to 2 ms.

## 4. Interface specification

### 4.1 Compact picker

Use the first design as the visual contract:

```text
┌──────────────────────────────────────────┐
│ Search arrows, symbols, emoji…       esc  │
├──────────────────────────────────────────┤
│ Favourites                               │
│  →    ✓    —    ∞    👍    😊    ❤️    🎉  │
│                                          │
│ Recent                                   │
│  ←    °    ≠    •    ✨    😂    ⌘    ↗   │
├──────────────────────────────────────────┤
│ Right arrow · U+2192  ↵ Insert · ⌘↵ Copy │
└──────────────────────────────────────────┘
```

The diagram is structural; native font metrics determine final spacing.

- Start near 400 points wide with approximately 40-44 point character cells and eight columns at the normal size.
- Surface the Copy action in the footer (for example `⌘↵ Copy`) so the explicit copy path is discoverable without reading the keyboard table.
- Let accessibility text sizing, available display area, and actual font metrics determine the final dimensions. Reflow rather than clipping.
- Empty search shows a compact favourites section and up to two rows of recents. Seed a small useful favourites set only on first launch.
- A non-empty query replaces those sections with a single result grid. Keep the selected name and full Unicode sequence in the footer.
- Use a native scroll view for longer results, keep the selected cell visible, and avoid resizing the panel on every keystroke.
- Start with the first available item selected whenever items are shown: the first favourite (or recent) with an empty query, the first match otherwise. Enter therefore always acts on a visible choice, also right after the picker opens. Clearing search selects the first item again. Enter does nothing only when there is nothing to select. (The first version left the empty-query view unselected; that made Enter a dead key until an arrow key or Tab was pressed.)
- Distinguish selection from hover. A stationary mouse must not steal selection after a keyboard search or rerender.
- A primary click on a result cell activates that item exactly once, equivalent to Enter. In insertion mode it inserts; in browse/copy mode it copies. Chrome, section headers, empty space, and context-menu clicks never insert. Favourite/variant actions remain separate (`⌘D` or context menu); record accidental-activation checks in M3.
- Use system appearance, readable contrast, restrained borders, and native focus indicators. Honour Reduce Motion, Increase Contrast, and Reduce Transparency. Evaluate native popover material with `NSVisualEffectView`; a translucent borderless implementation may use `isOpaque = false` and a clear backing only when its content provides readable coverage. If custom panel geometry changes require it, call `invalidateShadow()` and inspect the result; material/shadow choices are tested styling decisions, not prerequisites for focus correctness.
- Do not introduce permanent sidebars, font selectors, code-format controls, or category toolbars into this surface.
- An empty result state says that nothing matched and allows immediate query editing. Enter does nothing when no result is selected.

### 4.2 Keyboard behaviour

| Input | Behaviour |
| --- | --- |
| Configured global shortcut | Open the picker; if already open, cancel. Ignore key-repeat so holding the shortcut does not repeatedly toggle it. |
| Typing | Update the search query while preserving ordinary text editing and input-method composition. |
| Left / right | Edit the query normally while the search field is focused; move between cells while navigating the grid. |
| Down from search | Enter result navigation. With a result selected, which is the normal case, move down one row from it, staying put when there is only one row; with none, select the first available item. |
| Right with the caret at the end of the query | Enter result navigation and move to the next result. Right does nothing at the end of a text field, so no editing behaviour is lost. Together with Down this makes the arrow keys act on the results at once: the second result is one key away, not two. |
| Up from search | Nothing; the search field is the top of the picker. |
| Up / down in grid | Move by the visible column count; Up from the first row returns to search. Define and test partial final rows. |
| Partial final rows | Treat the short trailing row as a real case, not an edge case: Right and Down clamp to the last cell instead of wrapping, Left from a row's first cell moves to the previous row's last cell, and a one-cell final row still answers Up and Down. Confirm the choice during the M3 interaction review (§15). |
| Typing while navigating results | Return to the search field and edit the query using ordinary text input. |
| Enter | Activate the selected item once: Insert for a validated target, Copy in browse/copy mode. Do nothing with no selection. |
| Command-Enter | Copy the selected Unicode string, close the picker, and return focus without automatic insertion. Focus restoration follows the Escape rule (§7.1) and happens only when the original context is still current. |
| Command-C while the grid is focused | Copy the selected item; in the search field preserve ordinary selected-query copying. |
| Escape | Cancel and restore focus. |
| Command-D | Toggle the selected item's favourite state. |
| Control-Return | Open the selected result's context menu: favourite, Move Left/Right for a favourite, skin-tone variants, Copy. This keeps every secondary action reachable without the mouse. |
| Tab / Shift-Tab | Tab from search enters result navigation at the selected or first result; Tab or Shift-Tab while navigating returns to search. The footer is not a focus stop, and the user is never trapped in the grid. |

Confirm these rules with a native interaction test. Enter can activate the selected result directly from search. The search field keeps keyboard focus for the whole session, so typing always edits the query and input-method composition always has a real text client; "navigating the grid" is a mode of the picker that decides what the arrow keys do, not a second first responder. Let the native field editor/input context handle composition first; inspect the search field's actual `NSTextInputClient.hasMarkedText()` state before treating Return/arrows/Escape as picker commands. A false marked-text result alone is not proof that every IME candidate operation is finished. Preserve ordinary selection, paste, Undo, and VoiceOver commands.

### 4.3 Favourites, recents, and variants

- A context menu and Command-D add/remove favourites. Persist their explicit order; Move Left and Move Right in the cell's context menu are sufficient before drag reordering.
- Removing the final favourite leaves an intentionally empty section, rather than restoring the seed set. Settings' separate **Reset favourites** action restores that seed set; clearing every favourite is a different action, so the control must say which of the two it performs.
- Deduplicate recents by exact sequence and cap stored history, initially at 50 entries. Show only the compact leading portion in the empty-query grid.
- Provide Clear Recents in settings. Retain favourites separately.
- Store the exact selected emoji variant. The cell's context menu lists the skin-tone variants of an entry that defines them; do not manufacture combinations by appending arbitrary modifiers.
- A preferred skin tone can choose a valid default variant, while explicitly saved favourite variants remain unchanged. Apply it only where the emoji data defines that modifier variant for the entry, meaning the fully-qualified sequence is listed in the pinned `emoji-test.txt`, which covers the modifier and ZWJ sequences; otherwise show the base entry.
- Use the system's native text/emoji rendering. Preview combining marks against a dotted-circle guide when necessary; the guide must never become part of the inserted string.

### 4.4 Menu bar, settings, and onboarding

The menu-bar item must offer Open Charms, the `::` switch, Settings, About, and Quit. The switch is always listed, so the menu never changes shape; while insertion is not enabled it is disabled and says so. Capture the external app/field at the status-item engagement boundary, before transient menu/key-focus changes, whether or not Charms becomes active. Revalidate that same target when Open Charms is chosen; never substitute an indefinitely cached last app. If no trustworthy external target exists, use browse/copy mode. The visible-picker toggle rule below takes precedence over starting another capture.

Browse/copy mode is the same picker with no insertion-capable target: search, favourites, and recents remain available. The footer says Copy; Enter or primary-click copies the selected item, as do the explicit Copy shortcuts. No source focus is required to copy, and focus is restored only while its original context is still current. This is a supported mode, not an error state.

While the picker is visible, Open Charms from the menu bar follows the same toggle rule as the shortcut and cancels the session instead of opening a second one.

While the shortcut recorder captures a combination, suspend Charms' global registration or route its handler only to the recorder, and suppress picker invocation. Validate registration before storing a usable shortcut. Reserved or unregistrable combinations produce a recoverable explanation and retain the previous working binding; do not claim every system combination can be captured.

Keep settings to:

- Keyboard shortcut and an optional per-app shortcut pass-through list, separate from typed-trigger exclusions (§5).
- Enable typed `::` trigger, with an application exclusion list. The same stored switch appears in the menu-bar menu as the pause control; there is no second "paused" state to explain or to get out of step.
- Launch at login, off until the user opts in.
- Preferred emoji skin tone.
- Clear recents and reset favourites as separate explicit actions.
- A short list of applications that receive text through Paste instead of keyboard events (§7.3). It is empty by default: the spike found no application that needs it, but the Chromium- and Electron-based editors it exists for could not be tested on the development machine.
- A secondary Export Diagnostics action for user-initiated, local, content-free support data (§9).

On first launch, explain Accessibility access in plain language: Charms locates the typing field and returns characters there. Offer **Enable Insertion** and **Browse and Copy**. Request trust only in response to the enable action. Recheck capabilities on each invocation and when Settings/app activation changes (`NSApplication.didBecomeActiveNotification`); an accessory/nonactivating picker may never receive a normal app-activation transition when returning from System Settings. Explain recovery after revocation without continual text polling.

Enabling `::` is separate and opt-in. Explain local keyboard observation and the short-lived explicit trigger/query transition. Keep shortcut/menu-bar Browse and Copy available when it is off or unavailable. Turning it off, from Settings or the menu, removes the observer and clears transient recognition state.

Typed invocation requires trusted AX access, for its observer and for marker validation/replacement, and the capabilities required by the selected insertion backend. While insertion is not enabled the switch is disabled, Settings says "Enable Insertion to use the typed trigger" and offers that action; a user who started with Browse and Copy is never left at a dead end. Remove the observer if access is revoked. Should a supported system refuse key observation under Accessibility alone, request listening access with the public API at opt-in and say why; Input Monitoring alone is never sufficient. A field that later proves unsupported is left untouched and can use the explicit Copy path; this does not silently enable global observation in browse-only setup.

The design does not require Screen Recording, microphone, contacts, or Full Disk Access. Validate the permission model per transport in M1. For Quartz posting, use `CGPreflightPostEventAccess()` and, only after Enable Insertion, `CGRequestPostEventAccess()` as applicable; verify actual prompt/denial behaviour on supported systems. Treat AX inspection, keyboard listening, and event posting as capabilities, without depending on private TCC service identifiers or assuming that one successful check authorizes every backend.

## 5. Native architecture

Follow the setup of the owner's other Mac apps, so the shared scripts, workflows, and habits apply unchanged: a Swift package at the repository root (`swift-tools-version: 6.0`, Swift 5 language mode, `platforms: [.macOS(.v14)]`), no Xcode project, and no XCUITest target. `scripts/build-app.sh` assembles `dist/Charms.app` from `swift build`, the committed `Resources/Info.plist` (bundle identifier `ch.lkmc.Charms`), the generated icon, and the catalogue; `scripts/build.sh` and `scripts/release.sh` are thin entry points to the shared build and release engines.

All decisions that can be made without touching another application live in `CharmsCore`, which imports no AppKit and is covered by unit tests. The `Charms` executable holds only what needs the system: windows, the hot key, Accessibility calls, event posting.

```text
Package.swift
Sources/
  CharmsCore/           pure logic, no AppKit
    Catalog/            entries, the catalogue file format, variant relationships
    Search/             normalization, matching, deterministic ranking
    Placement/          coordinate conversion, caret estimate, display choice, panel position
    Session/            the session state table
    Trigger/            marker recognition, handoff reconciliation, eligibility
    Insertion/          backend choice, release gate, target check, clipboard guard
    HotKey/             the shortcut model and its labels
    Picker/             grid navigation, the content shown for a query
    Persistence/        favourites and recents store
    Settings/           the preferences document and default application lists
    Diagnostics/        the content-free event log
  Charms/               the app
    App/                lifecycle, status item, settings, onboarding, about
    HotKey/             registration, recorder, layout-aware key labels
    Triggers/           the optional :: observer
    Targeting/          focus capture, AX wrappers, target validation
    Picker/             NSPanel controller, SwiftUI views, keyboard handling
    Insertion/          Unicode-event and paste transports
  CharmsCatalogBuilder/ catalogue generation from the pinned data (development only)
  CharmsCatalogTool/    its command line: generate, check
  CharmsHarness/        a small text host and driver for end-to-end checks
Tests/
  CharmsCoreTests/
  CharmsCatalogBuilderTests/
Resources/              Info.plist, the generated catalogue and its manifest
Data/                   pinned Unicode and CLDR files, checksums, curated aliases
scripts/                build, release, icon, data fetch, end-to-end check
docs/                   compatibility results, review records
AGENTS.md  CLAUDE.md  CICD.md  CHANGELOG.md  README.md  PRIVACY.md  THIRD_PARTY_NOTICES.md
```

The generated catalogue is a committed, line-based text file, so a data update shows up as a reviewable diff, and it is copied into the app bundle by the build script rather than through a SwiftPM resource bundle.

### Responsibilities and boundaries

| Component | Responsibility |
| --- | --- |
| `HotKeyService` | Register one shortcut, handle conflicts and app changes, refresh layout-aware labels, and debounce invocation. The optional pass-through policy releases this registration in selected apps. |
| `TypedTriggerService` | Observe only while enabled/eligible, recognize a committed marker, reset on input-source changes, enforce exclusions, and emit a marker proof. Candidate translation never replaces source-text verification. |
| `TargetCaptureService` | Capture the originating process, focused element/window, selection range, and geometry; typed-marker validation permits only narrowly bounded source-text reads. |
| `PlacementEngine` | Pure placement decisions from captured rectangles, screen geometry, and panel size. |
| `PickerController` | Own one panel and one invocation session; coordinate show, cancel, and selection. |
| `CatalogStore` | Load an immutable, versioned catalogue and expose complete Unicode strings. |
| `SearchEngine` | Match and rank locally; return stable item identifiers with cancellable query results. |
| `InsertionCoordinator` | Validate the target, choose one backend, and perform at most one dispatch. |
| `PreferenceStore` | Persist user settings, favourites, and recents with schema migration. |

AppKit UI and lifecycle state belong on the main actor. Catalogue loading, indexing, and other pure work run away from the UI. Isolate potentially blocking cross-process AX calls behind bounded requests on a serial execution context; never move non-Sendable AX handles between arbitrary tasks. Give requests a generation/session identifier so late replies cannot reposition a new picker or insert into an expired target.

Use dependency injection at these boundaries to test geometry, search, session transitions, and insertion decisions without manipulating other apps.

Name the platform mechanisms explicitly so the spike does not re-derive them: hot-key registration through the Carbon Hot Key API (`RegisterEventHotKey`) behind `HotKeyService`; typed-trigger observation through `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` behind `TypedTriggerService`, which reports exactly the keys delivered to other applications and so provides the attribution §7.6 needs (a session event tap would also see the picker's own keys and would need Input Monitoring); focus/app-switch change detection through an accessibility observer (`AXObserver`, `kAXFocusedUIElementChangedNotification`) plus `NSWorkspace` frontmost-application notifications; and secure-input detection through `IsSecureEventInputEnabled()` before any source text is read or targeted. All of these were exercised against the macOS 27 SDK in the spike.

Start with public system hot-key registration behind `HotKeyService` rather than a global keyboard hook for shortcut-only use. Prototype direct distribution without App Sandbox; keep any future sandbox/App Store feasibility assessment separate from the initial implementation.

Shortcut pass-through is independent of typed-trigger exclusion. Keep the default shortcut policy global as requested; offer terminals/Emacs-style editors as suggested pass-through choices rather than silently disabling the user's shortcut there. When a selected app is frontmost, unregister Charms' hot key so the app receives its native binding; re-register on leaving it and handle registration failure. Test rapid app switches and first-key races instead of promising a notification is processed before every next keystroke.

Observe input-source changes with the supported Text Input Source notification (`kTISNotifySelectedKeyboardInputSourceChanged`) and, where appropriate, `NSTextInputContext.keyboardSelectionDidChangeNotification`. Refresh labels, invalidate layout caches, and reset pending trigger candidates. Prefer event character information plus committed-source verification. If `UCKeyTranslate` is needed, use translator-owned `deadKeyState`, reset it on source changes, and handle input methods without Unicode layout data. That API updates the caller's buffer, not another app's active dead-key state.

Use normal Launch Services open/reopen semantics. If explicit duplicate-process launches must also be supported, acquire atomic per-user ownership before registering global resources; enumerating `NSRunningApplication` is not an atomic guard. Route a second open request to the existing Settings UI without duplicate status items or event taps.

## 6. Focus capture and display placement

### 6.1 Capture before presentation

On each invocation, create a new session containing:

- Originating process and stable launch identity: the external app focused at invocation, or the app/field captured before status-item tracking for menu-bar invocation. Do not infer it from the picker's activation state or the PID alone.
- Opaque references to the focused editable AX element and focused window, when available.
- Selection range, caret/selection bounds, field bounds, and window bounds where supported.
- Display geometry at invocation and the selected placement source.
- Session identifier, permission state, and whether automatic insertion is allowed.
- Invocation source: shortcut, menu bar, or typed marker. A typed session additionally holds the activation range, bounded source-side query prefix, and expected caret position after them.

Keep this snapshot in memory only and discard it after the session ends. Shortcut/menu-bar invocation does not read selected text or document contents. Typed invocation may read only the marker, a bounded source-side query prefix during focus transfer, and a small boundary context. Neither path captures the window title or clipboard as part of ordinary invocation. Charms' own windows are never capture targets: when an invocation finds focus inside the settings window or another Charms surface, treat the session as having no trustworthy external target and open in browse/copy mode.

Try the focused element's selected range and bounds-for-range AX parameter first, and do not trust a zero-length caret rectangle by itself. Measured in TextEdit on macOS 27: the rectangle for a zero-length range is one line too high (the caret after a character at y 109 is reported at y 96, both 13 points tall), while rectangles for real characters are right. Other projects report the same for TextKit and that Chrome places the caret after a trailing newline on the previous line. A picker put "below" that rectangle covers the line being typed, which is the placement failure Charms exists to avoid.

So also request the bounds of the single character before and after the caret. These are geometry-only reads; no text is fetched. Take the caret's line from an adjacent character only when that character demonstrably meets the caret horizontally: the next character begins at the caret's X, or the previous one ends there. That test fails by itself across a wrap, a newline, or a direction change, which is exactly when an adjacent character is on another line. When no adjacent character confirms the line, keep the reported rectangle and additionally keep one line below it clear, so the picker never covers the real caret in either case. Do not infer a caret from one adjacent edge without the reported rectangle to compare with. Reject implausible rectangles (§6.3) and otherwise fall back to field/window geometry, including empty fields.

For a non-empty selection, use a reliable end-of-selection caret rectangle when supported, otherwise the selection/field bounds. Do not expand a failed geometry query into source-text reads or split a surrogate/grapheme to manufacture a caret.

Bound AX messaging time per call with `AXUIElementSetMessagingTimeout` and the overall capture deadline, initially near 100 ms so the warm-present budget remains reachable; a complete capture measured 7 to 10 ms in TextEdit. Do not assume an undocumented default timeout. If a call is slow, use already captured reliable geometry, and ignore replies after cancellation or session replacement. A hung source app must not freeze the picker.

### 6.2 Placement priority

1. **Usable caret/selection rectangle:** choose the display containing that rectangle and place adjacent to it.
2. **Focused editable field rectangle:** choose its display, using greatest intersection if it spans screens, and anchor near the field.
3. **Focused window rectangle:** choose the display with the greatest visible overlap and place within the window's usable intersection.
4. **Mouse display:** use only if no usable source geometry can be obtained. Determine it from the current pointer location (for example `NSEvent.mouseLocation`) compared against the connected screen frames, not from `NSScreen.main` or a remembered panel position.
5. **Primary available display:** final fallback if the mouse is not within a current screen. Use the system's primary display (for example `CGMainDisplayID()`) rather than an arbitrary entry in `NSScreen.screens`.

Select the screen from captured geometry rather than consulting the picker's own `NSScreen.main` after it has become key. Do not remember a last-used global panel position that overrides the current source.

When Accessibility is unavailable or yields no usable focused window, try a placement-only `CGWindowListCopyWindowInfo` fallback using the captured app's on-screen normal-layer window bounds, owner, and ordering. Metadata availability must be tested without Screen Recording; add no permission solely for this fallback and do not consume/retain window titles. If a suitable window cannot be identified, continue to the documented mouse/primary-display fallback. Window-list geometry never establishes an insertion-capable field.

### 6.3 Coordinate and bounds rules

- Centralize one tested global coordinate conversion: AX uses the menu-bar/primary display's top-left origin, X increasing right and Y downward; AppKit uses the primary display's bottom-left origin, X increasing right and Y upward. X is unchanged; only Y is reflected.
- Anchor on the primary display's full `frame`, not `visibleFrame`. Under those desktop-origin assumptions, a rectangle maps to `x = axRect.minX`, `y = primaryFrame.maxY - axRect.maxY`, preserving width/height. Apply `visibleFrame` only afterwards to clamp placement; otherwise menu-bar/Dock exclusions are counted twice.
- Verify round trips with displays above, below, left, and right of primary, including negative coordinates. The correctly anchored global Y transform remains valid in those layouts; do not flip around each destination screen's height or assume all origins are nonnegative.
- Use logical points for window layout. Do not apply a screen's backing scale twice.
- Accept a zero-width caret with a meaningful height, subject to the line confirmation in §6.1. Reject non-finite values, implausible geometry (a height outside roughly 4 to 300 points is a placeholder or a whole field, not a caret), stale offscreen rectangles, rectangles outside the focused window, and bounds unrelated to any connected screen.
- Prefer below the caret with a small gap, flip above if necessary, and clamp to the selected display's `visibleFrame` with an approximately 12-point margin. "Below" and "above" are measured from the region that must stay visible: the confirmed caret line, or the reported line plus its guard line.
- Account for the menu bar, Dock, notches, small displays, and panel size changes. Keep the picker visible and avoid covering the insertion line when geometry allows.
- Observe display changes with `NSApplication.didChangeScreenParametersNotification` or `CGDisplayRegisterReconfigurationCallback`, and Space changes separately with `NSWorkspace.activeSpaceDidChangeNotification`. On either, cancel unless the same session can be safely revalidated/repositioned. Display reconfiguration callbacks do not signal every Space change; never silently switch insertion targets.

### 6.4 Panel lifecycle

Use an `NSPanel` constructed with the nonactivating-panel style, able to become key for search without becoming an ordinary main application window. Capture the origin before ordering it on screen.

Measured on macOS 27 with TextEdit as the source: a borderless `.nonactivatingPanel` at `.floating` level, with collection behaviour `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.transient` and `hidesOnDeactivate = false`, became key about 10 ms after the hot key. The source stayed the frontmost application and no activation notification fired. After `orderOut`, the source's focused element was the captured one again within 3 ms, with no activation call. That is the starting configuration; full-screen and separate-Spaces behaviour still needs checking where the development machine allows it.

Start with ordinary/nonactivating `NSPanel` behaviour and `.floating` where appropriate, together with a tested full-screen/Spaces policy. Record the lowest sufficient level for ordering and keyboard focus. Evaluate status/pop-up levels only if ordinary levels demonstrably fail; screen-saver level is not a normal character-picker solution. Window level alone does not grant access to another full-screen Space.

Prove candidate collection behaviours, such as `.canJoinAllSpaces` with `.fullScreenAuxiliary`, on supported systems rather than treating them as a universal recipe. Do not combine mutually exclusive full-screen flags or rely on new options without availability checks. Test `hidesOnDeactivate = false` for the nonactivating panel and implement explicit session cancellation, so expected focus transitions do not hide it while genuine target changes still dismiss it. Never move the user to a different Space.

Cancel when the user genuinely changes the originating app/window, the panel loses keyboard focus to an outside click, the target exits, or the session becomes invalid. Distinguish expected panel-focus transitions from genuine user target changes so opening the picker does not immediately cancel itself.

Restore source keyboard focus only while the original process, window, and field are still current. Resigning the nonactivating panel restores the source naturally (measured above), so the shortcut and typed paths make no activation call. Use guarded `NSRunningApplication.activate(options:)`, AX window raise/focus, or selection restoration only where a path proves to need it, such as invocation from the menu bar. None of these is permission to reactivate an app the user deliberately left or to restore a stale selection.

## 7. Insertion and session correctness

### 7.1 State machine

Use one authoritative state table. Cancellation/timeouts before document/clipboard-content mutation or injected input dispatch can return to `idle`, or to visible copy-only browsing when that does not steal focus. Guarded reversible focus/selection preparation is not that commit boundary. After the first document/clipboard-content mutation or injected input dispatch, retain a dispatched/uncertain result; never relabel it as a cancellation that changed nothing.

| State | Work | Normal exits |
| --- | --- | --- |
| `idle` | No session; only minimal enabled trigger-candidate state may exist. | `capturing`. |
| `capturing` | Capture source and geometry under a deadline. | `browsing`, typed `handoff`, or cancellation. |
| `handoff` | Typed query input is accepted while source-prefix/order proof settles; commits remain pending. | `browsing`, visible copy-only browsing, or cancellation. |
| `browsing` | Search, result selection, and favourites; insertion-capable or copy-only. | `awaitingRelease` with a frozen Insert/Copy action, or cancellation. |
| `awaitingRelease` | Wait for invocation/selection modifiers and the activating key/button to be released. | `validating` for Insert; `copying` for Copy; on deadline return to browsing without a pending commit. |
| `validating` | Perform guarded focus handoff, exact activation selection where needed, and final source checks. | `dispatching`; visible copy-only browsing if safe, otherwise `idle` on failure. |
| `copying` | One explicit clipboard write; restore focus only if still appropriate. | `idle` with `copied`. |
| `dispatching` | One preselected transport. Its first document-content mutation, injected input dispatch, or clipboard-content write is the commit boundary; reversible focus/selection preparation is excluded. | `idle` with `dispatched`, including uncertainty after partial/unknown delivery; `failedBeforeDispatch` only if no content mutation, input dispatch, or clipboard-content write occurred; guarded selection preparation may have been restored. |

A paste-backend clipboard restoration (7.4) can outlive its session. A new session may start while one is pending, but must not start another clipboard transaction until it resolves, and a restoration never acts on behalf of a later session.

- Only one session and one insertion dispatch can be active.
- End each completed session with one honest outcome: `cancelled`, `copied`, `dispatched`, or `failedBeforeDispatch`. A posted Quartz event has no delivery acknowledgement; a later failure cannot prove that no text was sent.
- A shortcut invocation supersedes a pending typed candidate, clears it, preserves source text, and starts a fresh shortcut session. A second shortcut during `capturing` cancels that in-flight capture; a visible-picker shortcut cancels normally. Pending/late typed work cannot open a second panel or inherit a marker-removal range.
- Repeated Enter/click events cannot dispatch twice.
- The release wait before dispatch (7.3) also covers the key or mouse button that committed the choice. If focus returned while Return was still down, the source could receive its key-up or auto-repeated Return events and insert line breaks.
- Before dispatch, cancellation invalidates pending AX/search requests, scheduled actions, and focus-restoration callbacks. After document/clipboard-content mutation or injected input dispatch, do not retry, replay, or compensate by deleting text; record `dispatched`/uncertainty and prevent unsent actions from targeting a changed field.
- A late completion cannot revive a panel, modify recents for another session, or send text.
- Normal cancellation restores focus only if the original context is still current. It must not reactivate an app the user deliberately left.

### 7.2 Revalidate immediately before dispatch

Check permission, process identity/liveness, original window/element validity, and the source's current focus. Where supported, verify the selection range has not changed since capture. The picker being key is an expected exception, not permission to target any newly frontmost app.

Treat secure/password fields and active secure-input conditions conservatively. Check documented role/subrole or supported confidentiality metadata and `IsSecureEventInputEnabled()` before reading source text; the global secure-input flag supplements field classification rather than replacing it. Do not inspect contents to classify security. Such targets, Charms' own UI, and insufficiently revalidated fields use browse/copy mode without automatic insertion.

If the user switches to a different field/window while the picker is open, cancel or require reinvocation. Never silently retarget. A terminated app, recycled process identifier, replaced web element, or closed document must invalidate the snapshot. Process identifiers are reused, so compare a stable identity, such as the captured `NSRunningApplication` with its launch date, or the process audit token, rather than the number alone.

### 7.3 Choose a transport before sending text

Freeze the action, selected entry, query generation, and complete output. Wait for invocation/selection modifiers and the activating key or mouse button to be released, initially for up to one second. Query current key state (for example `CGEventSource.keyState(.combinedSessionState, key:)`) in addition to local key-up tracking; combined-session state is not exclusively hardware provenance. Never synthesize releases for held physical keys. If the deadline expires, discard the pending commit, keep the picker browsing while its context remains valid, and require a fresh activation. Releasing keys later must not dispatch automatically.

Then dismiss/resign the panel, establish that the same source app and field are effective receivers, and revalidate immediately before dispatch. Post with PID-addressed Quartz events (`event.postToPid(pid)`). PID targeting still does not identify the correct field. Do not silently fall back to global posting. If the selected backend's public capability preflight fails, offer explicit Copy without attempting a write.

The spike compared the transports with the same complete-string fixtures. The decision:

1. **Unicode keyboard events are the default.** Send the complete UTF-16 output as one key-down and one key-up carrying the string, with cleared flags and virtual key 0. Measured in TextEdit on macOS 27, through `postToPid` and through the HID tap alike: every fixture arrived exactly (arrow, non-BMP emoji, skin tone, ZWJ sequence, flag, keycap, variation-selector emoji, tag-sequence flag); strings of 21, 40, and 64 UTF-16 units arrived whole, so the 20-unit limit other projects work around did not appear; a selection was replaced; and one Undo removed exactly the insertion. No delay was needed between `orderOut` and posting. No catalogue entry comes near that length, so one event carries any of them; longer text is split between characters only, never inside a surrogate pair, a joined sequence, or a base with its marks. The posting process must outlive delivery: events from a process that exits immediately were dropped, which matters to test drivers, not to the app.
2. **Plain-text paste is an explicit per-app backend**, chosen ahead of time from the user's list (§4.4), never a retry. Send Paste through the effective Command-modified layout: find the key that produces `v` with Command held under the current input source, which also covers Dvorak-QWERTY Command layouts. A fixed ANSI V code is wrong: on the development machine's Swiss German layout the positions ANSI calls Y and Z are swapped, and a posted Command with position 6 did not undo.

Apple documents that some frameworks ignore an event's supplied Unicode string, so successful event dispatch is not proof of insertion, and the result of a session is `dispatched`, not "inserted". The acceptance criterion remains that one ordinary Undo restores the pre-insertion state in one step. If a transport cannot preserve a supported sequence or meet the Undo criterion in an application, that application belongs on the paste list or uses Copy, without dispatch-then-retry.

Do not automatically paste after an unconfirmed Unicode dispatch: the original event may have succeeded and a retry could duplicate the character. Choose a validated backend ahead of time, using an explicit per-app override only when needed. Unsupported apps retain the Copy action.

Do not set a text field's complete AX value to insert one character; that risks replacing unrelated content, losing formatting, and bypassing normal editing/Undo behaviour.

3. **AX selected-text replacement is not used.** Setting `kAXSelectedTextAttribute` can bypass script-controlled input events, may differ in Undo, and may report success without an effect; with keyboard events working there is no case that needs it. Do not add routine document read-back solely to claim delivery; any production verification needing source content requires an explicit, bounded privacy-policy revision.

Use distinct internal results such as `cancelled`, `copied`, `dispatched`, and `failedBeforeDispatch`. Do not report a verified insertion merely because an event was posted. Update recents after a committed dispatch or explicit copy, never after hovering or cancellation.

### 7.4 Clipboard policy

Explicit Copy intentionally replaces the clipboard. The normal Unicode-event backend does not touch it.

For the optional paste backend:

- Capture restorable clipboard representations in memory immediately before taking ownership. Preserve multiple items/types where safely supported, rather than saving only a string.
- Snapshotting is a programmatic pasteboard read and can encounter OS privacy controls, prompts, or denial. Where `NSPasteboard.accessBehavior` exists (macOS 15.4 and later), snapshot only when it reports that reading is always allowed; when it would ask or deny, skip the snapshot rather than prompt on every insertion, leave the chosen character on the clipboard, and say so next to the paste list. Never promise preservation that cannot be delivered.
- If contents cannot be safely snapshotted/restored, do not promise preservation; use an explicit copy/paste choice instead of silently discarding data.
- Write only the selected plain-text Unicode string and remember the resulting pasteboard `changeCount`.
- Restore previous contents only while the pasteboard `changeCount` still equals the value recorded immediately after this transaction's write, and only once per transaction; any later count means a newer copy exists. Never overwrite a subsequent user copy.
- A fixed delay is not a universal paste-completion acknowledgement. Establish app-specific supported behaviour in the spike; if consumption cannot be established reliably, leave this backend explicit and describe restoration as best effort.
- Consider the advisory NSPasteboard.org transient/auto-generated type conventions for temporary writes, and test with a clipboard-history tool. Cooperating managers may honour them; they do not guarantee that clipboard history skips the write or restoration.
- Do not chain a new clipboard transaction while restoration is unresolved. Never restore an old snapshot after relaunch or a later session.
- Do not write clipboard snapshots to disk or logs.

The release gate is predictable behaviour with a documented compatibility method, not a claim of perfectly invisible clipboard use in every application.

### 7.5 Optional typed-trigger recognition

Treat typed invocation as a separate input adapter, not a second picker or an unrestricted text expander.

- Install the observer, an `NSEvent` global key-down monitor, only while the user has opted in and the prerequisites in §4.4 hold. Apple documents that key events may be monitored when the process is trusted for accessibility, so no further permission is requested. Drop it and clear transient state when the switch is turned off or a required capability is lost. Keep event callbacks fast; never make blocking AX calls in them.
- Recognize the produced colon characters using the active input context, not hard-coded U.S. key positions. Confirm actual committed `::` text and any exactly tracked transition prefix in the source before enabling insertion.
- The event notification may precede the source app updating its AX selection. Use a bounded asynchronous reconciliation step; if the marker cannot be confirmed, leave the source untouched and do not open automatically.
- Before a trigger candidate, keep only minimal recognition state, such as a first-colon candidate, boundary state, source identity, and timestamp. After `::`, a bounded transient query-prefix buffer is allowed only for the handoff below. Do not buffer unrelated typing or log either form of state.
- Reset on app/focus/caret/input-source changes, mouse-down navigation (including movement within one field), nonmatching candidate-editing keys such as Command-V, and an initial one-second inter-colon timeout. Pause/cancel before dispatch on sleep (`NSWorkspace.willSleepNotification`), inactive login session (`NSWorkspace.sessionDidResignActiveNotification`), verified screen lock, secure input, permission loss, or interruption of the observer. The public session notification is not proof that every screen-lock transition is covered: establish a supported lock-detection strategy in the spike and do not present an undocumented distributed-notification string as a guaranteed API. Never dispatch while the user session is unverified/inactive.
- Suspend new trigger recognition through the entire active invocation, including capture, transition, visible browsing, validation, and insertion handoff, so query text cannot trigger a second session.
- Do not infer a typed marker from a paste, dictation, or an unproven synthetic/composed input path. The public cross-app AX contract does not provide a universal marked-text query, so recognition is suspended whenever the selected input source is an input method rather than a plain keyboard layout; there, key presses do not say what text was committed. Shortcut use remains available.
- Initially require start-of-field or preceding whitespace, verified with minimal context, so `std::`, `arr[::2]`, and `[::1]` do not meet the grammar. An eligible literal starting with `::` remains inherently ambiguous: the observer cannot know whether future characters will form IPv6, CSS, or a query. Do not promise future-text classification; preserve numeric/code-point queries such as `::2192` and `::1F44D`.
- Ship a conservative, editable exclusion list for built-in shortcode apps, code editors/terminals, password managers, and remote/virtualized input. Record bundle IDs in data; an entry ending in `.*` covers a vendor's whole family. Exclude browser address/search chrome only where a tested per-browser AX capability distinguishes it from ordinary page inputs; role/subrole is not a universal discriminator. Otherwise document the limitation and offer a browser-wide exclusion. Do not inspect URLs/page contents just to classify the marker.
- Start with application-level exclusions. Per-website exclusions can follow later; do not inspect browsing URLs or page content merely to detect the marker.
- Turning the switch off must stop observation promptly. Reinstall an interrupted observer only while the option is still enabled and permissions/eligibility remain valid.
- Event source fields such as `kCGEventSourceStateID`/`kCGEventSourceUnixProcessID` are evidence, not authentication of hardware origin or a receiving-field identifier. Charms' own insertions are posted to one process and were not seen by the global monitor in the spike; still verify committed source text and local picker input separately. Do not claim that an observer alone can prove all provenance or delivery.
- Once eligible `::` is recognized it opens the picker, including where literal text could share that prefix. Exclusions, the off switch, and the narrow boundary reduce accidental activation. Do not close and automatically replay query text merely because it starts with whitespace, a colon, or a digit: that would alter cancellation semantics, block valid queries, and require a separate validated recovery transaction. Keep Escape non-writing as specified in section 3; test the usability cost of this choice explicitly.

### 7.6 Replace the marker without guessing

For typed invocation, derive and retain the marker's AX range using the source's range units, normally UTF-16. Text before it may contain multi-scalar emoji; Swift character counts must not be used as AX offsets.

**Fast-typing handoff:** a listening observer cannot stop letters from reaching the source while asynchronous AX work and panel presentation occur. Implement an explicit transition state, using the method the spike measured:

- **Attribution by delivery channel.** A global monitor reports a key only when it was delivered to another application; a key delivered to the picker arrives through the picker's own event stream instead. Each key therefore appears in exactly one of the two, in order. Measured with `::arrow` typed at 2 ms gaps: the source received `::arro`, the picker received `w`, and the two streams said exactly that. Keys reported by the global monitor after the marker form the source-side prefix; the picker's field holds the rest; the query is the prefix followed by the field's text.
- **Position by read-back, never by arithmetic.** The monitor fires before the source has applied the key, so the caret read at that moment does not yet include it. Measured at 15 ms gaps: a marker position computed from the caret at event time was off by one and would have removed a neighbouring space. So read the text before the caret back from the source (bounded to the marker, the prefix, and one boundary character) until it equals `::` plus the prefix, and take the range from that reading. Until it matches, the source is still catching up; if it never matches within the deadline, insertion is not offered.
- The picker opens only once `::` is confirmed at an allowed boundary. An observed key says which application received a key, not which field or what text resulted (autocorrection and input methods can change it), which is why the comparison is against the source's text and is exact, scalar for scalar.
- A deletion, arrow, Return, or shortcut that reaches the source after the marker makes its text unpredictable; whitespace after the marker means the colons were ordinary text. Either ends the handoff without touching the source.
- Freeze the exact replacement range as marker plus verified source-side prefix once handoff settles. Keep the prefix in the source until insertion is committed, so cancellation requires no destructive rollback.
- Bound transition duration and buffered input, initially targeting at most 250 ms and 64 UTF-16 units, with sequence-safe limits. Tune from measurements. Only this activation transition may collect a query prefix; there is no general keystroke history.
- Enable insertion only after source range and input order are proved. If Enter reaches the picker during handoff/search, retain one pending activation tied to its exact query/input generation. Resolve the selected entry for that frozen query after reconciliation, then apply the same release wait and final validation; never use a selection from a later query. Editing input or an unprovable order cancels the pending activation. Enter received by the source before the panel is key remains ordinary source typing: abort without deleting/replaying it. If proof times out, preserve the source and offer Copy or cancel.
- The spike passed this feasibility check for uninterrupted `::arrow` typing at normal and high speed in TextEdit. Where reconciliation proves unreliable in an application, the source is left untouched there and the application belongs on the exclusion list; do not quietly assume that users will pause after `::`.

This policy retains listen-only recognition. Suppressing/buffering arbitrary global input would need a separate design for lossless replay and cancellation and is not an implicit fallback.

On commit:

1. Verify the same process, field, window, expected selection, literal marker, and tracked source-side prefix still exist.
2. Ensure the source supports safely selecting the exact frozen activation range. Select only that marker/prefix; never send blind Backspaces.
3. Perform the panel-to-source focus handoff first, then select the range and read the selection back: some apps apply a selection only to a focused element, and in TextEdit setting `kAXSelectedTextRange` after `orderOut` worked. A selection that does not read back as requested stops the commit before dispatch.
4. Dispatch the chosen output once using the already selected insertion transport.
5. If selection preparation fails before dispatch, preserve the activation text and offer Copy. If preparation changed the selection but dispatch cannot start, restore the previous caret only if the source remains unchanged and current.

Escape and explicit Copy leave source activation text intact. Choosing a symbol replaces it; one normal Undo should restore that text in supported apps. After an uncertain dispatch, do not remove more text or retry another transport. In fields without sufficient AX range access, disable typed invocation and retain shortcut/browse/copy use.

## 8. Catalogue, Unicode, and search

### 8.1 Data sources and coverage

Build a bundled catalogue from pinned releases: Unicode 18.0.0 (the Unicode Character Database and Emoji 18.0's `emoji-test.txt`, which lists every recommended sequence, including modifier and ZWJ sequences, with its qualification) and CLDR 49 English annotations. The files and their checksums are committed under `Data/`, so generation needs no network. Load both base and derived CLDR annotation data; base annotations are not restricted to single-scalar characters. Map annotation keys to validated fully-qualified emoji identities using Unicode's presentation/qualification rules, rather than assuming all keys match raw output strings or all omit the same selector. Resolve every included recommended sequence to a name or an explicit manifest exclusion. Add reviewed familiar aliases such as `cmd`, `option`, `tick`, `check`, `arrow`, `nbsp`, `->`, and `not equal`. They carry more weight than first assumed: CLDR 49 annotates all emoji but only 367 other symbols, so symbols are found through their Unicode names and these aliases, and the order of an alias's targets decides what a bare `arrow` shows first.

- Include assigned graphic characters and useful whitespace/punctuation, plus complete recommended emoji sequences in their fully-qualified form. Never insert the minimally-qualified or unqualified forms that `emoji-test.txt` also lists. The recommended set includes emoji tag sequences, the subdivision flags such as 🏴󠁧󠁢󠁳󠁣󠁴󠁿 (U+1F3F4 followed by tag characters); preserve them like the other sequence types in 8.2.
- Keep large algorithmically named repertoires available through literal and explicit code-point lookup without eagerly materializing every long name/token on the heap. An initial compact range-based representation can omit those names from ordinary word-search indexing; document that search-coverage distinction and measured entry/byte counts in the manifest. Do not silently discard characters or add an owner-approval blocker before M2 can measure the catalogue.
- Exclude unassigned scalars, surrogate code points, noncharacters, private-use glyphs, and standalone control/format/emoji components from normal suggestions. Document the exact coverage in the generator manifest.
- Give whitespace and combining characters visible names and suitable previews so the user understands what they will insert.
- Correctly expand source ranges and algorithmic names; do not expose Unicode data placeholders as user-facing names.
- Pin data releases/checksums and retain per-emoji version metadata. The data is newer than any shipping system: macOS 27.0.1 renders Emoji 17, and the supported floor, macOS 14, renders 15.0 or 15.1. Decide support on the running system instead of from a hand-kept version table: lay each emoji out with CoreText once and accept it only if it takes the advance of a single emoji, in at most two glyphs, from a real font. An unsupported sequence falls apart into components that take the width of several emoji, and an unknown character lands in the last-resort font. Two simpler tests are wrong: asking a font whether it has glyphs for the code points passes every unsupported sequence, since its parts all exist, and requiring exactly one glyph rejects supported ones, since the system draws mixed-skin-tone couples as two overlaid glyphs (measured on macOS 27). Check the result against version evidence: on a given system, entries up to its emoji version pass and newer ones fail.
- Handle known unsupported/missing glyphs deliberately. Hide unsupported emoji variants by default where support is known; retain understandable labels and explicit copy behaviour for entries that cannot be previewed reliably.

The catalogue generator is a development/build tool. The released app performs no data downloads or remote lookups.

### 8.2 Data model

Each entry needs:

- Stable identifier derived from its exact scalar sequence.
- Exact output `String` and scalar values; never assume one character equals one scalar or one UTF-16 unit.
- Human-readable display/official names, aliases, category/group, and tokens from CLDR names/keywords, Unicode names, and curated aliases. Test examples such as `happy`, `rightwards arrow`, and `up right` against the pinned data instead of assuming identical vocabulary or coverage in each source.
- Kind/presentation metadata, variant-family relationships, and any known rendering-support metadata.
- Source-data version and provenance in the catalogue manifest.

Preserve exact variation selectors, ZWJ joins, modifiers, tag characters, keycaps, and flags in stored/output sequences. Store intended text/emoji forms only when defined by the pinned Unicode data; `Emoji_Presentation` alone does not justify appending VS15/VS16 to an arbitrary symbol. Keep validated text and emoji variants distinct. Normalize search keys only, retaining raw sequence/code-point lookup without inventing or stripping selectors from output.

### 8.3 Matching and ranking

Start with a lightweight in-memory index rather than a database or external search service:

1. Exact literal non-ASCII character/sequence or an explicit `U+`-prefixed code-point query. Plain ASCII words/digits stay eligible for name/alias interpretation; `x` may prefer a curated cross alias, while `U+0078` explicitly finds the letter.
2. Exact familiar alias, display-name, or CLDR keyword match.
3. Token-prefix matches.
4. All-token substring matches.
5. Bounded fuzzy matching for genuine spelling variation, if it improves the fixtures.

Favourites and recency break ties within a relevance tier; they must not push an unrelated frequent item above an exact query. Remaining ties fall back to the entry's rank (curated, common, symbol, script, rare) and then to catalogue order, so results never depend on hash order. Preserve punctuation aliases such as `->` and `!=` during tokenization. Apart from such aliases, split names and keywords on whitespace and hyphens, so `up right` matches `up-right arrow`; a token-prefix match means every query token is a prefix of some entry token. Match the literal and code-point tiers against the raw query, before case or accent folding. Code points are hexadecimal; accept `U+` in either case, and several code points separated by spaces or commas as one sequence.

Support case-insensitive and accent-insensitive search keys, multiple query words, literal pasted symbols, and `U+2192`/`2192` notation. Many numbers and hex-letter words are valid code points — `face` is U+FACE (a CJK compatibility ideograph), `cafe` a Hangul syllable, and `100` LATIN CAPITAL LETTER A WITH MACRON — so treat a bare hexadecimal query such as `2192` as an additional interpretation ranked below exact name and alias matches, never in tier one; `2764` and `1F44D` still find ❤ and 👍 when no name or alias matches. A `U+`-prefixed query always parses as code points and keeps its tier-one rank. Multi-code-point lookup must parse an entire sequence instead of accepting only its first scalar. Reject invalid scalars gracefully.

Cancel superseded searches and apply results only to the matching query/session generation. Do not replace the selection under the user's Enter key with a late result from an older query.

### 8.4 Generation and licensing

Keep source URLs, exact release versions, checksums, curated overrides, and generation commands in the repository. Generate deterministic output and validate duplicate IDs, invalid sequences, missing labels, variant relationships, and expected search fixtures.

Retain required Unicode/CLDR and any package notices in `THIRD_PARTY_NOTICES.md` and the app's acknowledgements. Preserve the repository's existing license; it does not replace third-party data licenses. Render through system fonts rather than bundling extracted Apple emoji artwork.

## 9. Local persistence and privacy

- Store simple preferences in `UserDefaults` as one small document that tolerates missing or unreadable fields: shortcut, typed-trigger switch and exclusions, paste and pass-through lists, and preferred skin tone. The typed-trigger switch is the pause control; being stored, it survives relaunch and is shown in settings and the menu, so observation is never resumed silently. Launch at login is read from the system's registration state rather than stored twice.
- Store favourites, their order, and recents in a schema-versioned Codable file under the app's Application Support directory.
- Write atomically and serialize updates. Preserve a recoverable previous file when migrating; do not silently erase user choices on decode failure.
- Migrate entries using stable IDs and exact sequences so catalogue updates do not lose favourites. Preserve unresolved favourites for future recovery rather than deleting them automatically.
- Do not persist search queries, typed-trigger observations or marker context, AX snapshots, selected document text, window titles, or clipboard contents.
- Keep runtime diagnostics limited to timings, error categories, transport choice, coarse placement/fallback reasons, and the bundle identifier of the application concerned. The log has no free-text field, so typed text and raw user content cannot enter it. Add an opt-in "Export Diagnostics" action in Settings that writes the same categories to a local file the user can attach to a bug report; never transmit them and never include text content.
- No telemetry or network access is needed for ordinary operation.
- With typed recognition disabled, no global keyboard observer is installed. With it enabled, observation is local and ephemeral, limited to marker recognition and the bounded explicit-query handoff; unrelated typing is never retained.
- Use the system login-item API (`SMAppService.mainApp`) when the user opts in; reflect actual registration state, including a disabled or approval-required login item (`SMAppService.status == .requiresApproval`). In the approval-required state, provide a direct affordance to open System Settings (`SMAppService.openSystemSettingsLoginItems()`) with clear recovery instructions.

## 10. Accessibility and interaction quality

- Expose every result's understandable name, selected state, and available actions to VoiceOver.
- Give the grid a coherent reading/navigation order and identify favourites and recents as groups.
- Announce the selected result and settled search result state without speaking every hover or transient search update.
- Keep favourite/variant actions available to keyboard users; do not hide essential actions behind hover alone.
- Honour system text size, contrast, reduced motion, dark/light appearance, and keyboard focus settings.
- Test composition and non-U.S. layouts, refreshing shortcut labels and caches when input sources change. Native event/committed-text handling remains authoritative; a static layout translation is not a general IME composition model.
- Verify real keyboard and VoiceOver focus on show/dismiss. Notify accessibility observers about changes to Charms' own actually focused search/result elements when needed (`NSAccessibility.post` with `focusedUIElementChanged`); a notification is not a command that moves assistive focus. Do not post it on a foreign captured `AXUIElement` to manufacture restoration. Restore source keyboard focus through the validated lifecycle and test the source app's resulting assistive focus, including cases where the user has switched away.

## 11. Delivery milestones

A ticked box means the item is implemented and covered by the automated tests, by `scripts/e2e.sh`, or by a hand check recorded in `docs/compatibility.md`; that document also lists what was not exercised. Implement in small reviewable commits. The native risk spike was the gate for the broader implementation; it ran on 10 November 2026, and its conclusions are recorded in §15 and in the sections they settle. The milestones below keep their order; the M1 and M1b items describe what the spike established and what the implementation must then show in the real app.

### M0 — Bootstrap the project

- [x] Create the Swift package with the `CharmsCore` library, the `Charms` executable, unit tests, and a tiny native text-input harness.
- [x] Set `Info.plist` `LSUIElement` and verify the accessory activation policy, including how Settings/About are presented and how the app returns to accessory state.
- [x] Document the deployment target (macOS 14), toolchain, bundle identifier (`ch.lkmc.Charms`), and development signing approach (§14).
- [x] Add the shared scripts and workflows: `scripts/build.sh`, `scripts/build-app.sh`, `scripts/release.sh`, CI, release, automated review, and the `AGENTS.md`/`CLAUDE.md`/`CICD.md`/`CHANGELOG.md` set.
- [x] Add README build/run instructions and a focused `.gitignore`; do not commit local IDE state or signing secrets.
- [x] Create a menu-bar accessory app with Settings and Quit, with single-instance enforcement.

**Exit:** a fresh checkout builds and launches; the app can be quit cleanly, and pure tests run without Accessibility permission.

### M1 — Prove focus, placement, and insertion

- [x] Register the default `⌃P` shortcut with a working recorder in Settings, and capture the original target before presentation.
- [x] Show a minimal nonactivating panel with a handful of fixed fixtures: `→`, `—`, `∞`, `😀`, `👍🏽`, `👩‍💻`, and `🇨🇭`.
- [x] Add the sequence types the P0 matrix requires to those fixtures: a keycap (`#️⃣`), a variation-selector emoji (`❤️`), and a tag-sequence flag (`🏴󠁧󠁢󠁳󠁣󠁴󠁿`).
- [x] Implement geometry conversion and the complete display fallback chain.
- [x] Implement cancellation, target validation, and one-dispatch session control.
- [x] Compare Unicode events and explicit plain-text paste with selection replacement and Undo.
- [x] Test two displays with the mouse on the other screen, a display at negative coordinates, and a full-screen Space (the second display was a virtual one).
- [ ] Test vertical display layouts, mixed scale factors, and "Displays have separate Spaces" switched on; none was available on the development machine.
- [x] Record actual app/OS/version/backend results in `docs/compatibility.md` and capture decisions in a short technical note.
- [x] Provide the minimal Copy fallback that these exit criteria depend on, before they are judged; the full Copy action and its settings arrive in M3.

**Exit:** the core flow works in a native text view and ordinary browser field on both displays. Known incompatible contexts have a predictable Copy path. No unexplained wrong-target insertion or duplicate dispatch remains. If these behaviours cannot be achieved, narrow the supported matrix explicitly before proceeding.

### M1b — Prove the typed `::` trigger (separate gate)

- [x] Spike committed `::` detection, uninterrupted fast `::arrow` handoff, exact activation-range selection/replacement, Escape preservation, layout/IME limits, and the additional permission path before promising universal typed-trigger support.

Verdict: implemented as §7.5 and §7.6 describe and checked in the built app at 6 ms key gaps, with the Accessibility permission alone. Not checked with a real input method: the observer is suspended while one is active, and that rule has unit tests only.

**Exit:** a recorded M1b verdict with an implemented attribution/reconciliation method, permissions, IME/layout limits, and fast-typing evidence. M1 can close independently. Both requested invocation methods remain v1 scope; failure requires an explicit revised design and new evidence before M4, not silent deferral of `::`. Do not claim an unsupported trigger or make the core scaffold wait for that experiment.

### M2 — Build the offline catalogue and search

- [x] Pin official datasets and retain notices.
- [x] Implement deterministic generation, validation, curated aliases, and seed favourites.
- [x] Add an immutable catalogue loader, exact-sequence IDs, and a local search index.
- [x] Add independently specified search/Unicode fixtures and measure full-catalogue performance.

**Exit:** catalogue generation is reproducible; representative symbols and composite emoji round-trip exactly; relevance fixtures pass offline.

### M3 — Implement the selected compact grid

- [x] Build search, favourites, recents, the result grid, footer, and empty states around the M1 panel controller.
- [x] Add keyboard navigation, click selection, Copy, favourites actions, and validated emoji variants.
- [ ] Match the first design's spacing and simplicity in light/dark appearance and at increased text size. (Built and reviewed in the dark appearance only.)
- [x] Validate search-field editing and dismissal/focus behaviour.
- [ ] Validate input-method composition in the search field and VoiceOver; both are implemented (marked-text guard, labels and traits) and neither was exercised.

**Exit:** everyday use is possible without the mouse; opening and dismissing the panel remains correct after repeated searches and selections.

### M4 — Make it a dependable daily utility

- [x] Add versioned persistence, recovery/migration, and optional launch at login.
- [x] Add Accessibility onboarding and browse/copy mode.
- [x] Implement opt-in `::` observation, permission flow, the off switch and exclusions, boundary checks, bounded fast-typing handoff, and activation replacement proven in M1b.
- [x] Add only the compatibility overrides demonstrated necessary by M1; document the clipboard policy in user-facing terms.
- [x] Handle permission revocation, app termination, display changes, sleep/wake, and stale AX elements.

**Exit:** favourites/settings survive relaunch; permission and compatibility failures are recoverable; every priority-zero scenario in §12.2 that does not depend on the M5 compatibility matrix passes, and each remaining P0 row carries a recorded, dated status in `docs/compatibility.md` rather than an assumption.

### M5 — Verify and package the first release

- [ ] Complete the real-app/display compatibility matrix and review unresolved limitations.
- [x] Measure performance using release builds and record the hardware/OS used.
- [ ] Produce the universal app and its zip and dmg through the tag-triggered release workflow, ad-hoc signed. Add Developer ID signing and notarization only once an account is supplied.
- [ ] Verify a downloaded build from a stable, non-translocated installation, normally `/Applications`, including the Gatekeeper step an un-notarized download needs, launch, permission onboarding, login-item registration/approval, duplicate open, and quitting.
- [ ] Publish build instructions, compatibility notes, release notes, and checksums with the release, together with the documentation §14 already requires: uninstalling and disabling launch at login, privacy behaviour, current compatibility, and how to recover insertion permission.

**Exit:** a fresh user can install, grant only needed access, invoke Charms, insert symbols/emoji in documented contexts, and remove or quit it normally.

## 12. Verification strategy

### 12.1 Automated tests

Focus automated tests on decisions with meaningful independent expected outcomes:

- Placement geometry: left/right/above/below primary display, mixed scale metadata, zero-width carets, spanning windows, usable-frame edges, and missing geometry. Include the Accessibility-to-AppKit round trip itself, anchored on the primary screen's full frame, with a display arranged above and left of the primary so negative global origins are covered.
- Session state: duplicate Enter, cancellation during capture/validation, late AX/search callbacks, app exit, changed target, and overlapping invocations.
- Focus handoff and modifiers: dispatch cannot occur while the picker is the receiver, while physical modifiers or the committing key remain held, or after the source field changes.
- Input method and layout changes: local marked text/candidate handling retains Return/arrows/Escape; uncertain target composition suppresses trigger accumulation; input-source switches update labels/caches and reset candidates.
- Typed-trigger state: committed two-colon recognition, allowed boundaries, timeouts, resets, exclusions, auto-repeat, observer shutdown, synthetic-event filtering, and no reentrancy from the picker.
- Activation replacement: correct UTF-16 ranges after emoji, fast source/panel query splits in every position, source edits before commit, failed selection preparation, Escape/Copy preserving source activation text, and no blind deletion or duplicate transport.
- Transport selection: choose a method before dispatch; no implicit second transport after an unconfirmed first dispatch.
- Clipboard coordination: newer user copy is never overwritten; failed snapshot does not destroy contents; later sessions cannot restore older data.
- Unicode round trips: BMP symbols, supplementary scalars, variation selectors, skin tones, ZWJ sequences, flags, keycaps, and combining marks. Include the round trip in both directions — exact string inserted, and one Undo restoring the previous state in a single step — since a per-scalar dispatch can round-trip the text yet fragment Undo.
- Search: independently chosen expected results for aliases, punctuation, numeric/hex-word collisions (`face`, `cafe`, `100`), complete code-point sequences, stable relevance, and cancellation of old queries.
- Persistence: first-run seeding, intentionally empty favourites, ordering, migration, unknown IDs, interrupted writes, and corrupt-file recovery.
- Catalogue and search coverage: tag-sequence flags round-trip exactly; keyword-only matches such as `happy`, official-name matches such as `rightwards arrow`, hyphenated names queried as `up right`, and single ASCII letters behave as specified; the example queries in section 3 return independently chosen top results.

Use the native harness (`CharmsHarness`: a window with known text fields that can report its contents, plus a driver that posts keys) for known AX fields and editing/Undo behaviour, and a script that runs the critical flows end to end against the built app. There is no XCUITest target. Hosted CI builds and exercises the pure tests; cross-app TCC, VoiceOver, lock, and real display/Space scenarios require an interactive macOS session on local hardware. A machine with one display can still cover the multi-display rows: a virtual display created with the system's private `CGVirtualDisplay` classes behaved as a real second screen at negative coordinates on macOS 27. That is development tooling only and never ships in the app. Do not require infrastructure merely to review documentation.

### 12.2 Manual acceptance matrix

| Priority | Scenario | Expected result |
| --- | --- | --- |
| P0 | Caret on display B; mouse on A | Picker appears beside the caret on B. |
| P0 | Caret unavailable; focused window on B; mouse on A | Picker uses B and a window/field fallback. |
| P0 | Open from the menu bar while another app's field is focused | The previously frontmost app's field is targeted; when no trustworthy external target exists, the picker opens in browse/copy mode. |
| P0 | Left/above-primary and mixed Retina/non-Retina layouts | Picker coordinates and size remain correct, entirely within the chosen usable frame. |
| P0 | Caret near each display edge, Dock, or menu bar | Picker flips/clamps without disappearing or covering the insertion line unnecessarily. |
| P0 | Source app in full screen with independent display Spaces, and again with Stage Manager on | Picker appears in the current context without a Space switch. |
| P0 | Escape or outside click | No document/clipboard change; typing resumes in the still-current source. |
| P0 | Selected text in the source | One insertion replaces the selected range; unrelated text and formatting remain intact. |
| P0 | Arrow, non-BMP emoji, skin tone, ZWJ, flag, and keycap fixtures | Exact complete strings are inserted, and one Undo restores the previous state in a single step in supported apps. |
| P0 | Double Enter, Enter plus click, or held shortcut | At most one insertion or toggle transition occurs. |
| P0 | Return or the activating mouse button remains held | No source line break/click leaks from focus handoff. Dispatch waits up to the release deadline; expiry returns to browsing with no pending insertion, and requires a fresh activation. |
| P0 | User changes app/window/field while picker is open | Session cancels or becomes copy-only; text is never sent to the new target. |
| P0 | Source quits, document closes, or AX element becomes stale | No insertion and no forced reactivation of an unrelated app. |
| P0 | Password/secure field or secure-input condition | Automatic insertion is unavailable and the picker opens in browse/copy mode; no source text is read. |
| P0 | Invocation with no trustworthy external target: menu bar with no focused field, or focus inside Charms' own UI | The picker opens in browse/copy mode; no insertion is attempted and Copy works. |
| P0 | Accessibility missing or revoked | Browse/Copy remains usable and enabling insertion has a clear recovery path. |
| P0 | User copies another item during a paste transaction | New clipboard contents are retained; old contents are not restored over them. |
| P0 | Slow/hung source app or late AX response | Charms stays responsive and late work cannot affect another session. |
| P0 | Type `::arrow` continuously at normal/high speed in an eligible field | Query is exactly `arrow`, regardless of the source/panel split; Enter replaces the tracked activation text with one arrow and leaves no trigger/query prefix behind. |
| P0 | Escape or Copy after typed invocation, including a slow focus handoff | The literal `::` and any source-side prefix remain exactly as typed; source text is not deleted or overwritten. |
| P0 | Marker edited/deleted, caret moved, or field replaced before commit | No blind Backspaces or insertion; stale typed session cancels or offers Copy. |
| P0 | Type `::` and switch apps during asynchronous capture/handoff | No late popup or insertion appears in the new app; returning does not revive the old session. |
| P0 | Press the shortcut during a first-colon or `::` candidate | One shortcut session opens, pending trigger work is invalidated, and literal source text remains intact. |
| P0 | Typed invocation in native rich text, browser contenteditable, and a custom-rendered editor | Exact range replacement works only where proven; insufficient AX support preserves source text and offers shortcut/Copy without guessing offsets. |
| P0 | Typed trigger switched off, excluded, secure, an input method active, or missing AX/required backend access | No automatic popup or processing. Switched-off or globally unauthorized observation is removed; source activation text stays intact. Shortcut/menu Browse and Copy remains usable. |
| P0 | Held Shift/Command/Option during selection | Never synthesize physical releases or dispatch while held. Release within the one-second bound permits one revalidated action; expiry clears the action and returns to browsing while valid. A later release alone never inserts. |
| P1 | Display is unplugged, rearranged, or changes resolution | Session cancels/revalidates safely and the next invocation chooses the new correct display. |
| P1 | Accessibility not granted; source window on B and mouse on A | Available, validated window-list metadata places browse/copy on B without new permissions; otherwise use the documented mouse/primary fallback and never imply an insertion target exists. |
| P1 | IME marked text and candidate selection | Search composition works and candidate Return/Escape does not insert/cancel prematurely. |
| P1 | Literal-code/IPv6/CSS examples, including `x :: Int`, `:::`, `::1`, `::before`, and `::2192` | Excluded contexts stay literal; bracketed/preceded-word forms fail the boundary. In an eligible field the shared `::` prefix can open Charms, numeric queries remain valid, and cancellation never silently writes a guessed literal query. |
| P1 | Type `::arrow` and Enter in one motion | One pending activation uses only the frozen/reconciled query generation, waits for release, and dispatches once; timeout/order failure offers Copy or cancels without guessed text. Enter received by the source stays untouched. |
| P1 | `std::`, a pasted `::`, rapid repeats, U.S. and at least one non-U.S. colon layout, and another app's shortcode UI | Only confirmed eligible committed markers invoke Charms independent of physical key position; exclusions/boundaries prevent duplicate or unwanted handling. |
| P1 | Shortcut collision, changed layout, or another utility (for example PopChar) already owning `⌃P` | Conflict is recoverable; recorder labels remain accurate and another shortcut can be chosen. |
| P1 | Record the current shortcut or a reserved/unregistrable system combination | Recorder input never opens the picker. A valid combination is stored only after registration succeeds; failure preserves the previous working shortcut with a clear explanation. |
| P1 | Keyboard-only use and VoiceOver | Search, selection, favourites, variants, insertion, Copy, and dismissal are reachable and named. |
| P1 | Relaunch, sleep/wake, denied login item, and corrupt preferences | Settings recover predictably; Charms remains launchable and quit-able. |
| P1 | Reopen/duplicate launch, sleep, inactive session, and screen lock during capture/commit preparation | No duplicate global resources. Cancel pre-dispatch work, suspend recognition until a verified active/unlocked context, and never revive a stale session on wake/unlock. Retain honest uncertainty if a write had already begun. |
| P1 | Opt a terminal into shortcut pass-through, switch repeatedly to/from TextEdit, and press the first key rapidly | The terminal receives its native binding while registration is released; Charms handles the registered shortcut in TextEdit. Transition/re-registration failures are measured and recoverable, without an impossible before-every-next-key guarantee. |

### 12.3 Real application coverage

Record app version, macOS version, input type, display configuration, placement source, insertion backend, selection replacement, Undo, clipboard result, and CPU architecture. Start with:

- TextEdit plain text and rich text; Notes and Mail.
- Safari and Chrome native form inputs and textareas.
- At least one rich browser editor/contenteditable surface and Google Docs as a separate custom-rendered case.
- An Electron editor or messaging application, including VS Code if it is part of the user's workflow.
- Terminal and one remote-desktop/virtualized input context as explicit compatibility probes, not assumed supported contexts.

The development machine has Safari, TextEdit, Notes, Mail, and Terminal, one physical display, and no Chromium browser, Electron app, or Intel hardware. Rows that cannot be exercised there are recorded in `docs/compatibility.md` as built but unverified, with the reason; they are not assumed to pass.

Check whether Electron needs its accessibility tree enabled through the documented accessibility mechanism. Do not infer that one successful Electron app or browser field establishes support for all editors. Publish limitations and Copy fallbacks with the tested matrix. Recording CPU architecture keeps the §2 hardware statement honest: until the matrix holds an Intel result, the universal build is described as verified on Apple Silicon only.

Test the first and later invocations after an Electron app launches. Where needed, use Electron's documented `AXManualAccessibility` integration and record the change; do not assume every Chromium browser exposes the same switch or behaviour. Do not toggle undocumented accessibility modes as a universal workaround. A delayed accessibility tree uses the normal geometry fallback rather than blocking the picker.

Measured with Electron 45: an application whose tree is off reports no focused element and answers `AXManualAccessibility` with "off"; setting the attribute makes the focused field appear about two seconds later, and the tree is off again after the application restarts. Because the switch changes how another application runs, Charms does not set it by itself. When a session finds such an application it ends that attempt and asks the user, once per application: Turn On, Not Now (until Charms restarts), or do not ask again. Agreement is stored per bundle identifier, and Charms then sets the attribute whenever that application comes to the front. After the question the shortcut reopens the picker, with insertion if the field is now reported and for copying otherwise. A typed `::` shows the same question, but Return does not answer it, since the keys typed after the colons land in it. Settings lists the answers and can forget them.

## 13. Performance and reliability budgets

These are initial engineering targets, to be measured and adjusted from a documented baseline rather than presented as existing claims:

| Measure | Target |
| --- | --- |
| Warm shortcut to usable picker | 95th percentile at or below 150 ms on a documented reference Mac, measured from the hot-key event to the first frame with a focused search field, excluding the first invocation after launch. |
| Full-catalogue query to stable results | 95th percentile at or below 30 ms for ordinary queries; UI never blocks on catalogue generation. |
| Idle behaviour | No polling of document text or recurring network requests; no keyboard observer when `::` is off, and a negligible-cost observer when enabled. |
| Memory | Initial target below 75 MB idle, measured in M2 with entry/manifest/index byte counts. Prefer compact range/lazy metadata and measured index optimization before new infrastructure; if the documented target remains unrealistic, revise it with measured evidence rather than silently narrowing required coverage or blocking on a speculative estimate. |
| Error handling | Every capture/insertion failure terminates or degrades predictably; no indefinite spinner or retry loop. |

Preload or lazily prepare the immutable catalogue without delaying first keyboard use. Instruments should resolve real bottlenecks before adding caches or concurrency complexity.

## 14. Build, signing, and release operations

- Keep the bundle identifier (`ch.lkmc.Charms`), installation path, and signing identity stable for permission testing. Sign local builds with the machine's Apple Development identity (`CODE_SIGN_IDENTITY`): macOS then keeps Accessibility grants across rebuilds, which an ad-hoc signature, different in every build, does not. Ad-hoc builds remain what CI and releases produce.
- Document a predictable development installation/run path. Never automate granting TCC access or reset the user's permission database as a routine build step.
- Keep certificates, credentials, and provisioning data outside the repository; use local Keychain or CI secret storage.
- Use the shared pipelines unchanged. `ci.yml` builds, runs the tests, checks that the committed catalogue is what the generator produces from the pinned data, and assembles the universal app on the pinned hosted runner and Xcode. `release.yml` runs on a `v*` tag: it tests, builds the universal app, packages zip and dmg, publishes the GitHub Release, and compares the published assets with the built ones byte for byte. `zai-code-review.yml` adds the automated review. `CICD.md` documents them.
- Releases are ad-hoc signed and not notarized, so the README and release notes state the Gatekeeper step a downloader needs. When a Developer ID account is supplied, add the `notarytool` submit, staple, and `spctl` verification as a checklist then; it is not a prerequisite for the first release.
- Define "reproducible" before relying on it: either a clean checkout at a pinned commit, rebuilt on the documented toolchain, produces byte-identical archives, or the release notes state plainly that the published checksums identify the artifact rather than prove a reproducible build. Verify whichever claim is made once per release instead of assuming it.
- Recommend a stable installation such as `/Applications` before enabling launch at login; verify that the tested build is not running from app translocation. Document removal/disabling login item, privacy, compatibility, permission recovery, and reinstalling a previous release from retained GitHub assets/checksums. Include data-schema compatibility/backup instructions; replacing the app alone is not a guaranteed downgrade of migrated user data.
- Add automatic updates only after signing and release reproducibility work; assess a maintained updater separately if needed.

## 15. Decisions to record during implementation

Decisions settled by the spike of 10 November 2026 (macOS 27.0.1, Apple Silicon, one physical display plus a virtual one, Swiss German layout, TextEdit as the source):

| Decision | Outcome | Evidence |
| --- | --- | --- |
| Minimum macOS version and Intel release support | macOS 14; universal build, Intel unverified (§2). | The package builds for both architectures on the current toolchain; no Intel machine or older system was available to run it. |
| Nonactivating-panel window level and Spaces configuration | `.floating`, `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.transient`, `hidesOnDeactivate = false` (§6.4). | Key in about 10 ms without activating; focus returned to the source by itself within 3 ms. |
| Caret geometry | Confirm the line from an adjacent character, else guard one extra line (§6.1). | TextKit's zero-length rectangle is one line high; character rectangles are right. |
| Default insertion transport and per-app exceptions | One Unicode key event pair through `postToPid`; paste only for listed apps (§7.3). | All fixtures exact up to 64 UTF-16 units, selection replaced, one Undo, no delay needed. |
| Typed-marker observer and attribution | `NSEvent` global key-down monitor; attribution by delivery channel; position by read-back (§7.5, §7.6). | Clean split at 2 ms key gaps; caret arithmetic at event time was off by one at 15 ms gaps. |
| Insertion-backend permission model | Accessibility covers reading focus, posting to a process, and the key monitor. | The built app, started through Launch Services with only its own Accessibility grant, inserted by shortcut and by `::`; the grant was noticed without a relaunch. macOS 27 names the list Device Control and Data Access, so the interface describes it rather than naming it. |
| Unicode/CLDR baseline and missing-glyph policy | Unicode 18.0.0, Emoji 18.0, CLDR 49; support decided at run time by a CoreText layout check (§8.1). | macOS 27.0.1 renders Emoji 17: newer entries must be hidden there, older systems hide more. |
| Behaviour beyond TextEdit | Unicode events with no per-app exception needed so far. | Safari 27 (textarea, text input, editable element, password field) and Terminal 2.15 at a zsh prompt behaved like TextEdit; a password field gets Copy only. |
| Full screen | No special case. | Over full-screen TextEdit the picker appeared in that Space, took keys and inserted. The stranding other apps of the owner worked around did not occur with this panel configuration. |
| Pasteboard restoration for listed apps | Snapshot and restore only when the system allows reading without asking; never over a newer copy (§7.4). | In TextEdit and the harness the paste arrived and the previous clipboard was back afterwards; `accessBehavior` was `alwaysAllow` for the app started from a terminal. |
| Cell size, navigation, mouse activation | 44 point cells, eight columns; arrows act on the results from the first press; a click activates on release like Return. | `scripts/e2e.sh` scenarios `navigate`, `click_cell`, `click_outside`. |
| Permission request | One system prompt on the first press of Enable Insertion; later presses open the list directly. | Showing the prompt and opening System Settings together left the prompt open behind it after the switch was turned on. |
| Signing and release configuration | Shared pipeline: ad-hoc signed universal zip and dmg; Apple Development identity locally (§14). | The owner's other apps; a development identity is present on the machine and none for Developer ID. |

Still open, each to be recorded in `docs/compatibility.md` when a machine or occasion allows:

| Decision | Evidence needed | When |
| --- | --- | --- |
| Behaviour in Notes, Mail, Chromium and Electron applications | The checks already made in TextEdit, Safari and Terminal. Notes and Mail were left alone on the development machine so as not to write into the owner's data; no Chromium or Electron application was installed. | M5 |
| Stage Manager, separate Spaces | The picker appears in the current context without a Space switch. "Displays have separate Spaces" is off on the development machine, and changing it needs a logout. | M5 |
| Pasteboard restoration under Launch Services | What `accessBehavior` reports for the installed app on macOS 15.4 and later, and whether the system asks. | M5 |
| Light appearance, increased text size, VoiceOver, input methods | A pass through the picker and settings in each. | M5 |
| Coexistence with PopChar on the same shortcut | Which of the two receives Control-P, and what Charms reports when it is the second to register. PopChar was not installed on the development machine. | M5 |

Do not expand the main interface to solve rare compatibility problems. Keep special handling behind a clear fallback, an app-specific setting, or documented scope.

## 16. First implementation slice

As built: the implementation landed as one PR with a commit per slice (scaffold, catalogue generator and data, `CharmsCore` with its tests, the app, the harness with `scripts/e2e.sh`, and the documents), not as the separate PRs first planned. The shared CI assembles and inspects the app bundle, so a scaffold without the app target would have needed a second, untested variant of the package and the workflow. Both invocation methods are in.

Catalogue generation and a refined grid can proceed independently once their interfaces are defined, but the focus/placement/insertion state machine remains the critical path. Delegate bounded data, fixture, documentation, and visual tasks only after their expected outputs can be checked independently.

The first useful milestone is: **with the mouse on one monitor and the caret on another, press `⌃P`, choose `→` or `👩‍💻`, and continue typing in the original field; Escape cancels cleanly.**

## 17. Primary technical references

These references establish available platform/data capabilities. The placement, lifecycle, compatibility, and UX policies in this plan are engineering decisions that still require the tests above.

- [Apple: selected text range AX attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute).
- [Apple: bounds-for-range AX parameter](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute).
- [Apple: AX attribute queries and failure modes](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue).
- [Apple: focused UI element attribute](https://developer.apple.com/documentation/applicationservices/kaxfocuseduielementattribute).
- [Apple: focused UI element changed notification](https://developer.apple.com/documentation/applicationservices/kaxfocuseduielementchangednotification).
- [Apple: Accessibility trust](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).
- [Apple: workspace and frontmost application](https://developer.apple.com/documentation/appkit/nsworkspace).
- [Apple: session resign-active notification](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification).
- [Apple: nonactivating panels](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel).
- [Apple: local input-client marked text](https://developer.apple.com/documentation/appkit/nstextinputclient/hasmarkedtext%28%29).
- [Apple: provider accessibility notifications](https://developer.apple.com/documentation/appkit/nsaccessibility/notification/focuseduielementchanged).
- [Apple: shadow invalidation](https://developer.apple.com/documentation/appkit/nswindow/invalidateshadow%28%29).
- [Apple: screen containing keyboard focus](https://developer.apple.com/documentation/appkit/nsscreen/main) — consult only before the picker becomes key; afterwards rely on captured geometry (§6.2).
- [Apple: window collection behaviour](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct).
- [Apple: screen parameters change notification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification).
- [Apple: active Space change notification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification).
- [Apple: display reconfiguration callback](https://developer.apple.com/documentation/coregraphics/cgdisplayregisterreconfigurationcallback%28_%3A_%3A%29).
- [Apple: Unicode keyboard events and framework limitations](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29).
- [Apple: process-addressed event dispatch](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid%28_%3A%29).
- [Apple: preflight event-synthesizing access](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess%28%29).
- [Apple: request event-synthesizing access](https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess%28%29).
- [Apple: preflight keyboard-listening access](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29).
- [Apple: request keyboard-listening access](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29).
- [Apple: creating an event tap](https://developer.apple.com/documentation/coregraphics/cgeventtapcreate).
- [Apple: global event monitors and their accessibility requirement](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29).
- [Apple: creating an accessibility observer](https://developer.apple.com/documentation/applicationservices/axobservercreate%28_%3Acallback%3A%29).
- [Apple: event source key state](https://developer.apple.com/documentation/coregraphics/cgeventsourcekeystate%28_%3A_%3A%29).
- [Apple: pasteboard change count](https://developer.apple.com/documentation/appkit/nspasteboard/changecount).
- [Apple: pasteboard access behaviour](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum).
- [Apple: selected-text AX attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute).
- [NSPasteboard.org: transient and auto-generated pasteboard markers](http://nspasteboard.org/).
- [Apple: login item service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp).
- [Apple: SMAppService status](https://developer.apple.com/documentation/servicemanagement/smappservice/status).
- [Apple: SMAppService openSystemSettingsLoginItems](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems%28%29).
- [Apple: input-source selection notification](https://developer.apple.com/documentation/appkit/nstextinputcontext/keyboardselectiondidchangenotification).
- [Apple: Unicode keyboard translation](https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate).
- [Apple: macOS 26.4 release notes and Intel support horizon](https://developer.apple.com/documentation/macos-release-notes/macos-26_4-release-notes).
- [Electron: accessibility integration](https://www.electronjs.org/docs/latest/tutorial/accessibility).
- [Apple: window list information](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29).
- [Unicode Character Database](https://www.unicode.org/ucd/); pinned release: [18.0.0](https://www.unicode.org/Public/18.0.0/).
- [Unicode Emoji specification, UTS #51](https://www.unicode.org/reports/tr51/).
- [CLDR releases and downloads](https://cldr.unicode.org/index/downloads).
- [Unicode: CLDR annotations](https://unicode.org/reports/tr35/tr35-general.html#Annotations).
- [Unicode data/software license](https://www.unicode.org/license.txt).
