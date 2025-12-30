# sqlnet_aix_tune_staged.ksh — Stage Guide (English)

This document explains what each stage in `sqlnet_aix_tune_staged.ksh` does, why it exists, what it changes on AIX, and how to validate impact using your existing tcpdump+awk + notebook workflow.

---

## Purpose (What the script is optimizing)

Your measured “response delay” (client→DB PUSH to next DB→client PUSH on the same client port) is already very low at baseline (P50 ~1–2ms). The remaining customer-visible issue is **tail latency** (multi-second outliers, max events).

These stages focus on reducing **rare long stalls** by:
- preventing MTU/PMTU-induced fragmentation or tiny-packet behavior,
- improving TCP loss recovery (avoiding long timeouts),
- aligning socket buffers so bursts don’t produce backpressure or queueing artifacts.

---

## What the script produces (Artifacts)

Each stage produces before/after snapshots under:

- `OUTDIR/stageX_pre/`
- `OUTDIR/stageX_post/`

Each snapshot includes:
- `system.txt` (timestamp, uname, oslevel)
- `lsattr_<iface>.txt` (interface attributes)
- `no_all.txt` + `no_focus.txt` (all AIX `no` tunables + focused subset)
- `netstat_s.txt` (protocol counters snapshot)

It also creates a rollback state file on first modification:

- `OUTDIR/state.env`

---

## Stages Overview (1–4)

### Stage 0 — Baseline only
**Action:** `--baseline`  
**What it does:** Captures the current system/network tuning state.  
**What it changes:** Nothing.

**When to run:** Always run before any changes to document the starting point.

---

## Stage 1 — MTU/PMTU normalization (Interface-level)

**Action:** `--stage 1`  
**Primary goal:** Avoid PMTU/fragmentation edge cases that can create sporadic multi-second stalls.

**What it changes:**
- Interface attribute: `remmtu` on the selected interface (default `en1`)
- Default target: `remmtu=1500`

**Command used:**
- `chdev -l en1 -a remmtu=1500`

**Why this matters:**
- `mtu=1500` with an abnormally low `remmtu` (e.g., 576) can force suboptimal packetization and/or fragmentation interactions across multi-hop paths. This can manifest as rare but severe tail events.

**Risks / Notes:**
- If the path includes tunnels (IPsec/GRE/MPLS), a true path MTU may be lower than 1500. In that case you should set `remmtu` to the largest safe value (often 1400–1492), or use MSS clamping elsewhere. This stage assumes 1500 is safe unless the network path dictates otherwise.

**Validation (after stage 1):**
- Re-run a controlled app test + capture window.
- Confirm:
  - Reduction in `MAX` and counts `>=10s` / `>=20s`.
  - CCDF tail probability at 1s/5s/10s improves or remains stable.

---

## Stage 2 — Loss recovery improvements (Kernel TCP behavior)

**Action:** `--stage 2`  
**Primary goal:** Reduce timeouts and speed up recovery when packet loss or reordering happens.

**What it changes (AIX `no` tunables):**
- `sack` (Selective Acknowledgement): default target `1`
- `tcp_pmtu_discover` (Path MTU Discovery): default target `1`

**Commands used:**
- Runtime:
  - `no -o sack=1`
  - `no -o tcp_pmtu_discover=1`
- If `--persist` is used:
  - `no -p -o sack=1`
  - `no -p -o tcp_pmtu_discover=1`

**Why this matters:**
- With SACK enabled, TCP can recover multiple lost segments efficiently without excessive retransmission cycles.
- PMTU discovery helps avoid fragmentation and helps TCP adapt packet sizing to the actual path. This reduces tail stalls caused by repeated retransmission/timeouts on blackholed fragments.

**Risks / Notes:**
- Very uncommon: some legacy middleboxes can mishandle SACK/PMTU behaviors. If tail gets worse, rollback stage 2 first.

**Validation (after stage 2):**
- Compare pre/post:
  - tail counters (`>1s`, `>5s`, `>10s`, `>=20s`)
  - CCDF tail at 1s/5s/10s
  - `MAX` reduction and “top worst events” list

---

## Stage 3 — Global TCP socket buffer alignment

**Action:** `--stage 3`  
**Primary goal:** Align global send/receive buffers with your intended steady-state (avoid under-buffering that amplifies burst effects).

**What it changes (AIX `no` tunables):**
- `tcp_sendspace` to default target `262144` (256 KB)
- `tcp_recvspace` to default target `262144` (256 KB)

**Commands used:**
- Runtime:
  - `no -o tcp_sendspace=262144`
  - `no -o tcp_recvspace=262144`
- If `--persist` is used:
  - `no -p -o tcp_sendspace=262144`
  - `no -p -o tcp_recvspace=262144`

**Why this matters:**
- If global buffers are smaller than what your interface/app effectively uses, you can see intermittent queueing/backpressure under burst concurrency, which shows up in tail.
- This stage usually does not move P50, but can help reduce tail volatility.

**Risks / Notes:**
- Larger buffers can increase memory usage under high connection counts. 256 KB is typically conservative for enterprise app servers, but you should confirm typical concurrent sessions.

**Validation (after stage 3):**
- Tail counters and `MAX`
- Ensure no new memory pressure is introduced (optional: correlate with `vmstat`).

---

## Stage 4 — Raise socket buffer ceiling (sb_max)

**Action:** `--stage 4`  
**Primary goal:** Ensure the kernel allows sufficiently large socket buffers when configured or negotiated.

**What it changes (AIX `no` tunable):**
- `sb_max` to default target `4194304` (4 MB)

**Commands used:**
- Runtime:
  - `no -o sb_max=4194304`
- If `--persist` is used:
  - `no -p -o sb_max=4194304`

**Why this matters:**
- `sb_max` is a cap. If it is too low, even if you increase `tcp_sendspace/tcp_recvspace` or application-level buffers, the kernel may not allow effective scaling.
- This stage enables headroom; it may not show immediate benefit alone unless buffer pressure exists.

**Risks / Notes:**
- Like stage 3, larger buffer ceilings can increase potential memory usage if many sockets expand to near cap. Most workloads do not push all sockets to `sb_max`.

**Validation (after stage 4):**
- Same as prior stages: focus on `MAX` and multi-second tail counts.

---

## Recommended Execution Order

1. `--baseline`
2. `--stage 1` (MTU/PMTU normalization)
3. `--stage 2` (SACK + PMTU discovery)
4. `--stage 3` (tcp_sendspace/tcp_recvspace)
5. `--stage 4` (sb_max)

Validate after each stage using **the same test procedure** and the same capture window length.

---

## Persistence vs Runtime

- By default, the script applies **runtime-only** changes (safe for testing).
- Add `--persist` to make changes survive reboot:
  - Uses `no -p -o` for kernel tunables
  - Interface changes via `chdev` typically update ODM; behavior can be platform/attr dependent, which is why the script snapshots before/after.

---

## Rollback (Full revert)

**Action:** `--rollback`  
**What it does:** Restores values saved in `OUTDIR/state.env`.

Rollback is the first troubleshooting step if any stage makes tail worse.

---

## Validation Checklist (Engagement-proof)

After each stage, generate your standard metrics and explicitly report:

1. **Worst-case MAX** (seconds) PRE vs POST-stage
2. Tail counters:
   - `>1s`, `>5s`, `>10s`, `>=20s`
3. CCDF probability at:
   - 1s, 5s, 10s
4. “Top worst delays” list (ranked) to show the largest events shrinking/disappearing

This is the most defensible way to demonstrate improvement without needing application-level instrumentation.

---
