0.1.0-test6c wipe/recovery route-visibility hotfix:
- Recorder sectionIndex is now treated as provenance rather than navigation identity.
- Fixes routes/arrow/minimap disappearing after a wipe when PLAYER_ENTERING_WORLD resumes the same dungeon as section 2+.
- Physical route continuity remains governed by dungeon coordinate context, WDM floor/phase, and explicit breakBefore markers.
- Route pack geometry and coverage are unchanged from test6b.

0.1.0-test6b rapid-dungeon recorder split hotfix:
- No route-pack changes from test6a.
- Recorder now separates rapidly chained RDF/dungeon instances after 3 stable observations of a different dungeon identity.

0.1.0-test6a Halls of Lightning +4 Mythic route:
- Adds a separate Halls of Lightning Mythic +4 route from session 12/run 17 using Khorn's 0.95-confidence Death Knight tank trace.
- Discards one pre-instance sample, then processes 621 dungeon tank samples into 116 navigation points with 20 combat anchors and General Bjarngrim, Volkhan, Ionar, and Loken.
- The run reaches 100% enemy forces, records one party death, and needs no teleport reconstruction or artificial route break; its single WDM floor 1 -> 2 transition is preserved normally.
- The existing 123-point Heroic Halls of Lightning route remains unchanged. The Mythic trace consolidates the run into 20 pulls versus 25 on the Heroic recording, preserving Mythic-specific strategy rather than replacing the clean HC navigation route.
- Mythic+ chat/keystone tracking, stateful route progression, Dungeon Finder decoration, and recorder sampling/recovery behaviour are unchanged from test5z.

0.1.0-test5z Blood Furnace +4 and Forge of Souls +1 Mythic routes:
- Adds a separate Blood Furnace Mythic route from session 42/run 68 using Jordvogter's 0.95-confidence Druid tank trace: 629 raw tank samples -> 71 navigation points, 17 combat anchors, The Maker/Broggok/Keli'dan, and no player deaths.
- Adds a separate Forge of Souls Mythic route from session 46/run 72 using Hexxlich's 0.95-confidence Paladin tank trace: one obvious pre-instance coordinate discarded, then 422 raw dungeon samples -> 51 navigation points, 11 combat anchors, Bronjahm/Devourer of Souls, and no player deaths.
- Neither route requires a teleport splice, floor reconstruction, or route break. Existing Heroic routes remain unchanged.
- The rough Blood Furnace +15 and Mechanar +14 recordings remain comparison/strategy evidence only and are not used as default geometry.
- Mythic+ chat/keystone tracker, stateful progression, Dungeon Finder decoration, and recorder sampling/recovery behaviour are unchanged from test5y.

0.1.0-test5y Mythic+ keystone-link rotation evidence:
- Parses displayed [Mythic Keystone: Dungeon +N] links from chat as dungeon-level Mythic+ rotation evidence.
- Keystone links never modify the linking player's Mythic+ Best or per-dungeon completion history.
- Stores highest advertised keystone separately from highest observed completion.
- The existing gold Dungeon Finder rune appears for either completion or linked-keystone evidence; hover text identifies the source(s).
- /troutes mythic distinguishes completed +N from key +N observations; repeated chat-frame delivery is de-duplicated.
- /troutes mythic import accepts either completion announcements or text containing keystone links.
- Routing, route geometry, stateful progression and recorder behaviour are unchanged from test5x.

0.1.0-test5x stateful route progression + optional rejoin support:
- Replaces nearest-waypoint-only progress with a monotonic continuous projection along route segments. A waypoint is considered passed once movement has genuinely progressed onto the following leg; players no longer need to touch every saved point.
- Adds conservative forward re-sync: a substantially later segment must be a strong spatial match, beat the nearby expected geometry (or match an explicit curated rejoin), and persist briefly before progress jumps forward. Progress never rewinds.
- Adds route-level optionalBranches and resyncHints topology metadata. Crossing a branch's rejoin without entering it marks that branch skipped internally; the public GetRouteProgressState() exposes fractional progress, sync state, skipped branches, and pending resync for diagnostics/future UI.
- Halls of Stone is the regression case: the complete test4q route remains canonical, while test5u session 2 (Skorn) is used only to validate the post-Tribunal rejoin that cleanly skips the Maiden of Grief and Krystallus wings. It does not add/replace HC coverage.
- Protects routes that pass near themselves: initial matching favours the earliest plausible segment, and large forward snaps require confirmation. Existing Oculus platform-stage progression remains deliberately ordered and unchanged.
- No route IDs, route geometry, Dungeon Finder coverage, recorder sampling, sticky-tank, or same-tick coordinate recovery behaviour changed.

