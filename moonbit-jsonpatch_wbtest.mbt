///|
fn parse_ok(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("test fixture is not valid JSON: " + text)
  }
}

///|
/// Assert that applying `patch` to `doc` yields `expected`.
fn expect_apply(doc : String, patch : String, expected : String) -> Bool {
  match apply_patch(parse_ok(doc), parse_ok(patch)) {
    Ok(result) => json_equal(result, parse_ok(expected))
    Err(_) => false
  }
}

///|
/// Assert that applying `patch` to `doc` fails with the given kind.
fn expect_fail(doc : String, patch : String, kind : PatchErrorKind) -> Bool {
  match apply_patch(parse_ok(doc), parse_ok(patch)) {
    Ok(_) => false
    Err(e) => e.kind == kind
  }
}

///|
test "pointer: root, empty key, escapes, malformed" {
  inspect(parse_pointer(""), content="Some([])")
  // Debug rendering cannot show the empty-string token, so check "/" structurally
  match parse_pointer("/") {
    Some(t) => inspect(t.length() == 1 && t[0] == "", content="true")
    None => inspect("expected one empty token", content="")
  }
  inspect(parse_pointer("/a/b"), content="Some([a, b])")
  inspect(parse_pointer("/a~1b"), content="Some([a/b])")
  inspect(parse_pointer("/a~0b"), content="Some([a~b])")
  inspect(parse_pointer("a/b"), content="None")
  inspect(parse_pointer("/a~2b"), content="None")
  inspect(parse_pointer("/a~"), content="None")
  inspect(parse_index("0"), content="Some(0)")
  inspect(parse_index("10"), content="Some(10)")
  inspect(parse_index("01"), content="None")
  inspect(parse_index("-"), content="None")
  inspect(escape_token("a/b~c"), content="a~1b~0c")
}

///|
test "add: object member insert and overwrite" {
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2}]", "{\"a\":1,\"b\":2}",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/a\",\"value\":9}]", "{\"a\":9}",
    ),
    content="true",
  )
}

///|
test "add: nested path through existing containers" {
  inspect(
    expect_apply(
      "{\"a\":{\"x\":1}}", "[{\"op\":\"add\",\"path\":\"/a/y\",\"value\":2}]", "{\"a\":{\"x\":1,\"y\":2}}",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "{\"a\":[0,{},2]}", "[{\"op\":\"add\",\"path\":\"/a/1/z\",\"value\":true}]",
      "{\"a\":[0,{\"z\":true},2]}",
    ),
    content="true",
  )
}

///|
test "add: array append and middle insert" {
  inspect(
    expect_apply(
      "[1,2,3]", "[{\"op\":\"add\",\"path\":\"/-\",\"value\":4}]", "[1,2,3,4]",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "[1,2,3]", "[{\"op\":\"add\",\"path\":\"/2\",\"value\":9}]", "[1,2,9,3]",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "[]", "[{\"op\":\"add\",\"path\":\"/0\",\"value\":\"x\"}]", "[\"x\"]",
    ),
    content="true",
  )
}

///|
test "add: root replaces the whole document" {
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"\",\"value\":[1,2]}]", "[1,2]",
    ),
    content="true",
  )
}

///|
test "add: index beyond length or missing parent fails" {
  inspect(
    expect_fail(
      "[1,2]",
      "[{\"op\":\"add\",\"path\":\"/5\",\"value\":1}]",
      Conflict,
    ),
    content="true",
  )
  inspect(
    expect_fail(
      "{\"a\":1}",
      "[{\"op\":\"add\",\"path\":\"/a/b\",\"value\":1}]",
      PathNotFound,
    ),
    content="true",
  )
  inspect(
    expect_fail(
      "[1,2]",
      "[{\"op\":\"add\",\"path\":\"/01\",\"value\":1}]",
      Conflict,
    ),
    content="true",
  )
}

///|
test "remove: member, array element, missing" {
  inspect(
    expect_apply(
      "{\"a\":1,\"b\":2}", "[{\"op\":\"remove\",\"path\":\"/a\"}]", "{\"b\":2}",
    ),
    content="true",
  )
  inspect(
    expect_apply("[1,2,3]", "[{\"op\":\"remove\",\"path\":\"/1\"}]", "[1,3]"),
    content="true",
  )
  inspect(
    expect_fail(
      "{\"a\":1}",
      "[{\"op\":\"remove\",\"path\":\"/b\"}]",
      PathNotFound,
    ),
    content="true",
  )
  inspect(
    expect_fail("[1,2]", "[{\"op\":\"remove\",\"path\":\"/2\"}]", PathNotFound),
    content="true",
  )
}

