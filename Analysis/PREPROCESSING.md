
# PRE-PROCESSING

0) Define variables once (recommended)

```bash
export PRE="oci_tcpdump_20251212_155703.pcap"
export POST="oci_tcpdump_20251229_173137.pcap"
export C="192.168.84.67"
export D="100.112.1.74"
export P="1521"
```

1) Sanity: capture span for SQL*Net traffic (client<->db only)

This proves you are comparing comparable datasets.

1.1 PRE Span

```bash
tcpdump -nn -tt -r "$PRE" "host $C and host $D and tcp port $P" \
| awk 'NR==1{start=$1} {end=$1} END{printf "PRE sqlnet span: %.6f seconds\n", end-start}'
```

1.2 POST Span
```bash
tcpdump -nn -tt -r "$POST" "host $C and host $D and tcp port $P" \
| awk 'NR==1{start=$1} {end=$1} END{printf "POST sqlnet span: %.6f seconds\n", end-start}'
```
Expected: both roughly similar order-of-magnitude (depends on capture time).

Result: 

```bash
dralquinta@Denny-Macbook-Pro-M5 tcpdump -nn -tt -r "$PRE" "host $C and host $D and tcp port $P" \
| awk 'NR==1{start=$1} {end=$1} END{printf "PRE sqlnet span: %.6f seconds\n", end-start}'

reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
PRE sqlnet span: 179.957195 seconds
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % tcpdump -nn -tt -r "$POST" "host $C and host $D and tcp port $P" \
| awk 'NR==1{start=$1} {end=$1} END{printf "POST sqlnet span: %.6f seconds\n", end-start}'

reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
POST sqlnet span: 182.231568 seconds
```

So this is **179.96** vs **182.23** seconds. This means the conversation roundtrip is valid and the conversation is valid via OCI Protocol. 

----

2) Enumerate ALL client ephemeral ports (i.e., TCP sessions)

This is mandatory because OCI/SQL*Net uses multiple concurrent sessions.

2.1 PRE ports


```bash
tcpdump -nn -tt -r "$PRE" "src host $C and dst host $D and tcp dst port $P" \
| awk '
  {
    # format: "<ts> IP 192.168.84.67.<port> > 100.112.1.74.1521:"
    src=$3
    n=split(src,a,".")
    print a[n]
  }
' | sort -n | uniq > pre_ports.txt

wc -l pre_ports.txt | awk '{print "PRE distinct client ports:", $1}'

```
2.2 POST ports

```bash
tcpdump -nn -tt -r "$POST" "src host $C and dst host $D and tcp dst port $P" \
| awk '
  {
    src=$3
    n=split(src,a,".")
    print a[n]
  }
' | sort -n | uniq > post_ports.txt

wc -l post_ports.txt | awk '{print "POST distinct client ports:", $1}'

```

Results:

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % tcpdump -nn -tt -r "$PRE" "src host $C and dst host $D and tcp dst port $P" \
| awk '
  {
    # format: "<ts> IP 192.168.84.67.<port> > 100.112.1.74.1521:"
    src=$3
    n=split(src,a,".")
    print a[n]
  }
' | sort -n | uniq > pre_ports.txt

wc -l pre_ports.txt | awk '{print "PRE distinct client ports:", $1}'
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
PRE distinct client ports: 489
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % tcpdump -nn -tt -r "$POST" "src host $C and dst host $D and tcp dst port $P" \
| awk '
  {
    src=$3
    n=split(src,a,".")
    print a[n]
  }
' | sort -n | uniq > post_ports.txt

wc -l post_ports.txt | awk '{print "POST distinct client ports:", $1}'

reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
POST distinct client ports: 463
```

---

3) Per-port “payload push” extraction (rigorous proxy for application exchanges)

We will analyze only packets that:
- are in one TCP session (one client port)
- carry application payload likely to represent SQL*Net activity (Flags [P.])

This is a defensible proxy because:
- pure ACKs do not represent application progress
- stalls manifest as time gaps between pushes

---
4) Build a per-port stall summary CSV (PRE)

This produces:
pre_stalls.csv with columns:

- port
- pkts (push packets count)
- elapsed_s (end-start in that port)
- max_gap_s (largest inter-packet gap)
- stall_gt_50ms (gap > 0.05s count)
- stall_gt_200ms (gap > 0.2s count)


```bash
echo "port,pkts,elapsed_s,max_gap_s,stall_gt_50ms,stall_gt_200ms" > pre_stalls.csv

