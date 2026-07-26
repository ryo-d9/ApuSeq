# Large File Benchmark Checklist

Use this checklist before release to verify that ApuSeq remains responsive on large alignment files. Generated samples are local test artifacts and are not committed.

## Generate Samples

From the repository root:

```sh
./Scripts/generate-large-alignment-samples.sh
```

This writes generated files to:

```text
SampleData/LargeFileBenchmark/generated/
```

The script prints each generated file's expected `rows.count`, `alignment.length`, and `rows.count * alignment.length` so the test pass can be compared against ApuSeq's footer.

Default files:

| File | Shape | Purpose |
|---|---:|---|
| `fasta-approx-1mb.fasta` | 100 x 10,000 | baseline FASTA |
| `fasta-approx-10mb.fasta` | 500 x 20,000 | normal stress FASTA |
| `fasta-approx-50mb.fasta` | 1,000 x 50,000 | upper-range FASTA |
| `clustal-approx-1mb.aln` | 100 x 10,000 | baseline CLUSTAL |
| `clustal-approx-10mb.aln` | 500 x 20,000 | normal stress CLUSTAL |

To also generate a very large CLUSTAL file:

```sh
INCLUDE_LARGE_CLUSTAL=1 ./Scripts/generate-large-alignment-samples.sh
```

## Checks

Run this using a release-style build when possible.

| Check | Expected |
|---|---|
| Open each file | Alignment becomes visible without crashing |
| Compare footer counts | Footer sequence and site counts match the script output |
| Scroll vertically | Remains responsive |
| Scroll horizontally | Remains usable on long alignments |
| Switch background modes | Completes without hanging |
| Toggle auxiliary panels | Completes without hanging |
| Enter Edit mode | Warning appears and editing remains possible |
| Make a small edit on a disposable file | View updates and undo works |
| Save and reopen a disposable edited file | Reopened alignment reflects the edit |
| Try UPGMA on more than 300 rows | Command remains unavailable |
| Start MAFFT on a small sample and cancel | Progress sheet appears and cancel returns control |

## Suggested Release Thresholds

These are practical guidelines, not product limits.

| Size | Expected Behavior |
|---|---|
| 1MB | Opens and edits comfortably |
| 10MB | Opens and scrolls comfortably; heavier coloring may take noticeable time |
| 50MB | Opens without crashing; interaction may be slower; editing is best-effort |
