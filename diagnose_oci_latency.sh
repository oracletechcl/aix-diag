#!/bin/ksh

# ============================================================================
# AIX OS DIAGNOSTICS AND NETWORK CAPTURE SCRIPT
# ============================================================================
# *** IMPORTANT: YOU MUST RUN THIS SCRIPT AS ROOT ***
#
# USAGE (USE FLAGS TO AVOID CONFUSION):
#   sudo ./diagnose_oci_latency.sh --db-ip <IP> --interface <INTERFACE> --db-port <PORT> --time <SECONDS>
#
# EXAMPLE:
#   sudo ./diagnose_oci_latency.sh --db-ip 100.112.1.74 --interface ent0 --db-port 1521 --time 60
#
# WHAT EACH FLAG MEANS:
#   --db-ip       = The IP address of your Oracle database (example: 100.112.1.74)
#   --interface   = Your network interface (example: ent0)
#   --db-port     = The database port number (usually 1521)
#   --time        = How many seconds to capture network traffic (example: 60)
#
# ============================================================================

# Function to show usage
show_usage() {
    echo ""
    echo "========================================================"
    echo "AIX OS DIAGNOSTICS AND NETWORK CAPTURE SCRIPT"
    echo "========================================================"
    echo ""
    echo "*** IMPORTANT: RUN THIS SCRIPT AS ROOT ***"
    echo ""
    echo "USAGE:"
    echo "  sudo $0 --db-ip <IP> --interface <INTERFACE> --db-port <PORT> --time <SECONDS>"
    echo ""
    echo "EXAMPLE:"
    echo "  sudo $0 --db-ip 100.112.1.74 --interface ent0 --db-port 1521 --time 60"
    echo ""
    echo "WHAT EACH FLAG MEANS:"
    echo "  --db-ip       = The IP address of your Oracle database"
    echo "  --interface   = Your network interface (usually ent0)"
    echo "  --db-port     = The database port (usually 1521)"
    echo "  --time        = How many SECONDS to capture traffic (60 = 1 minute, 120 = 2 minutes)"
    echo ""
    echo "========================================================"
    echo ""
    exit 1
}

# Initialize variables
IP_DB_OCI=""
LOCAL_INTERFACE=""
DB_PORT=""
TIME_TO_COLLECT_TCPDUMP=""

# Parse command line arguments with flags
while [ $# -gt 0 ]; do
    case "$1" in
        --db-ip)
            IP_DB_OCI="$2"
            shift 2
            ;;
        --interface)
            LOCAL_INTERFACE="$2"
            shift 2
            ;;
        --db-port)
            DB_PORT="$2"
            shift 2
            ;;
        --time)
            TIME_TO_COLLECT_TCPDUMP="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "ERROR: Unknown parameter: $1"
            show_usage
            ;;
    esac
done

# Validate that all required parameters were provided
if [ -z "$IP_DB_OCI" ] || [ -z "$LOCAL_INTERFACE" ] || [ -z "$DB_PORT" ] || [ -z "$TIME_TO_COLLECT_TCPDUMP" ]; then
    echo ""
    echo "ERROR: Missing required parameters!"
    echo ""
    if [ -z "$IP_DB_OCI" ]; then
        echo "  Missing: --db-ip (Database IP address)"
    fi
    if [ -z "$LOCAL_INTERFACE" ]; then
        echo "  Missing: --interface (Network interface)"
    fi
    if [ -z "$DB_PORT" ]; then
        echo "  Missing: --db-port (Database port)"
    fi
    if [ -z "$TIME_TO_COLLECT_TCPDUMP" ]; then
        echo "  Missing: --time (Capture duration in seconds)"
    fi
    show_usage
fi

