# res-ds Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all code-review bugs and add the missing utility API surface that a production-grade persistent data-structure library requires.

**Architecture:** Bugs are surgical—each fix touches only the impl + `.resi` + test. Enhancements add new functions to existing modules (Vec/HashMap/HashSet) plus one new `PersistentQueue` module; every new symbol is added to the `.resi` and re-exported from `ResDs.resi`.

**Tech Stack:** ReScript 12, `@rescript/core` (opened globally via `-open RescriptCore`), Vitest (test runner via `pnpm test`).

---

## Bug Fixes

---

### Task 1: Fix exception mismatch — `pop`/`set`/`setMut` throw `Not_found` but `.resi` says `Invalid_argument`

**Files:**
- Modify: `src/PersistentVector.res` (lines ~193, ~237, ~491)
- Test: `tests/PersistentVector_test.res`

- [ ] **Step 1: Write failing tests that catch `Invalid_argument`**

Add inside `describe("PersistentVector — basics", ...)` in `tests/PersistentVector_test.res`:

```rescript
test("pop on empty vector throws Invalid_argument", () => {
  expect(() => V.pop(V.make()))->toThrow
})

test("set with negative index throws Invalid_argument", () => {
  let v = V.fromArray([1, 2, 3])
  expect(() => V.set(v, -1, 0))->toThrow
})

test("set with index > size throws Invalid_argument", () => {
  let v = V.fromArray([1, 2, 3])
  expect(() => V.set(v, 4, 0))->toThrow
})
```

- [ ] **Step 2: Run tests, verify they currently pass for wrong reasons (catch any throw)**

```bash
pnpm test -- --reporter=verbose 2>&1 | grep -E "Invalid_argument|Not_found|pop on empty|set with"
```

These tests pass today because the functions throw *something*, but the thrown value is wrong. We need to confirm the thrown value is `Not_found` today by temporarily checking in the REPL or adding a more precise test. Add a temporary assertion to verify current wrong behavior:

In `tests/PersistentVector_test.res`, add (then remove after step 5):
```rescript
test("TEMP: pop currently throws Not_found (wrong)", () => {
  let threw = ref("")
  try {
    let _ = V.pop(V.make())
    ()
  } catch {
  | Not_found => threw := "Not_found"
  | Invalid_argument(_) => threw := "Invalid_argument"
  }
  expect(threw.contents)->toBe("Not_found")
})
```

Run: `pnpm test -- --reporter=verbose 2>&1 | grep "TEMP"`
Expected: PASS (confirms current wrong behavior)

- [ ] **Step 3: Fix `pop` in `src/PersistentVector.res`**

Change line ~237:
```rescript
// BEFORE
let pop = (v: t<'a>): t<'a> =>
  switch v.size {
  | 0 => throw(Not_found)

// AFTER
let pop = (v: t<'a>): t<'a> =>
  switch v.size {
  | 0 => throw(Invalid_argument("PersistentVector.pop: empty vector"))
```

- [ ] **Step 4: Fix `set` in `src/PersistentVector.res`**

Change line ~191:
```rescript
// BEFORE
let set = (v: t<'a>, i: int, x: 'a): t<'a> =>
  if i < 0 || i > v.size {
    throw(Not_found)

// AFTER
let set = (v: t<'a>, i: int, x: 'a): t<'a> =>
  if i < 0 || i >= v.size {
    throw(Invalid_argument("PersistentVector.set: index out of bounds"))
```

Note: `i > v.size` becomes `i >= v.size` here because `i == v.size` is the documented push-alias (Task 2 will document this). This preserves the undocumented-but-existing push shortcut while fixing the wrong exception.

- [ ] **Step 5: Fix `setMut` in `src/PersistentVector.res`**

Change line ~491:
```rescript
// BEFORE
let setMut = (t: transient<'a>, i: int, x: 'a): transient<'a> => {
  ensureEditable(t)
  if i < 0 || i > t.size {
    throw(Not_found)

// AFTER
let setMut = (t: transient<'a>, i: int, x: 'a): transient<'a> => {
  ensureEditable(t)
  if i < 0 || i >= t.size {
    throw(Invalid_argument("PersistentVector.setMut: index out of bounds"))
```

Remove the TEMP test from Step 2.

- [ ] **Step 6: Build and run tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | grep -E "PASS|FAIL|Invalid_argument|pop on empty|set with"
```

Expected: all tests pass, including the 3 new ones.

- [ ] **Step 7: Commit**

```bash
git add src/PersistentVector.res tests/PersistentVector_test.res
git commit -m "fix(vector): align pop/set/setMut to throw Invalid_argument per .resi contract

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Document `set(v, size, x)` push-alias in `.resi`

**Files:**
- Modify: `src/PersistentVector.resi` (line ~27)

- [ ] **Step 1: Update the `set` doc comment**

```rescript
// BEFORE
/** Returns a new vector with element `i` replaced by `x`.
    Throws `Invalid_argument` if `i` is out of `[0, size)`. */
let set: (t<'a>, int, 'a) => t<'a>

// AFTER
/** Returns a new vector with element `i` replaced by `x`.
    If `i == size`, equivalent to {!push} (appends `x`).
    Throws `Invalid_argument` if `i` is out of `[0, size]`. */
let set: (t<'a>, int, 'a) => t<'a>
```

Likewise update `setMut`:
```rescript
// BEFORE
/** Replace element `i` in place. Throws `Invalid_argument` if `i` is out of range. */
let setMut: (transient<'a>, int, 'a) => transient<'a>

// AFTER
/** Replace element `i` in place. If `i == size`, equivalent to {!pushMut}.
    Throws `Invalid_argument` if `i` is out of `[0, size]`. */
let setMut: (transient<'a>, int, 'a) => transient<'a>
```

- [ ] **Step 2: Build**

