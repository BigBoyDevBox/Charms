# AGENTS.md

Guidance for AI coding agents working in the **Charms** repository.

## What Charms Is

Charms is a small macOS menu-bar utility for inserting arrows, symbols,
punctuation and emoji into the application you are typing in. Its defining
behaviour is placement: the picker opens on the display that holds the typing
focus, beside the text caret, and never on top of the line being typed, even
when the mouse is on another display. It opens with a global shortcut
(Control-P by default) or, optionally, by typing `::`.

The product and its reasoning live in [PLAN.md](PLAN.md); what has actually
been verified, and where, lives in [docs/compatibility.md](docs/compatibility.md).

## Tech Stack

- **Language:** Swift 6 toolchain (`swift-tools-version: 6.0`,
  `swiftLanguageModes: .v5`), macOS 14+ deployment.
- **Layout:** `Package.swift` at the root (no `.xcodeproj`):
  - `Sources/CharmsCore/`: pure logic with no AppKit. Catalogue and its file
    format, search, placement geometry, the session state table, typed-trigger
    recognition and handoff, insertion policy, preferences, favourites and
    recents. Everything testable lives here.
  - `Sources/Charms/`: the app. Status item, hot key, Accessibility capture,
    the picker panel, event posting, settings.
  - `Sources/CharmsCatalogBuilder/` and `Sources/CharmsCatalogTool/`: the
    development-time generator that turns the pinned Unicode and CLDR files
    under `Data/` into `Resources/catalog.txt`.
  - `Sources/CharmsHarness/`: a small text host and key driver used by
    `scripts/e2e.sh` to check the built app end to end.
- **Dependencies:** none. System frameworks only.

## Build & Test

```sh
swift build                               # the package
swift test                                # CharmsCoreTests, CharmsCatalogBuilderTests
swift run CharmsCatalogTool check         # the committed catalogue matches the pinned data
./scripts/build-app.sh                    # dist/Charms.app, ad-hoc signed (--debug, --universal)
CODE_SIGN_IDENTITY="Apple Development" ./scripts/build-app.sh   # keeps the Accessibility grant across rebuilds
./scripts/e2e.sh                          # drives dist/Charms.app with real keys against CharmsHarness
```

`scripts/e2e.sh` types on the real keyboard and screen for about a minute and
needs a terminal with the Accessibility permission; it exits 77 when it
cannot run. It is not part of CI. Run it after changes to the picker, the
session flow, insertion or the typed trigger. Three environment variables
exist for such checks: `CHARMS_HOME` moves all storage, preferences included,
into a directory of your choice; `CHARMS_SKIP_ONBOARDING` suppresses the
welcome window; `CHARMS_TRACE` writes each diagnostics entry to standard
error as it happens. The hidden-field question also needs the manual Electron
checks in `docs/compatibility.md`; the native harness does not emulate a
dormant accessibility tree.

`scripts/build.sh` / `scripts/release.sh` are thin stubs over the shared
`lkm-build` / `lkm-release` engines (the `release-tool` repo); the build engine
delegates assembly to `scripts/build-app.sh` via the `swiftpm` kind, which
also regenerates the icon via `scripts/make-icon.swift` from the committed
master, `assets/Charms-icon.png`. The master is the artwork in
`media-sources/icon.png` placed on the macOS icon grid; after replacing the
artwork, run `swift media-sources/icon.swift media-sources/icon.png
assets/Charms-icon.png` and commit the result. Releases are cut by tagging:
`scripts/release.sh X.Y.Z --push`. See `CICD.md`.

Note that `scripts/build.sh` reveals the built app in Finder. Automated
sessions should call `scripts/build-app.sh` directly.

## Conventions

- Standard Swift API Design Guidelines; one main type per file.
- Keep `CharmsCore` free of AppKit. A decision that can be made from plain
  values (rectangles, key observations, strings) belongs there with a test;
  the app layer gathers the values and carries out the result.
- Comments explain *why*. Where a rule comes from a measurement, the comment
  says what was measured.
- The session state table (`SessionMachine`) is the single authority on what
  the picker may do next. The app reports events to it and performs the
  effects it returns; it does not keep a second notion of state.

## Critical Constraints

- **Never insert into the wrong place.** Text is dispatched once, to the
  process and field captured when the picker opened, after revalidation. Any
  doubt turns into an explicit Copy. There is no retry and no second transport
  after a dispatch.
