#!/bin/bash

TARGET=$1
OUTPUT_DIR="recon_$TARGET"

mkdir -p $OUTPUT_DIR

echo "[*] Starting Recon on $TARGET"
echo "================================="

# Check if host is alive
echo "[+] Checking host..."
ping -c 1 $TARGET > /dev/null

if [ $? -ne 0 ]; then
    echo "[-] Host is down. Exiting."
    exit 1
fi

echo "[+] Host is UP"

#  Nmap scan
echo "[+] Running Nmap scan..."
nmap -sS -sV -oN $OUTPUT_DIR/nmap.txt $TARGET

# Extract open ports
echo "[+] Extracting open ports..."
PORTS=$(grep open $OUTPUT_DIR/nmap.txt | cut -d '/' -f1 | tr '\n' ',' | sed 's/,$//')

echo "[+] Open ports: $PORTS"

# Check for HTTP services
if echo "$PORTS" | grep -E "80|443" > /dev/null; then
    
    echo "[+] Web service detected"

# Directory brute force
    echo "[+] Running Gobuster..."
    gobuster dir -u http://$TARGET -w /usr/share/wordlists/dirb/common.txt -o $OUTPUT_DIR/gobuster.txt

# Nikto scan
    echo "[+] Running Nikto..."
    nikto -h http://$TARGET -output $OUTPUT_DIR/nikto.txt
fi

echo "[+] Recon Completed. Results saved in $OUTPUT_DIR"     
