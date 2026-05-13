// bench/Bench.res
// Micro-benchmarks comparing res-ds persistent collections to the
// counterparts shipped in `@rescript/core` (which wrap JavaScript's native
// mutable `Map` and `Array`).
//
// We measure two patterns for each "mutating" operation:
//   * Persistent / immutable: the natural res-ds API, vs. the equivalent
//     "copy then modify" pattern on the core types (the only fair way to
//     get an immutable result from a mutable container).
//   * In-place mutation: res-ds transients vs. the native mutable `Map.set` /
//     `Array.push`. Native mutation is the unbeatable lower bound.
//
// Run with: `pnpm bench`.

module V = PersistentVector
module M = PersistentHashMap

@val external now: unit => float = "performance.now"
@val external processVersion: string = "process.version"

let bench = (label: string, iterations: int, f: unit => unit): float => {
  // 1 untimed warm-up to let V8 JIT settle.
  f()
  let start = now()
  for _ in 1 to iterations {
    f()
  }
  let elapsed = now() -. start
  let perOp = elapsed /. Float.fromInt(iterations)
  Console.log(
    "  " ++
    label ++
    ": " ++
    Float.toFixed(elapsed, ~digits=2) ++
    " ms total, " ++
    Float.toFixed(perOp, ~digits=3) ++ " ms/run",
  )
  perOp
}

let header = title => {
  Console.log("")
  Console.log("── " ++ title ++ " ────────────────────────────────────────")
}

// ─────────────────────────── Vector vs Array ───────────────────────────

let benchVector = (n: int) => {
  header("Vector vs Array — N = " ++ Int.toString(n))
  let iters = n >= 100_000 ? 3 : 20

  let _ = bench("res-ds Vector  push (persistent)", iters, () => {
    let v = ref(V.make())
    for i in 0 to n - 1 {
      v := V.push(v.contents, i)
    }
  })
  let _ = bench("res-ds Vector  pushMut (transient)", iters, () => {
    let _ = V.withTransient(V.make(), t => {
      let cur = ref(t)
      for i in 0 to n - 1 {
        cur := V.pushMut(cur.contents, i)
      }
      cur.contents
    })
  })
  let _ = bench("Core Array     push  (mutable in-place)", iters, () => {
    let a = []
    for i in 0 to n - 1 {
      Array.push(a, i)
    }
  })
  let _ = bench("Core Array     concat (immutable copy)", iters >= 20 ? 5 : 1, () => {
    let a = ref([])
    for i in 0 to n - 1 {
      a := Array.concat(a.contents, [i])
    }
  })

  // Random reads on a pre-built collection. We accumulate into a sink so the
  // ReScript compiler can't drop these pure reads as dead code.
  let v = V.fromArray(Array.fromInitializer(~length=n, i => i))
  let a = Array.fromInitializer(~length=n, i => i)
  let sink = ref(0)
  let _ = bench("res-ds Vector  get (random)", 5, () => {
    for i in 0 to n - 1 {
      sink := sink.contents + V.getExn(v, i)
    }
  })
  let _ = bench("Core Array     get (random)", 5, () => {
    for i in 0 to n - 1 {
      sink := sink.contents + Array.getUnsafe(a, i)
    }
  })
  // Touch the sink so V8 cannot eliminate the loops above.
  if sink.contents == -1 {
    Console.log("unreachable")
  }

  // Single set: persistent vs whole-array clone.
  let _ = bench("res-ds Vector  set (persistent, one element)", 1000, () => {
    let _ = V.set(v, n / 2, -1)
  })
  let _ = bench("Core Array     set (immutable copy + mutate)", 1000, () => {
    let copy = Array.copy(a)
    Array.setUnsafe(copy, n / 2, -1)
  })
}

// ─────────────────────────── HashMap vs Map ───────────────────────────

let benchMap = (n: int) => {
  header("HashMap vs Map — N = " ++ Int.toString(n))
  let iters = n >= 100_000 ? 3 : 20

  // Pre-compute the keys so all benches hash the same strings.
  let keys = Array.fromInitializer(~length=n, i => "k" ++ Int.toString(i))

  let _ = bench("res-ds HashMap set (persistent)", iters, () => {
    let m = ref(M.make())
    for i in 0 to n - 1 {
      m := M.set(m.contents, Array.getUnsafe(keys, i), i)
    }
  })
  let _ = bench("res-ds HashMap setMut (transient)", iters, () => {
    let _ = M.withTransient(M.make(), t => {
      let cur = ref(t)
      for i in 0 to n - 1 {
        cur := M.setMut(cur.contents, Array.getUnsafe(keys, i), i)
      }
      cur.contents
    })
  })
  let _ = bench("Core Map       set  (mutable in-place)", iters, () => {
    let mm = Map.make()
    for i in 0 to n - 1 {
      Map.set(mm, Array.getUnsafe(keys, i), i)
    }
  })
  // "Immutable Map.set" really means: clone every entry, then mutate the new map.
  // We cap iterations because this is O(N²) — Vite's bench wall-clock would
  // otherwise be dominated by the warm-up of a single iteration.
  let immIters = n <= 1000 ? 3 : 1
  let immN = Math.Int.min(n, 5000)
  let immKeys = Array.fromInitializer(~length=immN, i => "k" ++ Int.toString(i))
  let _ = bench(
    "Core Map       clone+set (immutable, " ++ Int.toString(immN) ++ " keys)",
    immIters,
    () => {
      let mm = ref(Map.make())
      for i in 0 to immN - 1 {
        let next = Map.fromIterator(Map.entries(mm.contents))
        Map.set(next, Array.getUnsafe(immKeys, i), i)
        mm := next
      }
    },
  )

  // Lookups on a fully-loaded collection.
  let m = M.withTransient(M.make(), t => {
    let cur = ref(t)
    for i in 0 to n - 1 {
      cur := M.setMut(cur.contents, Array.getUnsafe(keys, i), i)
    }
    cur.contents
  })
  let mm = Map.make()
  for i in 0 to n - 1 {
    Map.set(mm, Array.getUnsafe(keys, i), i)
  }
  let sink = ref(0)
  let _ = bench("res-ds HashMap get", 5, () => {
    for i in 0 to n - 1 {
      sink := sink.contents + M.getExn(m, Array.getUnsafe(keys, i))
    }
  })
  let _ = bench("Core Map       get", 5, () => {
    for i in 0 to n - 1 {
      switch Map.get(mm, Array.getUnsafe(keys, i)) {
      | Some(v) => sink := sink.contents + v
      | None => ()
      }
    }
  })
  if sink.contents == -1 {
    Console.log("unreachable")
  }
}

let () = {
  Console.log("res-ds benchmarks (Node " ++ processVersion ++ ")")
  benchVector(10_000)
  benchVector(100_000)
  benchMap(10_000)
  benchMap(100_000)
}
