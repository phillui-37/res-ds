# res-ds

Clojure-inspired persistent (immutable) data structures, implemented in
**ReScript 12**, scaffolded with **Vite** + **pnpm** and tested with
**Vitest**.

The library is dependency-light — it uses `@rescript/core` and **does not**
use the deprecated `Belt` modules.

## Collections

| Module                | What it is                                                                  |
|----------------------|------------------------------------------------------------------------------|
| `PersistentVector`   | 32-way bitmapped trie with a 32-element tail buffer (Clojure's persistent vector). O(log₃₂ N) lookup / update / push / pop. New: `isEmpty`, `first`/`last`, `slice`/`concat`, `find`/`findIndex`/`some`/`every`. |
| `PersistentHashMap`  | Hash Array Mapped Trie (HAMT) with **bitmap-compressed** nodes, **hash-collision** nodes, and 5-bit branching. O(log₃₂ N) get / set / remove. New: `isEmpty`, `map`/`filter`/`update`. |
| `PersistentHashSet`  | Built on top of `PersistentHashMap`; element-type `'a`, value `unit`. New: `isEmpty`, `equals`/`isSubsetOf`/`isSupersetOf`/`filter`/`map`. |
| `PersistentQueue`    | Persistent FIFO queue (two-list, amortised O(1) enqueue/dequeue). |

### Advanced features

- **Bitmap compression** — each `BitmapIndexed` HAMT node stores a 32-bit
  bitmap and a *dense* array containing only the populated slots. Slot ↔ index
  conversion uses `popcount`. See `Hash.popcount`, `Hash.bitpos`,
  `Hash.arrayIndex`.
- **Transient (in-place mutable) variants** for both vector and hashmap with
  an `edit`-token ownership protocol (`asTransient` / `*Mut` / `persistent`).
  Building a 5 000-element collection via a transient is dramatically
  cheaper than chaining persistent operations. Reusing a transient after
  `persistent` throws `Invalid_argument`.
- **Hash-collision optimisation** — when two distinct keys hash to the same
  32-bit value the HAMT degrades into a `HashCollision` leaf that supports
  full O(k) linear probe within the colliding bucket while every other path
  in the trie remains O(log₃₂ N).
- **JS-style iterators** — `iterator(coll).next() → {value, done}` for the
  vector, hashmap, and hashset.
- **Structural sharing** — every "mutating" persistent operation returns a
  new collection that shares all unchanged subtrees with the previous one.
- **`.resi` interface files** — every public module ships a `.resi`,
  so the published API surface is small, stable, and documented.

### Key equality semantics

`PersistentHashMap` and `PersistentHashSet` use the generic `Hash.hash` /
`Hash.equals` pair. They are defined as follows:

| Key kind | Equality | Hash |
|---|---|---|
| `int` / `float` / `string` / `bool` / `bigint` | JS `===` (value) | by value |
| `null` / `undefined` | JS `===` | `0` |
| Anything else (object, array, function, symbol, `Date`, `Map`, …) | JS `===` (**identity**) | stable identity, backed by an internal `WeakMap` |

In particular, **two structurally-equal but separately-constructed objects are
*not* equal as keys**:

```rescript
let a = {"id": 1}
let b = {"id": 1}
M.make()->M.set(a, "x")->M.set(b, "y")->M.size  // 2
```

If you need value-equality on a record/object key, intern the key (e.g. use
its `id` as a string/int key) or build a wrapper key type. This matches
Clojure's `System.identityHashCode` fallback for non-`IHashEq` values and is
*sound* — the previous JSON-based fallback threw on cycles, mishandled
`Date` / `Map` / `Set` / functions / `undefined`, and was sensitive to
property-insertion order.

## Getting started

```sh
pnpm install
pnpm test           # build ReScript + run the Vitest suite (102 tests, ~6 s)
pnpm bench          # build + run the benchmark harness (Node ≥20)
pnpm build          # produce ESM bundle in dist/
pnpm res:watch      # ReScript incremental rebuild
```

## Usage

```rescript
module V = ResDs.Vector
module M = ResDs.HashMap
module S = ResDs.HashSet

let v = V.fromArray([1, 2, 3])->V.push(4)
let _ = V.getExn(v, 3) // 4

let m = M.make()->M.set("a", 1)->M.set("b", 2)
let _ = M.getExn(m, "a") // 1

// Bulk-build via a transient — much faster for large N.
let big = M.withTransient(M.make(), t => {
  for i in 0 to 99_999 {
    M.setMut(t, "k" ++ Int.toString(i), i)->ignore
  }
  t
})

let s = S.fromArray(["a", "b"])
let _ = S.union(s, S.fromArray(["b", "c"])) // {a, b, c}
```

## Project layout

```
src/
  Hash.res(i)                – 32-bit hash + popcount / bitpos / arrayIndex
  PersistentVector.res(i)    – Bitmapped trie + tail + transient
  PersistentHashMap.res(i)   – HAMT + collision nodes + transient
  PersistentHashSet.res(i)   – Set built on the hashmap
  PersistentQueue.res(i)     – Persistent FIFO queue (two-list)
  ResDs.res(i)               – Public barrel module
tests/
  Vitest.res                 – Bindings to vitest globals
  Hash_test.res
  PersistentVector_test.res
  PersistentHashMap_test.res
  PersistentHashSet_test.res
  PersistentQueue_test.res
  StackOverflow_stress_test.res
bench/
  Bench.res                  – Comparison vs @rescript/core Map/Array
.github/workflows/ci.yml     – Build + test on Node 20 / 22
rescript.json                – ReScript 12 config (esmodule, .res.mjs)
vite.config.js               – Vite build + Vitest config
package.json                 – pnpm scripts + npm publishing metadata
LICENSE                      – MIT
```

## Recursion depth & stack-overflow stress tests

Every recursive function in `PersistentVector` (`pushTail`, `pathFor`, `newPath`,
`doSet`, `popTail`, `tPushTail`) descends one trie level per call — bounded by
`shift / 5 ≤ 7`. Every recursive function in `PersistentHashMap` (`nodeFind`,
`nodeAssoc`, `nodeAssocMut`, `nodeWithout`, `mergeKVs`) has the same property
(at most 7 frames, since 5-bit slices of a 32-bit hash give a max trie height
of `⌈32/5⌉ = 7`).

To guard this property against future regressions, `tests/StackOverflow_stress_test.res`
runs **1 000 000-element** builds, lookups, sets, pops and removes for both
collections and asserts they complete:

```text
✓ Stack-overflow stress (6 tests) 5.3 s
   ✓ PersistentVector  1M push (persistent)         (exercises pushTail/newPath)
   ✓ PersistentVector  1M push (transient)          (exercises tPushTail/pathFor)
   ✓ PersistentVector  1M sets + 1M pops            (exercises doSet/popTail)
   ✓ PersistentHashMap 1M set (persistent)          (exercises nodeAssoc/mergeKVs)
   ✓ PersistentHashMap 1M setMut (transient)        (exercises nodeAssocMut)
   ✓ PersistentHashMap 1M get + 1M remove           (exercises nodeFind/nodeWithout)
```

Node's default JS stack tops out at roughly 10 000 nested calls, so 1 000 000
operations is two orders of magnitude over budget for any accidental linear
recursion — the suite catches it immediately.

## Benchmark

`pnpm bench` runs `bench/Bench.res` and prints results similar to the table
below. We compare against the collections that ship in `@rescript/core`,
which are thin bindings over JavaScript's native (mutable) `Map` and `Array`:

* "**Core Array push**" / "**Core Map set**" — raw mutable in-place operation.
  This is the unbeatable lower bound for throughput.
* "**Core Array concat**" / "**Core Map clone+set**" — the *immutable*
  equivalent: produce a fresh container per write. This is the apples-to-apples
  comparison for what res-ds gives you.
* "**res-ds … (persistent)**" — the natural immutable API.
* "**res-ds … (transient)**" — the in-place transient builder, which yields
  an immutable result at the end.

Numbers below are from a single run on Node v24, average ms per full run of N
operations. Lower is better. Note the **logarithmic gulf** between the
immutable copy patterns and our persistent collections.

### Vector vs Array

| Operation                                 | N = 10 000 | N = 100 000 |
|------------------------------------------|-----------:|------------:|
| res-ds Vector  push (persistent)         |    1.11 ms |    11.32 ms |
| res-ds Vector  pushMut (transient)       |    0.41 ms |     3.74 ms |
| Core Array     push  (mutable in-place)  |    0.07 ms |     1.34 ms |
| Core Array     concat (immutable copy)   |   21.37 ms | 20 287.58 ms |
| res-ds Vector  full random get sweep     |    0.54 ms |     2.67 ms |
| Core Array     full random get sweep     |    0.06 ms |     0.26 ms |
| res-ds Vector  set (one element)         |  0.001 ms  |    < 0.001 ms |
| Core Array     set (immutable copy)      |  0.006 ms  |     0.39 ms |

* **Transient push** is within 3× of the mutable `Array.push` lower bound and
  still produces an immutable result.
* For an immutable-result workload, `Array.concat` is **~1800× slower** than
  `V.push` at N = 100 000 (the cost is O(N²) per build).
* Single-element persistent `set` is two orders of magnitude faster than
  cloning the whole array first (because of structural sharing).

### HashMap vs Map

| Operation                                       | N = 10 000 | N = 100 000 |
|------------------------------------------------|-----------:|------------:|
| res-ds HashMap set (persistent)                |    2.21 ms |    47.84 ms |
| res-ds HashMap setMut (transient)              |    1.45 ms |    21.83 ms |
| Core Map       set  (mutable in-place)         |    0.70 ms |     7.47 ms |
| Core Map       clone+set (immutable, 5 000 keys [1]) |  695.45 ms |   699.64 ms |
| res-ds HashMap full get sweep                  |    0.79 ms |    14.17 ms |
| Core Map       full get sweep                  |    0.22 ms |     2.39 ms |

[1] The "Core Map clone+set" benchmark is capped at 5 000 keys because the
naive immutable pattern (`fromIterator(entries)` then `set`) is O(N²) per
build and would otherwise dominate the harness's wall-clock.

* **Transient setMut** is ~3× the cost of `Map.set` at 100 000 keys, while
  still producing an immutable result.
* For an immutable-result workload, the persistent path is **~325× faster**
  than the equivalent "clone the JS Map and write" pattern at N = 5 000 — and
  the gap widens with N because that pattern is O(N²).
* Native `Map.get` wins lookup throughput by ~6× at N = 100 000 (it is a
  hand-tuned hash table inside V8). This is the expected trade-off for the
  structural sharing the HAMT gives you on every write.

## Installation and usage

### Requirements

- **Node.js** ≥ 20 (ReScript 12 dropped Node 18 support)
- **ReScript** ≥ 12.0.0-alpha.13
- **`@rescript/core`** ≥ 1.6.0 opened globally (i.e. `compiler-flags: ["-open RescriptCore"]` in `rescript.json`)

`rescript` and `@rescript/core` are declared as `peerDependencies` — your
project should already have them.

### Install

With pnpm:

```sh
pnpm add res-ds
```

With npm:

```sh
npm install res-ds
```

With yarn:

```sh
yarn add res-ds
```

Then add `"res-ds"` to the `bs-dependencies` array of your `rescript.json` so
the ReScript compiler can see its `.res` / `.resi` files:

```json
{
  "bs-dependencies": ["@rescript/core", "res-ds"]
}
```

### Import

`res-ds` is a barrel module — pull the collections you need off the top-level
`ResDs` module:

```rescript
module V = ResDs.Vector
module M = ResDs.HashMap
module S = ResDs.HashSet
module Q = ResDs.PersistentQueue
module H = ResDs.Hash
```

Subpath imports are also exported for JS consumers:

```js
import * as Vector  from "res-ds/Vector"
import * as HashMap from "res-ds/HashMap"
import * as HashSet from "res-ds/HashSet"
import * as Queue   from "res-ds/Queue"
import * as Hash    from "res-ds/Hash"
```

### Usage

#### Persistent vector

```rescript
module V = ResDs.Vector

let v0 = V.fromArray([1, 2, 3])
let v1 = v0->V.push(4)->V.push(5)
let _  = V.getExn(v1, 4)        // 5
let v2 = V.set(v1, 0, 100)      // [100, 2, 3, 4, 5]
let _  = V.size(v2)             // 5
let _  = V.toArray(v2)          // [100, 2, 3, 4, 5]
```

Bulk-build via a transient (much faster for large N — see the benchmark above):

```rescript
let big = V.withTransient(V.make(), t => {
  for i in 0 to 99_999 {
    V.pushMut(t, i)->ignore
  }
  t
})
// `big` is an immutable Vector of 100 000 elements.
```

#### Persistent hash map

```rescript
module M = ResDs.HashMap

let m0 = M.make()->M.set("a", 1)->M.set("b", 2)
let _  = M.getExn(m0, "a")    // 1
let _  = M.has(m0, "z")       // false
let m1 = M.remove(m0, "a")    // {"b": 2}
let _  = M.entries(m1)        // [("b", 2)]
```

> **Key equality is by value for primitives, by identity (`===`) for objects.**
> Two structurally-equal but separately-constructed object keys are *different*
> entries. See [Key equality semantics](#key-equality-semantics) above.

#### Persistent hash set

```rescript
module S = ResDs.HashSet

let a = S.fromArray(["x", "y"])
let b = S.fromArray(["y", "z"])
let _ = S.union(a, b)         // {x, y, z}
let _ = S.intersect(a, b)     // {y}
let _ = S.difference(a, b)    // {x}
```

#### Persistent queue

```rescript
module Q = ResDs.PersistentQueue

let q0 = Q.fromArray([1, 2, 3])
let _  = Q.peek(q0)             // Some(1)
let q1 = Q.enqueue(q0, 4)       // [1, 2, 3, 4]
let _  = Q.dequeue(q1)          // Some((1, [2, 3, 4]))
let _  = Q.toArray(q0)          // [1, 2, 3]
```

#### JS-style iteration

Every collection exposes a `iterator` returning a `{next: () => {value, done}}`
object, mirroring the JS iterator protocol:

```rescript
let it = V.iterator(v1)
let rec loop = () =>
  switch it.next() {
  | {done: true} => ()
  | {value: Some(x)} => Console.log(x); loop()
  | _ => ()
  }
loop()
```
