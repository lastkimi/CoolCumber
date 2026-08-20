# Product UI phase 1

The phase-one product shell is compiled from `ThermFlowApp.swift` and
`MenuBarManager.swift` because the checked-in Xcode project explicitly lists
source files and this change is intentionally not allowed to rewrite the
project file.

The implemented boundaries are:

- standard resizable macOS window with a `NavigationSplitView`;
- universal menu bar popover, independent of notch hardware;
- trusted metric presentation (`loading`, `available`, `stale`, `unavailable`);
- semantic system colors and 12pt-or-larger supporting text;
- explicit-only helper setup and read-only monitoring on first interaction;
- legacy feature pages retained behind secondary, user-initiated entry points.

When the project is next regenerated, the model, shell, feature pages, and
components can be moved from the two compiled files into this directory
without changing their public type names.
