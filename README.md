# ApuSeq

ApuSeq is a lightweight native macOS alignment viewer and editor for sequence alignment files.

The project focuses on fast viewing, simple editing, and standard macOS document behavior while keeping custom UI and infrastructure as small as practical.

## Features

- Opens FASTA, Clustal, and plain-text alignment files
- Native macOS document support with autosave and versions
- TextKit 2 based alignment viewport
- View and Edit modes
- Reference, Consensus, and Identity panels
- Residue, majority-difference, and identity coloring modes
- View-only sequence ordering with Original and UPGMA modes
- Column selection and multi-range editing
- Sequence deletion from the name panel in Edit mode
- Remove All-Gap Columns command, treating `-` and `.` as gaps
- Nucleotide translation with selectable codon tables
- Quick Look preview extension with lightweight residue coloring
- Apple Help Book
- Icon Composer app icon

## Design Goals

- Use Apple-provided macOS document, menu, settings, help, Quick Look, and text system features where they fit
- Keep the viewer responsive for large alignments
- Avoid modifying files in View mode
- Keep derived outputs, such as translated sequences, as new unsaved documents until the user saves them
- Keep domain logic independent from platform UI where practical

## Editing Behavior

Edit mode follows the macOS document model. Changes can be autosaved and are managed by the system versions workflow.

When inserting or deleting residues, ApuSeq preserves alignment shape by adding gap characters to other sequences as needed. Removing all-gap columns is undoable and is disabled when it would make the alignment empty.

## Quick Look

The Quick Look extension provides a compact HTML preview for supported alignment files. Previews are intentionally limited in size so Finder remains responsive.

## Help

A lightweight Apple Help Book is bundled with the app and is available from the macOS Help menu.

## Project Structure

- `ApuSeq/ApuSeqApp.swift` - app entry point, commands, settings, and translation command routing
- `ApuSeq/ApuSeqDocument.swift` - document storage and file read/write support
- `ApuSeq/ContentView.swift` - main SwiftUI document view and alignment view model
- `ApuSeq/AlignmentCore.swift` - parsing, rendering, statistics, clustering, editing, and translation core
- `ApuSeq/AlignmentPanels.swift` - SwiftUI panels, controls, and status bar
- `ApuSeq/AlignmentTextConfiguration.swift` - alignment display configuration
- `ApuSeq/AlignmentTextViewport.swift` - AppKit/TextKit 2 alignment viewport
- `ApuSeq/TextDecoding.swift` - text decoding helpers
- `ApuSeq/ApuSeqHelp.help` - bundled Apple Help Book
- `ApuSeq/ApuSeqQuickLookExtension` - Quick Look preview extension
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
