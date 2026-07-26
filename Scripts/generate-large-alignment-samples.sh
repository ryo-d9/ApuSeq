#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR="${1:-$REPO_ROOT/SampleData/LargeFileBenchmark/generated}"
INCLUDE_LARGE_CLUSTAL="${INCLUDE_LARGE_CLUSTAL:-0}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/fasta-approx-*.fasta "$OUTPUT_DIR"/clustal-approx-*.aln

print_sample_summary() {
    file_path="$1"
    format="$2"
    row_count="$3"
    column_count="$4"
    file_name=$(basename "$file_path")
    residue_cells=$((row_count * column_count))

    printf "%-28s %-7s rows=%-5s length=%-7s cells=%s\n" \
        "$file_name" \
        "$format" \
        "$row_count" \
        "$column_count" \
        "$residue_cells"
}

generate_fasta() {
    output_file="$1"
    row_count="$2"
    column_count="$3"

    awk -v rows="$row_count" -v columns="$column_count" '
        BEGIN {
            alphabet = "ACGT--";
            for (row = 1; row <= rows; row++) {
                printf(">sample_%05d\n", row);
                for (column = 1; column <= columns; column++) {
                    residue_index = ((row * 17 + column * 31) % length(alphabet)) + 1;
                    printf("%s", substr(alphabet, residue_index, 1));
                    if (column % 100 == 0) {
                        printf("\n");
                    }
                }
                if (columns % 100 != 0) {
                    printf("\n");
                }
            }
        }
    ' > "$output_file"
}

generate_clustal() {
    output_file="$1"
    row_count="$2"
    column_count="$3"

    awk -v rows="$row_count" -v columns="$column_count" '
        BEGIN {
            alphabet = "ACGT--";
            block_width = 60;
            printf("CLUSTAL W generated benchmark alignment\n\n");
            for (block_start = 1; block_start <= columns; block_start += block_width) {
                block_end = block_start + block_width - 1;
                if (block_end > columns) {
                    block_end = columns;
                }
                for (row = 1; row <= rows; row++) {
                    printf("sample_%05d    ", row);
                    for (column = block_start; column <= block_end; column++) {
                        residue_index = ((row * 17 + column * 31) % length(alphabet)) + 1;
                        printf("%s", substr(alphabet, residue_index, 1));
                    }
                    printf("    %d\n", block_end);
                }
                printf("                ");
                for (column = block_start; column <= block_end; column++) {
                    printf(column % 5 == 0 ? "*" : " ");
                }
                printf("\n\n");
            }
        }
    ' > "$output_file"
}

echo "Writing benchmark samples to $OUTPUT_DIR"
printf "\nGenerated sample shapes:\n"

generate_fasta "$OUTPUT_DIR/fasta-approx-1mb.fasta" 100 10000
print_sample_summary "$OUTPUT_DIR/fasta-approx-1mb.fasta" "FASTA" 100 10000

generate_fasta "$OUTPUT_DIR/fasta-approx-10mb.fasta" 500 20000
print_sample_summary "$OUTPUT_DIR/fasta-approx-10mb.fasta" "FASTA" 500 20000

generate_fasta "$OUTPUT_DIR/fasta-approx-50mb.fasta" 1000 50000
print_sample_summary "$OUTPUT_DIR/fasta-approx-50mb.fasta" "FASTA" 1000 50000

generate_clustal "$OUTPUT_DIR/clustal-approx-1mb.aln" 100 10000
print_sample_summary "$OUTPUT_DIR/clustal-approx-1mb.aln" "CLUSTAL" 100 10000

generate_clustal "$OUTPUT_DIR/clustal-approx-10mb.aln" 500 20000
print_sample_summary "$OUTPUT_DIR/clustal-approx-10mb.aln" "CLUSTAL" 500 20000

if [ "$INCLUDE_LARGE_CLUSTAL" = "1" ]; then
    generate_clustal "$OUTPUT_DIR/clustal-approx-50mb.aln" 1000 50000
    print_sample_summary "$OUTPUT_DIR/clustal-approx-50mb.aln" "CLUSTAL" 1000 50000
fi

printf "\nFile sizes:\n"
wc -l -c "$OUTPUT_DIR"/fasta-approx-*.fasta "$OUTPUT_DIR"/clustal-approx-*.aln
ls -lh "$OUTPUT_DIR"/fasta-approx-*.fasta "$OUTPUT_DIR"/clustal-approx-*.aln
