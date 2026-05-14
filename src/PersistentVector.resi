// PersistentVector.resi — public surface of the persistent vector.
//
// 32-way bitmapped trie + 32-element tail buffer.
// O(log32 N) for `get` / `set` / `push` / `pop`; effectively O(1) on the tail.

/** Opaque persistent vector. */
type t<'a>

/** Empty vector. */
let make: unit => t<'a>

/** Number of elements. */
let size: t<'a> => int

/** Alias for {!size}. */
let length: t<'a> => int

/** True iff the vector contains no elements. */
let isEmpty: t<'a> => bool

/** O(log32 N) lookup. Returns `None` when `i` is out of bounds. */
let get: (t<'a>, int) => option<'a>

/** O(log32 N) lookup. Throws `Not_found` when `i` is out of bounds. */
let getExn: (t<'a>, int) => 'a

/** Returns a new vector with `x` appended. O(log32 N) amortised. */
let push: (t<'a>, 'a) => t<'a>

/** Returns a new vector with element `i` replaced by `x`.
    If `i == size`, equivalent to {!push} (appends `x`).
    Throws `Invalid_argument` if `i` is out of `[0, size]`. */
let set: (t<'a>, int, 'a) => t<'a>

/** Returns a new vector with the last element removed.
    Throws `Invalid_argument` on an empty vector. */
let pop: t<'a> => t<'a>

/** Build a vector from a JS array. */
let fromArray: array<'a> => t<'a>

/** Materialise the vector into a JS array. */
let toArray: t<'a> => array<'a>

/** Iterate every element in order. */
let forEach: (t<'a>, 'a => unit) => unit

/** Iterate every (element, index) pair in order. */
let forEachWithIndex: (t<'a>, ('a, int) => unit) => unit

/** Left fold. */
let reduce: (t<'a>, 'b, ('b, 'a) => 'b) => 'b

/** Map every element through `f`. */
let map: (t<'a>, 'a => 'b) => t<'b>

/** Keep elements satisfying `f`. */
let filter: (t<'a>, 'a => bool) => t<'a>

/** Element-wise equality under user-supplied `eq`. */
let equals: (t<'a>, t<'a>, ('a, 'a) => bool) => bool

/** JS-style iterator step — `{value: None, done: true}` once exhausted. */
type iterStep<'a> = {value: option<'a>, done: bool}

/** JS-style iterator. Call `.next()` repeatedly. */
type iter<'a> = {next: unit => iterStep<'a>}

/** Build a JS-style iterator over the vector's elements. */
let iterator: t<'a> => iter<'a>

/** O(1). First element, or `None` if empty. */
let first: t<'a> => option<'a>

/** O(1). Last element, or `None` if empty. */
let last: t<'a> => option<'a>

/** O(1). First element. Throws `Not_found` if empty. */
let firstExn: t<'a> => 'a

/** O(1). Last element. Throws `Not_found` if empty. */
let lastExn: t<'a> => 'a

// ───────────────────────── transient (mutable) builder ─────────────────────────

/** Opaque transient (in-place mutable) vector. Use only between {!asTransient}
    and {!persistent}; reusing a transient after {!persistent} throws. */
type transient<'a>

/** Open a transient builder around `v`. */
let asTransient: t<'a> => transient<'a>

/** Append `x` in place. Returns the same transient for chaining. */
let pushMut: (transient<'a>, 'a) => transient<'a>

/** Replace element `i` in place. If `i == size`, equivalent to {!pushMut}.
    Throws `Invalid_argument` if `i` is out of `[0, size]`. */
let setMut: (transient<'a>, int, 'a) => transient<'a>

/** Look up element `i` on a transient. */
let getMut: (transient<'a>, int) => option<'a>

/** Freeze a transient back into a persistent vector. The transient must not
    be used afterwards. */
let persistent: transient<'a> => t<'a>

/** Convenience: `withTransient(v, f)` is `v |> asTransient |> f |> persistent`. */
let withTransient: (t<'a>, transient<'a> => transient<'a>) => t<'a>
