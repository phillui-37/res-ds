# res-ds API Reference

> All modules are re-exported from the top-level `ResDs` barrel:
> `ResDs.Hash`, `ResDs.Vector`, `ResDs.HashMap`, `ResDs.HashSet`, `ResDs.PersistentQueue`.

---

## `Hash`

Hashing and equality utilities. All hash functions satisfy:
`Hash.equals(a, b) => Hash.hash(a) == Hash.hash(b)`.

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `mix32` | `int => int` | MurmurHash3 32-bit finalizer (avalanche mixer). | O(1) |
| `hashInt` | `int => int` | Hash a 32-bit integer. | O(1) |
| `hashBool` | `bool => int` | Hash a boolean (true→1231, false→1237). | O(1) |
| `hashString` | `string => int` | Java-style String.hashCode mixed through `mix32`. | O(N) where N = string length |
| `hashFloat` | `float => int` | Hash a float by mixing its two IEEE-754 32-bit halves. | O(1) |
| `identityHash` | `'a => int` | Stable 32-bit identity hash backed by a `WeakMap`. Each distinct object gets a unique hash on first call. | O(1) amortised |
| `hash` | `'a => int` | Generic hash: by value for primitives, by identity for everything else. | O(1) for non-strings; O(N) for strings |
| `equals` | `('a, 'a) => bool` | Generic equality: `===` for primitives and objects. | O(1) |
| `mask` | `(int, int) => int` | Extract the 5-bit trie index from a hash at a given shift level. | O(1) |
| `popcount` | `int => int` | Count set bits in a 32-bit integer (used for bitmap compression). | O(1) |
| `bitpos` | `(int, int) => int` | Bit position for the 5-bit slice of `hash` at `shift`. | O(1) |
| `arrayIndex` | `(int, int) => int` | Dense array index of a bit inside a bitmap-compressed array. | O(1) |

---

## `Vector` (`PersistentVector`)

Persistent (immutable) vector backed by a 32-way bitmapped trie with a 32-element tail buffer.
Structural sharing means unchanged paths are shared between old and new versions.

**Notation:** N = number of elements. log N means log₃₂ N ≈ effectively constant for all practical sizes.

### Construction

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `make` | `unit => t<'a>` | Empty vector. | O(1) |
| `fromArray` | `array<'a> => t<'a>` | Build from a JS array. | O(N) |

### Query

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `size` | `t<'a> => int` | Number of elements. | O(1) |
| `length` | `t<'a> => int` | Alias for `size`. | O(1) |
| `isEmpty` | `t<'a> => bool` | True iff empty. | O(1) |
| `get` | `(t<'a>, int) => option<'a>` | Element at index, or `None` if out of bounds. | O(log N) |
| `getExn` | `(t<'a>, int) => 'a` | Element at index. Throws `Not_found` if out of bounds. | O(log N) |
| `first` | `t<'a> => option<'a>` | First element, or `None` if empty. | O(1) |
| `last` | `t<'a> => option<'a>` | Last element, or `None` if empty. | O(1) |
| `firstExn` | `t<'a> => 'a` | First element. Throws `Not_found` if empty. | O(1) |
| `lastExn` | `t<'a> => 'a` | Last element. Throws `Not_found` if empty. | O(1) |

### Modification

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `push` | `(t<'a>, 'a) => t<'a>` | New vector with `x` appended. | O(log N) amortised |
| `pop` | `t<'a> => t<'a>` | New vector with the last element removed. Throws `Invalid_argument` if empty. | O(log N) amortised |
| `set` | `(t<'a>, int, 'a) => t<'a>` | New vector with element `i` replaced. If `i == size`, equivalent to `push`. Throws `Invalid_argument` if `i` outside `[0, size]`. | O(log N) |

### Transformation

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `map` | `(t<'a>, 'a => 'b) => t<'b>` | New vector with every element transformed by `f`. | O(N) |
| `filter` | `(t<'a>, 'a => bool) => t<'a>` | New vector keeping only elements satisfying `f`. | O(N) |
| `slice` | `(t<'a>, int, int) => t<'a>` | Sub-vector of elements `[start, end_)`, clamped to `[0, size]`. | O(K) where K = slice length |
| `concat` | `(t<'a>, t<'a>) => t<'a>` | New vector with all elements of `b` appended to `a`. | O(M log N) where M = size of `b` |

