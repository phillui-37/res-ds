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

  test("isEmpty returns true for empty set", () => {
    expect(S.isEmpty(S.make()))->toBe(true)
    expect(S.isEmpty(S.add(S.make(), 1)))->toBe(false)
  })
})

describe("PersistentHashSet — equals/subset/superset/filter/map", () => {
  test("equals returns true for identical content", () => {
    let a = S.fromArray([1, 2, 3])
    let b = S.fromArray([3, 1, 2])
    expect(S.equals(a, b))->toBe(true)
  })

  test("equals returns false when content differs", () => {
    let a = S.fromArray([1, 2, 3])
    let b = S.fromArray([1, 2, 4])
    expect(S.equals(a, b))->toBe(false)
    expect(S.equals(S.fromArray([1, 2]), S.fromArray([1, 2, 3])))->toBe(false)
  })

  test("isSubsetOf", () => {
    let a = S.fromArray([1, 2])
    let b = S.fromArray([1, 2, 3])
    expect(S.isSubsetOf(a, b))->toBe(true)
    expect(S.isSubsetOf(b, a))->toBe(false)
    expect(S.isSubsetOf(a, a))->toBe(true)
  })

  test("isSupersetOf", () => {
    let a = S.fromArray([1, 2, 3])
    let b = S.fromArray([1, 2])
    expect(S.isSupersetOf(a, b))->toBe(true)
    expect(S.isSupersetOf(b, a))->toBe(false)
  })

  test("filter keeps only matching elements", () => {
    let s = S.fromArray([1, 2, 3, 4, 5])
    let even = S.filter(s, x => Int.mod(x, 2) == 0)
    expect(S.size(even))->toBe(2)
    expect(S.has(even, 2))->toBe(true)
    expect(S.has(even, 1))->toBe(false)
  })

  test("map transforms elements", () => {
    let s = S.fromArray([1, 2, 3])
    let doubled = S.map(s, x => x * 2)
    expect(S.has(doubled, 2))->toBe(true)
    expect(S.has(doubled, 4))->toBe(true)
    expect(S.has(doubled, 6))->toBe(true)
    expect(S.size(doubled))->toBe(3)
  })

  test("empty set edge cases", () => {
    let empty = S.make()
    let nonEmpty = S.fromArray([1, 2, 3])
    expect(S.equals(empty, empty))->toBe(true)
    expect(S.isSubsetOf(empty, nonEmpty))->toBe(true)
    expect(S.isSubsetOf(empty, empty))->toBe(true)
    expect(S.isSupersetOf(nonEmpty, empty))->toBe(true)
    expect(S.size(S.filter(empty, _ => true)))->toBe(0)
    expect(S.size(S.map(empty, x => x)))->toBe(0)
  })
})
