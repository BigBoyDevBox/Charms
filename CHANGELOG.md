# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The picker: a compact grid with search, favourites, recents and a footer
  naming the selected character, opened with a configurable global shortcut
  (Control-P by default) or from the menu bar.
- Placement beside the text cursor on the display that holds the typing
  focus, with fallbacks to the focused field, the focused window, and the
  pointer's display. The picker never covers the line being typed.
- Insertion of the chosen character into the field the picker was opened
  from, sent once after the field has been checked again; Copy whenever that
  field cannot be confirmed.
- Optional `::` trigger: type two colons and a name, press Return, and the
  typed text is replaced by the character.
- Search over Unicode 18.0 characters and Emoji 18.0 by name, CLDR 49
  keyword, curated alias, literal character and code point, with skin-tone
  variants and a preferred tone.
- Settings for the shortcut, launch at login, skin tone, the typed trigger
  and its excluded applications, applications that keep the shortcut, and
  applications that receive characters by Paste.
- First-launch explanation of the Accessibility permission with a
  browse-and-copy alternative, and a content-free diagnostics export.
- Project scaffold in the shared setup: Swift package, build and release
  scripts, CI, tag-driven releases, automated PR review, Dependabot.
