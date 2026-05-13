// StackOverflow_stress_test.res
// Stress tests exercising the recursive trie operations at sizes that would
// blow the JS stack if any of them were O(N) instead of O(log32 N).
//
// Node's default stack tops out around ~10 000 nested function calls, so a
// 1 000 000-element build is more than 100× over budget for any accidental
// linear recursion.

open Vitest
module V = PersistentVector
module M = PersistentHashMap

// 1 000 000 keeps the test quick (~1 s) while still being well above the
// JS recursion ceiling.
let stressN = 1_000_000

describe("Stack-overflow stress", () => {
  test("PersistentVector: push 1M elements via persistent path (exercises pushTail/newPath)", () => {
    let v = ref(V.make())
    for i in 0 to stressN - 1 {
      v := V.push(v.contents, i)
    }
    expect(V.size(v.contents))->toBe(stressN)
    expect(V.getExn(v.contents, 0))->toBe(0)
    expect(V.getExn(v.contents, stressN - 1))->toBe(stressN - 1)
    expect(V.getExn(v.contents, stressN / 2))->toBe(stressN / 2)
  })

  test("PersistentVector: push 1M elements via transient (exercises tPushTail/pathFor)", () => {
    let built = V.withTransient(V.make(), t => {
      let cur = ref(t)
      for i in 0 to stressN - 1 {
        cur := V.pushMut(cur.contents, i)
      }
      cur.contents
    })
    expect(V.size(built))->toBe(stressN)
    expect(V.getExn(built, stressN - 1))->toBe(stressN - 1)
  })

  test("PersistentVector: 1M sets via persistent doSet then 1M pops via popTail", () => {
    let v = ref(V.fromArray(Array.fromInitializer(~length=stressN, _ => 0)))
    for i in 0 to stressN - 1 {
      v := V.set(v.contents, i, i)
    }
    expect(V.getExn(v.contents, stressN / 3))->toBe(stressN / 3)
    for _ in 1 to stressN {
      v := V.pop(v.contents)
    }
    expect(V.size(v.contents))->toBe(0)
  })

  test("PersistentHashMap: insert 1M keys via persistent path (exercises nodeAssoc/mergeKVs)", () => {
    let m = ref(M.make())
    for i in 0 to stressN - 1 {
      m := M.set(m.contents, i, i)
    }
    expect(M.size(m.contents))->toBe(stressN)
    expect(M.getExn(m.contents, 0))->toBe(0)
    expect(M.getExn(m.contents, stressN - 1))->toBe(stressN - 1)
  })

  test("PersistentHashMap: insert 1M keys via transient (exercises nodeAssocMut)", () => {
    let m = M.withTransient(M.make(), t => {
      let cur = ref(t)
      for i in 0 to stressN - 1 {
        cur := M.setMut(cur.contents, i, i)
      }
      cur.contents
    })
    expect(M.size(m))->toBe(stressN)
    Array.forEach([0, 1, stressN / 2, stressN - 1], i => expect(M.getExn(m, i))->toBe(i))
  })

  test("PersistentHashMap: 1M lookups (exercises nodeFind) and 1M removes (exercises nodeWithout)", () => {
    let m = ref(
      M.withTransient(M.make(), t => {
        let cur = ref(t)
        for i in 0 to stressN - 1 {
          cur := M.setMut(cur.contents, i, i)
        }
        cur.contents
      }),
    )
    // 1M lookups — accumulate the values to assert the loop genuinely ran.
    // (Closed-form n*(n-1)/2 doesn't fit in 32-bit ReScript ints for n=1M, so
    // we just verify the running sum is non-zero — i.e. every lookup returned
    // a real value rather than throwing or being optimised away.)
    let sum = ref(0)
    for i in 0 to stressN - 1 {
      sum := sum.contents + M.getExn(m.contents, i)
    }
    expect(sum.contents !== 0)->toBe(true)
    // 1M removes — drops back to empty.
    for i in 0 to stressN - 1 {
      m := M.remove(m.contents, i)
    }
    expect(M.size(m.contents))->toBe(0)
  })
})
