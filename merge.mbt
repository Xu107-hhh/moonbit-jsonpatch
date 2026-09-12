///|
/// RFC 7386 JSON Merge Patch: recursively merge `patch` into `target`
/// and return the result. Object members set to `null` in the patch are
/// removed; objects merge recursively; any other patch value replaces
/// the target wholesale. Neither input is modified.
pub fn merge_patch(target : Json, patch : Json) -> Json {
  match patch {
    Object(patch_members) => {
      let base : Map[String, Json] = match target {
        Object(target_members) => {
          let out : Map[String, Json] = Map([])
          for k, v in target_members {
            out.set(k, v)
          }
          out
        }
        _ => Map([])
      }
      for k, v in patch_members {
        if v is Null {
          let _ = base.remove(k)
        } else {
          let child = match base.get(k) {
            Some(existing) => existing
            None => Json::null()
          }
          base.set(k, merge_patch(child, v))
        }
      }
      Json::object(base)
    }
    _ => patch
  }
}

///|
/// Text-level convenience for `merge_patch`.
pub fn merge(
  target_text : String,
  patch_text : String,
) -> Result[String, TextJsonError] {
  let target : Json = @json.parse(target_text) catch {
    e => return Err(BadTargetJson(e.to_string()))
  }
  let patch : Json = @json.parse(patch_text) catch {
    e => return Err(BadPatchJson(e.to_string()))
  }
  Ok(merge_patch(target, patch).stringify())
}
