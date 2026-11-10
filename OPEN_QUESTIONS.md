# Plan questions and resolutions

These questions were raised before implementation in PRs #39 and #69. They are
retained as design history, not unresolved release prerequisites. The
original estimates and permission assumptions below are historical; the
current contract is in [PLAN.md](PLAN.md), and verified behavior is in
[docs/compatibility.md](docs/compatibility.md).

Related deferred proposals are retained separately:
[typed-trigger literal boundaries](docs/reviews/typed-trigger-boundary-proposal.md)
and [Escape recovery](docs/reviews/typed-trigger-escape-proposal.md).

## §8.1 Catalogue coverage vs. the §13 memory budget

**Resolved, 10 November 2026:** PLAN §8 defines coverage and representation;
the pinned catalogue contains 43,548 entries. Memory is a measured target
that can be revised with evidence (PLAN §13), not a prerequisite for owner
approval before catalogue work.

Original question:

- **Question**: Should the catalogue include every assigned graphic character, or a curated subset — arrows, symbols, punctuation, and complete emoji sequences?
- **Blocks**: M2 (catalogue generation, loader, and index design).
- **Why it blocks**: §8.1 mandates "assigned graphic characters and useful whitespace/punctuation, plus complete recommended emoji sequences", which is roughly 150,000 entries once names, aliases, and search tokens are attached. §13 budgets "below 75 MB at idle" and §1 calls the app "small". The plan sets no coverage count, no size target, and no rule for what happens when the measured index cost exceeds the budget — it only says to measure before adding a database.
- **Answer that unblocks**: The intended coverage, an approximate entry count, and a decision rule for exceeding the budget (narrow coverage, move the index off the heap, or revise the budget).

## §4.4 Typed `::` trigger when insertion access is unavailable

**Resolved, 10 November 2026:** Refuse to enable the typed trigger until
Accessibility and insertion are available. Settings explains how to enable
insertion; shortcut and menu-bar Browse and Copy remain usable. The observer
is removed if access is revoked. Input Monitoring is not required by the
implemented backend.

Original question:

- **Question**: When Accessibility access is missing or revoked — including the Browse and Copy choice made at onboarding — should Settings refuse to enable the typed trigger, or allow it and degrade every typed invocation to browse/copy with the marker left in place?
- **Blocks**: The §4.4 onboarding and Settings copy, and the M4 trigger work.
- **Why it blocks**: The plan grants Input Monitoring for the trigger and keeps the shortcut path usable when it is denied, but never covers the case where recognition works and insertion does not. The trigger's only purpose is to replace the marker (§7.6), so without a decision an implementer can ship a session that opens, implies it will insert, and then cannot.
- **Answer that unblocks**: "Refuse" or "degrade", plus the one-line explanation Settings should show.

## §2 Scope and §16 First implementation slice — is the `::` trigger a v1 requirement?

**Resolved, 10 November 2026:** The user requested both invocation methods.
The typed trigger is implemented for the first release, off until enabled.
Its description as unrequested in the original question is incorrect.

Original question:

- **Question**: Should the optional `::` typed trigger remain in the first usable release, or be deferred until the core (global shortcut, focus-aware placement, insertion) is proven and shipped?
- **Blocks**: The first-release scope decision — §2's included list and §16's "both invocation methods belong in the first usable release" cannot be safely committed or dropped without this answer.
- **Why it blocks**: The author asked for a streamlined, user-friendly PopChar; the `::` trigger is an unrequested input method with the plan's highest feasibility risk (the fast-typing handoff in §7.6). §16 commits both invocation methods to the first usable release, and M1 schedules the `::` spike before the catalogue/UI. If the spike fails, the first-release scope is unclear.
- **Answer that unblocks**: "Keep `::` as written", or "defer `::` to a fast-follow release after the core is proven", with the resulting §2/§16 wording.

## §7.6 Release decision when reconciliation fails

**Resolved for the implemented release, 10 November 2026:** The native spike
and fast-typing tests demonstrated reconciliation in the verified contexts.
Unsupported or unconfirmed fields are left untouched; the shortcut retains
Browse and Copy. This hypothetical failure is not an unresolved owner
prerequisite. Compatibility gaps remain explicit in the compatibility notes.

Original question:

- **Question**: If reconciliation proves unachievable and no revised design passes before release, what is the release decision?
- **Blocks**: The same §2/§16 wording change; the outcome determines what the first usable release contains.
- **Why it blocks**: "Revise the trigger design explicitly before release" defines a process, not the outcome when no design passes.
- **Answer that unblocks**: Release without `::`; ship a pause-before-open variant; or hold release until a design passes.

## §2 Deferred — font-based glyph browsing

**Resolved, 10 November 2026:** Name/code-point search and the compact grid
remain the first-release scope. Font inspection and private-use glyph
browsing remain deferred under PLAN §2.

Original question:

- **Question**: Does the user's PopChar workflow depend on browsing the glyphs of the current font, or is search-by-name/code-point sufficient?
- **Blocks**: The decision to keep font inspection deferred past the first usable release.
- **Why it blocks**: PopChar's primary interface is a font-based glyph grid; the plan replaces it with a Unicode/emoji catalogue and defers font inspection entirely. If the user relies on font-specific glyphs (ligatures, alternates, private-use glyphs), the first release would not replace PopChar for their workflow.
- **Answer that unblocks**: Confirm whether the user's day-to-day use is name/code-point search (defer font inspection) or font-grid browsing (pull font inspection forward).

## §7.6 Replace the marker without guessing — event attribution

**Resolved, 10 November 2026:** The global key monitor observes input
delivered to the source, and the picker receives its own input locally.
`TriggerHandoff` tracks that split and verifies the bounded UTF-16 source
prefix through Accessibility before replacement. Unit fixtures and the
`typed_trigger_fast` end-to-end scenario cover ordering and reconciliation;
PLAN §7.6 and the compatibility notes record the limits.

Original question:

- **Question**: What is the concrete mechanism for attributing candidate query events to the source field versus the picker during the fast-typing handoff?
- **Blocks**: The M1 `::arrow` handoff feasibility test.
- **Why it blocks**: A `CGEvent` tap callback does not identify the receiving app or field; the plan's "ordering/target evidence" is unspecified. The reconciliation strategy depends on whether the tap can observe focus changes or must rely entirely on AX reads after the fact.
- **Answer that unblocks**: Confirm the event-attribution mechanism (for example, a focus-change observer plus AX reconciliation, or a documented limitation) and the test that proves no characters are dropped or duplicated.
