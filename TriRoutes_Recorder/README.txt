0.1.0-test6c:
- Version alignment with the TriRoutes wipe/recovery navigation fix. Recorder behavior is unchanged from test6b.

0.1.0-test6b:
- Recorder hotfix for rapid chained dungeons: a stable change to another 5-player dungeon now closes the old run and starts a fresh session even inside the normal 45-second resume window.
- Requires 3 consecutive observations by default; candidate geometry is withheld during confirmation to avoid cross-dungeon contamination.
- One-off map/API glitches remain in the existing run. Route sampling/recovery logic is otherwise unchanged.

0.1.0-test6a:
- Version alignment with the Halls of Lightning Mythic +4 curated-route build.
- Recorder schema, sampling, sticky-tank selection, and same-tick coordinate recovery behaviour are unchanged from test5z.

0.1.0-test5z:
- Version alignment for the Blood Furnace +4 / Forge of Souls +1 Mythic route-pack build.
- Recorder schema, sampling, sticky-tank detection, and single same-tick coordinate recovery behaviour are unchanged from test5y.

0.1.0-test5y:
- Version alignment with the Mythic+ keystone-link tracker build. Recorder schema and sampling/recovery behaviour are unchanged.

0.1.0-test5x:
- Version alignment only for the TriRoutes stateful progression build.
- No recorder sampling, sticky-tank, party-coordinate retry, map recovery, canonicalization, or telemetry schema behaviour changed from test5u.

0.1.0-test5u:
- Added canonical Steamvault map aliases (Coilfang: The Steamvault / Coilfang Reservoir: The Steamvault / TheSteamvault / Steamvault).
- No sampling, sticky-tank, failure-retry, or map-recovery algorithm changes from test5t.

0.1.0-test5t:
- Added canonical Auchenai Crypts map aliases (Auchindoun: Auchenai Crypts / AuchenaiCrypts / Auchenai).
- No sampling, sticky-tank, failure-retry, or map-recovery algorithm changes from test5s.

0.1.0-test5s:
- Keeps test5r's validated passive + single same-tick party-coordinate retry behaviour unchanged.
- Adds Tempest Keep: The Botanica -> TheBotanica stored-map canonicalization learned from session 39.
- No startup map seeding, persistent map maintenance, retry loops, or other sampling changes were introduced.

0.1.0-test5r:
- Keeps test5q's validated passive + single same-tick party-coordinate retry behaviour unchanged.
- Adds Hellfire Citadel: Ramparts -> HellfireRamparts stored-map canonicalization learned from session 33.
- No startup map seeding, persistent map maintenance, retry loops, or other sampling changes were introduced.

0.1.0-test5q:
- Keeps test5p's validated passive + single same-tick party-coordinate retry behaviour unchanged.
- Adds Tempest Keep: The Arcatraz -> TheArcatraz stored-map canonicalization.
- Filters Defender Corpse, Warder Corpse, and Destroyed Sentinel from future combat pull NPC data.
- No startup map seeding, persistent map maintenance, retry loops, or other sampling changes were introduced.

0.1.0-test5p:
- Keeps test5o's validated passive + single same-tick party-coordinate retry behaviour unchanged.
- Adds Coilfang: The Underbog -> TheUnderbog stored-map canonicalization.
- Filters World Invisible Trigger, Toad, and Maggot from future combat pull NPC data.
- No startup map seeding, persistent map maintenance, or retry loops were reintroduced.

0.1.0-test5o:
- Keeps test5n passive WDM sampling, sticky learned-tank identity, tank-first party order, sparse-track protection, and all current route/UI behaviour.
- Adds one diagnostic same-tick recovery only after the first failed non-player coordinate read in a sampling tick: SetMapToCurrentZone is called once, that exact unit is retried immediately, then sampling returns to passive behaviour.
- Records initial-vs-final party failures plus retry attempts/successes/failures, whether the rescued read came from Astrolabe or native GetPlayerMapPosition, and raw map file before/after the retry.
- No run-start map seeding, retry loops, or persistent canonical-map maintenance are reintroduced.

0.1.0-test5n:
- Partial rollback of recorder map handling: removes the live SetMapToCurrentZone queue seeding, retry loop, and per-sample canonical-map maintenance introduced in test5k-test5m. Recording returns to passive WDM sampling, matching the simpler behaviour that previously produced healthy tank tracks.
- Keeps test5m sticky stable-tank identity, tank-first party sampling, sparse tank-track protection, player-vs-party failure counters, friendly/noise NPC filtering, logical session sections, and all current route/UI features.
- Adds Tempest Keep: The Mechanar -> TheMechanar canonical metadata mapping. This normalizes saved map identity but does not alter the user's live map state.
- New runs record samplingMapPolicy=passive-no-setmap so exports make the rollback explicit.

