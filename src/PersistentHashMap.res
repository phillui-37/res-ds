// PersistentHashMap.res
// Hash Array Mapped Trie (HAMT) with bitmap-compressed nodes, hash-collision
// nodes, structural sharing, and transient (one-thread mutable) builders.
//
// Reference: Phil Bagwell, "Ideal Hash Trees" (2001) and Rich Hickey's
// PersistentHashMap (Clojure).
//
// Trie shape:
//   * Branching factor 32; 5 bits of hash consumed per level (max depth 7).
//   * BitmapIndexed: holds up to ~16 entries packed into a dense array,
//     using a 32-bit bitmap to mark which of the 32 slots are populated
//     (bitmap compression).
//   * HashCollision: holds entries whose 32-bit hashes collide entirely.

module B = Int.Bitwise
let bits = 5

// Edit token, used by transients to identify owned (in-place mutable) nodes.
type edit = {mutable owned: bool}
let noEdit: edit = {owned: false}

// An entry inside a BitmapIndexed/HashCollision node — either a key/value
// pair (leaf) or a recursive sub-node (when this slot has been split).
type rec entry<'k, 'v> =
  | KV('k, 'v)
  | Sub(node<'k, 'v>)
and node<'k, 'v> =
  | BitmapIndexed({mutable edit: edit, mutable bitmap: int, mutable array: array<entry<'k, 'v>>})
  | HashCollision({mutable edit: edit, mutable hash: int, mutable array: array<entry<'k, 'v>>})

let emptyNode = (): node<'k, 'v> =>
  BitmapIndexed({edit: noEdit, bitmap: 0, array: []})

// ───────────────────────── public type ─────────────────────────

type t<'k, 'v> = {
  size: int,
  root: node<'k, 'v>,
  // null and undefined keys stored in distinct slots to preserve key identity.
  nullEntry: option<('k, 'v)>,
  undefinedEntry: option<('k, 'v)>,
}

let make = (): t<'k, 'v> => {
  size: 0,
  root: emptyNode(),
  nullEntry: None,
  undefinedEntry: None,
}

let size = (m: t<'k, 'v>): int => m.size

// ───────────────────────── lookup ─────────────────────────

