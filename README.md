# TriRoutes for Triumvirate WoW

**Version:** 0.1.0-test6c  
**Client:** World of Warcraft 3.3.5a / Interface 30300

TriRoutes provides curated dungeon route guidance for the Triumvirate WoW server, including route arrows, minimap/map trails, Heroic/Mythic route selection, Dungeon Finder route coverage indicators, Mythic+ chat observations, and stateful route progression.

`TriRoutes_Recorder` is the companion telemetry addon used to record dungeon runs so routes can be reviewed and improved later. It depends on `TriRoutes`.

## Included in this ZIP

- `TriRoutes/` — main addon
- `TriRoutes_Recorder/` — route telemetry recorder
- `README.md` — this file

## REQUIRED: WDM dungeon map patch

TriRoutes relies on the WDM-compatible dungeon maps used by this package. The required map patch is **not included in this ZIP** and must be downloaded separately.

For an **enUS** WoW 3.3.5a client, download:

https://github.com/Trimitor/WDM-patch/releases/download/2.4.5-stable/patch-enUS-M.MPQ

Release: **WDM-patch 2.4.5-stable**  
File: `patch-enUS-M.MPQ`

Install it here:

```text
[World of Warcraft folder]\Data\enUS\patch-enUS-M.MPQ
```

For example:

```text
World of Warcraft 3.3.5a\Data\enUS\patch-enUS-M.MPQ
```

The WDM-patch project states that this release is for **WoW 3.3.5a**. If your client uses a different locale, use the matching locale MPQ from the same WDM release instead of the enUS file.

WDM release page:

https://github.com/Trimitor/WDM-patch/releases/tag/2.4.5-stable

### Optional integrity check for the enUS file

The 2.4.5-stable release reports:

```text
SHA-256: b69713077e19498d20efa5eeaefdba98850764db6bdc99e292bfbdf7b1c858d6
Size:    48,767,934 bytes
```

## Addon installation

1. Close World of Warcraft.
2. Install the WDM map patch described above.
3. Extract this ZIP.
4. Copy both addon folders into:

```text
[World of Warcraft folder]\Interface\AddOns\
```

You should end up with:

```text
Interface\AddOns\TriRoutes\TriRoutes.toc
Interface\AddOns\TriRoutes_Recorder\TriRoutes_Recorder.toc
```

5. Start WoW and enable **TriRoutes** and **TriRoutes Recorder** on the AddOns screen.

`TriRoutes_Recorder` is required only if you want to collect route telemetry. The main `TriRoutes` addon handles route display/navigation.

## Basic TriRoutes commands

```text
/troutes status
/troutes refresh
/troutes map on|off
/troutes minimap on|off
/troutes overlay on|off
/troutes needs on|off
/troutes mythic
/troutes trail on|off
/troutes route auto|off
/troutes arrow on|off|reset|lock|unlock
```

Run `/troutes help` in game for the current full command list.

## Recorder commands

```text
/trr status
/trr record
/trr stop
/trr auto on|off
/trr difficulty auto|normal|heroic|mythic
/trr routeleader auto|target|<name>
/trr mark <pull|boss|turn|skip|warning|stairs> [note]
```

The recorder saves its data separately to:

```text
WTF\Account\<ACCOUNT>\SavedVariables\TriRoutes_Recorder.lua
```

That SavedVariables file is the one to share when submitting new dungeon recordings for route analysis.

## Current package notes

This package is based on **TriRoutes 0.1.0-test6c**. The test6c fix prevents route guidance from disappearing after a wipe/recovery simply because the recorder resumed the same dungeon under a new internal section number.

Current curated route coverage in this build is **27 Heroic-compatible routes and 7 Mythic routes**, with 35 curated routes in total.

## Troubleshooting

If a route does not appear:

- confirm `patch-enUS-M.MPQ` is installed in `Data\enUS` for an enUS client;
- confirm both addon folders are directly under `Interface\AddOns` and are not nested inside another folder;
- run `/troutes status` and `/troutes refresh`;
- after a problem during a recorded dungeon, keep the `TriRoutes_Recorder.lua` SavedVariables file so the run can be diagnosed.