- **Escape changes nothing.** Cancelling leaves the document, the clipboard,
  recents, and a typed `::` exactly as they were.
- **Strings are exact.** An entry is identified by its scalar sequence.
  Swift's `String ==` treats canonically equivalent text as equal (U+212B and
  U+00C5); use `ExactString` / `isExactly` wherever identity matters. Never
  add or strip variation selectors, joiners or modifiers.
- **Accessibility offsets are UTF-16.** Never use Swift character counts as
  ranges in another application's text.
- **Privacy.** No network access. No stored queries, typed text, document
  contents, window titles or clipboard contents. The diagnostics log has no
  free-text field on purpose. The `::` observer exists only while the user
  has switched it on, and keeps one candidate colon and a bounded query
  prefix, nothing else.
- **Shortcuts are key positions, labels are layout-dependent.** Do not
  hard-code ANSI key codes for commands such as Paste; resolve them through
  the active layout.
- **The catalogue is generated.** Do not edit `Resources/catalog.txt` by
  hand. Change `Data/aliases.tsv`, `Data/extras.tsv` or the builder, run
  `swift run CharmsCatalogTool generate`, and commit the result; CI fails when
  the committed file differs from a fresh build.
- **Bundle id is `ch.lkmc.Charms`.** Keep it and `NSHumanReadableCopyright`
  ("Public domain (Unlicense)") consistent with `LICENSE`; `ci.yml` asserts
  both. The Accessibility grant is tied to the bundle id and signature.

## Do / Don't

- **Do** update `README.md`, `AGENTS.md`, `PLAN.md` and `docs/compatibility.md`
  when behaviour, verified compatibility or workflows change.
- **Do** record what was verified and on which system; say "unverified" for
  what was not.
- **Don't** add third-party dependencies; system frameworks only.
- **Don't** commit signing credentials or provisioning profiles.
- **Don't** add controls to the picker for rare cases. Special handling goes
  behind a fallback, a per-application setting, or documented scope.
- **Don't** automate granting privacy permissions or reset the permission
  database as a build step.

<!-- shared-rules:start -->

## Working practices

- Follow explicit task instructions over the default workflow below.
- Writing the code is not finishing the task. A task is finished when
  its changes are merged to main through a PR that passed CI and review,
  or when the user explicitly accepts a different end state.
- Start every task on current code. Fetch first, then cut the task
  branch from origin/main — never from a stale local branch or an old
  checkout. To continue existing work, rebase or merge the latest
  origin/main into it before editing. Never overwrite existing work to
  update.
- Resolve ambiguity before making consequential changes. State low-risk
  assumptions; ask when scope, safety, or expected behavior is unclear.
- Keep changes focused. Do not modify unrelated code, formatting, or comments.
- Prefer surgical edits over whole-file rewrites when the result is equivalent.
- Stage only intended files. Inspect the diff before committing.

## Communication

- Be concise, factual, and direct. Preserve necessary context and uncertainty.
- Avoid praise, motivational filler, emojis, and em dashes in new prose.
- Address the reader directly in user-facing copy.
- Report what was verified and what remains unverified. Never imply that an
  unavailable check passed.

## Code design

- Prefer early returns and shallow nesting. Separate logical blocks with
  blank lines.
- Use descriptive constants or enums for meaningful or repeated values.
  Use existing standard definitions for protocol/specification constants.
  Keep obvious, one-off values inline.
- Use enums for behavioral modes that would otherwise require ambiguous
  boolean arguments.
- Default members to private. Widen visibility only for required consumers,
  and review the change as an API design decision.
- Follow the repository's declared dependency boundaries. UI and controllers
  must use application services rather than directly accessing databases,
  subprocesses, sockets, or other low-level mechanisms.
- Encapsulate low-level mechanics behind domain-oriented interfaces.
- Reuse genuinely shared logic. Avoid speculative abstractions and layers
  that only forward calls.
- Prefer pure functions for business rules and immutable data where practical.
  Isolate side effects; document non-obvious state ownership or synchronization.
- Explain non-obvious intent, constraints, and tradeoffs in comments.
  Do not narrate obvious code. Add examples or diagrams when they clarify it.

## Validation and errors

- Validate untrusted input at entry points. Where practical, represent valid
  states in types and enforce persistent invariants in database schemas.
