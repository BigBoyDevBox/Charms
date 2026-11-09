# Charms implementation plan

Status: proposed implementation, ready to break into engineering tasks

Updated: 9 November 2026

## 1. Product direction

Charms is a small native macOS utility for inserting arrows, unusual symbols, punctuation, and emoji into the app where the user is typing. Its defining behaviour is that the picker opens on the display containing the typing focus, preferably beside the text caret, even when the mouse is on another display.

The product name is **Charms**. The selected interface direction is the **first, compact grid design** from the initial concept: a search field, generous character cells, favourites, recents, and a quiet detail/footer area. The alternative named-results list is not the default design.

### Alternatives considered

- **macOS Character Viewer** (built in): complete Unicode coverage and nothing to install, but it opens as a detached palette away from the caret, keeps no favourites or recents, and cannot insert into the focused field. Charms differentiates on caret-adjacent placement and a query-first grid.
- **PopChar** (commercial): the mature reference for this job, with broad coverage and dependable insertion. Charms differentiates on focus-aware placement, favourites/recents, and a smaller surface; PopChar is also the likely owner of `⌃P`, which is why shortcut conflict recovery is a P1 acceptance case in §12.2.
- **Rocket and TextExpander-style typed expansion**: fast because the trigger is typed, but they expand abbreviations into text rather than letting the user search and choose a character, and their trigger languages are broader than the optional `::` marker planned here.
- **Named-results list** (the alternative in the initial concept): rejected as the default because scanning a vertical list of names is slower than scanning the characters themselves; the grid keeps the name in the footer instead.
- **Copy from a browser emoji picker**: no install and full coverage, but it needs the mouse and spends the clipboard. The shortcut path's promise of leaving the clipboard untouched is what makes Charms competitive with this habit.

These are positioning notes, not compatibility claims. Measured behaviour against real applications is recorded separately in §12.3 and `docs/compatibility.md`.

The repository currently contains the project license and no application implementation. This document specifies intended behaviour and engineering decisions; it does not claim that cross-app compatibility has already been demonstrated.

### Success criteria

- Press the configured shortcut, type a familiar name, select a character, and continue typing without moving the mouse.
- Opening the picker never chooses the mouse display over a usable caret or focused-window display.
- Escape restores the original typing context without modifying text or the clipboard.
- Enter inserts the exact selected Unicode string, including complete emoji sequences, into the intended input field.
- A stale or uncertain target produces a clear copy-only outcome instead of inserting somewhere else.
- The default interface remains useful without choosing a font, Unicode block, output format, or category.
- Searching, favourites, and recents work offline, without an account.
- An optional typed `::` trigger opens the same picker, alongside the global shortcut, without leaving the trigger behind after insertion.

## 2. Scope and initial platform choices

| Area | Initial decision |
| --- | --- |
| Platform | macOS 14 or later; confirm this deployment target during the native spike. |
| Hardware | Design for Apple Silicon and Intel; publish a universal build only after both architectures have build coverage and real-machine validation. |
| Language and UI | Swift, AppKit for application/window integration, SwiftUI for the picker and settings where it behaves reliably. |
| Application style | Menu-bar accessory app, with no persistent Dock icon or ordinary document window. |
| Shortcut | Offer the user's preferred Control-P (`⌃P`), configurable and subject to successful registration. |
| Typed trigger | Optional `::` recognition, enabled explicitly with any required Input Monitoring access; the shortcut remains available independently. |
| Distribution | Direct distribution, initially through GitHub releases; signed and notarized for public builds. |
| Runtime dependencies | Prefer Apple frameworks and a bundled local catalogue; introduce external packages only for a concrete unmet need. |
| Language | English interface and search annotations initially; use localizable strings and keep the data format ready for additional locales. |
| Storage | Local settings and versioned local files; no server or synchronization service. |

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
9. Typing continues in that field. The selected item is moved to the front of recents.

Escape, clicking outside the panel, or pressing the shortcut again cancels the picker. Cancellation does not modify the document, recents, or clipboard.

### Alternate journey: type `::`

1. The user enables the typed-trigger option and grants the access it needs.
2. In an eligible text field, the user types `::` at the start of a field or after an allowed boundary, initially whitespace or opening punctuation.
3. The two colons enter the source normally. After confirming committed text in the original field, Charms opens the same search-focused picker beside them.
4. The user can continue typing without an intentional pause. For `::arrow`, any query prefix that reaches the source during focus transfer is tracked and becomes the beginning of the picker query; later query characters go directly into the picker.
5. On Enter, Charms validates the original field and exact tracked range, returns keyboard focus, and replaces the marker plus any verified source-side query prefix with the chosen string once.
6. On Escape, the source is unchanged: the literal `::` and any prefix typed there before the picker took focus remain. Query text entered inside the picker is not written back to the source.