### Search / Predicate

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `find` | `(t<'a>, 'a => bool) => option<'a>` | First element satisfying `f`, or `None`. Short-circuits. | O(N) worst case |
| `findIndex` | `(t<'a>, 'a => bool) => option<int>` | Index of first element satisfying `f`, or `None`. Short-circuits. | O(N) worst case |
| `some` | `(t<'a>, 'a => bool) => bool` | True iff any element satisfies `f`. Short-circuits. | O(N) worst case |
| `every` | `(t<'a>, 'a => bool) => bool` | True iff all elements satisfy `f`. Short-circuits. | O(N) worst case |

### Iteration

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `forEach` | `(t<'a>, 'a => unit) => unit` | Call `f` on every element in order. | O(N) |
| `forEachWithIndex` | `(t<'a>, ('a, int) => unit) => unit` | Call `f` on every (element, index) pair in order. | O(N) |
| `reduce` | `(t<'a>, 'b, ('b, 'a) => 'b) => 'b` | Left fold. | O(N) |
| `toArray` | `t<'a> => array<'a>` | Materialise to a JS array. | O(N) |
| `equals` | `(t<'a>, t<'a>, ('a, 'a) => bool) => bool` | Element-wise equality under user-supplied `eq`. Short-circuits on first mismatch. | O(N) worst case |
| `iterator` | `t<'a> => iter<'a>` | JS-style lazy iterator. `.next()` is O(log N) per step. | O(1) to create |

### Transient (Mutable Builder)

Use transients for bulk construction — avoid O(N log N) overhead of repeated persistent updates.

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `asTransient` | `t<'a> => transient<'a>` | Open a mutable builder around an existing vector. | O(1) |
| `pushMut` | `(transient<'a>, 'a) => transient<'a>` | Append in place. Returns same transient for chaining. | O(log N) amortised |
| `setMut` | `(transient<'a>, int, 'a) => transient<'a>` | Replace element in place. If `i == size`, equivalent to `pushMut`. Throws `Invalid_argument` if out of `[0, size]`. | O(log N) |
| `getMut` | `(transient<'a>, int) => option<'a>` | Look up on a transient. | O(log N) |
| `persistent` | `transient<'a> => t<'a>` | Freeze back to persistent. The transient must not be used afterwards. | O(1) |
| `withTransient` | `(t<'a>, transient<'a> => transient<'a>) => t<'a>` | Convenience: open transient, run `f`, freeze. | O(1) overhead |

---

## `HashMap` (`PersistentHashMap`)

Persistent hash map using a Hash Array Mapped Trie (HAMT) with bitmap-compressed nodes
and hash-collision leaves. Branching factor 32, max depth 7.

Keys are hashed with `Hash.hash` and compared with `Hash.equals`:
primitives by value, objects/functions/symbols by identity.
`null` and `undefined` are supported as distinct keys.

**Notation:** N = number of entries. log N means log₃₂ N.

### Construction

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `make` | `unit => t<'k,'v>` | Empty map. | O(1) |
| `fromEntries` | `array<('k,'v)> => t<'k,'v>` | Build from array of pairs; later pairs win on duplicate keys. | O(N) |

### Query

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `size` | `t<'k,'v> => int` | Number of entries. | O(1) |
| `isEmpty` | `t<'k,'v> => bool` | True iff empty. | O(1) |
| `get` | `(t<'k,'v>, 'k) => option<'v>` | Lookup by key. | O(log N) |
| `getExn` | `(t<'k,'v>, 'k) => 'v` | Lookup. Throws `Not_found` if absent. | O(log N) |
| `has` | `(t<'k,'v>, 'k) => bool` | True iff key is present. | O(log N) |

