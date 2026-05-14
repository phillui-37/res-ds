// PersistentHashMap_test.res
open Vitest
module M = PersistentHashMap

describe("PersistentHashMap — basics", () => {
  test("empty map has size 0 and missing keys return None", () => {
    let m = M.make()
    expect(M.size(m))->toBe(0)
    expect(M.get(m, "missing"))->toEqual(None)
    expect(M.has(m, "missing"))->toBe(false)
  })

  test("set / get / has round-trip", () => {
    let m = M.make()->M.set("a", 1)->M.set("b", 2)->M.set("c", 3)
    expect(M.size(m))->toBe(3)
    expect(M.get(m, "a"))->toEqual(Some(1))
    expect(M.get(m, "b"))->toEqual(Some(2))
    expect(M.get(m, "c"))->toEqual(Some(3))
    expect(M.has(m, "a"))->toBe(true)
    expect(M.has(m, "z"))->toBe(false)
  })

  test("setting an existing key replaces, not grows", () => {
    let m = M.make()->M.set("a", 1)->M.set("a", 9)
    expect(M.size(m))->toBe(1)
    expect(M.getExn(m, "a"))->toBe(9)
  })

  test("structural sharing: removing from a copy does not affect the original", () => {
    let a = M.fromEntries([("a", 1), ("b", 2), ("c", 3)])
    let b = M.remove(a, "b")
    expect(M.has(a, "b"))->toBe(true)
    expect(M.has(b, "b"))->toBe(false)
    expect(M.size(a))->toBe(3)
    expect(M.size(b))->toBe(2)
  })

  test("remove on non-existent key is a no-op (returns same map)", () => {
    let a = M.fromEntries([("a", 1)])
    let b = M.remove(a, "z")
    expect(M.size(b))->toBe(1)
    expect(b === a)->toBe(true)
  })

  test("large random insert / lookup (10 000 string keys)", () => {
    let n = 10_000
    let m = ref(M.make())
    for i in 0 to n - 1 {
      m := M.set(m.contents, "key-" ++ Int.toString(i), i)
    }
    expect(M.size(m.contents))->toBe(n)
    for i in 0 to n - 1 {
      expect(M.getExn(m.contents, "key-" ++ Int.toString(i)))->toBe(i)
    }
    // remove half
    for i in 0 to n / 2 - 1 {
      m := M.remove(m.contents, "key-" ++ Int.toString(i))
    }
    expect(M.size(m.contents))->toBe(n / 2)
    expect(M.get(m.contents, "key-0"))->toEqual(None)
    expect(M.getExn(m.contents, "key-" ++ Int.toString(n - 1)))->toBe(n - 1)
  })

  test("keys/values/entries sizes match", () => {
    let m = M.fromEntries([("x", 1), ("y", 2), ("z", 3)])
    expect(Array.length(M.keys(m)))->toBe(3)
    expect(Array.length(M.values(m)))->toBe(3)
    expect(Array.length(M.entries(m)))->toBe(3)
  })

  test("forEach visits every entry exactly once", () => {
    let m = M.fromEntries([("a", 1), ("b", 2), ("c", 3), ("d", 4)])
    let total = ref(0)
    M.forEach(m, (_, v) => total := total.contents + v)
    expect(total.contents)->toBe(10)
  })

  test("iterator yields all entries", () => {
    let n = 200
    let pairs = Array.fromInitializer(~length=n, i => ("k" ++ Int.toString(i), i))
    let m = M.fromEntries(pairs)
    let it = M.iterator(m)
    let seen = ref(0)
    let keep = ref(true)
    while keep.contents {
      let step = it.next()
      if step.done {
        keep := false
      } else {
        seen := seen.contents + 1
      }
    }
    expect(seen.contents)->toBe(n)
  })

  test("merge combines two maps; right wins on conflict", () => {
    let a = M.fromEntries([("a", 1), ("b", 2)])
    let b = M.fromEntries([("b", 99), ("c", 3)])
    let m = M.merge(a, b)
    expect(M.size(m))->toBe(3)
    expect(M.getExn(m, "a"))->toBe(1)
    expect(M.getExn(m, "b"))->toBe(99)
    expect(M.getExn(m, "c"))->toBe(3)
  })

  test("equals compares structurally", () => {
    let a = M.fromEntries([("a", 1), ("b", 2)])
    let b = M.fromEntries([("b", 2), ("a", 1)])
    expect(M.equals(a, b, (x, y) => x == y))->toBe(true)
    expect(M.equals(a, M.set(b, "a", 99), (x, y) => x == y))->toBe(false)
  })
})