0.1.0-test5m:
- Adds Auchindoun: Mana-Tombs -> ManaTombs canonical instance-map pin.
- Known pinned dungeons now maintain map context at sampling time: if WDM reverts to the queue-origin map, the recorder can re-run SetMapToCurrentZone immediately before party reads instead of stopping after a handful of startup retries.
- Stable dungeon tank identity is sticky across temporary party-unit/coordinate failures and loading-screen exit churn; it is no longer demoted to player-fallback merely because a coordinate read fails.
- The stable tank is sampled first after canonical-map restoration. Player movement remains the geometry fallback.
- Sparse tank tracks are flagged and cannot win preferred geometry merely from TANK/route-leader metadata; tank identity/provenance is retained separately.
- Filters player-type combat-log objects outside the current party from pull-NPC capture, preventing stale player names from inflating pull counts.
- Adds mapContextExpectedFile/mapContextMaintenanceRepairs diagnostics while preserving schema 4 compatibility.
- `/trr status` now shows the dungeon tank lock, sparse-geometry state, expected canonical map, and maintenance-repair count for quick in-game verification.

0.1.0-test5l:
- Adds Hellfire Citadel: The Blood Furnace -> TheBloodFurnace instance-map pin.
- Extends queue-map recovery beyond the known override list: a newly encountered dungeon gets one generic SetMapToCurrentZone seed, with at most five rate-limited retries when player/party position probes are failing.
- Generic repair never changes the map while WorldMapFrame is open; explicit known-dungeon pins still determine canonical map identity.
- Records the initial/last repair map file to make the next queue export easier to diagnose.
- Filters Broggok Poison Cloud from future pull NPC lists; it is encounter-area hazard noise rather than a route pull target.

0.1.0-test5k:
- Adds The Shattered Halls instance-map pin.
- Dungeon Finder teleports now trigger a rate-limited SetMapToCurrentZone repair when a known dungeon inherits the outdoor map context and the World Map is closed.
- positionFailures now means route-critical player-position failures; party-position failures are counted separately so stale WDM context does not produce misleading 4-digit failure totals.
- Adds separate map repair success/attempt counters to saved runs and /trr status output.
- Filters Roach, Rat and Black Rat from future pull NPC lists.

0.1.0-test5j:
- Pins Auchindoun: Sethekk Halls to SethekkHalls by instance identity so WDM map flicker no longer starves party movement samples.
- Ignores Roach critter combat-log noise when constructing pull NPC lists.
- Keeps all test5i recorder behaviour unchanged.

0.1.0-test5j:

- Canonicalizes Coilfang: The Slave Pens to TheSlavePens, preventing WDM Dalaran/TheSlavePens flicker from generating fake map phases and avoidable position failures.
- Keeps the Shadow Labyrinth canonical-map workaround and all previous tank/route recording behaviour.
0.1.0-test5g:

- Version alignment with the Halls of Lightning Heroic curated-route build.
- Recorder schema and capture behaviour are unchanged from test5f; the multi-floor simplification improvement is in the main TriRoutes route processor.

0.1.0-test5f:

- Version alignment with the Nexus Heroic curated-route build; recorder schema and recording behaviour are unchanged from test5e.

0.1.0-test5e:

- Canonicalizes Auchindoun: Shadow Labyrinth to the ShadowLabyrinth map file, preventing WDM VioletHold/ShadowLabyrinth flicker from generating fake map phases.
- Filters friendly pets/guardians from recorded pull NPC lists.

- Version alignment with the Culling curated-route/compact-tooltip build; recorder schema remains compatible.
- Main-addon route processing now understands large in-instance teleport jumps as route breaks.

0.1.0-test5c:
- Version alignment with the Dungeon Finder route-needs dashboard build; recorder schema/behaviour is unchanged.

0.1.0-test5b:
- Version bump accompanying the curated Gundrak Mythic +8 route; recorder schema/behaviour is unchanged.

TriRoutes Recorder 0.1.0-test5p

test5a: version alignment with the Gundrak curated-route build; recorder schema/behaviour is unchanged.

test4z: version alignment with the main addon comparison-overlay build; recorder schema/behaviour is unchanged.

test4y: version alignment with the main addon; recorder schema/behaviour is unchanged.


Raw dungeon/raid telemetry for TriRoutes. Saved separately in:
WTF/Account/<ACCOUNT>/SavedVariables/TriRoutes_Recorder.lua

