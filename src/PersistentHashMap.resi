// PersistentHashMap.resi — public surface of the persistent hash map.
//
// Hash Array Mapped Trie (HAMT) with bitmap-compressed `BitmapIndexed` nodes
// and `HashCollision` leaves. Branching factor 32, max depth 7.
// O(log32 N) `get` / `set` / `remove`.

/** Opaque persistent hash map. */
type t<'k, 'v>

/** Empty map. */
let make: unit => t<'k, 'v>

/** Number of entries. */
let size: t<'k, 'v> => int

/** True iff the map contains no entries. */
let isEmpty: t<'k, 'v> => bool

/** O(log32 N) lookup. */
let get: (t<'k, 'v>, 'k) => option<'v>

/** O(log32 N) lookup. Throws `Not_found` if `key` is absent. */
let getExn: (t<'k, 'v>, 'k) => 'v

/** True iff `key` is present. */
let has: (t<'k, 'v>, 'k) => bool

/** Returns a new map with `(key, value)` inserted or replaced. */
let set: (t<'k, 'v>, 'k, 'v) => t<'k, 'v>

/** Returns a new map without `key`. No-op if `key` is absent. */
let remove: (t<'k, 'v>, 'k) => t<'k, 'v>

/** Iterate every `(key, value)` entry. Iteration order is unspecified. */
let forEach: (t<'k, 'v>, ('k, 'v) => unit) => unit

/** Left fold over `(key, value)` entries. */
let reduce: (t<'k, 'v>, 'acc, ('acc, 'k, 'v) => 'acc) => 'acc

/** All keys, in iteration order. */
let keys: t<'k, 'v> => array<'k>

/** All values, in iteration order. */
let values: t<'k, 'v> => array<'v>

/** All `(key, value)` pairs, in iteration order. */
let entries: t<'k, 'v> => array<('k, 'v)>

/** Build a map from an array of `(key, value)` pairs. Later pairs win on
    duplicates. */
let fromEntries: array<('k, 'v)> => t<'k, 'v>

/** JS-style iterator step — `{value: None, done: true}` once exhausted. */
type iterStep<'a> = {value: option<'a>, done: bool}

/** JS-style iterator. */
type iter<'a> = {next: unit => iterStep<'a>}

/** Build a JS-style iterator yielding `(key, value)` pairs. */
let iterator: t<'k, 'v> => iter<('k, 'v)>

/** Entry-wise equality under user-supplied `eq` on values; keys use the
    library's standard hash/equality. */
let equals: (t<'k, 'v>, t<'k, 'v>, ('v, 'v) => bool) => bool

/** Right-biased merge: entries from `b` override those from `a`. */
let merge: (t<'k, 'v>, t<'k, 'v>) => t<'k, 'v>

/** Returns a new map with all values transformed by `f`. Keys are preserved. */
let map: (t<'k, 'v>, 'v => 'w) => t<'k, 'w>

/** Returns a new map containing only entries for which `f(key, value)` is true. */
let filter: (t<'k, 'v>, ('k, 'v) => bool) => t<'k, 'v>

/** Atomically read-modify-write a key.
    `f` receives `Some(v)` if the key exists, `None` if absent.
    Return `Some(newV)` to insert/replace, `None` to delete. */
let update: (t<'k, 'v>, 'k, option<'v> => option<'v>) => t<'k, 'v>

// ───────────────────────── transient (mutable) builder ─────────────────────────

/** Opaque transient (in-place mutable) hash map. Use only between
    {!asTransient} and {!persistent}; reusing a transient after {!persistent}
    throws. */
type transient<'k, 'v>

/** Open a transient builder around `m`. */
let asTransient: t<'k, 'v> => transient<'k, 'v>

/** Insert / replace `(key, value)` in place. Returns the same transient for
    chaining. */
let setMut: (transient<'k, 'v>, 'k, 'v) => transient<'k, 'v>

/** Remove `key` in place. Returns the same transient for chaining. */
let removeMut: (transient<'k, 'v>, 'k) => transient<'k, 'v>

/** Look up on a transient. */
let getMut: (transient<'k, 'v>, 'k) => option<'v>

/** Freeze a transient back into a persistent map. The transient must not be
    used afterwards. */
let persistent: transient<'k, 'v> => t<'k, 'v>

/** Convenience: `withTransient(m, f)` is `m |> asTransient |> f |> persistent`. */
let withTransient: (t<'k, 'v>, transient<'k, 'v> => transient<'k, 'v>) => t<'k, 'v>