### Modification

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `set` | `(t<'k,'v>, 'k, 'v) => t<'k,'v>` | New map with `(key,value)` inserted or replaced. | O(log N) |
| `remove` | `(t<'k,'v>, 'k) => t<'k,'v>` | New map without `key`. No-op if absent. | O(log N) |
| `update` | `(t<'k,'v>, 'k, option<'v> => option<'v>) => t<'k,'v>` | Atomic read-modify-write: `f(Some v)` to update, `f(None)` to insert. Return `None` to delete. | O(log N) |
| `merge` | `(t<'k,'v>, t<'k,'v>) => t<'k,'v>` | Right-biased union: entries from `b` override `a`. | O(M log N) where M = size of smaller map |

### Transformation

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `map` | `(t<'k,'v>, 'v => 'w) => t<'k,'w>` | New map with all values transformed. Keys preserved. | O(N) |
| `filter` | `(t<'k,'v>, ('k,'v) => bool) => t<'k,'v>` | New map keeping only entries satisfying `f`. | O(N) |

### Iteration

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `forEach` | `(t<'k,'v>, ('k,'v) => unit) => unit` | Call `f` on every `(key, value)`. Order unspecified. | O(N) |
| `reduce` | `(t<'k,'v>, 'acc, ('acc,'k,'v) => 'acc) => 'acc` | Left fold. Order unspecified. | O(N) |
| `keys` | `t<'k,'v> => array<'k>` | All keys. | O(N) |
| `values` | `t<'k,'v> => array<'v>` | All values. | O(N) |
| `entries` | `t<'k,'v> => array<('k,'v)>` | All `(key,value)` pairs. | O(N) |
| `equals` | `(t<'k,'v>, t<'k,'v>, ('v,'v) => bool) => bool` | Entry-wise equality under user `eq` on values; keys use `Hash.equals`. | O(N) |
| `iterator` | `t<'k,'v> => iter<('k,'v)>` | Lazy JS-style iterator. O(1) per step, O(log N) space. | O(1) to create |

### Transient (Mutable Builder)

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `asTransient` | `t<'k,'v> => transient<'k,'v>` | Open a mutable builder. | O(1) |
| `setMut` | `(transient<'k,'v>, 'k, 'v) => transient<'k,'v>` | Insert/replace in place. | O(log N) |
| `removeMut` | `(transient<'k,'v>, 'k) => transient<'k,'v>` | Remove in place. | O(log N) |
| `getMut` | `(transient<'k,'v>, 'k) => option<'v>` | Lookup on transient. | O(log N) |
| `persistent` | `transient<'k,'v> => t<'k,'v>` | Freeze. Transient must not be used afterwards. | O(1) |
| `withTransient` | `(t<'k,'v>, transient<'k,'v> => transient<'k,'v>) => t<'k,'v>` | Convenience open/freeze. | O(1) overhead |

---

## `HashSet` (`PersistentHashSet`)

Persistent hash set built on `HashMap` with `unit` values. All operations are O(log N).
Same key semantics as `HashMap` (value equality for primitives, identity for objects).

**Notation:** N = number of elements. log N means log₃₂ N.

### Construction

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `make` | `unit => t<'a>` | Empty set. | O(1) |
| `fromArray` | `array<'a> => t<'a>` | Build from a JS array; duplicates dropped. | O(N) |

### Query

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `size` | `t<'a> => int` | Number of elements. | O(1) |
| `isEmpty` | `t<'a> => bool` | True iff empty. | O(1) |
| `has` | `(t<'a>, 'a) => bool` | Membership test. | O(log N) |
| `equals` | `(t<'a>, t<'a>) => bool` | True iff both sets contain exactly the same elements. | O(N) |
| `isSubsetOf` | `(t<'a>, t<'a>) => bool` | True iff every element of `a` is in `b`. Short-circuits on first mismatch. | O(N) worst case |
| `isSupersetOf` | `(t<'a>, t<'a>) => bool` | True iff every element of `b` is in `a`. | O(N) worst case |

### Modification

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `add` | `(t<'a>, 'a) => t<'a>` | New set containing `x`. | O(log N) |
| `remove` | `(t<'a>, 'a) => t<'a>` | New set without `x`. No-op if absent. | O(log N) |

