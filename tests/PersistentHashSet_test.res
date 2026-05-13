// PersistentHashSet_test.res
open Vitest
module S = PersistentHashSet

describe("PersistentHashSet — basics", () => {
  test("empty set", () => {
    expect(S.size(S.make()))->toBe(0)
    expect(S.has(S.make(), "x"))->toBe(false)
  })

  test("add / has / remove", () => {
    let s = S.make()->S.add("a")->S.add("b")->S.add("a")
    expect(S.size(s))->toBe(2)
    expect(S.has(s, "a"))->toBe(true)
    expect(S.has(s, "c"))->toBe(false)
    let s2 = S.remove(s, "a")
    expect(S.size(s2))->toBe(1)
    expect(S.has(s2, "a"))->toBe(false)
    // structural sharing
    expect(S.has(s, "a"))->toBe(true)
  })

  test("set operations", () => {
    let a = S.fromArray(["a", "b", "c", "d"])
    let b = S.fromArray(["c", "d", "e", "f"])
    expect(S.size(S.union(a, b)))->toBe(6)
    let inter = S.intersect(a, b)
    expect(S.size(inter))->toBe(2)
    expect(S.has(inter, "c"))->toBe(true)
    expect(S.has(inter, "d"))->toBe(true)
    let diff = S.difference(a, b)
    expect(S.size(diff))->toBe(2)
    expect(S.has(diff, "a"))->toBe(true)
    expect(S.has(diff, "c"))->toBe(false)
  })

  test("transient batch insert", () => {
    let n = 2000
    let s = S.withTransient(S.make(), t => {
      let cur = ref(t)
      for i in 0 to n - 1 {
        cur := S.addMut(cur.contents, "x" ++ Int.toString(i))
      }
      cur.contents
    })
    expect(S.size(s))->toBe(n)
    expect(S.has(s, "x0"))->toBe(true)
    expect(S.has(s, "x1999"))->toBe(true)
    expect(S.has(s, "x2000"))->toBe(false)
  })

  test("iterator visits each element once", () => {
    let s = S.fromArray(["a", "b", "c", "d", "e"])
    let it = S.iterator(s)
    let count = ref(0)
    let keep = ref(true)
    while keep.contents {
      let step = it.next()
      if step.done {
        keep := false
      } else {
        count := count.contents + 1
      }
    }
    expect(count.contents)->toBe(5)
  })
})
