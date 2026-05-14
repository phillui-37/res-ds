open Vitest
module Q = ResDs.PersistentQueue

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
