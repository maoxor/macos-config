# Performance: how this Mac uses its resources, and what is worth changing

A knowledge base built from measurements on the machine (MacBook Pro M5 Max, 18 cores = 6 P + 12 E, 64 GB
unified memory, macOS 26.6) and from sources cross-checked against them. Rule: **no optimisation without a
measured need, a before/after number and a rollback.** The goal is work done, not resources saved: a job that
needs 50 GB gets 50 GB; concurrency is reduced only when it is measured to be counter-productive. Reliability: **M** = measured here, **D** = official
documentation, **C** = community reports (useful, not proof).

## 1. Measure first: `scripts/perf-journal.py`

The launchd agent `perf-journal` (home-manager/startup.nix) takes one sample a minute and keeps 8 days in
`~/Library/Logs/macos-config/perf/`. Cost measured: 0.3 s of CPU a sample (0.5 % of one core), about 2 MB a day.

```sh
scripts/perf-journal.py report 24   # last 24 h: pressure, swap, compressor, CPU user/system, GPU, top processes
scripts/perf-journal.py now         # one sample, printed
```

What it records and why:
| Measure | Source | Why this one |
|---|---|---|
| Memory per process | `proc_pid_rusage` → `ri_phys_footprint` | Activity Monitor's Memory column, what jetsam counts. **RSS lies here** (M): a torch MPS job had RSS 209 MB for a 30 GB footprint (Metal buffers), a data replay 1.3 GB RSS for 7.6 GB (compressed pages). |
| Memory pressure | `kern.memorystatus_level` | the kernel's own "free %" (same as `memory_pressure`). "Memory used" near 64 GB means nothing alone. |
| Wired, compressor, swap, compressions/s, swap-ins/s | `vm_stat`, `vm.swapusage` | the real cost of a shortage: compressing and paging take CPU and SSD I/O. |
| CPU user / system | `host_processor_info` | `kernel_task` is unreadable without root; the system share carries its work (compression, paging). |
| GPU utilisation and memory | IOAccelerator `PerformanceStatistics` | unified memory: GPU allocations are wired RAM taken from the same 64 GB. |
| GPU time per process | `AGXDeviceUserClient` `accumulatedGPUTime` | sudoless attribution (macmon and asitop give power, not per-process GPU time). |

## 2. Memory on Apple silicon: what "full" means

