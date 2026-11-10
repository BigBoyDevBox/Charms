# Implementation-plan PR review

Reviewed: 10 November 2026

Reviewed the 40 open PR heads captured for this pass against planning baseline `d238759`. Integrated 36 of them with the corrections below. PRs #9 (`f15fbb60`), #39 (`98e18d52`), #53 (`83fcb476`), and #69 (`40b813f5`) remain unmerged. The accepted PR commits are retained in merge history; overlapping paragraphs were reconciled together before publication.

The product remains Charms, with the user's first compact-grid design, a configurable Control-P shortcut, and an opt-in `::` trigger. Both invocation methods remain in the first usable release. No native application has been implemented or compatibility result established by this documentation review.

## Important decisions

- Keep Escape non-writing. The proposed literal-query write-back does not yet define query editing, source-prefix replacement, failure, and release-wait semantics sufficiently to change that contract safely.
- Do not promise that an initial `::` can be classified using future CSS/IPv6 text. Numeric/code-point queries remain valid. Context exclusions and a conservative boundary reduce accidental invocation; they do not eliminate every ambiguous literal prefix.
- Separate the core native spike (M1) from typed-trigger feasibility (M1b). A failed experiment requires an explicit revised design, not silently dropping a requested feature or blocking the scaffold on an owner questionnaire.
- Require the public capabilities used by each insertion backend. Typed observation is disabled without its global prerequisites; Browse and Copy remains available.
- Treat the first document-content mutation, injected input dispatch, or clipboard-content write as the commit boundary; guarded reversible focus/selection preparation is excluded. After it, uncertainty cannot be relabelled as a cancellation that changed nothing, and there is no automatic second-transport retry.
- Make key/button/modifier release bounded and deterministic. Timeout clears the pending activation, keeps browsing while valid, and requires a fresh activation.

## Disposition by PR

"Corrected" includes conflict resolution and edits made in the integration correction commit; it does not mean the submitted wording was accepted unchanged.

