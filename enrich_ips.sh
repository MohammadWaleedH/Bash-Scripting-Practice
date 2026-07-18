#!/usr/bin/env bash
#
# enrich_ips.sh
# -------------
# Purpose:
#   Scan a raw log file (nginx/apache/syslog/anything), pull out every
#   IPv4 address it can find, deduplicate them, and enrich each one with
#   GeoIP + ASN data (country, city, ISP, ASN/org) using the free
#   ip-api.com batch API. Outputs a clean CSV you can load into a SIEM,
#   spreadsheet, or feed into further analysis.
#
# Why this exists:
#   Raw logs give you an IP address and nothing else. To spot things like
#   "why is traffic suddenly coming from a datacenter ASN in another
#   country" you need geolocation + network ownership context attached
#   to every IP. This script automates that enrichment step.
#
# Requirements:
#   - bash 4+
#   - curl
#   - jq        (JSON parsing)
#
# Usage:
#   ./enrich_ips.sh -i access.log -o enriched.csv
#   ./enrich_ips.sh -i access.log -o enriched.csv -r 1.5   # slower rate, avoid API throttling
#   cat access.log | ./enrich_ips.sh -o enriched.csv       # read from stdin
#
# Notes on the API:
#   ip-api.com's free tier allows 45 requests/minute and up to 100 IPs
#   per batch request. This script batches IPs in groups of 100 and
#   sleeps between batches to stay under that limit. For production/
#   high-volume use, get an API key (ip-api.com Pro, ipinfo.io, etc.)
#   and swap the API call section accordingly.

set -euo pipefail

# ---------- defaults ----------
INPUT_FILE=""
OUTPUT_FILE="enriched_ips.csv"
RATE_DELAY=1.4      # seconds to sleep between batches (45 req/min free tier)
BATCH_SIZE=100       # ip-api.com batch endpoint max
API_URL="http://ip-api.com/batch"

usage() {
    cat <<EOF
Usage: $0 -i <logfile> [-o <output.csv>] [-r <rate_delay_seconds>]

  -i FILE   Input log file to scan for IPs (omit to read from stdin)
  -o FILE   Output CSV path (default: enriched_ips.csv)
  -r SEC    Delay between API batches in seconds (default: 1.4)
  -h        Show this help

Example:
  $0 -i /var/log/nginx/access.log -o report.csv
EOF
    exit 1
}

# ---------- parse args ----------
while getopts ":i:o:r:h" opt; do
    case "$opt" in
        i) INPUT_FILE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        r) RATE_DELAY="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ---------- dependency checks ----------
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' not found. Install it and retry." >&2
        exit 1
    fi
done

# ---------- step 1: extract & dedupe IPv4 addresses ----------
# Regex matches standard dotted-quad IPv4. It's intentionally simple
# (doesn't validate octet ranges 0-255 strictly) — good enough for log
# scraping; the API will just fail gracefully on anything malformed.
IP_REGEX='([0-9]{1,3}\.){3}[0-9]{1,3}'

echo "Extracting IPs..." >&2
if [[ -n "$INPUT_FILE" ]]; then
    [[ -f "$INPUT_FILE" ]] || { echo "Error: input file '$INPUT_FILE' not found." >&2; exit 1; }
    mapfile -t IPS < <(grep -oE "$IP_REGEX" "$INPUT_FILE" | sort -u)
else
    mapfile -t IPS < <(grep -oE "$IP_REGEX" | sort -u)
fi

# Filter out obviously private/reserved ranges (optional but usually desired,
# since geolocating your own internal traffic is meaningless noise).
is_private() {
    local ip="$1"
    [[ "$ip" =~ ^10\. ]] && return 0
    [[ "$ip" =~ ^192\.168\. ]] && return 0
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
    [[ "$ip" =~ ^127\. ]] && return 0
    [[ "$ip" =~ ^169\.254\. ]] && return 0
    return 1
}

PUBLIC_IPS=()
for ip in "${IPS[@]}"; do
    is_private "$ip" || PUBLIC_IPS+=("$ip")
done

TOTAL=${#PUBLIC_IPS[@]}
if [[ "$TOTAL" -eq 0 ]]; then
    echo "No public IPs found in input. Nothing to enrich." >&2
    exit 0
fi
echo "Found $TOTAL unique public IP(s) to enrich." >&2

# ---------- step 2: write CSV header ----------
echo "ip,country,region,city,lat,lon,isp,org,as,query_status" > "$OUTPUT_FILE"

# ---------- step 3: batch-query the API ----------
# ip-api.com's /batch endpoint accepts a JSON array of IPs (or objects)
# and returns an array of result objects in the same order.
batch_lookup() {
    local -a batch=("$@")

    # Build JSON array like ["1.2.3.4","5.6.7.8",...]
    local json_ips
    json_ips=$(printf '%s\n' "${batch[@]}" | jq -R . | jq -s .)

    local fields="status,message,country,regionName,city,lat,lon,isp,org,as,query"

    curl -s -X POST "$API_URL?fields=${fields}" \
         -H "Content-Type: application/json" \
         -d "$json_ips"
}

# ---------- step 4: chunk IPs into batches of BATCH_SIZE ----------
count=0
batch=()
for ip in "${PUBLIC_IPS[@]}"; do
    batch+=("$ip")
    count=$((count + 1))

    if [[ "${#batch[@]}" -eq "$BATCH_SIZE" ]]; then
        echo "Querying batch of ${#batch[@]} IPs... ($count/$TOTAL processed)" >&2
        response=$(batch_lookup "${batch[@]}")

        echo "$response" | jq -r '
            .[] |
            [
                (.query // ""),
                (.country // ""),
                (.regionName // ""),
                (.city // ""),
                (.lat // ""),
                (.lon // ""),
                (.isp // ""),
                (.org // ""),
                (.as // ""),
                (.status // "")
            ] | @csv
        ' >> "$OUTPUT_FILE"

        batch=()
        sleep "$RATE_DELAY"
    fi
done

# handle leftover partial batch
if [[ "${#batch[@]}" -gt 0 ]]; then
    echo "Querying final batch of ${#batch[@]} IPs..." >&2
    response=$(batch_lookup "${batch[@]}")
    echo "$response" | jq -r '
        .[] |
        [
            (.query // ""),
            (.country // ""),
            (.regionName // ""),
            (.city // ""),
            (.lat // ""),
            (.lon // ""),
            (.isp // ""),
            (.org // ""),
            (.as // ""),
            (.status // "")
        ] | @csv
    ' >> "$OUTPUT_FILE"
fi

echo "Done. Enriched data written to: $OUTPUT_FILE" >&2
