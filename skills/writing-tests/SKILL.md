---
name: writing-tests
description: The team's bar for automated tests (unit, integration, e2e). Load before writing tests for a ticket, or before reviewing a ticket's tests.
---

The repo's own testing rules (the testing sections of `AGENTS.md`/`CLAUDE.md`, and any test docs) win over this file. Read them, and the existing tests for the area, first.

## What a good test is

Write the fewest tests that defend real behaviour:

- Extend the existing test that already drives the same entry point, instead of adding a new `describe`, helper or test.
- Assert whole payloads or outputs, not one field picked out of a mock call.
- Build test data with the repo's existing factories, fakes and in-memory adapters. Don't hand-build domain objects, and don't patch data afterwards.
- Test at the unit that carries the meaning: not a trivial internal helper, and not the whole mapper or resolver when the logic lives in one function.
- Don't re-list the cases of a switch or lookup table.
- Don't test what a framework, library or called helper already guarantees.
- Don't re-test what a lower-level test already covers.
- An existing weak test isn't coverage. Strengthen it rather than writing around it.

## Cases

Derive the cases from the ticket's Acceptance criteria and the spec's Testing Decisions (the agreed seams). Cover the failure paths and edge cases the criteria imply. Choose the level for each case: unit, integration or e2e.

## E2E

- Use Given/When/Then steps, and set up state through the API rather than the UI.
- Choose locators by role, then label, then placeholder, then text, using `getBy*` options rather than filtering with `locator`. If the UI lacks proper labels, roles or ARIA attributes, fix the UI rather than working around it in the test.
- Take text from the translation files.
- Wait on the specific responses, never with `waitForTimeout` or `networkidle`.
- Keep the tests safe to run in parallel.

## Unit and integration

Colocate tests with their source, following the repo's convention.

## Prove them

Run each new e2e test in isolation five times (e.g. `--repeat-each=5`) to catch flakiness. Run the affected unit and integration suites. Never bend a test to make wrong code pass.
