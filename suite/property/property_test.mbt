///|
/// Property-based round-trips over random documents (fixed seeds, so a
/// failure is reproducible): positional diff, keyed diff (fallback paths
/// included), keyed boards (the identity-matched path), merge-patch
/// idempotence, and input immutability.
test "property: positional diff round-trips random documents" {
  for i = 0; i < 80; i = i + 1 {
    let a = gen_json().sample(size=8, seed=u64(i))
    let b = gen_json().sample(size=8, seed=u64(100_000 + i))
    if !roundtrip_ok(a, b, None) {
      println("counterexample seeds (\{i}, \{100_000 + i}):")
      println("a = \{a.stringify()}")
      println("b = \{b.stringify()}")
      inspect("roundtrip failed", content="")
    }
  }
}

///|
test "property: keyed diff round-trips the same random documents" {
  for i = 0; i < 80; i = i + 1 {
    let a = gen_json().sample(size=8, seed=u64(200_000 + i))
    let b = gen_json().sample(size=8, seed=u64(300_000 + i))
    // random documents are rarely key-eligible; they exercise the
    // fallback, which must round-trip exactly like positional diff
    if !roundtrip_ok(a, b, Some("id")) {
      println("counterexample seeds (\{200_000 + i}, \{300_000 + i}):")
      println("a = \{a.stringify()}")
      println("b = \{b.stringify()}")
      inspect("keyed roundtrip failed", content="")
    }
  }
}

///|
test "property: keyed diff round-trips identity-matched boards" {
  for i = 0; i < 60; i = i + 1 {
    let count = i % 7
    let seed = i.to_uint64() * 7919UL + 13UL
    let a = board_from_values(count, seed)
    let b = board_variant(a, seed * 3UL + 1UL)
    if !roundtrip_ok(a, b, Some("id")) {
      println("counterexample i=\{i}:")
      println("a = \{a.stringify()}")
      println("b = \{b.stringify()}")
      inspect("board roundtrip failed", content="")
    }
  }
}

///|
test "property: merge patch is idempotent" {
  for i = 0; i < 80; i = i + 1 {
    let t = gen_json().sample(size=8, seed=u64(400_000 + i))
    let p = gen_json().sample(size=6, seed=u64(500_000 + i))
    let once = @jsonpatch.merge_patch(t, p)
    let twice = @jsonpatch.merge_patch(once, p)
    if !@jsonpatch.json_equal(once, twice) {
      println("counterexample i=\{i}:")
      println("t = \{t.stringify()}")
      println("p = \{p.stringify()}")
      inspect("merge not idempotent", content="")
    }
  }
}

///|
test "property: applying a patch never mutates its input" {
  for i = 0; i < 80; i = i + 1 {
    let a = gen_json().sample(size=8, seed=u64(600_000 + i))
    let b = gen_json().sample(size=8, seed=u64(700_000 + i))
    let before = a.stringify()
    let ops = @jsonpatch.diff(a, b)
    ignore(@jsonpatch.apply_patch(a, ops))
    if a.stringify() != before {
      println("input mutated, i=\{i}:")
      println("before = \{before}")
      println("after  = \{a.stringify()}")
      inspect("mutation detected", content="")
    }
  }
}
