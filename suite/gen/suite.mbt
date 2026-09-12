///|
/// Shared helpers for the generated conformance tests. This file also
/// anchors the package imports in the main (non-test) source set.
///
/// Parse a fixture, aborting on malformed JSON (fixtures are vendored,
/// so this never fires in practice).
pub fn parse_fixture(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("conformance fixture is not valid JSON")
  }
}

///|
/// Apply a patch that the upstream suite expects to succeed.
pub fn apply_ok(doc : Json, patch : Json) -> Json {
  match @jsonpatch.apply_patch(doc, patch) {
    Ok(result) => result
    Err(_) => abort("expected patch application to succeed")
  }
}

///|
/// Apply a patch that the upstream suite expects to fail.
pub fn apply_err(doc : Json, patch : Json) -> Bool {
  match @jsonpatch.apply_patch(doc, patch) {
    Ok(_) => false
    Err(_) => true
  }
}
