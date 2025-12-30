#!/usr/bin/env bash
set -euo pipefail

CLIENT_IP="192.168.84.67"
DB_IP="100.112.1.74"
DB_PORT="1521"
PRE_PCAP="oci_tcpdump_20251212_155703.pcap"
POST_PCAP="oci_tcpdump_20251229_173137.pcap"
OUTDIR="out_compare"

die(){ echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--client) CLIENT_IP="$2"; shift 2;;
    -d|--db)     DB_IP="$2"; shift 2;;
    -p|--port)   DB_PORT="$2"; shift 2;;
    -pre|--pre)  PRE_PCAP="$2"; shift 2;;
    -post|--post) POST_PCAP="$2"; shift 2;;
    -o|--out)    OUTDIR="$2"; shift 2;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$CLIENT_IP" ]] || die "Missing -c CLIENT_IP"
[[ -n "$DB_IP"     ]] || die "Missing -d DB_IP"
[[ -n "$PRE_PCAP"  ]] || die "Missing -pre PRE_PCAP"
[[ -n "$POST_PCAP" ]] || die "Missing -post POST_PCAP"
command -v tcpdump >/dev/null 2>&1 || die "tcpdump not found"

mkdir -p "$OUTDIR"/{pre,post,summary}

extract_sqlnet_push() {
  local PCAP="$1"
  tcpdump -nn -tt -r "$PCAP" \
    "host $CLIENT_IP and host $DB_IP and tcp port $DB_PORT and tcp[tcpflags] & tcp-push != 0"
}

most_active_client_port() {
  awk -v C="$CLIENT_IP" -v D="$DB_IP" -v P="$DB_PORT" '
    function port_of(ipport,   a,n){ n=split(ipport,a,"."); return a[n] }
    {
      src=$3
      dst=$5; sub(/:$/,"",dst)
      if (index(src, C".")==1 && index(dst, D"."P)==1) {
        cp=port_of(src)
        c[cp]++
      }
    }
    END{
      maxc=-1; maxp=""
      for(p in c) if(c[p]>maxc){ maxc=c[p]; maxp=p }
      if(maxp!="") print maxp
    }
  '
}

compute_resp_delay() {
  awk -v C="$CLIENT_IP" '
    function is_client(ipport){ return index(ipport, C".")==1 }
    function port_of(ipport,   a,n){ n=split(ipport,a,"."); return a[n] }
    {
      t=$1
      src=$3
      dst=$5; sub(/:$/,"",dst)

      if (is_client(src)) { cp=port_of(src); last_req[cp]=t; next }
      if (is_client(dst)) { cp=port_of(dst); if (cp in last_req){ d=t-last_req[cp]; if(d>=0) printf "%s %.6f\n", cp, d } }
    }
  '
}

percentiles_sorted() {
  local FILE="$1"
  local N P50 P95 P99
  N=$(wc -l < "$FILE" | tr -d ' ')
  if [[ "$N" -le 0 ]]; then echo "N=0"; return; fi
  P50=$(( (N*50 + 99)/100 ))
  P95=$(( (N*95 + 99)/100 ))
  P99=$(( (N*99 + 99)/100 ))
  printf "N=%d P50=%s P95=%s P99=%s MAX=%s\n" \
    "$N" "$(sed -n "${P50}p" "$FILE")" "$(sed -n "${P95}p" "$FILE")" "$(sed -n "${P99}p" "$FILE")" "$(tail -n 1 "$FILE")"
}

tail_counters_resp_delay() {
  awk '{
    d=$2
    if(d>0.05)c50++;
    if(d>0.2)c200++;
    if(d>1)c1++;
    if(d>5)c5++;
    if(d>10)c10++;
  } END{
    printf ">50ms=%d >200ms=%d >1s=%d >5s=%d >10s=%d\n", c50+0,c200+0,c1+0,c5+0,c10+0
  }'
}

elapsed_to_N() {
  local FILE="$1"
  local N="$2"
  awk -v N="$N" 'NR==1{start=$1} NR==N{printf "%.6f\n",($1-start); exit} END{if(NR<N) print "NA"}' "$FILE"
}

active_gaps_le_1s() {
  awk 'NR==1{prev=$1; next}{gap=$1-prev; if(gap<=1.0) print gap; prev=$1}'
}

stall_counts_gaps() {
  awk '{g=$1; if(g>0.05)c50++; if(g>0.2)c200++; if(g>max)max=g} END{printf "samples=%d stall>50ms=%d stall>200ms=%d max_active_gap=%s\n",NR,c50+0,c200+0,(NR?max:0)}'
}

