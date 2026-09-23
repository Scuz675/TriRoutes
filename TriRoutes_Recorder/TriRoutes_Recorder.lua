-- TriRoutes Recorder 0.1.0-test6c
-- Raw telemetry is deliberately stored in this addon's own SavedVariables file:
-- WTF/.../SavedVariables/TriRoutes_Recorder.lua

local VERSION = "0.1.0-test6c"

TriRoutesRecorderRuntime = TriRoutesRecorderRuntime or {}
local RT = TriRoutesRecorderRuntime

local lower = string.lower
local find = string.find
local format = string.format
local tinsert = table.insert
local tremove = table.remove
local max = math.max

local DEFAULTS = {
    schema = 4,
    settings = {
        autoRecord = true,
        sampleInterval = 0.75,
        heartbeat = 4.0,
        movementThreshold = 0.0015,
        difficulty = "auto", -- auto, normal, heroic, mythic
        maxRuns = 60,
        recordParty = true,
        -- Raids can contain 10-40 players. Recording every movement track makes
        -- SavedVariables grow rapidly, so raids keep the player plus a small
        -- route-leader/tank cohort. Dungeons still record the full party.
        raidTrackLimit = 6,
        sessionResumeSeconds = 45,
        -- A real dungeon change can occur before the 45-second resume window expires
        -- (for example rapid RDF chains). Require several consecutive observations
        -- of the new dungeon before splitting so one-frame WDM/API glitches do not.
        dungeonSplitConfirmSamples = 3,
    },
    runs = {},
}

local db
local currentRun
local currentCombat
local sampleElapsed = 0
local manualPausedUntilLeave = false
local groupGUIDs = {}
local seenBoss = {}
local deathState = {}
local recoveryActive = false
local wipeMarked = false
local currentMapSignature
local manualRouteLeaderGUID
local manualRouteLeaderName
local dungeonTransitionCandidateKey
local dungeonTransitionCandidateName
local dungeonTransitionCandidateMapFile
local dungeonTransitionCandidateCount = 0
local dungeonTransitionCandidateFirstClock

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end


local INSTANCE_MAPFILE_OVERRIDES = {
    ["auchindounshadowlabyrinth"] = "ShadowLabyrinth",
    ["auchindounsethekkhalls"] = "SethekkHalls",
    ["sethekkhalls"] = "SethekkHalls",
    ["coilfangtheslavepens"] = "TheSlavePens",
    ["coilfangreservoirtheslavepens"] = "TheSlavePens",
    ["hellfirecitadelramparts"] = "HellfireRamparts",
    ["hellfireramparts"] = "HellfireRamparts",
    ["hellfirecitadeltheshatteredhalls"] = "TheShatteredHalls",
    ["theshatteredhalls"] = "TheShatteredHalls",
    ["shatteredhalls"] = "TheShatteredHalls",
    ["hellfirecitadelthebloodfurnace"] = "TheBloodFurnace",
    ["thebloodfurnace"] = "TheBloodFurnace",
    ["bloodfurnace"] = "TheBloodFurnace",
    ["auchindounmanatombs"] = "ManaTombs",
    ["manatombs"] = "ManaTombs",
    ["tempestkeepthemechanar"] = "TheMechanar",
    ["themechanar"] = "TheMechanar",
    ["mechanar"] = "TheMechanar",
    ["coilfangtheunderbog"] = "TheUnderbog",
    ["coilfangreservoirtheunderbog"] = "TheUnderbog",
    ["theunderbog"] = "TheUnderbog",
    ["underbog"] = "TheUnderbog",
    ["coilfangthesteamvault"] = "TheSteamvault",
    ["coilfangreservoirthesteamvault"] = "TheSteamvault",
    ["thesteamvault"] = "TheSteamvault",
    ["steamvault"] = "TheSteamvault",
    ["tempestkeepthearcatraz"] = "TheArcatraz",
    ["thearcatraz"] = "TheArcatraz",
    ["arcatraz"] = "TheArcatraz",
    ["tempestkeepthebotanica"] = "TheBotanica",
    ["thebotanica"] = "TheBotanica",
    ["botanica"] = "TheBotanica",
    ["auchindounauchenaicrypts"] = "AuchenaiCrypts",
    ["auchenaicrypts"] = "AuchenaiCrypts",
    ["auchenai"] = "AuchenaiCrypts",
}

local function NormalizeInstanceKey(name)
    name = string.lower(tostring(name or ""))
    return string.gsub(name, "[^%a%d]", "")
end

local function CanonicalRecorderMapFile(rawFile)
    local instanceName = GetInstanceInfo and GetInstanceInfo() or nil
    local override = INSTANCE_MAPFILE_OVERRIDES[NormalizeInstanceKey(instanceName)]
    return override or rawFile
end

local function ResetDungeonTransitionCandidate()
    dungeonTransitionCandidateKey = nil
    dungeonTransitionCandidateName = nil
    dungeonTransitionCandidateMapFile = nil
    dungeonTransitionCandidateCount = 0
    dungeonTransitionCandidateFirstClock = nil
end

local function IsKnownDungeonMapFile(mapFile)
    if not mapFile or mapFile == "" then return false end

    -- Any map file already curated by TriRoutes is a recognised dungeon map.
    -- The recorder depends on TriRoutes, so this remains in sync with new route packs.
    local pack = rawget(_G, "TriRoutesBuiltInRoutes")
    if type(pack) == "table" then
        for _, route in pairs(pack) do
            if type(route) == "table" and route.mapFile == mapFile then return true end
        end
    end

    -- Also accept canonical map files known by the recorder even before a route
    -- has been curated for them.
    for _, canonical in pairs(INSTANCE_MAPFILE_OVERRIDES) do
        if canonical == mapFile then return true end
    end
    return false
end

-- test5o keeps passive map sampling as the default.  Instance-name
-- canonicalization remains for stored metadata/navigation.  The only live-map
-- change permitted by the recorder is the single same-tick diagnostic retry
-- after a party coordinate read has already failed; there is no startup seed,
-- loop, or persistent map maintenance.

local function GetMapSnapshot()
    local file = GetMapInfo and CanonicalRecorderMapFile(GetMapInfo()) or nil
    local area = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
    local floor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or nil
    return {file = file, area = area, floor = floor}
end

