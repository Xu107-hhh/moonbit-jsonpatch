///|
/// Benchmark harness: `moon run --release benches`.
///
/// Measures apply / diff / merge over object- and array-shaped documents
/// of growing size. Documents are generated deterministically (seeded
/// RNG); every timed closure re-uses the same inputs because the library
/// is immutable — applying a patch never consumes the input document.
fn main {
  let bench = @bench.Bench()
  let sizes = [1_000, 10_000, 100_000]
  // iterations per size: big documents are slower, use fewer repeats
  let counts = [500, 100, 10]
  for i, n in sizes {
    let runs = counts[i]
    // chacha8 requires a 32-byte seed; this one is fixed so runs are
    // reproducible (same documents and patches on every machine)
    let r = @random.Rand::chacha8(seed=b"0123456789abcdef0123456789abcdef")
    // object apply: 100 mixed operations on an n-key object
    let obj = make_object(n)
    let obj_patch = make_object_patch(n, r)
    bench.bench(
      () => ignore(@lib.apply_patch(obj, obj_patch)),
      name="apply/object-\{n} (100 ops)",
      count=runs.reinterpret_as_uint(),
    )
    // array apply: 100 replace+append operations on an n-item array
    let arr = make_array(n)
    let arr_patch = make_array_patch(n, r)
    bench.bench(
      () => ignore(@lib.apply_patch(arr, arr_patch)),
      name="apply/array-\{n} (100 ops)",
      count=runs.reinterpret_as_uint(),
    )
    // diff between two n-key objects (10% changed / 5% removed / 5% added)
    let original = make_object(n)
    let modified = tweaked_object(n)
    bench.bench(
      () => ignore(@lib.diff(original, modified)),
      name="diff/object-\{n}",
      count=runs.reinterpret_as_uint(),
    )
    // diff between two n-item arrays (10% changed, 10% grown)
    let arr_a = make_array(n)
    let arr_b = tweaked_array(n)
    bench.bench(
      () => ignore(@lib.diff(arr_a, arr_b)),
      name="diff/array-\{n}",
      count=runs.reinterpret_as_uint(),
    )
    // merge patch into an object of n/10 sub-objects with 10 members each
    let target = nested_object(n)
    let merge_p = merge_patch_for(n)
    bench.bench(
      () => ignore(@lib.merge_patch(target, merge_p)),
      name="merge/nested-\{n}",
      count=runs.reinterpret_as_uint(),
    )
  }
  println(bench.dump_summaries())
}

///|
/// An object with n members: `k<i>` keys with mixed number/string/bool
/// values, plus `d<i>` keys reserved for remove operations.
fn make_object(n : Int) -> Json {
  let m : Map[String, Json] = Map([])
  for i = 0; i < n; i = i + 1 {
    let v : Json = match i % 3 {
      0 => Json::number(i.to_double())
      1 => Json::string("v\{i}")
      _ => if i % 2 == 0 { Json::boolean(true) } else { Json::boolean(false) }
    }
    m.set("k\{i}", v)
  }
  for i = 0; i < OPS; i = i + 1 {
    m.set("d\{i}", Json::number(i.to_double()))
  }
  Json::object(m)
}

///|
/// An array with n items: mostly numbers, every 4th a string.
fn make_array(n : Int) -> Json {
  let a : Array[Json] = []
  for i = 0; i < n; i = i + 1 {
    if i % 4 == 3 {
      a.push(Json::string("s\{i}"))
    } else {
      a.push(Json::number(i.to_double()))
    }
  }
  Json::array(a)
}

///|
/// A patch with OPS operations over disjoint key families so that every
/// operation sequence is valid: replaces touch `k*`, adds create `new*`,
/// removes delete `d*` (never re-referenced afterwards).
fn make_object_patch(n : Int, r : @random.Rand) -> Json {
  let ops : Array[Json] = []
  for i = 0; i < OPS; i = i + 1 {
    let op : Map[String, Json] = Map([])
    let kind = r.int(limit=3)
    if kind == 0 {
      op.set("op", Json::string("replace"))
      op.set("path", Json::string("/k\{r.int(limit=n)}"))
      op.set("value", Json::number(i.to_double()))
    } else if kind == 1 {
      op.set("op", Json::string("add"))
      op.set("path", Json::string("/new\{i}"))
      op.set("value", Json::string("added-\{i}"))
    } else {
      op.set("op", Json::string("remove"))
      op.set("path", Json::string("/d\{i}"))
    }
    ops.push(Json::object(op))
  }
  Json::array(ops)
}

