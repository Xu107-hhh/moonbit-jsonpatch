///|
/// Internal failure modes while resolving or updating a location.
priv enum TreeErr {
  Missing // an ancestor or the target itself does not exist
  NotContainer // an ancestor exists but is neither object nor array
  BadIndex(String) // final array index malformed or out of range, with detail
}

///|
/// Functional update helpers: they build fresh containers along the
/// updated spine and share everything else, so inputs are never mutated
/// and a failed operation leaves no partial state.
fn object_with(
  o : Map[String, Json],
  key : String,
  value : Json,
) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for k, v in o {
    out.set(k, v)
  }
  out.set(key, value)
  out
}

///|
fn object_without(o : Map[String, Json], key : String) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for k, v in o {
    if k != key {
      out.set(k, v)
    }
  }
  out
}

///|
fn object_size(o : Map[String, Json]) -> Int {
  let mut n = 0
  for _k, _v in o {
    n = n + 1
  }
  n
}

///|
fn array_set(a : Array[Json], idx : Int, value : Json) -> Array[Json] {
  let out = a.copy()
  out[idx] = value
  out
}

///|
fn array_insert(a : Array[Json], idx : Int, value : Json) -> Array[Json] {
  let out : Array[Json] = []
  for i in 0..<idx {
    out.push(a[i])
  }
  out.push(value)
  for i in idx..<a.length() {
    out.push(a[i])
  }
  out
}

///|
fn array_remove(a : Array[Json], idx : Int) -> Array[Json] {
  let out : Array[Json] = []
  for i in 0..<a.length() {
    if i != idx {
      out.push(a[i])
    }
  }
  out
}

///|
fn array_append(a : Array[Json], value : Json) -> Array[Json] {
  let out = a.copy()
  out.push(value)
  out
}

///|
/// Drop the first token of a pointer token list.
fn tail_tokens(tokens : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for i in 1..<tokens.length() {
    out.push(tokens[i])
  }
  out
}

///|
/// Look up the value at a pointer location. `-` and non-canonical
/// indices never resolve.
fn tree_get(doc : Json, tokens : Array[String]) -> Json? {
  let mut cur = doc
  for t in tokens {
    match cur {
      Object(o) =>
        match o.get(t) {
          Some(v) => cur = v
          None => return None
        }
      Array(a) => {
        guard parse_index(t) is Some(i) else { return None }
        guard i < a.length() else { return None }
        cur = a[i]
      }
      _ => return None
    }
  }
  Some(cur)
}

///|
/// Functional "add"/"replace": returns the updated document. With
/// `must_exist` the final location has to exist already ("replace");
/// otherwise "add" semantics apply (object members are created or
// overwritten, arrays accept indices up to their length plus `-`).
fn tree_set(
  doc : Json,
  tokens : Array[String],
  value : Json,
  must_exist : Bool,
) -> Result[Json, TreeErr] {
  if tokens.length() == 0 {
    return Ok(value) // the whole document is the target
  }
  let head = tokens[0]
  match doc {
    Object(o) => {
      let existing = o.get(head)
      if tokens.length() == 1 {
        if must_exist && existing is None {
          return Err(Missing)
        }
        return Ok(Json::object(object_with(o, head, value)))
      }
      match existing {
        Some(child) =>
          match tree_set(child, tail_tokens(tokens), value, must_exist) {
            Ok(updated) => Ok(Json::object(object_with(o, head, updated)))
            Err(e) => Err(e)
          }
        None => Err(Missing)
      }
    }
    Array(a) => {
      if tokens.length() == 1 {
        if head == "-" {
          if must_exist {
            return Err(Missing) // "-" never names an existing element
          }
          return Ok(Json::array(array_append(a, value)))
        }
        guard parse_index(head) is Some(i) else {
          return Err(
            BadIndex("array index \"\{head}\" is not a canonical decimal index"),
          )
        }
        if must_exist {
          if i >= a.length() {
            return Err(Missing)
          }
          return Ok(Json::array(array_set(a, i, value)))
        }
        if i > a.length() {
          return Err(
            BadIndex(
              "array index \{i} is beyond the end of the array (length \{a.length()})",
            ),
          )
        }
        return Ok(Json::array(array_insert(a, i, value)))
      }
      guard parse_index(head) is Some(i) else { return Err(Missing) }
      guard i < a.length() else { return Err(Missing) }
      match tree_set(a[i], tail_tokens(tokens), value, must_exist) {
        Ok(updated) => Ok(Json::array(array_set(a, i, updated)))
        Err(e) => Err(e)
      }
    }
    _ => Err(NotContainer)
  }
}

///|
/// Functional "remove": returns the updated document together with the
/// removed value. Removing the whole document yields `Null`.
fn tree_remove(
  doc : Json,
  tokens : Array[String],
) -> Result[(Json, Json), TreeErr] {
  if tokens.length() == 0 {
    return Ok((Json::null(), doc))
  }
  let head = tokens[0]
  match doc {
    Object(o) =>
      match o.get(head) {
        None => Err(Missing)
        Some(child) =>
          if tokens.length() == 1 {
            Ok((Json::object(object_without(o, head)), child))
          } else {
            match tree_remove(child, tail_tokens(tokens)) {
              Ok((updated, removed)) =>
                Ok((Json::object(object_with(o, head, updated)), removed))
              Err(e) => Err(e)
            }
          }
      }
    Array(a) => {
      guard parse_index(head) is Some(i) else { return Err(Missing) }
      guard i < a.length() else { return Err(Missing) }
      if tokens.length() == 1 {
        Ok((Json::array(array_remove(a, i)), a[i]))
      } else {
        match tree_remove(a[i], tail_tokens(tokens)) {
          Ok((updated, removed)) =>
            Ok((Json::array(array_set(a, i, updated)), removed))
          Err(e) => Err(e)
        }
      }
    }
    _ => Err(NotContainer)
  }
}

///|
/// Deep structural equality per RFC 6902 "test": numbers compare by
/// mathematical value, strings code-point-wise, objects and arrays
/// recursively regardless of member order. Exposed because it defines
/// what "the same value" means for patch operations.
pub fn json_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (Number(x, ..), Number(y, ..)) => x == y
    (String(x), String(y)) => x == y
    (Array(x), Array(y)) => {
      if x.length() != y.length() {
        return false
      }
      for i in 0..<x.length() {
        if !json_equal(x[i], y[i]) {
          return false
        }
      }
      true
    }
    (Object(x), Object(y)) => {
      if object_size(x) != object_size(y) {
        return false
      }
      for k, v in x {
        match y.get(k) {
          Some(w) => if !json_equal(v, w) { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}
