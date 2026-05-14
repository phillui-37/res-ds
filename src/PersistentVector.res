// PersistentVector.res
// Clojure-style persistent vector backed by a 32-way bitmapped trie, with a 32-element
// "tail" buffer that absorbs the last block of pushes/pops in O(1) amortised, and a
// transient builder that allows in-place mutation while a vector is being constructed.
//
// References: Bagwell's Ideal Hash Trees + Hickey's PersistentVector.

module B = Int.Bitwise

let bits = 5
let branching = 32 // 1 lsl bits
let mask5 = 0x1f

// Edit token used by transients to identify "owned" nodes that may be mutated in place.
type edit = {mutable owned: bool}

// Trie nodes carry an edit token so transients can detect ownership.
type rec node<'a> = {
  edit: edit,
  array: array<nodeOrLeaf<'a>>,
}
and nodeOrLeaf<'a> =
  | Branch(node<'a>)
  | Leaf('a)
  | Empty

let noEdit: edit = {owned: false}

let emptyArray = (): array<nodeOrLeaf<'a>> => Array.make(~length=branching, Empty)

let emptyNode = (): node<'a> => {edit: noEdit, array: emptyArray()}

// ───────────────────────── persistent vector ─────────────────────────

type t<'a> = {
  size: int,
  shift: int,
  root: node<'a>,
  tail: array<'a>,
}

let make = (): t<'a> => {
  size: 0,
  shift: bits,
  root: emptyNode(),
  tail: [],
}