Test4i additions:
- Logical dungeon sessions. Short map/world transitions, reloads, and reconnects in the same dungeon/difficulty/party continue the same session as a new section.
- Existing recordings are migrated on load. In particular, adjacent legacy recordings can be joined when they match the same dungeon/difficulty/party and are only seconds apart.
- Each new sample records section, map phase, and dungeon floor when the 3.3.5/WDM client exposes it.
- Map transitions are recorded as events with map file, area ID, floor, and phase.
- Basic wipe detection records a wipe when all currently visible party members are dead/ghost.
- Recovery/run-back samples are retained in the raw log but marked recovery=true and are excluded from learned routes. Recovery ends when combat resumes.
- If a wipe/reload causes another loading screen, recovery state can continue into the next section of the same session.

Commands:
/trr status
/trr record
/trr stop
/trr auto on|off
/trr difficulty auto|normal|heroic|mythic
/trr mark <pull|boss|turn|skip|warning|stairs> [note]

0.1.0-test4j: recorder data format unchanged; package version aligned with TriRoutes difficulty-fallback build.

0.1.0-test4k: recorder schema unchanged; package version aligned with built-in curated route pack.

0.1.0-test4l standalone collector:
- Shifty is no longer required or consulted.
- Tank selection uses TriRoutes' built-in main-tank/group-role/combat-target detector.
- Mythic promotion uses TriRoutes' built-in MythicBossTimerUI/active-state detector.
- New tracks use roleSource values such as group-role-api, maintank-assignment, or combat-target-evidence.
- /trr status shows the currently resolved tank, detection source, confidence, and evidence count.
- Existing recorder SavedVariables remain compatible; old Shifty-derived metadata is preserved only as historical data in older runs.

0.1.0-test4m raid collector:
- Stores raidSize/raidMode metadata so 10/25/other raid sizes can be learned separately while remaining compatible fallbacks.
- Raid recordings are lean: player + stable route leader + assigned/inferred tanks, capped by raidTrackLimit (default 6), instead of every raid member every 0.75 sec.
- Combat-log NPC capture still recognizes the full raid roster even when movement tracks are reduced.
- Raid route leader priority: manual /trr routeleader -> raid leader -> explicit main tank -> stable inferred tank -> player fallback.
- /trr routeleader target or /trr routeleader <name> can explicitly choose the movement leader; /trr routeleader auto clears it.
- /trr status reports raid size, route leader, source, track count, and recording policy.


0.1.0-test4n collector hardening:
- Rejects non-string/invalid role API values (including boolean true) instead of recording them as a role.
- Accumulates tank observations across the run; weak one-mob aggro is retained as evidence but is not enough by itself to stamp a track TANK.
- Final preferred dungeon track uses the stable accumulated tank when available.
- Rapid same-group Mythic exit/re-entry sections resume the prior logical session even if the Mythic UI is a fraction of a second late after loading.
- On load, matching adjacent test4m sections can be repaired into one logical session.
- mythicDetected becomes true when a run is promoted to Mythic after recording has already started.

0.1.0-test4o:
- Recorder behaviour/schema are unchanged from test4n; package version is aligned with the Pit of Saron curated-route build.



0.1.0-test4s:
- Package version matched to TriRoutes test4s.
- Recorder/detector behavior is unchanged from test4r.
- Core route pack adds the curated Drak'Tharon Keep Heroic route from Katalyna's stable tank track.

0.1.0-test4r:
- Package version matched to TriRoutes test4r.
- Recorder/detector behavior is unchanged from test4q.
- Core route pack adds the curated Halls of Stone Heroic route with Scuz's walked post-Krystallus connector.

0.1.0-test4q:
- Package version matched to TriRoutes test4q.
- Recorder/detector behavior is unchanged from test4p; test4q adds the curated Drak'Tharon Mythic route to the core route pack.

0.1.0-test4p:
- Recorder behaviour/schema are unchanged from test4o.
- Real test4o recordings validated accumulated tank selection: Grimblade in Forge of Souls and Boogs in Ahn'kahet remained the preferred learned tank tracks even when the live route-leader display later fell back out of combat.


0.1.0-test4u:
- Package version matched to TriRoutes test4u.
- Recorder schema and sampling behavior are unchanged from test4t.
- Mythic tier was already recorded per run; core route curation now preserves that tier when a low-level Mythic recording is intentionally classified as Heroic-compatible.

0.1.0-test4t:
- Package version matched to TriRoutes test4t.
- Recorder/detector behavior is unchanged from test4s.
- Core route selection adds a fixed-route policy for dynamic/random instances such as Violet Hold.

0.1.0-test4v: version sync with TriRoutes Oculus platform-guidance build; recorder schema/behavior unchanged.