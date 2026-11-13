# Changelog

## Unreleased

- Single-hit and crit records per spell are back. The addon refills the Combat Log chat tab after your hits (at most once a second) and reads them from it, so a record is announced about a second after the hit. Needs a Combat Log tab and the English client.
- Fight totals are no longer announced as a "new best" by default; they stay in the Fight tab.
- `/cmf probe` shows what the client exposes, for troubleshooting.
- Fight bests: when the current meter session was still hidden, the addon fell back to the older Expired session, saved that fight's totals and stopped retrying. It now waits for the real numbers.
- Fight bests: one fight read several times no longer announces more than once or overwrites the previous best with a partial total of the same fight.
- The end-of-fight summary now runs after the damage meter read, so it includes the fight bests.
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
