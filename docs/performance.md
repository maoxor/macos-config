# Performance: how this Mac uses its resources, and what is worth changing

A knowledge base built from measurements on the machine (MacBook Pro M5 Max, 18 cores = 6 P + 12 E, 64 GB
unified memory, macOS 26.6) and from sources cross-checked against them. Rule: **no optimisation without a
measured need, a before/after number and a rollback.** Reliability: **M** = measured here, **D** = official
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

## 3. Levers, ranked by measured benefit

| Lever | Benefit | Risk / cost | Status |
|---|---|---|---|
| **Admit heavy jobs by memory** (one ML job at a time, and only if its need fits) | avoids thrashing and panics | jobs wait | a shared lock exists in the projects; it must measure footprint, not RSS (§4) |
| **Cap PyTorch MPS** (`PYTORCH_MPS_HIGH_WATERMARK_RATIO` + `PYTORCH_MPS_LOW_WATERMARK_RATIO`) | a job that outgrows RAM fails cleanly instead of freezing the Mac | a job needing more than the cap fails | proposed (§5) |
| **Fewer simultaneous copies of the same data** | one Python object per M1 candle costs 212 bytes against 40 in an array (M): a replay loading 20 pairs is 6.4 GB in objects, 1.2 GB in arrays | code change in the project | proposed to the project |
| **Bound parallel workers** (`PARALLEL_PROCESSOR_COUNT=N` for RuboCop, `n_jobs` for joblib) | each lot spawns one worker per core (D: [RuboCop CLI](https://docs.rubocop.org/rubocop/usage/cli_reference.html)); several lots at once multiply memory | slower single lot | proposed |
| Background QoS for batch jobs (`taskpolicy -b <cmd>`) | confines them to the E cores, P cores stay free for interactive work (D/C: [Eclectic Light, QoS](https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/)) | the job runs slower; `nice` alone does not change the core type | optional |
| Ghostty opaque, no blur | Ghostty measured 2-7 % GPU time, 12-60 % CPU with 11 windows (M); blur goes through a private WindowServer API (C) | visual change | A/B test to run with the user |
| Spotlight privacy for big generated-data folders | `mds_stores` averaged 3 % of a core over 4 days (M); `.metadata_never_index` no longer works, use System Settings or a `.noindex` suffix (C: [Eclectic Light, Spotlight](https://eclecticlight.co/2024/11/29/using-and-troubleshooting-spotlight-in-sequoia-summary/)) | lost search results there | low priority |
| Quit Docker Desktop when unused | about 2 GB (VM 1.4 GB + app) (M) | none | the user's choice |

Rejected (no measured need, or harmful): memory "cleaners" and `purge` (they empty a useful cache),
disabling swap/compressor/SIP/services, `ulimit -v` (RLIMIT_AS is not enforced on macOS; C:
[Fast Downward issue 825](https://ai-fast-downward.dmi.unibas.ch/issue825)), raising `iogpu.wired_limit_mb`
(lets the GPU wire even more of the RAM that is already short), more oversubscription (the context-switch
cost is small, C: [HPDC 2021](https://ranger.uta.edu/~jiang/publication/Conferences/2021/HPDC2021.pdf);
on this machine the cost of extra parallel jobs is their memory, not their scheduling).

## 4. The shared heavy-job lock (`heavy.py` / `lourd.py` copies in the projects)

Sessions agreed on a lock (`~/.cache/gpu-lourd.lock` + a queue) after the 2026-10-12 panic. Two measurement
errors make it admit jobs that do not fit (M, 2026-10-29):
- "no other process above 6 GB" reads **RSS**: the 7.6-8 GB replays (RSS 1.3-1.5 GB) and a 30 GB MPS job
  (RSS 0.2 GB) are invisible to it. Fix: `ri_phys_footprint` (as `perf-journal.py` does).
- "available" = free + inactive + speculative + purgeable from `vm_stat`, which ignores what the compressor and
  the GPU already hold. Fix: `kern.memorystatus_level` × RAM, or require the job's need below it.
There are about ten diverging copies; one shared implementation would keep them consistent.

## 5. PyTorch MPS cap: tested

`recommended_max_memory` is 55.7 GB here and the default high watermark is 1.7×, so **an MPS job may allocate
up to ~95 GB on a 64 GB Mac** (D: [PyTorch MPS variables](https://docs.pytorch.org/docs/2.14/mps_environment_variables.html)).
Setting only the high ratio below 1.4 fails with "invalid low watermark ratio 1.4": the low ratio (default 1.4)
must be set too. Test (torch 2.14.1, high 0.03, low 0.02): 1.5 GB allocated, the next 512 MB refused with a
clean "MPS backend out of memory" error (M). Suggested values for 64 GB: high 0.8 (~44 GB), low 0.65 (~36 GB).
