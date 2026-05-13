# res-ds

Clojure-inspired persistent (immutable) data structures, implemented in
**ReScript 12**, scaffolded with **Vite** + **pnpm** and tested with
**Vitest**.

The library is dependency-light — it uses `@rescript/core` and **does not**
use the deprecated `Belt` modules.

## Collections

| Module                | What it is                                                                  |
|----------------------|------------------------------------------------------------------------------|
| `PersistentVector`   | 32-way bitmapped trie with a 32-element tail buffer (Clojure's persistent vector). O(log₃₂ N) lookup / update / push / pop. |
| `PersistentHashMap`  | Hash Array Mapped Trie (HAMT) with **bitmap-compressed** nodes, **hash-collision** nodes, and 5-bit branching. O(log₃₂ N) get / set / remove. |
| `PersistentHashSet`  | Built on top of `PersistentHashMap`; element-type `'a`, value `unit`.        |

### Advanced features

- **Bitmap compression** — each `BitmapIndexed` HAMT node stores a 32-bit
  bitmap and a *dense* array containing only the populated slots. Slot ↔ index
  conversion uses `popcount`. See `Hash.popcount`, `Hash.bitpos`,
  `Hash.arrayIndex`.
- **Transient (in-place mutable) variants** for both vector and hashmap with
  an `edit`-token ownership protocol (`asTransient` / `*Mut` / `persistent`).
  Building a 5 000-element collection via a transient is dramatically
  cheaper than chaining persistent operations.
- **Hash-collision optimisation** — when two distinct keys hash to the same
  32-bit value the HAMT degrades into a `HashCollision` leaf that supports
  full O(k) linear probe within the colliding bucket while every other path
  in the trie remains O(log₃₂ N).
- **JS-style iterators** — `iterator(coll).next() → {value, done}` for the
  vector, hashmap, and hashset.
- **Structural sharing** — every "mutating" persistent operation returns a
  new collection that shares all unchanged subtrees with the previous one.

## Getting started

```sh
pnpm install
pnpm test           # build ReScript + run the Vitest suite
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
  Hash.res                   – 32-bit hash + popcount / bitpos / arrayIndex
  PersistentVector.res       – Bitmapped trie + tail + transient
  PersistentHashMap.res      – HAMT + collision nodes + transient
  PersistentHashSet.res      – Set built on the hashmap
  ResDs.res                  – Public barrel module
tests/
  Vitest.res                 – Bindings to vitest globals
  PersistentVector_test.res
  PersistentHashMap_test.res
  PersistentHashSet_test.res
rescript.json                – ReScript 12 config (esmodule, .res.mjs)
vite.config.js               – Vite build + Vitest config
package.json                 – pnpm scripts
```