0.1.0-test5u Steamvault complete Heroic tank route:
- Added Coilfang: The Steamvault Heroic from TriRoutes session 42 using Twoacross's stable Death Knight tank track (0.95 confidence).
- Merges recorder sections 1 and 2 into one continuous route: 609 tank movement samples, 568 accumulated tank observations, and only a ~0.006 normalized-distance / ~6-second section boundary gap.
- Curated to 95 navigation points with 18 combat anchors and all three bosses: Hydromancer Thespia, Mekgineer Steamrigger, and Warlord Kalithresh.
- No teleport reconstruction, wipe splice, or inferred floor transition is required. The tiny section 3 post-run tail is excluded, and the older partial Steamvault session remains diagnostic only.
- Added TheSteamvault recorder canonical aliases. Recorder sampling/recovery behaviour is otherwise unchanged from test5t.

0.1.0-test5t Auchenai Crypts clean Heroic tank route:
- Added Auchenai Crypts Heroic from TriRoutes session 41/run 58. Iso (Paladin) is the stable tank at 0.95 confidence with 371 movement samples and 417 tank observations.
- Curated to 67 navigation points with 16 combat anchors and two real bosses: Shirrak the Dead Watcher and Exarch Maladaar. Tiny/lingering Shirrak combat-log appearances are not duplicated as boss anchors.
- Reconstructed one floor 1 -> floor 2 transition from the recording's sole large in-instance coordinate discontinuity plus saved endMapFloor=2; later recovery-induced floor/phase flicker is ignored.
- Auchenai Heroic evaluation follows the N/H policy: complete clean navigation and boss coverage matter; completion time, pull size, wipes and individual deaths do not reduce route quality.
- Added AuchenaiCrypts recorder canonical aliases. Recorder sampling/recovery behavior is otherwise unchanged from test5s.

0.1.0-test5s Botanica universal Heroic route reconstruction:
- Adds Tempest Keep: The Botanica Heroic from Triumvirate session 39 using only TriRoutes recorder data.
- Keeps Affenfleisch's 0.95-confidence Warrior tank run as the route authority, but reconstructs Warlock-portal skip sections with Bobbymac's continuous 534-sample walking trace; Jessaipa's 502-sample trace cross-checks the reconstruction.
- Produces a 79-point universally walkable route with 12 combat anchors and all five bosses: Commander Sarannis, High Botanist Freywinn, Thorngrin the Tender, Laj, and Warp Splinter.
- Portal teleports are deliberately not encoded into the default HC route, so no Warlock or special ability is required to follow it.
- Adds TheBotanica recorder canonicalization. The validated passive + one same-tick recovery algorithm is otherwise unchanged (906/910 recoveries succeeded in the two useful sections).
- Botanica remains HC-only coverage. Mythic can use the normal HC fallback geometry, but no M marker is awarded from the rough +10 recording without a separate Mythic strategy-quality comparison.

0.1.0-test5r Hellfire Ramparts clean Heroic tank route:
- Adds Hellfire Citadel: Ramparts Heroic from Triumvirate session 33, using only run 44 after the group committed to Heroic.
- Deliberately excludes run 43 staging/backtracking while the party debated Mythic vs Heroic, because run 44 restarts at the entrance and contains the complete clean Heroic path; run 45 is the short post-exit tail and is also excluded.
- Uses Drrudolf's 569-sample Warrior tank track (704 observations, 0.95 confidence), curated to 75 navigation points with 20 combat anchors and Watchkeeper Gargolmar, Omor the Unscarred, and Vazruden + Nazan.
- Records 1100/1128 successful same-tick party-coordinate recoveries through Astrolabe; the validated recovery algorithm itself is unchanged.
- Adds Ramparts canonical map/collection aliases so the route resolves to HellfireRamparts and lights the HC Dungeon Finder marker on the server's `Hellfire Citadel: Ramparts` instance name.

0.1.0-test5q Arcatraz tank route:
- Adds Tempest Keep: The Arcatraz Heroic from Triumvirate session 31/run 41 using Yolosan's 778-sample Paladin tank track (968 tank observations, 0.95 confidence).
- Preserves all 21 combat sections and Zereketh the Unbound, Dalliah the Doomsayer, Wrath-Scryer Soccothrates, and Harbinger Skyriss boss anchors.
- Reconstructs two clear recorded map-level discontinuities as floor 1 -> 2 -> 3, matching the run's final WDM floor 3, and breaks navigation at each level transition rather than drawing impossible cross-floor lines.
- Records test5p recovery provenance: 1680/1723 same-tick recovery attempts succeeded through Astrolabe; the recovery algorithm itself is unchanged.
- Adds TheArcatraz canonical map aliases and filters Defender Corpse, Warder Corpse, and Destroyed Sentinel from future pull-NPC telemetry.

