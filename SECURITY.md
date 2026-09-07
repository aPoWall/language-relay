# Security

## Trust boundary

Language Relay observes local keyboard events through Hammerspoon and may read the focused Accessibility text value to repair it. It does not persist or transmit typed content.

- the in-memory buffer is capped at 256 characters;
- the buffer is cleared on application, focus, mouse, navigation, and Secure Input changes;
- standard repairs use normal edit events by default to preserve application undo behavior where the host editor supports it;
- writable Accessibility values are used only as an opt-in compatibility fallback and are read back before success is reported;
- clipboard fallback restores the previous clipboard when Language Relay still owns it;
- no runtime network access is implemented.
- `hs.ipc` calls are bounded to 350 ms; a timed-out child is terminated by exact PID;
- runtime logs contain diagnostics only and never receive conversion input or buffered text.

## Reporting

Report a vulnerability privately to `info@aimindset.org`. Do not include real sensitive text captured from an affected field.