///|
/// A patch with OPS operations over an array: replaces never shift
/// indices and `-` always appends, so any mix is valid in any order.
fn make_array_patch(n : Int, r : @random.Rand) -> Json {
  let ops : Array[Json] = []
  for i = 0; i < OPS; i = i + 1 {
    let op : Map[String, Json] = Map([])
    if r.int(limit=4) == 0 {
      op.set("op", Json::string("add"))
      op.set("path", Json::string("/-"))
      op.set("value", Json::number(i.to_double()))
    } else {
      op.set("op", Json::string("replace"))
      op.set("path", Json::string("/\{r.int(limit=n)}"))
      op.set("value", Json::number(i.to_double()))
    }
    ops.push(Json::object(op))
  }
  Json::array(ops)
}

///|
/// A deterministic variant of `make_object`: every 10th value changed,
/// every 20th key missing, plus n/20 extra keys.
fn tweaked_object(n : Int) -> Json {
  let m : Map[String, Json] = Map([])
  for i = 0; i < n; i = i + 1 {
    if i % 20 == 5 {
      continue // removed in the modified version
    }
    let v : Json = match i % 3 {
      0 =>
        if i % 10 == 0 {
          Json::number(-1.0)
        } else {
          Json::number(i.to_double())
        }
      1 =>
        if i % 10 == 0 {
          Json::string("changed-\{i}")
        } else {
          Json::string("v\{i}")
        }
      _ => if i % 2 == 0 { Json::boolean(true) } else { Json::boolean(false) }
    }
    m.set("k\{i}", v)
  }
  for i = 0; i < n / 20; i = i + 1 {
    m.set("extra\{i}", Json::string("e\{i}"))
  }
  Json::object(m)
}

///|
/// A deterministic variant of `make_array`: every 10th value changed,
/// plus a 10% longer tail.
fn tweaked_array(n : Int) -> Json {
  let a : Array[Json] = []
  for i = 0; i < n + n / 10; i = i + 1 {
    if i >= n {
      a.push(Json::number(i.to_double()))
    } else if i % 4 == 3 {
      if i % 10 == 3 {
        a.push(Json::string("changed-\{i}"))
      } else {
        a.push(Json::string("s\{i}"))
      }
    } else if i % 10 == 0 {
      a.push(Json::number(-1.0))
    } else {
      a.push(Json::number(i.to_double()))
    }
  }
  Json::array(a)
}

///|
/// An object of n/10 sub-objects with 10 members each — merge patches
/// recurse into these, so this exercises the deep-merge path.
fn nested_object(n : Int) -> Json {
  let m : Map[String, Json] = Map([])
  for i = 0; i < n / 10; i = i + 1 {
    let inner : Map[String, Json] = Map([])
    for j = 0; j < 10; j = j + 1 {
      inner.set("m\{j}", Json::number((i * 10 + j).to_double()))
    }
    m.set("o\{i}", Json::object(inner))
  }
  Json::object(m)
}

///|
/// A merge patch over `nested_object`: replace one member per third
/// sub-object, delete (null) another, and add fresh sub-objects.
fn merge_patch_for(n : Int) -> Json {
  let m : Map[String, Json] = Map([])
  for i = 0; i < n / 30; i = i + 1 {
    let inner : Map[String, Json] = Map([])
    inner.set("m0", Json::number(-1.0))
    inner.set("m1", Json::null())
    m.set("o\{i * 3}", Json::object(inner))
  }
  for i = 0; i < n / 100; i = i + 1 {
    let inner : Map[String, Json] = Map([])
    inner.set("x", Json::string("new-\{i}"))
    m.set("added\{i}", Json::object(inner))
  }
  Json::object(m)
}

///|
/// Patch operations per apply benchmark.
const OPS : Int = 100