while read -r PORT; do
  tcpdump -nn -tt -r "$PRE" \
    "((src host $C and src port $PORT) or (dst host $C and dst port $PORT)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
  | awk -v port="$PORT" '
      NR==1 {start=$1; prev=$1; maxgap=0; s50=0; s200=0; pkts=0}
      {
        t=$1
        gap=t-prev
        if (gap>maxgap) maxgap=gap
        if (gap>0.05) s50++
        if (gap>0.2) s200++
        prev=t
        end=t
        pkts++
      }
      END {
        if (pkts>0) {
          elapsed=end-start
          printf "%s,%d,%.6f,%.6f,%d,%d\n", port, pkts, elapsed, maxgap, s50, s200
        }
      }
  ' >> pre_stalls.csv
done < pre_ports.txt

```

Execution:

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % echo "port,pkts,elapsed_s,max_gap_s,stall_gt_50ms,stall_gt_200ms" > pre_stalls.csv

while read -r PORT; do
  tcpdump -nn -tt -r "$PRE" \
    "((src host $C and src port $PORT) or (dst host $C and dst port $PORT)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
  | awk -v port="$PORT" '
      NR==1 {start=$1; prev=$1; maxgap=0; s50=0; s200=0; pkts=0}
      {
        t=$1
        gap=t-prev
        if (gap>maxgap) maxgap=gap
        if (gap>0.05) s50++
        if (gap>0.2) s200++
        prev=t
        end=t
        pkts++
      }
      END {
        if (pkts>0) {
          elapsed=end-start
          printf "%s,%d,%.6f,%.6f,%d,%d\n", port, pkts, elapsed, maxgap, s50, s200
        }
      }
  ' >> pre_stalls.csv
done < pre_ports.txt
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
...
...
...
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
```

---
5) Build the same stall summary CSV (POST)



```bash
echo "port,pkts,elapsed_s,max_gap_s,stall_gt_50ms,stall_gt_200ms" > post_stalls.csv

while read -r PORT; do
  tcpdump -nn -tt -r "$POST" \
    "((src host $C and src port $PORT) or (dst host $C and dst port $PORT)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
  | awk -v port="$PORT" '
      NR==1 {start=$1; prev=$1; maxgap=0; s50=0; s200=0; pkts=0}
      {
        t=$1
        gap=t-prev
        if (gap>maxgap) maxgap=gap
        if (gap>0.05) s50++
        if (gap>0.2) s200++
        prev=t
        end=t
        pkts++
      }
      END {
        if (pkts>0) {
          elapsed=end-start
          printf "%s,%d,%.6f,%.6f,%d,%d\n", port, pkts, elapsed, maxgap, s50, s200
        }
      }
  ' >> post_stalls.csv
done < post_ports.txt

```

Execution:

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % echo "port,pkts,elapsed_s,max_gap_s,stall_gt_50ms,stall_gt_200ms" > post_stalls.csv

while read -r PORT; do
  tcpdump -nn -tt -r "$POST" \
    "((src host $C and src port $PORT) or (dst host $C and dst port $PORT)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
  | awk -v port="$PORT" '
      NR==1 {start=$1; prev=$1; maxgap=0; s50=0; s200=0; pkts=0}
      {
        t=$1
        gap=t-prev
        if (gap>maxgap) maxgap=gap
        if (gap>0.05) s50++
        if (gap>0.2) s200++
        prev=t
        end=t
        pkts++
      }
      END {
        if (pkts>0) {
          elapsed=end-start
          printf "%s,%d,%.6f,%.6f,%d,%d\n", port, pkts, elapsed, maxgap, s50, s200
        }
      }
  ' >> post_stalls.csv
done < post_ports.txt

reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
...
...
...
reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
```
---
6) Produce comparable “worst case” summaries

6.1 Worst max gap (PRE vs POST)


```bash
echo "PRE worst max_gap_s:"
tail -n +2 pre_stalls.csv | sort -t, -k4,4nr | head -1

echo "POST worst max_gap_s:"
tail -n +2 post_stalls.csv | sort -t, -k4,4nr | head -1

```

Result:
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % echo "PRE worst max_gap_s:"
tail -n +2 pre_stalls.csv | sort -t, -k4,4nr | head -1

echo "POST worst max_gap_s:"
tail -n +2 post_stalls.csv | sort -t, -k4,4nr | head -1
PRE worst max_gap_s:
49342,15817,174.129063,138.705223,3,2
POST worst max_gap_s:
62061,437,166.432454,165.931747,1,1
```

