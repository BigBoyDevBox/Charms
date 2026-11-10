# Typed-trigger literal boundary proposal

Status: deferred design proposal from [PR #9](https://github.com/L-K-M/Charms/pull/9),
retained during the integration of the remaining planning PRs on 10 November
2026. The active trigger grammar in [PLAN.md](../../PLAN.md) is unchanged.

## Proposal

Suppress automatic invocation when `::` begins a valid IPv6 literal, such as
`::1` or `::ffff:192.0.2.1`, or a CSS pseudo-element such as `::before` or
`::after`, including at the beginning of a field or after whitespace.

## Why it remains deferred

At the second colon, `::arrow`, `::before` and an IPv6 literal have the same
prefix. A rule based only on preceding text cannot classify characters that
have not been typed yet. Also, `::a` and `::b` are valid IPv6 forms, contrary
to the original PR's description. Numeric and code-point queries must remain
usable rather than being suppressed as presumed literals.

A future design would need a different activation or continuation policy,
with tests for literal constructs, valid symbol queries, fast typing,
editing and cancellation. If that design writes picker-side text back into
the source, it also needs the separate
[literal-recovery design](typed-trigger-escape-proposal.md).

## Current behavior

The trigger uses a conservative preceding boundary, application exclusions
and an explicit off switch. It does not promise future-text classification.
`std::` inside a word does not invoke the picker, and code editors and
terminals are excluded by default. Escape is non-writing; picker-only query
text is not restored to the source. The shortcut remains available when the
typed trigger is off.
