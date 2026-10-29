# DriveIndex style

DriveIndex should look like Finder and System Settings: system controls, fonts and colors. Add custom styling only where macOS has nothing equivalent.

## Defaults first

1. Start with the stock SwiftUI control and no modifiers. Add a modifier only when the default looks wrong.
2. Use semantic values, not literal ones: text styles (`.title`, `.headline`, `.body`, `.callout`, `.caption`), semantic colors (`.primary`, `.secondary`, `.tertiary`, `.tint`) and built-in styles (`.bordered`, `.grouped`). Don't use point sizes, hex values or opacity math. Semantic values follow Dark Mode, Increase Contrast, accent color and sidebar size automatically.
3. Take containers from the system: `Form` with `.formStyle(.grouped)` for grouped cards, `List` or `Table` for rows, `GroupBox` for a single panel, and `ContentUnavailableView` for empty states. Don't draw rounded rectangles with stroked borders.
4. Use `.monospacedDigit()` only for numbers that update in place, such as progress counts. Don't use monospaced text anywhere else.
5. Delete as you go. When a token or modifier loses its last caller, remove it in the same commit.

## What we keep

These live in `DriveIndex/Styles/AppStyle.swift` because macOS has no equivalent:

- **Storage category colors** (`StorageCategory.color`): Media `.pink`, Other `.orange`, Apps `.blue`, Documents `.purple`, System `.gray`. They carry meaning in the storage bar, and because they're system colors they adapt to light mode, dark mode and Increase Contrast.
- **Connection status color**: `.green` when connected, `.secondary` when not. The sidebar dot and the drive header use it.
- **Layout widths**: sidebar 200–250 pt and the main window's minimum size.

Anything else that ends up in `AppStyle.swift` must have a comment explaining why the system version doesn't work.