6.2 Top 10 ports by max gap (PRE vs POST)


```bash
echo "PRE top 10 by max_gap_s:"
tail -n +2 pre_stalls.csv | sort -t, -k4,4nr | head -10

echo "POST top 10 by max_gap_s:"
tail -n +2 post_stalls.csv | sort -t, -k4,4nr | head -10

```

Results: 
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % echo "PRE top 10 by max_gap_s:"
tail -n +2 pre_stalls.csv | sort -t, -k4,4nr | head -10

echo "POST top 10 by max_gap_s:"
tail -n +2 post_stalls.csv | sort -t, -k4,4nr | head -10

PRE top 10 by max_gap_s:
49342,15817,174.129063,138.705223,3,2
33361,803,156.703401,137.943905,2,2
57922,9555,179.938848,128.946786,26,15
57845,7352,144.850469,128.914383,21,12
60074,5286,135.915096,120.160094,6,3
33424,798,118.433389,117.680081,1,1
33577,9015,140.286065,112.003498,29,17
33441,21,163.329052,106.719238,4,4
36706,5731,104.765947,97.858346,2,2
49281,1534,176.160311,95.107605,20,17
POST top 10 by max_gap_s:
62061,437,166.432454,165.931747,1,1
61388,658,164.401520,162.438423,3,3
39834,60,149.781271,149.389986,2,2
56029,5097,162.485414,145.627822,2,2
59691,335,158.940295,140.006765,5,3
60471,14,148.959004,130.089228,4,2
37684,4786,169.581199,122.399202,3,3
55920,28352,181.996709,121.224960,25,22
60446,586,142.805484,120.373734,6,5
55857,8686,177.010292,113.555694,32,18
```

6.3 Total stall events across all sessions

```bash
echo "PRE total stalls >50ms and >200ms:"
tail -n +2 pre_stalls.csv | awk -F, '{s50+=$5; s200+=$6} END{print "stall_gt_50ms=",s50," stall_gt_200ms=",s200}'

echo "POST total stalls >50ms and >200ms:"
tail -n +2 post_stalls.csv | awk -F, '{s50+=$5; s200+=$6} END{print "stall_gt_50ms=",s50," stall_gt_200ms=",s200}'
```

Results:
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % echo "PRE total stalls >50ms and >200ms:"
tail -n +2 pre_stalls.csv | awk -F, '{s50+=$5; s200+=$6} END{print "stall_gt_50ms=",s50," stall_gt_200ms=",s200}'

echo "POST total stalls >50ms and >200ms:"
tail -n +2 post_stalls.csv | awk -F, '{s50+=$5; s200+=$6} END{print "stall_gt_50ms=",s50," stall_gt_200ms=",s200}'

PRE total stalls >50ms and >200ms:
stall_gt_50ms= 9750  stall_gt_200ms= 7031
POST total stalls >50ms and >200ms:
stall_gt_50ms= 11147  stall_gt_200ms= 7657
```
---
7) Transaction-like latency proxy (first N PUSH packets)

This replicates your proven method (NR==20) but makes it systematic.

Choose N=20 (same as you used). You can also use 50 for stability.

7.1 Compute on the worst port (PRE)


```bash
WPRE=$(tail -n +2 pre_stalls.csv | sort -t, -k4,4nr | head -1 | cut -d, -f1)
echo "PRE worst port: $WPRE"

tcpdump -nn -tt -r "$PRE" \
  "((src host $C and src port $WPRE) or (dst host $C and dst port $WPRE)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
| awk '
    NR==1 {start=$1}
    NR==20 {end=$1; printf "PRE elapsed first 20 PUSH: %.6f seconds\n", (end-start); exit}
    END {if (NR<20) print "PRE: <20 packets, cannot compute"}
'
```

Results: 

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % WPRE=$(tail -n +2 pre_stalls.csv | sort -t, -k4,4nr | head -1 | cut -d, -f1)
echo "PRE worst port: $WPRE"

tcpdump -nn -tt -r "$PRE" \
  "((src host $C and src port $WPRE) or (dst host $C and dst port $WPRE)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
| awk '
    NR==1 {start=$1}
    NR==20 {end=$1; printf "PRE elapsed first 20 PUSH: %.6f seconds\n", (end-start); exit}
    END {if (NR<20) print "PRE: <20 packets, cannot compute"}
'

