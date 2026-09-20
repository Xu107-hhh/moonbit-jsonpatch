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
/// Compute a patch like `diff`, but arrays whose items are all objects
/// carrying a unique `key` member are matched by that key instead of by
/// position: an item inserted in the middle costs one `add`, a removed
/// item one `remove`, and a changed field inside a surviving item is
/// diffed recursively.
///
/// An array falls back to positional diffing (the `diff` behavior) when
/// any item is not an object, lacks the key, the key values are not
/// unique within one side, or the shared items appear in a different
/// relative order on both sides (reordering is deliberately not modeled
/// as moves). As with `diff`, applying the result to `original` always
/// reproduces `modified`.
pub fn diff_keyed(original : Json, modified : Json, key : String) -> Json {
  let ops : Array[Json] = []
  diff_walk_keyed(original, modified, "", Some(key), ops)
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
  diff_walk_keyed(a, b, prefix, None, ops)
}

///|
/// Shared walker. `key` enables keyed array matching at every array
/// level (see `diff_keyed`); `None` keeps plain positional diffing.
fn diff_walk_keyed(
  a : Json,
  b : Json,
  prefix : String,
  key : String?,
  ops : Array[Json],
) -> Unit {
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
          Some(v) => diff_walk_keyed(v, w, join_path(prefix, k), key, ops)
        }
      }
    }
    (Array(x), Array(y)) => {
      let handled = match key {
        Some(k) => keyed_array_diff(x, y, prefix, k, ops)
        None => false
      }
      if !handled {
        positional_array_diff(x, y, prefix, key, ops)
      }
    }
    _ => if !json_equal(a, b) { ops.push(op_with_value("replace", prefix, b)) }
  }
}

///|
/// Positional array diff: pair items by index, drop the old tail
/// (descending), grow the new tail.
fn positional_array_diff(
  x : Array[Json],
  y : Array[Json],
  prefix : String,
  key : String?,
  ops : Array[Json],
) -> Unit {
  let common = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<common {
    diff_walk_keyed(x[i], y[i], prefix + "/" + i.to_string(), key, ops)
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

///|
/// Pair each array item with its key string (the stringified value of
/// member `key`). Returns None when an item is not an object, lacks the
/// key, or a key value repeats within the array — those cases have no
/// unambiguous identity and fall back to positional diffing.
fn keyed_pairs(items : Array[Json], key : String) -> Array[(String, Json)]? {
  let pairs : Array[(String, Json)] = []
  let seen : Map[String, Bool] = Map([])
  for item in items {
    guard item is Object(o) else { return None }
    guard o.get(key) is Some(v) else { return None }
    let ks = v.stringify()
    if seen.get(ks) is Some(_) {
      return None
    }
    seen.set(ks, true)
    pairs.push((ks, item))
  }
  Some(pairs)
}

///|
/// Diff two arrays by item identity. Emits ops into `ops` and returns
/// true when the pair is eligible for keyed matching; returns false
/// (emitting nothing) when the caller should fall back to positional
/// diffing.
fn keyed_array_diff(
  x : Array[Json],
  y : Array[Json],
  prefix : String,
  key : String,
  ops : Array[Json],
) -> Bool {
  guard keyed_pairs(x, key) is Some(xp) else { return false }
  guard keyed_pairs(y, key) is Some(yp) else { return false }
  let ykeys : Map[String, Bool] = Map([])
  for p in yp {
    ykeys.set(p.0, true)
  }
  let xkeys : Map[String, Bool] = Map([])
  for p in xp {
    xkeys.set(p.0, true)
  }
  // Reordering is not modeled: require shared items to keep the same
  // relative order on both sides, otherwise stay positional.
  let x_common : Array[String] = []
  for p in xp {
    if ykeys.get(p.0) is Some(_) {
      x_common.push(p.0)
    }
  }
  let y_common : Array[String] = []
  for p in yp {
    if xkeys.get(p.0) is Some(_) {
      y_common.push(p.0)
    }
  }
  guard x_common == y_common else { return false }
  // Phase 1: drop items that disappeared, back to front so earlier
  // indices stay valid against the evolving document.
  for i = xp.length() - 1; i >= 0; i = i - 1 {
    if ykeys.get(xp[i].0) is None {
      ops.push(remove_op(prefix + "/" + i.to_string()))
    }
  }
  // cur = survivors of x, in x order; shared items keep this order on
  // both sides, so walking y left-to-right either matches cur[i] or
  // inserts a brand-new item before it.
  let cur : Array[(String, Json)] = []
  for p in xp {
    if ykeys.get(p.0) is Some(_) {
      cur.push(p)
    }
  }
  let mut i = 0
  for p in yp {
    if i < cur.length() && cur[i].0 == p.0 {
      // same item at this position: recurse into the pair
      diff_walk_keyed(
        cur[i].1,
        p.1,
        prefix + "/" + i.to_string(),
        Some(key),
        ops,
      )
      i = i + 1
    } else {
      // brand-new item; inserting before cur[i] keeps later indices
      // aligned as the loop advances
      ops.push(op_with_value("add", prefix + "/" + i.to_string(), p.1))
      cur.insert(i, p)
      i = i + 1
    }
  }
  true
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

///|
/// Text-level convenience for `diff_keyed`.
pub fn diff_text_keyed(
  original_text : String,
  modified_text : String,
  key : String,
) -> Result[String, TextJsonError] {
  let original : Json = @json.parse(original_text) catch {
    e => return Err(BadTargetJson(e.to_string()))
  }
  let modified : Json = @json.parse(modified_text) catch {
    e => return Err(BadPatchJson(e.to_string()))
  }
  Ok(diff_keyed(original, modified, key).stringify())
}
