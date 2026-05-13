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
let hashFloat = (f: float): int => {
  let buf = ArrayBuffer.make(8)
  let f64 = Float64Array.fromBuffer(buf)
  let i32v = Int32Array.fromBuffer(buf)
  TypedArray.set(f64, 0, f)
  let lo = TypedArray.get(i32v, 0)->Option.getOr(0)
  let hi = TypedArray.get(i32v, 1)->Option.getOr(0)
  mix32(B.lxor(lo, hi))
}

// Generic hash — best-effort dispatch over runtime type.
// Mirrors Clojure's principle: if `equals(a, b)` then `hash(a) == hash(b)`.
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
      hashString(JSON.stringifyAny(v)->Option.getOr(""))
    }
  | _ => hashString(JSON.stringifyAny(v)->Option.getOr(""))
  }
}

// Generic structural equality. Uses JS `===` for primitives and JSON for objects.
let equals: ('a, 'a) => bool = (a, b) => {
  if Obj.magic(a) === Obj.magic(b) {
    true
  } else {
    let ta = Type.typeof(a)
    let tb = Type.typeof(b)
    if ta !== tb {
      false
    } else {
      switch ta {
      | #object =>
        if Obj.magic(a) === Obj.magic(Null.null) || Obj.magic(b) === Obj.magic(Null.null) {
          false
        } else {
          JSON.stringifyAny(a) == JSON.stringifyAny(b)
        }
      | _ => false
      }
    }
  }
}

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
