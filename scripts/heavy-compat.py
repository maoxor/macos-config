#!/usr/bin/env python3
"""Drop-in replacement for the heavy.py / lourd.py copies of the projects: python3 -S heavy.py NEED_GB command args...

Same command line and same shared lock (~/.cache/gpu-lourd.lock) as before, but the decisions are jobgate's
(macos-config scripts/jobgate.py, docs/performance.md): the job starts when NEED_GB is really free (footprints,
not RSS; kernel free memory, not free + inactive), PyTorch MPS gets watermarks sized to that free memory, the
job is paused rather than killed while the Mac thrashes, and stopped (exit 75) only if memory stays critical.
Without jobgate (another Mac), the command runs directly. Original copies backed up on 2026-10-29 in
~/.local/state/macos-power-user-deploy/backups/jobgate-migration-*/."""
import os, shutil, sys

if len(sys.argv) < 3:
    sys.exit("usage: python3 -S heavy.py NEED_GB command args...")
jobgate = shutil.which("jobgate") or os.path.expanduser("~/.local/bin/jobgate")
if os.path.exists(jobgate):
    os.execv("/usr/bin/python3", ["/usr/bin/python3", "-I", os.path.realpath(jobgate), "run", "--gpu",
                                  "--mem", sys.argv[1], "--", *sys.argv[2:]])
print("[heavy] jobgate not found: running the command without the shared queue", file=sys.stderr, flush=True)
os.execvp(sys.argv[2], sys.argv[2:])
