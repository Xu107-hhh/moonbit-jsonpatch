///|
/// Parse a JSON Pointer (RFC 6901) as used by JSON Patch "path"/"from"
/// members: either the empty string (the whole document) or a string
/// beginning with `/`, where `~0` escapes `~` and `~1` escapes `/`.
/// Returns `None` when the pointer is malformed (missing leading `/`,
/// an invalid escape such as `~2`, or a dangling `~`).
fn parse_pointer(pointer : String) -> Array[String]? {
  if pointer == "" {
    return Some([]) // the whole document
  }
  let tokens : Array[String] = []
  let buf = StringBuilder()
  let mut in_escape = false
  let mut started = false
  for c in pointer {
    if !started {
      if c != '/' {
        return None
      }
      started = true
      continue
    }
    if in_escape {
      match c {
        '0' => buf.write_char('~')
        '1' => buf.write_char('/')
        _ => return None // invalid escape
      }
      in_escape = false
    } else if c == '~' {
      in_escape = true
    } else if c == '/' {
      tokens.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  if in_escape {
    return None // dangling '~'
  }
  tokens.push(buf.to_string())
  Some(tokens)
}

///|
/// Render one pointer token back to its escaped form (`~` -> `~0`,
/// `/` -> `~1`), for generating pointers in `diff`.
fn escape_token(token : String) -> String {
  let buf = StringBuilder()
  for c in token {
    if c == '~' {
      buf.write_string("~0")
    } else if c == '/' {
      buf.write_string("~1")
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Parse a canonical array index (digits only, no leading zeros unless
/// the value is exactly "0"). Indices longer than 9 digits are treated
/// as unresolvable to stay clear of overflow.
fn parse_index(t : String) -> Int? {
  if t.length() == 0 || t.length() > 9 {
    return None
  }
  let mut n = 0
  for c in t {
    guard c >= '0' && c <= '9' else { return None }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  if t.length() > 1 && t.get_char(0) == Some('0') {
    return None
  }
  Some(n)
}
