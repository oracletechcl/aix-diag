#!/bin/ksh

# ============================================================================
# AIX OS DIAGNOSTICS AND NETWORK CAPTURE SCRIPT
# ============================================================================
# USAGE (COPY AND PASTE THIS):
#   ./diagnose_oci_latency.sh <IP_DB_OCI> <LOCAL_INTERFACE> <DB_PORT> <TIME_TO_COLLECT_TCPDUMP>
#
# EXAMPLE:
#   ./diagnose_oci_latency.sh 10.50.20.15 ent0 1521 60
#
# WHAT EACH PARAMETER MEANS:
#   IP_DB_OCI              = The IP address of your Oracle database (example: 10.50.20.15)
#   LOCAL_INTERFACE        = Your network interface (example: ent0)
#   DB_PORT                = The database port number (usually 1521)
#   TIME_TO_COLLECT_TCPDUMP = How many seconds to capture network traffic (example: 60)
# ============================================================================

# Check if exactly 4 parameters were provided
if [ $# -ne 4 ]; then
    echo ""
    echo "ERROR: You must provide exactly 4 parameters!"
    echo ""
    echo "USAGE:"
    echo "  $0 <IP_DB_OCI> <LOCAL_INTERFACE> <DB_PORT> <TIME_TO_COLLECT_TCPDUMP>"
    echo ""
    echo "EXAMPLE:"
    echo "  $0 10.50.20.15 ent0 1521 60"
    echo ""
    echo "WHAT EACH PARAMETER MEANS:"
    echo "  IP_DB_OCI              = The IP address of your Oracle database"
    echo "  LOCAL_INTERFACE        = Your network interface (usually ent0 or similar)"
    echo "  DB_PORT                = The database port (usually 1521)"
    echo "  TIME_TO_COLLECT_TCPDUMP = How many seconds to capture network traffic"
    echo ""
    exit 1
fi

# Assign parameters to variables with clear names
IP_DB_OCI=$1
LOCAL_INTERFACE=$2
DB_PORT=$3
TIME_TO_COLLECT_TCPDUMP=$4

# Generate output file names with timestamp
OUTFILE="oci_diagnosis_$(date +%Y%m%d_%H%M%S).log"
PCAPFILE="/tmp/oci_tcpdump_$(date +%Y%m%d_%H%M%S).pcap"

echo "===================================================" | tee -a $OUTFILE
echo "AIX OS DIAGNOSTICS AND NETWORK CAPTURE" | tee -a $OUTFILE
echo "Fecha: $(date)" | tee -a $OUTFILE
echo "IP DB OCI: $IP_DB_OCI" | tee -a $OUTFILE
echo "Interfaz: $LOCAL_INTERFACE" | tee -a $OUTFILE
echo "Database Port: ${DB_PORT}" | tee -a $OUTFILE
echo "Tcpdump duration: ${TIME_TO_COLLECT_TCPDUMP}s" | tee -a $OUTFILE
echo "===================================================" | tee -a $OUTFILE


# -------------------------------------------------------------
# 1. Network Configuration
# -------------------------------------------------------------
echo "\n[1] Network Configuration (AIX)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
ifconfig -a | tee -a $OUTFILE
lsattr -El $LOCAL_INTERFACE | tee -a $OUTFILE

# -------------------------------------------------------------
# 2. TCP Parameters
# -------------------------------------------------------------
echo "\n[2] TCP Parameters" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
no -a | grep -E "rfc1323|tcp_sendspace|tcp_recvspace|sb_max" | tee -a $OUTFILE

# -------------------------------------------------------------
# 3. TCP Retransmissions and Metrics
# -------------------------------------------------------------
echo "\n[3] TCP Retransmissions and Metrics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
netstat -s | grep -i retrans | tee -a $OUTFILE
netstat -p tcp | grep -i retrans | tee -a $OUTFILE
netstat -v $LOCAL_INTERFACE | grep -i "drop\|error\|fail" | tee -a $OUTFILE

# -------------------------------------------------------------
# 4. Traceroute to Database
# -------------------------------------------------------------
echo "\n[4] Traceroute to Database ($IP_DB_OCI)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
traceroute $IP_DB_OCI | tee -a $OUTFILE

# -------------------------------------------------------------
# 5. Ping Test
# -------------------------------------------------------------
echo "\n[5] Ping Test (20 packets)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
ping -c 20 $IP_DB_OCI | tee -a $OUTFILE

# -------------------------------------------------------------
# 6. Interface Statistics
# -------------------------------------------------------------
echo "\n[6] Interface Statistics ($LOCAL_INTERFACE)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
entstat -d $LOCAL_INTERFACE | tee -a $OUTFILE

# -------------------------------------------------------------
# 7. CPU Diagnostics
# -------------------------------------------------------------
echo "\n[7] CPU Diagnostics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "CPU Configuration:" | tee -a $OUTFILE
lsdev -Cc processor | tee -a $OUTFILE
echo "\nCPU Utilization (vmstat 1 10):" | tee -a $OUTFILE
vmstat 1 10 | tee -a $OUTFILE
echo "\nCPU Statistics (mpstat -a 1 5):" | tee -a $OUTFILE
mpstat -a 1 5 | tee -a $OUTFILE
echo "\nTop CPU Consuming Processes:" | tee -a $OUTFILE
ps aux | head -1 | tee -a $OUTFILE
ps aux | sort -rn -k 3 | head -20 | tee -a $OUTFILE
echo "\nLoad Averages:" | tee -a $OUTFILE
uptime | tee -a $OUTFILE

# -------------------------------------------------------------
# 8. Memory Diagnostics
# -------------------------------------------------------------
echo "\n[8] Memory Diagnostics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "Global Memory Summary:" | tee -a $OUTFILE
svmon -G | tee -a $OUTFILE
echo "\nMemory by Segment:" | tee -a $OUTFILE
svmon -P -t 10 | tee -a $OUTFILE
echo "\nPaging Space:" | tee -a $OUTFILE
lsps -a | tee -a $OUTFILE
lsps -s | tee -a $OUTFILE
echo "\nTop Memory Consuming Processes:" | tee -a $OUTFILE
ps aux | head -1 | tee -a $OUTFILE
ps aux | sort -rn -k 4 | head -20 | tee -a $OUTFILE

# -------------------------------------------------------------
# 9. Disk I/O Diagnostics
# -------------------------------------------------------------
echo "\n[9] Disk I/O Diagnostics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "Disk Statistics:" | tee -a $OUTFILE
iostat -D 1 5 | tee -a $OUTFILE
echo "\nFilesystem Usage:" | tee -a $OUTFILE
df -g | tee -a $OUTFILE
echo "\nInode Usage:" | tee -a $OUTFILE
df -i | tee -a $OUTFILE

# -------------------------------------------------------------
# 10. Network Connection State
# -------------------------------------------------------------
echo "\n[10] Network Connection Analysis" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "Established Connections:" | tee -a $OUTFILE
netstat -an | grep ESTABLISHED | wc -l | tee -a $OUTFILE
echo "\nConnection States Summary:" | tee -a $OUTFILE
netstat -an | awk '{print $6}' | sort | uniq -c | sort -rn | tee -a $OUTFILE
echo "\nConnections to Database ($IP_DB_OCI):" | tee -a $OUTFILE
netstat -an | grep $IP_DB_OCI | tee -a $OUTFILE

# -------------------------------------------------------------
# 11. System Error Logs
# -------------------------------------------------------------
echo "\n[11] System Error Logs" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "Recent Error Log Entries:" | tee -a $OUTFILE
errpt | head -50 | tee -a $OUTFILE
echo "\nSystem Uptime:" | tee -a $OUTFILE
uptime | tee -a $OUTFILE

# -------------------------------------------------------------
# 12. TCPDUMP - NETWORK PACKET CAPTURE
# -------------------------------------------------------------
echo "\n[12] Starting TCPDUMP (${TIME_TO_COLLECT_TCPDUMP} seconds)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "Capturing traffic to: $IP_DB_OCI:${DB_PORT}" | tee -a $OUTFILE
echo "Please wait ${TIME_TO_COLLECT_TCPDUMP} seconds..." | tee -a $OUTFILE

/usr/sbin/tcpdump -i $LOCAL_INTERFACE -s 0 -w $PCAPFILE "host $IP_DB_OCI and port ${DB_PORT}" &
TCPDUMP_PID=$!
sleep $TIME_TO_COLLECT_TCPDUMP
kill $TCPDUMP_PID 2>/dev/null

echo "TCPDUMP capture completed!" | tee -a $OUTFILE
echo "PCAP file saved at: $PCAPFILE" | tee -a $OUTFILE

# -------------------------------------------------------------
# 13. COMPLETION
# -------------------------------------------------------------
echo "\n[13] DIAGNOSTIC COMPLETE" | tee -a $OUTFILE
echo "========================================" | tee -a $OUTFILE
echo "Output log file: $OUTFILE" | tee -a $OUTFILE
echo "PCAP file: $PCAPFILE" | tee -a $OUTFILE
echo "" | tee -a $OUTFILE
echo "NEXT STEPS:" | tee -a $OUTFILE
echo "1. Send both files to your support team:" | tee -a $OUTFILE
echo "   - $OUTFILE" | tee -a $OUTFILE
echo "   - $PCAPFILE" | tee -a $OUTFILE
echo "2. The PCAP file can be analyzed with Wireshark" | tee -a $OUTFILE
echo "========================================" | tee -a $OUTFILE

exit 0
