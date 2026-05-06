# ApuSeq

ApuSeq is a lightweight macOS alignment viewer/editor for FASTA, CLUSTAL, and plain text sequence alignments.

## Goals

- Fast startup and smooth rendering for large alignments
- Native macOS behavior and standard UI components
- Minimal custom UI complexity where possible

## Current Features

- Open and view alignments in:
  - FASTA
  - CLUSTAL
  - Plain text
- Optional residue coloring (`Residue` mode)
- Optional identity shading (`Identity` mode)
  - 3-level background shading:
    - 100% match
    - threshold-100% match
    - 0-threshold match
  - Threshold is configurable in Settings
- Reference/Consensus/Identity auxiliary panel support
- Edit mode for in-place sequence editing
- Column selection up/down commands (multi-range edit workflow)
- Quick Look extension target included

## Project Structure

- `ApuSeq/` app target sources
- `ApuSeqQuickLookExtension/` Quick Look extension sources
- `AlignmentCore.swift` parsing/rendering/statistics core
- `AlignmentTextSystem.swift` text system and panel synchronization
- `AlignmentPanels.swift` footer/info UI

## Requirements

- macOS (project deployment target is set in Xcode project settings)
- Xcode (current project configured for Swift 5)

## Build and Run

1. Open `ApuSeq.xcodeproj` in Xcode
2. Select scheme:
   - `ApuSeq` for app
   - `ApuSeqQuickLookExtension` for extension debugging
3. Build/Run with `Cmd+R`

## Settings

Open **ApuSeq > Settings**:

- Alignment Font Size
- Identity Threshold
- Translation Codon Table

## Notes on Editing

- Edit mode and View mode are switchable from the toolbar menu.
- Edits are applied to sequence text and reflected in document content.
- Multi-range column editing is supported through column selection commands.

## Known Areas Under Active Development

- View/Edit transition refresh behavior
- Advanced multi-range undo/redo ergonomics
- Quick Look extension workflow and distribution validation

## License

No license file is currently included in this repository.
