# aix-diag

**AIX → OCI diagnostic helper script**

This repository contains a small diagnostic script for AIX systems that helps triage network latency and Oracle DB (OCI) connectivity issues by collecting network, TCP, interface, and PL/SQL timing information.

**What it does**
- **Collects network config:** runs `ifconfig` and interface attributes for the specified network device.
- **Gathers TCP parameters and metrics:** uses `no -a`, `netstat`, and other commands to show retransmissions and socket buffer settings.
- **Performs connectivity checks:** runs `traceroute` and `ping` toward the target Oracle DB IP.
- **Captures a short tcpdump:** records 60 seconds of traffic on port `1521` to a `pcap` file for offline analysis.
- **Executes PL/SQL / SQL script (optional):** runs the provided SQL file via `sqlplus` (if available) while measuring timings.

**Files**
- `diagnose_oci_latency.sh`: Main diagnostic script.

**Requirements**
- **Shell:** The script uses `ksh` (`#!/bin/ksh`) but works on systems with Bourne-like shells if `ksh` is available.
- **Permissions:** Must be run with a user that can execute `tcpdump` and network commands; `root` is usually required for `tcpdump` and some interface diagnostics.
- **Optional tools:** `sqlplus` (for PL/SQL execution), `tcpdump`, `traceroute`, `ping`, `entstat`, `svmon`, `vmstat`.

**Usage**
```
./diagnose_oci_latency.sh <IP_DB_OCI> <INTERFACE> <TNS_ALIAS> <SQL_FILE>
```

Example:
```
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1 /tmp/test.sql
```

Notes:
- `<IP_DB_OCI>`: IP address of the Oracle DB / OCI endpoint.
- `<INTERFACE>`: AIX network interface name (for example `ent0`).
- `<TNS_ALIAS>`: TNS alias configured in `tnsnames.ora` used by `sqlplus`.
- `<SQL_FILE>`: Path to a SQL/PLSQL script to run (optional for timing tests; must be readable).

**Output**
- The script creates a timestamped log file named `oci_diagnosis_<YYYYMMDD_HHMMSS>.log` in the working directory.
- It also creates a tcpdump capture at `/tmp/oci_tcpdump_<YYYYMMDD_HHMMSS>.pcap`.

**Examples**
- Quick run (no PL/SQL execution):
```
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1 /dev/null
```
- Full run with SQL file:
```
./diagnose_oci_latency.sh 10.50.20.15 ent0 ORCL_PDB1 /tmp/test.sql
```

**Troubleshooting & tips**
- If `tcpdump` fails: confirm you have sufficient privileges (try `sudo` or run as `root`).
- If `sqlplus` is missing: install Oracle client tools or skip PL/SQL step by passing `/dev/null` as the `SQL_FILE`.
- If interface commands like `entstat` are not found: ensure the AIX networking tools are installed and that you're on AIX.
- To analyze the `pcap`: copy it to a workstation and open with Wireshark or use `tshark`.

**Security notice**
- The script may capture sensitive network traffic (including DB traffic). Store and share the generated `pcap` and logs securely.

**Contributing**
- Feel free to open issues or PRs to improve diagnostics, add more checks, or adapt for other UNIX variants.

**License**
- No license specified. Add a `LICENSE` file if you want to clarify reuse terms.

--
Generated: `diagnose_oci_latency.sh` documentation
# aix-diag