describe("PersistentHashMap — collision handling", () => {
  test("two keys with the same hash both round-trip", () => {
    // The string keys "Aa" and "BB" share the *same* Java-style 32-bit hash.
    // (Aa: 'A'*31 + 'a' = 31*65 + 97 = 2112; BB: 31*66 + 66 = 2112.)
    // That equality is preserved through our mix32 finalizer, so they exercise
    // the HashCollision path inside the HAMT.
    let h1 = Hash.hashString("Aa")
    let h2 = Hash.hashString("BB")
    expect(h1)->toBe(h2)
    let m = M.make()->M.set("Aa", 1)->M.set("BB", 2)
    expect(M.size(m))->toBe(2)
    expect(M.getExn(m, "Aa"))->toBe(1)
    expect(M.getExn(m, "BB"))->toBe(2)
    let m2 = M.remove(m, "Aa")
    expect(M.size(m2))->toBe(1)
    expect(M.get(m2, "Aa"))->toEqual(None)
    expect(M.getExn(m2, "BB"))->toBe(2)
  })

  test("colliding and non-colliding keys coexist correctly", () => {
    // "Aa" and "BB" share the same Java-style 32-bit hash (verified above);
    // "AaAa" hashes to a completely different value. We mix all three so
    // the test exercises both the HashCollision branch ("Aa"/"BB") and a
    // regular BitmapIndexed branch ("AaAa") inside the same map.
    let keys = ["Aa", "BB", "AaAa"]
    expect(Hash.hashString("Aa"))->toBe(Hash.hashString("BB"))
    expect(Hash.hashString("Aa") == Hash.hashString("AaAa"))->toBe(false)
    let m = M.fromEntries(Array.mapWithIndex(keys, (k, i) => (k, i)))
    expect(M.size(m))->toBe(3)
    Array.forEachWithIndex(keys, (k, i) => expect(M.getExn(m, k))->toBe(i))
  })
})

describe("PersistentHashMap — null/undefined key distinction", () => {
  test("null and undefined keys are distinct", () => {
    let m: M.t<Nullable.t<string>, int> = M.make()
      ->M.set(Nullable.null, 1)
      ->M.set(Nullable.undefined, 2)
    expect(M.size(m))->toBe(2)
    expect(M.get(m, Nullable.null))->toEqual(Some(1))
    expect(M.get(m, Nullable.undefined))->toEqual(Some(2))
  })

  test("entries preserves the original key (null stays null, undefined stays undefined)", () => {
    let m: M.t<Nullable.t<string>, int> = M.make()->M.set(Nullable.null, 42)
    let es = M.entries(m)
    expect(Array.length(es))->toBe(1)
    let (k, v) = Array.getUnsafe(es, 0)
    expect(k === Nullable.null)->toBe(true)
    expect(v)->toBe(42)
  })

  test("remove null does not remove undefined", () => {
    let m: M.t<Nullable.t<string>, int> = M.make()
      ->M.set(Nullable.null, 1)
      ->M.set(Nullable.undefined, 2)
    let m2 = M.remove(m, Nullable.null)
    expect(M.has(m2, Nullable.null))->toBe(false)
    expect(M.get(m2, Nullable.undefined))->toEqual(Some(2))
  })
})

describe("PersistentHashMap — transients", () => {
  test("setMut + persistent preserves correctness for 5000 entries", () => {
    let n = 5000
    let m = M.withTransient(M.make(), t => {
      let cur = ref(t)
      for i in 0 to n - 1 {
        cur := M.setMut(cur.contents, "k" ++ Int.toString(i), i)
      }
      cur.contents
    })
    expect(M.size(m))->toBe(n)
    for i in 0 to n - 1 {
      expect(M.getExn(m, "k" ++ Int.toString(i)))->toBe(i)
    }
  })

  test("transient does not affect original map", () => {
    let original = M.fromEntries([("a", 1), ("b", 2)])
    let extended = M.withTransient(original, t => {
      M.setMut(t, "c", 3)->ignore
      M.setMut(t, "d", 4)->ignore
      t
    })
    expect(M.size(original))->toBe(2)
    expect(M.size(extended))->toBe(4)
    expect(M.has(original, "c"))->toBe(false)
    expect(M.has(extended, "c"))->toBe(true)
  })

  test("using a transient after persistent! throws", () => {
    let t = M.asTransient(M.fromEntries([("a", 1)]))
    let _ = M.persistent(t)
    expect(() => M.setMut(t, "b", 2)->ignore)->toThrow
  })
})

