# aix-diag

**AIX → OCI diagnostic helper script**

This repository contains a small diagnostic script for AIX systems that helps triage network latency and Oracle DB (OCI) connectivity issues by collecting network, TCP, interface, and PL/SQL timing information.

## What it does
- **Collects network config:** runs `ifconfig` and interface attributes for the specified network device.
- **Gathers TCP parameters and metrics:** uses `no -a`, `netstat`, and other commands to show retransmissions and socket buffer settings.
- **Performs connectivity checks:** runs `traceroute` and `ping` toward the target Oracle DB IP.
- **Captures a short tcpdump:** records traffic on the specified database port to a `pcap` file for offline analysis (duration and port both configurable).
- **Executes PL/SQL / SQL script (optional):** runs the provided SQL file via `sqlplus` (if available) while measuring timings.
- **CPU diagnostics:** collects comprehensive CPU metrics including configuration, utilization, per-processor statistics, top consumers, load averages, and scheduler statistics.
- **Memory diagnostics:** gathers detailed memory information including global summary, segment usage, paging space, page faults, and top memory consumers.
- **Disk I/O diagnostics:** analyzes disk performance with iostat, filesystem usage, inode usage, LVM configuration, and I/O-intensive processes.
- **Process analysis:** monitors process count, zombie processes, Oracle processes, and blocked/waiting processes.
- **Kernel parameters:** captures network, virtual memory, and I/O tunable parameters plus system limits.
- **System health checks:** reviews error logs, hardware errors, uptime, and boot time.
- **Network connection state:** analyzes established connections, connection states, and socket buffer statistics.

## Files
- `diagnose_oci_latency.sh`: Main diagnostic script.

## Requirements
- **Shell:** The script uses `ksh` (`#!/bin/ksh`) but works on systems with Bourne-like shells if `ksh` is available.
- **Permissions:** Must be run with a user that can execute `tcpdump` and network commands; `root` is usually required for `tcpdump` and some interface diagnostics.
- **Optional tools:** `sqlplus` (for PL/SQL execution), `tcpdump`, `traceroute`, `ping`, `entstat`, `svmon`, `vmstat`, `mpstat`, `iostat`, `lsdev`, `lsattr`, `lsvg`, `errpt`.
- **Note:** Since DPI (Deep Packet Inspection) is being removed from environments, this script provides comprehensive system-level diagnostics to compensate for reduced network visibility.

## Usage
```
./diagnose_oci_latency.sh <IP_DB_OCI> <INTERFACE> <TNS_ALIAS> [SQL_FILE] [TCPDUMP_SECONDS] [DB_PORT]
```

### Examples
```
# Full run with SQL, 2-minute tcpdump, and custom port
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1 /tmp/test.sql 120 1522

# Run without SQL and use 30s tcpdump (default port 1521)
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1 30

# Run with custom port, no SQL, default duration (60s)
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1 1522

# Run with default tcpdump duration (60s), default port (1521), and no SQL
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1
```

### Notes
- `<IP_DB_OCI>`: IP address of the Oracle DB / OCI endpoint.
- `<INTERFACE>`: AIX network interface name (for example `ent0`).
- `<TNS_ALIAS>`: TNS alias configured in `tnsnames.ora` used by `sqlplus`.
- `[SQL_FILE]`: Optional path to a SQL/PLSQL script to run. If omitted or if you pass `/dev/null`, the script will skip PL/SQL execution and only perform network diagnostics.
- `[TCPDUMP_SECONDS]`: Optional integer seconds to run tcpdump (default: `60`). You can provide this either as the 4th argument (when skipping SQL) or the 5th argument (when providing a SQL file).
- `[DB_PORT]`: Optional database port (default: `1521`). Use this when your Oracle DB listens on a non-standard port. If you specify a 4-5 digit number as the only optional argument after TNS_ALIAS with no SQL file, it's interpreted as a port; otherwise numeric args are interpreted as duration first, port last.

## Output
- The script creates a timestamped log file named `oci_diagnosis_<YYYYMMDD_HHMMSS>.log` in the working directory.
- It also creates a tcpdump capture at `/tmp/oci_tcpdump_<YYYYMMDD_HHMMSS>.pcap`.

## Troubleshooting & tips
- If `tcpdump` fails: confirm you have sufficient privileges (try `sudo` or run as `root`).
- If `sqlplus` is missing: install Oracle client tools or skip PL/SQL step by passing `/dev/null` as the `SQL_FILE`.
- If interface commands like `entstat` are not found: ensure the AIX networking tools are installed and that you're on AIX.
- To analyze the `pcap`: copy it to a workstation and open with Wireshark or use `tshark`.

## Security notice
- The script may capture sensitive network traffic (including DB traffic). Store and share the generated `pcap` and logs securely.

## Contributing
- Feel free to open issues or PRs to improve diagnostics, add more checks, or adapt for other UNIX variants.