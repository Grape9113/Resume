# Current Resume specification

The authoritative current product specification is [Resume: current product baseline, September 2026](https://github.com/Grape9113/Resume/issues/2). It describes the intended existing product, including accepted evolution and explicitly tracked exceptions. Read it with [the reconciliation register](baseline.md), rather than interpreting its existence as proof of complete acceptance.

[The original build specification](https://github.com/Grape9113/Resume/issues/1) is closed historical work. Its body and implementation discussion are preserved; it no longer serves as an executable greenfield plan. Do not recreate those completed stories as tickets.

Product rules live in the current GitHub specification and later explicitly accepted amendments. The repository keeps [domain definitions](../CONTEXT.md), [architecture](architecture.md), [decisions](adr/), [verification evidence](testing.md) and [workflow guidance](workflow.md) separately. This file is an index, not a second copy of the spec.

## Accepted amendments

[Compact player, startup feedback and automatic pause synchronization](https://github.com/Grape9113/Resume/issues/11) replaces the baseline’s manual Force Push control with automatic pause synchronization and refines loading, focus, warning and layout behavior. Read this amendment alongside issue #2; unchanged baseline requirements still apply.

[Native Settings and conflict-only recovery](https://github.com/Grape9113/Resume/issues/12) supersedes the remaining Force Fetch/dropdown and single-panel Settings requirements. Settings uses the native window and standard Command-comma/app-menu command; version/build metadata lives there. Only unresolved material conflicts show player recovery choices; still-valid alternatives remain in Settings. Recovery verifies current server authority before accepting a choice, without autoplay or a manual force-write action. Execution is tracked by independent tickets [#13](https://github.com/Grape9113/Resume/issues/13) and [#14](https://github.com/Grape9113/Resume/issues/14).