///|
test "replace: existing only" {
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"replace\",\"path\":\"/a\",\"value\":2}]", "{\"a\":2}",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "[1,2]", "[{\"op\":\"replace\",\"path\":\"/0\",\"value\":\"x\"}]", "[\"x\",2]",
    ),
    content="true",
  )
  inspect(
    expect_fail(
      "{\"a\":1}",
      "[{\"op\":\"replace\",\"path\":\"/b\",\"value\":2}]",
      PathNotFound,
    ),
    content="true",
  )
}

///|
test "move: relocate a value, refuse moving into own child" {
  inspect(
    expect_apply(
      "{\"a\":1,\"b\":2}", "[{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/c\"}]",
      "{\"b\":2,\"c\":1}",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "{\"a\":{\"b\":1}}", "[{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/a/x\"}]",
      "{\"a\":{\"b\":1}}",
    ),
    content="false", // must be rejected: /a is a proper prefix of /a/x
  )
  inspect(
    expect_fail(
      "{\"a\":{\"b\":1}}",
      "[{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/a/x\"}]",
      Conflict,
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "{\"a\":[0,1,2,3]}", "[{\"op\":\"move\",\"from\":\"/a/1\",\"path\":\"/a/3\"}]",
      "{\"a\":[0,2,3,1]}",
    ),
    content="true",
  )
}

///|
test "move: missing from fails" {
  inspect(
    expect_fail(
      "{\"a\":1}",
      "[{\"op\":\"move\",\"from\":\"/x\",\"path\":\"/a\"}]",
      PathNotFound,
    ),
    content="true",
  )
}

///|
test "copy: duplicate a value, source stays" {
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"copy\",\"from\":\"/a\",\"path\":\"/b\"}]", "{\"a\":1,\"b\":1}",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "{\"a\":{\"x\":1}}", "[{\"op\":\"copy\",\"from\":\"/a\",\"path\":\"/b\"},{\"op\":\"add\",\"path\":\"/b/y\",\"value\":2}]",
      "{\"a\":{\"x\":1},\"b\":{\"x\":1,\"y\":2}}",
    ),
    content="true",
  )
}

///|
test "test: equality and failure" {
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":1}]", "{\"a\":1}",
    ),
    content="true",
  )
  inspect(
    expect_apply(
      "{\"a\":{\"b\":[1,2]}}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":{\"b\":[1,2]}}]",
      "{\"a\":{\"b\":[1,2]}}",
    ),
    content="true",
  )
  inspect(
    expect_fail(
      "{\"a\":1}",
      "[{\"op\":\"test\",\"path\":\"/a\",\"value\":2}]",
      TestFailed,
    ),
    content="true",
  )
  inspect(
    expect_fail(
      "{\"a\":1}",
      "[{\"op\":\"test\",\"path\":\"/b\",\"value\":1}]",
      TestFailed,
    ),
    content="true",
  )
  inspect(
    expect_fail(
      "{\"a\":null}",
      "[{\"op\":\"test\",\"path\":\"/a\",\"value\":null}]",
      TestFailed,
    ),
    content="false", // null is a legitimate value and compares equal
  )
}

///|
test "patch document validation" {
  inspect(expect_fail("{}", "{}", InvalidPatchDoc), content="true")
  inspect(expect_fail("{}", "[1]", InvalidPatchDoc), content="true")
  inspect(
    expect_fail("{}", "[{\"path\":\"/a\",\"value\":1}]", InvalidPatchDoc),
    content="true",
  )
  inspect(
    expect_fail(
      "{}",
      "[{\"op\":\"shove\",\"path\":\"/a\",\"value\":1}]",
      InvalidPatchDoc,
    ),
    content="true",
  )
  inspect(
    expect_fail("{}", "[{\"op\":\"add\",\"path\":\"/a\"}]", InvalidPatchDoc),
    content="true",
  )
  inspect(
    expect_fail("{}", "[{\"op\":\"copy\",\"path\":\"/a\"}]", InvalidPatchDoc),
    content="true",
  )
  inspect(
    expect_fail(
      "{}",
      "[{\"op\":\"add\",\"path\":\"nope\",\"value\":1}]",
      MalformedPointer,
    ),
    content="true",
  )
  inspect(is_valid_patch(parse_ok("[]")), content="true")
  inspect(
    is_valid_patch(parse_ok("[{\"op\":\"add\",\"path\":\"/a\",\"value\":1}]")),
    content="true",
  )
  inspect(is_valid_patch(parse_ok("{}")), content="false")
}

