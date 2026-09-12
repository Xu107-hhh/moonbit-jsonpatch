///|
/// One parsed operation from a patch document. `value` uses `None` for
/// "member absent" so that an explicit JSON `null` value stays distinct.
priv struct Operation {
  op : String
  path : String
  path_tokens : Array[String]
  from_tokens : Array[String] // empty when the operation has no "from"
  value : Json?
}

///|
/// Validate the shape of a patch document and split it into operations.
/// Members not required by an operation are ignored (extension-friendly).
fn parse_operations(patch : Json) -> Result[Array[Operation], PatchError] {
  guard patch is Array(items) else {
    return Err(
      patch_error(
        -1,
        "",
        "",
        InvalidPatchDoc,
        "a patch document must be a JSON array of operation objects",
      ),
    )
  }
  let ops : Array[Operation] = []
  for i, item in items {
    guard item is Object(o) else {
      return Err(
        patch_error(
          i,
          "",
          "",
          InvalidPatchDoc,
          "each patch element must be a JSON object",
        ),
      )
    }
    let op = match o.get("op") {
      Some(String(s)) => s
      _ =>
        return Err(
          patch_error(
            i,
            "",
            "",
            InvalidPatchDoc,
            "operation must have a string \"op\" member",
          ),
        )
    }
    match op {
      "add" | "remove" | "replace" | "move" | "copy" | "test" => ()
      _ =>
        return Err(
          patch_error(i, op, "", InvalidPatchDoc, "unknown operation \{op}"),
        )
    }
    let path = match o.get("path") {
      Some(String(s)) => s
      _ =>
        return Err(
          patch_error(
            i,
            op,
            "",
            InvalidPatchDoc,
            "operation must have a string \"path\" member",
          ),
        )
    }
    let path_tokens = match parse_pointer(path) {
      Some(t) => t
      None =>
        return Err(
          patch_error(
            i,
            op,
            path,
            MalformedPointer,
            "\"path\" is not a valid JSON Pointer (RFC 6901)",
          ),
        )
    }
    let value : Json? = o.get("value")
    match op {
      "add" | "replace" | "test" =>
        if value is None {
          return Err(
            patch_error(
              i,
              op,
              path,
              InvalidPatchDoc,
              "operation requires a \"value\" member",
            ),
          )
        }
      _ => ()
    }
    let from_tokens : Array[String] = []
    if op == "move" || op == "copy" {
      match o.get("from") {
        Some(String(s)) =>
          match parse_pointer(s) {
            Some(t) =>
              for tok in t {
                from_tokens.push(tok)
              }
            None =>
              return Err(
                patch_error(
                  i,
                  op,
                  path,
                  MalformedPointer,
                  "\"from\" is not a valid JSON Pointer (RFC 6901)",
                ),
              )
          }
        _ =>
          return Err(
            patch_error(
              i,
              op,
              path,
              InvalidPatchDoc,
              "operation requires a string \"from\" member",
            ),
          )
      }
    }
    ops.push(Operation::{ op, path, path_tokens, from_tokens, value, })
  }
  Ok(ops)
}

///|
/// `from` must not be a proper prefix of `path` for "move" operations.
fn is_proper_prefix(prefix : Array[String], full : Array[String]) -> Bool {
  if prefix.length() >= full.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if prefix[i] != full[i] {
      return false
    }
  }
  true
}

