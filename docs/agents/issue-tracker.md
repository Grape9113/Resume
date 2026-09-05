# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` or `gh issue edit <number> --remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

Infer the repository from `git remote -v`; `gh` does this automatically inside this clone.

## Pull requests as a triage surface

**PRs as a request surface: no.**

When set to `yes`, PRs run through the same labels and states as issues using the `gh pr` equivalents. GitHub shares one number space across issues and PRs, so resolve a bare issue number with `gh pr view` and fall back to `gh issue view`.

## When a skill says “publish to the issue tracker”

Create a GitHub issue.

## When a skill says “fetch the relevant ticket”

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The map is one issue with child issues as tickets.

- **Map**: create an issue labelled `wayfinder:map` containing Notes, Decisions-so-far, and Fog.
- **Child ticket**: link an issue as a GitHub sub-issue. If sub-issues are unavailable, put it in the map’s task list and add `Part of #<map>` to the child. Use a `wayfinder:<type>` label.
- **Blocking**: use GitHub’s native issue dependencies. If unavailable, add a `Blocked by: #<n>` line to the child.
- **Frontier**: choose the first open, unassigned child with no open blocker.
- **Claim**: assign the issue to the authenticated user.
- **Resolve**: comment with the answer, close the child, and append its context pointer to the map.
