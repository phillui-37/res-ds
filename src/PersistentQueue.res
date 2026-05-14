// Persistent FIFO queue using the classic two-list representation.
// `front` holds elements in dequeue order (head first); `rear` holds newly enqueued
// elements in reverse order (most-recent first).
// When `front` is exhausted, `rear` is reversed into `front`.
//
// Amortised complexity:
//   enqueue  — O(1)
//   dequeue  — O(1) amortised (O(N) worst case for the reverse)
//   peek     — O(1)

type t<'a> = {
  size: int,
  front: list<'a>,
  rear: list<'a>,
}

let make = (): t<'a> => {size: 0, front: list{}, rear: list{}}

let size = (q: t<'a>): int => q.size

let isEmpty = (q: t<'a>): bool => q.size == 0

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
  {next: next}
}
