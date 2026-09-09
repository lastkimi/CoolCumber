# Product UI

The production UI is a menu-bar-first, native SwiftUI experience backed by the
same typed `SystemSnapshot` used by history, alerts, and the Widget.

Current boundaries:

- standard resizable macOS window with `NavigationSplitView`;
- universal menu-bar popover for both notched and non-notched Macs;
- optional SmartBar enhancement only on a detected notch display;
- explicit loading, available, stale, unsupported, and unavailable states;
- semantic system colors, light/dark appearance, Reduce Motion support, and
  accessibility labels for the main monitoring surfaces;
- explicit helper approval in Direct builds; Mac App Store builds never embed
  or reference the helper;
- Free monitoring and 24-hour history, with verified Pro entitlement gating
  30-day history, local alerts, and CSV export.

## Reproducible UI capture

Debug builds accept these UI-only launch arguments without injecting synthetic
telemetry:

- `--open-main-window`, `--open-history`, `--open-settings`, or `--open-pro`;
- `--show-welcome` or `--skip-welcome`;
- `--ui-language-en` or `--ui-language-zh`;
- `--ui-appearance-light` or `--ui-appearance-dark`.

Every screenshot must still come from a real built app. Missing hardware data
must remain visibly unavailable; release bundles do not compile the language
or appearance overrides.