let rec nodeFind = (n: node<'k, 'v>, shift: int, hash: int, key: 'k): option<'v> =>
  switch n {
  | BitmapIndexed({bitmap, array}) =>
    let bit = Hash.bitpos(hash, shift)
    if B.land(bitmap, bit) == 0 {
      None
    } else {
      let idx = Hash.arrayIndex(bitmap, bit)
      switch Array.getUnsafe(array, idx) {
      | KV(k, v) => Hash.equals(k, key) ? Some(v) : None
      | Sub(child) => nodeFind(child, shift + bits, hash, key)
      }
    }
  | HashCollision({hash: nodeHash, array}) =>
    if hash !== nodeHash {
      None
    } else {
      let len = Array.length(array)
      let i = ref(0)
      let result = ref(None)
      while result.contents == None && i.contents < len {
        switch Array.getUnsafe(array, i.contents) {
        | KV(k, v) =>
          if Hash.equals(k, key) {
            result := Some(v)
          }
        | Sub(_) => ()
        }
        i := i.contents + 1
      }
      result.contents
    }
  }

let isNull: 'k => bool = k => Obj.magic(k) === Obj.magic(Null.null)
let isUndefined: 'k => bool = k => Type.typeof(k) == #undefined

let get = (m: t<'k, 'v>, key: 'k): option<'v> =>
  if isNull(key) {
    m.nullEntry->Option.map(snd)
  } else if isUndefined(key) {
    m.undefinedEntry->Option.map(snd)
  } else {
    nodeFind(m.root, 0, Hash.hash(key), key)
  }

let getExn = (m: t<'k, 'v>, key: 'k): 'v =>
  switch get(m, key) {
  | Some(v) => v
  | None => throw(Not_found)
  }

let has = (m: t<'k, 'v>, key: 'k): bool =>
  if isNull(key) {
    Option.isSome(m.nullEntry)
  } else if isUndefined(key) {
    Option.isSome(m.undefinedEntry)
  } else {
    switch nodeFind(m.root, 0, Hash.hash(key), key) {
    | Some(_) => true
    | None => false
    }
  }

// ───────────────────────── persistent assoc ─────────────────────────

// Splice `e` into `array` at index `idx`, returning a fresh array.
let arrayInsert = (array: array<'a>, idx: int, e: 'a): array<'a> => {
  let len = Array.length(array)
  let out = Array.make(~length=len + 1, e)
  for i in 0 to idx - 1 {
    Array.setUnsafe(out, i, Array.getUnsafe(array, i))
  }
  for i in idx to len - 1 {
    Array.setUnsafe(out, i + 1, Array.getUnsafe(array, i))
  }
  out
}

let arrayRemoveAt = (array: array<'a>, idx: int): array<'a> => {
  let len = Array.length(array)
  let out = Array.make(~length=len - 1, Array.getUnsafe(array, 0))
  for i in 0 to idx - 1 {
    Array.setUnsafe(out, i, Array.getUnsafe(array, i))
  }
  for i in idx + 1 to len - 1 {
    Array.setUnsafe(out, i - 1, Array.getUnsafe(array, i))
  }
  out
}

let arrayReplace = (array: array<'a>, idx: int, e: 'a): array<'a> => {
  let out = Array.copy(array)
  Array.setUnsafe(out, idx, e)
  out
}

// Push `addedLeaf` to true via a 1-element flag (used to count growth).
let mkFlag = () => ref(false)

// Build a sub-node that holds two KV pairs whose hashes start to differ at `shift`.
let rec mergeKVs = (
  shift: int,
  h1: int,
  k1: 'k,
  v1: 'v,
  h2: int,
  k2: 'k,
  v2: 'v,
): node<'k, 'v> =>
  if h1 == h2 {
    HashCollision({edit: noEdit, hash: h1, array: [KV(k1, v1), KV(k2, v2)]})
  } else {
    let bit1 = Hash.bitpos(h1, shift)
    let bit2 = Hash.bitpos(h2, shift)
    if bit1 == bit2 {
      // Same 5-bit slice — recurse.
      let child = mergeKVs(shift + bits, h1, k1, v1, h2, k2, v2)
      BitmapIndexed({edit: noEdit, bitmap: bit1, array: [Sub(child)]})
    } else {
      let bitmap = B.lor(bit1, bit2)
      let arr = if Hash.arrayIndex(bitmap, bit1) == 0 {
        [KV(k1, v1), KV(k2, v2)]
      } else {
        [KV(k2, v2), KV(k1, v1)]
      }
      BitmapIndexed({edit: noEdit, bitmap: bitmap, array: arr})
    }
  }

let rec nodeAssoc = (
  n: node<'k, 'v>,
  shift: int,
  hash: int,
  key: 'k,
  value: 'v,
  addedLeaf: ref<bool>,
): node<'k, 'v> =>
  switch n {
  | BitmapIndexed({bitmap, array}) =>
    let bit = Hash.bitpos(hash, shift)
    let idx = Hash.arrayIndex(bitmap, bit)
    if B.land(bitmap, bit) == 0 {
      // Empty slot — insert new KV.
      addedLeaf := true
      let newArr = arrayInsert(array, idx, KV(key, value))
      BitmapIndexed({edit: noEdit, bitmap: B.lor(bitmap, bit), array: newArr})
    } else {
      switch Array.getUnsafe(array, idx) {
      | KV(k, v) =>
        if Hash.equals(k, key) {
          // Same key — replace value (no growth).
          if Hash.equals(v, value) {
            n
          } else {
            BitmapIndexed({
              edit: noEdit,
              bitmap: bitmap,
              array: arrayReplace(array, idx, KV(key, value)),
            })
          }
        } else {
          // Hash collision at this prefix — split into a sub-node.
          addedLeaf := true
          let sub = mergeKVs(shift + bits, Hash.hash(k), k, v, hash, key, value)
          BitmapIndexed({
            edit: noEdit,
            bitmap: bitmap,
            array: arrayReplace(array, idx, Sub(sub)),
          })
        }
      | Sub(child) =>
        let newChild = nodeAssoc(child, shift + bits, hash, key, value, addedLeaf)
        if newChild === child {
          n
        } else {
          BitmapIndexed({
            edit: noEdit,
            bitmap: bitmap,
            array: arrayReplace(array, idx, Sub(newChild)),
          })
        }
      }
    }
  | HashCollision({hash: nodeHash, array}) =>
    if hash == nodeHash {
      // Look for an existing entry with this key.
      let len = Array.length(array)
      let foundIdx = ref(-1)
      for i in 0 to len - 1 {
        if foundIdx.contents < 0 {
          switch Array.getUnsafe(array, i) {
          | KV(k, _) =>
            if Hash.equals(k, key) {
              foundIdx := i
            }
          | _ => ()
          }
        }
      }
      if foundIdx.contents >= 0 {
        HashCollision({
          edit: noEdit,
          hash: nodeHash,
          array: arrayReplace(array, foundIdx.contents, KV(key, value)),
        })
      } else {
        addedLeaf := true
        HashCollision({
          edit: noEdit,
          hash: nodeHash,
          array: arrayInsert(array, len, KV(key, value)),
        })
      }
    } else {
      // Wrap the collision node in a BitmapIndexed at this level so the new
      // key (with a different hash) can live alongside it.
      let wrapped = BitmapIndexed({
        edit: noEdit,
        bitmap: Hash.bitpos(nodeHash, shift),
        array: [Sub(n)],
      })
      nodeAssoc(wrapped, shift, hash, key, value, addedLeaf)
    }
  }

let set = (m: t<'k, 'v>, key: 'k, value: 'v): t<'k, 'v> =>
  if isNull(key) {
    let added = Option.isNone(m.nullEntry) ? 1 : 0
    {...m, size: m.size + added, nullEntry: Some((key, value))}
  } else if isUndefined(key) {
    let added = Option.isNone(m.undefinedEntry) ? 1 : 0
    {...m, size: m.size + added, undefinedEntry: Some((key, value))}
  } else {
    let added = mkFlag()
    let newRoot = nodeAssoc(m.root, 0, Hash.hash(key), key, value, added)
    if newRoot === m.root && !added.contents {
      m
    } else {
      {...m, size: added.contents ? m.size + 1 : m.size, root: newRoot}
    }
  }

// ───────────────────────── persistent dissoc ─────────────────────────

let rec nodeWithout = (
  n: node<'k, 'v>,
  shift: int,
  hash: int,
  key: 'k,
  removed: ref<bool>,
): node<'k, 'v> =>
  switch n {
  | BitmapIndexed({bitmap, array}) =>
    let bit = Hash.bitpos(hash, shift)
    if B.land(bitmap, bit) == 0 {
      n
    } else {
      let idx = Hash.arrayIndex(bitmap, bit)
      switch Array.getUnsafe(array, idx) {
      | KV(k, _) =>
        if Hash.equals(k, key) {
          removed := true
          if bitmap == bit {
            // Last entry in this node — represent as empty BitmapIndexed.
            BitmapIndexed({edit: noEdit, bitmap: 0, array: []})
          } else {
            BitmapIndexed({
              edit: noEdit,
              bitmap: B.lxor(bitmap, bit),
              array: arrayRemoveAt(array, idx),
            })
          }
        } else {
          n
        }
      | Sub(child) =>
        let newChild = nodeWithout(child, shift + bits, hash, key, removed)
        if newChild === child {
          n
        } else {
          // Detect "child collapsed to empty" → drop the slot entirely.
          let isEmpty = switch newChild {
          | BitmapIndexed({bitmap}) => bitmap == 0
          | _ => false
          }
          if isEmpty {
            if bitmap == bit {
              BitmapIndexed({edit: noEdit, bitmap: 0, array: []})
            } else {
              BitmapIndexed({
                edit: noEdit,
                bitmap: B.lxor(bitmap, bit),
                array: arrayRemoveAt(array, idx),
              })
            }
          } else {
            BitmapIndexed({
              edit: noEdit,
              bitmap: bitmap,
              array: arrayReplace(array, idx, Sub(newChild)),
            })
          }
        }
      }
    }
  | HashCollision({hash: nodeHash, array}) =>
    if hash !== nodeHash {
      n
    } else {
      let len = Array.length(array)
      let foundIdx = ref(-1)
      for i in 0 to len - 1 {
        if foundIdx.contents < 0 {
          switch Array.getUnsafe(array, i) {
          | KV(k, _) =>
            if Hash.equals(k, key) {
              foundIdx := i
            }
          | _ => ()
          }
        }
      }
      if foundIdx.contents < 0 {
        n
      } else {
        removed := true
        if len == 1 {
          BitmapIndexed({edit: noEdit, bitmap: 0, array: []})
        } else {
          HashCollision({
            edit: noEdit,
            hash: nodeHash,
            array: arrayRemoveAt(array, foundIdx.contents),
          })
        }
      }
    }
  }

let remove = (m: t<'k, 'v>, key: 'k): t<'k, 'v> =>
  if isNull(key) {
    let removed = Option.isSome(m.nullEntry) ? 1 : 0
    {...m, size: m.size - removed, nullEntry: None}
  } else if isUndefined(key) {
    let removed = Option.isSome(m.undefinedEntry) ? 1 : 0
    {...m, size: m.size - removed, undefinedEntry: None}
  } else {
    let removed = mkFlag()
    let newRoot = nodeWithout(m.root, 0, Hash.hash(key), key, removed)
    if !removed.contents {
      m
    } else {
      {...m, size: m.size - 1, root: newRoot}
    }
  }

// ───────────────────────── traversal helpers ─────────────────────────

// In-order walk of every (key, value) pair.
let rec nodeForEach = (n: node<'k, 'v>, f: ('k, 'v) => unit): unit =>
  switch n {
  | BitmapIndexed({array}) | HashCollision({array}) =>
    Array.forEach(array, e =>
      switch e {
      | KV(k, v) => f(k, v)
      | Sub(child) => nodeForEach(child, f)
      }
    )
  }

let forEach = (m: t<'k, 'v>, f: ('k, 'v) => unit): unit => {
  switch m.nullEntry {
  | Some((k, v)) => f(k, v)
  | None => ()
  }
  switch m.undefinedEntry {
  | Some((k, v)) => f(k, v)
  | None => ()
  }
  nodeForEach(m.root, f)
}

let reduce = (m: t<'k, 'v>, init: 'acc, f: ('acc, 'k, 'v) => 'acc): 'acc => {
  let acc = ref(init)
  forEach(m, (k, v) => acc := f(acc.contents, k, v))
  acc.contents
}

let keys = (m: t<'k, 'v>): array<'k> => {
  let out = []
  forEach(m, (k, _) => Array.push(out, k))
  out
}

let values = (m: t<'k, 'v>): array<'v> => {
  let out = []
  forEach(m, (_, v) => Array.push(out, v))
  out
}

let entries = (m: t<'k, 'v>): array<('k, 'v)> => {
  let out = []
  forEach(m, (k, v) => Array.push(out, (k, v)))
  out
}

let fromEntries = (entries: array<('k, 'v)>): t<'k, 'v> => {
  let m = ref(make())
  Array.forEach(entries, ((k, v)) => m := set(m.contents, k, v))
  m.contents
}

// JS-style iterator over (k, v) pairs.
type iterStep<'a> = {value: option<'a>, done: bool}
type iter<'a> = {next: unit => iterStep<'a>}

