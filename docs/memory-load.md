# Memory-load benchmarking

How Pharo behaves when the image holds 1 GB … 1 TB of live objects: time to
allocate, time to GC over it, time to snapshot, time to come back up. The
harness is `GenieMemoryLoadBenchmark` (package `Genie-MemoryLoad`), driven by
`scripts/memory-load-bench`.

## What one run measures

Each run is one tier in one fresh VM launch, phases in order:

| metric | meaning |
|---|---|
| `allocMs`, `allocMBPerSecond` | build the live set chunk by chunk |
| `scavengeCount/Ms`, `fullGCCount/Ms` | GC work the VM did *during* allocation (VM params 7–10) |
| `fullGCAtLoadMs` | one explicit full GC with the whole tier live — the pause-time number |
| `snapshotMs`, `imageFileBytes` | `Smalltalk snapshot:` with the load live, and the resulting file size |
| `releaseMs`, `heapBytesAfterRelease` | drop everything, full GC — does the heap shrink back? |
| `coldStartMs` (from the shell runner) | launch the fat snapshot until it quits |
| Max RSS (from `/usr/bin/time -v`) | what the OS actually charged, vs. `heapBytesAfterAlloc` |

Two allocation shapes, because they stress different things:

- **`smallObjects`** (default) — chunks of 16 384 seven-slot Arrays, 64 bytes
  each on 64-bit Spur. Billions of pointer objects; worst case for marking,
  scavenging, and tenuring.
- **`byteArrays`** — 1 MiB ByteArrays. Nearly no objects to mark; isolates raw
  allocation and the disk-write cost of snapshots.

Results stream to stdout as JSON lines plus a progress line per GiB, so
partial results survive an OOM kill of a later phase.

## Preparing the image (small machine, once)

```smalltalk
Metacello new
    baseline: 'Genie';
    repository: 'github://KentBeck/SmalltalkGenie:<branch-or-sha>/src';
    load.
```

Verify the harness, then save:

```smalltalk
(GenieMemoryLoadBenchmarkTest buildSuite run) printString.  "expect all pass"
Smalltalk snapshot: true andQuit: true.
```

Copy that image + a matching VM to the benchmark host. Prepare once, reuse
for every tier — the runner copies the image per rep, so the prepared image
is never dirtied.

## Where to run the big tiers

Not locally, and not in a default CI/agent container. Sizing rule of thumb:
**RAM ≈ 1.3–1.5× the tier** (heap + new space + VM/OS headroom, no swap) and
**free fast disk ≈ 2× the tier** (the snapshot writes a file about the size
of the heap; the runner keeps one copy plus the prepared image).

One deliberately blunt point: at these sizes **snapshot time is a disk
benchmark**. A 1 TB snapshot at ~2 GB/s local NVMe is ~9 minutes; on default
EBS gp3 (125 MB/s) it's over two hours. Use instances with **local NVMe**, put
`WORKDIR` on it, or you're measuring the network storage tier, not Pharo.

Rent by the hour — a full matrix is a few hours of machine time:

| tier | RAM needed | example host | approx cost |
|---|---|---|---|
| 1 GB | any | laptop / CI box | – |
| 10 GB | 32–64 GB | AWS `r7i.2xlarge` | ~$0.5/hr |
| 100 GB | ~192–256 GB | AWS `x2iedn.2xlarge` (has NVMe) | ~$1.7/hr |
| 1 TB | ~1.5–2 TB | AWS `x2iedn.16xlarge` — 2 TiB RAM + local NVMe | ~$13/hr |

(Prices are ballpark on-demand us-east-1; spot is ~60–70% off and fine here —
runs are short and restartable. GCP `m3-megamem`/`m1-ultramem` and Azure
`Msv3` are the equivalents. A Hetzner dedicated 1 TB box is far cheaper per
month but only worth it if this becomes a recurring benchmark.)

Host notes for clean numbers: no swap; record kernel, VM version, and
transparent-huge-pages setting; big instances are multi-socket, and Pharo is
single-threaded, so consider `numactl --interleave=all` to reduce variance;
watch `dmesg` for OOM-killer visits — a killed rep still leaves its progress
lines in `results.jsonl`.

## Running

```bash
# 1 GB and 10 GB, 5 reps each, snapshots on, results in results.jsonl:
scripts/memory-load-bench ./pharo bench.image 1073741824 10737418240

# 100 GB and 1 TB on the big box, workdir on local NVMe:
WORKDIR=/nvme/bench REPS=5 scripts/memory-load-bench ./pharo bench.image \
    107374182400 1099511627776

# Same tiers, allocation-only (no huge files):
SNAPSHOT=false scripts/memory-load-bench ./pharo bench.image 1099511627776

# Raw-allocation shape:
MODE=byteArrays scripts/memory-load-bench ./pharo bench.image 10737418240
```

Protocol: 5 reps per tier per mode, report medians; run tiers smallest →
largest so a failure loses the least; `DROP_CACHES=true` (root) makes
`coldStartMs` honest by forcing the snapshot to be read from disk.

Caveat: the snapshot phase saves mid-run, so launching that image later
resumes inside the benchmark. The harness detects the resume (session
changed), prints `{"resumedFromSnapshot":true}`, and stops — that's expected
in the cold-start launch; ignore that line when aggregating.

## Beyond the four tiers — other tests worth running

1. **Full-GC pause vs. live-set size.** `fullGCAtLoadMs` across tiers: is it
   linear? A multi-minute stop-the-world at 1 TB is the number that decides
   whether a huge image is *operable*, not just *loadable*.
2. **Server responsiveness under load.** Genie-specific and arguably the most
   important: run `GenieServer` while a big eval churns memory and measure MCP
   request latency percentiles. A scavenge/full GC blocks the whole image —
   how bad does tool latency get at 100 GB?
3. **Steady-state churn.** Allocate/release 10% of the tier in a loop:
   fragmentation, compaction cost, and whether RSS creeps above live bytes.
4. **Shrink-back.** After `releaseMs`: does `heapBytesAfterRelease` (and RSS)
   actually return segments to the OS, or does the image stay fat forever?
5. **The ceiling.** Push allocation until it fails: do you get a catchable
   `OutOfMemory` signal or a VM abort/OOM-kill? Also `maxOldSpaceSize`
   behavior when a cap is set.
6. **Access after load.** Enumeration (`allObjectsDo:`), a Dictionary/Set with
   10⁸–10⁹ entries (identity-hash distribution at scale), `become:` with a
   huge heap — operations whose cost depends on heap size, not live work.
7. **Startup tail.** After cold start of a fat image, time the *first* full GC
   and first scavenge — lazily-mapped pages make the first touch expensive.
8. **Medium objects / mixed shapes.** The two modes bracket the space; real
   heaps are mixtures. A 50/50 mix run tells you whether costs compose.
9. **Disk sensitivity.** Same 100 GB tier on NVMe vs. network storage to
   quantify how much of `snapshotMs` is Pharo vs. the device.
10. **Variance.** Everything ×5; if rep-to-rep spread at a tier exceeds ~10%,
    something environmental (NUMA, THP, page cache) is leaking into the data.
