# AIX OS Diagnostics and Network Capture Script

## What This Script Does

This script collects OS diagnostics from your AIX system and captures network traffic (TCPDUMP) to/from an Oracle database. It's designed to be **extremely simple to use** - just copy and paste the command with your values.

## How to Use (STEP BY STEP)

### Step 1: Get Your Information Ready

You need 4 pieces of information:

1. **IP_DB_OCI**: The IP address of your Oracle database
   - Example: `10.50.20.15`
   - Ask your DBA if you don't know this

2. **LOCAL_INTERFACE**: Your network interface name
   - Usually this is `ent0`
   - To find it, run: `ifconfig -a` and look for your active interface

3. **DB_PORT**: The database port number
   - Usually this is `1521`
   - Ask your DBA if it's different

4. **TIME_TO_COLLECT_TCPDUMP**: How many seconds to capture network traffic
   - Use `60` for 1 minute
   - Use `120` for 2 minutes
   - Use `300` for 5 minutes

### Step 2: Run the Script

Copy and paste this command, replacing the example values with your own:

```bash
./diagnose_oci_latency.sh 10.50.20.15 ent0 1521 180
```

**Replace:**
- `10.50.20.15` with your database IP
- `ent0` with your network interface
- `1521` with your database port
- `180` with how many seconds you want to capture

### Step 3: Wait

The script will run and collect:
- Network configuration
- TCP parameters and statistics
- Traceroute and ping tests
- CPU diagnostics
- Memory diagnostics
- Disk I/O statistics
- Network connections
- System error logs
- Network packet capture (TCPDUMP)

### Step 4: Get the Files

When complete, you'll see:
```
Output log file: oci_diagnosis_YYYYMMDD_HHMMSS.log
PCAP file: /tmp/oci_tcpdump_YYYYMMDD_HHMMSS.pcap
```

Send **BOTH files** to your support team.

## Full Example

```bash
# Example 1: Capture for 60 seconds to database 10.50.20.15 on port 1521 using ent0 interface
./diagnose_oci_latency.sh 10.50.20.15 ent0 1521 60

# Example 2: Capture for 2 minutes to database 192.168.1.100 on port 1522 using ent1 interface
./diagnose_oci_latency.sh 192.168.1.100 ent1 1522 120
```

## What If I Get an Error?

If you see:
```
ERROR: You must provide exactly 4 parameters!
```

It means you didn't provide all 4 required values. Make sure you have:
1. Database IP
2. Network interface of AIX machine where communication is circulating
3. Database port
4. Time in seconds

## Need Help?

Just run the script without any parameters to see the help:
```bash
./diagnose_oci_latency.sh
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