let size = (v: t<'a>): int => v.size
let length = size
let isEmpty = (v: t<'a>): bool => v.size == 0

// Number of elements that live in the trie (everything not in the tail).
let tailOffset = (v: t<'a>): int =>
  if v.size < branching {
    0
  } else {
    B.lsl(B.lsr(v.size - 1, bits), bits)
  }

// Locate the leaf array of length-≤32 that holds the element at `i`.
let arrayFor = (v: t<'a>, i: int): array<'a> => {
  if i < 0 || i >= v.size {
    throw(Not_found)
  } else if i >= tailOffset(v) {
    v.tail
  } else {
    let node = ref(v.root)
    let level = ref(v.shift)
    while level.contents > 0 {
      let idx = B.land(B.lsr(i, level.contents), mask5)
      switch Array.getUnsafe(node.contents.array, idx) {
      | Branch(n) => node := n
      | _ => throw(Not_found)
      }
      level := level.contents - bits
    }
    // At the bottom we have a node whose array's slots are Leafs.
    let result = Array.make(~length=branching, Obj.magic(0))
    Array.forEachWithIndex(node.contents.array, (slot, j) =>
      switch slot {
      | Leaf(x) => Array.setUnsafe(result, j, x)
      | _ => ()
      }
    )
    result
  }
}

let get = (v: t<'a>, i: int): option<'a> =>
  if i < 0 || i >= v.size {
    None
  } else if i >= tailOffset(v) {
    Array.get(v.tail, i - tailOffset(v))
  } else {
    let node = ref(v.root)
    let level = ref(v.shift)
    while level.contents > 0 {
      let idx = B.land(B.lsr(i, level.contents), mask5)
      switch Array.getUnsafe(node.contents.array, idx) {
      | Branch(n) => node := n
      | _ => level := -1 // signal failure
      }
      if level.contents >= 0 {
        level := level.contents - bits
      }
    }
    switch Array.getUnsafe(node.contents.array, B.land(i, mask5)) {
    | Leaf(x) => Some(x)
    | _ => None
    }
  }

let getExn = (v: t<'a>, i: int): 'a =>
  switch get(v, i) {
  | Some(x) => x
  | None => throw(Not_found)
  }

let cloneNode = (n: node<'a>): node<'a> => {edit: n.edit, array: Array.copy(n.array)}

// Build a fresh path from the root down to a leaf containing `tail`.
let rec newPath = (level: int, tail: array<'a>): node<'a> =>
  if level == 0 {
    let arr = emptyArray()
    Array.forEachWithIndex(tail, (x, i) => Array.setUnsafe(arr, i, Leaf(x)))
    {edit: noEdit, array: arr}
  } else {
    let n = emptyNode()
    Array.setUnsafe(n.array, 0, Branch(newPath(level - bits, tail)))
    n
  }

// Insert the tail into the trie at the right slot, splitting/growing as needed.
let rec pushTail = (level: int, parent: node<'a>, tail: array<'a>, size: int): node<'a> => {
  let subIdx = B.land(B.lsr(size - 1, level), mask5)
  let result = cloneNode(parent)
  let nodeToInsert = if level == bits {
    let leafNode = emptyNode()
    Array.forEachWithIndex(tail, (x, i) => Array.setUnsafe(leafNode.array, i, Leaf(x)))
    leafNode
  } else {
    switch Array.getUnsafe(parent.array, subIdx) {
    | Branch(child) => pushTail(level - bits, child, tail, size)
    | _ => newPath(level - bits, tail)
    }
  }
  Array.setUnsafe(result.array, subIdx, Branch(nodeToInsert))
  result
}

let push = (v: t<'a>, x: 'a): t<'a> => {
  // Tail still has room.
  if v.size - tailOffset(v) < branching {
    let newTail = Array.copy(v.tail)
    Array.push(newTail, x)
    {...v, size: v.size + 1, tail: newTail}
  } else {
    // Tail is full — push it into the trie, start a new tail with [x].
    // Root overflow check: trie capacity in 32-blocks is (1 << shift). When
    // (size >>> 5) exceeds that, we must grow the root upwards by one level.
    let (newRoot, newShift) = if B.lsr(v.size, bits) > B.lsl(1, v.shift) {
      let nr = emptyNode()
      Array.setUnsafe(nr.array, 0, Branch(v.root))
      Array.setUnsafe(nr.array, 1, Branch(newPath(v.shift, v.tail)))
      (nr, v.shift + bits)
    } else {
      (pushTail(v.shift, v.root, v.tail, v.size), v.shift)
    }
    {
      size: v.size + 1,
      shift: newShift,
      root: newRoot,
      tail: [x],
    }
  }
}

// Set element at index `i` (must be in-bounds). Returns a new vector sharing structure.
let rec doSet = (level: int, n: node<'a>, i: int, x: 'a): node<'a> => {
  let cloned = cloneNode(n)
  if level == 0 {
    Array.setUnsafe(cloned.array, B.land(i, mask5), Leaf(x))
  } else {
    let subIdx = B.land(B.lsr(i, level), mask5)
    switch Array.getUnsafe(n.array, subIdx) {
    | Branch(child) => Array.setUnsafe(cloned.array, subIdx, Branch(doSet(level - bits, child, i, x)))
    | _ => throw(Not_found)
    }
  }
  cloned
}

let set = (v: t<'a>, i: int, x: 'a): t<'a> =>
  if i < 0 || i > v.size {
    throw(Invalid_argument("PersistentVector.set: index out of bounds"))
  } else if i == v.size {
    push(v, x)
  } else if i >= tailOffset(v) {
    let newTail = Array.copy(v.tail)
    Array.setUnsafe(newTail, i - tailOffset(v), x)
    {...v, tail: newTail}
  } else {
    {...v, root: doSet(v.shift, v.root, i, x)}
  }

// Remove the right-most slot in the trie, returning the new root or None when empty.
let rec popTail = (level: int, n: node<'a>, size: int): option<node<'a>> => {
  let subIdx = B.land(B.lsr(size - 2, level), mask5)
  if level > bits {
    switch Array.getUnsafe(n.array, subIdx) {
    | Branch(child) =>
      switch popTail(level - bits, child, size) {
      | Some(newChild) =>
        let cloned = cloneNode(n)
        Array.setUnsafe(cloned.array, subIdx, Branch(newChild))
        Some(cloned)
      | None =>
        if subIdx == 0 {
          None
        } else {
          let cloned = cloneNode(n)
          Array.setUnsafe(cloned.array, subIdx, Empty)
          Some(cloned)
        }
      }
    | _ => None
    }
  } else if subIdx == 0 {
    None
  } else {
    let cloned = cloneNode(n)
    Array.setUnsafe(cloned.array, subIdx, Empty)
    Some(cloned)
  }
}

let pop = (v: t<'a>): t<'a> =>
  switch v.size {
  | 0 => throw(Invalid_argument("PersistentVector.pop: empty vector"))
  | 1 => make()
  | _ =>
    if v.size - tailOffset(v) > 1 {
      let newTail = Array.copy(v.tail)
      let _ = Array.pop(newTail)
      {...v, size: v.size - 1, tail: newTail}
    } else {
      // Promote the right-most leaf array out of the trie into the new tail.
      let newTail = arrayFor(v, v.size - 2)
      let newRootOpt = popTail(v.shift, v.root, v.size)
      let (newRoot, newShift) = switch newRootOpt {
      | None => (emptyNode(), bits)
      | Some(r) =>
        // Collapse the spine when the root has only the first child populated.
        if v.shift > bits {
          switch Array.getUnsafe(r.array, 1) {
          | Empty =>
            switch Array.getUnsafe(r.array, 0) {
            | Branch(child) => (child, v.shift - bits)
            | _ => (r, v.shift)
            }
          | _ => (r, v.shift)
          }
        } else {
          (r, v.shift)
        }
      }
      {size: v.size - 1, shift: newShift, root: newRoot, tail: newTail}
    }
  }

// ───────────────────────── high-level helpers ─────────────────────────

let fromArray = (arr: array<'a>): t<'a> => {
  let v = ref(make())
  Array.forEach(arr, x => v := push(v.contents, x))
  v.contents
}

let toArray = (v: t<'a>): array<'a> => {
  let out = Array.make(~length=v.size, Obj.magic(0))
  let i = ref(0)
  while i.contents < v.size {
    let leaf = arrayFor(v, i.contents)
    let baseIdx = i.contents - B.land(i.contents, mask5)
    let copyLen = Math.Int.min(branching, v.size - baseIdx)
    for j in 0 to copyLen - 1 {
      Array.setUnsafe(out, baseIdx + j, Array.getUnsafe(leaf, j))
    }
    i := baseIdx + copyLen
  }
  out
}

let forEach = (v: t<'a>, f: 'a => unit): unit => {
  let i = ref(0)
  while i.contents < v.size {
    let leaf = arrayFor(v, i.contents)
    let baseIdx = i.contents - B.land(i.contents, mask5)
    let copyLen = Math.Int.min(branching, v.size - baseIdx)
    for j in 0 to copyLen - 1 {
      f(Array.getUnsafe(leaf, j))
    }
    i := baseIdx + copyLen
  }
}

let forEachWithIndex = (v: t<'a>, f: ('a, int) => unit): unit => {
  let i = ref(0)
  while i.contents < v.size {
    let leaf = arrayFor(v, i.contents)
    let baseIdx = i.contents - B.land(i.contents, mask5)
    let copyLen = Math.Int.min(branching, v.size - baseIdx)
    for j in 0 to copyLen - 1 {
      f(Array.getUnsafe(leaf, j), baseIdx + j)
    }
    i := baseIdx + copyLen
  }
}

let reduce = (v: t<'a>, init: 'b, f: ('b, 'a) => 'b): 'b => {
  let acc = ref(init)
  forEach(v, x => acc := f(acc.contents, x))
  acc.contents
}

let map = (v: t<'a>, f: 'a => 'b): t<'b> => {
  let out = ref(make())
  forEach(v, x => out := push(out.contents, f(x)))
  out.contents
}

let filter = (v: t<'a>, f: 'a => bool): t<'a> => {
  let out = ref(make())
  forEach(v, x =>
    if f(x) {
      out := push(out.contents, x)
    }
  )
  out.contents
}

let equals = (a: t<'a>, b: t<'a>, eq: ('a, 'a) => bool): bool =>
  if a.size !== b.size {
    false
  } else {
    let same = ref(true)
    let i = ref(0)
    while same.contents && i.contents < a.size {
      let av = arrayFor(a, i.contents)
      let bv = arrayFor(b, i.contents)
      let baseIdx = i.contents - B.land(i.contents, mask5)
      let copyLen = Math.Int.min(branching, a.size - baseIdx)
      let j = ref(0)
      while same.contents && j.contents < copyLen {
        if !eq(Array.getUnsafe(av, j.contents), Array.getUnsafe(bv, j.contents)) {
          same := false
        }
        j := j.contents + 1
      }
      i := baseIdx + copyLen
    }
    same.contents
  }

// JS-style iterator — yields {value, done} pairs (value is None when done).
type iterStep<'a> = {value: option<'a>, done: bool}
type iter<'a> = {next: unit => iterStep<'a>}

let iterator = (v: t<'a>): iter<'a> => {
  let i = ref(0)
  let leafCache = ref(v.size > 0 ? arrayFor(v, 0) : [])
  let leafBase = ref(0)
  let next = () =>
    if i.contents >= v.size {
      {value: None, done: true}
    } else {
      if i.contents - leafBase.contents >= branching {
        leafCache := arrayFor(v, i.contents)
        leafBase := i.contents - B.land(i.contents, mask5)
      }
      let v = Array.getUnsafe(leafCache.contents, i.contents - leafBase.contents)
      i := i.contents + 1
      {value: Some(v), done: false}
    }
  {next: next}
}

// ───────────────────────── transient (mutable) vector ─────────────────────────

type transient<'a> = {
  mutable size: int,
  mutable shift: int,
  mutable root: node<'a>,
  mutable tail: array<'a>,
  edit: edit,
}

let asTransient = (v: t<'a>): transient<'a> => {
  let edit = {owned: true}
  // Tail is grown to a 32-slot buffer for amortised pushes.
  let bigTail = Array.make(~length=branching, Obj.magic(0))
  Array.forEachWithIndex(v.tail, (x, i) => Array.setUnsafe(bigTail, i, x))
  {
    size: v.size,
    shift: v.shift,
    root: {edit: edit, array: Array.copy(v.root.array)},
    tail: bigTail,
    edit: edit,
  }
}

let ensureEditable = (t: transient<'a>): unit =>
  if !t.edit.owned {
    throw(Invalid_argument("transient used after persistent! was called"))
  }

let editableNode = (edit: edit, n: node<'a>): node<'a> =>
  if n.edit === edit {
    n
  } else {
    {edit: edit, array: Array.copy(n.array)}
  }

// Build a path of fresh wrapping nodes from `level` down to 0, with `tailNode`
// (a leaf-node) at the bottom. Each wrapping node has the child placed at slot 0,
// because grow / fill-empty-slot is always at the right-most edge.
let rec pathFor = (edit: edit, level: int, tailNode: node<'a>): node<'a> =>
  if level == 0 {
    tailNode
  } else {
    let n = {edit: edit, array: emptyArray()}
    Array.setUnsafe(n.array, 0, Branch(pathFor(edit, level - bits, tailNode)))
    n
  }

let rec tPushTail = (edit: edit, level: int, parent: node<'a>, tailNode: node<'a>, size: int): node<'a> => {
  let subIdx = B.land(B.lsr(size - 1, level), mask5)
  let parent = editableNode(edit, parent)
  let nodeToInsert = if level == bits {
    tailNode
  } else {
    switch Array.getUnsafe(parent.array, subIdx) {
    | Branch(child) => tPushTail(edit, level - bits, child, tailNode, size)
    | _ => pathFor(edit, level - bits, tailNode)
    }
  }
  Array.setUnsafe(parent.array, subIdx, Branch(nodeToInsert))
  parent
}

let pushMut = (t: transient<'a>, x: 'a): transient<'a> => {
  ensureEditable(t)
  let snapshotForOff: t<'a> = {size: t.size, shift: t.shift, root: t.root, tail: []}
  let tailLen = t.size - tailOffset(snapshotForOff)
  if tailLen < branching {
    Array.setUnsafe(t.tail, tailLen, x)
    t.size = t.size + 1
    t
  } else {
    // Move the full 32-element tail into the trie and start a fresh tail.
    let tailNode: node<'a> = {
      edit: t.edit,
      array: {
        let a = emptyArray()
        for i in 0 to branching - 1 {
          Array.setUnsafe(a, i, Leaf(Array.getUnsafe(t.tail, i)))
        }
        a
      },
    }
    let newTail = Array.make(~length=branching, Obj.magic(0))
    Array.setUnsafe(newTail, 0, x)
    if B.lsr(t.size, bits) > B.lsl(1, t.shift) {
      // Grow the spine: new root with the old root on slot 0 and a fresh
      // path-to-tailNode on slot 1.
      let newRoot = {edit: t.edit, array: emptyArray()}
      Array.setUnsafe(newRoot.array, 0, Branch(t.root))
      Array.setUnsafe(newRoot.array, 1, Branch(pathFor(t.edit, t.shift, tailNode)))
      t.root = newRoot
      t.shift = t.shift + bits
    } else {
      t.root = tPushTail(t.edit, t.shift, t.root, tailNode, t.size)
    }
    t.tail = newTail
    t.size = t.size + 1
    t
  }
}

let setMut = (t: transient<'a>, i: int, x: 'a): transient<'a> => {
  ensureEditable(t)
  if i < 0 || i > t.size {
    throw(Invalid_argument("PersistentVector.setMut: index out of bounds"))
  } else if i == t.size {
    pushMut(t, x)
  } else {
    let snapshot: t<'a> = {size: t.size, shift: t.shift, root: t.root, tail: t.tail}
    let off = tailOffset(snapshot)
    if i >= off {
      Array.setUnsafe(t.tail, i - off, x)
      t
    } else {
      // Walk down, owning every node we touch.
      let level = ref(t.shift)
      let n = ref(editableNode(t.edit, t.root))
      t.root = n.contents
      while level.contents > 0 {
        let subIdx = B.land(B.lsr(i, level.contents), mask5)
        switch Array.getUnsafe(n.contents.array, subIdx) {
        | Branch(child) =>
          let owned = editableNode(t.edit, child)
          Array.setUnsafe(n.contents.array, subIdx, Branch(owned))
          n := owned
        | _ => throw(Not_found)
        }
        level := level.contents - bits
      }
      Array.setUnsafe(n.contents.array, B.land(i, mask5), Leaf(x))
      t
    }
  }
}

let getMut = (t: transient<'a>, i: int): option<'a> => {
  ensureEditable(t)
  let snapshot: t<'a> = {size: t.size, shift: t.shift, root: t.root, tail: t.tail}
  if i < 0 || i >= t.size {
    None
  } else if i >= tailOffset(snapshot) {
    Some(Array.getUnsafe(t.tail, i - tailOffset(snapshot)))
  } else {
    get(snapshot, i)
  }
}

let persistent = (t: transient<'a>): t<'a> => {
  ensureEditable(t)
  t.edit.owned = false
  let off = tailOffset({size: t.size, shift: t.shift, root: t.root, tail: []})
  let tailLen = t.size - off
  let trimmedTail = Array.make(~length=tailLen, Obj.magic(0))
  for i in 0 to tailLen - 1 {
    Array.setUnsafe(trimmedTail, i, Array.getUnsafe(t.tail, i))
  }
  {size: t.size, shift: t.shift, root: t.root, tail: trimmedTail}
}

// Convenience: build a vector via a mutable transient closure (very fast for bulk loads).
let first = (v: t<'a>): option<'a> => get(v, 0)

let last = (v: t<'a>): option<'a> => get(v, v.size - 1)

let firstExn = (v: t<'a>): 'a => getExn(v, 0)

let lastExn = (v: t<'a>): 'a => getExn(v, v.size - 1)

let withTransient = (v: t<'a>, f: transient<'a> => transient<'a>): t<'a> =>
  v->asTransient->f->persistent

let slice = (v: t<'a>, start: int, end_: int): t<'a> => {
  let s = Math.Int.max(0, start)
  let e = Math.Int.min(v.size, end_)
  if s >= e {
    make()
  } else {
    withTransient(make(), t => {
      let i = ref(s)
      while i.contents < e {
        let _ = pushMut(t, getExn(v, i.contents))
        i := i.contents + 1
      }
      t
    })
  }
}

let concat = (a: t<'a>, b: t<'a>): t<'a> =>
  withTransient(a, t => {
    forEach(b, x => {
      let _ = pushMut(t, x)
    })
    t
  })