- **Full is normal, pressure is not.** macOS keeps file cache and compresses idle pages before it swaps
  (D/C: [Eclectic Light, M1 memory](https://eclecticlight.co/2022/03/01/making-sense-of-m1-memory-use/),
  [Activity Monitor meanings](https://eclecticlight.co/2022/08/13/activity-monitor-meanings-and-misleadings/)).
  The signals of a real shortage are a sustained high compression rate, swap-ins every second, a system CPU share
  in double digits, and `memorystatus_level` low.
- **GPU memory is wired.** It cannot be compressed or swapped. One 30 GB MPS job moved wired memory from 6 to
  26 GB and pushed everything else into the compressor (M).
- **A shortage costs CPU.** Measured on 2026-10-29 with an ML job + five data replays + a parallel linter:
  235,000 compressions/s, 15,000 swap-ins/s (about 240 MB/s read from the SSD), **31 % of all cores in the
  kernel**. When the ML job ended: wired 26 → 6 GB, kernel free 24 → 85 %, system CPU 31 → 5 % (M).
- **Swap is not the enemy, thrashing is.** A few GB of swap with calm swap-ins is fine; pageouts overcount
  real SSD writes (C: [MacRumors](https://forums.macrumors.com/threads/memory-swap-usage-higher-on-m1-chips-than-intel.2271844)).
  Disabling swap or the compressor removes the safety margin: rejected.
- **The 2026-10-12 panic was memory exhaustion.** "watchdog timeout: no checkins from watchdogd in 91 seconds";
  its compressor line reads "100% of segments limit (BAD) with 70 swapfiles" (M). Watchdog panics have other
  causes too (C: [Apple forums](https://developer.apple.com/forums/thread/835414)); this one's log names memory.
- **So was the 2026-10-30 one, and both ended at the same wall** (M): "100% of segments limit (BAD)" with 70 and 68
  swapfiles, 31.5 + 70 and 33 + 68 GB of compressed data in memory + swap, i.e. the store's capacity, segment limit
  × segment size (1,653,622 × 64 KB = 100.9 GB on 64 GB of RAM). `vm.compressor.segment.total` does not measure it:
  it is a high-water mark that never falls. **Memory pressure does not see it coming**: 30 s before the collapse the
  kernel still reported 41 % free and level 2, with 2 × 55 GB jobs swapping at 640 MB/s (0.6 % of the store per
  second). The two jobs had declared 16 GB each. Same jobs at 19:30 that day: 95 % of the store, a near miss.

## 3. Principle: orchestrate, do not cap

Throughput rises with concurrency until the working sets of the running jobs no longer fit in memory; past that
point the machine thrashes and every job slows down (Denning's working-set theory: load control suspends
processes to restore throughput, as 4.4BSD, AIX and HP-UX did; D/C:
[Denning & Graham 1975](https://typeset.io/pdf/multiprogrammed-memory-management-5fpbbollr8.pdf),
[USENIX 2001](https://usenix.org/legacy/publications/library/proceedings/als01/full_papers/jiang/jiang_html/node9.html)).
CPU oversubscription alone is cheap (context switches cost 1-2 µs, C:
[HPDC 2021](https://ranger.uta.edu/~jiang/publication/Conferences/2021/HPDC2021.pdf)); memory oversubscription is
what costs here (§2: 31 % of the cores in the kernel). Hence:
- **admit by real free memory**, not by a fixed number of jobs (GNU parallel `--memfree` / `--memsuspend`, Ray's
  memory monitor and Dask's pause threshold follow the same idea; D:
  [Ray OOM prevention](https://docs.ray.io/en/latest/ray-core/scheduling/ray-oom-prevention.html));
- **reduce concurrency only while thrashing is measured**, by pausing the youngest job (cheaper than killing it,
  its pages are compressed or swapped once and stay quiet), and resume when it is calm;
- **find the best parallelism by measuring throughput** at several levels and fitting the Universal Scalability
  Law, X(N) = λN / (1 + α(N−1) + βN(N−1)), peak at N* = √((1−α)/β) (D:
  [Gunther](https://arxiv.org/pdf/0809.2541.pdf)); more workers are kept as long as they add throughput.

## 4. `jobgate`: the shared orchestrator (`scripts/jobgate.py`, on PATH as `jobgate`)

```sh
jobgate run [--mem GB] [--gpu] [--name KEY] -- CMD...   # wait for room, run at full power, supervise, record
PARALLEL_PROCESSOR_COUNT=$(jobgate workers --per-worker 0.5) rubocop --parallel   # workers that fit now
jobgate bench --levels 1,2,4,8,12,18 -- CMD {i}         # throughput per level + USL optimum (run on an idle Mac)
jobgate status | jobgate history [KEY]
```
- **Admission**: need ≤ kernel free memory − what admitted jobs will still grow into − a reserve (8 % of RAM).
  Need = the larger of `--mem` and the 95th percentile of the job's past peaks ×1.1 (learnt from `history`, all
  exits), 4 GB until it is learnt, at most 60 % of RAM. A low `--mem` no longer hides what a job really reaches, for
  the jobs already running too (`admitted_needs`). Nothing starts while the compressor's store is ≥ 50 % full.
  FIFO; a younger job may overtake while older waiters have waited under 10 min (no starvation).
- **GPU**: a `--gpu` job also waits while the GPU is already ≥ 70 % busy (two jobs on a saturated GPU share it,
  neither finishes sooner) and gets **PyTorch MPS watermarks sized to the memory free at its start**: high =
  room / recommendedMaxWorkingSetSize (read from Metal), low = 0.8 × high. Not a fixed cap: with 57 GB free a
  job may use 57 GB; it only cannot ask for the ~95 GB the default 1.7 allows on 64 GB (§7).
- **Thrashing guard**: pressure warn/critical, or swap-ins > 2,000 pages/s with kernel CPU > 15 %, for 10 s →
  the youngest running pausable job is paused (SIGSTOP; never the last running one; GPU jobs are not pausable,
  their wired memory would not be freed); after 20 s of calm the oldest paused job resumes.
- **Last resort** (the legacy watchdog's role): memory critical (pressure level 4, or under 3 % free) for 20 s →
  the youngest job, paused or not, is stopped (SIGTERM, SIGKILL after 20 s) with exit 75 so its caller can retry.
- **Memory guard** (`scripts/memory-guard.swift`, launchd agent `memory-guard`, `memory-guard --check`): the panics
  come faster than the last resort above and without critical pressure, and a Python supervisor may stall with the
  Mac. A compiled loop reads the store every 2 s without forking; at ≥ 70 % it stops the youngest jobgate job over
  4 GB, else the largest command-line process over 8 GB (SIGTERM, SIGKILL after 3 s). Apps are never stopped: it
  then only warns. Measured over two days: a single job peaks at 53 %, 74 % was a minute from 95 %, and from 70 % the
  worst rate leaves about 45 s. The stopped job's script usually retries: jobgate holds it until there is room.
- **Compatibility**: it honours the projects' `heavy.py` / `lourd.py` lock (`~/.cache/gpu-lourd.lock`): a
  `--gpu` job waits for a live legacy holder and for older legacy tickets, and holds the lock while it runs,
  so the legacy copies keep working unchanged.
- Measures footprint (Metal buffers and compressed pages included: a 2 GB MPS tensor read 2.32 GB) where
  `heavy.py` read RSS (§5). Tests: `jobgate self-test` (in `scripts/check.sh`); live tests 2026-10-29: learnt need,
  exit codes, youngest-paused / oldest-resumed, legacy lock wait and hand-over, a real torch job under the
  dynamic watermarks.

## 5. The legacy lock (`heavy.py` / `lourd.py` copies in the projects)

Sessions agreed on a lock (`~/.cache/gpu-lourd.lock` + a queue) after the 2026-10-12 panic. Two measurement
errors make it admit jobs that do not fit (M, 2026-10-29):
- "no other process above 6 GB" reads **RSS**: the 7.6-8 GB replays (RSS 1.3-1.5 GB) and a 30 GB MPS job
  (RSS 0.2 GB) are invisible to it.
- "available" = free + inactive + speculative + purgeable from `vm_stat`, which ignores what the compressor and
  the GPU already hold.
**Migrated on 2026-10-29**: the 12 copies (a shared helper and the copies inside projects) are now
`scripts/heavy-compat.py`: same command line
(`python3 -S heavy.py NEED_GB cmd…`), same lock for scripts that write it by hand, decisions by
`jobgate run --gpu --mem NEED_GB`; without jobgate (another Mac) the command runs directly. Originals backed up in
`~/.local/state/macos-power-user-deploy/backups/jobgate-migration-20261029-145221/` (`ROLLBACK.txt`).

## 6. Structural wins measured (do more with the same machine)

| Change | Before | After | Check |
|---|---|---|---|
| Data replays: preprocessed series written once to a binary file and **mmap'd read-only** by every process (instead of each process parsing and cleaning the same CSV) | load 263 s, peak 9.2 GB per process; short replay 408 s, peak 8.4 GB | load 0.01 s; short replay **147 s, peak 0.23 GB**; 3 processes share one 1.06 GB copy (clean file pages: never compressed nor swapped, just dropped and re-read) | outputs identical except wall-clock timestamps; cache key = input content + all the code that transforms it |
| Element access through `memoryview` instead of `array` | 8.5 s full pass | 8.8 s (+3 %) | the price of sharing, far below the load saved |
| Background QoS (`taskpolicy -b`) on the same load | ~4.4 min on P cores | 10 min on E cores | keep it for jobs nobody waits for |

**Best parallelism, measured** (2026-10-29, user away, other agents' jobs running: load 3-54; `jobgate bench`-style
runs, minimum of 3 wall times, ±0.5 s for RuboCop):

| Workload | 1 | 2 | 4 | 6 | 9 | 12 | 18 | 24 | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| RuboCop, 957 files, all cops, cold cache (wall s) | 15.6 | 17.6 | 4.5 | 4.0 | 3.0 | 2.5 | 2.0 | 2.0 | the default (one worker per core = 18) is the optimum: ×7.8; **a cap at 6 would double the time** |
| Data replays with the shared cache (wall s for N at once) | 118 | 123 | 122 | 145 | 189 | 200 | — | — | throughput ×7.1 at 12 (×1.84 over the former fixed cap of 4); still rising (USL α 0.09, β 0) |

RuboCop parallelises through its result cache: `--cache false` silently disables `--parallel` ("-P/--parallel is
being ignored because it is not compatible with --cache false"); benchmark it with a fresh `--cache-root`. Without
the shared cache, 12 replays would have needed ~100 GB of peaks: the structural change is what makes the
parallelism usable.

Pattern: when N processes read the same large derived data, compute it once, store it in a native layout and map
it; the page cache shares it, the memory pressure of N copies disappears, and start-up staggering becomes useless.

## 7. PyTorch MPS memory: tested

`recommended_max_memory` is 55.7 GB here and the default high watermark is 1.7×, so **an MPS job may allocate
up to ~95 GB on a 64 GB Mac** (D: [PyTorch MPS variables](https://docs.pytorch.org/docs/2.14/mps_environment_variables.html)).
Setting only the high ratio below 1.4 fails with "invalid low watermark ratio 1.4": the low ratio (default 1.4)
must be set too. Test (torch 2.14.1, high 0.03, low 0.02): 1.5 GB allocated, the next 512 MB refused with a
clean "MPS backend out of memory" error (M). MLX has its own limits (`set_memory_limit`, default 1.5 × the
recommended working set; `set_wired_limit`; D: [mlx-c memory.h](https://forge.lthn.ai/core/go-mlx/src/branch/main/dist/include/mlx/memory.h)).

## 8. Other levers, by measured benefit

| Lever | Measure | Verdict |
|---|---|---|
| Energy mode | AC: High Power (`powermode 2`), battery: Automatic (M). On M5 Max, High Power holds ~70 W sustained against ~54 W, +8 % Cinebench multi-core (C: [Notebookcheck](https://www.notebookcheck.net/Did-Apple-reduce-the-performance-of-the-M5-Max-via-software-update-Yes-and-no.1376940.0.html)) | keep: already the full-power setting |
| Background QoS (`taskpolicy -b`) | confines a job to the E cores (D/C: [Eclectic Light, QoS](https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/)); a load that takes ~3 min on P cores took 10 min (M) | only for jobs nobody waits for; not a default |
| Ghostty opaque, no blur | 2-7 % GPU time, 12-60 % CPU with 11 windows (M) | negligible next to the jobs: keep the look |
| Spotlight privacy for generated-data folders | `mds_stores` 3 % of a core averaged over 4 days (M); `.metadata_never_index` no longer works (C: [Eclectic Light, Spotlight](https://eclecticlight.co/2024/11/29/using-and-troubleshooting-spotlight-in-sequoia-summary/)) | low priority |
| Docker Desktop idle | about 2 GB (M) | the user's choice |

Rejected (no measured need, or harmful): memory "cleaners" and `purge` (they empty a useful cache), disabling
swap/compressor/SIP/services, `ulimit -v` (RLIMIT_AS is not enforced on macOS; C:
[Fast Downward issue 825](https://ai-fast-downward.dmi.unibas.ch/issue825)), raising `iogpu.wired_limit_mb`
(lets the GPU wire even more of a RAM that is already short), fixed caps on workers or memory.