0.1.0-test5p Underbog tank route:
- Adds Coilfang: The Underbog Heroic from Triumvirate session 30/run 39 using Morar's 610-sample Paladin tank track.
- Preserves all 23 combat sections and the Hungarfen, Ghaz'an, Swamplord Musel'ek, and The Black Stalker boss anchors.
- Records the successful test5o diagnostic provenance: 1184/1187 same-tick recovery attempts succeeded through Astrolabe, leaving only 32 unrecovered party-position reads over the complete run.
- Adds TheUnderbog canonical map aliases for navigation/metadata.
- Route generation excludes World Invisible Trigger, Toad, and Maggot from pull counts.
- The test5o single-failure retry strategy is otherwise unchanged.

0.1.0-test5o single-failure party-coordinate diagnostic:
- Main route pack and Dungeon Finder coverage UI are unchanged from test5n.
- Recorder remains passive by default and adds only a one-shot same-tick recovery probe after the first failed party-coordinate read, allowing the next dungeon to show whether the tank can be rescued without persistent WDM map manipulation.
- Steamvault session 29 is intentionally not curated because Scuz joined after the run was already in progress; it is diagnostic evidence only.

0.1.0-test5n Mechanar provisional HC + recorder map-repair rollback:
- Adds first Heroic The Mechanar coverage from session 28/runs 35-36. Chivalry remains the 0.95-confidence stable Druid tank (674 combined observations); the route uses Scuz progress geometry because test5m captured only five total Chivalry movement samples.
- Curates 498 progress samples into 72 navigation points with 9 regular pull anchors and all five bosses: Gatewatcher Gyro-Kill, Mechano-Lord Capacitus, Gatewatcher Iron-Hand, Nethermancer Sepethrea, and Pathaleon the Calculator.
- The release/re-entry recovery path is not used as default geometry. A route break marks the upper-level rejoin; the Nether Charge-only residual combat and the first recovery/run-back combat are intentionally omitted.
- Rolls back only the recorder's aggressive live WDM SetMapToCurrentZone repair/seeding added in test5k-test5m. Dungeon Finder HC/M row markers, compact tooltip, all curated routes, difficulty fallback, comparison overlay, sticky tank identity, sparse-track protection, and separate player/party failure diagnostics are retained.
- Adds passive The Mechanar canonical aliases for stored route/map metadata without manipulating the live World Map.
- Future Mechanar recordings are comparison candidates; a clean tank trace must be compared section-by-section before replacing this provisional route.

0.1.0-test5m Mana-Tombs rescue + sticky tank sampling:
- Adds first Heroic Mana-Tombs coverage from session 27/run 34. Empressd remains the 0.95-confidence stable Death Knight tank (404 observations), while Scuz's coherent 304-sample player trace supplies explicitly provisional geometry because test5l captured only four party-position samples.
- Rescues the route as 304 raw samples -> 53 navigation points with 7 regular pull anchors and boss anchors for Pandemonius, Tavarok, and Nexus-Prince Shaffar. The final outdoor exit coordinate is excluded and bogus Dalaran/ManaTombs map phases are normalized to ManaTombs.
- Adds Mana-Tombs canonical map aliases for live navigation/metrics and the recorder.
- Recorder tank identity is now sticky: once a dungeon tank is learned, temporary unit/position failures no longer demote the route leader to the player/group leader. A genuine replacement requires the old tank to be absent for a grace period plus overwhelming new evidence.
- Known dungeon map pins are re-established immediately before party-coordinate sampling when WDM has reverted to the outdoor map; the stable tank is sampled first. The World Map is still never manipulated while visibly open.
- Sparse tank tracks are separated from tank identity: a four-point tank trace can remain authoritative provenance without overriding a healthy player geometry trace. This applies both when saving recorder runs and when TriRoutes selects raw tracks for analysis.
- Future repeated Mana-Tombs data follows the comparison-first policy; a clean tank trace is compared section-by-section rather than blindly replacing today's rescued route.

0.1.0-test5l Blood Furnace provisional HC route + broader queue-map seeding:
- Adds first Heroic Blood Furnace coverage from session 26/run 33. Twoacross is preserved as the 0.95-confidence stable Death Knight tank (952 observations), while Scuz's 533-sample follower trace supplies provisional geometry because this run was captured on test5j before queue-map recovery and contains no usable party movement samples.
- Preserves all 25 combat sections and The Maker, Broggok, and Keli'dan the Breaker boss anchors. The provisional route keeps a conservative quality score and must be compared against future clean tank traces rather than blindly replaced.
- Adds Blood Furnace canonical map aliases for navigation/metrics and the recorder.
- Recorder queue-map recovery can now seed WDM for previously unseen dungeons too: it performs an initial SetMapToCurrentZone while the World Map is closed and makes a few rate-limited retries only when position probes are failing. Explicit per-dungeon map pins remain authoritative when known.

