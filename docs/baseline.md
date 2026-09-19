# Resume baseline — 18 September 2026

This is a documentation/workflow recovery of the existing product, not a release or redesign. The authoritative [current specification](specification.md) replaces the baseline role of the original closed build ticket. Application sources, tests, resources and build configuration remain unchanged by this recovery.

## Scope and provenance

The starting point is `fcab5aa551ab87b32c9d07282afd6b3f626f0056` plus the working tree at the start of this task. The user explicitly approved that fixed point for a documentation-only review. The working tree already contained the Xcode migration, behavioral fixes, native adapter tests and UI tests discussed below; they are evidence, not this task's implementation diff.

Evidence examined: the complete body and two comments of [the original issue](https://github.com/Grape9113/Resume/issues/1); all seven ordinary branch commits; current production sources and tests; project/scheme, resources and package resolution; repository guidance, glossary and testing notes; and this session's prior playback diagnosis and user reports. There were no existing ADRs or separate child-ticket backlog. Installed skills came from `mattpocock/skills` as recorded in `skills-lock.json`; their local `SKILL.md` files were read directly.

No new live-account acceptance is claimed. [Testing notes](testing.md) retain dated automated results and their limits. Historical reports of 14/25 passing tests and `.build/Resume.app` remain historical, not instructions for the current project.

## Reconciliation of completed work

| Area and evidence | Classification | Baseline disposition |
| --- | --- | --- |
| Native single-panel app, local Search, deliberate playback/navigation, one Connection/library; initial `311ecda` and original issue | Existing settled product | Preserve; no new discovery or rebuild ticket. |
| Shared Xcode project, scheme, local run instructions; working-tree removal of root package/build scripts | Accepted build evolution | Xcode is the current build entry point; old `.build` instructions are superseded. Minimum deployment target is not a support promise. |
| Server hostname normalization and PikaPods `www.` correction; `ServerAddress` and authentication tests | Accepted usability evolution | Capture forgiving HTTPS setup, retaining the same server/account scope and secure-scheme restriction. |
| Panel version/build/time identity; current README and panel | Accepted visible addition | Capture its purpose, not exact formatting or timestamp implementation. |
| Position recovery in the synchronization menu; original detailed decisions, current panel, `fcab5aa` | Reconcile stale overview | A temporary menu choice, not a separate panel/history mode. Selecting a position suspends automatic writes. |
| Actual `AppModel` tests, real native playback/artwork tests, Debug panel host | Requirement-preserving verification improvement | Record the real seams; older helper tests and the host do not prove full product integration. |
| Startup cancellation, prior-session close on selection, paused reconnect, server-derived start and ending replay exception | Requirement-preserving fixes | Preserve explicit playing intent and intended positions. No new autoplay policy. |
| Pending-aware wake, changed-baseline suspension even for small differences, paused external progress, replay completion reset, recovery expiry on ordinary resume | Requirement-preserving fixes | Preserve server authority, recovery and completion policy. Exact verified paths are distinguished from open race/timing questions. |
| Rotating-token concurrency, late 401 reuse, correct token envelopes, reliable Keychain errors | Requirement-preserving fixes | Retain secure session rebuilding. Client success does not establish UI recovery in every caller. |
| Incremental media loading, cancellation and two artwork concurrency fixes; prior red reproductions and native regressions | Requirement-preserving fixes | Preserve responsive preparation and safe system callbacks. Chunk size, pixel cap and fixture timing thresholds are implementation details. |
| Process-local server-session ID rather than the old persistence prescription | Stale implementation description | Document actual lifetime. No new session-persistence feature is authorized or needed merely to mirror that old prescription. |
| JSON schema details, scoring constants, UUID generations, synchronization cadence, exact panel width | Implementation details | Keep in code; describe only architectural consequences where useful. Do not promote them into user stories. |
| Universal completion-epoch knowledge, broad acceptance assertions and idealized test dependencies | Stale/overstated claims | Qualify explicitly; preserve intended policy and record what still requires evidence or a decision. |

### Historical completion ledger

| Evidence | Completed scope |
| --- | --- |
| `311ecda` | Initial native client, domain glossary, workflow configuration and policy tests. |
| `3a4e55d` | Authentication/playback safeguards. |
| `f6c42e3`, `fa74cd4` | Playback persistence/integration and session closure. |
| `32888cf` | Synchronization, streaming, persistence and lifecycle hardening. |
| `41c823d`, `fcab5aa` | Search/output/recovery corrections and explicit recovery write suspension. |
| Pre-existing working tree at recovery start | Xcode migration, application/native/UI regression coverage, later correctness fixes and playback/artwork diagnosis. Already implemented; preserved separately, not recreated as work. |

Issue #1 stays closed. Its early progress comment's remaining-work list was followed by later commits and closure; it is not a live backlog. The new baseline issue is a reference to completed reconciliation. Open follow-ups below describe only unresolved evidence or actual remaining behavior.

## Product-to-evidence audit

| Product family | Production path | Verification evidence and limit |
| --- | --- | --- |
| One panel and keyboard modes | `ResumeApp`, `ResumePanel`, `SearchInput`, `AppModel` | Four panel UI tests cover selected interactions in an isolated host; real menu-bar lifecycle and wider accessibility are pending. |
| Local credible Search | `LibrarySearch`, client index conversion | Query normalization/relevance/recency/weak-match tests; large real-library performance and metadata completeness remain open. |
| Connection and automatic session recovery | `ServerAddress`, `AudiobookshelfClient`, `KeychainStore`, `AppModel` | Real HTTP fixture tests cover token envelopes, concurrent renewal and rejected saved passwords; not every UI entry point or deployed server. |
| Playback intent, book selection and navigation | `AppModel`, `AudioPlayer` | Controlled-model regressions plus native AVPlayer startup/seek/advancing-time tests; unresolved async paths are not covered by those successes. |
| Read-only Book progress and per-book speed | `ResumePanel`, `AppModel`, `AudioPlayer` | Pointer/Space UI tests, state tests and paused-rate adapter test; accessibility adjustment needs native acceptance. |
| Server authority and recovery | `SynchronizationState`, `AppModel`, `PlaybackLedger` | Baseline/suspension, pending wake, explicit controls, distinct alternatives and expiry tests; repeated-conflict expiry and real multi-client races remain open. |
| Recently finished | `CompletionPolicy`, `AppModel`, ledger | 95% boundaries, paused seeks, replay/reset policy tests; historical completion time and overdue reconciliation scheduling remain uncertain. |
| Persistence, sign-out and artwork | Local-state/Keychain/artwork adapters and model | Sign-out/cache and concurrent decoding tests; real Keychain authorization, freshness and storage growth remain qualified. |
| Native integrations and resource behavior | `SystemMonitor`, socket client, Now Playing, login item | Selected callbacks tested; hardware, private account, HLS, idle/library-scale behavior and system UI are not certified. |

## Remaining discrepancies

These are deliberately **not canonized**. Static observations are not labelled reproduced production failures. Ticket bodies carry the executable next step; this register preserves why the discrepancy was raised.

| ID | Evidence and unresolved point | Remaining ticket |
| --- | --- | --- |
| R1 | Guards exist around some asynchronous operations, but restore/tick/close/completion/chapter/artwork paths are not uniformly book/Connection-scoped. A cancelled server start can lose the returned session identity; quit/final-close cancellation needs deadline evidence. | [Audit stale playback work across book and Connection changes](https://github.com/Grape9113/Resume/issues/3) |
| R2 | Only restoration specifically routes `authenticationRequired` into Connection; Play, Force Fetch/Push and other callers often surface generic errors. This does not supersede the intended inline recovery rule. | [Restore inline credential recovery during normal use](https://github.com/Grape9113/Resume/issues/4) |
| R3 | First seeing an already-finished book uses its latest server update as an epoch, not a proven original completion time. Overdue resets are checked at selected lifecycle opportunities, not every synchronization event. The original five-day policy stays intended; fallback/scheduling semantics need resolution. | [Resolve completion epoch and overdue-reset semantics](https://github.com/Grape9113/Resume/issues/5) |
| R4 | Repeated suspended playback checks can renew the one-hour recovery expiry even without a newly distinct ambiguity. The existing ordinary pause/resume test does not settle this case. | [Keep recovery expiry tied to a new ambiguity](https://github.com/Grape9113/Resume/issues/6) |
| R5 | Range requests are bounded but a server returning HTTP 200 can still cause full-response buffering. WAV fixtures do not prove authenticated HLS, broad codec coverage, live session/socket contracts or many-part startup performance. Media URL validation checks host/scheme, not full origin/port. | [Verify authenticated media and server-session interoperability](https://github.com/Grape9113/Resume/issues/7) |
| R6 | Real menu-bar focus/dismissal, setup-mode Escape/Settings transitions, native media commands, sleep/output changes, login items, input methods and assistive technologies are not covered by the isolated host. | [Complete native Mac acceptance on the supported environment](https://github.com/Grape9113/Resume/issues/8) |
| R7 | Missing revision data becomes the string `0`, bypassing the artwork store's nil-only freshness fallback. Old revision files have no eviction beyond sign-out. Stale covers/unbounded growth are not accepted policy. | [Verify artwork freshness when revision data is absent](https://github.com/Grape9113/Resume/issues/9) |
| R8 | The index uses one unpaged `limit=0` enumeration and no separate subtitle/alias fields. Whether the deployed server/library makes this incomplete or costly requires evidence; no deliberate exclusion was found. | [Reconcile library enumeration and Search metadata coverage](https://github.com/Grape9113/Resume/issues/10) |

The intended policy and current implementation therefore are not identical in every edge case. The baseline makes these differences explicit; “re-baselined” means future work has an accurate contract and an honest frontier, not a claim of a defect-free app.

### Subsequent scope reconciliation

Accepted amendments [#11](https://github.com/Grape9113/Resume/issues/11) and [#12](https://github.com/Grape9113/Resume/issues/12) supersede the historical manual synchronization controls, recovery-menu placement and single-panel Settings behavior above. Pause synchronization is automatic; conflict choices are conditional in Player and retained in native Settings. Force Fetch/Push are removed, so R2 must not recreate or test those obsolete entry points. Current behavior and verification are indexed by [the specification](specification.md) and [testing record](testing.md); the original register remains dated evidence for the broader open follow-ups.

## Recovery scope and review

Used `grill-with-docs` with its `grilling`/`domain-modeling` primitives under the user's evidence-first recovery instruction; `to-spec`; `to-tickets`; two-axis `code-review`; and `retro`/`writing-for-agents`. `ask-matt` and `codebase-design` informed routing and vocabulary. Inspected `implement`, `implement-spec`, `triage`, `wayfinder`, `setup-matt-pocock-skills`, `tdd` and `improve-codebase-architecture`; none authorized feature work or an opportunistic refactor here.

The final audit reviews only this recovery's documentation/tracker delta against the approved starting snapshot. Existing application changes are inspected as evidence but remain outside that diff. A source/test/resource/project hash comparison checks that this task preserved the working product. See [workflow](workflow.md) before taking a remaining ticket.

## Final consistency audit

| Axis | Result |
| --- | --- |
| Current product behavior | Production paths were inspected against the starting working tree; no application behavior was intentionally changed. Accepted evolution and static suspicions are separated above. |
| Tests | Existing 56 core/four UI test functions and dated runs are verification evidence, with fake/native/manual limits retained. No tests were added or changed during this documentation pass. |
| Specification | Current GitHub baseline replaces the greenfield role of issue #1; intended policies remain distinct from known exceptions and tuning details. |
| Durable documentation | Glossary, actual architecture, four reconstructed accepted ADRs, workflow authority and retrospective have distinct roles. Local links resolve. |
| Tickets | Eight native child issues of the current baseline describe actual remaining work. R3 is decision-gated, R6 human-led, and there are no invented ticket dependencies. Historical implementation stays completed. |

Source/test/resource/project/installed-skill hashes match the saved starting snapshot, and non-documentation git status is identical. `git diff --check` passes. No build or native acceptance was rerun for this documentation-only change; prior dated evidence is retained without relabelling it as a new run.

There are no unexplained documentation contradictions identified by this audit. The eight registered discrepancies remain open product/evidence questions; this is not a certification that the runtime has no defects. At audit completion the working tree was uncommitted. The subsequent user-authorized checkpoint records the unchanged application work in `d1f721a` and this documentation delta in the following commit. Future development starts from both commits; see [checkpoint provenance](workflow.md#checkpoint-provenance).

## Standards

No actionable findings in the documentation/workflow delta against `fcab5aa` plus the approved saved starting working tree. Pre-existing application, test and build changes were excluded from this review.

- `AGENTS.md` uses conditional navigation pointers, consistent with `writing-for-agents`. Product authority remains the GitHub specification; the local specification file is an index rather than a competing copy.
- `CONTEXT.md` now follows `domain-modeling` and `CONTEXT-FORMAT.md`: short domain definitions and discouraged synonyms, with numeric policy and implementation prescriptions removed. The four sequential ADRs use the installed concise format and identify their historical provenance and trade-offs.
- The current specification follows `to-spec` sections and separates behavior, implementation decisions, evidence and exclusions. Its long story list is required by that skill rather than unnecessary document expansion.
- The eight ticket drafts follow `to-tickets`, reference their parent, provide verifiable deliverables and declare blocking edges. R3 explicitly gates behavior changes on a decision; R6 identifies human acceptance. Investigation tickets avoid granting open-ended redesign authority. Approved label exceptions remain explicit.
- The retrospective follows the installed environmental-improvement categories, orders candidates by severity and separates enacted guidance from recommendations and historical work.
- Cross-document overlaps provide navigation, historical evidence or qualified summaries; they do not establish competing product authorities. I found no actionable Fowler-baseline heuristic in this documentation-only change. Runtime refactor smells are outside scope.

Result: **0 documented-standard violations; 0 actionable heuristic findings.** This review does not certify unverified runtime behavior or the pre-existing code diff.

## Spec

**No findings in the documentation/workflow delta.** Reviewed against the user's re-baseline request, using `fcab5aa` plus the saved starting working tree; pre-existing application changes were excluded.

- “Do not intentionally change current product behavior”: the reviewed delta is documentation and workflow artifacts; source/test/build preservation was separately hash-verified by the coordinating agent.
- “An authoritative current specification matching the intended current product”: issue #2 owns product intent, with `docs/specification.md` as an index. The baseline explicitly qualifies incomplete implementation/verification rather than claiming universal compliance.
- “Completed historical work marked appropriately rather than recreated as new work”: issue #1 and ordinary commits remain historical evidence. Accepted Xcode migration, hostname entry, build identity and existing corrective work are reconciled without recreating their implementation tickets.
- “Suspicious or accidental behavior ... flagged rather than canonized”: the eight discrepancy entries distinguish evidence from static risks. Tickets #3–#10 describe investigation, bounded corrections or acceptance; the completion decision and native environment acceptance appropriately require maintainer/human involvement.
- “Tests understood as verification evidence”: architecture and testing guidance identify the actual AppModel/native-adapter seams, distinguish unused helper tests and the isolated UI host, and avoid turning fixture budgets into product guarantees.
- Durable knowledge, ADRs, product specification, executable tickets and retrospective lessons have explicit separate authority. The installed workflow is preserved, including stopping before remaining-ticket implementation.

Remaining runtime discrepancies are deliberately recorded in the baseline and tickets; they are not defects introduced by this documentation pass. Final baseline closure/history annotations were subsequently completed.

Review totals: Standards — 0 findings, no worst issue; Spec — 0 findings, no worst issue. These are independent documentation-review outcomes, not a review of the pre-existing implementation diff.
