// PersistentHashSet.resi — public surface of the persistent hash set.
//
// Built on {!PersistentHashMap} with `unit` values. All ops are O(log32 N).

/** Opaque persistent hash set. */
type t<'a>

/** Empty set. */
let make: unit => t<'a>

/** Number of elements. */
let size: t<'a> => int

/** True iff the set contains no elements. */
let isEmpty: t<'a> => bool

/** True iff `x` is in the set. */
let has: (t<'a>, 'a) => bool

/** Returns a new set containing `x`. */
let add: (t<'a>, 'a) => t<'a>

/** Returns a new set without `x`. No-op if absent. */
let remove: (t<'a>, 'a) => t<'a>

/** Build a set from a JS array. */
let fromArray: array<'a> => t<'a>

/** Materialise the set into a JS array. Order is unspecified. */
let toArray: t<'a> => array<'a>

/** Iterate every element. */
let forEach: (t<'a>, 'a => unit) => unit

/** Left fold. */
let reduce: (t<'a>, 'b, ('b, 'a) => 'b) => 'b

/** Set union — every element in `a` or `b`. */
let union: (t<'a>, t<'a>) => t<'a>

/** Set intersection — elements in both `a` and `b`. */
let intersect: (t<'a>, t<'a>) => t<'a>

/** Set difference — elements in `a` but not in `b`. */
let difference: (t<'a>, t<'a>) => t<'a>

/** JS-style iterator step — `{value: None, done: true}` once exhausted. */
type iterStep<'a> = {value: option<'a>, done: bool}

/** JS-style iterator. */
type iter<'a> = {next: unit => iterStep<'a>}

/** Build a JS-style iterator over the elements. */
let iterator: t<'a> => iter<'a>

// ───────────────────────── transient (mutable) builder ─────────────────────────

/** Opaque transient (in-place mutable) set. */
type transient<'a>

/** Open a transient builder around `s`. */
let asTransient: t<'a> => transient<'a>

/** Add `x` in place. */
let addMut: (transient<'a>, 'a) => transient<'a>

/** Remove `x` in place. */
let removeMut: (transient<'a>, 'a) => transient<'a>

/** Look up on a transient. */
let hasMut: (transient<'a>, 'a) => bool

/** Freeze a transient back into a persistent set. The transient must not be
    used afterwards. */
let persistent: transient<'a> => t<'a>

/** Convenience: `withTransient(s, f)` is `s |> asTransient |> f |> persistent`. */
let withTransient: (t<'a>, transient<'a> => transient<'a>) => t<'a>