let iterator = (m: t<'k, 'v>): iter<('k, 'v)> => {
  let nullDone = ref(false)
  let undefDone = ref(false)
  let stack: array<array<entry<'k, 'v>>> = []
  let stackIdxs: array<int> = []
  // Seed trie lazily at construction time (O(1) — just push the root array).
  (switch m.root {
  | BitmapIndexed({array}) | HashCollision({array}) =>
    if Array.length(array) > 0 {
      Array.push(stack, array)
      Array.push(stackIdxs, 0)
    }
  })
  let rec advance = (): iterStep<('k, 'v)> => {
    if !nullDone.contents {
      nullDone := true
      switch m.nullEntry {
      | Some(pair) => {value: Some(pair), done: false}
      | None => advance()
      }
    } else if !undefDone.contents {
      undefDone := true
      switch m.undefinedEntry {
      | Some(pair) => {value: Some(pair), done: false}
      | None => advance()
      }
    } else {
      let depth = Array.length(stack)
      if depth == 0 {
        {value: None, done: true}
      } else {
        let arr = Array.getUnsafe(stack, depth - 1)
        let idx = Array.getUnsafe(stackIdxs, depth - 1)
        if idx >= Array.length(arr) {
          let _ = Array.pop(stack)
          let _ = Array.pop(stackIdxs)
          advance()
        } else {
          Array.setUnsafe(stackIdxs, depth - 1, idx + 1)
          switch Array.getUnsafe(arr, idx) {
          | KV(k, v) => {value: Some((k, v)), done: false}
          | Sub(child) =>
            (switch child {
            | BitmapIndexed({array}) | HashCollision({array}) =>
              Array.push(stack, array)
              Array.push(stackIdxs, 0)
            })
            advance()
          }
        }
      }
    }
  }
  {next: advance}
}

