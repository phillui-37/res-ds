// PersistentHashSet.res
// Persistent hash set built on PersistentHashMap. The map's value is just
// a sentinel — we keep it as `unit` so the runtime cost is one bit.

module M = PersistentHashMap

type t<'a> = M.t<'a, unit>

let make = (): t<'a> => M.make()

let size = (s: t<'a>): int => M.size(s)
let isEmpty = (s: t<'a>): bool => M.isEmpty(s)
let has = (s: t<'a>, x: 'a): bool => M.has(s, x)
let add = (s: t<'a>, x: 'a): t<'a> => M.set(s, x, ())
let remove = (s: t<'a>, x: 'a): t<'a> => M.remove(s, x)

let fromArray = (arr: array<'a>): t<'a> => {
  let s = ref(make())
  Array.forEach(arr, x => s := add(s.contents, x))
  s.contents
}

let toArray = (s: t<'a>): array<'a> => M.keys(s)

let forEach = (s: t<'a>, f: 'a => unit): unit => M.forEach(s, (k, _) => f(k))

let reduce = (s: t<'a>, init: 'b, f: ('b, 'a) => 'b): 'b =>
  M.reduce(s, init, (acc, k, _) => f(acc, k))

let union = (a: t<'a>, b: t<'a>): t<'a> => M.merge(a, b)

let intersect = (a: t<'a>, b: t<'a>): t<'a> =>
  M.withTransient(make(), t => {
    forEach(a, x =>
      if has(b, x) {
        M.setMut(t, x, ())->ignore
      }
    )
    t
  })

let difference = (a: t<'a>, b: t<'a>): t<'a> =>
  M.withTransient(make(), t => {
    forEach(a, x =>
      if !has(b, x) {
        M.setMut(t, x, ())->ignore
      }
    )
    t
  })

// Iterator yielding each element once.
type iterStep<'a> = {value: option<'a>, done: bool}
type iter<'a> = {next: unit => iterStep<'a>}

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
  {next: next}
}

// ───────────────────────── transient ─────────────────────────

type transient<'a> = M.transient<'a, unit>

let asTransient = (s: t<'a>): transient<'a> => M.asTransient(s)
let addMut = (t: transient<'a>, x: 'a): transient<'a> => M.setMut(t, x, ())
let removeMut = (t: transient<'a>, x: 'a): transient<'a> => M.removeMut(t, x)
let hasMut = (t: transient<'a>, x: 'a): bool =>
  switch M.getMut(t, x) {
  | Some(_) => true
  | None => false
  }
let persistent = (t: transient<'a>): t<'a> => M.persistent(t)
let withTransient = (s: t<'a>, f: transient<'a> => transient<'a>): t<'a> =>
  s->asTransient->f->persistent

// ───────────────────────── comparison and filtering ─────────────────────────

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