0.1.0-test5k Shattered Halls provisional HC route + queue-map recovery:
- Added first Heroic Shattered Halls coverage from session 25/run 32. Phoee is preserved as the 0.95-confidence stable Druid tank, while the 817-sample Scuz follower trace supplies provisional geometry because the stale Dalaran map context yielded no usable party movement samples.
- Preserves 38 combat sections and all four observed bosses: Grand Warlock Nethekurse, Blood Guard Porung, Warbringer O'mrogg, and Warchief Kargath Bladefist.
- Adds The Shattered Halls canonical map aliases for live navigation and recorder analysis.
- Repeated recordings remain comparison candidates; provisional routes are not blindly replaced.

0.1.0-test5j Sethekk Halls provisional HC route + map stability:
- Adds first curated Sethekk Halls Normal/Heroic coverage from session 24/run 31.
- Keeps the route explicitly provisional: WDM map flicker left only three tank movement samples, so geometry uses Scuz's continuous 502-sample follower trace while Sintrapal's 583 tank observations establish the intended tank-led run.
- Preserves all 19 combat anchors and the observed Darkweaver Syth / Talon King Ikiss boss anchors; obvious Roach critter noise is excluded from pull counts.
- Pins Auchindoun: Sethekk Halls to SethekkHalls by instance identity in both live navigation and the recorder, preventing Dalaran/Sethekk map flicker from corrupting future traces.
- Future clean Sethekk recordings should be compared section-by-section; this route has a deliberately conservative quality score so a validated tank trace can supersede it without blindly replacing unrelated curated data.

0.1.0-test5j repeated-route comparison + Slave Pens map stability:
- Repeated dungeon recordings are curated analytically rather than blindly replacing an existing route: compare section-by-section, retain safer established geometry, and only adopt compatible improvements.
- Re-analysed the new Slave Pens Heroic session 22/test5h recording. Its major time saving used a Mage Slow Fall shortcut and aggressive chain-pulling, so the existing safe default route remains authoritative.
- Stores the Mennu -> Rokmar Slow Fall line as disabled conditional-alternative metadata for future optional-route support; it is NOT used by normal navigation.
- Pins Coilfang: The Slave Pens to TheSlavePens by instance identity, preventing WDM Dalaran/TheSlavePens/Dalaran flicker from corrupting recorder phases or live route map selection.

0.1.0-test5h Dungeon Finder coverage markers + compact route-status tooltip:

- Specific Dungeon rows now show routes TriRoutes already HAS: `HC` for Normal/Heroic-compatible coverage, `M` for a dedicated Mythic route, `HC M` for both, and no marker when neither exists.
- Removed the repeated `TR` prefix from every decorated dungeon row.
- Hovering any tracked dungeon now appends one compact status line using Blizzard ready-check icons: `HC [tick/cross]  Mythic(+tier) [tick/cross]`.
- Mythic tier is shown only when the curated Mythic route has reliable recorded tier metadata. Nexus and Drak'Tharon are now explicitly tagged +4; Gundrak already carries +8. Routes with no reliable tier still display simply as `Mythic`.
- The Dungeon Finder summary now reports bundled coverage (`HC` and `M` routes present) instead of remaining-route counts.
- No navigation geometry, difficulty fallback, comparison overlay, recorder schema, WDM handling, or route-processing behaviour changed in this UI-focused build.

0.1.0-test5g Halls of Lightning Heroic route + multi-floor simplification:

- Added a curated Halls of Lightning Normal/Heroic route from session 21/run 27 using Midget's stable Paladin tank track.
- 781 raw tank samples process to 123 navigation points with 25 combat anchors and all four observed bosses: General Bjarngrim, Volkhan, Ionar, and Loken.
- The curated route spans both WDM dungeon floors and ignores the transient route-leader fallback that occurred while the party was leaving the instance.
- RouteProcessor now treats WDM floor/phase/section changes as hard simplification boundaries, preventing a combat that crosses floors from forcing every intermediate sample into the final route.
- Retains Nexus N/H + Mythic comparison data, Culling teleport-skip handling, Shadow Labyrinth map normalization, friendly-pet filtering, Dungeon Finder route-needs markers, and compact tooltip.

0.1.0-test5f Nexus Heroic route:

- Added a curated The Nexus Normal/Heroic route from session 20 using Tymone's stable Death Knight tank track.
- 583 raw movement samples process down to 62 navigation points with 21 combat anchors and 4 boss anchors.
- Observed full boss set: Grand Magus Telestra, Anomalus, Ormorok the Tree-Shaper, and Keristrasza.
- The Nexus now has independent N/H and Mythic curated routes, enabling comparison overlay in both directions without relying on difficulty fallback.
- Retains the Culling teleport-skip handling, Shadow Labyrinth WDM map normalization, friendly-pet filtering, Dungeon Finder route-needs markers, and compact tooltip from test5e.

0.1.0-test5e Shadow Labyrinth route + WDM map identity fix:

