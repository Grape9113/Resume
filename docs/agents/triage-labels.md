# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to GitHub labels in this repository.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a canonical role, use its corresponding tracker label.

Category roles use the installed skill's literal labels: `bug` for broken existing behavior and `enhancement` for an improvement. A triaged issue has one category and one state. Manual environment acceptance can be `ready-for-human`; an unresolved product decision is `needs-info`, not silently agent-ready. A completed baseline/specification record is closed reference material, not an open execution ticket.
