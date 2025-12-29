# AIX OS Diagnostics and Network Capture Script

## What This Script Does

This script collects OS diagnostics from your AIX system and captures network traffic (TCPDUMP) to/from an Oracle database. It's designed to be **extremely simple to use** with clear flags to avoid confusion.

## ⚠️ IMPORTANT: YOU MUST RUN AS ROOT

This script requires root privileges to run tcpdump. Use `sudo` or login as root first.

## How to Use (STEP BY STEP)

### Step 1: Get Your Information Ready

You need 4 pieces of information:

1. **Database IP Address**: The IP address of your Oracle database
   - Example: `100.112.1.74`
   - Ask your DBA if you don't know this

2. **Network Interface**: Your AIX network interface name
   - Usually this is `ent0`
   - To find it, run: `ifconfig -a` and look for your active interface

3. **Database Port**: The database port number
   - Usually this is `1521` (Oracle default)
   - Ask your DBA if it's different

4. **Capture Time**: How many SECONDS to capture network traffic
   - Use `60` for 1 minute
   - Use `120` for 2 minutes
   - Use `300` for 5 minutes
   - **WARNING: Don't confuse this with the port number!**

### Step 2: Run the Script WITH FLAGS

**RECOMMENDED METHOD (Using Flags - Foolproof):**

```bash
sudo ./diagnose_oci_latency.sh --db-ip 100.112.1.74 --interface ent0 --db-port 1521 --time 60
```

**Replace with your values:**
- `100.112.1.74` → Your database IP address
- `ent0` → Your network interface name
- `1521` → Your database port number
- `60` → How many seconds to capture (NOT the port!)

### Step 3: Wait for Completion

The script will:
1. Show you a summary of what it's doing
2. Run all diagnostic commands
3. Capture network traffic for the specified time
4. Create two output files

**DO NOT STOP THE SCRIPT WHILE IT'S RUNNING!** Wait for it to complete.

### Step 4: Get the Files

When complete, you'll see:
```
Output log file: oci_diagnosis_YYYYMMDD_HHMMSS.log
PCAP file: /tmp/oci_tcpdump_YYYYMMDD_HHMMSS.pcap
```

Send **BOTH files** to your support team.

## Complete Examples

```bash
# Example 1: Capture for 1 minute (60 seconds) to database 100.112.1.74 on port 1521
sudo ./diagnose_oci_latency.sh --db-ip 100.112.1.74 --interface ent0 --db-port 1521 --time 60

# Example 2: Capture for 2 minutes (120 seconds) to database on custom port 1522
sudo ./diagnose_oci_latency.sh --db-ip 192.168.1.100 --interface ent0 --db-port 1522 --time 120

# Example 3: Capture for 5 minutes (300 seconds) using interface ent1
sudo ./diagnose_oci_latency.sh --db-ip 10.0.0.50 --interface ent1 --db-port 1521 --time 300
```

## Common Mistakes to Avoid

❌ **WRONG - Swapping port and time:**
```bash
# This will try to capture for 1521 seconds (25+ minutes)!
sudo ./diagnose_oci_latency.sh --db-ip 100.112.1.74 --interface ent0 --db-port 60 --time 1521
```

✅ **CORRECT - Port is the database port, time is in seconds:**
```bash
sudo ./diagnose_oci_latency.sh --db-ip 100.112.1.74 --interface ent0 --db-port 1521 --time 60
```

## What If I Get an Error?

### "Missing required parameters"
You forgot one or more flags. Make sure you include all 4:
- `--db-ip`
- `--interface`
- `--db-port`
- `--time`

### "db-port must be a valid port number (1-65535)"
You provided an invalid port. Common ports:
- `1521` = Oracle default
- `1522`, `1523` = Common Oracle custom ports

### "time must be between 1 and 7200 seconds"
The capture time must be reasonable (max 2 hours). Common values:
- `60` = 1 minute
- `120` = 2 minutes
- `300` = 5 minutes

### "tcpdump not found" or "not running as root"
You must run the script with `sudo` or as root user.

## Need Help?

Run the script without parameters to see the help:
```bash
./diagnose_oci_latency.sh
```

Or use the help flag:
```bash
./diagnose_oci_latency.sh --help
```

## Requirements

- AIX operating system
- Root or sudo access (needed for tcpdump and system diagnostics)
- Network connectivity to the database

## What Gets Collected

The script collects:

1. **Network Configuration** - Your network interface settings
2. **TCP Parameters** - TCP tuning and buffer settings
3. **TCP Metrics** - Retransmissions, drops, and errors
4. **Traceroute** - Network path to the database
5. **Ping Test** - Basic connectivity and latency
6. **Interface Statistics** - Detailed network interface stats
7. **CPU Diagnostics** - CPU usage, load, and top processes
8. **Memory Diagnostics** - Memory usage, paging, and top consumers
9. **Disk I/O** - Disk performance and filesystem usage
10. **Network Connections** - Active connections to the database
11. **System Errors** - Recent system error logs
12. **TCPDUMP** - Raw network packet capture for detailed analysis

## Security Note

The PCAP file contains network traffic data. Handle it securely and only share it with authorized support personnel.