- Added a curated Shadow Labyrinth Normal/Heroic route from session 19 using Saint's stable Paladin tank track.
- Normalizes the WDM ShadowLabyrinth/VioletHold map-file flicker to ShadowLabyrinth for navigation and map metrics.
- Recorder now applies the same canonical map identity so this flicker no longer creates hundreds of fake map phases.
- Friendly combat pets/guardians are ignored when building pull NPC lists.
- Retains the compact Dungeon Finder route-needs tooltip and Culling teleport-skip route from test5d.

- Adds The Culling of Stratholme as a curated Normal/Heroic-compatible route from session 18/run 23, using Harmburger's stable Druid tank movement.
- Preserves the server's in-dungeon teleport-NPC skip as a route break instead of drawing an impossible straight line across the map.
- Adds five observed boss anchors: Meathook, Salramm the Fleshcrafter, Chrono-Lord Epoch, Infinite Corruptor, and Mal'Ganis.
- The general route processor now treats an implausible >=0.20 same-map movement jump as a teleport break for future recordings.
- Dungeon Finder route-need markers/icons are unchanged; their hover tooltip is reduced to a two-line TriRoutes + missing-route status.
- Culling's N/H collection marker now disappears because compatible curated data is bundled.

0.1.0-test5c Dungeon Finder route-needs dashboard:
- Decorates Blizzard's stock 3.3.5 Specific Dungeons rows instead of replacing or reordering Dungeon Finder.
- Missing standard-route data is marked `TR N/H`; confirmed missing Mythic data is marked `TR M`; both can appear together.
- Markers are calculated from the bundled curated route pack, so a need disappears automatically when its route is added.
- Mythic markers are only shown for dungeons already confirmed to support Mythic on Triumvirate; unknown Mythic eligibility stays hidden.
- Hovering a marked row explains exactly what TriRoutes still needs.
- A compact footer reports the global remaining N/H and confirmed Mythic counts.
- `/troutes needs on|off` toggles the Dungeon Finder decorations.
- Existing queue checkboxes, locks, ordering, scrolling, route navigation, WDM handling and recorder schema are unchanged.

0.1.0-test5b Gundrak Mythic +8 route:
- Adds a curated Mythic +8 Gundrak route from session 17, using Boog's stable Paladin tank track.
- Preserves the distinct Mythic boss order: Moorabi -> Eck the Ferocious -> Drakkari Colossus -> Slad'ran -> Gal'darah.
- Removes the failed Slad'ran wipe/recovery from section 1 and splices into the successful Slad'ran kill from section 2 before continuing to Gal'darah.
- The curated route remains the preferred Mythic route until a future recording is demonstrably better; the existing +5/+other raw runs do not replace it merely for being newer.
- This gives Gundrak both Heroic and Mythic curated routes, enabling the N/H <-> Mythic comparison overlay in both directions.
- No minimap/WDM live-context, arrow, overlay rendering, difficulty fallback, or recorder schema behaviour is changed.

TriRoutes 0.1.0-test5p

test5a Gundrak Heroic route:
- Adds Gundrak as a curated Heroic route from session 15/run 17.
- Uses Aetharra, the stable Paladin tank, as the preferred geometry source (650 raw samples).
- Processes the tank trace to 90 navigation points with 11 combat anchors and five observed boss anchors: Slad'ran, Drakkari Colossus, Moorabi, Eck the Ferocious, and Gal'darah.
- The run had 14 position failures, one stable WDM floor, and no full wipe/recovery path to remove.
- Keeps the test4z Normal/Heroic <-> Mythic comparison-overlay system and the known-good test4x WDM live-context/minimap behaviour unchanged.

test4z N/H <-> Mythic comparison overlay:
- When a useful curated route exists for both route families, the route for the difficulty you are actually running remains the primary navigation route.
- Normal/Heroic navigation can ghost a curated Mythic route; Mythic navigation can ghost the curated Normal/Heroic counterpart.
- The secondary route is line-only: it never owns NEXT distance, waypoint dots, route progression, or the directional arrow.
- Mythic comparison lines are warm gold and Normal/Heroic comparison lines are green. Segments that overlap the primary route are intentionally very faint; divergences become much more visible.
- The main route is rendered after the comparison route, so the authoritative blue/purple route stays visually dominant at crossings.
- /troutes overlay on|off controls comparison rendering and defaults to ON. /troutes status reports the selected comparison route.
- Mythic runs that are already using a Normal/Heroic fallback do not get a redundant comparison overlay.
- Violet Hold fixed routes remain excluded from comparison. Oculus platform routes only compare against another platform-policy route, never a raw 3D flight trace.
- Preserves the known-good test4x WDM live-context/minimap coexistence behaviour and the previously curated route geometries unchanged.

