# Final plan review before implementation

Reviewed: 10 November 2026

This is the last review of `PLAN.md` before the application is built. It had three inputs: independent research into the problem, a native spike on the development machine, and three independent reviews of the plan against that evidence. The plan was then edited once; this note records what changed and why.

## Requirements, restated from research

The owner uses PopChar daily, opens it with Control-P, and has two complaints: the window does not appear on the display where they are typing, and the interface is more complex than the job needs. Research into PopChar, the macOS Character Viewer, Rocket, and several open-source pickers and text tools led to the same requirements the plan already had, with a sharper order of importance:

1. **Placement is the product.** The picker opens on the display that holds the typing focus, beside the caret, and never on top of the line being typed. PopChar 11.0, released the day before this review, added a compact grid-only view and names the receiving app on its Insert button, which addresses complexity; its documentation says nothing about which display the window opens on. Placement is therefore still the reason for Charms to exist.
2. **One small surface.** A search field, a grid, a one-line footer. No font chooser, category bar, or output-format controls.
3. **Insert once into the field the user left, or do not insert.** Anything uncertain becomes an explicit Copy.
4. **Keyboard first.** Shortcut, type a familiar word, Return. Favourites and recents before any query.
5. **Typed `::` as an opt-in second way in**, without leaving the marker behind.
6. **Local and quiet.** No network, no account, no stored queries, only the permission insertion needs.
7. **Built like the owner's other Mac apps**, so the shared scripts, workflows, and habits apply.

## What the spike measured

Machine: macOS 27.0.1, Apple Silicon, one physical display plus a virtual second display, Swiss German keyboard layout. Source application: TextEdit. These are results from one machine, written into the plan as such.

| Question | Result |
| --- | --- |
| Can the caret be located quickly? | A complete Accessibility capture took 7 to 10 ms. |
| Is the caret rectangle trustworthy? | No. The rectangle for a zero-length range is one line too high (caret after a character at y 109 reported at y 96, both 13 points tall). Rectangles of real characters are correct. |
| Can a panel take the keyboard without activating Charms? | Yes. A borderless nonactivating panel at floating level became key about 10 ms after the hot key; the source stayed frontmost and no activation notification fired. |
| Does focus come back by itself? | Yes. After `orderOut` the source's focused element was the captured one within 3 ms, with no activation call. |
| Do Unicode keyboard events insert complete strings? | Yes, through `postToPid` and the HID tap alike: arrow, non-BMP emoji, skin tone, ZWJ sequence, flag, keycap, variation-selector emoji, tag-sequence flag. Strings of 21, 40, and 64 UTF-16 units arrived whole. A selection was replaced. One Undo removed exactly the insertion. No delay was needed after `orderOut`. |
| Is a fixed key code for Paste or Undo safe? | No. On the Swiss German layout the positions ANSI calls Y and Z are swapped; a posted Command with position 6 did not undo. |
| Can `::arrow` typed without a pause be reconciled? | Yes. A global key monitor reports exactly the keys delivered to other applications, and the panel's own event stream receives the rest. At 2 ms key gaps the source got `::arro` and the panel got `w`, and the two streams said so. |
| Can the marker position be computed from the caret when a key is observed? | No. The monitor fires before the source applies the key; at 15 ms gaps the computed start was off by one and would have removed a space. The position has to be read back from the settled source text. |
| Can multi-display behaviour be tested with one monitor? | Yes, with a virtual display created through the system's private `CGVirtualDisplay` classes, as development tooling only. |
| Which emoji does the system draw? | macOS 27.0.1 renders Emoji 17; the pinned data is Emoji 18. Asking a font for glyphs of the code points is not a sufficient check, and neither is counting glyphs: a supported mixed-skin-tone couple is drawn as two overlaid glyphs. The advance width of the laid-out line separates the cases: one emoji wide when supported, several when the sequence falls apart. |

Data releases found current and pinned: Unicode 18.0.0, Emoji 18.0, CLDR 49. CLDR annotates every emoji but only 367 other symbols.

## Changes made to the plan

- **Project setup (§2, §5, §11, §14, §16).** The plan prescribed a checked-in Xcode project with a UI-test target and a signed, notarized release. Every other Mac app of the owner is a Swift package with a pure core library, shared build and release scripts, shared CI, release, and review workflows, and ad-hoc signed universal releases. The plan now follows that setup. Developer ID signing and notarization are deferred until an account exists, and the documentation must state the Gatekeeper step that implies.
- **Caret geometry (§6.1, §6.3).** The plan treated an adjacent-character probe as optional and warned against it. With the measured one-line error it is required, in a form that stays safe: an adjacent character corrects the line only when it demonstrably meets the caret horizontally, and otherwise one extra line is kept clear.
- **Panel and focus (§6.4).** Candidate configurations became the measured starting configuration, and the activation calls became exceptions.
- **Transport (§7.3).** "The spike compares" became the decision: one Unicode key event pair to the source process by default; Paste only for applications the user lists, sent through the layout's real Command-V key; Accessibility text replacement not used.
- **Typed trigger (§2, §4.4, §5, §7.5, §7.6).** The observer is an `NSEvent` global key-down monitor, which Apple documents as available to a process trusted for accessibility, instead of an event tap needing Input Monitoring. Attribution is by delivery channel and position by read-back. Recognition is suspended while an input method is the active input source.
- **Catalogue (§8.1, §8.3, §4.3).** Releases pinned; `emoji-test.txt` is the single emoji source; emoji support is decided on the running system by a layout check; curated aliases are acknowledged as the main route to symbols; tie-breaking is fully defined.
- **Keyboard and settings (§4.2 to §4.4, §9).** Tab, Up from search, and the surfaces for reordering and variants are now concrete. Right at the end of the query moves into the results. Control-Return opens the selected cell's menu. The separate "pause" state for `::` is gone: one stored switch, shown in Settings and in the menu.
- **Decisions (§15).** The table of evidence still needed became a table of outcomes with their evidence, followed by what the finished app still has to show.

## Reviewer proposals

Three reviewers read the plan against the evidence, each with a different lens: consistency with the evidence, fit to the requirements, and whether it can be built in the shared setup. They agreed on the project setup, the release pipeline, the caret correction, the transport, and the observer.

Accepted beyond those: explicit aliases for `arrow`, `check`, and `nbsp`; a defined tie-break; a concrete Tab order and "Up from search does nothing"; context-menu surfaces for reordering and variants; a disabled `::` switch that explains itself while insertion is off; merging pause into the one switch.

Declined:

- **A fixed, non-editable exclusion list.** The list is a guess about someone else's applications; a wrong guess needs a way out that is not a new release.
- **Dropping the per-app shortcut pass-through.** Control-P is "previous line" in every shell and Emacs-style field, the list is empty by default, and it costs one settings row.
- **Dropping the preferred skin tone.** One menu, and without it every skin-toned emoji takes a detour through the cell's menu.
- **Dropping clipboard restoration from the paste backend.** Restoration stays best effort and guarded by the change count, and is skipped where reading the clipboard would prompt.

## Not verified, and recorded as such

No Chromium browser, Electron app, Intel Mac, or system older than macOS 27 was available. "Displays have separate Spaces" is off on the development machine and changing it needs a logout. The spike ran from a shell that was already trusted, so the claim that Accessibility alone covers the key monitor rests on Apple's documentation until the installed app confirms it. These rows stay open in §15 and go into `docs/compatibility.md` with their reason rather than being assumed to pass.
