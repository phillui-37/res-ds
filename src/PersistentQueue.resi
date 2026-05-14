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
