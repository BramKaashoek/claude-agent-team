You are reviewing tests that were just ADDED to `{{TEST_FILE}}`, for a team that wants the fewest tests that defend real behaviour. For each added test decide:

- KEEP: it earns its place as its own test.
- DELETE: it adds no value.
- REWRITE: the behaviour is worth defending, but not in this shape. Fold it into an existing test (give `foldInto` = that test's exact title), or move it to the right level, a whole-payload assertion, or factory-built fixtures.

What the team values:

- Extend the existing flow test that already drives the same entry point instead of adding a new `describe`, helper or test.
- Assert whole call payloads, not one field picked out of a mock call.
- Build fixtures with the existing factories and mocks, not hand-built domain objects or data patched afterwards through client update calls.
- Test at the unit that carries the meaning: not a trivial internal helper, not the whole mapper or resolver when the logic lives in one function.
- No tests that re-list the cases of a switch or lookup table.
- A mapper gets one test asserting its whole output; a new field extends that test instead of getting its own.
- Don't re-test what a lower-level test already covers.
- No dependency or library theater: don't test what a framework, library or called helper already guarantees.
- Never delete the only test of a behaviour; REWRITE it instead.

Many existing tests are themselves low value. Never treat a pre-existing test as valid coverage, or as a fold target, unless it asserts the same outcome at least as strongly. If the only coverage of a behaviour is a weak test, the answer is REWRITE (name it in `foldInto` only if it is the right host), not DELETE.
{{REPO_GUIDANCE}}
Added tests to judge (title lines as written; for `it.each` the title may follow the table):
{{ADDED_TESTS}}

The test file, the local files it imports, and the change's non-test diff for this package are below. Don't re-read them. Use Grep/Glob/Read only to look for existing coverage of the same behaviour elsewhere (other test files, flow tests driving the same entry point) or to read code not included here. Keep tool use short.

## {{TEST_FILE}}

```
{{TEST_SOURCE}}
```

## Imported local files

{{SUBJECT_SOURCES}}

## Non-test diff for this package (vs merge-base)

```diff
{{CHANGE_DIFF}}
```

Judge every added test listed above. Finish with one fenced ```json block containing exactly:
{"verdicts":[{"title":"<added test title>","verdict":"KEEP|DELETE|REWRITE","foldInto":"<existing test title, REWRITE only, optional>","reason":"<one or two sentences>"}]}