```bash
pnpm run res:build 2>&1 | grep -E "Error|Warning"
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/PersistentVector.resi
git commit -m "docs(vector): document set/setMut push-alias at index==size

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Fix `null`/`undefined` key coalescence in `PersistentHashMap`

**Problem:** The map stores a single "null slot" for both `null` and `undefined` keys, re-emitting `Null.null` for any key in that slot. `get(m, null)` returns a value stored under `undefined` (and vice versa). The fix stores `null` and `undefined` in distinct slots.

**Files:**
- Modify: `src/PersistentHashMap.res`
- Modify: `src/PersistentHashMap.resi` (update type comment only)
- Test: `tests/PersistentHashMap_test.res`

- [ ] **Step 1: Write failing tests**

Add in `tests/PersistentHashMap_test.res` inside a new `describe`:

```rescript
describe("PersistentHashMap — null/undefined key distinction", () => {
  test("null and undefined keys are distinct", () => {
    let m = M.make()
      ->M.set(Obj.magic(Null.null), 1)
      ->M.set(Obj.magic(Js.undefined), 2)
    expect(M.size(m))->toBe(2)
    expect(M.get(m, Obj.magic(Null.null)))->toEqual(Some(1))
    expect(M.get(m, Obj.magic(Js.undefined)))->toEqual(Some(2))
  })

  test("entries preserves the original key (null stays null, undefined stays undefined)", () => {
    let m = M.make()->M.set(Obj.magic(Null.null), 42)
    let es = M.entries(m)
    expect(Array.length(es))->toBe(1)
    let (k, v) = Array.getUnsafe(es, 0)
    expect(Obj.magic(k) === Obj.magic(Null.null))->toBe(true)
    expect(v)->toBe(42)
  })

  test("remove null does not remove undefined", () => {
    let m = M.make()
      ->M.set(Obj.magic(Null.null), 1)
      ->M.set(Obj.magic(Js.undefined), 2)
    let m2 = M.remove(m, Obj.magic(Null.null))
    expect(M.has(m2, Obj.magic(Null.null)))->toBe(false)
    expect(M.get(m2, Obj.magic(Js.undefined)))->toEqual(Some(2))
  })
})
```

Run `pnpm test` — expected: these 3 tests FAIL.

- [ ] **Step 2: Refactor the `t<'k,'v>` type to use two distinct slots**

In `src/PersistentHashMap.res`, replace the `t` type definition and `make`:

```rescript
// BEFORE
type t<'k, 'v> = {
  size: int,
  root: node<'k, 'v>,
  hasNullKey: bool,
  nullValue: option<'v>,
}

let make = (): t<'k, 'v> => {
  size: 0,
  root: emptyNode(),
  hasNullKey: false,
  nullValue: None,
}

// AFTER
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
```

- [ ] **Step 3: Update `isNullKey`, `get`, `has`, `set`, `remove`, `forEach`, `size` usages**

Replace `isNullKey` with two helpers, and update every function that used `hasNullKey`/`nullValue`:

```rescript
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
```

Update `set` — the null-key branch becomes:
```rescript
let set = (m: t<'k, 'v>, key: 'k, value: 'v): t<'k, 'v> =>
  if isNull(key) {
    let added = Option.isNone(m.nullEntry) ? 1 : 0
    {...m, size: m.size + added, nullEntry: Some((key, value))}
  } else if isUndefined(key) {
    let added = Option.isNone(m.undefinedEntry) ? 1 : 0
    {...m, size: m.size + added, undefinedEntry: Some((key, value))}
  } else {
    // ... existing trie logic unchanged ...
  }