# Validate DB_PORT is a number between 1 and 65535
if ! echo "$DB_PORT" | grep -Eq '^[0-9]+$' || [ "$DB_PORT" -lt 1 ] || [ "$DB_PORT" -gt 65535 ]; then
    echo ""
    echo "ERROR: --db-port must be a valid port number (1-65535)"
    echo "You provided: $DB_PORT"
    echo ""
    echo "Common database ports:"
    echo "  1521 = Oracle default port"
    echo "  1522, 1523, etc. = Custom Oracle ports"
    echo ""
    exit 1
fi

# Validate TIME is a reasonable number (1-7200 seconds = max 2 hours)
if ! echo "$TIME_TO_COLLECT_TCPDUMP" | grep -Eq '^[0-9]+$' || [ "$TIME_TO_COLLECT_TCPDUMP" -lt 1 ] || [ "$TIME_TO_COLLECT_TCPDUMP" -gt 7200 ]; then
    echo ""
    echo "ERROR: --time must be between 1 and 7200 seconds (max 2 hours)"
    echo "You provided: $TIME_TO_COLLECT_TCPDUMP"
    echo ""
    echo "Common values:"
    echo "  60   = 1 minute"
    echo "  120  = 2 minutes"
    echo "  300  = 5 minutes"
    echo "  600  = 10 minutes"
    echo ""
    exit 1
fi

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

# Check if tcpdump exists
if [ ! -x "/usr/sbin/tcpdump" ]; then
    echo "ERROR: tcpdump not found at /usr/sbin/tcpdump" | tee -a $OUTFILE
    echo "ERROR: Please run this script as root or with sudo" | tee -a $OUTFILE
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "WARNING: You are not running as root!" | tee -a $OUTFILE
    echo "WARNING: tcpdump will likely FAIL without root privileges" | tee -a $OUTFILE
    echo "WARNING: Please run: sudo $0 $*" | tee -a $OUTFILE
    echo "" | tee -a $OUTFILE
fi

echo "Starting tcpdump... Please wait ${TIME_TO_COLLECT_TCPDUMP} seconds..." | tee -a $OUTFILE

# Start tcpdump in background and capture any errors
/usr/sbin/tcpdump -i $LOCAL_INTERFACE -s 0 -w $PCAPFILE "host $IP_DB_OCI and port ${DB_PORT}" > /tmp/tcpdump_error.$$.log 2>&1 &
TCPDUMP_PID=$!

# Wait a moment and check if tcpdump is still running
sleep 2
if ! ps -p $TCPDUMP_PID > /dev/null 2>&1; then
    echo "ERROR: tcpdump failed to start!" | tee -a $OUTFILE
    echo "ERROR: Check error log below:" | tee -a $OUTFILE
    cat /tmp/tcpdump_error.$$.log | tee -a $OUTFILE
    rm -f /tmp/tcpdump_error.$$.log
    exit 1
fi

echo "tcpdump is running (PID: $TCPDUMP_PID)" | tee -a $OUTFILE

# Wait for the specified duration
sleep $TIME_TO_COLLECT_TCPDUMP

# Send proper termination signal and WAIT for tcpdump to finish writing
echo "Stopping tcpdump and flushing buffers..." | tee -a $OUTFILE
kill -TERM $TCPDUMP_PID 2>/dev/null
wait $TCPDUMP_PID 2>/dev/null

# Clean up error log if no errors
rm -f /tmp/tcpdump_error.$$.log

# Verify the PCAP file was created
if [ -f "$PCAPFILE" ]; then
    PCAP_SIZE=$(ls -lh "$PCAPFILE" | awk '{print $5}')
    echo "SUCCESS: TCPDUMP capture completed!" | tee -a $OUTFILE
    echo "PCAP file saved at: $PCAPFILE (Size: $PCAP_SIZE)" | tee -a $OUTFILE
else
    echo "ERROR: PCAP file was NOT created at $PCAPFILE" | tee -a $OUTFILE
    echo "ERROR: tcpdump may have failed. Check permissions and interface name." | tee -a $OUTFILE
fi

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
