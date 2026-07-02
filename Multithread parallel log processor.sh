




#!/bin/bash

#############################################
# Parallel Log Processor
#############################################


for i in {1..100000}; do
echo "192.168.$((RANDOM%10)).$((RANDOM%255)) GET /index.html 200" >> dataset.log    
done

INPUT="dataset.log"

CHUNK_DIR="chunks"
RESULT_DIR="results"

THREADS=4

mkdir -p "$CHUNK_DIR"
mkdir -p "$RESULT_DIR"

echo "Cleaning old files..."

rm -f "$CHUNK_DIR"/*
rm -f "$RESULT_DIR"/*
rm -f final_report.txt

#############################################
# Step 1
# Split file into equal chunks
#############################################

echo "Splitting dataset..."

split -n l/$THREADS "$INPUT" "$CHUNK_DIR/chunk_"

#############################################
# Worker Function
#############################################

process_chunk() {

    chunk=$1
    outfile=$2

    total_lines=$(wc -l < "$chunk")

    unique_ips=$(awk '{print $1}' "$chunk" | sort | uniq | wc -l)

    success=$(grep -c "200" "$chunk")

    echo "Chunk : $chunk" > "$outfile"
    echo "Lines : $total_lines" >> "$outfile"
    echo "Unique IPs : $unique_ips" >> "$outfile"
    echo "HTTP 200 : $success" >> "$outfile"

}

#############################################
# Step 2
# Process each chunk in parallel
#############################################

echo "Starting parallel workers..."

for file in "$CHUNK_DIR"/*
do

    output="$RESULT_DIR/$(basename "$file").txt"

    process_chunk "$file" "$output" &

done

#############################################
# Step 3
# Wait for all workers
#############################################

echo "Waiting for workers..."

wait

echo "All workers finished."

#############################################
# Step 4
# Aggregate Results
#############################################

echo "Creating final report..."

echo "========== FINAL REPORT ==========" > final_report.txt

total_lines=0
total_success=0
total_ips=0

for report in "$RESULT_DIR"/*
do

    cat "$report" >> final_report.txt
    echo "" >> final_report.txt

    lines=$(grep "Lines" "$report" | awk '{print $3}')
    success=$(grep "HTTP 200" "$report" | awk '{print $3}')
    ips=$(grep "Unique IPs" "$report" | awk '{print $4}')

    total_lines=$((total_lines+lines))
    total_success=$((total_success+success))
    total_ips=$((total_ips+ips))

done

echo "==============================" >> final_report.txt
echo "Total Lines : $total_lines" >> final_report.txt
echo "Total HTTP 200 : $total_success" >> final_report.txt
echo "Sum of Unique IP Counts : $total_ips" >> final_report.txt

echo ""
echo "Done!"
echo "Report saved to final_report.txt"