- Represent absence and failure explicitly.
- Use assertions for internal programming invariants, not external-input
  validation or required runtime error handling.
- Prefer explicit, actionable errors over silent failure or undocumented
  fallback. Document intentional recovery behavior.
- Never report a skipped or failed operation as successful.

## Bug fixes

1. Identify the root cause and define an observable success criterion.
2. Add a regression test and observe the relevant failure before fixing it.
3. Implement the fix and observe the test passing.
4. Check surrounding behavior for regressions and architectural consistency.

If an automated regression test is impractical, document the reproduction
and verification procedure. State any inability to reproduce the failure.

## Verification

- Run relevant tests and lint after changes.
- Choose coverage by affected behavior and risk, not patch size.
- Use integration or end-to-end tests for critical workflows and boundaries;
  test isolated business rules at the lowest effective level.
- Run broader suites for cross-cutting or high-risk changes, and the full
  required release checks before releasing.
- Validate the requested command, options, platform, and configuration.
  Unrelated green CI is not proof that the reported problem is fixed.
- Recheck after the final edit. Distinguish local checks from CI results.

## Commit messages

- Use a capitalized, imperative subject without a final period.
- Target 50 characters; never exceed 72.
- Separate the subject and body with one blank line.
- Wrap body text at 72 characters.
- Explain what changed and why. Leave implementation mechanics to the code.

## Implementation and review

Unless explicitly instructed otherwise:

1. Work on a focused branch cut from the latest origin/main and open a PR
   against main before reporting the task as done.
2. Inspect CI results and completed review feedback for the latest commit.
   A successful reviewer job does not mean the review found no problems.
3. Address important findings or explain why they do not apply. Handle minor
   findings according to the stopping rules below.
4. Evaluate each fix in the surrounding project, add regression coverage,
   and rerun affected checks before pushing.
5. Repeat until a stopping criterion is met.
6. Merge without asking again once the stopping criterion is met, required
   checks pass on the latest commit, and no unresolved blockers or required
   human review requests remain.

### Reviewer context limits

The automated PR reviewer does not see the user's original prompt or
conversation. It may suggest changes that go against or beyond what the
user asked for. Do not implement such suggestions. Note each conflict and
report it to the user at the end of the thread.

### Automated review stopping rules

Judge findings by verified impact, not the reviewer's severity label.
Important findings concern correctness, security, data loss, broken builds,
or materially degraded behavior/performance.

Track completed review rounds and consecutive rounds without important
findings. Reruns of the same revision and integration failures do not count.

- No applicable actionable feedback: finish immediately.
- First minor-only round: optionally fix worthwhile, low-risk findings.
  Do not manufacture another push merely to obtain another review.
- Two consecutive rounds without important findings: stop responding to
  automated nitpicks, even if actionable minor suggestions remain.
  Defer worthwhile leftovers rather than continuing the cycle.
- A confirmed important finding resets the minor-only streak. Address it
  and verify the fix before continuing.

After ten completed rounds, enter stabilization:

- Stop optional cleanup, refactoring, and nitpick fixes.
- One completed review without confirmed important findings is sufficient
  to finish, even if minor suggestions remain.
- Continue only for confirmed important defects. If resolving them stalls,
  report the blockers rather than continuing indefinitely.

These limits end optional automated-feedback work. They do not waive
confirmed blockers, unresolved human review requests, or required checks.

### Reviewer integration failures

After two consecutive reviewer-integration failures, stop and report the
review gap. Do not treat failures as approval. An explicit user instruction
may waive review; report that waiver rather than claiming review passed.

## Ending a task

- A task ends with its changes merged to main — not with code written,
  and not with a PR merely opened. An open PR is work in progress:
  monitor CI on the latest commit, address review findings per the
  stopping rules, and merge once the criteria are met.
- Never finish with uncommitted changes or unpushed commits in the
  worktree. Commit, push, and open or update the PR first.
- If a step is impossible (missing push access, CI failure, reviewer
  outage), report the exact blocker instead. Never present unreviewed or
  unmerged work as finished.
- Before finishing, confirm: the requested behavior is implemented
  without unrelated changes; relevant checks pass on the latest code;
  important review findings are addressed or rejected with reasons;
  deferred suggestions, remaining risks, and validation gaps are
  disclosed.
- The final response states where the work stands: branch, PR, CI
  status, review rounds completed, and whether it is merged.

<!-- shared-rules:end -->