// ───────────────────────── transient (in-place mutable) ─────────────────────────

type transient<'k, 'v> = {
  mutable size: int,
  mutable root: node<'k, 'v>,
  mutable nullEntry: option<('k, 'v)>,
  mutable undefinedEntry: option<('k, 'v)>,
  edit: edit,
}

let asTransient = (m: t<'k, 'v>): transient<'k, 'v> => {
  size: m.size,
  root: m.root,
  nullEntry: m.nullEntry,
  undefinedEntry: m.undefinedEntry,
  edit: {owned: true},
}

let ensureEditable = (t: transient<'k, 'v>): unit =>
  if !t.edit.owned {
    throw(Invalid_argument("transient used after persistent! was called"))
  }

let rec nodeAssocMut = (
  ownEdit: edit,
  n: node<'k, 'v>,
  shift: int,
  hash: int,
  key: 'k,
  value: 'v,
  addedLeaf: ref<bool>,
): node<'k, 'v> =>
  switch n {
  | BitmapIndexed(self) =>
    let bit = Hash.bitpos(hash, shift)
    let idx = Hash.arrayIndex(self.bitmap, bit)
    if B.land(self.bitmap, bit) == 0 {
      addedLeaf := true
      let newArr = arrayInsert(self.array, idx, KV(key, value))
      if self.edit === ownEdit {
        self.bitmap = B.lor(self.bitmap, bit)
        self.array = newArr
        n
      } else {
        BitmapIndexed({edit: ownEdit, bitmap: B.lor(self.bitmap, bit), array: newArr})
      }
    } else {
      switch Array.getUnsafe(self.array, idx) {
      | KV(k, v) =>
        if Hash.equals(k, key) {
          if Hash.equals(v, value) {
            n
          } else {
            let newArr = if self.edit === ownEdit {
              Array.setUnsafe(self.array, idx, KV(key, value))
              self.array
            } else {
              arrayReplace(self.array, idx, KV(key, value))
            }
            if self.edit === ownEdit {
              n
            } else {
              BitmapIndexed({edit: ownEdit, bitmap: self.bitmap, array: newArr})
            }
          }
        } else {
          addedLeaf := true
          let sub = mergeKVs(shift + bits, Hash.hash(k), k, v, hash, key, value)
          let newArr = if self.edit === ownEdit {
            Array.setUnsafe(self.array, idx, Sub(sub))
            self.array
          } else {
            arrayReplace(self.array, idx, Sub(sub))
          }
          if self.edit === ownEdit {
            n
          } else {
            BitmapIndexed({edit: ownEdit, bitmap: self.bitmap, array: newArr})
          }
        }
      | Sub(child) =>
        let newChild = nodeAssocMut(ownEdit, child, shift + bits, hash, key, value, addedLeaf)
        if newChild === child {
          n
        } else {
          let newArr = if self.edit === ownEdit {
            Array.setUnsafe(self.array, idx, Sub(newChild))
            self.array
          } else {
            arrayReplace(self.array, idx, Sub(newChild))
          }
          if self.edit === ownEdit {
            n
          } else {
            BitmapIndexed({edit: ownEdit, bitmap: self.bitmap, array: newArr})
          }
        }
      }
    }
  | HashCollision(self) =>
    if hash == self.hash {
      let len = Array.length(self.array)
      let foundIdx = ref(-1)
      for i in 0 to len - 1 {
        if foundIdx.contents < 0 {
          switch Array.getUnsafe(self.array, i) {
          | KV(k, _) =>
            if Hash.equals(k, key) {
              foundIdx := i
            }
          | _ => ()
          }
        }
      }
      if foundIdx.contents >= 0 {
        let newArr = if self.edit === ownEdit {
          Array.setUnsafe(self.array, foundIdx.contents, KV(key, value))
          self.array
        } else {
          arrayReplace(self.array, foundIdx.contents, KV(key, value))
        }
        if self.edit === ownEdit {
          n
        } else {
          HashCollision({edit: ownEdit, hash: self.hash, array: newArr})
        }
      } else {
        addedLeaf := true
        let newArr = arrayInsert(self.array, len, KV(key, value))
        if self.edit === ownEdit {
          self.array = newArr
          n
        } else {
          HashCollision({edit: ownEdit, hash: self.hash, array: newArr})
        }
      }
    } else {
      let wrapped = BitmapIndexed({
        edit: ownEdit,
        bitmap: Hash.bitpos(self.hash, shift),
        array: [Sub(n)],
      })
      nodeAssocMut(ownEdit, wrapped, shift, hash, key, value, addedLeaf)
    }
  }

