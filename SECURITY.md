# Security

## Trust boundary

Type Relay observes local keyboard events through Hammerspoon and may read the focused Accessibility text value to repair it. It does not persist or transmit typed content.

- the in-memory buffer is capped at 256 characters;
- the buffer is cleared on application, focus, mouse, navigation, and Secure Input changes;
- writable Accessibility values are read back before success is reported;
- clipboard fallback restores the previous clipboard when Type Relay still owns it;
- no runtime network access is implemented.

## Reporting

Report a vulnerability privately to `info@aimindset.org`. Do not include real sensitive text captured from an affected field.
