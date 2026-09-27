///|
/// Random JSON generators for property-based tests. Object keys include
/// `/` and `~` on purpose: diff must emit correctly escaped pointers for
/// them, and the round-trip properties below would catch any mistake.
let keys : Array[String] = ["a", "b", "c", "k~0", "k/1", "x"]

///|
/// Widen an Int to UInt64 for seed arithmetic.
pub fn u64(i : Int) -> UInt64 {
  i.to_int64().reinterpret_as_uint64()
}

///|
/// Leaf values: null / numbers / strings / booleans.
pub fn gen_leaf() -> @quickcheck.Generator[Json] {
  @quickcheck.one_of([
    @quickcheck.pure(Json::null()),
    @quickcheck.int_range(-1000, 1000).map(i => Json::number(i.to_double())),
    @quickcheck.elements(["a", "b", "hello", "x~y", "p/q"]).map(s => {
      Json::string(s)
    }),
    @quickcheck.elements([true, false]).map(b => Json::boolean(b)),
  ])
}

///|
/// Random documents of bounded depth/width, built recursively through
/// `sized`: small sizes collapse to leaves so termination is structural.
pub fn gen_json() -> @quickcheck.Generator[Json] {
  @quickcheck.sized(size => {
    if size <= 1 {
      gen_leaf()
    } else {
      let child = gen_json().resize(size / 2)
      let kv = @quickcheck.elements(keys).flat_map(k => child.map(v => (k, v)))
      @quickcheck.one_of([
        gen_leaf(),
        gen_leaf(),
        @quickcheck.int_range(0, 5)
        .flat_map(n => child.array_with_size(n))
        .map(a => Json::array(a)),
        @quickcheck.int_range(0, 5)
        .flat_map(n => kv.array_with_size(n))
        .map(pairs => {
          let m : Map[String, Json] = Map([])
          for p in pairs {
            m.set(p.0, p.1)
          }
          Json::object(m)
        }),
      ])
    }
  })
}

///|
/// A keyed task board: items carry a unique `id` in ascending order, so
/// two boards' shared ids always keep the same relative order — exactly
/// the shape `diff_keyed` matches by identity.
pub fn board_from_values(count : Int, seed : UInt64) -> Json {
  let items : Array[Json] = []
  for i = 0; i < count; i = i + 1 {
    let v = ((seed >> (i * 3)) & 255UL).to_int() - 128
    let m : Map[String, Json] = Map([])
    m.set("id", Json::number(i.to_double()))
    m.set("v", Json::number(v.to_double()))
    m.set("done", Json::boolean(((seed >> i) & 1UL) == 1UL))
    items.push(Json::object(m))
  }
  Json::array(items)
}

///|
/// Variant of a board: drops some ids, tweaks kept values, and inserts
/// fresh ids (>= 100) between survivors — the common ids stay in order,
/// so the keyed path is exercised, not the fallback.
pub fn board_variant(board : Json, seed : UInt64) -> Json {
  let items : Array[Json] = []
  let next_fresh = 100
  match board {
    Array(a) => {
      for i, item in a {
        // drop roughly one item in three
        if ((seed >> (i + 1)) & 3UL) == 0UL {
          continue
        }
        // sometimes insert a fresh item before a survivor
        if ((seed >> i) & 3UL) == 3UL {
          items.push(fresh_item(next_fresh + items.length()))
        }
        items.push(tweak_item(item, seed + u64(i)))
      }
      if (seed & 1UL) == 1UL {
        items.push(fresh_item(next_fresh + items.length()))
      }
    }
    _ => ()
  }
  Json::array(items)
}

///|
pub fn fresh_item(id : Int) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("id", Json::number(id.to_double()))
  m.set("v", Json::number((-id).to_double()))
  m.set("done", Json::boolean(false))
  Json::object(m)
}

///|
/// Change one field of a board item.
pub fn tweak_item(item : Json, seed : UInt64) -> Json {
  match item {
    Object(o) => {
      let m : Map[String, Json] = Map([])
      for k, v in o {
        m.set(k, v)
      }
      m.set("v", Json::number(((seed & 63UL).to_int() - 32).to_double()))
      Json::object(m)
    }
    _ => item
  }
}

///|
/// The core property: applying the generated diff back to the original
/// must reproduce the target — for positional diff and (via the board
/// generators) for keyed diff, whose fallback paths the plain random
/// documents also exercise.
pub fn roundtrip_ok(a : Json, b : Json, key : String?) -> Bool {
  let ops = match key {
    Some(k) => @jsonpatch.diff_keyed(a, b, k)
    None => @jsonpatch.diff(a, b)
  }
  match @jsonpatch.apply_patch(a, ops) {
    Ok(r) => @jsonpatch.json_equal(r, b)
    Err(_) => false
  }
}