The shortcut path inserts at the existing selection. The typed-trigger path replaces a tracked activation range. Keep those operations distinct even though they share the same picker. Seamless fast typing must be proved in the native spike; a listen-only observer alone does not guarantee it.

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
│ Right arrow · U+2192             ↵ Insert │
└──────────────────────────────────────────┘
```

The diagram is structural; native font metrics determine final spacing.

- Start near 400 points wide with approximately 40-44 point character cells and eight columns at the normal size.
- Let accessibility text sizing, available display area, and actual font metrics determine the final dimensions. Reflow rather than clipping.
- Empty search shows a compact favourites section and up to two rows of recents. Seed a small useful favourites set only on first launch.
- A non-empty query replaces those sections with a single result grid. Keep the selected name and full Unicode sequence in the footer.
- Use a native scroll view for longer results, keep the selected cell visible, and avoid resizing the panel on every keystroke.
- Start with the first matching item selected. Clearing search restores the initial favourites/recents state.
- Distinguish selection from hover. A stationary mouse must not steal selection after a keyboard search or rerender.
- Use system appearance, readable contrast, restrained borders, and native focus indicators. Honour Reduce Motion and Increase Contrast.
- Do not introduce permanent sidebars, font selectors, code-format controls, or category toolbars into this surface.
- An empty result state says that nothing matched and allows immediate query editing. Enter does nothing when no result is selected.

### 4.2 Keyboard behaviour

| Input | Behaviour |
| --- | --- |
| Configured global shortcut | Open the picker; if already open, cancel. Ignore key-repeat so holding the shortcut does not repeatedly toggle it. |
| Typing | Update the search query while preserving ordinary text editing and input-method composition. |
| Left / right | Edit the query normally while the search field is focused; move between cells while navigating the grid. |
| Down from search | Enter result navigation, initially using the currently selected result. |
| Up / down in grid | Move by the visible column count; Up from the first row returns to search. Define and test partial final rows. |
| Typing while navigating results | Return to the search field and edit the query using ordinary text input. |
| Enter | Insert the selected item exactly once. |
| Command-Enter | Copy the selected Unicode string, close the picker, and return focus without automatic insertion. |
| Escape | Cancel and restore focus. |
| Command-D | Toggle the selected item's favourite state. |
| Tab / Shift-Tab | Follow a predictable native focus order; never trap the user in the grid. |

Confirm these search-field/result navigation rules with a small native interaction test. Enter can insert the selected result directly from the search field, without an extra Down key. Do not intercept Return, arrows, or Escape while an input method is using them to commit marked text or choose candidates. Keep normal selection, paste, undo, and VoiceOver commands usable in the search field.

### 4.3 Favourites, recents, and variants

- A context menu and Command-D add/remove favourites. Persist their explicit order; an initial simple move-left/move-right action is sufficient before drag reordering.
- Removing the final favourite leaves an intentionally empty section, rather than restoring the seed set.
- Deduplicate recents by exact sequence and cap stored history, initially at 50 entries. Show only the compact leading portion in the empty-query grid.
- Provide Clear Recents in settings. Retain favourites separately.
- Store the exact selected emoji variant. A small secondary variant chooser may expose skin tones for entries with defined variants; do not manufacture combinations by appending arbitrary modifiers.
- A preferred skin tone can choose a valid default variant, while explicitly saved favourite variants remain unchanged.
- Use the system's native text/emoji rendering. Preview combining marks against a dotted-circle guide when necessary; the guide must never become part of the inserted string.

### 4.4 Menu bar, settings, and onboarding

The menu-bar item must offer Open Charms, Settings, About, and Quit. Opening through the menu bar uses the same target-capture rules as the shortcut. If no trustworthy external target is available, open in browse/copy mode.

Keep settings to:

- Keyboard shortcut.
- Enable typed `::` trigger, with an application exclusion list and a simple pause control.
- Launch at login, off until the user opts in.
- Preferred emoji skin tone.
- Clear recents and reset favourites as separate explicit actions.
- A compact Compatibility section for an app's insertion method, only if the native spike proves that per-app overrides are necessary.

On first launch, explain Accessibility access in plain language: Charms uses it to locate the typing field and return characters there. Offer **Enable Insertion** and **Browse and Copy**. Prompt for trust only in response to the enable action; browsing remains useful without access. Recheck permission when returning from System Settings and explain how to recover if it is revoked.

Enabling `::` is a separate, opt-in step. Explain that recognizing it requires observing keyboard events and briefly tracking the explicit trigger/query transition, request Input Monitoring through the applicable public API if needed, and leave the keyboard-shortcut path usable when this permission is denied. Disabling the option removes the event observer and clears its transient state.

The design does not require Screen Recording, microphone, contacts, or Full Disk Access. Keyboard observation runs only while the typed-trigger option is enabled and eligible. Validate the actual authorization requirements of each backend during the spike; add no permission without a demonstrated need.

## 5. Native architecture

Use one macOS application target, a unit-test target, and a small UI-test/harness target. Start with a conventional checked-in Xcode project and shared scheme. Record the supported Xcode/Swift toolchain in the README when the project is created; avoid an unnecessarily elaborate project generator or build system.

Suggested organization:

```text
Charms.xcodeproj/
Charms/
  App/                  AppDelegate, app lifecycle, status item, settings
  HotKey/               registration, recorder, layout-aware key labels
  Triggers/             optional :: observer, marker recognition, exclusions
  Targeting/            focus capture, AX wrappers, target validation
  Placement/            coordinate conversion, display choice, panel layout
  Picker/               NSPanel controller, SwiftUI views, keyboard handling
  Catalog/              records, catalogue loading, variant relationships
  Search/               normalization, matching, deterministic ranking
  Insertion/            transaction coordinator, Unicode/paste transports
  Persistence/          settings, favourites, recents, migrations
  Resources/            generated catalogue, assets, localized strings