describe("PersistentHashMap — lazy iterator", () => {
  test("iterator yields exactly size elements", () => {
    let n = 1000
    let m = ref(M.make())
    for i in 0 to n - 1 {
      m := M.set(m.contents, i, i * 2)
    }
    let it = M.iterator(m.contents)
    let count = ref(0)
    let step = ref(it.next())
    while !step.contents.done {
      count := count.contents + 1
      step := it.next()
    }
    expect(count.contents)->toBe(n)
  })

  test("iterator terminates correctly with null/undefined keys", () => {
    let m = M.make()
      ->M.set(Obj.magic(Null.null), 0)
      ->M.set(Obj.magic(undefined), 1)
      ->M.set("a", 2)
    let it = M.iterator(m)
    let count = ref(0)
    let step = ref(it.next())
    while !step.contents.done {
      count := count.contents + 1
      step := it.next()
    }
    expect(count.contents)->toBe(3)
  })

  test("isEmpty returns true for empty map", () => {
    expect(M.isEmpty(M.make()))->toBe(true)
    expect(M.isEmpty(M.set(M.make(), "a", 1)))->toBe(false)
  })
})

describe("PersistentHashMap — map/filter/update", () => {
  test("map transforms all values", () => {
    let m = M.fromEntries([("a", 1), ("b", 2), ("c", 3)])
    let m2 = M.map(m, v => v * 10)
    expect(M.getExn(m2, "a"))->toBe(10)
    expect(M.getExn(m2, "b"))->toBe(20)
    expect(M.size(m2))->toBe(3)
    // original unchanged
    expect(M.getExn(m, "a"))->toBe(1)
  })

  test("filter keeps only matching entries", () => {
    let m = M.fromEntries([("a", 1), ("b", 2), ("c", 3)])
    let m2 = M.filter(m, (_, v) => v > 1)
    expect(M.size(m2))->toBe(2)
    expect(M.has(m2, "a"))->toBe(false)
    expect(M.has(m2, "b"))->toBe(true)
  })

  test("update inserts when key absent", () => {
    let m = M.make()
    let m2 = M.update(m, "x", _ => Some(42))
    expect(M.getExn(m2, "x"))->toBe(42)
  })

  test("update modifies existing key", () => {
    let m = M.fromEntries([("x", 10)])
    let m2 = M.update(m, "x", v => Some(Option.getOr(v, 0) + 5))
    expect(M.getExn(m2, "x"))->toBe(15)
  })

  test("update removes key when f returns None", () => {
    let m = M.fromEntries([("x", 10)])
    let m2 = M.update(m, "x", _ => None)
    expect(M.has(m2, "x"))->toBe(false)
    expect(M.size(m2))->toBe(0)
  })

  test("map with null and undefined keys", () => {
    let m = M.make()
      ->M.set("a", 1)
      ->M.set(Obj.magic(Null.null), 2)
      ->M.set(Obj.magic(undefined), 3)
    let m2 = M.map(m, v => v * 10)
    expect(M.get(m2, "a"))->toEqual(Some(10))
    expect(M.get(m2, Obj.magic(Null.null)))->toEqual(Some(20))
    expect(M.get(m2, Obj.magic(undefined)))->toEqual(Some(30))
  })

  test("filter with null and undefined keys", () => {
    let m = M.make()
      ->M.set("a", 1)
      ->M.set(Obj.magic(Null.null), 2)
      ->M.set(Obj.magic(undefined), 3)
    let m2 = M.filter(m, (_, v) => v > 1)
    expect(M.size(m2))->toBe(2)
    expect(M.get(m2, "a"))->toEqual(None)
    expect(M.get(m2, Obj.magic(Null.null)))->toEqual(Some(2))
    expect(M.get(m2, Obj.magic(undefined)))->toEqual(Some(3))
  })

  test("update absent key with f returning None is a no-op", () => {
    let m = M.make()
    let m2 = M.update(m, "x", _ => None)
    expect(M.size(m2))->toBe(0)
  })
})
