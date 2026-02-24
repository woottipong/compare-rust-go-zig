#!/bin/bash
# Save benchmark results to timestamped file
# Usage: ./benchmark/results/save-results.sh [project_name]

PROJECT_NAME="${1:-hls-stream-segmenter}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="$(dirname "$0")"
OUTPUT_FILE="$RESULTS_DIR/${PROJECT_NAME}_${TIMESTAMP}.txt"

echo "Saving benchmark results to: $OUTPUT_FILE"
echo ""

# Run benchmark and capture output
cd "$(dirname "$0")/.."
./run.sh "$@" > "$OUTPUT_FILE"

echo "Results saved to: $OUTPUT_FILE"
echo "Latest results:"
echo "  $OUTPUT_FILE"

# Also create a summary CSV for easy comparison
SUMMARY_FILE="$RESULTS_DIR/${PROJECT_NAME}_summary.csv"
if [ ! -f "$SUMMARY_FILE" ]; then
    echo "Timestamp,Project,Go_Avg,Rust_Avg,Zig_Avg,Go_Memory,Rust_Memory,Zig_Memory,Go_Size,Rust_Size,Zig_Size" > "$SUMMARY_FILE"
fi

# Extract metrics (simplified extraction)
go_avg=$(grep "Avg:" "$OUTPUT_FILE" -A 1 | head -1 | grep -o "[0-9]\+ms" | head -1)
rust_avg=$(grep "Avg:" "$OUTPUT_FILE" -A 3 | head -2 | tail -1 | grep -o "[0-9]\+ms" | head -1)
zig_avg=$(grep "Avg:" "$OUTPUT_FILE" -A 5 | head -3 | tail -1 | grep -o "[0-9]\+ms" | head -1)

go_mem=$(grep "Peak Memory:" "$OUTPUT_FILE" | head -1 | grep -o "[0-9]\+ KB")
rust_mem=$(grep "Peak Memory:" "$OUTPUT_FILE" | head -2 | tail -1 | grep -o "[0-9]\+ KB")
zig_mem=$(grep "Peak Memory:" "$OUTPUT_FILE" | head -3 | tail -1 | grep -o "[0-9]\+ KB")

echo "$TIMESTAMP,$PROJECT_NAME,${go_avg:-N/A},${rust_avg:-N/A},${zig_avg:-N/A},${go_mem:-N/A},${rust_mem:-N/A},${zig_mem:-N/A}" >> "$SUMMARY_FILE"

echo "Summary updated: $SUMMARY_FILE"
