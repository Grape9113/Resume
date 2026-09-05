# Domain Docs

How engineering skills consume Resume’s domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Applicable ADRs under `docs/adr/`.

If an expected file does not exist, proceed silently. The domain-modeling workflow creates glossary and decision records lazily.

## File structure

Resume is a single-context repository:

```text
/
├── CONTEXT.md
├── docs/adr/
└── Sources/
```

## Use the glossary’s vocabulary

Use terms as defined in `CONTEXT.md` in issues, specifications, tests, and code. Avoid synonyms that the glossary explicitly rejects.

If a needed domain concept is absent, reconsider whether it belongs or note the gap for the domain-modeling workflow.

## Flag ADR conflicts

Surface any contradiction with an existing ADR explicitly instead of silently overriding it.
