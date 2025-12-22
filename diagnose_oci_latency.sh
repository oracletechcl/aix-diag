#!/bin/ksh

# -------------------------------------------------------------
# AIX → OCI DEEP DIAGNOSTIC SCRIPT (with PL/SQL Execution)
# -------------------------------------------------------------
# Usage:
#   ./diagnose_oci_latency.sh <IP_DB_OCI> <INTERFACE> <TNS_ALIAS> <SQL_FILE>
# Example:
#   ./diagnose_oci_latency.sh 10.50.20.15 ent0 PRODDB /tmp/test.sql
# -------------------------------------------------------------

if [ $# -lt 3 ] || [ $# -gt 6 ]; then
    echo "Uso: $0 <IP_DB_OCI> <INTERFACE> <TNS_ALIAS> [SQL_FILE] [TCPDUMP_SECONDS] [DB_PORT]"
    echo "Ejemplo (con SQL, duración y puerto): $0 10.50.20.15 ent0 ORCL_PDB1 /tmp/test.sql 120 1521"
    echo "Ejemplo (solo duración, sin SQL): $0 10.50.20.15 ent0 ORCL_PDB1 120"
    echo "Ejemplo (con puerto personalizado, sin SQL): $0 10.50.20.15 ent0 ORCL_PDB1 1522"
    echo "Ejemplo (sin SQL y valores por defecto 60s, puerto 1521): $0 10.50.20.15 ent0 ORCL_PDB1"
    exit 1
fi

DBIP=$1
IFACE=$2
DBALIAS=$3
SQLFILE=
# default values
DURATION=60
DBPORT=1521

# Interpret optional 4th, 5th and 6th args. Support multiple forms:
# 1) <...> <TNS_ALIAS> <SQL_FILE> <TCPDUMP_SECONDS> <DB_PORT>
# 2) <...> <TNS_ALIAS> <TCPDUMP_SECONDS> <DB_PORT>  (no SQL file)
# 3) <...> <TNS_ALIAS> <TCPDUMP_SECONDS>  (no SQL file, default port)
# 4) <...> <TNS_ALIAS> <DB_PORT>  (no SQL file, default duration)
if [ $# -ge 4 ]; then
    arg4="$4"
    if echo "$arg4" | grep -Eq '^[0-9]+$'; then
        # 4th arg is numeric -> could be duration or port, we'll decide later
        DURATION=$arg4
    else
        # 4th arg is a file path
        SQLFILE=$arg4
    fi
fi

if [ $# -ge 5 ]; then
    arg5="$5"
    if echo "$arg5" | grep -Eq '^[0-9]+$'; then
        # 5th arg is numeric
        if [ -n "$SQLFILE" ]; then
            # If we have a SQL file, 5th arg is duration
            DURATION=$arg5
        else
            # If no SQL file, 5th arg could be duration or port; assume duration if first numeric
            DURATION=$arg5
        fi
    fi
fi

if [ $# -ge 6 ]; then
    arg6="$6"
    if echo "$arg6" | grep -Eq '^[0-9]+$'; then
        # 6th arg is always port
        DBPORT=$arg6
    else
        echo "Aviso: sexto argumento no es numérico, usando puerto por defecto ${DBPORT}"
    fi
fi

# If we only have 4 numeric args and no SQL file, treat the last one as port
if [ $# -eq 4 ] && [ -z "$SQLFILE" ] && echo "$4" | grep -Eq '^[0-9]{4,5}$'; then
    DBPORT=$4
    DURATION=60
fi

# Decide whether to run PL/SQL execution. Treat empty or /dev/null as "no".
RUN_SQL=0
if [ -n "$SQLFILE" ] && [ "$SQLFILE" != "/dev/null" ]; then
    RUN_SQL=1
fi

OUTFILE="oci_diagnosis_$(date +%Y%m%d_%H%M%S).log"
PCAPFILE="/tmp/oci_tcpdump_$(date +%Y%m%d_%H%M%S).pcap"

echo "===================================================" | tee -a $OUTFILE
echo "AIX → OCI Diagnostic Script (with PL/SQL Triage)" | tee -a $OUTFILE
echo "Fecha: $(date)" | tee -a $OUTFILE
echo "IP DB OCI: $DBIP" | tee -a $OUTFILE
echo "Interfaz: $IFACE" | tee -a $OUTFILE
echo "TNS Alias: $DBALIAS" | tee -a $OUTFILE
if [ -n "$SQLFILE" ]; then
    echo "SQL File: $SQLFILE" | tee -a $OUTFILE
else
    echo "SQL File: (none) — PL/SQL execution will be skipped" | tee -a $OUTFILE
fi
echo "Tcpdump duration: ${DURATION}s" | tee -a $OUTFILE
echo "Database Port: ${DBPORT}" | tee -a $OUTFILE
echo "===================================================" | tee -a $OUTFILE


# -------------------------------------------------------------
# 1. Mostrar configuración de red
# -------------------------------------------------------------
echo "\n[1] Configuración de red AIX" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
ifconfig -a | tee -a $OUTFILE
lsattr -El $IFACE | tee -a $OUTFILE

# -------------------------------------------------------------
# 2. Mostrar parámetros TCP críticos
# -------------------------------------------------------------
echo "\n[2] Parámetros TCP actuales" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
no -a | grep -E "rfc1323|tcp_sendspace|tcp_recvspace|sb_max" | tee -a $OUTFILE

# -------------------------------------------------------------
# 3. Revisar retransmisiones TCP
# -------------------------------------------------------------
echo "\n[3] Métricas TCP (retransmisiones, colas)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
netstat -s | grep -i retrans | tee -a $OUTFILE
netstat -p tcp | grep -i retrans | tee -a $OUTFILE
netstat -v $IFACE | grep -i "drop\|error\|fail" | tee -a $OUTFILE

# -------------------------------------------------------------
# 4. Traceroute hacia OCI
# -------------------------------------------------------------
echo "\n[4] Traceroute hacia DB OCI ($DBIP)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
traceroute $DBIP | tee -a $OUTFILE

# -------------------------------------------------------------
# 5. Ping extendido
# -------------------------------------------------------------
echo "\n[5] Ping extendido (20 paquetes)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
ping -c 20 $DBIP | tee -a $OUTFILE

# -------------------------------------------------------------
# 6. SQLNet handshake test (sqlplus)
# -------------------------------------------------------------
if command -v sqlplus >/dev/null 2>&1; then
    echo "\n[6] SQL*Net handshake (sqlplus test)" | tee -a $OUTFILE
    echo "----------------------------------------" | tee -a $OUTFILE
    # Use the TNS alias to attempt a lightweight connect and simple query
    sqlplus -s /nolog <<EOF | tee -a $OUTFILE
conn /@${DBALIAS}
set timing on;
select 1 from dual;
exit;
EOF
else
    echo "\n[6] SQLNet: sqlplus no está instalado." | tee -a $OUTFILE
fi

# -------------------------------------------------------------
# 7. Estadísticas de interfaz AIX
# -------------------------------------------------------------
echo "\n[7] Estadísticas de la interfaz ($IFACE)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
entstat -d $IFACE | tee -a $OUTFILE

# -------------------------------------------------------------
# 8. CPU Diagnostics (Detailed)
# -------------------------------------------------------------
echo "\n[8] CPU Diagnostics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "8.1) CPU configuration:" | tee -a $OUTFILE
lsdev -Cc processor | tee -a $OUTFILE
lsattr -El proc0 | tee -a $OUTFILE
echo "\n8.2) CPU utilization (vmstat 1 10):" | tee -a $OUTFILE
vmstat 1 10 | tee -a $OUTFILE
echo "\n8.3) CPU statistics per processor:" | tee -a $OUTFILE
mpstat -a 1 5 | tee -a $OUTFILE
echo "\n8.4) Process-level CPU consumers (top 20):" | tee -a $OUTFILE
ps aux | head -1 | tee -a $OUTFILE
ps aux | sort -rn -k 3 | head -20 | tee -a $OUTFILE
echo "\n8.5) Load averages and run queue:" | tee -a $OUTFILE
uptime | tee -a $OUTFILE
echo "\n8.6) Scheduler statistics:" | tee -a $OUTFILE
vmstat -s | grep -E "context switch|forks|interrupts" | tee -a $OUTFILE

# -------------------------------------------------------------
# 9. Memory Diagnostics (Detailed)
# -------------------------------------------------------------
echo "\n[9] Memory Diagnostics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "9.1) Global memory summary (svmon -G):" | tee -a $OUTFILE
svmon -G | tee -a $OUTFILE
echo "\n9.2) Memory by segment (svmon -P -t 10):" | tee -a $OUTFILE
svmon -P -t 10 | tee -a $OUTFILE
echo "\n9.3) Paging space utilization:" | tee -a $OUTFILE
lsps -a | tee -a $OUTFILE
lsps -s | tee -a $OUTFILE
echo "\n9.4) Page faults and I/O statistics:" | tee -a $OUTFILE
vmstat -s | grep -E "page fault|paging|reclaims" | tee -a $OUTFILE
echo "\n9.5) Top memory consuming processes (top 20):" | tee -a $OUTFILE
ps aux | head -1 | tee -a $OUTFILE
ps aux | sort -rn -k 4 | head -20 | tee -a $OUTFILE
echo "\n9.6) Detailed process memory usage:" | tee -a $OUTFILE
svmon -Pu -t 10 | tee -a $OUTFILE

# -------------------------------------------------------------
# 10. Disk I/O Diagnostics
# -------------------------------------------------------------
echo "\n[10] Disk I/O Diagnostics" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "10.1) Disk statistics (iostat):" | tee -a $OUTFILE
iostat -D 1 5 | tee -a $OUTFILE
echo "\n10.2) Detailed disk adapter statistics:" | tee -a $OUTFILE
iostat -A 1 5 | tee -a $OUTFILE
echo "\n10.3) Filesystem usage:" | tee -a $OUTFILE
df -g | tee -a $OUTFILE
echo "\n10.4) Inode usage:" | tee -a $OUTFILE
df -i | tee -a $OUTFILE
echo "\n10.5) LVM information:" | tee -a $OUTFILE
lsvg | tee -a $OUTFILE
for vg in $(lsvg); do
    echo "\nVolume Group: $vg" | tee -a $OUTFILE
    lsvg $vg | tee -a $OUTFILE
done
echo "\n10.6) Top I/O consuming processes:" | tee -a $OUTFILE
ps aux | head -1 | tee -a $OUTFILE
ps gv | sort -rn -k 10 | head -20 | tee -a $OUTFILE

# -------------------------------------------------------------
# 11. Process and Thread Analysis
# -------------------------------------------------------------
echo "\n[11] Process and Thread Analysis" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "11.1) Process count:" | tee -a $OUTFILE
ps -ef | wc -l | tee -a $OUTFILE
echo "\n11.2) Zombie processes:" | tee -a $OUTFILE
ps -ef | grep defunct | grep -v grep | tee -a $OUTFILE
echo "\n11.3) Oracle processes (if any):" | tee -a $OUTFILE
ps -ef | grep -i oracle | grep -v grep | tee -a $OUTFILE
echo "\n11.4) Waiting/blocked processes:" | tee -a $OUTFILE
ps -efl | grep -E " [DUSZ] " | head -20 | tee -a $OUTFILE

# -------------------------------------------------------------
# 12. System Kernel Parameters
# -------------------------------------------------------------
echo "\n[12] Kernel Parameters and Limits" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "12.1) Network tunable parameters:" | tee -a $OUTFILE
no -a | tee -a $OUTFILE
echo "\n12.2) Virtual Memory Manager parameters:" | tee -a $OUTFILE
vmo -a | tee -a $OUTFILE
echo "\n12.3) I/O tunable parameters:" | tee -a $OUTFILE
ioo -a | tee -a $OUTFILE
echo "\n12.4) System limits (ulimit):" | tee -a $OUTFILE
ulimit -a | tee -a $OUTFILE

# -------------------------------------------------------------
# 13. Error Logs and System Health
# -------------------------------------------------------------
echo "\n[13] System Error Logs and Health" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "13.1) Recent error log entries:" | tee -a $OUTFILE
errpt | head -50 | tee -a $OUTFILE
echo "\n13.2) Hardware errors (last 24 hours):" | tee -a $OUTFILE
errpt -a -s $(date -v -1d +%m%d%H%M%y 2>/dev/null || date --date="1 day ago" +%m%d%H%M%y 2>/dev/null || echo "010100001970") | grep -i "hardware\|memory\|cpu\|disk" | head -30 | tee -a $OUTFILE
echo "\n13.3) System uptime and boot time:" | tee -a $OUTFILE
uptime | tee -a $OUTFILE
who -b | tee -a $OUTFILE

# -------------------------------------------------------------
# 14. Network Connection State
# -------------------------------------------------------------
echo "\n[14] Network Connection Analysis" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
echo "14.1) Established connections:" | tee -a $OUTFILE
netstat -an | grep ESTABLISHED | wc -l | tee -a $OUTFILE
echo "\n14.2) Connection states summary:" | tee -a $OUTFILE
netstat -an | awk '{print $6}' | sort | uniq -c | sort -rn | tee -a $OUTFILE
echo "\n14.3) Connections to OCI database:" | tee -a $OUTFILE
netstat -an | grep $DBIP | tee -a $OUTFILE
echo "\n14.4) Socket buffer statistics:" | tee -a $OUTFILE
netstat -m | tee -a $OUTFILE

# -------------------------------------------------------------
# 15. Iniciar tcpdump filtrado
# -------------------------------------------------------------
echo "\n[15] Iniciando tcpdump ${DURATION}s hacia DB OCI ($DBIP:${DBPORT})" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE

/usr/sbin/tcpdump -i $IFACE -s 0 -w $PCAPFILE "host $DBIP and port ${DBPORT}" &
TCPDUMP_PID=$!
sleep $DURATION
kill $TCPDUMP_PID

echo "\nTcpdump almacenado en: $PCAPFILE" | tee -a $OUTFILE


# -------------------------------------------------------------
# 16. Ejecutar PL/SQL o query para triage (con timing)
# -------------------------------------------------------------
echo "\n[16] Ejecutando PL/SQL / SQL para medición real" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE

if [ "$RUN_SQL" -eq 1 ]; then
    if command -v sqlplus >/dev/null 2>&1; then
        echo "Ejecutando: $SQLFILE" | tee -a $OUTFILE

        sqlplus -s /nolog <<EOF | tee -a $OUTFILE
conn /@${DBALIAS}
set timing on;
set serveroutput on;
@$SQLFILE
exit;
EOF

    else
        echo "sqlplus no instalado. No se puede ejecutar el PL/SQL." | tee -a $OUTFILE
    fi
else
    echo "PL/SQL execution skipped (no SQL file provided)." | tee -a $OUTFILE
fi


# -------------------------------------------------------------
# 17. Finalización
# -------------------------------------------------------------
echo "\n[17] FIN DEL DIAGNÓSTICO" | tee -a $OUTFILE
echo "Archivo de salida: $OUTFILE" | tee -a $OUTFILE
echo "PCAP capturado: $PCAPFILE" | tee -a $OUTFILE
echo "Listo para análisis con Wireshark + AWR." | tee -a $OUTFILE

exit 0
