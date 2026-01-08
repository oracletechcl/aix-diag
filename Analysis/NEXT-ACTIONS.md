# Next Actions – SQL*Net / End-to-End Latency

## 1) Correlate Wallclock to Customer 16.2s
- Re-export tcpdump with `-tttt` (absolute time) for both PRE/POST if feasible.
- In notebooks, re-run wallclock plots; align burst start/end ISO timestamps to app/MQ/DB logs.
- Identify where any residual >10–16s spans accumulate (app queue, MQ, DB wait, CPU scheduling).

## 2) Reduce Chatty / Round-Trip Cost
- Increase JDBC/OCI `arraysize`/prefetch and batch small calls; avoid row-by-row patterns.
- Consider `TCP.NODELAY=YES` on SQL*Net if workloads are interactive and packet sizes are small.
- Keep session reuse high; avoid frequent logons.

## 3) Database Waits & Commit Strategy
- Trace top statements and waits (`log file sync`, `db file sequential/scattered read`, `enqueue`).
- Tune plans/indexes; ensure bind usage; avoid hot blocks and slow sequences.
- If safe, reduce commit frequency (batch commits) to cut round-trip commits.

## 4) MQ / App Queues
- Inspect queue depth and consumer lag around burst times; scale consumers or tune prefetch.
- Remove unnecessary retries/backoffs; ensure thread pools are not saturated.
- Check GC pauses and CPU headroom on app tier; pin noisy neighbors if needed.

## 5) Network Path Hygiene
- Verify end-to-end MTU consistency (or true jumbo if all hops allow); avoid fragmentation.
- Check loss/dups/ECN on path; remediate noisy interfaces/ports.
- Keep SDU/TDU consistent (e.g., 32767) across client/listener/server.

## 6) Monitoring & Alerts (Closure Guardrails)
- Add alerts on burst MAX and counts >10s/>15s, plus response-delay >10s.
- Track P99/P99.9 for response-delay and burst durations daily post-change.
- Record tcpdump spans and packet counts for each capture to spot anomalies quickly.

## 7) Re-run & Validate
- Run `sql_net_compare_all_pairs.sh -p Dec12-Ene06` (or target pair) after changes.
- Re-run the notebook with the matching `PAIR` to regenerate KPIs, bursts, wallclock plots, and narrative.
- Document before/after in `closure_narrative.md` and keep plots/CSVs under `out/<PAIR>/summary/`.

## 8) Extension to Other Pairs
- Add new PAIR entries to `sql_net_compare_all_pairs.sh` map and rerun.
- Execute notebooks with the new `PAIR` to confirm improvements and regenerate closure artifacts.
