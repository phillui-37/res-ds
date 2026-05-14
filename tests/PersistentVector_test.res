// PersistentVector_test.res
open Vitest
module V = PersistentVector

describe("PersistentVector — basics", () => {
  test("empty vector has size 0", () => {
    expect(V.size(V.make()))->toBe(0)
  })

  test("push/get round-trip for small vectors", () => {
    let v = V.fromArray([1, 2, 3, 4, 5])
    expect(V.size(v))->toBe(5)
    expect(V.getExn(v, 0))->toBe(1)
    expect(V.getExn(v, 4))->toBe(5)
    expect(V.get(v, 5))->toEqual(None)
  })

  test("set returns a new vector and preserves the old", () => {
    let v = V.fromArray([10, 20, 30])
    let w = V.set(v, 1, 99)
    expect(V.getExn(v, 1))->toBe(20)
    expect(V.getExn(w, 1))->toBe(99)
    expect(V.size(w))->toBe(3)
  })

  test("set at index == size acts like push (conj)", () => {
    let v = V.fromArray([1, 2])
    let w = V.set(v, 2, 3)
    expect(V.toArray(w))->toEqual([1, 2, 3])
  })

  test("pop removes the last element", () => {
    let v = V.fromArray([1, 2, 3])
    let w = V.pop(v)
    expect(V.size(w))->toBe(2)
    expect(V.toArray(w))->toEqual([1, 2])
  })

  test("pop on empty vector throws Invalid_argument", () => {
    let msg = ref("")
    try { let _ = V.pop(V.make()); () } catch {
    | Invalid_argument(m) => msg := m
    }
    expect(msg.contents)->toBe("PersistentVector.pop: empty vector")
  })

  test("set with negative index throws Invalid_argument", () => {
    let v = V.fromArray([1, 2, 3])
    let msg = ref("")
    try { let _ = V.set(v, -1, 0); () } catch {
    | Invalid_argument(m) => msg := m
    }
    expect(msg.contents)->toBe("PersistentVector.set: index out of bounds")
  })

  test("set with index > size throws Invalid_argument", () => {
    let v = V.fromArray([1, 2, 3])
    let msg = ref("")
    try { let _ = V.set(v, 4, 0); () } catch {
    | Invalid_argument(m) => msg := m
    }
    expect(msg.contents)->toBe("PersistentVector.set: index out of bounds")
  })

  test("setMut with out-of-bounds index throws Invalid_argument", () => {
    let t = V.asTransient(V.fromArray([1, 2, 3]))
    let msg = ref("")
    try { let _ = V.setMut(t, -1, 0); () } catch {
    | Invalid_argument(m) => msg := m
    }
    expect(msg.contents)->toBe("PersistentVector.setMut: index out of bounds")
  })

  test("toArray round-trip on a 1000-element vector (crosses tail boundary)", () => {
    let n = 1000
    let arr = Array.fromInitializer(~length=n, i => i)
    let v = V.fromArray(arr)
    expect(V.size(v))->toBe(n)
    expect(V.toArray(v))->toEqual(arr)
  })

  test("structural sharing: setting one element does not mutate the original", () => {
    let v = V.fromArray(Array.fromInitializer(~length=200, i => i))
    let w = V.set(v, 100, -1)
    expect(V.getExn(v, 100))->toBe(100)
    expect(V.getExn(w, 100))->toBe(-1)
  })

  test("push/pop stress crosses multiple trie levels (10 000 elements)", () => {
    let n = 10_000
    let v = ref(V.make())
    for i in 0 to n - 1 {
      v := V.push(v.contents, i)
    }
    expect(V.size(v.contents))->toBe(n)
    for i in 0 to n - 1 {
      expect(V.getExn(v.contents, i))->toBe(i)
    }
    // pop everything back down.
    for _ in 1 to n {
      v := V.pop(v.contents)
    }
    expect(V.size(v.contents))->toBe(0)
  })

  test("forEach / reduce / map / filter", () => {
    let v = V.fromArray([1, 2, 3, 4, 5])
    let sum = V.reduce(v, 0, (acc, x) => acc + x)
    expect(sum)->toBe(15)
    expect(V.toArray(V.map(v, x => x * 2)))->toEqual([2, 4, 6, 8, 10])
    expect(V.toArray(V.filter(v, x => mod(x, 2) == 0)))->toEqual([2, 4])
  })

  test("iterator yields every element exactly once", () => {
    let n = 100
    let v = V.fromArray(Array.fromInitializer(~length=n, i => i))
    let it = V.iterator(v)
    let seen = []
    let go = ref(true)
    while go.contents {
      let step = it.next()
      if step.done {
        go := false
      } else {
        switch step.value {
        | Some(x) => Array.push(seen, x)
        | None => ()
        }
      }
    }
    expect(seen)->toEqual(Array.fromInitializer(~length=n, i => i))
  })
})