///|
/// Apply an RFC 6902 JSON Patch to a JSON document. On success the
/// patched document is returned; the input is never modified. On the
/// first failing operation the whole patch is rejected, so no partial
/// result ever escapes.
pub fn apply_patch(doc : Json, patch : Json) -> Result[Json, PatchError] {
  let ops = match parse_operations(patch) {
    Ok(ops) => ops
    Err(e) => return Err(e)
  }
  let mut current = doc
  for i, operation in ops {
    match operation.op {
      "add" => {
        let value = match operation.value {
          Some(v) => v
          None =>
            return Err(
              patch_error(
                i,
                "add",
                operation.path,
                InvalidPatchDoc,
                "operation requires a \"value\" member",
              ),
            )
        }
        match tree_set(current, operation.path_tokens, value, false) {
          Ok(updated) => current = updated
          Err(e) => return Err(tree_patch_error(i, operation, e))
        }
      }
      "remove" =>
        match tree_remove(current, operation.path_tokens) {
          Ok((updated, _removed)) => current = updated
          Err(e) => return Err(tree_patch_error(i, operation, e))
        }
      "replace" => {
        let value = match operation.value {
          Some(v) => v
          None =>
            return Err(
              patch_error(
                i,
                "replace",
                operation.path,
                InvalidPatchDoc,
                "operation requires a \"value\" member",
              ),
            )
        }
        match tree_set(current, operation.path_tokens, value, true) {
          Ok(updated) => current = updated
          Err(e) => return Err(tree_patch_error(i, operation, e))
        }
      }
      "move" => {
        if is_proper_prefix(operation.from_tokens, operation.path_tokens) {
          return Err(
            patch_error(
              i,
              "move",
              operation.path,
              Conflict,
              "\"from\" must not be a proper prefix of \"path\"",
            ),
          )
        }
        match tree_remove(current, operation.from_tokens) {
          Ok((updated, moved)) =>
            match tree_set(updated, operation.path_tokens, moved, false) {
              Ok(updated2) => current = updated2
              Err(e) => return Err(tree_patch_error(i, operation, e))
            }
          Err(e) => return Err(tree_patch_error(i, operation, e))
        }
      }
      "copy" =>
        match tree_get(current, operation.from_tokens) {
          Some(copied) =>
            match tree_set(current, operation.path_tokens, copied, false) {
              Ok(updated) => current = updated
              Err(e) => return Err(tree_patch_error(i, operation, e))
            }
          None =>
            return Err(
              patch_error(
                i,
                "copy",
                operation.path,
                PathNotFound,
                "\"from\" location does not exist",
              ),
            )
        }
      "test" => {
        let expected = match operation.value {
          Some(v) => v
          None =>
            return Err(
              patch_error(
                i,
                "test",
                operation.path,
                InvalidPatchDoc,
                "operation requires a \"value\" member",
              ),
            )
        }
        match tree_get(current, operation.path_tokens) {
          Some(actual) =>
            if !json_equal(actual, expected) {
              return Err(
                patch_error(
                  i,
                  "test",
                  operation.path,
                  TestFailed,
                  "value at the target location differs from \"value\"",
                ),
              )
            }
          None =>
            return Err(
              patch_error(
                i,
                "test",
                operation.path,
                TestFailed,
                "target location does not exist",
              ),
            )
        }
      }
      _ =>
        return Err(
          patch_error(
            i,
            operation.op,
            operation.path,
            InvalidPatchDoc,
            "unknown operation",
          ),
        )
    }
  }
  Ok(current)
}

///|
/// Translate an internal tree failure into a public patch error.
fn tree_patch_error(index : Int, op : Operation, e : TreeErr) -> PatchError {
  let (kind, message) = match e {
    Missing => (PathNotFound, "target location does not exist")
    NotContainer =>
      (
        PathNotFound,
        "an ancestor of the target location is neither an object nor an array",
      )
    BadIndex =>
      (Conflict, "array index is malformed or beyond the end of the array")
  }
  patch_error(index, op.op, op.path, kind, message)
}

///|
/// Text-level convenience: parse both documents, apply the patch, and
/// return the serialized result. JSON syntax errors of the inputs are
/// separated from patch application failures.
pub fn apply(
  doc_text : String,
  patch_text : String,
) -> Result[String, JsonPatchError] {
  let doc : Json = @json.parse(doc_text) catch {
    e => return Err(BadDocumentJson(e.to_string()))
  }
  let patch : Json = @json.parse(patch_text) catch {
    e => return Err(BadPatchJson(e.to_string()))
  }
  match apply_patch(doc, patch) {
    Ok(result) => Ok(result.stringify())
    Err(e) => Err(PatchFailed(e))
  }
}

///|
/// Check whether a value is a structurally valid patch document
/// (an array of well-formed operation objects).
pub fn is_valid_patch(patch : Json) -> Bool {
  match parse_operations(patch) {
    Ok(_) => true
    Err(_) => false
  }
}
