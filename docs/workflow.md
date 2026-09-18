# Resume's development workflow

Use the installed `.agents/skills/*/SKILL.md` files as the process authority. [The baseline](baseline.md) records the existing product; it is not a request to rebuild it. GitHub Issues remains the tracker, with the default [triage labels](agents/triage-labels.md) and [single-context domain layout](agents/domain.md).

## Artifact authority

| Question | Source |
| --- | --- |
| What is the intended current product? | [Current specification](specification.md), the authoritative GitHub baseline issue it links, and later explicitly accepted amendments. |
| What do domain terms mean? | [CONTEXT.md](../CONTEXT.md), a glossary only. |
| Why retain a consequential architectural choice? | Accepted [ADRs](adr/); supersede an ADR explicitly when a decision changes. |
| How is the current implementation arranged? | [Architecture](architecture.md) and the build/source configuration it points to. |
| What does verification actually establish? | [Testing](testing.md), dated runs, and the tests' actual production paths. |
| What remains to do? | Open GitHub tickets. [The reconciliation register](baseline.md#remaining-discrepancies) explains the initial evidence and links those tickets; ticket state is authoritative. |
| What happened before the baseline? | Closed original issue, commits and [reconciliation history](baseline.md). Historical completion claims are dated evidence, not current acceptance certificates. |
| What improved the agent environment? | [The retrospective](retrospectives/2026-09-18-workflow-recovery.md), with enacted guidance distinguished from recommendations. |

## Normal loop

1. **Recover context.** Read the current spec, relevant open ticket, glossary and applicable ADRs. Check the baseline register before interpreting a known discrepancy as intended behavior.
2. **`grill-with-docs` when decisions are unresolved.** Inspect implementation/tests/history for facts first. Ask the user about genuine decisions, preserving their answers in the appropriate artifact. Keep the glossary free of policy and implementation detail; use ADRs sparingly for consequential trade-offs.
3. **`to-spec` for an accepted change.** Synthesize the agreed behavior and testing seams; publish to GitHub. Name the current baseline and affected requirements so a later reader can tell what changes. A changed implementation alone is not proof of a changed product decision.
4. **`to-tickets` for remaining execution.** Check that work is not already implemented. Propose complete, narrow slices and genuine blocking edges, obtain the skill's required breakdown confirmation, then publish. Independent work has no invented dependency. A closed baseline spec is a reference, not a new implementation queue.
5. **`implement` one ready ticket in a fresh context.** Use `tdd` at agreed seams, run appropriate checks, then `code-review` and commit as that skill directs. Investigation and manual-acceptance tickets have their own deliverables; they are not permission for an unspecified redesign.
6. **`code-review` against a pinned fixed point.** Keep Standards and Spec reviews separate as the skill requires. Review current product intent and declared exceptions, not an obsolete greenfield description. Include the documentation/amendment and verification evidence with the change.
7. **Close the ticket on evidence.** Record what changed and what was verified. If a deliberate behavior change was accepted, reconcile the specification and affected durable docs in the same work. Preserve historical issue discussion; add a supersession link instead of rewriting history as though it never happened.
8. **`retro` where the run exposed environmental friction.** Prefer a missing navigation pointer or useful verification rule over a long always-loaded instruction list. Record proposals as proposals until adopted.

Raw incoming requests use `triage`; tickets already produced through `to-tickets` do not need a second triage pass. `wayfinder` is for a genuinely unresolved multi-session decision effort, not for restarting discovery of this existing product. `implement-spec`, prototypes and architecture refactors are optional workflows for future authorized work, not part of this re-baseline.

## Reconciling a difference

Use five distinct classifications: accepted evolution, requirement-preserving fix, implementation detail, stale artifact, or unresolved/suspicious behavior. Cite the evidence. Put a confirmed product decision in the spec; a source-layout fact in architecture; a domain definition in the glossary; executable remaining work in a ticket. Flag an unresolved contradiction rather than changing either the app or its intended contract to make the discrepancy disappear.

The existing seams remain application behavior, concrete integration adapters and the panel. A fake player's success does not establish real media startup; a value-model test does not establish the shipped application. Exact chunk sizes, score weights, fixture thresholds and file layouts do not become product requirements merely because a test observes them.

## Checkpoint provenance

This recovery began at `fcab5aa` with substantial pre-existing application/test/build changes. The documentation audit reviewed its own delta against the saved starting working tree; it did not certify the pre-existing code diff. The user subsequently authorized a deliberate checkpoint: `d1f721a` preserves the application/build/test state, and the following documentation commit records the reconciled baseline. Start future branches from that documentation checkpoint or its descendants so they include both parts. Open tickets remain remaining work, not part of this checkpoint.