let setMut = (t: transient<'k, 'v>, key: 'k, value: 'v): transient<'k, 'v> => {
  ensureEditable(t)
  if isNull(key) {
    if Option.isNone(t.nullEntry) {
      t.size = t.size + 1
    }
    t.nullEntry = Some((key, value))
    t
  } else if isUndefined(key) {
    if Option.isNone(t.undefinedEntry) {
      t.size = t.size + 1
    }
    t.undefinedEntry = Some((key, value))
    t
  } else {
    let added = mkFlag()
    let newRoot = nodeAssocMut(t.edit, t.root, 0, Hash.hash(key), key, value, added)
    t.root = newRoot
    if added.contents {
      t.size = t.size + 1
    }
    t
  }
}

let removeMut = (t: transient<'k, 'v>, key: 'k): transient<'k, 'v> => {
  ensureEditable(t)
  if isNull(key) {
    if Option.isSome(t.nullEntry) {
      t.nullEntry = None
      t.size = t.size - 1
    }
    t
  } else if isUndefined(key) {
    if Option.isSome(t.undefinedEntry) {
      t.undefinedEntry = None
      t.size = t.size - 1
    }
    t
  } else {
    let removed = mkFlag()
    // We re-use the persistent path-copying remover for transients — simpler
    // and still O(log32 N). The owned-node path remains valid because we only
    // touch nodes via path-copying.
    let newRoot = nodeWithout(t.root, 0, Hash.hash(key), key, removed)
    t.root = newRoot
    if removed.contents {
      t.size = t.size - 1
    }
    t
  }
}

