# Typed-trigger Escape recovery proposal

Status: deferred design proposal from [PR #53](https://github.com/L-K-M/Charms/pull/53),
retained during the integration of the remaining planning PRs on 10 November
2026. This is not the implemented cancellation contract.

## Proposal

After a typed `::` invocation, Escape would return the picker-side query to
the source so the source held the complete literal query, independent of the
source/picker focus-transfer split. The proposed write would happen once,
only after the handoff settled and the original field validated.

The motivation remains useful: without literal recovery, Escape can leave
`::`, `::a` or a longer prefix depending on how much typing reached the
source before the picker took focus.

## Why it remains deferred

Appending picker-side text cannot handle an edited query. If the source
already holds `::ar` and the user changes `arrow` to `cat` in the picker,
appending a remainder cannot produce `::cat` while preserving existing
source text. Backspace, selection replacement and pasted query edits need
defined semantics before an implementation is safe.

A future literal-recovery action must define those semantics and its
content-changing commit boundary, wait for held keys to be released,
revalidate the exact UTF-16 source range, and specify Undo and stale-target
outcomes. An uncertain dispatch must not be retried through another
transport. It cannot be described as ordinary, non-writing cancellation.

## Current behavior

Escape changes neither the document nor the clipboard. The colons and any
query prefix delivered to the source remain there; query text received only
by the picker is not written back. Explicit Copy also leaves the source
alone. [PLAN.md](../../PLAN.md), [README.md](../../README.md) and
[the compatibility notes](../compatibility.md) remain authoritative.