| PR | Disposition | Review result |
| --- | --- | --- |
| [9](https://github.com/L-K-M/Charms/pull/9) | Not merged | Future IPv6/CSS classification is not possible when the initial marker is recognized; `::a` and `::b` are also valid IPv6 forms. Keep the ambiguity explicit rather than adding the proposed guarantee. |
| [12](https://github.com/L-K-M/Charms/pull/12) | Merged | Names valid hot-key, AX observer, workspace, and secure-input mechanisms. Secure-input state supplements field classification. |
| [14](https://github.com/L-K-M/Charms/pull/14) | Merged | Accessibility and permission outcomes belong in the success criteria. |
| [33](https://github.com/L-K-M/Charms/pull/33) | Merged, corrected | Retained design context; removed false claims that Character Viewer cannot insert or keep favourites, Rocket cannot search/select, and browser pickers universally require a mouse. Grounded positioning in the user's actual preferences. |
| [34](https://github.com/L-K-M/Charms/pull/34) | Merged, corrected | X is unchanged between the stated global spaces; reflect Y around the primary full frame. A correctly anchored global transform works with negative/above-primary coordinates. Kept full-frame and round-trip tests. |
| [35](https://github.com/L-K-M/Charms/pull/35) | Merged, corrected | Kept single-step Undo and complete-sequence fixtures; removed the unproven prescription to suppress intervening key-up events. |
| [36](https://github.com/L-K-M/Charms/pull/36) | Merged, reconciled | Aligned recorder/Copy prerequisites, milestone exits, architecture coverage, release documentation, notarization, and reproducibility claims. |
| [37](https://github.com/L-K-M/Charms/pull/37) | Merged, corrected | Chose one permission policy rather than contradictory alternatives: no typed observer without required global AX/listening/backend capabilities. |
| [38](https://github.com/L-K-M/Charms/pull/38) | Merged | Defined partial final rows and explicit Reset Favourites semantics. |
| [39](https://github.com/L-K-M/Charms/pull/39) | Not merged | Permission policy is resolved in the plan; catalogue memory is a measured engineering target, not an owner-input blocker. Its duplicated grid/reset changes are already covered by #38. |
| [40](https://github.com/L-K-M/Charms/pull/40) | Merged, corrected | Kept accessory lifecycle and guarded focus restoration. Panel collection flags are tested candidates; permission rechecks also occur on invocation, not solely app activation. |
| [41](https://github.com/L-K-M/Charms/pull/41) | Merged, reconciled | Made source/pointer/display capture concrete and combined secure detection with copy-only behaviour. Current session key state is not proof of hardware provenance. |
| [42](https://github.com/L-K-M/Charms/pull/42) | Merged, corrected | Kept discoverable Copy. Browser chrome identification is a per-browser capability; Unicode presentation properties do not authorize generic variation-selector synthesis. |
| [43](https://github.com/L-K-M/Charms/pull/43) | Merged, corrected | Test the lowest sufficient ordinary/floating panel level and Spaces policy first; screen-saver level is not the normal picker recipe. |
| [44](https://github.com/L-K-M/Charms/pull/44) | Merged, reconciled | Introduced a distinct M1b gate without silently making the requested trigger expendable. |
| [45](https://github.com/L-K-M/Charms/pull/45) | Merged, reconciled | Kept editorial/reference improvements; replaced overlapping diagrams with one authoritative state table and clarified interactive test environments. |
| [46](https://github.com/L-K-M/Charms/pull/46) | Merged, corrected | Kept derived annotations, qualification/version data, exact sequences, useful tokens, and extra fixtures. Corrected overbroad CLDR claims, removed an unsupported repertoire percentage, chose compact direct lookup for algorithmic ranges, and avoided a single-glyph support guarantee. |
| [47](https://github.com/L-K-M/Charms/pull/47) | Merged, corrected | Adjacent-character edges are not a general caret algorithm at wrap/RTL/grapheme boundaries. Kept only proven geometry probes, conditional window-list fallback, first-invocation tests, and no new Screen Recording requirement. |
| [48](https://github.com/L-K-M/Charms/pull/48) | Merged, corrected | Kept bounded AX replacement as an optional tested transport and clipboard privacy/history probes. Removed an undocumented numerical string limit and universal no-focus promise; validated effective Command layouts and advisory clipboard markers. |
| [49](https://github.com/L-K-M/Charms/pull/49) | Merged, corrected | Added handoff/release/copy states and a commit boundary; failures do not claim cancellation after a write. Copy-only browsing remains a visible state only when it will not steal focus. |
| [50](https://github.com/L-K-M/Charms/pull/50) | Merged, corrected | Kept whitespace boundary, reset cases, early Enter, and per-app focus/selection ordering. Removed digit rejection and automatic false-trigger write-back; queued Enter is bound to its exact query generation. |
| [51](https://github.com/L-K-M/Charms/pull/51) | Merged, corrected | Defined activation, empty-query Down, copy-only primary action, and recorder behaviour; unregistrable shortcuts retain the previous working binding. |
| [52](https://github.com/L-K-M/Charms/pull/52) | Merged, reconciled | Excluded Charms' own UI as a target, defined secure/no-target Copy mode, and unified the one-second release timeout. |
| [53](https://github.com/L-K-M/Charms/pull/53) | Not merged | Appending picker-side text cannot restore an edited query correctly when the source-derived prefix was changed. It also changes Escape into a source write without a complete recovery/Undo/failure transaction and conflicts with the blanket cancellation contract. The UX concern remains a native-spike evaluation item. |
| [54](https://github.com/L-K-M/Charms/pull/54) | Merged, corrected | Kept shortcut-binding disclosure, optional pass-through, Intel horizon, and stable signing advice. Pass-through is opt-in; no promise of re-registration before every next key, and no paid identity prerequisite for local prototypes. |
| [55](https://github.com/L-K-M/Charms/pull/55) | Merged, corrected | Kept local `NSTextInputClient.hasMarkedText()`/IME routing tests. Removed `kAXMarkedTextRangeAttribute`, which is absent from the public SDK, and its unsupported generic target-side query. |
| [56](https://github.com/L-K-M/Charms/pull/56) | Merged, corrected | Kept styling/shadow checks and actual VoiceOver tests. Provider notifications describe Charms' own focus; they are not commands to move VoiceOver or restore a foreign AX element. |
| [57](https://github.com/L-K-M/Charms/pull/57) | Merged, corrected | Kept duplicate-open, capture cancellation, lifecycle, and Login Items recovery. Enumeration is not atomic ownership; no reliance on an undocumented lock-notification string as a guaranteed public API. |
| [58](https://github.com/L-K-M/Charms/pull/58) | Merged, corrected | Kept runtime layout refresh/reset. `UCKeyTranslate` updates caller-owned state, not another app's active dead-key buffer; translation remains subordinate to committed-source verification. |
| [59](https://github.com/L-K-M/Charms/pull/59) | Merged, corrected | Added public posting-access preflight/request checks. Correct PID posting is `event.postToPid(pid)`; avoid private TCC identifiers and permission assumptions across transports. |
| [60](https://github.com/L-K-M/Charms/pull/60) | Merged, corrected | Display reconfiguration and active-Space changes use distinct notifications. |
| [61](https://github.com/L-K-M/Charms/pull/61) | Merged, reconciled | Added stable, non-translocated installation guidance and a clean-account test, normally from `/Applications`. |
| [62](https://github.com/L-K-M/Charms/pull/62) | Merged | Bare hex queries do not outrank exact name/alias matches; explicit `U+` lookup remains unambiguous. |
| [63](https://github.com/L-K-M/Charms/pull/63) | Merged, corrected | Capture/revalidate the external field before menu tracking; status-item interaction does not universally activate Charms, and an old cached target is not sufficient. |
| [64](https://github.com/L-K-M/Charms/pull/64) | Merged, reconciled | Kept grid Copy, persistent pause, bounded AX messaging, and one-time clipboard restoration. Consolidated outcome/recents semantics without claiming delivery acknowledgement. |
| [65](https://github.com/L-K-M/Charms/pull/65) | Merged | Added a secondary user-initiated local diagnostics export with no content or automatic upload. |
| [66](https://github.com/L-K-M/Charms/pull/66) | Merged, reconciled | Documented retained release assets/checksums and downgrade data-schema/backup limitations. |
| [67](https://github.com/L-K-M/Charms/pull/67) | Merged, reconciled | One deterministic held-key/modifier timeout, consistent across the state table, transport rules, and acceptance matrix. |
| [68](https://github.com/L-K-M/Charms/pull/68) | Merged, reconciled | First PR is the M0 scaffold, followed by separately reviewable M1 work and M1b, rather than a large scaffold-plus-spike change. |
| [69](https://github.com/L-K-M/Charms/pull/69) | Not merged | Its claim that `::` was unrequested contradicts the user's explicit request; font browsing was already scoped out for arrows/symbols/emoji. Kept event-attribution uncertainty as an M1b experiment, not an unanswered owner prerequisite. Duplicated questions/definitions are covered elsewhere. |

## Verification and limits

- Read every submitted diff and checked the integrated plan after overlap resolution.
- Compared questionable API claims with public SDK headers for AX attributes/coordinate conventions, CoreGraphics posting APIs, accessibility provider notifications, Text Input Services translation state, workspace notifications, and Login Items APIs.
- Verified representative bare-hex examples and reviewed the Unicode/CLDR data contract against primary documentation.
- Checked Markdown structure, whitespace, references for rejected/nonexistent API instructions, expected requirement coverage, and Git ancestry of every accepted reviewed head.
- No application code exists yet, so no native build, cross-app insertion, display, TCC, IME, or VoiceOver compatibility result is claimed. Those remain implementation acceptance work.

Primary references are in [PLAN.md](../../PLAN.md#17-primary-technical-references). Competitive facts were checked against [Apple's Character Viewer guide](https://support.apple.com/en-jo/guide/mac-help/mchlp1560) and [Rocket's own feature page](https://matthewpalmer.net/rocket/). SDK findings refer to public declarations in `AXAttributeConstants.h`, `CGEvent.h`/`CoreGraphics.apinotes`, `NSAccessibility.h`, `UnicodeUtilities.h`, `NSWorkspace.h`, and `SMAppService.h`.
