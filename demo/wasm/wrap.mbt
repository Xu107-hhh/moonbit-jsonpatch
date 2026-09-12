///|
/// JavaScript-facing wrapper for the playground: apply / diff / merge,
/// each returning a JSON report string so the page can render failures
/// uniformly.
fn error_report(
  stage : String,
  message : String,
  index : Int,
  op : String,
  path : String,
) -> String {
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(false))
  m.set("stage", Json::string(stage))
  m.set("message", Json::string(message))
  m.set("index", Json::number(index.to_double()))
  m.set("op", Json::string(op))
  m.set("path", Json::string(path))
  Json::object(m).stringify()
}

///|
#export_name("apply")
pub fn apply(doc_text : String, patch_text : String) -> String {
  let doc : Json = @json.parse(doc_text) catch {
    e => return error_report("document", e.to_string(), -1, "", "")
  }
  let patch : Json = @json.parse(patch_text) catch {
    e => return error_report("patch", e.to_string(), -1, "", "")
  }
  match @lib.apply_patch(doc, patch) {
    Ok(result) => {
      let m : Map[String, Json] = Map([])
      m.set("ok", Json::boolean(true))
      m.set("result", result)
      Json::object(m).stringify()
    }
    Err(e) => error_report("apply", e.message, e.index, e.op, e.path)
  }
}

///|
#export_name("diff")
pub fn diff(original_text : String, modified_text : String) -> String {
  let original : Json = @json.parse(original_text) catch {
    e => return error_report("document", e.to_string(), -1, "", "")
  }
  let modified : Json = @json.parse(modified_text) catch {
    e => return error_report("patch", e.to_string(), -1, "", "")
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(true))
  m.set("result", @lib.diff(original, modified))
  Json::object(m).stringify()
}

///|
#export_name("merge")
pub fn merge(target_text : String, patch_text : String) -> String {
  let target : Json = @json.parse(target_text) catch {
    e => return error_report("document", e.to_string(), -1, "", "")
  }
  let patch : Json = @json.parse(patch_text) catch {
    e => return error_report("patch", e.to_string(), -1, "", "")
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(true))
  m.set("result", @lib.merge_patch(target, patch))
  Json::object(m).stringify()
}