```

Update `remove`:
```rescript
let remove = (m: t<'k, 'v>, key: 'k): t<'k, 'v> =>
  if isNull(key) {
    let removed = Option.isSome(m.nullEntry) ? 1 : 0
    {...m, size: m.size - removed, nullEntry: None}
  } else if isUndefined(key) {
    let removed = Option.isSome(m.undefinedEntry) ? 1 : 0
    {...m, size: m.size - removed, undefinedEntry: None}
  } else {
    // ... existing trie logic unchanged ...
  }
```

Update `forEach` — replace the null-key emit:
```rescript
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
```

Update the `transient` type similarly (replace `hasNullKey`/`nullValue` fields with `nullEntry`/`undefinedEntry`), and update `setMut`, `removeMut`, `getMut`, `persistent` for the transient.

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

Expected: all 52 + 3 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/PersistentHashMap.res tests/PersistentHashMap_test.res
git commit -m "fix(hashmap): store null and undefined keys in distinct slots

Previously both null and undefined mapped to the same internal slot,
causing get(m,null) to return values stored under undefined and vice
versa. Now two independent option fields preserve key identity.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Lazy iterators for `PersistentHashMap` and `PersistentHashSet`

**Problem:** `HashMap.iterator` and `HashSet.iterator` call `entries()`/`toArray()` upfront, allocating the entire collection before yielding the first element. Fix with a stack-based lazy HAMT walk matching `Vector.iterator`'s O(1) per-step semantics.

**Files:**
- Modify: `src/PersistentHashMap.res`
- Modify: `src/PersistentHashSet.res`
- Test: `tests/PersistentHashMap_test.res`

- [ ] **Step 1: Write a test that would catch eager materialisation**

Add in `tests/PersistentHashMap_test.res`:

```rescript
describe("PersistentHashMap — lazy iterator", () => {
  test("iterator yields exactly size elements", () => {
    let n = 1000
    let m = ref(M.make())
    for i in 0 to n - 1 {
      m := M.set(m.contents, i, i * 2)
    }
    let it = M.iterator(m.contents)
    let count = ref(0)
    let step = ref(it.next())
    while !step.contents.done {
      count := count.contents + 1
      step := it.next()
    }
    expect(count.contents)->toBe(n)
  })

  test("iterator terminates correctly with null/undefined keys", () => {
    let m = M.make()
      ->M.set(Obj.magic(Null.null), 0)
      ->M.set(Obj.magic(Js.undefined), 1)
      ->M.set("a", 2)
    let it = M.iterator(m)
    let count = ref(0)
    let step = ref(it.next())
    while !step.contents.done {
      count := count.contents + 1
      step := it.next()
    }
    expect(count.contents)->toBe(3)
  })
})
```

Run `pnpm test` — expected: these pass (they test count, not laziness), establishing a baseline. We'll verify laziness via inspection.

- [ ] **Step 2: Implement lazy HAMT iterator in `src/PersistentHashMap.res`**

Replace the `iterator` function:

```rescript
let iterator = (m: t<'k, 'v>): iter<('k, 'v)> => {
  // Phase 0: yield nullEntry, then undefinedEntry, then walk trie.
  let phase = ref(0) // 0=null slot, 1=undefined slot, 2=trie walk
  // Stack of node arrays (each entry is a dense `array<entry<'k,'v>>`).
  let stack: array<array<entry<'k, 'v>>> = []
  let stackIdxs: array<int> = [] // current position within each stacked array
  // Seed the stack with the root's array (if non-empty).
  let seedTrie = () => {
    switch m.root {
    | BitmapIndexed({array}) | HashCollision({array}) =>
      if Array.length(array) > 0 {
        Array.push(stack, array)
        Array.push(stackIdxs, 0)
      }
    }
  }
  let next = () => {
    let result = ref(None)
    while result.contents == None {
      switch phase.contents {
      | 0 =>
        phase := 1
        switch m.nullEntry {
        | Some(pair) => result := Some(pair)
        | None => ()
        }
      | 1 =>
        phase := 2
        seedTrie()
        switch m.undefinedEntry {
        | Some(pair) => result := Some(pair)
        | None => ()
        }
      | _ =>
        // trie walk
        let depth = Array.length(stack)
        if depth == 0 {
          // exhausted
          result := Some(Obj.magic(None)) // sentinel: use done=true path below
        } else {
          let arr = Array.getUnsafe(stack, depth - 1)
          let idx = Array.getUnsafe(stackIdxs, depth - 1)
          if idx >= Array.length(arr) {
            // pop this level
            let _ = Array.pop(stack)
            let _ = Array.pop(stackIdxs)
          } else {
            Array.setUnsafe(stackIdxs, depth - 1, idx + 1)
            switch Array.getUnsafe(arr, idx) {
            | KV(k, v) => result := Some((k, v))
            | Sub(child) =>
              switch child {
              | BitmapIndexed({array}) | HashCollision({array}) =>
                Array.push(stack, array)
                Array.push(stackIdxs, 0)
              }
            }
          }
        }
      }
    }
    switch result.contents {
    | Some(pair) =>
      // Check if this was the "exhausted" sentinel
      if Array.length(stack) == 0 && phase.contents == 2 && result.contents == Some(Obj.magic(None)) {
        {value: None, done: true}
      } else {
        {value: Some(pair), done: false}
      }
    | None => {value: None, done: true}
    }
  }
  {next}
}
```

**Note:** The sentinel approach above is awkward. Use a cleaner boolean-based approach instead:

```rescript
let iterator = (m: t<'k, 'v>): iter<('k, 'v)> => {
  let nullDone = ref(false)
  let undefDone = ref(false)
  let stack: array<array<entry<'k, 'v>>> = []
  let stackIdxs: array<int> = []
  // Seed trie
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
```

- [ ] **Step 3: Update `HashSet.iterator` to delegate to HashMap's lazy iterator**

In `src/PersistentHashSet.res`, replace the `iterator` function:

```rescript
let iterator = (s: t<'a>): iter<'a> => {
  let inner = M.iterator(s)
  let next = () => {
    let step = inner.next()
    if step.done {
      {value: None, done: true}
    } else {
      switch step.value {
      | Some((k, _)) => {value: Some(k), done: false}
      | None => {value: None, done: true}
      }
    }
  }
  {next}
}
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/PersistentHashMap.res src/PersistentHashSet.res tests/PersistentHashMap_test.res
git commit -m "fix(hashmap/hashset): replace eager iterator with lazy stack-based HAMT walk

Previously iterator() called entries() upfront allocating an O(N) array
before yielding the first element. Now uses a stack-based walk identical
in laziness to Vector.iterator (O(1) per step, O(log32 N) space).

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Short-circuit inner loop in `PersistentVector.equals`

**Files:**
- Modify: `src/PersistentVector.res` (lines ~340-360)

- [ ] **Step 1: Write a test that confirms short-circuit behaviour (no observable change — micro-correctness)**

Add in `tests/PersistentVector_test.res`:

```rescript
test("equals short-circuits: comparator not called after first mismatch", () => {
  let calls = ref(0)
  let eq = (a, b) => {
    calls := calls.contents + 1
    a == b
  }
  let a = V.fromArray(Array.fromInitializer(~length=64, i => i))
  let b = V.set(a, 0, -1) // differ at index 0
  let _ = V.equals(a, b, eq)
  // Without short-circuit the inner for-loop would call eq 32 times for the
  // first leaf block then stop at the outer while. With short-circuit it calls
  // eq exactly once.
  expect(calls.contents)->toBe(1)
})
```

Run `pnpm test` — expected: FAIL (calls will be 32, not 1).

- [ ] **Step 2: Replace the inner `for` with a guarded `while`**

In `src/PersistentVector.res` find the `equals` function and change:

```rescript
// BEFORE
      for j in 0 to copyLen - 1 {
        if !eq(Array.getUnsafe(av, j), Array.getUnsafe(bv, j)) {
          same := false
        }
      }

// AFTER
      let j = ref(0)
      while same.contents && j.contents < copyLen {
        if !eq(Array.getUnsafe(av, j.contents), Array.getUnsafe(bv, j.contents)) {
          same := false
        }
        j := j.contents + 1
      }
```

- [ ] **Step 3: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

Expected: all tests pass including the new short-circuit test.

- [ ] **Step 4: Commit**

```bash
git add src/PersistentVector.res tests/PersistentVector_test.res
git commit -m "perf(vector): short-circuit inner comparison loop in equals

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Enhancements

---

### Task 6: `isEmpty` on `Vector`, `HashMap`, and `HashSet`

**Files:**
- Modify: `src/PersistentVector.res`, `src/PersistentVector.resi`
- Modify: `src/PersistentHashMap.res`, `src/PersistentHashMap.resi`
- Modify: `src/PersistentHashSet.res`, `src/PersistentHashSet.resi`
- Test: `tests/PersistentVector_test.res`, `tests/PersistentHashMap_test.res`, `tests/PersistentHashSet_test.res`

- [ ] **Step 1: Write failing tests**

In `tests/PersistentVector_test.res`:
```rescript
test("isEmpty returns true for empty vector", () => {
  expect(V.isEmpty(V.make()))->toBe(true)
  expect(V.isEmpty(V.fromArray([1])))->toBe(false)
})
```

In `tests/PersistentHashMap_test.res`:
```rescript
test("isEmpty returns true for empty map", () => {
  expect(M.isEmpty(M.make()))->toBe(true)
  expect(M.isEmpty(M.set(M.make(), "a", 1)))->toBe(false)
})
```

In `tests/PersistentHashSet_test.res`:
```rescript
test("isEmpty returns true for empty set", () => {
  expect(S.isEmpty(S.make()))->toBe(true)
  expect(S.isEmpty(S.add(S.make(), 1)))->toBe(false)
})
```

Run `pnpm test` — expected: 3 FAIL.

- [ ] **Step 2: Add implementations**

In `src/PersistentVector.res` (after `length`):
```rescript
let isEmpty = (v: t<'a>): bool => v.size == 0
```

In `src/PersistentHashMap.res` (after `size`):
```rescript
let isEmpty = (m: t<'k, 'v>): bool => m.size == 0
```

In `src/PersistentHashSet.res` (after `size`):
```rescript
let isEmpty = (s: t<'a>): bool => M.isEmpty(s)
```

- [ ] **Step 3: Add to `.resi` files**

In `src/PersistentVector.resi` (after `length`):
```rescript
/** True iff the vector contains no elements. */
let isEmpty: t<'a> => bool
```

In `src/PersistentHashMap.resi` (after `size`):
```rescript
/** True iff the map contains no entries. */
let isEmpty: t<'k, 'v> => bool
```

In `src/PersistentHashSet.resi` (after `size`):
```rescript
/** True iff the set contains no elements. */
let isEmpty: t<'a> => bool
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/PersistentVector.res src/PersistentVector.resi \
        src/PersistentHashMap.res src/PersistentHashMap.resi \
        src/PersistentHashSet.res src/PersistentHashSet.resi \
        tests/PersistentVector_test.res tests/PersistentHashMap_test.res \
        tests/PersistentHashSet_test.res
git commit -m "feat: add isEmpty to Vector, HashMap, HashSet

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: `first` and `last` on `PersistentVector`

O(1) access to head and tail elements (avoid manually calling `getExn(v, 0)` / `getExn(v, size-1)`).

**Files:**
- Modify: `src/PersistentVector.res`, `src/PersistentVector.resi`
- Test: `tests/PersistentVector_test.res`

- [ ] **Step 1: Write failing tests**

```rescript
test("first/last return None on empty vector", () => {
  let v = V.make()
  expect(V.first(v))->toEqual(None)
  expect(V.last(v))->toEqual(None)
})

test("first/last return correct elements", () => {
  let v = V.fromArray([10, 20, 30])
  expect(V.first(v))->toEqual(Some(10))
  expect(V.last(v))->toEqual(Some(30))
})

test("firstExn/lastExn throw on empty", () => {
  expect(() => V.firstExn(V.make()))->toThrow
  expect(() => V.lastExn(V.make()))->toThrow
})
```

- [ ] **Step 2: Add implementations in `src/PersistentVector.res`**

```rescript
let first = (v: t<'a>): option<'a> => get(v, 0)
let last = (v: t<'a>): option<'a> => get(v, v.size - 1)
let firstExn = (v: t<'a>): 'a => getExn(v, 0)
let lastExn = (v: t<'a>): 'a => getExn(v, v.size - 1)
```

- [ ] **Step 3: Add to `src/PersistentVector.resi`**

```rescript
/** O(1). First element, or `None` if empty. */
let first: t<'a> => option<'a>

/** O(1). Last element, or `None` if empty. */
let last: t<'a> => option<'a>

/** O(1). First element. Throws `Not_found` if empty. */
let firstExn: t<'a> => 'a

/** O(1). Last element. Throws `Not_found` if empty. */
let lastExn: t<'a> => 'a
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add src/PersistentVector.res src/PersistentVector.resi tests/PersistentVector_test.res
git commit -m "feat(vector): add first/last/firstExn/lastExn

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: `slice` and `concat` on `PersistentVector`

`slice(v, start, end_)` — returns a new vector containing elements `[start, end_)`, clamped to valid range. `concat(a, b)` — appends all elements of `b` to `a` via a transient builder for efficiency.

**Files:**
- Modify: `src/PersistentVector.res`, `src/PersistentVector.resi`
- Test: `tests/PersistentVector_test.res`

- [ ] **Step 1: Write failing tests**

```rescript
describe("PersistentVector — slice/concat", () => {
  test("slice returns sub-range", () => {
    let v = V.fromArray([0, 1, 2, 3, 4])
    expect(V.toArray(V.slice(v, 1, 4)))->toEqual([1, 2, 3])
  })

  test("slice with clamped bounds returns empty", () => {
    let v = V.fromArray([0, 1, 2])
    expect(V.size(V.slice(v, 5, 10)))->toBe(0)
    expect(V.size(V.slice(v, 2, 1)))->toBe(0)
  })

  test("slice full range equals original", () => {
    let arr = Array.fromInitializer(~length=100, i => i)
    let v = V.fromArray(arr)
    expect(V.toArray(V.slice(v, 0, 100)))->toEqual(arr)
  })

  test("concat two vectors", () => {
    let a = V.fromArray([1, 2, 3])
    let b = V.fromArray([4, 5, 6])
    expect(V.toArray(V.concat(a, b)))->toEqual([1, 2, 3, 4, 5, 6])
  })

  test("concat with empty is identity", () => {
    let v = V.fromArray([1, 2, 3])
    expect(V.toArray(V.concat(v, V.make())))->toEqual([1, 2, 3])
    expect(V.toArray(V.concat(V.make(), v)))->toEqual([1, 2, 3])
  })

  test("concat large vectors (crosses trie boundaries)", () => {
    let a = V.fromArray(Array.fromInitializer(~length=500, i => i))
    let b = V.fromArray(Array.fromInitializer(~length=500, i => 500 + i))
    let c = V.concat(a, b)
    expect(V.size(c))->toBe(1000)
    expect(V.getExn(c, 999))->toBe(999)
  })
})
```

- [ ] **Step 2: Implement in `src/PersistentVector.res`**

```rescript
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
```

- [ ] **Step 3: Add to `src/PersistentVector.resi`**

```rescript
/** Returns a new vector containing elements in `[start, end_)`.
    Indices are clamped to `[0, size]`; an empty vector is returned when
    `start >= end_`. */
let slice: (t<'a>, int, int) => t<'a>

/** Returns a new vector with all elements of `b` appended to `a`.
    Uses a transient builder — O(|b| log32 N) amortised. */
let concat: (t<'a>, t<'a>) => t<'a>
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add src/PersistentVector.res src/PersistentVector.resi tests/PersistentVector_test.res
git commit -m "feat(vector): add slice and concat

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: `find`, `findIndex`, `some`, `every` on `PersistentVector`

**Files:**
- Modify: `src/PersistentVector.res`, `src/PersistentVector.resi`
- Test: `tests/PersistentVector_test.res`

- [ ] **Step 1: Write failing tests**

```rescript
describe("PersistentVector — search/predicate", () => {
  test("find returns first matching element", () => {
    let v = V.fromArray([1, 2, 3, 4, 5])
    expect(V.find(v, x => x > 3))->toEqual(Some(4))
    expect(V.find(v, x => x > 10))->toEqual(None)
  })

  test("findIndex returns index of first match", () => {
    let v = V.fromArray([10, 20, 30, 20])
    expect(V.findIndex(v, x => x == 20))->toEqual(Some(1))
    expect(V.findIndex(v, x => x == 99))->toEqual(None)
  })

  test("some returns true iff any element satisfies predicate", () => {
    let v = V.fromArray([1, 2, 3])
    expect(V.some(v, x => x > 2))->toBe(true)
    expect(V.some(v, x => x > 10))->toBe(false)
    expect(V.some(V.make(), _ => true))->toBe(false)
  })

  test("every returns true iff all elements satisfy predicate", () => {
    let v = V.fromArray([2, 4, 6])
    expect(V.every(v, x => Int.mod(x, 2) == 0))->toBe(true)
    expect(V.every(v, x => x > 3))->toBe(false)
    expect(V.every(V.make(), _ => false))->toBe(true)
  })
})
```

- [ ] **Step 2: Implement in `src/PersistentVector.res`**

```rescript
let find = (v: t<'a>, f: 'a => bool): option<'a> => {
  let result = ref(None)
  let i = ref(0)
  while result.contents == None && i.contents < v.size {
    let x = getExn(v, i.contents)
    if f(x) {
      result := Some(x)
    }
    i := i.contents + 1
  }
  result.contents
}

let findIndex = (v: t<'a>, f: 'a => bool): option<int> => {
  let result = ref(None)
  let i = ref(0)
  while result.contents == None && i.contents < v.size {
    if f(getExn(v, i.contents)) {
      result := Some(i.contents)
    }
    i := i.contents + 1
  }
  result.contents
}

let some = (v: t<'a>, f: 'a => bool): bool =>
  findIndex(v, f) != None

let every = (v: t<'a>, f: 'a => bool): bool => {
  let failed = ref(false)
  let i = ref(0)
  while !failed.contents && i.contents < v.size {
    if !f(getExn(v, i.contents)) {
      failed := true
    }
    i := i.contents + 1
  }
  !failed.contents
}
```

- [ ] **Step 3: Add to `src/PersistentVector.resi`**

```rescript
/** Returns the first element satisfying `f`, or `None`. */
let find: (t<'a>, 'a => bool) => option<'a>

/** Returns the index of the first element satisfying `f`, or `None`. */
let findIndex: (t<'a>, 'a => bool) => option<int>

/** True iff any element satisfies `f`. Always `false` on empty vector. */
let some: (t<'a>, 'a => bool) => bool

/** True iff all elements satisfy `f`. Always `true` on empty vector. */
let every: (t<'a>, 'a => bool) => bool
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add src/PersistentVector.res src/PersistentVector.resi tests/PersistentVector_test.res
git commit -m "feat(vector): add find, findIndex, some, every

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 10: `map`, `filter`, `update` on `PersistentHashMap`

**Files:**
- Modify: `src/PersistentHashMap.res`, `src/PersistentHashMap.resi`
- Test: `tests/PersistentHashMap_test.res`

- [ ] **Step 1: Write failing tests**

```rescript
describe("PersistentHashMap — map/filter/update", () => {
  test("map transforms all values", () => {
    let m = M.fromEntries([("a", 1), ("b", 2), ("c", 3)])
    let m2 = M.map(m, v => v * 10)
    expect(M.getExn(m2, "a"))->toBe(10)
    expect(M.getExn(m2, "b"))->toBe(20)
    expect(M.size(m2))->toBe(3)
    // original unchanged
    expect(M.getExn(m, "a"))->toBe(1)
  })

  test("filter keeps only matching entries", () => {
    let m = M.fromEntries([("a", 1), ("b", 2), ("c", 3)])
    let m2 = M.filter(m, (_, v) => v > 1)
    expect(M.size(m2))->toBe(2)
    expect(M.has(m2, "a"))->toBe(false)
    expect(M.has(m2, "b"))->toBe(true)
  })

  test("update inserts when key absent", () => {
    let m = M.make()
    let m2 = M.update(m, "x", _ => Some(42))
    expect(M.getExn(m2, "x"))->toBe(42)
  })

  test("update modifies existing key", () => {
    let m = M.fromEntries([("x", 10)])
    let m2 = M.update(m, "x", v => Some(Option.getOr(v, 0) + 5))
    expect(M.getExn(m2, "x"))->toBe(15)
  })

  test("update removes key when f returns None", () => {
    let m = M.fromEntries([("x", 10)])
    let m2 = M.update(m, "x", _ => None)
    expect(M.has(m2, "x"))->toBe(false)
    expect(M.size(m2))->toBe(0)
  })
})
```

- [ ] **Step 2: Implement in `src/PersistentHashMap.res`**

```rescript
let map = (m: t<'k, 'v>, f: 'v => 'w): t<'k, 'w> => {
  let out = ref({
    size: m.size,
    root: emptyNode(),
    nullEntry: m.nullEntry->Option.map(((k, v)) => (k, f(v))),
    undefinedEntry: m.undefinedEntry->Option.map(((k, v)) => (k, f(v))),
  })
  // Re-insert all trie entries with transformed values.
  // Use withTransient for efficiency.
  let t = asTransient(make())
  nodeForEach(m.root, (k, v) => {
    let _ = setMut(t, k, f(v))
  })
  let trieOnly = persistent(t)
  {
    size: m.size,
    root: trieOnly.root,
    nullEntry: m.nullEntry->Option.map(((k, v)) => (k, f(v))),
    undefinedEntry: m.undefinedEntry->Option.map(((k, v)) => (k, f(v))),
  }
}

let filter = (m: t<'k, 'v>, f: ('k, 'v) => bool): t<'k, 'v> => {
  let out = ref(make())
  forEach(m, (k, v) =>
    if f(k, v) {
      out := set(out.contents, k, v)
    }
  )
  out.contents
}

let update = (m: t<'k, 'v>, key: 'k, f: option<'v> => option<'v>): t<'k, 'v> => {
  let current = get(m, key)
  switch f(current) {
  | Some(v) => set(m, key, v)
  | None =>
    switch current {
    | Some(_) => remove(m, key)
    | None => m
    }
  }
}
```

- [ ] **Step 3: Add to `src/PersistentHashMap.resi`**

```rescript
/** Returns a new map with all values transformed by `f`. Keys are preserved. */
let map: (t<'k, 'v>, 'v => 'w) => t<'k, 'w>

/** Returns a new map containing only entries for which `f(key, value)` is true. */
let filter: (t<'k, 'v>, ('k, 'v) => bool) => t<'k, 'v>

/** Atomically read-modify-write a key.
    `f` receives `Some(v)` if the key exists, `None` if absent.
    Return `Some(newV)` to insert/replace, `None` to delete. */
let update: (t<'k, 'v>, 'k, option<'v> => option<'v>) => t<'k, 'v>
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add src/PersistentHashMap.res src/PersistentHashMap.resi tests/PersistentHashMap_test.res
git commit -m "feat(hashmap): add map, filter, update

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 11: `equals`, `isSubsetOf`, `isSupersetOf`, `filter`, `map` on `PersistentHashSet`

**Files:**
- Modify: `src/PersistentHashSet.res`, `src/PersistentHashSet.resi`
- Test: `tests/PersistentHashSet_test.res`

- [ ] **Step 1: Write failing tests**

```rescript
describe("PersistentHashSet — equals/subset/superset/filter/map", () => {
  test("equals returns true for identical content", () => {
    let a = S.fromArray([1, 2, 3])
    let b = S.fromArray([3, 1, 2])
    expect(S.equals(a, b))->toBe(true)
  })

  test("equals returns false when content differs", () => {
    let a = S.fromArray([1, 2, 3])
    let b = S.fromArray([1, 2, 4])
    expect(S.equals(a, b))->toBe(false)
  })

  test("isSubsetOf", () => {
    let a = S.fromArray([1, 2])
    let b = S.fromArray([1, 2, 3])
    expect(S.isSubsetOf(a, b))->toBe(true)
    expect(S.isSubsetOf(b, a))->toBe(false)
    expect(S.isSubsetOf(a, a))->toBe(true)
  })

  test("isSupersetOf", () => {
    let a = S.fromArray([1, 2, 3])
    let b = S.fromArray([1, 2])
    expect(S.isSupersetOf(a, b))->toBe(true)
    expect(S.isSupersetOf(b, a))->toBe(false)
  })

  test("filter keeps only matching elements", () => {
    let s = S.fromArray([1, 2, 3, 4, 5])
    let even = S.filter(s, x => Int.mod(x, 2) == 0)
    expect(S.size(even))->toBe(2)
    expect(S.has(even, 2))->toBe(true)
    expect(S.has(even, 1))->toBe(false)
  })

  test("map transforms elements", () => {
    let s = S.fromArray([1, 2, 3])
    let doubled = S.map(s, x => x * 2)
    expect(S.has(doubled, 2))->toBe(true)
    expect(S.has(doubled, 4))->toBe(true)
    expect(S.has(doubled, 6))->toBe(true)
    expect(S.size(doubled))->toBe(3)
  })
})
```

- [ ] **Step 2: Implement in `src/PersistentHashSet.res`**

```rescript
let equals = (a: t<'a>, b: t<'a>): bool =>
  M.size(a) == M.size(b) && {
    let allIn = ref(true)
    forEach(a, x =>
      if !has(b, x) {
        allIn := false
      }
    )
    allIn.contents
  }

let isSubsetOf = (a: t<'a>, b: t<'a>): bool => {
  let allIn = ref(true)
  forEach(a, x =>
    if !has(b, x) {
      allIn := false
    }
  )
  allIn.contents
}

let isSupersetOf = (a: t<'a>, b: t<'a>): bool => isSubsetOf(b, a)

let filter = (s: t<'a>, f: 'a => bool): t<'a> =>
  M.withTransient(make(), t => {
    forEach(s, x =>
      if f(x) {
        M.setMut(t, x, ())->ignore
      }
    )
    t
  })

let map = (s: t<'a>, f: 'a => 'b): t<'b> =>
  M.withTransient(make(), t => {
    forEach(s, x => M.setMut(t, f(x), ())->ignore)
    t
  })
```

- [ ] **Step 3: Add to `src/PersistentHashSet.resi`**

```rescript
/** True iff `a` and `b` contain exactly the same elements. */
let equals: (t<'a>, t<'a>) => bool

/** True iff every element of `a` is also in `b`. */
let isSubsetOf: (t<'a>, t<'a>) => bool

/** True iff every element of `b` is also in `a`. */
let isSupersetOf: (t<'a>, t<'a>) => bool

/** Returns a new set containing only elements satisfying `f`. */
let filter: (t<'a>, 'a => bool) => t<'a>

/** Returns a new set formed by applying `f` to every element.
    If `f` maps two distinct elements to the same value, duplicates are dropped. */
let map: (t<'a>, 'a => 'b) => t<'b>
```

- [ ] **Step 4: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add src/PersistentHashSet.res src/PersistentHashSet.resi tests/PersistentHashSet_test.res
git commit -m "feat(hashset): add equals, isSubsetOf, isSupersetOf, filter, map

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 12: `PersistentQueue` — persistent FIFO queue

A persistent FIFO queue using the classic two-list (front/rear) representation with lazy rebalancing. `enqueue` is O(1) amortised; `dequeue`/`peek` is O(1) amortised (O(N) in worst case for the reverse, amortised away).

**Files:**
- Create: `src/PersistentQueue.res`
- Create: `src/PersistentQueue.resi`
- Modify: `src/ResDs.res`, `src/ResDs.resi`
- Create: `tests/PersistentQueue_test.res`

- [ ] **Step 1: Write failing tests in `tests/PersistentQueue_test.res`**

```rescript
open Vitest
module Q = PersistentQueue

describe("PersistentQueue — basics", () => {
  test("empty queue has size 0 and isEmpty true", () => {
    let q = Q.make()
    expect(Q.size(q))->toBe(0)
    expect(Q.isEmpty(q))->toBe(true)
  })

  test("enqueue/peek/dequeue round-trip", () => {
    let q = Q.make()->Q.enqueue(1)->Q.enqueue(2)->Q.enqueue(3)
    expect(Q.size(q))->toBe(3)
    expect(Q.peek(q))->toEqual(Some(1))
    let (v, q2) = Q.dequeue(q)->Option.getExn
    expect(v)->toBe(1)
    expect(Q.size(q2))->toBe(2)
    expect(Q.peek(q2))->toEqual(Some(2))
  })

  test("FIFO order preserved across rebalance (N > 1000)", () => {
    let n = 1000
    let q = ref(Q.make())
    for i in 0 to n - 1 {
      q := Q.enqueue(q.contents, i)
    }
    let ok = ref(true)
    for i in 0 to n - 1 {
      switch Q.dequeue(q.contents) {
      | Some((v, q2)) =>
        if v != i { ok := false }
        q := q2
      | None => ok := false
      }
    }
    expect(ok.contents)->toBe(true)
  })

  test("peek on empty returns None", () => {
    expect(Q.peek(Q.make()))->toEqual(None)
  })

  test("dequeue on empty returns None", () => {
    expect(Q.dequeue(Q.make()))->toEqual(None)
  })

  test("peekExn/dequeueExn throw on empty", () => {
    expect(() => Q.peekExn(Q.make()))->toThrow
    expect(() => Q.dequeueExn(Q.make()))->toThrow
  })

  test("toArray preserves FIFO order", () => {
    let q = Q.make()->Q.enqueue(10)->Q.enqueue(20)->Q.enqueue(30)
    expect(Q.toArray(q))->toEqual([10, 20, 30])
  })

  test("fromArray preserves order", () => {
    let arr = [1, 2, 3, 4, 5]
    let q = Q.fromArray(arr)
    expect(Q.toArray(q))->toEqual(arr)
  })

  test("structural sharing: dequeue does not mutate original", () => {
    let q = Q.make()->Q.enqueue(1)->Q.enqueue(2)
    let _ = Q.dequeue(q)
    expect(Q.size(q))->toBe(2)
    expect(Q.peek(q))->toEqual(Some(1))
  })
})
```

Run `pnpm test` — expected: compile error (module not found).

- [ ] **Step 2: Create `src/PersistentQueue.res`**

```rescript
// PersistentQueue.res
// Persistent FIFO queue using the classic Hood-Melville / two-list representation.
// `front` holds elements in dequeue order (head first); `rear` holds newly enqueued
// elements in reverse order (most-recent first).
// When `front` is exhausted, `rear` is reversed into `front`.
//
// Amortised complexity:
//   enqueue  — O(1)
//   dequeue  — O(1) amortised (O(N) worst case, O(1) amortised over all ops)
//   peek     — O(1)

type t<'a> = {
  size: int,
  front: list<'a>,
  rear: list<'a>,
}

let make = (): t<'a> => {size: 0, front: list{}, rear: list{}}

let size = (q: t<'a>): int => q.size

let isEmpty = (q: t<'a>): bool => q.size == 0

// Rebalance: reverse `rear` into `front` when `front` is empty.
let balance = (q: t<'a>): t<'a> =>
  switch q.front {
  | list{} => {...q, front: List.reverse(q.rear), rear: list{}}
  | _ => q
  }

let enqueue = (q: t<'a>, x: 'a): t<'a> =>
  balance({size: q.size + 1, front: q.front, rear: list{x, ...q.rear}})

let peek = (q: t<'a>): option<'a> =>
  switch q.front {
  | list{x, ..._} => Some(x)
  | list{} => None
  }

let peekExn = (q: t<'a>): 'a =>
  switch q.front {
  | list{x, ..._} => x
  | list{} => throw(Not_found)
  }

let dequeue = (q: t<'a>): option<('a, t<'a>)> =>
  switch q.front {
  | list{x, ...rest} =>
    Some((x, balance({size: q.size - 1, front: rest, rear: q.rear})))
  | list{} => None
  }

let dequeueExn = (q: t<'a>): ('a, t<'a>) =>
  switch dequeue(q) {
  | Some(pair) => pair
  | None => throw(Not_found)
  }

let toArray = (q: t<'a>): array<'a> => {
  let out = Array.make(~length=q.size, Obj.magic(0))
  let i = ref(0)
  let cur = ref(q)
  while !isEmpty(cur.contents) {
    switch dequeue(cur.contents) {
    | Some((x, q2)) =>
      Array.setUnsafe(out, i.contents, x)
      i := i.contents + 1
      cur := q2
    | None => ()
    }
  }
  out
}

let fromArray = (arr: array<'a>): t<'a> => {
  let q = ref(make())
  Array.forEach(arr, x => q := enqueue(q.contents, x))
  q.contents
}

let forEach = (q: t<'a>, f: 'a => unit): unit =>
  Array.forEach(toArray(q), f)

let reduce = (q: t<'a>, init: 'b, f: ('b, 'a) => 'b): 'b => {
  let acc = ref(init)
  forEach(q, x => acc := f(acc.contents, x))
  acc.contents
}

let map = (q: t<'a>, f: 'a => 'b): t<'b> => {
  let out = ref(make())
  forEach(q, x => out := enqueue(out.contents, f(x)))
  out.contents
}

let filter = (q: t<'a>, f: 'a => bool): t<'a> => {
  let out = ref(make())
  forEach(q, x =>
    if f(x) {
      out := enqueue(out.contents, x)
    }
  )
  out.contents
}

// JS-style iterator (front-to-back).
type iterStep<'a> = {value: option<'a>, done: bool}
type iter<'a> = {next: unit => iterStep<'a>}

let iterator = (q: t<'a>): iter<'a> => {
  let cur = ref(q)
  let next = () =>
    switch dequeue(cur.contents) {
    | Some((x, q2)) =>
      cur := q2
      {value: Some(x), done: false}
    | None => {value: None, done: true}
    }
  {next}
}
```

- [ ] **Step 3: Create `src/PersistentQueue.resi`**

```rescript
// PersistentQueue.resi — public surface of the persistent FIFO queue.
//
// Two-list persistent queue. `enqueue` is O(1); `dequeue`/`peek` are O(1)
// amortised (O(N) worst case for the internal reverse, amortised to O(1)).

/** Opaque persistent FIFO queue. */
type t<'a>

/** Empty queue. */
let make: unit => t<'a>

/** Number of elements. */
let size: t<'a> => int

/** True iff the queue contains no elements. */
let isEmpty: t<'a> => bool

/** Returns a new queue with `x` added at the back. O(1). */
let enqueue: (t<'a>, 'a) => t<'a>

/** The front element, or `None` if empty. O(1). */
let peek: t<'a> => option<'a>

/** The front element. Throws `Not_found` if empty. O(1). */
let peekExn: t<'a> => 'a

/** Returns `Some((front, rest))`, or `None` if empty. O(1) amortised. */
let dequeue: t<'a> => option<('a, t<'a>)>

/** Returns `(front, rest)`. Throws `Not_found` if empty. O(1) amortised. */
let dequeueExn: t<'a> => ('a, t<'a>)

/** Materialise the queue into a JS array in front-to-back order. */
let toArray: t<'a> => array<'a>

/** Build a queue from a JS array (first element becomes the front). */
let fromArray: array<'a> => t<'a>

/** Iterate every element in front-to-back order. */
let forEach: (t<'a>, 'a => unit) => unit

/** Left fold in front-to-back order. */
let reduce: (t<'a>, 'b, ('b, 'a) => 'b) => 'b

/** Map every element through `f`, preserving order. */
let map: (t<'a>, 'a => 'b) => t<'b>

/** Keep elements satisfying `f`, preserving order. */
let filter: (t<'a>, 'a => bool) => t<'a>

/** JS-style iterator step — `{value: None, done: true}` once exhausted. */
type iterStep<'a> = {value: option<'a>, done: bool}

/** JS-style iterator. */
type iter<'a> = {next: unit => iterStep<'a>}

/** Build a JS-style iterator over the queue's elements (front to back). */
let iterator: t<'a> => iter<'a>
```

- [ ] **Step 4: Re-export from `src/ResDs.res` and `src/ResDs.resi`**

In `src/ResDs.res` add:
```rescript
module Queue = PersistentQueue
```

In `src/ResDs.resi` add:
```rescript
module Queue = PersistentQueue
```

- [ ] **Step 5: Build and run all tests**

```bash
pnpm run res:build && pnpm test -- --reporter=verbose 2>&1 | tail -30
```

Expected: all tests pass including the new `PersistentQueue` tests.

- [ ] **Step 6: Commit**

```bash
git add src/PersistentQueue.res src/PersistentQueue.resi \
        src/ResDs.res src/ResDs.resi \
        tests/PersistentQueue_test.res
git commit -m "feat: add PersistentQueue (persistent FIFO, two-list amortised O(1))

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 13: Update `README.md` with new API surface

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Queue to the module table and add entries for each new function group**

In `README.md`, update the module overview table to include `Queue`:

```markdown
| `ResDs.Queue` | `PersistentQueue` | Persistent FIFO queue |
```

Add a `### PersistentQueue` section after `PersistentHashSet` with the same format used for the other modules (constructor, enqueue, dequeue, peek, toArray, fromArray, iterator).

Add a note in each module's section for the new functions added (isEmpty, first/last, slice/concat, find/findIndex/some/every for Vector; isEmpty, map/filter/update for HashMap; isEmpty, equals/isSubsetOf/isSupersetOf/filter/map for HashSet).

- [ ] **Step 2: Verify README renders correctly**

```bash
cat README.md | head -100
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document Queue module and new API additions in README

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

---

### Task 14: Write `docs/API.md` — full API reference with complexity

**Files:**
- Create: `docs/API.md`

- [ ] **Step 1: Create `docs/API.md`**

The file must document every public symbol across all five modules (`Hash`, `Vector`, `HashMap`, `HashSet`, `Queue`) with:
- A one-line description
- Big-O complexity (time)
- Whether it throws and what exception

Structure:

```markdown
# res-ds API Reference

> All modules are re-exported from the top-level `ResDs` barrel:
> `ResDs.Hash`, `ResDs.Vector`, `ResDs.HashMap`, `ResDs.HashSet`, `ResDs.Queue`.

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
| `isSubsetOf` | `(t<'a>, t<'a>) => bool` | True iff every element of `a` is in `b`. | O(N) |
| `isSupersetOf` | `(t<'a>, t<'a>) => bool` | True iff every element of `b` is in `a`. | O(N) |

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
```

- [ ] **Step 2: Verify file was created**

```bash
wc -l docs/API.md
```

Expected: > 100 lines.

- [ ] **Step 3: Commit**

```bash
git add docs/API.md
git commit -m "docs: add docs/API.md — full API reference with complexity

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Critical bug: exception mismatch → Task 1
- ✅ Important: undocumented push-alias → Task 2
- ✅ Important: null/undefined coalescence → Task 3
- ✅ Important: eager iterators → Task 4
- ✅ Minor: equals short-circuit → Task 5
- ✅ Enhancement: isEmpty → Task 6
- ✅ Enhancement: first/last → Task 7
- ✅ Enhancement: slice/concat → Task 8
- ✅ Enhancement: find/findIndex/some/every → Task 9
- ✅ Enhancement: HashMap map/filter/update → Task 10
- ✅ Enhancement: HashSet equals/isSubsetOf/filter/map → Task 11
- ✅ Enhancement: PersistentQueue → Task 12
- ✅ Documentation → Task 13

- ✅ Documentation API.md → Task 14

**Type consistency:** All function signatures reference only types defined in the same or earlier tasks. `PersistentQueue.t` is used only in Task 12 tasks.
