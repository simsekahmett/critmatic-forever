# Changelog

## Unreleased

- Personal best records are off. The client never gives the hit number as a plain integer, so nothing is saved.
- Every crit is shown as it lands, from UNIT_COMBAT. Ticks and heal over time are shown only when they crit.
- Chat can share a crit to party, guild, or raid: `CritMatic Forever ★ Claw crit 224`.
- The on-screen alert is plain text, with no box.
- Fight totals from the damage meter are no longer recorded or shown.
- Settings pages are drawn in the window itself. A hidden scroll box left the tabs up and the page blank.
- `/cmf probe` shows what the client exposes, for troubleshooting.
- Records are stored per "Name-Realm" in the account file. Existing per-character records are imported once. `/cmf status` shows which character the records belong to.
- Alert bar: width is measured from the full text, so a reused bar can grow again. Height, icon and stacking follow the text size.
- Record window: the spell name column follows the window width, and rows update while resizing.

## 1.0.0

- First Forever release for interface 16001.
- Per-spell crit and normal hit records, including heals and pets, when the combat log is readable.
- The combat log event is never registered. Forever treats that registration as a protected action.
- Fight totals are read from the built-in damage meter after combat and saved separately from crits.
- Record window, spell tooltips, alert popups, sounds, chat lines, ignore lists, and a minimap button.
- English and Turkish text.
