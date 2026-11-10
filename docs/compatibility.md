# Compatibility

What has been checked, on which system, and how. Anything not listed under
"Verified" is unverified, whatever the code intends.

## Verified

One system so far, on 10 November 2026:

| | |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Hardware | Mac Studio, Apple M4 Max |
| Toolchain | Xcode 27.2, Swift 6.4.2 |
| Displays | One 1920 x 1080 display at scale 1, plus a virtual second display to its left for the two-display checks. "Displays have separate Spaces" off. |
| Keyboard | Swiss German layout |
| Build | `scripts/build-app.sh`, release configuration, signed with an Apple Development identity |

### How

- **Automated:** `swift test` (331 tests) and `swift run CharmsCatalogTool check`.
- **End to end:** `scripts/e2e.sh` drives the built app with real key and
  mouse events against the `CharmsHarness` window (an `NSTextView`, an
  `NSTextField` and an `NSSecureTextField`) and compares the text that
  arrives, scalar for scalar. All 22 scenarios passed.
- **By hand:** the built app in the applications below, driven with the same
  synthetic keys, with screenshots and the app's own trace (`CHARMS_TRACE`).

### End-to-end scenarios

| Scenario | What it shows |
| --- | --- |
| `insert` | Control-P, a query, Return: the character arrives; the clipboard's change count is untouched; one Undo removes it. |
| `escape` | Escape leaves the text and the clipboard alone and returns the keyboard to the source. |
| `replace_selection` | A selection in the source is replaced by the character. |
| `sequence` | A joined emoji sequence (technologist, U+1F9D1 U+200D U+1F4BB) arrives exactly. |
| `navigate` | Arrow keys act on the results from the first press. |
| `first_selected` | Control-P and Return, with nothing typed: the first favourite arrives. |
| `copy` | Command-Return copies and inserts nothing. |
| `placement` | The picker window is at the caret and does not cover the caret's line. |
| `click_cell`, `click_outside` | A click on a cell inserts it; a click elsewhere cancels and changes nothing. |
| `cancel_while_held` | Escape pressed while Return is still down: the picker stays until Return is released, then closes without inserting. |
| `typed_trigger`, `typed_trigger_fast` | `::arrow` and Return replace the colons and the query, also when typed with 6 ms between keys. |
| `typed_trigger_first_selected` | `::`, Tab and Return replace the colons with the first favourite. |
| `typed_trigger_late_selection` | A field that applies a selection made through Accessibility 30 ms after the call, as Chromium does: the colons are still replaced. |
| `typed_trigger_focus_moves_during_selection` | While such a late selection is on its way, another field of the same application takes the keyboard: nothing is sent, and that field stays empty. |
| `typed_trigger_selection_refused` | A field that accepts that call and never honours it: nothing is sent, the picker offers Copy, and Escape leaves the colons. |
| `typed_trigger_escape` | Escape after `::ar` leaves `::` as typed. |
| `colons_inside_a_word` | `std::cout` does not open the picker. |
| `password_field` | In a password field nothing is sent; Return copies. |
| `paste_backend` | For a listed application the character arrives by Paste and the previous clipboard is put back. |
| `pass_through` | For a listed application Control-P reaches that application and Charms stays closed. |

### Applications

