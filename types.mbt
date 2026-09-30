///|
/// Classification of a failed JSON Patch operation.
pub enum PatchErrorKind {
  InvalidPatchDoc // the patch document itself is malformed
  MalformedPointer // a "path"/"from" member is not a valid JSON Pointer
  PathNotFound // the target (or one of its ancestors) does not exist
  TestFailed // a "test" operation found a different value than expected
  Conflict // e.g. array index beyond the end, or moving into one's own child
} derive(Debug, Eq)

///|
pub extend PatchErrorKind with @debug.Debug::{to_repr}

///|
pub extend PatchErrorKind with Eq::{not_equal, equal}

///|
/// A single failure while parsing or applying a JSON Patch document.
pub(all) struct PatchError {
  index : Int // index of the failing operation, -1 for patch-level errors
  op : String // operation name, "" for patch-level errors
  path : String // the "path" member verbatim, "" when not applicable
  kind : PatchErrorKind
  message : String
} derive(Debug, Eq)

///|
pub extend PatchError with @debug.Debug::{to_repr}

///|
pub extend PatchError with Eq::{not_equal, equal}

///|
/// Errors from the text-level `apply` entry point: JSON syntax problems
/// with the inputs, or a failed patch application.
pub enum JsonPatchError {
  BadDocumentJson(String)
  BadPatchJson(String)
  PatchFailed(PatchError)
} derive(Debug, Eq)

///|
pub extend JsonPatchError with @debug.Debug::{to_repr}

///|
pub extend JsonPatchError with Eq::{not_equal, equal}

///|
/// JSON syntax problems with text-level `merge` / `diff_text` inputs
/// (first / second argument respectively).
pub enum TextJsonError {
  BadTargetJson(String)
  BadPatchJson(String)
} derive(Debug, Eq)

///|
pub extend TextJsonError with @debug.Debug::{to_repr}

///|
pub extend TextJsonError with Eq::{not_equal, equal}

///|
/// Assemble a `PatchError` without repeating the field names.
fn patch_error(
  index : Int,
  op : String,
  path : String,
  kind : PatchErrorKind,
  message : String,
) -> PatchError {
  PatchError::{ index, op, path, kind, message, }
}