describe("PersistentVector — first/last", () => {
  test("first/last return None on empty vector", () => {
    let v = V.make()
    expect(V.first(v))->toEqual(None)
    expect(V.last(v))->toEqual(None)
  })

  test("first/last return correct elements", () => {
    let v = V.fromArray([10, 20, 30])
    expect(V.first(v))->toEqual(Some(10))
    expect(V.last(v))->toEqual(Some(30))
  })

  test("firstExn/lastExn throw on empty", () => {
    expect(() => V.firstExn(V.make()))->toThrow
    expect(() => V.lastExn(V.make()))->toThrow
  })
})

describe("PersistentVector — transients", () => {
  test("transient pushMut + persistent matches the persistent path", () => {
    let n = 5_000
    let built = V.withTransient(V.make(), t => {
      let cur = ref(t)
      for i in 0 to n - 1 {
        cur := V.pushMut(cur.contents, i)
      }
      cur.contents
    })
    expect(V.size(built))->toBe(n)
    Array.forEach([0, 31, 32, 33, 1023, 1024, 1025, n - 1], i => {
      expect(V.getExn(built, i))->toBe(i)
    })
  })

  test("transient setMut updates in place", () => {
    let v = V.fromArray(Array.fromInitializer(~length=100, i => i))
    let w = V.withTransient(v, t => {
      let cur = ref(t)
      for i in 0 to 99 {
        cur := V.setMut(cur.contents, i, i * 10)
      }
      cur.contents
    })
    // original is untouched
    expect(V.getExn(v, 50))->toBe(50)
    expect(V.getExn(w, 50))->toBe(500)
  })

  test("using a transient after persistent! throws", () => {
    let t = V.asTransient(V.fromArray([1, 2, 3]))
    let _ = V.persistent(t)
    expect(() => V.pushMut(t, 4)->ignore)->toThrow
  })

  test("equals short-circuits: comparator not called after first mismatch", () => {
    let calls = ref(0)
    let eq = (a, b) => {
      calls := calls.contents + 1
      a == b
    }
    let a = V.fromArray(Array.fromInitializer(~length=64, i => i))
    let b = V.set(a, 0, -1) // differ at index 0
    let _ = V.equals(a, b, eq)
    // Without short-circuit the inner for-loop calls eq 32 times for the
    // first leaf block. With short-circuit it calls eq exactly once.
    expect(calls.contents)->toBe(1)
  })

  test("isEmpty returns true for empty vector", () => {
    expect(V.isEmpty(V.make()))->toBe(true)
    expect(V.isEmpty(V.fromArray([1])))->toBe(false)
  })
})

describe("PersistentVector — slice/concat", () => {
  test("slice returns sub-range", () => {
    let v = V.fromArray([0, 1, 2, 3, 4])
    expect(V.toArray(V.slice(v, 1, 4)))->toEqual([1, 2, 3])
  })

  test("slice with clamped bounds returns empty", () => {
    let v = V.fromArray([0, 1, 2])
    expect(V.size(V.slice(v, 5, 10)))->toBe(0)
    expect(V.size(V.slice(v, 2, 1)))->toBe(0)
  })

  test("slice full range equals original", () => {
    let arr = Array.fromInitializer(~length=100, i => i)
    let v = V.fromArray(arr)
    expect(V.toArray(V.slice(v, 0, 100)))->toEqual(arr)
  })

  test("concat two vectors", () => {
    let a = V.fromArray([1, 2, 3])
    let b = V.fromArray([4, 5, 6])
    expect(V.toArray(V.concat(a, b)))->toEqual([1, 2, 3, 4, 5, 6])
  })

  test("concat with empty is identity", () => {
    let v = V.fromArray([1, 2, 3])
    expect(V.toArray(V.concat(v, V.make())))->toEqual([1, 2, 3])
    expect(V.toArray(V.concat(V.make(), v)))->toEqual([1, 2, 3])
  })

  test("concat large vectors (crosses trie boundaries)", () => {
    let a = V.fromArray(Array.fromInitializer(~length=500, i => i))
    let b = V.fromArray(Array.fromInitializer(~length=500, i => 500 + i))
    let c = V.concat(a, b)
    expect(V.size(c))->toBe(1000)
    expect(V.getExn(c, 999))->toBe(999)
  })
})
