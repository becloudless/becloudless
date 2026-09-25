# Instructions for AI coding agents

## Code quality

- While implementing a change, always look for opportunities to refactor
  surrounding code to simplify it and improve quality (remove duplication,
  reduce indirection, clarify naming). Prefer small, safe refactors that keep
  behavior identical and are verified by existing tests.
- Do not expand refactors beyond what is safe to verify in the current
  change; if a larger refactor is warranted but risky, mention it instead of
  applying it silently.

## Comments

- Prefer renaming variables, functions, and types to make the code
  self-explanatory instead of adding a comment to clarify what something
  does.
- Only add a comment when it explains something not obvious from the code
  itself (a "why", a non-obvious constraint, a gotcha). Do not restate what
  the code already says.
- Keep comments very short - prefer a single short sentence or clause over a
  paragraph.

## Naming

- Use long, explicit, descriptive names for variables, functions, and types
  instead of short or abbreviated ones. Prefer `maxRetryAttemptCount` over
  `max`, `pendingInvoiceTotal` over `pit`, `isEligibleForDiscount` over
  `flag`. A name should make the purpose of the value clear without needing
  to read surrounding code.
- Avoid single-letter or cryptic abbreviations, except for extremely common,
  narrowly-scoped loop indices (e.g. `i`) or well-known idioms in the
  language/ecosystem (e.g. Go's `err`, `ctx` for `context.Context`).
