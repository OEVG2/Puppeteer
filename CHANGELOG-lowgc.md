# Puppeteer 1.1.3-lowgc

A low-garbage build of [skrymsli/Puppeteer](https://github.com/skrymsli/Puppeteer) (healer mana display included),
with the upstream OldManAlpha `dev` fixes merged:
- Nampower fallback for cast failures on base 1.12 (fixes stuck heal predictions)
- "Vanilla Shaman Color" option

Neither upstream change adds garbage.

## Why

WoW 1.12 runs Lua 5.0, whose collector stops the game and walks the whole heap whenever enough garbage piles up.
That is the combat hitch. The only fix an addon can make is to allocate less, so every change below removes
allocations from code that runs during fights. Nothing about how the frames look or behave was changed.

## Garbage per event (bytes), 40-man raid

| Event | Before | After |
|---|---:|---:|
| Full group check (RAID_ROSTER_UPDATE) | 16,267 | 237 |
| Target change | 5,550 | 1.5 |
| HealComm message from another healer | 546 | 4.5 |
| Heal cast (SuperWoW START + CAST) | 409 | 1.8 |
| HoT cast + Nampower aura event | 409 | 0.4 |
| Heal cast + its combat log line | 164 | 6.9 |
| UNIT_AURA | 52–58 | 0.1 |
| UNIT_HEALTH | 49 | 21 |

Simulated Naxxramas-style fight: 21.2 KB/s → 8.6 KB/s of garbage. The SuperWoW + Nampower + UnitXP client and the
plain 1.12 client gave the same results.

## Changes

- **Private table pool (`libs/Pool.lua`).** Puppeteer used Compost-2.0, which strongly keeps only 10 tables and puts
  the rest in a weak table that every GC empties. Its erase also shrinks tables, so every reuse has to grow them
  again. Puppeteer's own code now uses a pool that survives GC and keeps table capacity. The shared Ace libraries
  still use their own Compost.
- **Aura scanning (`PTUnit`).** Each unit reuses one entry table per aura slot and its name/type arrays, instead of
  rebuilding everything on every UNIT_AURA.
- **Target changes and group checks.**
  - The heal-prediction GUID set is now refilled in place; it used to be a new array plus a new set every time.
  - Frame sorting and layout use reusable scratch tables and static comparators.
  - Role ranks are computed once per frame instead of inside the comparator, which also removes an O(n²)
    lookup during the sort.
- **Heal prediction.**
  - Fixed tables that were orphaned on every cast: last cast, overwritten HoTs, overwritten resurrections.
  - Debug messages are only built when debug output is on. They were built for every heal even with debug off.
- **Aura tracking.**
  - Nampower aura events reuse one table instead of creating `{target}` each time.
  - AoE buff target lists are now released after use.
- **Unit frame text.**
  - Health, missing health, power, incoming heal and range text are each built with one `string.format`, so no
    intermediate strings are created.
  - Color code prefixes are cached.
  - Range text is only rebuilt when the shown distance or its color changes.
  - Aura minute strings ("5m") are cached.
- **Raid mana header.** It used to scan all 40 frames on every mana, rage or energy tick in the raid. It now updates
  at most twice per second. This is a CPU saving rather than a garbage one.
- **HealComm-1.0 (bundled).** The message split table and heal entries are reused. HealComm is shared between addons,
  so this only applies when Puppeteer's copy is the one loaded.

## Verification

- All files compile under a real Lua 5.0 VM.
- Baseline and this build were run through the same deterministic simulated fight. Every frame's texts, bar values,
  colors, alpha, positions, aura icons, heal predictions and aura caches were compared at checkpoints across 10
  settings and client combinations. The only difference: a stale aura icon reference now holds that slot's current
  aura instead of an erased table, which only affects what a hover tooltip would show.

## About ClassicAPI

ClassicAPI backports the modern API and Lua 5.1 syntax, but it still runs on 1.12's Lua 5.0 VM and documents no
collector changes. It would not reduce GC pauses, so this build does not depend on it.