run_one() {
  local LABEL="$1"
  local PCAP="$2"
  local SUB
  SUB="$OUTDIR/$LABEL"

  mkdir -p "$SUB"
  echo "== Processing ${LABEL}: ${PCAP} =="

  extract_sqlnet_push "$PCAP" > "$SUB/sqlnet_push_all.txt" || true
  local LINES
  LINES=$(wc -l < "$SUB/sqlnet_push_all.txt" | tr -d ' ')
  echo "$LINES" > "$SUB/sqlnet_push_lines.txt"

  if [[ "$LINES" -eq 0 ]]; then
    echo "NA" > "$SUB/most_active_port.txt"
    echo "NA" > "$SUB/sqlnet_push_span_s.txt"
    echo "N=0" > "$SUB/resp_delay_percentiles.txt"
    echo ">50ms=0 >200ms=0 >1s=0 >5s=0 >10s=0" > "$SUB/resp_delay_tailcounts.txt"
    for N in 20 200 1000; do echo "NA" > "$SUB/elapsed_N${N}_s.txt"; done
    echo "N=0" > "$SUB/gaps_active_percentiles.txt"
    echo "samples=0 stall>50ms=0 stall>200ms=0 max_active_gap=0" > "$SUB/gaps_active_stalls.txt"
    return 0
  fi

  awk 'NR==1{start=$1}{end=$1} END{printf "%.6f\n",(end-start)}' "$SUB/sqlnet_push_all.txt" > "$SUB/sqlnet_push_span_s.txt"

  local MPORT
  MPORT=$(most_active_client_port < "$SUB/sqlnet_push_all.txt" || true)
  [[ -n "$MPORT" ]] || MPORT="NA"
  echo "$MPORT" > "$SUB/most_active_port.txt"

  if [[ "$MPORT" != "NA" ]]; then
    awk -v C="$CLIENT_IP" -v PORT="$MPORT" '
      {src=$3; dst=$5; sub(/:$/,"",dst); if (src ~ (C"\\."PORT"$") || dst ~ (C"\\."PORT"$")) print}
    ' "$SUB/sqlnet_push_all.txt" > "$SUB/stream_${MPORT}.txt"

    for N in 20 200 1000; do
      elapsed_to_N "$SUB/stream_${MPORT}.txt" "$N" > "$SUB/elapsed_N${N}_s.txt"
    done

    active_gaps_le_1s < "$SUB/stream_${MPORT}.txt" > "$SUB/gaps_active.txt"
    sort -g "$SUB/gaps_active.txt" > "$SUB/gaps_active_sorted.txt"
    stall_counts_gaps < "$SUB/gaps_active.txt" > "$SUB/gaps_active_stalls.txt"
    percentiles_sorted "$SUB/gaps_active_sorted.txt" > "$SUB/gaps_active_percentiles.txt"
  fi

  compute_resp_delay < "$SUB/sqlnet_push_all.txt" > "$SUB/resp_delay.txt"
  awk '{print $2}' "$SUB/resp_delay.txt" | sort -g > "$SUB/resp_delay_sorted.txt"
  percentiles_sorted "$SUB/resp_delay_sorted.txt" > "$SUB/resp_delay_percentiles.txt"
  tail_counters_resp_delay < "$SUB/resp_delay.txt" > "$SUB/resp_delay_tailcounts.txt"
  sort -k2,2gr "$SUB/resp_delay.txt" | head -20 > "$SUB/resp_delay_top20.txt" || true
}

run_one "pre"  "$PRE_PCAP"
run_one "post" "$POST_PCAP"

SUM="$OUTDIR/summary/summary.txt"
{
  echo "SQL*Net PRE/POST (tcpdump+awk only)"
  echo "Client=$CLIENT_IP DB=$DB_IP:$DB_PORT"
  echo "PRE=$PRE_PCAP"
  echo "POST=$POST_PCAP"
  echo ""
  echo "[sanity] sqlnet_push_lines:"
  echo -n "PRE : "; cat "$OUTDIR/pre/sqlnet_push_lines.txt"
  echo -n "POST: "; cat "$OUTDIR/post/sqlnet_push_lines.txt"
  echo ""
  echo "[span seconds] sqlnet_push_span_s:"
  echo -n "PRE : "; cat "$OUTDIR/pre/sqlnet_push_span_s.txt"
  echo -n "POST: "; cat "$OUTDIR/post/sqlnet_push_span_s.txt"
  echo ""
  echo "[most-active port]"
  echo -n "PRE : "; cat "$OUTDIR/pre/most_active_port.txt"
  echo -n "POST: "; cat "$OUTDIR/post/most_active_port.txt"
  echo ""
  echo "[elapsed N=20/200/1000 on most-active]"
  for N in 20 200 1000; do
    echo -n "PRE  N=$N : "; cat "$OUTDIR/pre/elapsed_N${N}_s.txt"
    echo -n "POST N=$N : "; cat "$OUTDIR/post/elapsed_N${N}_s.txt"
  done
  echo ""
  echo "[active-gap stalls + percentiles on most-active]"
  echo -n "PRE stalls: "; cat "$OUTDIR/pre/gaps_active_stalls.txt"
  echo -n "POST stalls: "; cat "$OUTDIR/post/gaps_active_stalls.txt"
  echo -n "PRE pct: "; cat "$OUTDIR/pre/gaps_active_percentiles.txt"
  echo -n "POST pct: "; cat "$OUTDIR/post/gaps_active_percentiles.txt"
  echo ""
  echo "[response-delay percentiles across ALL sessions]"
  echo -n "PRE : "; cat "$OUTDIR/pre/resp_delay_percentiles.txt"
  echo -n "POST: "; cat "$OUTDIR/post/resp_delay_percentiles.txt"
  echo ""
  echo "[response-delay tail counters across ALL sessions]"
  echo -n "PRE : "; cat "$OUTDIR/pre/resp_delay_tailcounts.txt"
  echo -n "POST: "; cat "$OUTDIR/post/resp_delay_tailcounts.txt"
} > "$SUM"

echo "DONE. Summary: $SUM"
