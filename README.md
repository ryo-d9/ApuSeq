# ApuSeq

ApuSeq is a lightweight native macOS alignment viewer and editor for sequence alignment files.

The project focuses on fast viewing, simple editing, and standard macOS document behavior while keeping custom UI and infrastructure as small as practical.

## Features

- Opens FASTA, Clustal, and plain-text alignment files
- Native macOS document support with autosave and versions
- TextKit 2 based alignment viewport
- View and Edit modes
- Reference, Consensus, and Identity panels
- None, Residue, Different, and Identity background coloring modes
- View-only display ordering with Original, Name, and UPGMA modes for alignments with 3 to 300 sequences
- Column selection and multi-range editing
- Sequence add, FASTA clipboard import, rename, and deletion from Edit mode
- Copy Sequence and Copy as FASTA from the sequence name context menu
- Insert Gap Column, Remove All-Gap Columns, Trim Trailing Gaps, and Sort Sequences commands, treating `-` and `.` as gaps where applicable
- Nucleotide translation with selectable codon tables
- Reverse complement generation for nucleotide alignments
- Bundled MAFFT 7.526 `--auto` alignment for whole documents and selected columns
- Quick Look preview extension with lightweight residue coloring
- Apple Help Book
- Open source license viewer for bundled third-party components
- Icon Composer app icon

## Design Goals

- Use Apple-provided macOS document, menu, settings, help, Quick Look, and text system features where they fit
- Keep the viewer responsive for large alignments
- Avoid modifying files in View mode
- Keep derived outputs, such as translated or reverse-complemented sequences, as new unsaved documents until the user saves them
- Keep domain logic independent from platform UI where practical

## Editing Behavior

Edit mode follows the macOS document model. Changes can be autosaved and are managed by the system versions workflow.

Typing and deletion in the alignment viewport edit only the selected sequence rows, matching normal text editing behavior. ApuSeq pads shorter rows with trailing `-` characters so the alignment remains rectangular.

Use Edit > Insert Gap Column, or Command-Shift-Hyphen, to insert a gap column at the current cursor position across all sequences. Removing all-gap columns is undoable and is disabled when it would make the alignment empty.

Use Edit > Add FASTA from Clipboard, or Command-Shift-V, to append FASTA records from the clipboard. Multi-line FASTA sequences are supported.

Use Alignment > Trim Trailing Gaps in Edit mode to remove trailing `-` and `.` characters from each sequence. ApuSeq may still display temporary padding gaps to keep alignment columns visually aligned.

Use Alignment > Sort Sequences in Edit mode to reorder the document contents by sequence name or UPGMA. UPGMA ordering is available for alignments with 3 to 300 sequences. Use View > Display Order to change only the displayed order without modifying the document.

Use Alignment > Reverse Complement to create a new unsaved FASTA document containing reverse-complemented nucleotide sequences. The source document is not modified.

Use Alignment > Translation to create a new unsaved FASTA document translated from nucleotide sequences in frame +0, +1, or +2. The source document is not modified.

Use Alignment > Align with MAFFT > Entire Alignment to create a new unsaved FASTA document aligned by the bundled MAFFT executable using `--auto`. ApuSeq shows an indeterminate progress sheet while MAFFT is running and provides a Cancel button for long-running alignments. The source document is not modified.

In Edit mode, select one or more columns and use Alignment > Align with MAFFT > Selected Columns to realign only those columns across all sequences. ApuSeq removes gaps from the selected region before sending it to MAFFT, then restores the aligned region between the unchanged prefix and suffix columns. The command is undoable and leaves the document unchanged if alignment fails.

## Quick Look

The Quick Look extension provides a compact HTML preview for supported alignment files. Previews are intentionally limited in size so Finder remains responsive.

## Sample Data

Small synthetic alignments for trying ApuSeq and for App Store review notes are available in `SampleData/`. They are not bundled with the app.

## Help

A lightweight Apple Help Book is bundled with the app and is available from the macOS Help menu.

Open source license notices for bundled third-party components are available from Help > Open Source Licenses.

## Project Structure

- `ApuSeq/App` - app entry point, document type, commands, settings, and the main SwiftUI document view
- `ApuSeq/Core` - alignment data model, parsing, rendering, statistics, clustering, translation, reverse complement, MAFFT integration, and text decoding
- `ApuSeq/Viewer` - SwiftUI panels and the AppKit/TextKit 2 alignment viewport
- `ApuSeq/ApuSeqHelp.help` - bundled Apple Help Book
- `ApuSeq/ApuSeqQuickLookExtension` - Quick Look preview extension
- `SampleData` - small synthetic alignments for review and manual testing
- `Vendor/MAFFT` - bundled MAFFT files and MAFFT license notice
- `Scripts` - build helper scripts and file lists for bundled tools
- `Signing` - helper entitlements used when signing bundled command-line tools
- `ApuSeqIcon.icon` - Icon Composer app icon

## Requirements

- macOS
- Xcode

The deployment target and signing settings are managed in the Xcode project.

## Build

1. Open `ApuSeq.xcodeproj` in Xcode.
2. Select the `ApuSeq` scheme.
3. Build and run with Command-R.

For Quick Look development, use the `ApuSeqQuickLookExtension` target and install the built app so macOS can discover the extension.

## License

ApuSeq is released under the MIT License. See `LICENSE` for details.

MAFFT 7.526 (2024/Apr/26) is bundled under its BSD-style license. See `Vendor/MAFFT/LICENSE-MAFFT.txt` or Help > Open Source Licenses in the app.