PRE worst port: 49342
reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
PRE elapsed first 20 PUSH: 0.055714 seconds
tcpdump: Unable to write output: Broken pipe
```

7.2 Compute on the worst port (POST)

```bash
WPOST=$(tail -n +2 post_stalls.csv | sort -t, -k4,4nr | head -1 | cut -d, -f1)
echo "POST worst port: $WPOST"

tcpdump -nn -tt -r "$POST" \
  "((src host $C and src port $WPOST) or (dst host $C and dst port $WPOST)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
| awk '
    NR==1 {start=$1}
    NR==20 {end=$1; printf "POST elapsed first 20 PUSH: %.6f seconds\n", (end-start); exit}
    END {if (NR<20) print "POST: <20 packets, cannot compute"}
'
```

Results: 

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % WPOST=$(tail -n +2 post_stalls.csv | sort -t, -k4,4nr | head -1 | cut -d, -f1)
echo "POST worst port: $WPOST"

tcpdump -nn -tt -r "$POST" \
  "((src host $C and src port $WPOST) or (dst host $C and dst port $WPOST)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
| awk '
    NR==1 {start=$1}
    NR==20 {end=$1; printf "POST elapsed first 20 PUSH: %.6f seconds\n", (end-start); exit}
    END {if (NR<20) print "POST: <20 packets, cannot compute"}
'

POST worst port: 62061
reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
POST elapsed first 20 PUSH: 0.073766 seconds
tcpdump: Unable to write output: Broken pipe
```

---

8) Optional: measure “median” port instead of worst (more representative)

Worst-case can be affected by idle sessions. For a representative stream, pick the port with the highest packet count (pkts) instead.

PRE most active port

