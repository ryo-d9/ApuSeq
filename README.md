# ApuSeq

**ApuSeq** (Alignment Preview Utility for Sequences) is a sequence alignment viewer and editor for macOS, designed for fast viewing and editing with a simple interface.

- **Requirement**: macOS Tahoe 26 or later
- **Languages**: English and Japanese
- **Distribution**: Currently under development. Planned for future release on the Mac App Store.

## Features
ApuSeq currently supports FASTA, CLUSTAL, CLUSTAL W, MUSCLE, and plain text sequence alignment files.

- **Common features**
  - Reference, Consensus, and Identity panels
  - Background coloring modes: None, Residue, Minority, Reference, and Identity
  - Copy Sequence and Copy as FASTA from the context menu
  - Nucleotide translation with selectable codon tables
  - Reverse complement generation for nucleotide alignments
  - Bundled MAFFT 7.526 alignment (`--auto`)
  - Amino-acid-guided nucleotide alignment for coding FASTA sequences
  - Quick Look preview extension with lightweight residue coloring
- **View mode**
  - Display ordering: Original, Name, and UPGMA
- **Edit mode**
  - Column selection and multi-range editing
  - Adding, renaming, and deleting sequences, including FASTA import from the clipboard
  - Insert Gap Column, Remove All-Gap Columns, Trim Trailing Gaps, and Sort Sequences commands, treating `-` and `.` as gaps where applicable
  - MAFFT alignment for selected columns

## Viewing Behavior

Background coloring can be changed from the footer or View > Background Color.

- Minority colors: residues differ from the column majority
- Reference coloring: residues that differ from the selected reference sequence (appears after a reference is selected)

## Editing Behavior

Changes in edit mode can be autosaved and are managed by the system versions workflow.

- Typing and deletion edit the selected sequence rows. Shorter rows are temporarily padded with trailing `-` characters to preserve alignment length.
- Insert gap columns with Edit > Insert Gap Column, and remove all-gap columns with Alignment > Remove All-Gap Columns.
- Import FASTA records from the clipboard with Edit > Add FASTA from Clipboard.
- Sort sequences by name or UPGMA (3–300 sequences).
- Reverse Complement, Translation, and Align with MAFFT create new FASTA documents.
- Selected columns can be realigned independently using MAFFT.
- Coding nucleotide FASTA sequences can be translated, aligned as amino acids with MAFFT, and mapped back to nucleotide codons with Alignment > Align with MAFFT > Amino-Acid-Guided Nucleotide Alignment.

## Quick Look

The Quick Look extension provides a compact HTML preview for supported alignment files. Previews are intentionally limited in size so Finder remains responsive.

## Project Structure

- `ApuSeq/App` - app entry point, document type, commands, settings, and the main SwiftUI document view
- `ApuSeq/Core` - alignment model, parsing, rendering, analysis, and MAFFT integration
- `ApuSeq/Viewer` - SwiftUI panels and TextKit 2 alignment editor
- `ApuSeq/ApuSeqHelp.help` - bundled Apple Help Book
- `ApuSeq/ApuSeqQuickLookExtension` - Quick Look preview extension
- `SampleData` - small synthetic alignments for review and manual testing
- `Vendor/MAFFT` - bundled MAFFT files and MAFFT license notice
- `Scripts` - build helper scripts and file lists for bundled tools
- `Signing` - helper entitlements used when signing bundled command-line tools
- `ApuSeqIcon.icon` - Icon Composer app icon

## Development
  - macOS 26.5
  - Xcode 26.6

## Build

1. Open `ApuSeq.xcodeproj` in Xcode.
2. Select the `ApuSeq` scheme.
3. Build and run with Command-R.

For Quick Look development, use the `ApuSeqQuickLookExtension` target and install the built app so macOS can discover the extension.

## License

ApuSeq is released under the MIT License. See `LICENSE` for details.

The following materials are not covered by the MIT License unless explicitly stated otherwise:

- Screenshots, App Store images, icons, and other branding or promotional assets.

Documentation screenshots may use alignments derived from public NCBI sequence records. See `SampleData/README.md` for accession numbers and source information.

MAFFT 7.526 (2024/Apr/26) is bundled under its BSD-style license. See `Vendor/MAFFT/LICENSE-MAFFT.txt` or Help > Open Source Licenses in the app.