local function MapSignature(m)
    if not m then return "?:?" end
    -- WDM area IDs can be misleading (Stockades reported Gnomeregan's area ID),
    -- so section/floor identity follows the map file and dungeon floor first.
    if m.file then return tostring(m.file) .. ":" .. tostring(m.floor or "?") end
    return tostring(m.area or "?") .. ":" .. tostring(m.floor or "?")
end

local function CurrentPartySignature()
    local guids = {}
    local function add(unit)
        if UnitExists(unit) then
            local g = UnitGUID(unit)
            if g then guids[#guids + 1] = g end
        end
    end
    add("player")
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do add("raid" .. i) end
    else
        local n = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, n do add("party" .. i) end
    end
    table.sort(guids)
    return table.concat(guids, "|")
end

local function RunPartySignature(run)
    if run and run.partySignature and run.partySignature ~= "" then return run.partySignature end
    local guids = {}
    for g, tr in pairs(run and run.tracks or {}) do
        if tr and tr.name then guids[#guids + 1] = g end
    end
    table.sort(guids)
    return table.concat(guids, "|")
end

local function SameDifficultyForResume(last, ctx)
    if not last or not ctx then return false end
    if last.difficultyKey == ctx.difficultyKey then return true end
    -- Triumvirate exposes Mythic dungeons through the stock Heroic instance ID.
    -- Immediately after a teleport/re-entry the Mythic timer can take a fraction
    -- of a second to reappear, so allow the previous Mythic session to resume
    -- while the new section is still temporarily reported as Heroic.
    if db and db.settings and db.settings.difficulty == "auto"
        and last.instanceType == "party" and ctx.instanceType == "party"
        and last.difficultyKey == "mythic" and ctx.difficultyKey == "heroic" then
        return true
    end
    return false
end

local function SamePartySignature(a, b)
    if not a or not b or a == "" or b == "" then return false end
    if a == b then return true end
    local function count(sig)
        local n=0
        for _ in string.gmatch(sig, "[^|]+") do n=n+1 end
        return n
    end
    -- During PLAYER_ENTERING_WORLD the party roster can briefly collapse to
    -- just the player. Within the short resume window, treat that as compatible
    -- with the previous full roster so floor transitions stay one session.
    if count(a) == 1 and string.find("|"..b.."|", "|"..a.."|", 1, true) then return true end
    if count(b) == 1 and string.find("|"..a.."|", "|"..b.."|", 1, true) then return true end
    return false
end

local function AllocateSessionId()
    local id = db.nextSessionId or 1
    db.nextSessionId = id + 1
    return id
end

local function IsTransitionReason(reason)
    -- A short /reload or reconnect inside the same dungeon should also resume
    -- the same logical session instead of creating a new learned route.
    return reason == "PLAYER_ENTERING_WORLD" or reason == "ZONE_CHANGED_NEW_AREA" or reason == "logout_or_reload"
end

local function MigrateSessions()
    db.nextSessionId = tonumber(db.nextSessionId) or 1
    local prev
    for i = 1, #(db.runs or {}) do
        local run = db.runs[i]
        if run then
            run.partySignature = run.partySignature or RunPartySignature(run)
            if run.instanceType == "raid" and not run.raidSize then
                run.raidSize = tonumber(run.maxPlayers)
            end
            if run.instanceType == "raid" and run.raidSize and not run.raidMode then
                run.raidMode = tostring(run.raidSize) .. "-" .. tostring(run.difficultyKey or "normal")
            end
            if not run.sessionId then
                local join = false
                if prev and prev.sessionId and prev.endedAt and run.startedAt
                    and prev.instanceName == run.instanceName and prev.difficultyKey == run.difficultyKey
                    and IsTransitionReason(prev.reasonEnded) then
                    local gap = run.startedAt - prev.endedAt
                    if gap >= 0 and gap <= 30 then
                        local ps, rs = RunPartySignature(prev), RunPartySignature(run)
                        join = SamePartySignature(ps, rs)
                    end
                end
                if join then
                    run.sessionId = prev.sessionId
                    run.sectionIndex = (prev.sectionIndex or 1) + 1
                    run.continuedFromRunId = prev.id
                    run.sessionTransition = "legacy-map-or-world-transition"
                else
                    run.sessionId = AllocateSessionId()
                    run.sectionIndex = 1
                end
            else
                if run.sessionId >= db.nextSessionId then db.nextSessionId = run.sessionId + 1 end
                run.sectionIndex = run.sectionIndex or 1
            end

            -- Repair sections written by test4m when a rapid Mythic teleport/re-entry
            -- started while the roster/timer were still repopulating.  If the prior
            -- section ended on a world transition and the same group resumed the same
            -- dungeon/difficulty within the configured window, it is one session.
            if prev and prev.endedAt and run.startedAt and prev.sessionId ~= run.sessionId
                and prev.instanceName == run.instanceName and prev.difficultyKey == run.difficultyKey
                and IsTransitionReason(prev.reasonEnded) then
                local gap = run.startedAt - prev.endedAt
                local resume = tonumber(db.settings and db.settings.sessionResumeSeconds) or 45
                if gap >= 0 and gap <= resume and SamePartySignature(RunPartySignature(prev), RunPartySignature(run)) then
                    run.sessionId = prev.sessionId
                    run.sectionIndex = (prev.sectionIndex or 1) + 1
                    run.continuedFromRunId = prev.id
                    run.sessionTransition = "repaired-map-or-world-transition"
                end
            end
            prev = run
        end
    end
    db.schema = 4
end

local function Chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff65D7FFTriRoutes Recorder:|r " .. tostring(msg))
    end
end

local function GetStandaloneMythicContext()
    if not TriRoutes or type(TriRoutes.GetMythicPlusContext) ~= "function" then return nil end
    local ok, ctx = pcall(TriRoutes.GetMythicPlusContext, true)
    if ok and type(ctx) == "table" then return ctx end
    return nil
end

local function NormalizeDifficulty(instanceType, difficultyIndex, difficultyName, mythic)
    local forced = db and db.settings and db.settings.difficulty or "auto"
    if forced and forced ~= "auto" then return forced, "manual" end

    -- TriRoutes carries its own Triumvirate Mythic bridge. Prefer live
    -- MythicBossTimerUI/active character-state evidence over stock 3.3.5 IDs.
    if mythic and mythic.active and mythic.inInstance
        and (mythic.instanceType == "party" or instanceType == "party") then
        return "mythic", "triroutes-mythic"
    end

    local n = lower(tostring(difficultyName or ""))
    if find(n, "mythic", 1, true) then return "mythic", "instance-name" end
    if find(n, "heroic", 1, true) then return "heroic", "instance-api" end
    if find(n, "normal", 1, true) then return "normal", "instance-api" end

    local idx = tonumber(difficultyIndex)
    if instanceType == "party" and idx == 2 then return "heroic", "instance-api" end
    -- 3.3.5 raid difficulty IDs: 3/4 normal 10/25, 5/6 heroic 10/25.
    -- Custom cores may still provide useful difficultyName text above, so these
    -- IDs are intentionally only a fallback.
    if instanceType == "raid" and (idx == 5 or idx == 6) then return "heroic", "instance-api" end
    if instanceType == "raid" and (idx == 3 or idx == 4) then return "normal", "instance-api" end
    return "normal", "instance-api"
end

local function NormalizeRaidSize(instanceType, maxPlayers, difficultyIndex)
    if instanceType ~= "raid" then return nil end
    local n = tonumber(maxPlayers)
    if n and n > 0 then return n end
    local idx = tonumber(difficultyIndex)
    if idx == 3 or idx == 5 then return 10 end
    if idx == 4 or idx == 6 then return 25 end
    local roster = GetNumRaidMembers and tonumber(GetNumRaidMembers() or 0) or 0
    if roster > 25 then return 40 end
    if roster > 10 then return 25 end
    if roster > 0 then return 10 end
    return nil
end

local function GetContext()
    local name, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic = GetInstanceInfo()
    local inInstance = IsInInstance()
    local mythic = GetStandaloneMythicContext()
    local difficultyKey, difficultySource = NormalizeDifficulty(instanceType, difficultyIndex, difficultyName, mythic)
    local mythicCurrent = mythic and mythic.active and mythic.inInstance
        and (mythic.instanceType == "party" or instanceType == "party") and true or false
    local raidSize = NormalizeRaidSize(instanceType, maxPlayers, difficultyIndex)
    local raidMode = raidSize and (tostring(raidSize) .. "-" .. tostring(difficultyKey)) or nil
    return {
        inInstance = inInstance and true or false,
        instanceName = name,
        instanceType = instanceType,
        difficultyIndex = difficultyIndex,
        difficultyName = difficultyName,
        difficultyKey = difficultyKey,
        difficultySource = difficultySource,
        maxPlayers = maxPlayers,
        raidSize = raidSize,
        raidMode = raidMode,
        dynamicDifficulty = dynamicDifficulty,
        isDynamic = isDynamic,
        detectorVersion = TriRoutes and TriRoutes.DETECTION_VERSION or nil,
        -- A persistent character-state table may survive a previous key. Only mark
        -- the CURRENT dungeon Mythic when active+inInstance confirms it; retain the
        -- broader state separately for diagnostics.
        mythicDetected = mythicCurrent,
        mythicStateDetected = mythic and mythic.detected and true or false,
        mythicActive = mythicCurrent,
        mythicTier = mythicCurrent and mythic.tier or nil,
        mythicSource = mythicCurrent and mythic.source or nil,
        mythicAffixes = mythicCurrent and mythic.affixText or nil,
        mythicEnemyForcesPct = mythicCurrent and mythic.enemyForcesPercentage or nil,
    }
end
RT.GetContext = GetContext

local function GetAstrolabe()
    return TriRoutes and TriRoutes.GetAstrolabe and TriRoutes.GetAstrolabe() or nil
end

local function GetUnitPositionDetailed(unit)
    local A = GetAstrolabe()
    if A then
        if unit == "player" and A.GetCurrentPlayerPosition then
            local c, z, x, y = A:GetCurrentPlayerPosition()
            if c and x and y and (x > 0 or y > 0) then return c, z or 0, x, y, "astrolabe-player" end
        elseif A.GetUnitPosition then
            local c, z, x, y = A:GetUnitPosition(unit, true)
            if c and x and y and (x > 0 or y > 0) then return c, z or 0, x, y, "astrolabe-unit" end
        end
    end
    local x, y = GetPlayerMapPosition(unit)
    if x and y and (x > 0 or y > 0) then
        return GetCurrentMapContinent(), GetCurrentMapZone(), x, y, "native-map"
    end
end

local function GetUnitPosition(unit)
    local c, z, x, y = GetUnitPositionDetailed(unit)
    return c, z, x, y
end

-- test5o diagnostic recovery: at most one live-map nudge per normal sampling
-- tick, and only after a non-player coordinate read has already failed.  This
-- intentionally does not seed at run start, loop retries, or maintain a
-- canonical map continuously.  It tells us whether the exact failed read can
-- be rescued and which coordinate API succeeds afterward.
local sameTickPartyRecoveryUsed = false

local function RetryPartyPositionSameTick(unit)
    if sameTickPartyRecoveryUsed or not currentRun then return nil end
    sameTickPartyRecoveryUsed = true
    currentRun.sameTickPartyRecoveryTriggers = (currentRun.sameTickPartyRecoveryTriggers or 0) + 1

    local beforeFile = GetMapInfo and GetMapInfo() or nil
    currentRun.lastSameTickRetryMapBefore = beforeFile
    currentRun.lastSameTickRetryUnit = UnitName(unit) or unit

    if not SetMapToCurrentZone then
        currentRun.sameTickMapRetryUnavailable = (currentRun.sameTickMapRetryUnavailable or 0) + 1
        return nil
    end
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
        currentRun.sameTickMapRetryDeferred = (currentRun.sameTickMapRetryDeferred or 0) + 1
        currentRun.lastSameTickRetrySource = "world-map-open"
        return nil
    end

    currentRun.sameTickMapRetryAttempts = (currentRun.sameTickMapRetryAttempts or 0) + 1
    local ok = pcall(SetMapToCurrentZone)
    if not ok then
        currentRun.sameTickMapRetryErrors = (currentRun.sameTickMapRetryErrors or 0) + 1
        currentRun.lastSameTickRetrySource = "setmap-error"
        return nil
    end
    local afterFile = GetMapInfo and GetMapInfo() or nil
    currentRun.lastSameTickRetryMapAfter = afterFile

    local c, z, x, y, source = GetUnitPositionDetailed(unit)
    if c and x and y then
        currentRun.sameTickMapRetrySuccesses = (currentRun.sameTickMapRetrySuccesses or 0) + 1
        currentRun.lastSameTickRetrySource = source
        if source and string.find(source, "astrolabe", 1, true) then
            currentRun.sameTickAstrolabeSuccesses = (currentRun.sameTickAstrolabeSuccesses or 0) + 1
        elseif source == "native-map" then
            currentRun.sameTickNativeSuccesses = (currentRun.sameTickNativeSuccesses or 0) + 1
        end
        return c, z, x, y, source
    end

    currentRun.sameTickMapRetryFailures = (currentRun.sameTickMapRetryFailures or 0) + 1
    currentRun.lastSameTickRetrySource = "failed"
    return nil
end

local function IsLeader(unit)
    if UnitIsPartyLeader and UnitIsPartyLeader(unit) then return true end
    if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return true end
    local raidIndex = string.match(unit or "", "^raid(%d+)$")
    if raidIndex and GetRaidRosterInfo then
        local _, rank = GetRaidRosterInfo(tonumber(raidIndex))
        return rank == 2
    end
    return false
end

local function NormalizeRoleValue(role)
    if type(role) ~= "string" then return nil end
    role = string.upper(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" or role == "ASSIST" then return role end
    return nil
end

local function GetRole(unit)
    if TriRoutes and type(TriRoutes.GetGroupRole) == "function" then
        local ok, role, source, confidence, spec = pcall(TriRoutes.GetGroupRole, unit)
        role = ok and NormalizeRoleValue(role) or nil
        if role then
            return role, source or "triroutes-role", tonumber(confidence or 0) or 0, spec
        end
    end
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return "TANK", "maintank-assignment", 1.0 end
    if UnitGroupRolesAssigned then
        local role = NormalizeRoleValue(UnitGroupRolesAssigned(unit))
        if role and role ~= "NONE" then return role, "group-role-api", 1.0 end
    end
    local raidIndex = string.match(unit or "", "^raid(%d+)$")
    if raidIndex and GetRaidRosterInfo then
        local _, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(tonumber(raidIndex))
        if role == "MAINTANK" then return "TANK", "raid-maintank", 1.0 end
        if role == "MAINASSIST" then return "ASSIST", "raid-mainassist", 1.0 end
    end
    return nil, "unknown", 0
end

local function GetStandaloneTankUnit()
    if not TriRoutes or type(TriRoutes.GetGroupTankUnit) ~= "function" then return nil end
    local ok, unit, source, confidence, evidence = pcall(TriRoutes.GetGroupTankUnit, true)
    if ok and unit and UnitExists(unit) then
        return unit, source or "triroutes-tank", tonumber(confidence or 0) or 0, tonumber(evidence or 0) or 0
    end
    return nil
end

local function GroupUnits()
    local units = {"player"}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do units[#units + 1] = "raid" .. i end
    else
        local n = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, n do units[#units + 1] = "party" .. i end
    end
    return units
end

local function FindGroupUnitByGUID(guid)
    if not guid then return nil end
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    end
end

local function FindGroupUnitByName(name)
    name = lower(tostring(name or ""))
    if name == "" then return nil end
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local n = UnitName(unit)
            if n and lower(n) == name then return unit end
        end
    end
end

local function GetRaidLeaderUnit()
    if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then return nil end
    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i
        if UnitExists(unit) and IsLeader(unit) then return unit end
    end
end

local function GetExplicitTankUnits()
    local out, seen = {}, {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local role, source, confidence = GetRole(unit)
            local explicit = source == "maintank-assignment" or source == "raid-maintank" or source == "group-role-api" or source == "group-role"
            if role == "TANK" and explicit then
                local guid = UnitGUID(unit) or unit
                if not seen[guid] then
                    seen[guid] = true
                    out[#out + 1] = {unit=unit, source=source, confidence=confidence or 1}
                end
            end
        end
    end
    return out
end

local function GetStableTankUnit()
    if not currentRun or not currentRun.stableTankGuid then return nil end
    return FindGroupUnitByGUID(currentRun.stableTankGuid)
end

local function UpdateStableTankEvidence(track, source, confidence, evidence)
    if not currentRun or not track then return end
    currentRun.tankObservations = currentRun.tankObservations or {}
    local row = currentRun.tankObservations[track.guid]
    if not row then
        row = {name=track.name, class=track.class, hits=0, score=0, lastSource=source}
        currentRun.tankObservations[track.guid] = row
    end
    local ev = tonumber(evidence or 0) or 0
    local conf = tonumber(confidence or 0) or 0
    local weight = math.max(0.25, conf) * math.max(1, ev)
    if source == "maintank-assignment" or source == "raid-maintank" or source == "group-role" or source == "group-role-api" then
        weight = weight + 4
        row.explicit = true
    end
    row.hits = (row.hits or 0) + 1
    row.score = (row.score or 0) + weight
    row.lastSource = source
    row.lastConfidence = conf
    row.lastEvidence = ev

    local bestGuid, bestRow, secondScore
    for guid, info in pairs(currentRun.tankObservations) do
        local score = tonumber(info.score or 0) or 0
        if not bestRow or score > (bestRow.score or 0) then
            secondScore = bestRow and (bestRow.score or 0) or secondScore
            bestGuid, bestRow = guid, info
        elseif not secondScore or score > secondScore then
            secondScore = score
        end
    end
    secondScore = secondScore or 0
    local qualifies = bestGuid and bestRow and (bestRow.explicit or ((bestRow.hits or 0) >= 6 and (bestRow.score or 0) >= secondScore + 1.5))
    if not qualifies then return end

    -- Once a dungeon tank has been learned, transient party-unit/API failures
    -- must not make the route identity bounce to the player or group leader.
    -- Keep the established tank while their GUID is still in the group. If the
    -- tank genuinely disappears, require both an eight-second grace period and
    -- overwhelming replacement evidence before changing the stable identity.
    local oldGuid = currentRun.stableTankGuid
    if oldGuid and oldGuid ~= bestGuid then
        local oldUnit = FindGroupUnitByGUID(oldGuid)
        if oldUnit then
            currentRun.stableTankMissingSince = nil
            return
        end
        local now = GetTime and GetTime() or 0
        currentRun.stableTankMissingSince = currentRun.stableTankMissingSince or now
        local missingFor = now - currentRun.stableTankMissingSince
        local oldRow = currentRun.tankObservations and currentRun.tankObservations[oldGuid]
        local oldScore = oldRow and (tonumber(oldRow.score or 0) or 0) or 0
        local newScore = tonumber(bestRow.score or 0) or 0
        local overwhelming = bestRow.explicit or ((bestRow.hits or 0) >= 12 and newScore >= oldScore + 10 and (oldScore <= 0 or newScore >= oldScore * 1.25))
        if missingFor < 8 or not overwhelming then return end
    else
        local oldUnit = oldGuid and FindGroupUnitByGUID(oldGuid) or nil
        if oldUnit or not oldGuid then currentRun.stableTankMissingSince = nil end
    end

    currentRun.stableTankGuid = bestGuid
    currentRun.stableTankName = bestRow.name
    currentRun.stableTankSource = bestRow.explicit and (bestRow.lastSource or "explicit") or "accumulated-combat-evidence"
    currentRun.stableTankConfidence = bestRow.explicit and 1.0 or math.min(0.95, 0.65 + math.min(0.30, (bestRow.hits or 0) * 0.015))
end

-- A raid route should follow a stable movement leader, not whichever tank has
-- aggro during a swap. Manual choice wins; otherwise the raid leader is the
-- most stable proxy, then an explicitly assigned tank, then inferred tank.
local function ResolveRouteLeaderUnit()
    local raid = GetNumRaidMembers and GetNumRaidMembers() > 0
    if manualRouteLeaderGUID then
        local unit = FindGroupUnitByGUID(manualRouteLeaderGUID)
        if unit then return unit, "manual-route-leader", 1.0 end
    end

    if raid then
        local leader = GetRaidLeaderUnit()
        if leader then return leader, "raid-leader", 1.0 end
        local tanks = GetExplicitTankUnits()
        if tanks[1] then return tanks[1].unit, tanks[1].source or "raid-maintank", tanks[1].confidence or 1.0 end
        local tank, source, confidence = GetStandaloneTankUnit()
        if tank then return tank, source or "combat-target-evidence", confidence or 0.7 end
        return "player", "player-fallback", 0.25
    end

    local stableTank = GetStableTankUnit()
    if stableTank then return stableTank, currentRun.stableTankSource or "stable-tank", currentRun.stableTankConfidence or 0.8 end
    local tank, source, confidence, evidence = GetStandaloneTankUnit()
    -- Do not let one loose mob immediately replace the movement leader.
    if tank and ((tonumber(evidence or 0) or 0) >= 2 or (tonumber(confidence or 0) or 0) >= 0.70) then
        return tank, source or "tank", confidence or 0.7
    end
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and IsLeader(unit) then return unit, "group-leader", 0.65 end
    end
    return "player", "player-fallback", 0.25
end

local function GetRaidRecordUnits()
    local limit = tonumber(db and db.settings and db.settings.raidTrackLimit) or 6
    if limit < 2 then limit = 2 end
    local out, seen = {}, {}
    local playerGUID = UnitGUID("player")
    if playerGUID then seen[playerGUID] = true end

    local function add(unit)
        if not unit or not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid or seen[guid] then return end
        if #out >= (limit - 1) then return end
        seen[guid] = true
        out[#out + 1] = unit
    end

    local routeLeader = ResolveRouteLeaderUnit()
    add(routeLeader)
    for _, info in ipairs(GetExplicitTankUnits()) do add(info.unit) end
    local inferred = GetStandaloneTankUnit()
    add(inferred)
    add(GetRaidLeaderUnit())
    return out
end

local function RefreshGroupGUIDs()
    groupGUIDs = {}
    local pg = UnitGUID("player")
    if pg then groupGUIDs[pg] = true end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local g = UnitGUID("raid" .. i)
            if g then groupGUIDs[g] = true end
        end
    else
        local n = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, n do
            local g = UnitGUID("party" .. i)
            if g then groupGUIDs[g] = true end
        end
    end
end

local function NowRunTime()
    if not currentRun then return 0 end
    return GetTime() - (currentRun.startedClock or GetTime())
end

local function AddEvent(kind, data)
    if not currentRun then return end
    local e = data or {}
    e.t = NowRunTime()
    e.kind = kind
    currentRun.events[#currentRun.events + 1] = e
end

local function CreateTrack(unit)
    if not currentRun or not UnitExists(unit) then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local track = currentRun.tracks[guid]
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    local role, roleSource, roleConfidence, roleSpec = GetRole(unit)
    local leader = IsLeader(unit)
    if not track then
        track = {
            guid = guid,
            name = name,
            class = class,
            role = role,
            roleSource = roleSource,
            roleConfidence = roleConfidence,
            roleSpec = roleSpec,
            leader = leader and true or false,
            isPlayer = UnitIsUnit and UnitIsUnit(unit, "player") and true or (unit == "player"),
            unitHint = unit,
            samples = {},
        }
        currentRun.tracks[guid] = track
    else
        if role and role ~= "NONE" then
            track.role = role
            track.roleSource = roleSource
            track.roleConfidence = roleConfidence
            track.roleSpec = roleSpec
        end
        if leader then track.leader = true end
        if name then track.name = name end
        if class then track.class = class end
        track.unitHint = unit
    end
    return track
end

local function RefreshMapState(reason)
    if not currentRun then return nil end
    local m = GetMapSnapshot()
    local sig = MapSignature(m)
    if not currentMapSignature then
        currentMapSignature = sig
        currentRun.mapFile = m.file
        currentRun.mapAreaId = m.area
        currentRun.mapFloor = m.floor
        currentRun.mapPhase = currentRun.mapPhase or 1
    elseif sig ~= currentMapSignature then
        currentMapSignature = sig
        currentRun.mapPhase = (currentRun.mapPhase or 1) + 1
        AddEvent("map_transition", {mapFile=m.file, mapAreaId=m.area, mapFloor=m.floor, phase=currentRun.mapPhase, reason=reason or "sample"})
    end
    currentRun.currentMapFile = m.file
    currentRun.currentMapAreaId = m.area
    currentRun.currentMapFloor = m.floor
    return m
end

local function UpdateDeathAndWipeState()
    if not currentRun then return end
    local units = {"player"}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i=1,GetNumRaidMembers() do units[#units+1] = "raid"..i end
    else
        local n = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i=1,n do units[#units+1] = "party"..i end
    end
    local total, dead, tankDead = 0, 0, false
    for _,unit in ipairs(units) do
        if UnitExists(unit) then
            total = total + 1
            local guid = UnitGUID(unit)
            local isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false
            if guid and deathState[guid] ~= isDead then
                deathState[guid] = isDead
                local tr = currentRun.tracks and currentRun.tracks[guid]
                local role = tr and tr.role or GetRole(unit)
                AddEvent(isDead and "unit_dead" or "unit_alive", {guid=guid, name=UnitName(unit), role=role})
            end
            if isDead then
                dead = dead + 1
                local tr = guid and currentRun.tracks and currentRun.tracks[guid]
                local role = tr and tr.role or GetRole(unit)
                if role == "TANK" then tankDead = true end
            end
        end
    end
    if total >= 2 and dead == total and not recoveryActive then
        recoveryActive = true
        wipeMarked = true
        local c,z,x,y = GetUnitPosition("player")
        AddEvent("wipe", {dead=dead,total=total,tankDead=tankDead,c=c,z=z,x=x,y=y})
        currentRun.wipes = (currentRun.wipes or 0) + 1
    end
end

local function EndRecovery(reason)
    if not recoveryActive then return end
    recoveryActive = false
    local c,z,x,y = GetUnitPosition("player")
    AddEvent("recovery_end", {reason=reason or "combat_resumed", c=c,z=z,x=x,y=y})
end

local function AppendSample(unit)
    local track = CreateTrack(unit)
    if not track then return false end
    local c, z, x, y, source = GetUnitPositionDetailed(unit)
    if not c or not x or not y then
        if unit == "player" then
            -- positionFailures is intentionally the route-critical player count.
            currentRun.positionFailures = (currentRun.positionFailures or 0) + 1
            return false
        end

        currentRun.partyInitialPositionFailures = (currentRun.partyInitialPositionFailures or 0) + 1
        c, z, x, y, source = RetryPartyPositionSameTick(unit)
        if not c or not x or not y then
            currentRun.partyPositionFailures = (currentRun.partyPositionFailures or 0) + 1
            return false
        end
        currentRun.partyRecoveredPositionReads = (currentRun.partyRecoveredPositionReads or 0) + 1
    end

    if unit ~= "player" then
        if source and string.find(source, "astrolabe", 1, true) then
            currentRun.partyAstrolabePositionReads = (currentRun.partyAstrolabePositionReads or 0) + 1
        elseif source == "native-map" then
            currentRun.partyNativePositionReads = (currentRun.partyNativePositionReads or 0) + 1
        end
    end

    local now = NowRunTime()
    local facing
    if unit == "player" and GetPlayerFacing then facing = GetPlayerFacing() end
    local s = {t = now, c = c, z = z or 0, x = x, y = y, f = facing, section = currentRun.sectionIndex or 1, phase = currentRun.mapPhase or 1}
    if currentRun.currentMapFloor ~= nil then s.floor = currentRun.currentMapFloor end
    if recoveryActive then s.recovery = true end
    local samples = track.samples
    local last = samples[#samples]
    local should = not last
    if last then
        if last.c ~= s.c or last.z ~= s.z then
            should = true
        else
            local dx, dy = s.x - last.x, s.y - last.y
            local moved = (dx * dx + dy * dy) ^ 0.5
            if moved >= db.settings.movementThreshold or (s.t - last.t) >= db.settings.heartbeat then should = true end
        end
    end
    if should then samples[#samples + 1] = s end
    return should
end

local function RefreshRunContext()
    if not currentRun then return end
    local ctx = GetContext()

    -- A Mythic run may only become identifiable after the server's timer/state
    -- appears. Promote an already-started recording as soon as TriRoutes confirms it.
    if db.settings.difficulty == "auto" and ctx.difficultyKey == "mythic" and currentRun.difficultyKey ~= "mythic" then
        local old = currentRun.difficultyKey
        currentRun.difficultyKey = "mythic"
        currentRun.difficultySource = ctx.difficultySource
        currentRun.difficultyIndex = ctx.difficultyIndex
        currentRun.difficultyName = ctx.difficultyName
        AddEvent("difficulty_promoted", {from = old, to = "mythic", source = ctx.difficultySource, tier = ctx.mythicTier})
        Chat("TriRoutes confirmed Mythic" .. (ctx.mythicTier and (" +" .. tostring(ctx.mythicTier)) or "") .. "; recording promoted from " .. tostring(old) .. ".")
    end

    if ctx.mythicDetected then
        currentRun.mythicDetected = true
        currentRun.mythicActive = true
    end
    if ctx.mythicTier then currentRun.mythicTier = ctx.mythicTier end
    if ctx.mythicSource then currentRun.mythicSource = ctx.mythicSource end
    if ctx.mythicAffixes then currentRun.mythicAffixes = ctx.mythicAffixes end
    if ctx.mythicEnemyForcesPct then currentRun.mythicEnemyForcesPct = ctx.mythicEnemyForcesPct end
end

local function ApplyStandaloneTankEvidence()
    local unit, source, confidence, evidence = GetStandaloneTankUnit()
    if not unit then return end
    local track = CreateTrack(unit)
    if not track then return end
    UpdateStableTankEvidence(track, source, confidence, evidence)
    track.tankEvidence = true
    track.tankEvidenceCount = evidence
    track.tankEvidenceObservations = (track.tankEvidenceObservations or 0) + 1
    local explicit = source == "maintank-assignment" or source == "raid-maintank" or source == "group-role" or source == "group-role-api"
    if explicit or (tonumber(evidence or 0) or 0) >= 2 or (tonumber(confidence or 0) or 0) >= 0.70 then
        track.role = "TANK"
        track.roleSource = source
        track.roleConfidence = confidence
    end
    if currentRun.stableTankGuid and currentRun.tracks[currentRun.stableTankGuid] then
        local stable = currentRun.tracks[currentRun.stableTankGuid]
        stable.role = "TANK"
        stable.roleSource = currentRun.stableTankSource or "run-stable-tank"
        stable.roleConfidence = currentRun.stableTankConfidence or 0.8
    end
end

local function ApplyRouteLeaderEvidence()
    if not currentRun then return end

    -- Dungeon route identity follows the learned stable tank even if WDM cannot
    -- currently provide that party member's coordinates, or their partyN unit
    -- disappears briefly during the loading-screen/exit transition. Identity
    -- and coordinate availability are deliberately separate concerns.
    if currentRun.instanceType == "party" and currentRun.stableTankGuid then
        local stableUnit = FindGroupUnitByGUID(currentRun.stableTankGuid)
        local track = stableUnit and CreateTrack(stableUnit) or (currentRun.tracks and currentRun.tracks[currentRun.stableTankGuid])
        if track then
            local source = currentRun.stableTankSource or "stable-tank-sticky"
            local confidence = currentRun.stableTankConfidence or 0.8
            local oldGuid = currentRun.routeLeaderGuid
            if oldGuid and oldGuid ~= track.guid then
                local oldTrack = currentRun.tracks and currentRun.tracks[oldGuid]
                if oldTrack then oldTrack.routeLeader = nil end
                AddEvent("route_leader_changed", {from=oldGuid, to=track.guid, name=track.name, source=source})
            end
            track.routeLeader = true
            track.routeLeaderSource = source
            track.routeLeaderConfidence = confidence
            currentRun.routeLeaderGuid = track.guid
            currentRun.routeLeaderName = track.name or currentRun.stableTankName
            currentRun.routeLeaderSource = source
            currentRun.routeLeaderConfidence = confidence
            currentRun.preferredTrackGuid = track.guid
            if stableUnit then
                currentRun.stableTankUnresolvedTicks = 0
            else
                currentRun.stableTankUnresolvedTicks = (currentRun.stableTankUnresolvedTicks or 0) + 1
            end
            return
        end
    end

    local unit, source, confidence = ResolveRouteLeaderUnit()
    if not unit then return end
    local track = CreateTrack(unit)
    if not track then return end
    local oldGuid = currentRun.routeLeaderGuid
    if oldGuid and oldGuid ~= track.guid then
        local oldTrack = currentRun.tracks and currentRun.tracks[oldGuid]
        if oldTrack then oldTrack.routeLeader = nil end
        AddEvent("route_leader_changed", {from=oldGuid, to=track.guid, name=track.name, source=source})
    end
    track.routeLeader = true
    track.routeLeaderSource = source
    track.routeLeaderConfidence = confidence
    currentRun.routeLeaderGuid = track.guid
    currentRun.routeLeaderName = track.name
    currentRun.routeLeaderSource = source
    currentRun.routeLeaderConfidence = confidence
    if currentRun.instanceType == "raid" then currentRun.preferredTrackGuid = track.guid end
end

local function SampleGroup()
    if not currentRun then return end
    sameTickPartyRecoveryUsed = false
    RefreshRunContext()
    RefreshMapState("sample")
    UpdateDeathAndWipeState()
    ApplyStandaloneTankEvidence()
    ApplyRouteLeaderEvidence()

    -- test5o keeps passive sampling as the default.  The learned dungeon tank
    -- is sampled first; only the first failed party read in this tick may trigger
    -- one immediate SetMapToCurrentZone + retry diagnostic.  There is no startup
    -- seeding, retry loop, or persistent canonical-map maintenance.
    local any = AppendSample("player")
    if db.settings.recordParty then
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            for _, unit in ipairs(GetRaidRecordUnits()) do
                if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then AppendSample(unit) end
            end
        else
            local sampled = {}
            local stableUnit = currentRun.stableTankGuid and FindGroupUnitByGUID(currentRun.stableTankGuid) or nil
            if stableUnit and UnitExists(stableUnit) then
                local guid = UnitGUID(stableUnit)
                AppendSample(stableUnit)
                if guid then sampled[guid] = true end
            end
            local n = GetNumPartyMembers and GetNumPartyMembers() or 0
            for i = 1, n do
                local unit = "party" .. i
                if UnitExists(unit) then
                    local guid = UnitGUID(unit)
                    if not guid or not sampled[guid] then AppendSample(unit) end
                end
            end
        end
    end

    if any and not currentRun.firstValidPositionAt then
        currentRun.firstValidPositionAt = NowRunTime()
    end

    if any then
        currentRun.lastValidPositionAt = NowRunTime()
    end
end

local function CountSamples(track)
    return track and track.samples and #track.samples or 0
end

local function IsSparsePartyGeometryTrack(run, track)
    if not run or run.instanceType ~= "party" or not track or track.isPlayer then return false end
    local n = CountSamples(track)
    local playerTrack = run.player and run.tracks and run.tracks[run.player.guid]
    local playerN = CountSamples(playerTrack)
    return playerN >= 20 and (n < 20 or n < playerN * 0.25)
end

local function ChoosePreferredTrack(run)
    if run and run.instanceType == "party" and run.stableTankGuid then
        local tankTrack = run.tracks and run.tracks[run.stableTankGuid]
        if tankTrack and CountSamples(tankTrack) >= 4 and not IsSparsePartyGeometryTrack(run, tankTrack) then
            run.preferredTrackGuid = run.stableTankGuid
            run.tankTrackSparse = nil
            return
        elseif tankTrack then
            run.tankTrackSparse = true
        end
    end
    -- For raids, prefer the stable movement leader captured during the run. This
    -- avoids a boss tank-swap changing the learned route source halfway through.
    if run and run.instanceType == "raid" and run.routeLeaderGuid then
        local routeTrack = run.tracks and run.tracks[run.routeLeaderGuid]
        if routeTrack and CountSamples(routeTrack) >= 4 then
            run.preferredTrackGuid = run.routeLeaderGuid
            return
        end
    end

    local bestGuid, bestScore
    for guid, track in pairs(run.tracks or {}) do
        local n = CountSamples(track)
        local score = n
        if run.instanceType == "raid" then
            if track.routeLeader then score = score + 20000 end
            if track.leader then score = score + 7000 end
            if track.role == "TANK" then score = score + 5000 end
            if track.isPlayer then score = score + 250 end
        else
            local sparse = IsSparsePartyGeometryTrack(run, track)
            if track.isPlayer then score = score + 1000 end
            if not sparse and track.leader then score = score + 2500 end
            if not sparse and track.role == "TANK" then score = score + 10000 end
        end
        if n >= 4 and (not bestScore or score > bestScore) then
            bestGuid, bestScore = guid, score
        end
    end
    run.preferredTrackGuid = bestGuid
end

local function TrimRuns()
    local maxRuns = tonumber(db.settings.maxRuns) or 60
    while #db.runs > maxRuns do tremove(db.runs, 1) end
end

local function StartRun(reason)
    if currentRun then return end
    local ctx = GetContext()
    local playerName = UnitName("player")
    local _, class = UnitClass("player")
    local id = (db.nextRunId or 1)
    db.nextRunId = id + 1

    local partySignature = CurrentPartySignature()
    local sessionId, sectionIndex, continuedFrom, sessionTransition, continueRecovery
    local last = db.runs and db.runs[#db.runs]
    local resumeSeconds = tonumber(db.settings.sessionResumeSeconds) or 45
    if last and last.endedAt and IsTransitionReason(last.reasonEnded)
        and last.instanceName == ctx.instanceName and SameDifficultyForResume(last, ctx)
        and (ctx.instanceType ~= "raid" or not last.raidSize or not ctx.raidSize or tonumber(last.raidSize) == tonumber(ctx.raidSize))
        and (time() - last.endedAt) >= 0 and (time() - last.endedAt) <= resumeSeconds
        and SamePartySignature(RunPartySignature(last), partySignature) then
        sessionId = last.sessionId or AllocateSessionId()
        last.sessionId = sessionId
        last.sectionIndex = last.sectionIndex or 1
        sectionIndex = last.sectionIndex + 1
        continuedFrom = last.id
        sessionTransition = "map-or-world-transition"
        continueRecovery = last.endedInRecovery and true or false
    else
        sessionId = AllocateSessionId()
        sectionIndex = 1
    end

    currentRun = {
        schema = 4,
        addonVersion = VERSION,
        id = id,
        sessionId = sessionId,
        sectionIndex = sectionIndex,
        continuedFromRunId = continuedFrom,
        sessionTransition = sessionTransition,
        partySignature = partySignature,
        startedAt = time(),
        startedClock = GetTime(),
        reasonStarted = reason or "manual",
        realm = GetRealmName and GetRealmName() or nil,
        player = {name = playerName, class = class, guid = UnitGUID("player")},
        instanceName = ctx.instanceName,
        instanceType = ctx.instanceType,
        difficultyIndex = ctx.difficultyIndex,
        difficultyName = ctx.difficultyName,
        difficultyKey = ctx.difficultyKey,
        difficultySource = ctx.difficultySource,
        detectorVersion = ctx.detectorVersion,
        mythicDetected = ctx.mythicDetected,
        mythicStateDetectedAtStart = ctx.mythicStateDetected,
        mythicActiveAtStart = ctx.mythicActive,
        mythicTier = ctx.mythicTier,
        mythicSource = ctx.mythicSource,
        mythicAffixes = ctx.mythicAffixes,
        maxPlayers = ctx.maxPlayers,
        raidSize = ctx.raidSize,
        raidMode = ctx.raidMode,
        raidRecordingPolicy = ctx.instanceType == "raid" and "route-leader+tanks+player" or nil,
        dynamicDifficulty = ctx.dynamicDifficulty,
        isDynamic = ctx.isDynamic,
        difficultyMode = db.settings.difficulty,
        tracks = {},
        combats = {},
        events = {},
        tankObservations = {},
        positionFailures = 0,
        partyPositionFailures = 0,
        partyInitialPositionFailures = 0,
        partyRecoveredPositionReads = 0,
        partyAstrolabePositionReads = 0,
        partyNativePositionReads = 0,
        sameTickPartyRecoveryTriggers = 0,
        sameTickMapRetryAttempts = 0,
        sameTickMapRetrySuccesses = 0,
        sameTickMapRetryFailures = 0,
        sameTickAstrolabeSuccesses = 0,
        sameTickNativeSuccesses = 0,
        samplingMapPolicy = "passive-single-failure-retry",
    }
    db.runs[#db.runs + 1] = currentRun
    RT.currentRun = currentRun
    currentCombat = nil
    seenBoss = {}
    deathState = {}
    recoveryActive = continueRecovery and true or false
    wipeMarked = recoveryActive
    currentMapSignature = nil
    ResetDungeonTransitionCandidate()
    RefreshGroupGUIDs()
    RefreshMapState("run_start")
    SampleGroup()
    Chat(format("recording #%d (session %d section %d): %s [%s]", id, sessionId, sectionIndex, tostring(ctx.instanceName or "unknown"), tostring(ctx.difficultyKey)))
end

local function EndCombat(reason)
    if not currentCombat then return end
    currentCombat.finish = NowRunTime()
    currentCombat.duration = currentCombat.finish - (currentCombat.start or currentCombat.finish)
    currentCombat.reason = reason or "combat_end"
    local c, z, x, y = GetUnitPosition("player")
    currentCombat.endPos = c and {c = c, z = z, x = x, y = y} or nil
    currentCombat = nil
end

local function StopRun(reason, skipFinalSample)
    if not currentRun then return end
    EndCombat("run_end")
    if not skipFinalSample then SampleGroup() end
    currentRun.endedAt = time()
    currentRun.endedClock = GetTime()
    currentRun.duration = currentRun.endedClock - currentRun.startedClock
    currentRun.reasonEnded = reason or "manual"
    currentRun.endedInRecovery = recoveryActive and true or false
    currentRun.partySignature = CurrentPartySignature() ~= "" and CurrentPartySignature() or currentRun.partySignature
    if reason == "dungeon_transition" then
        -- During the confirmation window we intentionally withhold new-dungeon
        -- samples. Preserve the old dungeon as this run's end metadata too.
        currentRun.endMapFile = currentRun.currentMapFile or currentRun.mapFile
        currentRun.endMapAreaId = currentRun.currentMapAreaId or currentRun.mapAreaId
        currentRun.endMapFloor = currentRun.currentMapFloor or currentRun.mapFloor
    else
        local em = GetMapSnapshot()
        currentRun.endMapFile, currentRun.endMapAreaId, currentRun.endMapFloor = em.file, em.area, em.floor
    end
    if recoveryActive then AddEvent("recovery_interrupted", {reason=currentRun.reasonEnded}) end
    ChoosePreferredTrack(currentRun)

    local playerTrack = currentRun.player and currentRun.tracks[currentRun.player.guid]
    local sampleCount = CountSamples(playerTrack)
    local trackCount = 0
    for _ in pairs(currentRun.tracks) do trackCount = trackCount + 1 end
    Chat(format("saved #%d: %.1f min, %d player samples, %d tracks, %d combats, player failures=%d, party failures=%d", currentRun.id, currentRun.duration / 60, sampleCount, trackCount, #currentRun.combats, currentRun.positionFailures or 0, currentRun.partyPositionFailures or 0))
    Chat(format("same-tick party retry: triggers=%d attempts=%d success=%d failed=%d deferred=%d | Astrolabe=%d native=%d", currentRun.sameTickPartyRecoveryTriggers or 0, currentRun.sameTickMapRetryAttempts or 0, currentRun.sameTickMapRetrySuccesses or 0, currentRun.sameTickMapRetryFailures or 0, currentRun.sameTickMapRetryDeferred or 0, currentRun.sameTickAstrolabeSuccesses or 0, currentRun.sameTickNativeSuccesses or 0))
    Chat("After /reload, upload WTF/.../SavedVariables/TriRoutes_Recorder.lua for analysis.")

    RT.currentRun = nil
    currentRun = nil
    currentCombat = nil
    recoveryActive = false
    wipeMarked = false
    currentMapSignature = nil
    ResetDungeonTransitionCandidate()
    TrimRuns()
    if TriRoutes and TriRoutes.RefreshRoute then TriRoutes:RefreshRoute(true) end
end

local function CheckForStableDungeonTransition()
    if not currentRun or currentRun.instanceType ~= "party" then
        ResetDungeonTransitionCandidate()
        return false
    end

    local ctx = GetContext()
    if not ctx.inInstance or ctx.instanceType ~= "party" then
        ResetDungeonTransitionCandidate()
        return false
    end

    local baseNameKey = NormalizeInstanceKey(currentRun.instanceName)
    local liveNameKey = NormalizeInstanceKey(ctx.instanceName)
    local liveRawMap = GetMapInfo and GetMapInfo() or nil
    local baseMap = currentRun.mapFile

    local nameChanged = baseNameKey ~= "" and liveNameKey ~= "" and liveNameKey ~= baseNameKey
    local worldMapOpen = WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
    local mapChanged = not worldMapOpen and baseMap and liveRawMap and liveRawMap ~= baseMap
        and IsKnownDungeonMapFile(liveRawMap)

    if not nameChanged and not mapChanged then
        ResetDungeonTransitionCandidate()
        return false
    end

    -- Prefer the map identity when available so a context update part-way through
    -- confirmation does not reset the candidate from name:X to map:Y.
    local key
    if mapChanged then
        key = "map:" .. tostring(liveRawMap)
    else
        key = "name:" .. tostring(liveNameKey)
    end

    if dungeonTransitionCandidateKey == key then
        dungeonTransitionCandidateCount = dungeonTransitionCandidateCount + 1
    else
        dungeonTransitionCandidateKey = key
        dungeonTransitionCandidateName = ctx.instanceName
        dungeonTransitionCandidateMapFile = liveRawMap
        dungeonTransitionCandidateCount = 1
        dungeonTransitionCandidateFirstClock = GetTime()
    end

    local needed = tonumber(db.settings.dungeonSplitConfirmSamples) or 3
    if needed < 2 then needed = 2 end

    if dungeonTransitionCandidateCount < needed then
        -- Do not append geometry while the candidate is unresolved. This prevents
        -- the first points from the next dungeon contaminating the previous run.
        return true
    end

    local oldRunId = currentRun.id
    local oldInstance = currentRun.instanceName
    local targetName = dungeonTransitionCandidateName or ctx.instanceName
    local targetMap = dungeonTransitionCandidateMapFile or liveRawMap
    local confirmSeconds = dungeonTransitionCandidateFirstClock and (GetTime() - dungeonTransitionCandidateFirstClock) or 0

    AddEvent("dungeon_transition_confirmed", {
        fromInstance = oldInstance,
        toInstance = targetName,
        toMapFile = targetMap,
        confirmations = dungeonTransitionCandidateCount,
        confirmSeconds = confirmSeconds,
    })
    Chat(format("confirmed dungeon change after %d samples: %s -> %s%s; splitting recording.",
        dungeonTransitionCandidateCount, tostring(oldInstance or "unknown"), tostring(targetName or "unknown"),
        targetMap and (" [" .. tostring(targetMap) .. "]") or ""))

    -- Skip StopRun's normal final sample: the live map already belongs to the
    -- next dungeon. StartRun will immediately seed the new run instead.
    StopRun("dungeon_transition", true)
    StartRun("dungeon_transition")
    if currentRun then
        currentRun.splitFromRunId = oldRunId
        currentRun.dungeonTransition = "confirmed-dungeon-change"
    end
    return true
end

local function EvaluateAuto(reason)
    if not db or not db.settings.autoRecord then return end
    local ctx = GetContext()
    local dungeon = ctx.inInstance and (ctx.instanceType == "party" or ctx.instanceType == "raid")
    if dungeon then
        if not manualPausedUntilLeave and not currentRun then StartRun(reason or "auto") end
    else
        manualPausedUntilLeave = false
        if currentRun then StopRun(reason or "left_instance") end
        manualRouteLeaderGUID = nil
        manualRouteLeaderName = nil
    end
end

local function StartCombat()
    if not currentRun or currentCombat then return end
    if recoveryActive then EndRecovery("combat_resumed") end
    local c, z, x, y = GetUnitPosition("player")
    currentCombat = {
        start = NowRunTime(),
        startPos = c and {c = c, z = z, x = x, y = y} or nil,
        npcs = {},
    }
    currentRun.combats[#currentRun.combats + 1] = currentCombat
end

local ROUTE_NOISE_NPC_NAMES = {
    ["Roach"] = true,
    ["Rat"] = true,
    ["Black Rat"] = true,
    ["Broggok Poison Cloud"] = true,
    ["World Invisible Trigger"] = true,
    ["Toad"] = true,
    ["Maggot"] = true,
    ["Defender Corpse"] = true,
    ["Warder Corpse"] = true,
    ["Destroyed Sentinel"] = true,
}

local function AddNPC(guid, name, flags, subevent)
    if not currentCombat or not name or name == "" then return end
    if ROUTE_NOISE_NPC_NAMES[name] then return end
    if guid and groupGUIDs[guid] then return end
    -- Friendly pets/guardians (for example Mechanical Squirrel and allied
    -- Risen Ghouls) can emit combat-log events involving party members. They
    -- are route noise, not dungeon pull targets.
    local band = bit and bit.band
    local friendlyMask = rawget(_G, "COMBATLOG_OBJECT_REACTION_FRIENDLY") or 0x10
    local playerMask = rawget(_G, "COMBATLOG_OBJECT_TYPE_PLAYER") or 0x400
    if flags and band and band(flags, friendlyMask) ~= 0 then return end
    -- Stale combat-log traffic from players outside the current party can leak
    -- into a dungeon pull during queue transitions. They are never route NPCs.
    if flags and band and band(flags, playerMask) ~= 0 then return end
    local key = guid or name
    local npc = currentCombat.npcs[key]
    if not npc then
        npc = {guid = guid, name = name, flags = flags, first = NowRunTime(), last = NowRunTime(), events = 0}
        currentCombat.npcs[key] = npc
    end
    npc.last = NowRunTime()
    npc.events = (npc.events or 0) + 1
    npc.lastEvent = subevent
end

local function CombatLogEvent(...)
    if not currentRun or not currentCombat then return end
    local timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags = ...
    if srcGUID and groupGUIDs[srcGUID] and dstGUID and not groupGUIDs[dstGUID] then
        AddNPC(dstGUID, dstName, dstFlags, subevent)
    elseif dstGUID and groupGUIDs[dstGUID] and srcGUID and not groupGUIDs[srcGUID] then
        AddNPC(srcGUID, srcName, srcFlags, subevent)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "TriRoutes_Recorder" then
            TriRoutesRecorderDB = CopyDefaults(DEFAULTS, TriRoutesRecorderDB)
            db = TriRoutesRecorderDB
            MigrateSessions()
            RT.db = db
            if TriRoutes and TriRoutes.RefreshRoute then TriRoutes:RefreshRoute(true) end
            Chat("loaded. Auto-record is " .. (db.settings.autoRecord and "ON" or "OFF") .. ". Session/floor tracking enabled. /trr status")
        end
        return
    end
    if not db then return end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        EvaluateAuto(event)
    elseif event == "PLAYER_LEAVING_WORLD" then
        -- Do not stop here; normal zone transitions fire this too. PLAYER_LOGOUT handles reload/logout.
    elseif event == "PLAYER_LOGOUT" then
        if currentRun then StopRun("logout_or_reload") end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        RefreshGroupGUIDs()
    elseif event == "PLAYER_REGEN_DISABLED" then
        StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        EndCombat("combat_end")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        CombatLogEvent(...)
    end
end)

local update = CreateFrame("Frame")
update:SetScript("OnUpdate", function(self, elapsed)
    if not db then return end
    if currentRun then
        sampleElapsed = sampleElapsed + elapsed
        if sampleElapsed >= db.settings.sampleInterval then
            sampleElapsed = 0
            if not CheckForStableDungeonTransition() then
                SampleGroup()
            end
        end
    end
end)

local function Status()
    local ctx = GetContext()
    Chat(format("v%s | auto=%s | difficulty mode=%s | standalone detector=%s", VERSION, tostring(db.settings.autoRecord), tostring(db.settings.difficulty), tostring(ctx.detectorVersion or "missing")))
    Chat(format("Dungeon split confirmation: %d consecutive samples", tonumber(db.settings.dungeonSplitConfirmSamples) or 3))
    Chat(format("Context: %s | type=%s | key=%s | source=%s | index=%s | name=%s%s", tostring(ctx.instanceName), tostring(ctx.instanceType), tostring(ctx.difficultyKey), tostring(ctx.difficultySource), tostring(ctx.difficultyIndex), tostring(ctx.difficultyName), ctx.raidSize and (" | raid=" .. tostring(ctx.raidSize)) or ""))
    if ctx.mythicDetected then
        Chat(format("Mythic: active=%s | tier=%s | source=%s | affixes=%s", tostring(ctx.mythicActive), tostring(ctx.mythicTier or "-"), tostring(ctx.mythicSource or "-"), tostring(ctx.mythicAffixes or "-")))
    end
    if TriRoutes and type(TriRoutes.GetTankDetectionState) == "function" then
        local ok, tank = pcall(TriRoutes.GetTankDetectionState)
        if ok and type(tank) == "table" and tank.unit then
            Chat(format("Detected tank: %s | unit=%s | source=%s | confidence=%.2f | evidence=%s", tostring(tank.name or "?"), tostring(tank.unit), tostring(tank.source or "?"), tonumber(tank.confidence or 0) or 0, tostring(tank.evidence or 0)))
        else
            Chat("Detected tank: not resolved yet (combat evidence will learn it).")
        end
    end
    if currentRun then
        local track = currentRun.player and currentRun.tracks[currentRun.player.guid]
        local tracked = 0
        for _ in pairs(currentRun.tracks or {}) do tracked = tracked + 1 end
        Chat(format("ACTIVE #%d | session=%s section=%s | %.1f min | player samples=%d | tracks=%d | combats=%d | wipes=%d | player failures=%d | party failures=%d", currentRun.id, tostring(currentRun.sessionId or "?"), tostring(currentRun.sectionIndex or 1), NowRunTime() / 60, CountSamples(track), tracked, #currentRun.combats, currentRun.wipes or 0, currentRun.positionFailures or 0, currentRun.partyPositionFailures or 0))
        if currentRun.instanceType == "raid" then
            Chat(format("Raid route leader: %s | source=%s | preferred GUID=%s | policy=%s", tostring(currentRun.routeLeaderName or "unresolved"), tostring(currentRun.routeLeaderSource or "?"), tostring(currentRun.routeLeaderGuid or "?"), tostring(currentRun.raidRecordingPolicy or "?")))
        elseif currentRun.instanceType == "party" then
            Chat(format("Dungeon tank lock: %s | source=%s | confidence=%.2f | preferred GUID=%s | sparse=%s", tostring(currentRun.stableTankName or "learning"), tostring(currentRun.stableTankSource or "?"), tonumber(currentRun.stableTankConfidence or 0) or 0, tostring(currentRun.preferredTrackGuid or "?"), currentRun.tankTrackSparse and "YES" or "NO"))
        end
        Chat(format("Map: file=%s area=%s floor=%s phase=%s | policy=%s | recovery=%s", tostring(currentRun.currentMapFile or currentRun.mapFile or "?"), tostring(currentRun.currentMapAreaId or currentRun.mapAreaId or "?"), tostring(currentRun.currentMapFloor or currentRun.mapFloor or "?"), tostring(currentRun.mapPhase or 1), tostring(currentRun.samplingMapPolicy or "passive"), recoveryActive and "YES" or "NO"))
        Chat(format("Party coord retry: triggers=%d attempts=%d success=%d failed=%d deferred=%d | Astrolabe=%d native=%d | last=%s->%s via %s", currentRun.sameTickPartyRecoveryTriggers or 0, currentRun.sameTickMapRetryAttempts or 0, currentRun.sameTickMapRetrySuccesses or 0, currentRun.sameTickMapRetryFailures or 0, currentRun.sameTickMapRetryDeferred or 0, currentRun.sameTickAstrolabeSuccesses or 0, currentRun.sameTickNativeSuccesses or 0, tostring(currentRun.lastSameTickRetryMapBefore or "?"), tostring(currentRun.lastSameTickRetryMapAfter or "?"), tostring(currentRun.lastSameTickRetrySource or "?")))
    else
        Chat("Recorder idle. Completed runs: " .. tostring(#db.runs))
    end
end

local function Mark(kind, note)
    if not currentRun then Chat("No active recording.") return end
    local c, z, x, y = GetUnitPosition("player")
    AddEvent("mark", {mark = kind or "note", note = note, c = c, z = z, x = x, y = y})
    Chat("marked " .. tostring(kind or "note") .. (note and note ~= "" and (": " .. note) or ""))
end

local function SetRouteLeader(value)
    value = tostring(value or "")
    local key = lower(value)
    if key == "" or key == "auto" or key == "clear" then
        manualRouteLeaderGUID = nil
        manualRouteLeaderName = nil
        Chat("raid route leader = AUTO")
        if currentRun then AddEvent("route_leader_auto", {}) end
        return
    end

    local unit
    if key == "target" then
        if UnitExists("target") then
            local targetGuid = UnitGUID("target")
            unit = targetGuid and FindGroupUnitByGUID(targetGuid) or nil
        end
    else
        unit = FindGroupUnitByName(value)
    end

    if not unit then
        Chat("Route leader not found in the current group. Use /trr routeleader target while targeting them, or /trr routeleader <name>.")
        return
    end

    manualRouteLeaderGUID = UnitGUID(unit)
    manualRouteLeaderName = UnitName(unit)
    Chat("raid route leader = " .. tostring(manualRouteLeaderName or unit) .. " (manual)")
    if currentRun then
        AddEvent("route_leader_manual", {guid=manualRouteLeaderGUID, name=manualRouteLeaderName})
        ApplyRouteLeaderEvidence()
    end
end

SLASH_TRIROUTESREC1 = "/trr"
SlashCmdList.TRIROUTESREC = function(msg)
    msg = tostring(msg or "")
    local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
    cmd = lower(cmd or "")
    if cmd == "" or cmd == "help" then
        Chat("/trr status | record | stop | auto on/off | difficulty auto/normal/heroic/mythic | routeleader auto|target|<name> | mark <pull|boss|turn|skip|warning|stairs> [note]")
    elseif cmd == "status" then
        Status()
    elseif cmd == "record" then
        manualPausedUntilLeave = false
        if not currentRun then StartRun("manual") else Chat("Already recording.") end
    elseif cmd == "stop" then
        manualPausedUntilLeave = true
        if currentRun then StopRun("manual") else Chat("No active recording.") end
    elseif cmd == "auto" then
        local val = lower(rest or "")
        db.settings.autoRecord = val ~= "off"
        Chat("auto-record " .. (db.settings.autoRecord and "ON" or "OFF"))
        if db.settings.autoRecord then EvaluateAuto("auto_enabled") end
    elseif cmd == "difficulty" then
        local val = lower(rest or "")
        if val == "auto" or val == "normal" or val == "heroic" or val == "mythic" then
            db.settings.difficulty = val
            Chat("difficulty detection mode = " .. val .. ". Applies to new recordings.")
        else
            Chat("Use: /trr difficulty auto|normal|heroic|mythic")
        end
    elseif cmd == "routeleader" or cmd == "leader" then
        SetRouteLeader(rest)
    elseif cmd == "mark" then
        local kind, note = string.match(rest or "", "^(%S*)%s*(.-)$")
        Mark(kind ~= "" and lower(kind) or "note", note)
    else
        Chat("Unknown command. /trr help")
    end
end
