# Open questions

Decisions the plan needs from its owner before the affected work can be
designed or validated. Each entry names what it blocks and the answer
that unblocks it, so a reply can be dropped straight in.

## §8.1 Catalogue coverage vs. the §13 memory budget

- **Question**: Should the catalogue include every assigned graphic character, or a curated subset — arrows, symbols, punctuation, and complete emoji sequences?
- **Blocks**: M2 (catalogue generation, loader, and index design).
- **Why it blocks**: §8.1 mandates "assigned graphic characters and useful whitespace/punctuation, plus complete recommended emoji sequences", which is roughly 150,000 entries once names, aliases, and search tokens are attached. §13 budgets "below 75 MB at idle" and §1 calls the app "small". The plan sets no coverage count, no size target, and no rule for what happens when the measured index cost exceeds the budget — it only says to measure before adding a database.
- **Answer that unblocks**: The intended coverage, an approximate entry count, and a decision rule for exceeding the budget (narrow coverage, move the index off the heap, or revise the budget).

## §4.4 Typed `::` trigger when insertion access is unavailable

- **Question**: When Accessibility access is missing or revoked — including the Browse and Copy choice made at onboarding — should Settings refuse to enable the typed trigger, or allow it and degrade every typed invocation to browse/copy with the marker left in place?
- **Blocks**: The §4.4 onboarding and Settings copy, and the M4 trigger work.
- **Why it blocks**: The plan grants Input Monitoring for the trigger and keeps the shortcut path usable when it is denied, but never covers the case where recognition works and insertion does not. The trigger's only purpose is to replace the marker (§7.6), so without a decision an implementer can ship a session that opens, implies it will insert, and then cannot.
- **Answer that unblocks**: "Refuse" or "degrade", plus the one-line explanation Settings should show.