let getMut = (t: transient<'k, 'v>, key: 'k): option<'v> => {
  ensureEditable(t)
  if isNull(key) {
    t.nullEntry->Option.map(snd)
  } else if isUndefined(key) {
    t.undefinedEntry->Option.map(snd)
  } else {
    nodeFind(t.root, 0, Hash.hash(key), key)
  }
}

let persistent = (t: transient<'k, 'v>): t<'k, 'v> => {
  ensureEditable(t)
  t.edit.owned = false
  {size: t.size, root: t.root, nullEntry: t.nullEntry, undefinedEntry: t.undefinedEntry}
}

let withTransient = (m: t<'k, 'v>, f: transient<'k, 'v> => transient<'k, 'v>): t<'k, 'v> =>
  m->asTransient->f->persistent

// ───────────────────────── equality & merge ─────────────────────────

let equals = (a: t<'k, 'v>, b: t<'k, 'v>, eq: ('v, 'v) => bool): bool =>
  if a.size !== b.size {
    false
  } else {
    let same = ref(true)
    forEach(a, (k, v) =>
      switch get(b, k) {
      | Some(v2) =>
        if !eq(v, v2) {
          same := false
        }
      | None => same := false
      }
    )
    same.contents
  }

let merge = (a: t<'k, 'v>, b: t<'k, 'v>): t<'k, 'v> =>
  withTransient(a, t => {
    forEach(b, (k, v) => setMut(t, k, v)->ignore)
    t
  })
