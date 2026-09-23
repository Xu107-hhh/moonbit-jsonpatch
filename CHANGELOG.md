# Changelog

## 0.2.0 — 2026-09-20

### Added

- Keyed array diffing: `diff_keyed` / `diff_text_keyed` match id-bearing
  arrays by a unique member instead of by position — one `add` for a middle
  insert, one `remove` for a deletion, recursive diff for survivors;
  positional fallback for non-object items, duplicate ids, missing keys and
  reorderings (#8). CLI: `diff --key <member>`. Playground Diff tab gained a
  "keyed by" input.
- CLI: every document argument accepts `@path` (read from a file, via
  `moonbitlang/x/fs`) and `-` (read stdin; js backend) (#6).
- Benchmark harness `moon run --release benches` — pinned-seed documents,
  apply/diff/merge across 1k–100k items; README gained a Performance
  section with the measured cost model (#7).
- `examples/ai`: an agent editing a shared document through patches —
  cheaper than regenerating, guarded by `test` against stale concurrent
  edits, recovered with keyed diff (#9).
- `docs/design-faq.md`: twenty design-decision Q&As (#10).

### Fixed

- Running the CLI under `moon run --target js` silently exited: Node's
  `process.argv` keeps the interpreter prefix, which confused argparse's
  positional parsing. Arguments are now normalized per backend and passed
  explicitly (#6).
- Array-index errors report the actual array length and the offending
  token (e.g. "array index 5 is beyond the end of the array (length 2)").

## 0.1.1 — 2026-09-14

### Added

- Error context: array index failures carry the real length and the
  malformed token instead of a generic message (#5, closes #2).

### Changed

- `moon.mod` readme path follows the `README.md` rename.

## 0.1.0 — 2026-09-12

Initial release.

- RFC 6902 JSON Patch: apply (add / remove / replace / move / copy / test),
  atomic failure with operation index, op and path in every error.
- RFC 6901 JSON Pointer parsing with `~0`/`~1` escapes and canonical
  array indices.
- RFC 7386 JSON Merge Patch.
- Diff generation (positional arrays), immutable updates with zero side
  effects on failure.
- CLI (`cmd/patch`), browser playground (GitHub Pages), official
  json-patch-tests conformance 108/108, published to mooncakes.
