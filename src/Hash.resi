// Hash.resi — public surface of the hashing utilities.

/** MurmurHash3 finalizer. Public for advanced users that want a 32-bit mixer. */
let mix32: int => int

/** 32-bit hash of an integer. */
let hashInt: int => int

/** Java-style boolean hash — `true` → 1231, `false` → 1237. */
let hashBool: bool => int

/** Java-style String.hashCode, then mixed through {!mix32}. */
let hashString: string => int

/** Hash a JS number (double) by mixing the two 32-bit halves of its
    IEEE-754 representation. */
let hashFloat: float => int

/** Identity hash for any value, backed by a module-private `WeakMap`.
    Each distinct object gets a fresh, stable 32-bit identity on first use.
    Used internally as the fallback for {!hash} on non-primitive values. */
let identityHash: 'a => int

/** Generic hash. Hashes primitives by value (`number`, `string`, `boolean`,
    `bigint`, `undefined`, `null`) and everything else by identity (see
    {!identityHash}). Always satisfies: if `equals(a, b)` then `hash(a) == hash(b)`. */
let hash: 'a => int

/** Generic equality. JS `===` for primitives, identity (`===`) for objects /
    functions / symbols. Use primitive keys (string/int/bool) if you need
    structural equality. */
let equals: ('a, 'a) => bool

/** Mask off the 5-bit slice of a hash for a given trie level. */
let mask: (int, int) => int

/** popcount over a 32-bit integer. */
let popcount: int => int

/** Bit position for the 5-bit slice of `hash` at `shift`. */
let bitpos: (int, int) => int

/** Dense array index of `bit` inside a bitmap-compressed array. */
let arrayIndex: (int, int) => int