///|
test "empty patch is a no-op; operations run in order" {
  inspect(expect_apply("{\"a\":1}", "[]", "{\"a\":1}"), content="true")
  inspect(
    expect_apply(
      "{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2},{\"op\":\"move\",\"from\":\"/b\",\"path\":\"/c\"}]",
      "{\"a\":1,\"c\":2}",
    ),
    content="true",
  )
}

///|
test "inputs are never mutated" {
  let doc = parse_ok("{\"a\":{\"x\":1},\"list\":[1,2]}")
  let patch_text = "[{\"op\":\"add\",\"path\":\"/list/-\",\"value\":3},{\"op\":\"remove\",\"path\":\"/a/x\"},{\"op\":\"replace\",\"path\":\"/list/0\",\"value\":9}]"
  let original = parse_ok("{\"a\":{\"x\":1},\"list\":[1,2]}")
  let _ = apply_patch(doc, parse_ok(patch_text))
  inspect(json_equal(doc, original), content="true")
}

///|
test "merge patch (RFC 7386)" {
  inspect(
    json_equal(
      merge_patch(
        parse_ok("{\"a\":1,\"b\":2}"),
        parse_ok("{\"b\":null,\"c\":3}"),
      ),
      parse_ok("{\"a\":1,\"c\":3}"),
    ),
    content="true",
  )
  inspect(
    json_equal(
      merge_patch(
        parse_ok("{\"a\":{\"x\":1,\"y\":2}}"),
        parse_ok("{\"a\":{\"y\":3}}"),
      ),
      parse_ok("{\"a\":{\"x\":1,\"y\":3}}"),
    ),
    content="true",
  )
  inspect(
    json_equal(
      merge_patch(parse_ok("{\"a\":1}"), parse_ok("[1,2]")),
      parse_ok("[1,2]"),
    ),
    content="true",
  )
  inspect(
    json_equal(
      merge_patch(parse_ok("{\"a\":1}"), parse_ok("{\"a\":null}")),
      parse_ok("{}"),
    ),
    content="true",
  )
}

///|
test "diff: object changes" {
  let patch = diff(parse_ok("{\"a\":1,\"b\":2}"), parse_ok("{\"a\":1,\"c\":3}"))
  inspect(is_valid_patch(patch), content="true")
  match apply_patch(parse_ok("{\"a\":1,\"b\":2}"), patch) {
    Ok(result) =>
      inspect(json_equal(result, parse_ok("{\"a\":1,\"c\":3}")), content="true")
    Err(_) => inspect("diff apply failed", content="")
  }
}

///|
test "diff: array changes roundtrip" {
  let a = parse_ok("[1,{\"x\":2},3]")
  let b = parse_ok("[1,{\"x\":9},4,5]")
  let patch = diff(a, b)
  match apply_patch(a, patch) {
    Ok(result) => inspect(json_equal(result, b), content="true")
    Err(_) => inspect("diff apply failed", content="")
  }
}

///|
test "diff: equal documents produce an empty patch" {
  inspect(
    diff(parse_ok("{\"a\":[1,2]}"), parse_ok("{\"a\":[1,2]}")).stringify(),
    content="[]",
  )
}

///|
test "text-level apply separates parse errors" {
  match apply("{\"a\":}", "[]") {
    Err(BadDocumentJson(_)) => inspect("doc", content="doc")
    _ => inspect("expected BadDocumentJson", content="")
  }
  match apply("{}", "not json") {
    Err(BadPatchJson(_)) => inspect("patch", content="patch")
    _ => inspect("expected BadPatchJson", content="")
  }
  match apply("{\"a\":1}", "[{\"op\":\"test\",\"path\":\"/a\",\"value\":2}]") {
    Err(PatchFailed(e)) => inspect(e.kind == TestFailed, content="true")
    _ => inspect("expected PatchFailed", content="")
  }
  match apply("{\"a\":1}", "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2}]") {
    Ok(text) =>
      inspect(
        json_equal(parse_ok(text), parse_ok("{\"a\":1,\"b\":2}")),
        content="true",
      )
    _ => inspect("expected ok", content="")
  }
}
