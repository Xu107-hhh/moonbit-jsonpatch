///|
/// Runnable example: an AI agent edits a shared document through JSON
/// Patch instead of regenerating it. Run with:
///
/// ```bash
/// moon run examples/ai
/// ```
///
/// Why patches instead of whole-document output:
/// 1. cheaper — the model emits only what changed;
/// 2. safer — a `test` precondition refuses to apply a stale edit;
/// 3. auditable — every accepted edit is itself a JSON document that
///    can be stored, replayed, and reviewed.
fn parse(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("example fixture is not valid JSON")
  }
}

///|
fn report(title : String, body : String) -> Unit {
  println("\n== \{title} ==")
  println(body)
}

///|
fn main {
  // The shared state an assistant maintains across turns.
  let state_text = "{\"project\": \"moonbit-jsonpatch\", \"owner\": \"Xu\", \"repo\": \"https://github.com/Xu107-hhh/moonbit-jsonpatch\", \"license\": \"Apache-2.0\", \"conformance\": \"108/108\", \"turn\": 3, \"tasks\": [{\"id\": 1, \"title\": \"core\", \"done\": true}, {\"id\": 2, \"title\": \"docs\", \"done\": false}, {\"id\": 3, \"title\": \"release\", \"done\": false}]}"
  let mut state = parse(state_text)
  report(
    "shared document (what regenerating every turn would cost)",
    "\{state.stringify()}",
  )
  println("bytes: \{state.stringify().length()}")

  // --- turn 4: the model answers with a patch, not the document ---
  let patch = parse(
    "[{\"op\": \"test\", \"path\": \"/turn\", \"value\": 3}, {\"op\": \"replace\", \"path\": \"/turn\", \"value\": 4}, {\"op\": \"add\", \"path\": \"/tasks/-\", \"value\": {\"id\": 4, \"title\": \"benchmarks\", \"done\": false}}]",
  )
  report(
    "model output for turn 4 (a patch: test guard + edits)",
    "\{patch.stringify()}",
  )
  match @jsonpatch.apply_patch(state, patch) {
    Ok(next) => {
      state = next
      report("state after applying", state.stringify())
      let full = state.stringify().length()
      let delta = patch.stringify().length()
      println(
        "bytes: \{full}, patch bytes: \{delta} (\{delta * 100 / full}% of a full rewrite)",
      )
      println(
        "the patch stays this small as the document grows; full rewrites scale with it",
      )
    }
    Err(e) => println("apply failed: \{e.message}")
  }

  // --- turn 5: the document moved on; the stale edit is refused ---
  let concurrent = parse(
    "[{\"op\": \"replace\", \"path\": \"/turn\", \"value\": 5}, {\"op\": \"replace\", \"path\": \"/tasks/1/done\", \"value\": true}]",
  )
  match @jsonpatch.apply_patch(state, concurrent) {
    Ok(next) => state = next
    Err(e) => println("unexpected: \{e.message}")
  }
  report("another writer bumped the document", state.stringify())
  let stale = patch // still guarded by test /turn == 3
  match @jsonpatch.apply_patch(state, stale) {
    Ok(_) => println("unexpected: stale patch applied")
    Err(e) =>
      report(
        "replaying the stale patch is refused",
        "test failed at operation 0 (test, path /turn): \{e.message}",
      )
  }

  // --- recovery: re-diff against current reality, keyed by id ---
  let target = parse(
    "{\"project\": \"moonbit-jsonpatch\", \"owner\": \"Xu\", \"repo\": \"https://github.com/Xu107-hhh/moonbit-jsonpatch\", \"license\": \"Apache-2.0\", \"conformance\": \"108/108\", \"turn\": 6, \"tasks\": [{\"id\": 1, \"title\": \"core\", \"done\": true}, {\"id\": 3, \"title\": \"release\", \"done\": false}, {\"id\": 4, \"title\": \"benchmarks + keyed diff\", \"done\": false}, {\"id\": 5, \"title\": \"submit\", \"done\": false}]}",
  )
  let fresh = @jsonpatch.diff_keyed(state, target, "id")
  report("recovery: diff_keyed(state, target, \"id\")", "\{fresh.stringify()}")
  match @jsonpatch.apply_patch(state, fresh) {
    Ok(end_state) => {
      report("final state", end_state.stringify())
      let ops = match fresh {
        Array(a) => a.length()
        _ => 0
      }
      println(
        "roundtrip ok: \{@jsonpatch.json_equal(end_state, target)}, patch ops: \{ops}",
      )
    }
    Err(e) => println("unexpected: \{e.message}")
  }
}
