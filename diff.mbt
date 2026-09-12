///|
/// Compute an RFC 6902 patch that transforms `original` into `modified`.
/// The result is not guaranteed to be minimal, but applying it to
/// `original` with `apply_patch` always reproduces `modified`.
pub fn diff(original : Json, modified : Json) -> Json {
  let ops : Array[Json] = []
  diff_walk(original, modified, "", ops)
  Json::array(ops)
}

///|
fn join_path(prefix : String, key : String) -> String {
  prefix + "/" + escape_token(key)
}

///|
fn remove_op(path : String) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("op", Json::string("remove"))
  m.set("path", Json::string(path))
  Json::object(m)
}

///|
fn op_with_value(op : String, path : String, value : Json) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("op", Json::string(op))
  m.set("path", Json::string(path))
  m.set("value", value)
  Json::object(m)
}

///|
fn diff_walk(a : Json, b : Json, prefix : String, ops : Array[Json]) -> Unit {
  match (a, b) {
    (Object(x), Object(y)) => {
      for k, _v in x {
        if y.get(k) is None {
          ops.push(remove_op(join_path(prefix, k)))
        }
      }
      for k, w in y {
        match x.get(k) {
          None => ops.push(op_with_value("add", join_path(prefix, k), w))
          Some(v) => diff_walk(v, w, join_path(prefix, k), ops)
        }
      }
    }
    (Array(x), Array(y)) => {
      let common = if x.length() < y.length() { x.length() } else { y.length() }
      for i in 0..<common {
        diff_walk(x[i], y[i], prefix + "/" + i.to_string(), ops)
      }
      let mut i = x.length() - 1
      while i >= y.length() {
        ops.push(remove_op(prefix + "/" + i.to_string()))
        i = i - 1
      }
      for i in x.length()..<y.length() {
        ops.push(op_with_value("add", prefix + "/" + i.to_string(), y[i]))
      }
    }
    _ => if !json_equal(a, b) { ops.push(op_with_value("replace", prefix, b)) }
  }
}

///|
/// Text-level convenience for `diff`.
pub fn diff_text(
  original_text : String,
  modified_text : String,
) -> Result[String, TextJsonError] {
  let original : Json = @json.parse(original_text) catch {
    e => return Err(BadTargetJson(e.to_string()))
  }
  let modified : Json = @json.parse(modified_text) catch {
    e => return Err(BadPatchJson(e.to_string()))
  }
  Ok(diff(original, modified).stringify())
}
