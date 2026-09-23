///|
/// Runnable example: apply an RFC 6902 patch, compute a diff, and apply
/// an RFC 7386 merge patch. Run with:
///
/// ```bash
/// moon run examples/basic
/// ```
fn parse(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("example fixture is not valid JSON")
  }
}

///|
fn main {
  // RFC 6902: apply a patch document (test / replace / add / remove).
  let doc = parse(
    "{\"name\": \"moonbit-jsonpatch\", \"version\": 1, \"tags\": [\"json\"]}",
  )
  let patch = parse(
    "[{\"op\": \"test\", \"path\": \"/version\", \"value\": 1}, {\"op\": \"replace\", \"path\": \"/version\", \"value\": 2}, {\"op\": \"add\", \"path\": \"/tags/-\", \"value\": \"rfc6902\"}, {\"op\": \"remove\", \"path\": \"/name\"}]",
  )
  match @jsonpatch.apply_patch(doc, patch) {
    Ok(result) => println("apply: \{result.stringify()}")
    Err(e) => println("apply failed: \{e.message}")
  }

  // diff: generate a patch transforming one document into another,
  // then verify it round-trips.
  let old = parse("{\"a\": 1, \"b\": [1, 2]}")
  let new = parse("{\"a\": 2, \"b\": [1, 2, 3]}")
  let generated = @jsonpatch.diff(old, new)
  println("diff:  \{generated.stringify()}")
  match @jsonpatch.apply_patch(old, generated) {
    Ok(result) => println("roundtrip ok: \{@jsonpatch.json_equal(result, new)}")
    Err(e) => println("unexpected: \{e.message}")
  }

  // RFC 7386: merge patch — null deletes a member, objects merge
  // recursively.
  let target = parse(
    "{\"title\": \"hello\", \"author\": {\"name\": \"Xu\", \"email\": \"x@y.z\"}}",
  )
  let merge = parse("{\"title\": \"hi\", \"author\": {\"email\": null}}")
  println("merge: \{@jsonpatch.merge_patch(target, merge).stringify()}")

  // keyed diff: id-bearing arrays are matched by identity, so a middle
  // change costs one semantic operation instead of cascading replaces.
  let board_old = parse(
    "{\"todos\": [{\"id\": 1, \"done\": true}, {\"id\": 2, \"done\": false}, {\"id\": 3, \"done\": false}]}",
  )
  let board_new = parse(
    "{\"todos\": [{\"id\": 1, \"done\": true}, {\"id\": 3, \"done\": true}]}",
  )
  let keyed = @jsonpatch.diff_keyed(board_old, board_new, "id")
  println("keyed diff: \{keyed.stringify()}")
  println("positional: \{@jsonpatch.diff(board_old, board_new).stringify()}")

  // Error reporting: failures name the operation and the exact path.
  let bad = parse("[{\"op\": \"add\", \"path\": \"/a/x\", \"value\": 1}]")
  match @jsonpatch.apply_patch(parse("{\"a\": 1}"), bad) {
    Ok(_) => println("unexpected success")
    Err(e) =>
      println(
        "error: operation \{e.index} (\{e.op}) at \{e.path}: \{e.message}",
      )
  }
}