| Application | Field | Placement | Insertion |
| --- | --- | --- | --- |
| TextEdit 1.21 | Plain text document | Beside the caret, below; above when there is no room below | Unicode events. One Undo. Selection replaced. Paste fallback also works, clipboard restored. |
| TextEdit, full screen | Same | The picker appears in the full-screen Space and takes the keyboard | Same |
| Safari 27.0.1 | `<textarea>` | Below the caret with one guard line (the caret's line could not be confirmed from a neighbouring character) | Unicode events |
| Safari 27.0.1 | `<input type="text">` | At the end of the selection | Selection replaced |
| Safari 27.0.1 | `contenteditable` element | Beside the caret | Joined emoji sequence exact |
| Safari 27.0.1 | `<input type="password">` | Under the field | Copy only, as intended |
| Safari 27.0.1 | `<textarea>`, typed `::` | Below the caret | `::`, Tab and Return replace the colons |
| Electron 45.2.3 with its accessibility tree on | `<textarea>`, `<input type="text">`, `contenteditable` element | Beside the caret | Typed `::` with a name: the colons and the name are replaced in all three. Shortcut in the `<textarea>`: Unicode events. |
| Electron 45.2.3 with its accessibility tree off | `<textarea>` | Over its window | Copy only: the application reports no focused field. Typed `::` does nothing. |
| Terminal 2.15 | zsh prompt | Beside the cursor, estimated from the previous character | Unicode events |
| An application without a text field in front | | Over its window | Copy only |

### Displays

With TextEdit on the second display (to the left of the main one, so at
negative coordinates) and the pointer on the main display, the picker opened
on the second display beside the caret, and insertion worked. The second
display was a virtual one.

### Permission

Started through Launch Services with no permission, Charms showed the welcome
window; "Browse and Copy" gave a working copy-only picker placed over the
active window. "Enable Insertion" showed the system prompt, whose button
opened System Settings at the list (named Device Control and Data Access on
macOS 27, Accessibility before). After switching Charms on there, the welcome
window reported it by itself, and both the shortcut and the typed `::`
worked without a relaunch and with no other permission. Input Monitoring is
not needed.

### Other

- The status menu, the settings window and its four tabs; recording a new
  shortcut (Control-Option-P took effect at once, the old one was released)
  and resetting it.
- Favourites (Command-D), recents, and their storage across relaunches.
- "Open Charms at login", with an ad-hoc signed build in the Applications
  folder. Before its first registration the system reports the login item
  as "not found"; the switch is usable in that state. Switching it on
  registered the item (shown as enabled by `sfltool dumpbtm`), switching it
  off disabled it again.
- Another application coming to the front while the picker is open cancels
  the session and nothing is inserted. (Seen repeatedly: other processes on
  the test machine kept activating themselves.)

### Timings

Release build, Apple M4 Max, macOS 27.0.1.

| | |
| --- | --- |
| Shortcut to picker on screen | 2 to 17 ms (reading the focused field: 1 to 14 ms) |
| Catalogue load at launch | about 60 ms, off the main thread (43,548 entries) |
| Search, per keystroke | median 0.2 ms, 95th percentile 3.6 ms, worst case about 27 ms for a single common letter |

## Not verified

- **macOS 14, 15 and 26.** The deployment target is macOS 14 and CI builds
  with Xcode 26 on macOS 26, but the app has only been run on macOS 27.
- **Intel Macs.** Release builds are universal; the Intel half has not been
  run.
- **Chrome and real Electron applications** (VS Code, Slack and the like),
  **Firefox**, **Microsoft Office**, **JetBrains** IDEs. None was installed.
  Electron was tried only as a bare Electron 45 window showing a test page.
  An Electron application keeps its accessibility tree off until an
  assistive tool asks for it; while it is off Charms sees no field there
  and offers Copy only. Charms does not switch it on.
- **Notes, Mail, Messages, Pages.** Left alone on the test machine so as not
  to write into real data.
- **The typed `::`** outside TextEdit, the harness, a Safari `<textarea>`
  and the Electron test page. It is off by default and off in terminals,
  editors and password managers.
- **Input methods** (Japanese, Chinese, Korean). The `::` observer is
  suspended while one is composing and the picker's search field does not act
  on Return during composition; both have code and unit tests only.
- **"Displays have separate Spaces" switched on, Stage Manager, a real second
  display, mixed scale factors, vertical arrangements.** Placement geometry
  for these is covered by unit tests only.
- **Light appearance, increased contrast, larger text, VoiceOver.** Cells
  carry names, values and traits; nobody has listened to them.
- **PopChar or another utility on the same shortcut.** The first to register
  wins; what Charms shows when it is second (a message in Settings) was not
  exercised.
- **Starting at login.** The login item registers and unregisters, but
  nobody has logged out and in again to see Charms start. A login item that
  waits for approval in System Settings, and a copy that macOS runs from a
  temporary location (opened straight from Downloads or the disk image),
  have code and unit tests only.
- **A downloaded release**, its Gatekeeper prompt, and the pasteboard privacy
  behaviour of an app started that way.
- **Secure input switched on by another application** (some password
  managers and terminals do this) while Charms is used elsewhere.
- **Skin-tone variants by hand.** The preference, the per-cell menu and the
  fallback to the base emoji have unit tests; the menu was not opened.
- **Sleep, display changes and permission revocation during an open
  picker.** Each cancels the session in code; only the application-change
  case was seen.
