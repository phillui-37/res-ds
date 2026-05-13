// Hash.res
// 32-bit signed-integer hashing utilities used by HAMT-based collections.
// All hashes return a 32-bit signed integer (JS bitwise ops fold into int32).

module B = Int.Bitwise

// MurmurHash3 finalizer mixer — gives good avalanche for int hashes.
let mix32 = (h: int): int => {
  let h = B.lxor(h, B.lsr(h, 16))
  let h = Math.Int.imul(h, 0x85ebca6b)
  let h = B.lxor(h, B.lsr(h, 13))
  let h = Math.Int.imul(h, 0xc2b2ae35)
  let h = B.lxor(h, B.lsr(h, 16))
  B.lor(h, 0)
}

let hashInt = (n: int): int => mix32(B.lor(n, 0))

let hashBool = (b: bool): int => b ? 1231 : 1237

// Java-style String.hashCode, then mixed.
let hashString = (s: string): int => {
  let h = ref(0)
  let len = String.length(s)
  for i in 0 to len - 1 {
    let c = String.charCodeAt(s, i)->Float.toInt
    h := B.lor(Math.Int.imul(h.contents, 31) + c, 0)
  }
  mix32(h.contents)
}

// Float hash — combine the two 32-bit halves of the IEEE-754 representation.
// Buffers are hoisted to module scope so the hot path doesn't allocate.
let _floatBuf = ArrayBuffer.make(8)
let _floatF64 = Float64Array.fromBuffer(_floatBuf)
let _floatI32 = Int32Array.fromBuffer(_floatBuf)

let hashFloat = (f: float): int => {
  TypedArray.set(_floatF64, 0, f)
  let lo = TypedArray.get(_floatI32, 0)->Option.getOr(0)
  let hi = TypedArray.get(_floatI32, 1)->Option.getOr(0)
  mix32(B.lxor(lo, hi))
}

// Identity hashing for non-primitive values (objects, functions, symbols).
//
// We deliberately do NOT structurally hash objects:
//   * `JSON.stringify` throws on cycles and silently drops `undefined`,
//     functions, and symbols.
//   * `Date`, `Map`, `Set`, `RegExp`, typed arrays, and class instances all
//     stringify to ambiguous JSON.
//   * `JSON.stringify({a:1, b:2})` and `JSON.stringify({b:2, a:1})` differ —
//     property iteration order leaks into hash codes.
//
// Instead we assign each distinct object a fresh, stable 32-bit identity on
// first use, recorded in a module-private `WeakMap`. This matches JVM
// Clojure's `System.identityHashCode` fallback for non-`IHashEq` values, and
// — combined with `===` equality — gives sound, predictable behaviour:
//
//   `equals(a, b)`  ⇒  `hash(a) == hash(b)`            (identity for objects)
//   `equals(a, b)`  is `===` for objects, structural for primitives.
//
// Callers who want value-equality for their own record/object types should
// either intern the keys themselves or use primitive (string/int) keys.

@new external newWeakMap: unit => 'wm = "WeakMap"
@send external _wmGet: ('wm, 'k) => Nullable.t<int> = "get"
@send external _wmSet: ('wm, 'k, int) => unit = "set"

let _identityMap: 'wm = newWeakMap()
let _identityCounter = ref(0)

let identityHash = (v: 'a): int => {
  switch _wmGet(_identityMap, v)->Nullable.toOption {
  | Some(h) => h
  | None =>
    _identityCounter := _identityCounter.contents + 1
    let h = mix32(_identityCounter.contents)
    _wmSet(_identityMap, v, h)
    h
  }
}

// Generic hash — primitives are hashed by value, everything else by identity.
// Property: if `equals(a, b)` then `hash(a) == hash(b)`.
let hash: 'a => int = v => {
  let t = Type.typeof(v)
  switch t {
  | #number =>
    let f: float = Obj.magic(v)
    let asInt = Float.toInt(f)
    if Float.fromInt(asInt) === f {
      hashInt(asInt)
    } else {
      hashFloat(f)
    }
  | #string => hashString(Obj.magic(v))
  | #boolean => hashBool(Obj.magic(v))
  | #undefined => 0
  | #object =>
    if Obj.magic(v) === Obj.magic(Null.null) {
      0
    } else {
      identityHash(v)
    }
  | #bigint => hashString(Obj.magic(v)->Obj.magic->String.make)
  | _ => identityHash(v) // function, symbol — identity-keyed in the WeakMap.
  }
}

// Generic equality.
//   * Primitives: JS `===` (NaN ≠ NaN matches IEEE-754 and JS `Map.has`).
//   * Non-primitives: identity (`===`). Two structurally-similar objects
//     constructed independently are NOT considered equal — see `hash`
//     above for the rationale.
let equals: ('a, 'a) => bool = (a, b) => Obj.magic(a) === Obj.magic(b)

// Mask off the relevant 5 bits for a given trie level shift.
let mask = (hash: int, shift: int): int => B.land(B.lsr(hash, shift), 0x1f)

// popcount over a 32-bit int — counts populated slots in a bitmap.
let popcount = (x: int): int => {
  let x = B.lor(x, 0)
  let x = x - B.land(B.lsr(x, 1), 0x55555555)
  let x = B.land(x, 0x33333333) + B.land(B.lsr(x, 2), 0x33333333)
  let x = B.land(x + B.lsr(x, 4), 0x0f0f0f0f)
  B.land(B.lsr(Math.Int.imul(x, 0x01010101), 24), 0x3f)
}

// Bit position for a 5-bit slice and the dense index inside a bitmap-compressed array.
let bitpos = (hash: int, shift: int): int => B.lsl(1, mask(hash, shift))
let arrayIndex = (bitmap: int, bit: int): int => popcount(B.land(bitmap, bit - 1))
