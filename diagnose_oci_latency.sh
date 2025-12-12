#!/bin/ksh

# -------------------------------------------------------------
# AIX → OCI DEEP DIAGNOSTIC SCRIPT (with PL/SQL Execution)
# -------------------------------------------------------------
# Usage:
#   ./diagnose_oci_latency.sh <IP_DB_OCI> <INTERFACE> <TNS_ALIAS> <SQL_FILE>
# Example:
#   ./diagnose_oci_latency.sh 10.50.20.15 ent0 PRODDB /tmp/test.sql
# -------------------------------------------------------------

if [ $# -ne 4 ]; then
    echo "Uso: $0 <IP_DB_OCI> <INTERFACE> <TNS_ALIAS> <SQL_FILE>"
    echo "Ejemplo: $0 10.50.20.15 ent0 ORCL_PDB1 /tmp/test.sql"
    exit 1
fi

DBIP=$1
IFACE=$2
DBALIAS=$3
SQLFILE=$4

OUTFILE="oci_diagnosis_$(date +%Y%m%d_%H%M%S).log"
PCAPFILE="/tmp/oci_tcpdump_$(date +%Y%m%d_%H%M%S).pcap"

echo "===================================================" | tee -a $OUTFILE
echo "AIX → OCI Diagnostic Script (with PL/SQL Triage)" | tee -a $OUTFILE
echo "Fecha: $(date)" | tee -a $OUTFILE
echo "IP DB OCI: $DBIP" | tee -a $OUTFILE
echo "Interfaz: $IFACE" | tee -a $OUTFILE
echo "TNS Alias: $DBALIAS" | tee -a $OUTFILE
echo "SQL File: $SQLFILE" | tee -a $OUTFILE
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
    echo "set timing on; select 1 from dual;" | sqlplus -s /nolog | tee -a $OUTFILE
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
# 8. CPU y memoria general
# -------------------------------------------------------------
echo "\n[8] Utilización del sistema (CPU, memoria)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE
vmstat 1 5 | tee -a $OUTFILE
svmon -G | tee -a $OUTFILE

# -------------------------------------------------------------
# 9. Iniciar tcpdump filtrado (60s)
# -------------------------------------------------------------
echo "\n[9] Iniciando tcpdump 60s hacia DB OCI ($DBIP:1521)" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE

/usr/sbin/tcpdump -i $IFACE -s 0 -w $PCAPFILE "host $DBIP and port 1521" &
TCPDUMP_PID=$!
sleep 60
kill $TCPDUMP_PID

echo "\nTcpdump almacenado en: $PCAPFILE" | tee -a $OUTFILE


# -------------------------------------------------------------
# 10. Ejecutar PL/SQL o query para triage (con timing)
# -------------------------------------------------------------
echo "\n[10] Ejecutando PL/SQL / SQL para medición real" | tee -a $OUTFILE
echo "----------------------------------------" | tee -a $OUTFILE

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


# -------------------------------------------------------------
# 11. Finalización
# -------------------------------------------------------------
echo "\n[11] FIN DEL DIAGNÓSTICO" | tee -a $OUTFILE
echo "Archivo de salida: $OUTFILE" | tee -a $OUTFILE
echo "PCAP capturado: $PCAPFILE" | tee -a $OUTFILE
echo "Listo para análisis con Wireshark + AWR." | tee -a $OUTFILE

exit 0
