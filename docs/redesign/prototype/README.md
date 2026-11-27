# SOS Mac Redesign v1 — Aurora Indigo

Clickable prototype of the SOS Mac redesign: macOS window frame, dark first, 1200×760.

## Pages
- `index.html` — the prototype. The bar on top switches screen, state, appearance and palette. Links can open a state directly, e.g. `index.html?screen=junk&state=review&theme=light`.
- `board.html` — every screen and state side by side, the confirmation dialogs, the 3 light screens and the menu bar widget.
- `tokens.html` — Tokens & Components, with the Swift name for every token.
- `palettes.html` — Smart Care in palettes A, B and C.
- `needs-engine-work.html` — what was left out because the engine has no data for it yet, or has a known bug.

## Tokens
- `tokens.css` — the source used by the prototype (Palette A + B/C overrides for comparison).
- `tokens/Theme.swift` — proposed Swift version (typechecks for macOS 14+; Liquid Glass only behind `#available(macOS 26, *)`). Not in the sos-mac repo yet.
- `tokens/sos-aurora-indigo.tokens.json` — the same values as a tokens JSON file.

## Notes
- Sample data (file names, sizes, versions) is made up for the prototype. The kinds of numbers shown are only those the engine provides today (inventory §4.1).
- Copy for local removal is always "Move to Trash". Cloud deletes have their own server-side confirmation.