```bash
MPRE=$(tail -n +2 pre_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "PRE most active port: $MPRE"

```
Result:
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % MPRE=$(tail -n +2 pre_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "PRE most active port: $MPRE"

PRE most active port: 33502
```

POST most active port


```bash
MPOST=$(tail -n +2 post_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "POST most active port: $MPOST"

```
Results:

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % MPOST=$(tail -n +2 post_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "POST most active port: $MPOST"

POST most active port: 60538
```

---
8) Optional: measure “median” port instead of worst (more representative)

Worst-case can be affected by idle sessions. For a representative stream, pick the port with the highest packet count (pkts) instead.


PRE most active port
```bash
MPRE=$(tail -n +2 pre_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "PRE most active port: $MPRE"

```

Results:

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % MPRE=$(tail -n +2 pre_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "PRE most active port: $MPRE"

PRE most active port: 33502
```


POST most active port
```bash
MPOST=$(tail -n +2 post_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "POST most active port: $MPOST"

```
Results
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % MPOST=$(tail -n +2 post_stalls.csv | sort -t, -k2,2nr | head -1 | cut -d, -f1)
echo "POST most active port: $MPOST"

POST most active port: 60538
```
---

# POST PROCESSING

1. Export variables

```bash
export PRE="oci_tcpdump_20251212_155703.pcap"
export POST="oci_tcpdump_20251229_173137.pcap"
export C="192.168.84.67"
export D="100.112.1.74"
export P="1521"
```

1) Identify the most active SQL*Net session (client ephemeral port)

This is the only defensible way to pick a stream representative of the actual workload.

PRE: most active port
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % MPRE=$(
  tcpdump -nn -tt -r "$PRE" "src host $C and dst host $D and tcp dst port $P and tcp[tcpflags] & tcp-push != 0" \
  | awk '{src=$3; n=split(src,a,"."); port=a[n]; c[port]++} END{for(p in c) print c[p],p}' \
  | sort -nr | head -1 | awk '{print $2}'
)
echo "PRE most-active client port: $MPRE"

reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
PRE most-active client port: 33502
```


POST: most active port

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % MPOST=$(
  tcpdump -nn -tt -r "$POST" "src host $C and dst host $D and tcp dst port $P and tcp[tcpflags] & tcp-push != 0" \
  | awk '{src=$3; n=split(src,a,"."); port=a[n]; c[port]++} END{for(p in c) print c[p],p}' \
  | sort -nr | head -1 | awk '{print $2}'
)
echo "POST most-active client port: $MPOST"

reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
POST most-active client port: 60538
```
---

2) Extract that single TCP stream (PUSH payload only)
PRE stream extract
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % tcpdump -nn -tt -r "$PRE" \
"((src host $C and src port $MPRE) or (dst host $C and dst port $MPRE)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
> pre_stream_$MPRE.txt

reading from file oci_tcpdump_20251212_155703.pcap, link-type EN10MB (Ethernet)
```

POST stream extract

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % tcpdump -nn -tt -r "$POST" \
"((src host $C and src port $MPOST) or (dst host $C and dst port $MPOST)) and host $D and tcp port $P and tcp[tcpflags] & tcp-push != 0" \
> post_stream_$MPOST.txt

reading from file oci_tcpdump_20251229_173137.pcap, link-type EN10MB (Ethernet)
```

Sanity check for extraction:
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % wc -l pre_stream_$MPRE.txt post_stream_$MPOST.txt

   74017 pre_stream_33502.txt
   81365 post_stream_60538.txt
  155382 total
```
---
3) “Transaction-like” timing proxy (elapsed time to reach N PUSH packets)

This is the same method you validated (NR==20), but do it at multiple N to make it engagement-proof.

PRE elapsed for N = 20 / 200 / 1000


```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % for N in 20 200 1000; do
  awk -v N="$N" 'NR==1{start=$1} NR==N{printf "PRE N=%d elapsed=%.6f s\n", N, ($1-start); exit} END{if(NR<N) printf "PRE N=%d <insufficient packets>\n", N}' \
  pre_stream_$MPRE.txt
done

PRE N=20 elapsed=0.018644 s
PRE N=200 elapsed=0.199006 s
PRE N=1000 elapsed=0.889719 s
```

POST elapsed for N = 20 / 200 / 1000


```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % for N in 20 200 1000; do
  awk -v N="$N" 'NR==1{start=$1} NR==N{printf "POST N=%d elapsed=%.6f s\n", N, ($1-start); exit} END{if(NR<N) printf "POST N=%d <insufficient packets>\n", N}' \
  post_stream_$MPOST.txt
done

POST N=20 elapsed=0.019475 s
POST N=200 elapsed=0.177724 s
POST N=1000 elapsed=0.945611 s
```
---

4) Active-window stall analysis (rigorous; excludes idle time)

This fixes your earlier “max_gap” issue. We compute gaps between consecutive PUSH packets but only count gaps ≤ 1s as “active window.”
(Idle gaps are not performance; they are inactivity.)

PRE and POST active gaps (≤ 1s)


```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % awk '
NR==1 {prev=$1; next}
{
  gap=$1-prev
  if (gap<=1.0) print gap
  prev=$1
}
' pre_stream_$MPRE.txt > pre_gaps_active.txt

dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % awk '
NR==1 {prev=$1; next}
{
  gap=$1-prev
  if (gap<=1.0) print gap
  prev=$1
}
' post_stream_$MPOST.txt > post_gaps_active.txt
```

Count stalls in the active window (>50ms, >200ms) + max active gap

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % echo "PRE active-window stall counts:"
awk '{if($1>0.05)c50++; if($1>0.2)c200++; if($1>max)max=$1} END{printf "samples=%d stall>50ms=%d stall>200ms=%d max_active_gap=%.6f\n", NR,c50+0,c200+0,max+0}' pre_gaps_active.txt

echo "POST active-window stall counts:"
awk '{if($1>0.05)c50++; if($1>0.2)c200++; if($1>max)max=$1} END{printf "samples=%d stall>50ms=%d stall>200ms=%d max_active_gap=%.6f\n", NR,c50+0,c200+0,max+0}' post_gaps_active.txt

PRE active-window stall counts:
samples=73991 stall>50ms=29 stall>200ms=18 max_active_gap=0.871398
POST active-window stall counts:
samples=81334 stall>50ms=36 stall>200ms=21 max_active_gap=0.962716
```
---

Percentiles (P50/P95/P99) of active gaps

PRE
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % sort -n pre_gaps_active.txt > pre_gaps_active_sorted.txt
N=$(wc -l < pre_gaps_active_sorted.txt)
P50=$(( (N*50+99)/100 ))
P95=$(( (N*95+99)/100 ))
P99=$(( (N*99+99)/100 ))
echo "PRE active-gap percentiles (seconds):"
printf "N=%d P50=%s P95=%s P99=%s\n" \
  "$N" "$(sed -n "${P50}p" pre_gaps_active_sorted.txt)" \
  "$(sed -n "${P95}p" pre_gaps_active_sorted.txt)" \
  "$(sed -n "${P99}p" pre_gaps_active_sorted.txt)"

PRE active-gap percentiles (seconds):
N=73991 P50=0.0014329 P95=8.39233e-05 P99=9.67979e-05
```
POST
```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % sort -n post_gaps_active.txt > post_gaps_active_sorted.txt
N=$(wc -l < post_gaps_active_sorted.txt)
P50=$(( (N*50+99)/100 ))
P95=$(( (N*95+99)/100 ))
P99=$(( (N*99+99)/100 ))
echo "POST active-gap percentiles (seconds):"
printf "N=%d P50=%s P95=%s P99=%s\n" \
  "$N" "$(sed -n "${P50}p" post_gaps_active_sorted.txt)" \
  "$(sed -n "${P95}p" post_gaps_active_sorted.txt)" \
  "$(sed -n "${P99}p" post_gaps_active_sorted.txt)"

POST active-gap percentiles (seconds):
N=81334 P50=0.00146103 P95=9.01222e-05 P99=9.799e-05
```
---
5) Seq-based estimators for retransmissions and out-of-order (tcpdump-only)

This is not as perfect as tshark tcp.analysis.*, but it is rigorous enough to show “path disorder” from raw sequence progression.

PRE: retrans/ooo estimator (active window only: gap ≤ 1s per direction)


```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % awk -v C="$C" '
function is_client(src){ return index(src, C".")==1 }
{
  t=$1
  src=$3
  dir = is_client(src) ? "C2D" : "D2C"

  # find "seq" token
  seqtok=""
  for(i=1;i<=NF;i++) if($i=="seq"){ seqtok=$(i+1); gsub(",","",seqtok); break }
  if(seqtok=="") next

  split(seqtok,s,":")
  start=s[1]+0
  end=(s[2]!=""?s[2]:s[1])+0

  # per-direction time gap to avoid counting idle periods
  if(prevT[dir]!=""){
    gap=t-prevT[dir]
    if(gap>1.0){
      prevT[dir]=t
      lastStart[dir]=start
      next
    }
  }

  key=dir ":" start ":" end
  if(seen[key]++) retrans++
  if(lastStart[dir]!="" && start < lastStart[dir]) ooo++

  lastStart[dir]=start
  prevT[dir]=t
}
END{
  printf "PRE retrans_est=%d ooo_est=%d\n", retrans+0, ooo+0
}
' pre_stream_$MPRE.txt

PRE retrans_est=0 ooo_est=1
```


POST: retrans/ooo estimator

```bash
awk -v C="$C" '
function is_client(src){ return index(src, C".")==1 }
{
  t=$1
  src=$3
  dir = is_client(src) ? "C2D" : "D2C"

  seqtok=""
  for(i=1;i<=NF;i++) if($i=="seq"){ seqtok=$(i+1); gsub(",","",seqtok); break }
  if(seqtok=="") next

  split(seqtok,s,":")
  start=s[1]+0
  end=(s[2]!=""?s[2]:s[1])+0

  if(prevT[dir]!=""){
    gap=t-prevT[dir]
    if(gap>1.0){
      prevT[dir]=t
      lastStart[dir]=start
      next
    }
  }

  key=dir ":" start ":" end
  if(seen[key]++) retrans++
  if(lastStart[dir]!="" && start < lastStart[dir]) ooo++

  lastStart[dir]=start
  prevT[dir]=t
}
END{
  printf "POST retrans_est=%d ooo_est=%d\n", retrans+0, ooo+0
}
' post_stream_$MPOST.txt

```

```bash
dralquinta@Denny-Macbook-Pro-M5 antes-y-despues % awk -v C="$C" '
function is_client(src){ return index(src, C".")==1 }
{
  t=$1
  src=$3
  dir = is_client(src) ? "C2D" : "D2C"

  seqtok=""
  for(i=1;i<=NF;i++) if($i=="seq"){ seqtok=$(i+1); gsub(",","",seqtok); break }
  if(seqtok=="") next

  split(seqtok,s,":")
  start=s[1]+0
  end=(s[2]!=""?s[2]:s[1])+0

  if(prevT[dir]!=""){
    gap=t-prevT[dir]
    if(gap>1.0){
      prevT[dir]=t
      lastStart[dir]=start
      next
    }
  }

  key=dir ":" start ":" end
  if(seen[key]++) retrans++
  if(lastStart[dir]!="" && start < lastStart[dir]) ooo++

  lastStart[dir]=start
  prevT[dir]=t
}
END{
  printf "POST retrans_est=%d ooo_est=%d\n", retrans+0, ooo+0
}
' post_stream_$MPOST.txt

POST retrans_est=2 ooo_est=1

```

---

REDO



```bash
```

```bash
```

```bash
```

```bash
```

```bash
```

```bash
```

```bash
```

```bash
```

```bash
```

```bash
```