CharmsTests/
CharmsUITests/
Tools/                  reproducible catalogue generation and validation
Data/                   source manifests, curated aliases, seed favourites
docs/                   compatibility results, technical decisions, release guide
THIRD_PARTY_NOTICES.md
```

### Responsibilities and boundaries

| Component | Responsibility |
| --- | --- |
| `HotKeyService` | Register one shortcut, handle conflicts and changes, and emit a debounced invocation. |
| `TypedTriggerService` | Observe only while enabled, recognize a committed `::` marker, enforce exclusions, and emit an invocation with a marker proof. |
| `TargetCaptureService` | Capture the originating process, focused element/window, selection range, and geometry; typed-marker validation permits only narrowly bounded source-text reads. |
| `PlacementEngine` | Pure placement decisions from captured rectangles, screen geometry, and panel size. |
| `PickerController` | Own one panel and one invocation session; coordinate show, cancel, and selection. |
| `CatalogStore` | Load an immutable, versioned catalogue and expose complete Unicode strings. |
| `SearchEngine` | Match and rank locally; return stable item identifiers with cancellable query results. |
| `InsertionCoordinator` | Validate the target, choose one backend, and perform at most one dispatch. |
| `PreferenceStore` | Persist user settings, favourites, and recents with schema migration. |

AppKit UI and lifecycle state belong on the main actor. Catalogue loading, indexing, and other pure work run away from the UI. Isolate potentially blocking cross-process AX calls behind bounded requests on a serial execution context; never move non-Sendable AX handles between arbitrary tasks. Give requests a generation/session identifier so late replies cannot reposition a new picker or insert into an expired target.

Use dependency injection at these boundaries to test geometry, search, session transitions, and insertion decisions without manipulating other apps.

Start with public system hot-key registration behind `HotKeyService` rather than a global keyboard hook for shortcut-only use. Prototype direct distribution without App Sandbox; keep any future sandbox/App Store feasibility assessment separate from the initial implementation.

## 6. Focus capture and display placement

### 6.1 Capture before presentation

On each invocation, create a new session containing:

- Originating process identifier and application identity.
- Opaque references to the focused editable AX element and focused window, when available.
- Selection range, caret/selection bounds, field bounds, and window bounds where supported.
- Display geometry at invocation and the selected placement source.
- Session identifier, permission state, and whether automatic insertion is allowed.
- Invocation source: shortcut, menu bar, or typed marker. A typed session additionally holds the activation range, bounded source-side query prefix, and expected caret position after them.

Keep this snapshot in memory only and discard it after the session ends. Shortcut/menu-bar invocation does not read selected text or document contents. Typed invocation may read only the marker, a bounded source-side query prefix during focus transfer, and a small boundary context. Neither path captures the window title or clipboard as part of ordinary invocation.

Try the focused element's selected range and the bounds-for-range AX parameter. A collapsed selection is normally the caret. Some apps return no useful bounds, and that is an expected compatibility condition.

For a non-empty selection, anchor near a reliable end-of-selection caret rectangle when available; otherwise use the selection or field bounds. Do not turn an unsupported range query into a request for the entire document.

Bound AX messaging time and the total capture deadline. If a request is slow, present using already captured reliable window/display geometry, then ignore replies after cancellation or session replacement. A hung external application must not freeze the picker.

### 6.2 Placement priority

1. **Usable caret/selection rectangle:** choose the display containing that rectangle and place adjacent to it.
2. **Focused editable field rectangle:** choose its display, using greatest intersection if it spans screens, and anchor near the field.
3. **Focused window rectangle:** choose the display with the greatest visible overlap and place within the window's usable intersection.
4. **Mouse display:** use only if no usable source geometry can be obtained.
5. **Primary available display:** final fallback if the mouse is not within a current screen.

Select the screen from captured geometry rather than consulting the picker's own `NSScreen.main` after it has become key. Do not remember a last-used global panel position that overrides the current source.

### 6.3 Coordinate and bounds rules

- Centralize conversion between Accessibility global coordinates and AppKit screen coordinates. Verify the desktop origin transform across all connected displays.
- Use logical points for window layout. Do not apply a screen's backing scale twice.
- Accept a zero-width caret with a meaningful height. Reject non-finite values, implausible geometry, stale offscreen rectangles, and bounds unrelated to any connected screen.
- Prefer below the caret with a small gap, flip above if necessary, and clamp to the selected display's `visibleFrame` with an approximately 12-point margin.
- Account for the menu bar, Dock, notches, small displays, and panel size changes. Keep the picker visible and avoid covering the insertion line when geometry allows.
- On display disconnection or a Space change during a session, cancel safely unless the session can be revalidated and repositioned without changing its target. Do not silently switch to another target.

### 6.4 Panel lifecycle

Prototype an `NSPanel` constructed with the nonactivating-panel style, able to become key for search without becoming an ordinary main application window. Capture the origin before ordering it on screen. Use standard window levels.

Prove the combination of full-screen auxiliary behaviour and one explicit Spaces strategy on supported macOS versions. Do not combine mutually exclusive collection behaviours or rely on a newly introduced option without availability checks. Opening Charms must not move the user to a different Space.

Cancel when the user genuinely changes the originating app/window, the panel loses keyboard focus to an outside click, the target exits, or the session becomes invalid. Distinguish expected panel-focus transitions from genuine user target changes so opening the picker does not immediately cancel itself.

## 7. Insertion and session correctness

### 7.1 State machine

Represent lifecycle explicitly:

```text
idle -> capturing -> browsing -> validating -> dispatching -> idle
                         |           |
                         +-> cancel -+
                         +-> copy -> idle
