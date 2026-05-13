// Hash_test.res — regression tests for the hash / equality semantics.
// These guard the documented contract: primitives are hashed/compared by value;
// non-primitives (objects, functions, symbols) are hashed/compared by identity.

open Vitest

describe("Hash — primitive hashing", () => {
  test("equal primitives hash to the same value", () => {
    expect(Hash.hash(42))->toBe(Hash.hash(42))
    expect(Hash.hash("hello"))->toBe(Hash.hash("hello"))
    expect(Hash.hash(true))->toBe(Hash.hash(true))
    expect(Hash.hash(false))->toBe(Hash.hash(false))
    expect(Hash.hash(true) == Hash.hash(false))->toBe(false)
  })

  test("integer-valued floats and ints hash equally", () => {
    expect(Hash.hash(3))->toBe(Hash.hash(3.0))
  })

  test("non-integer floats use the IEEE-754 hash path", () => {
    expect(Hash.hash(3.14))->toBe(Hash.hash(3.14))
    expect(Hash.hash(3.14) == Hash.hash(2.71))->toBe(false)
  })

  test("equals is === for primitives", () => {
    expect(Hash.equals(1, 1))->toBe(true)
    expect(Hash.equals("x", "x"))->toBe(true)
    expect(Hash.equals(1, 2))->toBe(false)
    expect(Hash.equals("x", "y"))->toBe(false)
  })
})

describe("Hash — object identity (regression)", () => {
  // The old implementation used `JSON.stringifyAny`, which:
  //   * threw on cycles,
  //   * silently dropped `undefined` / functions / symbols,
  //   * was order-dependent on property insertion,
  //   * gave a single hash for every Date / Map / Set / RegExp.
  // The new implementation falls back on identity hashing via a WeakMap.

  test("two structurally-equal objects are NOT equal (identity semantics)", () => {
    let a = {"x": 1, "y": 2}
    let b = {"x": 1, "y": 2}
    expect(Hash.equals(a, b))->toBe(false)
    expect(Hash.equals(a, a))->toBe(true)
  })

  test("the same object hashes to the same value across calls", () => {
    let a = {"x": 1}
    let h1 = Hash.hash(a)
    let h2 = Hash.hash(a)
    expect(h1)->toBe(h2)
  })

  test("distinct objects (overwhelmingly) hash to different values", () => {
    let a = {"x": 1}
    let b = {"x": 1}
    // Identity counter is monotonic + mixed, so consecutive allocations
    // never collide.
    expect(Hash.hash(a) == Hash.hash(b))->toBe(false)
  })

  test("cyclic objects do not throw (regression: JSON.stringify would throw)", () => {
    let cyclic = Dict.make()
    Dict.set(cyclic, "self", Obj.magic(cyclic))
    // Just shouldn't throw. Hash is some stable identity int.
    let h = Hash.hash(cyclic)
    expect(h == Hash.hash(cyclic))->toBe(true)
  })

  test("functions can be used as keys without throwing", () => {
    let f = () => 1
    let g = () => 1
    let h1 = Hash.hash(f)
    expect(h1)->toBe(Hash.hash(f))
    expect(Hash.equals(f, g))->toBe(false)
    expect(Hash.equals(f, f))->toBe(true)
  })

  test("null hashes to 0 and equals itself", () => {
    expect(Hash.hash(Null.null))->toBe(0)
    expect(Hash.equals(Null.null, Null.null))->toBe(true)
  })
})

describe("PersistentHashMap with object keys uses identity", () => {
  module M = PersistentHashMap

  test("the same object key round-trips", () => {
    let k = {"id": 1}
    let m = M.make()->M.set(k, "v")
    expect(M.getExn(m, k))->toBe("v")
    expect(M.has(m, k))->toBe(true)
  })

  test("structurally-equal but distinct objects are different keys", () => {
    let k1 = {"id": 1}
    let k2 = {"id": 1}
    let m = M.make()->M.set(k1, "a")->M.set(k2, "b")
    expect(M.size(m))->toBe(2)
    expect(M.getExn(m, k1))->toBe("a")
    expect(M.getExn(m, k2))->toBe("b")
  })
})