test4y Slave Pens tighter Normal/Heroic route:
- Adds Coilfang: The Slave Pens as a curated Heroic-compatible route, which also supplies the normal fallback path.
- Compared two same-party recordings of the same standard route: Mythic +8 and Mythic +1. The +1 movement trace was selected because its coarse travel path was about 6% tighter overall, with the largest reduction in the Rokmar -> Quagmirran section.
- Both recordings identified Jordvogter as the stable Druid tank. Only Scuz had a complete movement track, so route geometry is curated from Scuz's movement while retaining Jordvogter as provenance for the party route.
- The selected +1 trace processes 523 raw samples -> 72 navigation points with 16 combat anchors and observed boss anchors for Mennu the Betrayer, Rokmar the Crackler, and Quagmirran.
- The route remains deliberately classified as Heroic-compatible even though its selected source was Mythic +1; the +8 trace corroborates the same basic route. mythicTierAsHeroicMax=8 prevents these known basic M1-M8 traces from being treated as the dedicated Mythic route.
- Preserves the known-good test4x WDM live-context/minimap coexistence fixes unchanged.


test4x minimap live-context fix:
- REC is only the recorder/logger indicator; a loaded saved route remains navigation-active at the same time.
- Restored WDM c=-1 player points now canonicalise the transient Astrolabe zone index to z=0, matching curated route coordinates after reloads/transitions.
- Single-floor restored maps (including Ahn\'kahet) canonicalise the live floor to the only bundled WDM floor, preventing a temporary recorder/map-floor probe from suppressing minimap route lines and NEXT distance while the arrow still works.
- No curated route geometry, world-map rendering, arrow heading, recorder schema, or difficulty selection changed.
======================

Changes from test4d
- Main world-map route renderer is unchanged; the working WDM-local A->B->C overlay remains intact.
- TriRoutes now bundles the dungeon/raid map dimensions needed to turn WDM-local 0..1 coordinates into yards. The WDM MPQ can therefore be used without a separately loaded WDM or LibMapData-1.0 addon.
- Stockades and the other bundled 3.3.5 dungeon/raid maps can use the local minimap renderer even when /troutes status says the WDM addon and LibMapData are not loaded.
- The minimap local renderer always uses indoor minimap radii for C-1 restored instance coordinates instead of trusting Astrolabe's unsupported c=-1 outside/inside flag.
- Questie navigation lookup now mirrors Questie's own fallback path (QuestieCompat first, then HereBeDragons LibStub libraries).
- Removed the 26px map/target icon that was sitting over the TriRoutes directional atlas; the HUD now shows the clean cyan directional arrow itself.
- Real bundled map dimensions also replace the old emergency normalized-distance fallback, so values such as a bogus 183 yd first Stockades pull should become sensible yard distances.
- /troutes status now prints the raw map file/area/floor probe and the selected map-metric source.

Commands
/troutes status
/troutes refresh
/troutes map on|off
/troutes minimap on|off
/troutes overlay on|off
/troutes trail on|off
/troutes process on|off
/troutes arrow on|off|reset|lock|unlock
/troutes arrow scale 1.15


test4f route progression colours:
- Dim blue: completed/behind route.
- Bright blue: current leg through the next pull/boss/finish landmark.
- Purple: later/upcoming route.
- Minimap now draws the full saved route and clips it to the visible minimap, so later branches that pass nearby remain visible.


TEST4G: Minimap scaling now follows Astrolabe's actual indoor/outdoor zoom state instead of forcing WDM C-1 maps to indoor. Use /troutes miniscale auto|indoor|outdoor for diagnostics/override.


test4h: fixes WDM-restored maps reporting a misleading numeric area ID. TriRoutes now trusts the explicit map file / instance name before area ID when choosing dungeon yard dimensions.

0.1.0-test4i
- Adds dungeon-session aggregation: multiple recorded sections from the same run can be processed as one route.
- Route points carry section/map-phase context so separate floors/sections are not connected by false straight lines.
- Current map/minimap/arrow navigation follows the matching live section.
- Recovery/run-back samples marked by the recorder are ignored by route processing.
- Legacy adjacent recordings are compatible with the new session model after recorder migration.

Difficulty fallback (test4j):
- Normal: prefer Normal, then Heroic.
- Heroic: prefer Heroic, then Normal.
- Mythic: always prefer Mythic; if none exists, use the highest-quality Heroic/Normal route.
- Route quality only competes inside the highest available compatibility tier.
- /troutes status reports requested difficulty, route difficulty, and exact/fallback state.


Built-in curated routes (test4k):
- Stormwind Stockade: Normal (Scuz full route; five named encounter anchors).
- Azjol-Nerub: Heroic (Holorder Protection Paladin tank route; two recorded sections; Krik'thir, Hadronox, Anub'arak anchors).
- Utgarde Pinnacle: Heroic (Morar Protection Paladin tank route; floor-aware; Svala, Gortok, Skadi, Ymiron anchors).
- Only processed route points are bundled; raw recorder telemetry remains in TriRoutes_Recorder SavedVariables.
- Built-in and recorder candidates share the test4j difficulty fallback policy. Difficulty tier wins first, then quality; exact ties prefer the curated built-in copy.
- Built-in floor-aware routes use WDM floor identity rather than recorder-local phase numbering.

0.1.0-test4l standalone detection:
- Shifty is no longer an optional dependency and TriRoutes does not call Shifty APIs.
- Adds a self-contained tank resolver using main-tank assignments, group roles, and stable combat-target evidence.
- Combat inference watches hostile targets held by party members and suppresses rapid tank switching during brief aggro swaps.
- Adds a self-contained Triumvirate Mythic detector using the live MythicBossTimerUI plus active MythicPlusCharRunState restoration data.
- /troutes status reports the standalone tank detector when it has resolved a tank.
- Existing built-in routes, difficulty fallbacks, WDM map/minimap rendering, sessions, floors, and wipe recovery are unchanged.

0.1.0-test4m raid-aware routing:
- Raids now carry an explicit raidSize in route context and recorder metadata.
- Raid route fallback prefers exact difficulty + exact size, then the same difficulty at another size, then compatible fallback difficulty. Example: 25 Heroic -> other-size Heroic -> 25 Normal -> other-size Normal.
- Dungeon Normal/Heroic/Mythic fallback is unchanged.
- Raid learned routes prefer the recorder's stable route-leader track rather than whichever tank currently has aggro during a tank swap.
- /troutes status reports requested/selected raid size and whether the size match is exact or fallback.


0.1.0-test4n Nexus + standalone hardening:
- Adds a built-in Mythic The Nexus route from Wachapiola's confirmed Druid tank movement (590 raw samples -> 72 navigation points).
- The curated Nexus route has four named boss anchors: Grand Magus Telestra, Anomalus, Ormorok the Tree-Shaper, and Keristrasza.
- The intentional post-Ormorok shortcut is preserved as two route sections: WARNING "Teleport out and re-enter" then SKIP "Re-enter at Nexus entrance". No false line is drawn across the teleport.
- Weak one-enemy combat-target observations no longer instantly establish a tank; single-target inference must persist before being trusted.
- Recorder role values are validated so a 3.3.5 boolean `true` cannot be stored as a group role.
- Recorder accumulates tank evidence across the run and prefers the stable tank track when enough evidence exists.
- Rapid Mythic teleport/re-entry can resume the prior session even while the stock client briefly reports Heroic before the Mythic timer returns.
- Existing adjacent test4m sections matching the same dungeon/difficulty/group can be repaired into one logical session on load.
- Mythic promotion now also updates the run-level mythicDetected flag.
- Same-tier recorder candidates now need to beat a curated built-in route by more than 5,000 quality points before replacing it, so a slightly noisier raw run cannot silently displace an absorbed route.

0.1.0-test4o Pit of Saron route:
- Adds a built-in Heroic Pit of Saron route from Kaylessara's manually confirmed Paladin tank movement (547 raw samples -> 56 navigation points).
- The legacy test4m preferred-track result is deliberately ignored; Kaylessara is the authoritative curated movement source.
- Adds three named encounter anchors from the observed recording: Ick / Krick, Forgemaster Garfrost, and Scourgelord Tyrannus / Rimefang.
- The first legacy combat window contained both Ick/Krick and Garfrost, so named boss anchors are placed by their observed first-event times instead of assuming one combat window equals one encounter.
- No recorder schema or navigation-rendering behaviour changed from test4n.



0.1.0-test4s Drak'Tharon Heroic route:
- Adds a curated Heroic Drak'Tharon Keep route from recorder run 8.
- Uses Katalyna's automatically selected stable Warrior tank track (1015 accumulated tank observations, 0.95 confidence).
- Includes observed Trollgore, Novos the Summoner, King Dred, and The Prophet Tharon'ja anchors.
- Preserves the two WDM floors captured by the run.
- Katalyna briefly died near Tharon'ja and was resurrected; there was no wipe/recovery section, so the normal route remains continuous.
- No map/minimap/arrow, difficulty, tank-detection, or recorder behavior changed from test4r.

0.1.0-test4r Halls of Stone Heroic route:
- Adds a curated Halls of Stone Heroic route from recorder run 7.
- Legendairy (Warrior) remains the authoritative tank path for the dungeon.
- After Krystallus, the route deliberately switches to Scuz's continuous walked path until the next pull, avoiding the party members' teleport-out/re-entry shortcut.
- The route rejoins Legendairy at the next combat.
- Observed named boss anchors: Maiden of Grief, Krystallus, Sjonnir the Ironshaper.
- No changes to map/minimap/arrow, difficulty detection, tank detection, or recorder behavior.

0.1.0-test4q Drak'Tharon Mythic route:
- Added a curated Drak'Tharon Keep Mythic tier 4 route from the test4p recorder run.
- Uses Selmac's automatically selected stable tank track (1067 accumulated tank observations).
- Includes observed Trollgore, Novos the Summoner, King Dred, and The Prophet Tharon'ja anchors.
- Preserves the two WDM floors captured in the run.
- No detector/navigation rendering behavior changed from test4p.

0.1.0-test4p Forge of Souls + Ahn'kahet routes:
- Adds a built-in Heroic The Forge of Souls route from Grimblade's test4o Warrior tank movement (472 raw samples -> 60 navigation points).
- test4o's accumulated tank detector strongly resolved Grimblade (score 694.44 across 687 observations) and kept him as the final preferred track.
- Adds observed Bronjahm and Devourer of Souls boss anchors.
- Adds a built-in Heroic Ahn'kahet: The Old Kingdom route from Boogs' test4o Druid tank movement (534 raw samples -> 91 navigation points).
- Boogs remained the preferred track despite the live route-leader display falling back to the group leader after the final combat; accumulated tank evidence was overwhelming (score 605.90 across 579 observations).
- Adds observed Elder Nadox, Prince Taldaram, and Herald Volazj anchors. No unobserved Jedoga/Amanitar boss anchor is invented.
- These two recordings are the first bundled routes curated from the hardened standalone accumulated-tank detector rather than a manually corrected legacy tank choice.
- Recorder schema/navigation rendering remain unchanged from test4o.

0.1.0-test4u Utgarde Keep M+1 classified as Heroic-compatible:
- Adds a curated Utgarde Keep route from the test4t Mythic +1 recording, using Theros's stable Death Knight tank movement.
- The route is intentionally stored as Heroic-compatible because the +1 run followed the basic dungeon path without meaningful Mythic routing differences.
- Retains recordedDifficultyKey=mythic, recordedMythicTier=1, and recordedMythicSource=timer-ui in the curated route metadata.
- Adds mythicTierAsHeroicMax=1 for Utgarde Keep so raw M+1 recorder traces are not selected as representative Mythic routes at higher Mythic levels.
- A later Mythic +2 or higher recording remains eligible as an exact Mythic candidate and can supersede the Heroic fallback when appropriate.
- /troutes status now reports when a curated route originated from a Mythic recording but was deliberately classified as a lower difficulty.

0.1.0-test4t Violet Hold static start route:
- Adds fixed start-only routes for Violet Hold Heroic and Mythic.
- Uses Scuz's observed Heroic entrance walk to the stable pre-portal staging point (6 compact points).
- Navigation intentionally ends there; Violet Hold portal positions/order are random and are not treated as a learnable route.
- Adds routePolicy=fixed so recorder traces from random portal sequences cannot displace these curated routes.
- Mythic uses the same start geometry by design.


0.1.0-test4v The Oculus Heroic platform guidance:
- Adds a curated Heroic The Oculus route from recorder run 11 using Chivalry's stable Druid tank track (579 accumulated tank observations, 0.95 confidence).
- Keeps the reliable ground route through Drakos the Interrogator and the drake pickup.
- Adds routePolicy=platform for the flying portion: TriRoutes advances through ordered major destinations instead of reproducing literal 3D flight movement.
- Platform targets cover Varos Cloudstrider, three Mage-Lord Urom staging platforms, Mage-Lord Urom, and Ley-Guardian Eregos.
- The recorder's 113 position failures and rapid WDM floor changes are retained only as provenance; they are deliberately not converted into route lines.
- breakBefore platform points prevent impossible straight route lines across flight gaps on the world map and minimap.
- Platform navigation becomes sequential after the drake pickup, preventing 2D proximity from skipping ahead to a later platform.
- When the client is reporting a different Oculus floor than the next destination, the arrow hides rather than presenting a false 2D direction; the HUD names the next flight destination until that floor becomes usable.
- routePolicy=platform is protected from replacement by a higher-scoring raw recorder trace, like the existing fixed Violet Hold policy.

TEST4W: Minimap renderer coexistence fix
- Fixes saved route lines disappearing on the minimap while TriRoutes_Recorder is actively collecting a live breadcrumb.
- On restored WDM dungeon coordinates, the saved route and live breadcrumb now both use the WDM-local renderer.
- This avoids Questie HBDPins clearing the shared minimap line pool and leaving only the recording trail visible.
- World-map, arrow, route selection, difficulty logic, curated routes, and recorder schema are unchanged.

0.1.0-test5x Mythic+ chat tracker
- Passively parses Triumvirate [Mythic+] completion announcements.
- Stores each observed player's overall and per-dungeon Mythic+ completion best.
- Stores observed Mythic+ rotation dungeons independently from HC/M route coverage.
- Specific Dungeons rows show a small gold rune for observed Mythic+ rotation entries.
- Player tooltips and the native InspectFrame show Mythic+ Best when known.
- /troutes mythic lists observed rotation; /troutes mythic <player> shows history.
- /troutes mythic resetrotation clears rotation observations but preserves player bests.
- Exposes TriRoutesAPI.GetMythicProfile/GetMythicRotationEntry(s) for TriAudit.