```

- Only one session and one insertion dispatch can be active.
- A shortcut invocation supersedes pending `::` recognition, clears its candidate state, and preserves text already typed in the source. It starts a fresh shortcut session rather than inheriting a marker-removal range. An already visible picker still follows the normal shortcut-to-cancel rule.
- Repeated Enter/click events cannot dispatch twice.
- Cancelling invalidates pending AX requests, search results, scheduled paste actions, and focus restoration callbacks.
- A late completion cannot revive a panel, modify recents for another session, or send text.
- Normal cancellation restores focus only if the original context is still current. It must not reactivate an app the user deliberately left.

### 7.2 Revalidate immediately before dispatch

Check permission, process identity/liveness, original window/element validity, and the source's current focus. Where supported, verify the selection range has not changed since capture. The picker being key is an expected exception, not permission to target any newly frontmost app.

Treat secure/password fields and active secure-input conditions conservatively. Do not inspect their text or synthesize insertion into them. If an element cannot be classified or revalidated sufficiently, offer Copy and ask the user to place the caret and invoke Charms again.

If the user switches to a different field/window while the picker is open, cancel or require reinvocation. Never silently retarget. A terminated app, recycled process identifier, replaced web element, or closed document must invalidate the snapshot.

### 7.3 Choose a transport before sending text

After freezing the selected output, wait for invocation/selection modifiers to be physically released within a bounded interval. Do not synthesize key-up events for keys the user is still holding. If modifiers remain held, keep a recoverable pending state or cancel; do not send altered text.

Then dismiss/resign the panel, establish that the original app and exact target field are again the effective receiver, and revalidate immediately before dispatch. Prefer PID-addressed Quartz events where supported and tested. PID targeting alone does not prove that the correct field/window is focused; abort if that validation fails. Do not silently fall back to the global event stream.

The spike must compare two methods using the same complete string fixtures:

1. **Unicode keyboard events:** post the selected UTF-16 string to the revalidated target using Quartz, with correctly paired events and clean event flags. Verify selection replacement and Undo in each supported app.
2. **Plain-text paste:** an explicitly selected compatibility backend for apps where Unicode events are unsuitable.

Prefer the Unicode path where it behaves like ordinary typing and preserves the clipboard. Apple documents that some frameworks ignore an event's supplied Unicode string, so successful event dispatch is not proof of insertion.

Do not automatically paste after an unconfirmed Unicode dispatch: the original event may have succeeded and a retry could duplicate the character. Choose a validated backend ahead of time, using an explicit per-app override only when needed. Unsupported apps retain the Copy action.

Do not set a text field's complete AX value to insert one character; that risks replacing unrelated content, losing formatting, and bypassing normal editing/Undo behaviour.

Use distinct internal results such as `cancelled`, `copied`, `dispatched`, and `failedBeforeDispatch`. Do not report a verified insertion merely because an event was posted. Update recents after a committed dispatch or explicit copy, never after hovering or cancellation.

### 7.4 Clipboard policy

Explicit Copy intentionally replaces the clipboard. The normal Unicode-event backend does not touch it.

For the optional paste backend:

- Capture restorable clipboard representations in memory immediately before taking ownership. Preserve multiple items/types where safely supported, rather than saving only a string.
- If contents cannot be safely snapshotted/restored, do not promise preservation; use an explicit copy/paste choice instead of silently discarding data.
- Write only the selected plain-text Unicode string and remember the resulting pasteboard `changeCount`.
- Restore previous contents only while the pasteboard still has the exact ownership/change count established by that transaction. Never overwrite a subsequent user copy.
- A fixed delay is not a universal paste-completion acknowledgement. Establish app-specific supported behaviour in the spike; if consumption cannot be established reliably, leave this backend explicit and describe restoration as best effort.
- Do not chain a new clipboard transaction while restoration is unresolved. Never restore an old snapshot after relaunch or a later session.
- Do not write clipboard snapshots to disk or logs.

The release gate is predictable behaviour with a documented compatibility method, not a claim of perfectly invisible clipboard use in every application.

### 7.5 Optional typed-trigger recognition

Treat typed invocation as a separate input adapter, not a second picker or an unrestricted text expander.

- Install a listen-only system keyboard observer/event tap only after the user enables the feature and the needed access is granted. Keep the callback fast; do not perform blocking AX calls inside it.
- Recognize the produced colon characters using the active input context, not hard-coded U.S. key positions. Confirm actual committed `::` text and any exactly tracked transition prefix in the source before enabling insertion.
- The event notification may precede the source app updating its AX selection. Use a bounded asynchronous reconciliation step; if the marker cannot be confirmed, leave the source untouched and do not open automatically.
- Before a trigger candidate, keep only minimal recognition state, such as a first-colon candidate, boundary state, source identity, and timestamp. After `::`, a bounded transient query-prefix buffer is allowed only for the handoff below. Do not buffer unrelated typing or log either form of state.
- Reset on focus/caret changes, app switch, mouse navigation, nonmatching editing keys, timeout, sleep/lock, secure input, permission loss, or event-tap interruption. Ignore auto-repeat and Charms-generated events.
- Suspend new trigger recognition through the entire active invocation, including capture, transition, visible browsing, validation, and insertion handoff, so query text cannot trigger a second session.
- Do not trigger from pasted text, dictation, or unproven synthetic input. Uncertain IME/marked-text composition disables automatic recognition in that context; the global shortcut still works.
- Require an allowed boundary to avoid treating constructs such as `std::` as a command. Validate only the minimal source context needed for that decision.
- Ship a conservative, editable application exclusion list for apps with their own shortcode UI, code editors/terminals, password managers, and remote/virtualized input environments. Record the initial bundle IDs in data, not scattered conditionals.
- Start with application-level exclusions. Per-website exclusions can follow later; do not inspect browsing URLs or page content merely to detect the marker.
- Pause/disable must stop observation promptly. Recover an interrupted tap only while the option is still enabled and permissions/eligibility remain valid.

### 7.6 Replace the marker without guessing

For typed invocation, derive and retain the marker's AX range using the source's range units, normally UTF-16. Text before it may contain multi-scalar emoji; Swift character counts must not be used as AX offsets.

**Fast-typing handoff:** a listen-only event tap cannot stop letters from reaching the source while asynchronous AX work and panel presentation occur. Implement an explicit transition state:

- Track a bounded sequence of candidate query events after the marker while the source is still the receiver, with ordering/target evidence, and separately track input received by the new search field.
- Reconcile the committed source substring and caret against those candidate events during focus transfer. Seed the query from the verified source prefix and append the panel-received remainder in proven order; do not duplicate or drop characters.
- Freeze the exact replacement range as marker plus verified source-side prefix once handoff settles. Keep the prefix in the source until insertion is committed, so cancellation requires no destructive rollback.
- Bound transition duration and buffered input, initially targeting at most 250 ms and 64 UTF-16 units, with sequence-safe limits. Tune from measurements. Only this activation transition may collect a query prefix; there is no general keystroke history.
- Do not enable insertion until both the source range and input ordering are established. If the source changes unexpectedly, a bound is exceeded, composition is uncertain, or routing/order cannot be proved, preserve the source and fall back to Copy or cancel. Do not guess, delete, or replay keys into a potentially changed target.
- This is a required feasibility check for uninterrupted `::arrow` typing at normal and high speed. If reliable reconciliation is not achievable with the selected public APIs, record that limitation and revise the trigger design explicitly before release; do not quietly assume that users will pause after `::`.

This policy retains listen-only recognition. Suppressing/buffering arbitrary global input would need a separate design for lossless replay and cancellation and is not an implicit fallback.

On commit:

1. Verify the same process, field, window, expected selection, literal marker, and tracked source-side prefix still exist.
2. Ensure the source supports safely selecting the exact frozen activation range. Select only that marker/prefix; never send blind Backspaces.
3. Perform the panel-to-source focus handoff and revalidate the expected activation selection.
4. Dispatch the chosen output once using the already selected insertion transport.
5. If selection preparation fails before dispatch, preserve the activation text and offer Copy. If preparation changed the selection but dispatch cannot start, restore the previous caret only if the source remains unchanged and current.

Escape and explicit Copy leave source activation text intact. Choosing a symbol replaces it; one normal Undo should restore that text in supported apps. After an uncertain dispatch, do not remove more text or retry another transport. In fields without sufficient AX range access, disable typed invocation and retain shortcut/browse/copy use.

## 8. Catalogue, Unicode, and search

### 8.1 Data sources and coverage

Build a bundled catalogue from pinned official Unicode Character Database data, official emoji data, and CLDR English annotations. Add a small reviewed alias file for familiar terms such as `cmd`, `option`, `tick`, `->`, and `not equal`.

- Include assigned graphic characters and useful whitespace/punctuation, plus complete recommended emoji sequences.
- Exclude unassigned scalars, surrogate code points, noncharacters, private-use glyphs, and standalone control/format/emoji components from normal suggestions. Document the exact coverage in the generator manifest.
- Give whitespace and combining characters visible names and suitable previews so the user understands what they will insert.
- Correctly expand source ranges and algorithmic names; do not expose Unicode data placeholders as user-facing names.
- The initial data version must be selected against the oldest supported macOS rendering behaviour, then pinned with checksums. Do not equate the latest Unicode data with the emoji repertoire rendered by every supported OS.
- Handle known unsupported/missing glyphs deliberately. Hide unsupported emoji variants by default where support is known; retain understandable labels and explicit copy behaviour for entries that cannot be previewed reliably.

The catalogue generator is a development/build tool. The released app performs no data downloads or remote lookups.

### 8.2 Data model

Each entry needs:

- Stable identifier derived from its exact scalar sequence.
- Exact output `String` and scalar values; never assume one character equals one scalar or one UTF-16 unit.
- Human-readable display name, official name where applicable, aliases, category/group, and search tokens.
- Kind/presentation metadata, variant-family relationships, and any known rendering-support metadata.
- Source-data version and provenance in the catalogue manifest.

Preserve variation selectors, ZWJ joins, modifiers, keycap sequences, and regional-indicator flag sequences in stored and inserted values. Normalize **search keys**, not the output string. Deduplicate by exact output sequence without collapsing meaningful text/emoji presentations.

### 8.3 Matching and ranking

Start with a lightweight in-memory index rather than a database or external search service:

1. Exact literal character/sequence and valid exact code-point query.
2. Exact familiar alias or display-name match.
3. Token-prefix matches.
4. All-token substring matches.
5. Bounded fuzzy matching for genuine spelling variation, if it improves the fixtures.

Favourites and usage can break ties within a relevance tier; they must not push an unrelated frequent item above an exact query. Keep deterministic ordering for ties. Preserve punctuation aliases such as `->` and `!=` during tokenization.

Support case-insensitive and accent-insensitive search keys, multiple query words, literal pasted symbols, and `U+2192`/`2192` notation. Multi-code-point lookup must parse an entire sequence instead of accepting only its first scalar. Reject invalid scalars gracefully.

Cancel superseded searches and apply results only to the matching query/session generation. Do not replace the selection under the user's Enter key with a late result from an older query.

### 8.4 Generation and licensing

Keep source URLs, exact release versions, checksums, curated overrides, and generation commands in the repository. Generate deterministic output and validate duplicate IDs, invalid sequences, missing labels, variant relationships, and expected search fixtures.

Retain required Unicode/CLDR and any package notices in `THIRD_PARTY_NOTICES.md` and the app's acknowledgements. Preserve the repository's existing license; it does not replace third-party data licenses. Render through system fonts rather than bundling extracted Apple emoji artwork.

## 9. Local persistence and privacy

- Store simple preferences in `UserDefaults`, including shortcut, typed-trigger opt-in/exclusions/pause state, preferred skin tone, and launch-at-login preference.
- Store favourites, their order, and recents in a schema-versioned Codable file under the app's Application Support directory.
- Write atomically and serialize updates. Preserve a recoverable previous file when migrating; do not silently erase user choices on decode failure.
- Migrate entries using stable IDs and exact sequences so catalogue updates do not lose favourites. Preserve unresolved favourites for future recovery rather than deleting them automatically.
- Do not persist search queries, typed-trigger observations or marker context, AX snapshots, selected document text, window titles, or clipboard contents.
- Keep runtime diagnostics limited to timings, error categories, transport choice, and coarse placement/fallback reasons. Avoid typed text and raw user content.
- No telemetry or network access is needed for ordinary operation.
- With typed recognition disabled, no global keyboard observer is installed. With it enabled, observation is local and ephemeral, limited to marker recognition and the bounded explicit-query handoff; unrelated typing is never retained.
- Use the system login-item API when the user opts in; reflect actual registration state, including a disabled or approval-required login item.

## 10. Accessibility and interaction quality

- Expose every result's understandable name, selected state, and available actions to VoiceOver.
- Give the grid a coherent reading/navigation order and identify favourites and recents as groups.
- Announce the selected result and settled search result state without speaking every hover or transient search update.
- Keep favourite/variant actions available to keyboard users; do not hide essential actions behind hover alone.
- Honour system text size, contrast, reduced motion, dark/light appearance, and keyboard focus settings.
- Test marked-text composition and non-U.S. keyboard layouts. Record/display shortcuts according to the current layout while retaining stable registration semantics.
- Verify focus restoration with VoiceOver as well as visually; a dismissed panel must not leave assistive focus stranded.

## 11. Delivery milestones

Implement in small reviewable commits. The native risk spike is a gate for the broader implementation, rather than a demo that is discarded before its conclusions are recorded.

### M0 — Bootstrap the project

- [ ] Create the app target, shared scheme, unit tests, and a tiny native text-input harness.
- [ ] Select and document the deployment target, toolchain, stable bundle identifier, and development signing approach.
- [ ] Add README build/run instructions and a focused `.gitignore`; do not commit local IDE state or signing secrets.
- [ ] Create a menu-bar accessory app with Settings and Quit.

**Exit:** a fresh checkout builds and launches; the app can be quit cleanly, and pure tests run without Accessibility permission.

### M1 — Prove focus, placement, and insertion

- [ ] Register a configurable shortcut and capture the original target before presentation.
- [ ] Show a minimal nonactivating panel with a handful of fixed fixtures: `→`, `—`, `∞`, `😀`, `👍🏽`, `👩‍💻`, and `🇨🇭`.
- [ ] Implement geometry conversion and the complete display fallback chain.
- [ ] Implement cancellation, target validation, and one-dispatch session control.
- [ ] Compare Unicode events and explicit plain-text paste with selection replacement and Undo.
- [ ] Spike committed `::` detection, uninterrupted fast `::arrow` handoff, exact activation-range selection/replacement, Escape preservation, layout/IME limits, and the additional permission path before promising universal typed-trigger support.
- [ ] Test two displays, the mouse on the other screen, negative/vertical display layouts, mixed scale factors, and full-screen/Spaces behaviour.
- [ ] Record actual app/OS/version/backend results in `docs/compatibility.md` and capture decisions in a short technical note.

**Exit:** the core flow works in a native text view and ordinary browser field on both displays. Known incompatible contexts have a predictable Copy path. No unexplained wrong-target insertion or duplicate dispatch remains. If these behaviours cannot be achieved, narrow the supported matrix explicitly before proceeding.

### M2 — Build the offline catalogue and search

- [ ] Pin official datasets and retain notices.
- [ ] Implement deterministic generation, validation, curated aliases, and seed favourites.
- [ ] Add an immutable catalogue loader, exact-sequence IDs, and a local search index.
- [ ] Add independently specified search/Unicode fixtures and measure full-catalogue performance.

**Exit:** catalogue generation is reproducible; representative symbols and composite emoji round-trip exactly; relevance fixtures pass offline.

### M3 — Implement the selected compact grid

- [ ] Build search, favourites, recents, the result grid, footer, and empty states around the M1 panel controller.
- [ ] Add keyboard navigation, click selection, Copy, favourites actions, and validated emoji variants.
- [ ] Match the first design's spacing and simplicity in light/dark appearance and at increased text size.
- [ ] Validate search-field editing, input-method composition, VoiceOver, and dismissal/focus behaviour.

**Exit:** everyday use is possible without the mouse; opening and dismissing the panel remains correct after repeated searches and selections.

### M4 — Make it a dependable daily utility

- [ ] Add versioned persistence, recovery/migration, shortcut recording, and optional launch at login.
- [ ] Add Accessibility onboarding and browse/copy mode.
- [ ] Implement opt-in `::` observation, its separate permission flow, pause/exclusions, boundary checks, bounded fast-typing handoff, and the activation-range replacement transaction proven in M1.
- [ ] Add only the compatibility overrides demonstrated necessary by M1; document the clipboard policy in user-facing terms.
- [ ] Handle permission revocation, app termination, display changes, sleep/wake, and stale AX elements.

**Exit:** favourites/settings survive relaunch; permission and compatibility failures are recoverable; all priority-zero scenarios below pass.

### M5 — Verify and package the first release

- [ ] Complete the real-app/display compatibility matrix and review unresolved limitations.
- [ ] Measure performance using release builds and record the hardware/OS used.
- [ ] Produce a signed/notarized app and distribution archive, using an appropriate Developer ID identity supplied through local/CI signing configuration.
- [ ] Verify a downloaded build on a clean user account, including launch, trust onboarding, login item, and quitting.
- [ ] Publish build instructions, compatibility notes, release notes, and checksums with the release.

**Exit:** a fresh user can install, grant only needed access, invoke Charms, insert symbols/emoji in documented contexts, and remove or quit it normally.

## 12. Verification strategy

### 12.1 Automated tests

Focus automated tests on decisions with meaningful independent expected outcomes:

- Placement geometry: left/right/above/below primary display, mixed scale metadata, zero-width carets, spanning windows, usable-frame edges, and missing geometry.
- Session state: duplicate Enter, cancellation during capture/validation, late AX/search callbacks, app exit, changed target, and overlapping invocations.
- Focus handoff and modifiers: dispatch cannot occur while the picker is the receiver, while physical modifiers remain held, or after the source field changes.
- Typed-trigger state: committed two-colon recognition, allowed boundaries, timeouts, resets, exclusions, auto-repeat, observer shutdown, synthetic-event filtering, and no reentrancy from the picker.
- Activation replacement: correct UTF-16 ranges after emoji, fast source/panel query splits in every position, source edits before commit, failed selection preparation, Escape/Copy preserving source activation text, and no blind deletion or duplicate transport.
- Transport selection: choose a method before dispatch; no implicit second transport after an unconfirmed first dispatch.
- Clipboard coordination: newer user copy is never overwritten; failed snapshot does not destroy contents; later sessions cannot restore older data.
- Unicode round trips: BMP symbols, supplementary scalars, variation selectors, skin tones, ZWJ sequences, flags, keycaps, and combining marks.
- Search: a fixed corpus with independently chosen expected results, alias punctuation, code-point parsing, stable ranking, and cancellation of old queries.
- Persistence: first-run seeding, intentionally empty favourites, ordering, migration, unknown IDs, interrupted writes, and corrupt-file recovery.

Use a small native test harness for known AX fields and editing behaviour. UI tests should verify a few critical flows, not mirror every view implementation. Hosted CI can build and test pure logic; it cannot prove real multiple-display or TCC permission behaviour.

### 12.2 Manual acceptance matrix

| Priority | Scenario | Expected result |
| --- | --- | --- |
| P0 | Caret on display B; mouse on A | Picker appears beside the caret on B. |
| P0 | Caret unavailable; focused window on B; mouse on A | Picker uses B and a window/field fallback. |
| P0 | Left/above-primary and mixed Retina/non-Retina layouts | Picker coordinates and size remain correct, entirely within the chosen usable frame. |
| P0 | Caret near each display edge, Dock, or menu bar | Picker flips/clamps without disappearing or covering the insertion line unnecessarily. |
| P0 | Source app in full screen with independent display Spaces | Picker appears in the current context without a Space switch. |
| P0 | Escape or outside click | No document/clipboard change; typing resumes in the still-current source. |
| P0 | Selected text in the source | One insertion replaces the selected range; unrelated text and formatting remain intact. |
| P0 | Arrow, non-BMP emoji, skin tone, ZWJ, flag, and keycap fixtures | Exact complete strings are inserted; Undo behaves normally in supported apps. |
| P0 | Double Enter, Enter plus click, or held shortcut | At most one insertion or toggle transition occurs. |
| P0 | User changes app/window/field while picker is open | Session cancels or becomes copy-only; text is never sent to the new target. |
| P0 | Source quits, document closes, or AX element becomes stale | No insertion and no forced reactivation of an unrelated app. |
| P0 | Password/secure field or secure-input condition | Automatic insertion is unavailable; no source text is read. |
| P0 | Accessibility missing or revoked | Browse/Copy remains usable and enabling insertion has a clear recovery path. |
| P0 | User copies another item during a paste transaction | New clipboard contents are retained; old contents are not restored over them. |
| P0 | Slow/hung source app or late AX response | Charms stays responsive and late work cannot affect another session. |
| P0 | Type `::arrow` continuously at normal/high speed in an eligible field | Query is exactly `arrow`, regardless of the source/panel split; Enter replaces the tracked activation text with one arrow and leaves no trigger/query prefix behind. |
| P0 | Escape or Copy after typed invocation, including a slow focus handoff | The literal `::` and any source-side prefix remain exactly as typed; source text is not deleted or overwritten. |
| P0 | Marker edited/deleted, caret moved, or field replaced before commit | No blind Backspaces or insertion; stale typed session cancels or offers Copy. |
| P0 | Type `::` and switch apps during asynchronous capture/handoff | No late popup or insertion appears in the new app; returning does not revive the old session. |
| P0 | Press the shortcut during a first-colon or `::` candidate | One shortcut session opens, pending trigger work is invalidated, and literal source text remains intact. |
| P0 | Typed invocation in native rich text, browser contenteditable, and a custom-rendered editor | Exact range replacement works only where proven; insufficient AX support preserves source text and offers shortcut/Copy without guessing offsets. |
| P0 | Typed trigger disabled, paused, excluded, secure, or permission denied | No automatic popup or trigger processing; disabling/pausing removes the observer, and the configured shortcut remains usable where permitted. |
| P0 | Held Shift/Command/Option during selection | No synthetic release of physical keys and no dispatch to the panel or unintended receiver. |
| P1 | Display is unplugged, rearranged, or changes resolution | Session cancels/revalidates safely and the next invocation chooses the new correct display. |
| P1 | IME marked text and candidate selection | Search composition works and candidate Return/Escape does not insert/cancel prematurely. |
| P1 | `std::`, a pasted `::`, rapid repeats, U.S. and at least one non-U.S. colon layout, and another app's shortcode UI | Only confirmed eligible committed markers invoke Charms independent of physical key position; exclusions/boundaries prevent duplicate or unwanted handling. |
| P1 | Shortcut collision, changed layout, or PopChar still owning `⌃P` | Conflict is recoverable; recorder labels remain accurate and another shortcut can be chosen. |
| P1 | Keyboard-only use and VoiceOver | Search, selection, favourites, variants, insertion, Copy, and dismissal are reachable and named. |
| P1 | Relaunch, sleep/wake, denied login item, and corrupt preferences | Settings recover predictably; Charms remains launchable and quit-able. |

### 12.3 Real application coverage

Record app version, macOS version, input type, display configuration, placement source, insertion backend, selection replacement, Undo, and clipboard result. Start with:

- TextEdit plain text and rich text; Notes and Mail.
- Safari and Chrome native form inputs and textareas.
- At least one rich browser editor/contenteditable surface and Google Docs as a separate custom-rendered case.
- An Electron editor or messaging application, including VS Code if it is part of the user's workflow.
- Terminal and one remote-desktop/virtualized input context as explicit compatibility probes, not assumed supported contexts.

Check whether Electron needs its accessibility tree enabled through the documented accessibility mechanism. Do not infer that one successful Electron app or browser field establishes support for all editors. Publish limitations and Copy fallbacks with the tested matrix.

## 13. Performance and reliability budgets

These are initial engineering targets, to be measured and adjusted from a documented baseline rather than presented as existing claims:

| Measure | Target |
| --- | --- |
| Warm shortcut to usable picker | 95th percentile at or below 150 ms on a documented reference Mac. |
| Full-catalogue query to stable results | 95th percentile at or below 30 ms for ordinary queries; UI never blocks on catalogue generation. |
| Idle behaviour | No polling of document text or recurring network requests; no keyboard observer when `::` is off, and a negligible-cost observer when enabled. |
| Memory | Aim below 75 MB at idle; measure the actual catalogue/index cost before adding a database or cache hierarchy. |
| Error handling | Every capture/insertion failure terminates or degrades predictably; no indefinite spinner or retry loop. |

Preload or lazily prepare the immutable catalogue without delaying first keyboard use. Instruments should resolve real bottlenecks before adding caches or concurrency complexity.

## 14. Build, signing, and release operations

- Keep the bundle identifier and development signing identity stable before testing Accessibility; permissions can be sensitive to application identity and build changes.
- Document a predictable development installation/run path. Never automate granting TCC access or reset the user's permission database as a routine build step.
- Keep certificates, credentials, notarization material, and provisioning data outside the repository; use local Keychain or CI secret storage.
- Build without signing for ordinary CI checks where appropriate, and use a separate explicit signed release job.
- Add CI for a macOS build, meaningful unit tests, deterministic data validation, and release-artifact checks. Use currently available supported runner/toolchain versions when implementing it, rather than freezing guessed service versions in this plan.
- A signing identity/Apple Developer account is a release prerequisite, not a reason to block unsigned local prototyping.
- Document uninstalling/disabling launch at login, privacy behaviour, current compatibility, and how to recover insertion permission.
- Add automatic updates only after signing and release reproducibility work; assess a maintained updater separately if needed.

## 15. Decisions to record during implementation

The defaults above allow work to begin. Record evidence and adjust them at the relevant milestone:

| Decision | Evidence needed | When |
| --- | --- | --- |
| Minimum macOS version and Intel release support | Actual build/toolchain compatibility and available test machines. | M0/M1 |
| Nonactivating-panel/Spaces configuration | Real fullscreen, Stage Manager, separate-Spaces, and keyboard-focus behaviour. | M1 |
| Default insertion transport and per-app exceptions | Exact-string, selection, Undo, focus, and clipboard tests. | M1 |
| Typed-marker observer, permissions, and supported contexts | Committed-text proof, fast-typing handoff/order, bounded range replacement, IME/layout tests, and exclusion behaviour. | M1/M4 |
| Pasteboard restoration policy for supported apps | Demonstrated consumption/ownership behaviour and race tests. | M1/M4 |
| Unicode/CLDR baseline and missing-glyph policy | Rendering on the minimum OS plus catalogue/search fixtures. | M2 |
| Final cell size and keyboard navigation details | First-design review, increased text size, VoiceOver, and IME tests. | M3 |
| Public signing/release configuration | Supplied Developer ID and a clean-install test. | M5 |

Do not expand the main interface to solve rare compatibility problems. Keep special handling behind a clear fallback, an app-specific setting, or documented scope.

## 16. First implementation slice

The first pull request or implementation commit should contain only the project scaffold and the M1 native spike foundations: a menu-bar app, configurable shortcut, target snapshot, fixed-fixture picker, correct-screen placement, cancellation, and one insertion transport. Include the small pure tests and a recorded two-display manual check. Follow immediately with the small opt-in `::` feasibility spike, then build the shared catalogue/UI; both invocation methods belong in the first usable release.

Catalogue generation and a refined grid can proceed independently once their interfaces are defined, but the focus/placement/insertion state machine remains the critical path. Delegate bounded data, fixture, documentation, and visual tasks only after their expected outputs can be checked independently.

The first useful milestone is: **with the mouse on one monitor and the caret on another, press `⌃P`, choose `→` or `👩‍💻`, and continue typing in the original field; Escape cancels cleanly.**

## 17. Primary technical references

These references establish available platform/data capabilities. The placement, lifecycle, compatibility, and UX policies in this plan are engineering decisions that still require the tests above.

- [Apple: selected text range AX attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute).
- [Apple: bounds-for-range AX parameter](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute).
- [Apple: AX attribute queries and failure modes](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue).
- [Apple: Accessibility trust](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).
- [Apple: nonactivating panels](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel).
- [Apple: screen containing keyboard focus](https://developer.apple.com/documentation/appkit/nsscreen/main).
- [Apple: window collection behaviour](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct).
- [Apple: Unicode keyboard events and framework limitations](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29).
- [Apple: process-addressed event dispatch](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid%28_%3A%29).
- [Apple: preflight keyboard-listening access](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29).
- [Apple: request keyboard-listening access](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29).
- [Apple: pasteboard change count](https://developer.apple.com/documentation/appkit/nspasteboard/changecount).
- [Apple: login item service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp).
- [Electron: accessibility integration](https://www.electronjs.org/docs/latest/tutorial/accessibility).
- [Unicode Character Database](https://www.unicode.org/ucd/).
- [Unicode Emoji specification, UTS #51](https://www.unicode.org/reports/tr51/).
- [CLDR releases and downloads](https://cldr.unicode.org/index/downloads).
- [Unicode data/software license](https://www.unicode.org/license.txt).