### Set Operations

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `union` | `(t<'a>, t<'a>) => t<'a>` | Elements in `a` or `b`. | O(M log N) |
| `intersect` | `(t<'a>, t<'a>) => t<'a>` | Elements in both `a` and `b`. | O(min(M,N) log max(M,N)) |
| `difference` | `(t<'a>, t<'a>) => t<'a>` | Elements in `a` but not in `b`. | O(M log N) |

### Transformation

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `map` | `(t<'a>, 'a => 'b) => t<'b>` | New set applying `f` to every element. Duplicates dropped. | O(N) |
| `filter` | `(t<'a>, 'a => bool) => t<'a>` | New set keeping only elements satisfying `f`. | O(N) |

### Iteration

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `forEach` | `(t<'a>, 'a => unit) => unit` | Call `f` on every element. Order unspecified. | O(N) |
| `reduce` | `(t<'a>, 'b, ('b,'a) => 'b) => 'b` | Left fold. | O(N) |
| `toArray` | `t<'a> => array<'a>` | Materialise to a JS array. Order unspecified. | O(N) |
| `iterator` | `t<'a> => iter<'a>` | Lazy JS-style iterator. O(1) per step. | O(1) to create |

### Transient (Mutable Builder)

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `asTransient` | `t<'a> => transient<'a>` | Open a mutable builder. | O(1) |
| `addMut` | `(transient<'a>, 'a) => transient<'a>` | Add in place. | O(log N) |
| `removeMut` | `(transient<'a>, 'a) => transient<'a>` | Remove in place. | O(log N) |
| `hasMut` | `(transient<'a>, 'a) => bool` | Membership test on transient. | O(log N) |
| `persistent` | `transient<'a> => t<'a>` | Freeze. Transient must not be used afterwards. | O(1) |
| `withTransient` | `(t<'a>, transient<'a> => transient<'a>) => t<'a>` | Convenience open/freeze. | O(1) overhead |

---

## `Queue` (`PersistentQueue`)

Persistent FIFO queue using the classic two-list representation.
`enqueue` appends to the `rear` list; `dequeue` consumes the `front` list,
reversing `rear` into `front` when `front` is exhausted.

**Amortised analysis:** Each element is enqueued once and reversed at most once,
so the total cost across N operations is O(N), giving O(1) amortised per operation.
A single `dequeue` on an empty `front` takes O(K) where K = size of `rear`.

### Construction

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `make` | `unit => t<'a>` | Empty queue. | O(1) |
| `fromArray` | `array<'a> => t<'a>` | Build from array; first element becomes front. | O(N) |

### Query

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `size` | `t<'a> => int` | Number of elements. | O(1) |
| `isEmpty` | `t<'a> => bool` | True iff empty. | O(1) |
| `peek` | `t<'a> => option<'a>` | Front element, or `None` if empty. | O(1) |
| `peekExn` | `t<'a> => 'a` | Front element. Throws `Not_found` if empty. | O(1) |

### Modification

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `enqueue` | `(t<'a>, 'a) => t<'a>` | New queue with `x` added at the back. | O(1) |
| `dequeue` | `t<'a> => option<('a, t<'a>)>` | Returns `Some((front, rest))`, or `None` if empty. | O(1) amortised |
| `dequeueExn` | `t<'a> => ('a, t<'a>)` | Returns `(front, rest)`. Throws `Not_found` if empty. | O(1) amortised |

### Iteration

| Function | Signature | Description | Complexity |
|----------|-----------|-------------|------------|
| `forEach` | `(t<'a>, 'a => unit) => unit` | Call `f` on every element front-to-back. | O(N) |
| `reduce` | `(t<'a>, 'b, ('b,'a) => 'b) => 'b` | Left fold front-to-back. | O(N) |
| `toArray` | `t<'a> => array<'a>` | Materialise to a JS array in front-to-back order. | O(N) |
| `map` | `(t<'a>, 'a => 'b) => t<'b>` | New queue with every element transformed, order preserved. | O(N) |
| `filter` | `(t<'a>, 'a => bool) => t<'a>` | New queue keeping only elements satisfying `f`, order preserved. | O(N) |
| `iterator` | `t<'a> => iter<'a>` | Lazy JS-style iterator (front to back). | O(1) to create; O(1) amortised per step |
