#!/bin/bash

# Monitor Elixir app memory usage
# Usage: ./scripts/monitor-memory.sh [interval_seconds] [duration_seconds]

INTERVAL=${1:-5}  # Default: check every 5 seconds
DURATION=${2:-300}  # Default: run for 5 minutes
ITERATIONS=$((DURATION / INTERVAL))

echo "🔍 Monitoring Elixir processes for memory leaks"
echo "   Interval: ${INTERVAL}s"
echo "   Duration: ${DURATION}s (${ITERATIONS} checks)"
echo ""
echo "Timestamp,PID,CPU%,MEM%,VSZ,RSS,COMMAND" | tee memory-monitor.csv

for i in $(seq 1 $ITERATIONS); do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Get all beam.smp processes (your Phoenix apps)
    ps aux | grep "beam.smp" | grep -v grep | grep -v "docker" | while read line; do
        PID=$(echo $line | awk '{print $2}')
        CPU=$(echo $line | awk '{print $3}')
        MEM=$(echo $line | awk '{print $4}')
        VSZ=$(echo $line | awk '{print $5}')
        RSS=$(echo $line | awk '{print $6}')
        CMD=$(echo $line | awk '{print $NF}')

        echo "$TIMESTAMP,$PID,$CPU,$MEM,$VSZ,$RSS,$CMD" | tee -a memory-monitor.csv
    done

    echo "---"

    sleep $INTERVAL
done

echo ""
echo "✅ Monitoring complete. Results saved to: memory-monitor.csv"
echo ""
echo "📊 Summary:"
echo "   Check for increasing RSS (Resident Set Size) - indicates memory leak"
echo "   Check for increasing VSZ (Virtual Memory Size) - may indicate atom table growth"
