-- TriRoutes standalone group-role/tank + Triumvirate Mythic detection.
-- Derived from the detection approaches previously proven in Shifty, but kept
-- self-contained so route collectors do not need Shifty installed.

TriRoutes = TriRoutes or {}
local TR = TriRoutes

local VERSION = "0.1.0-test6c"
TR.DETECTION_VERSION = VERSION

local lower = string.lower
local min = math.min
local max = math.max

local function Now()
    return GetTime and GetTime() or 0
end

local function Num(v)
    return tonumber(v)
end

local function Bool(v)
    return v == true or v == 1 or v == "1"
end

local function Trim(v)
    v = tostring(v or "")
    v = string.gsub(v, "^%s+", "")
    v = string.gsub(v, "%s+$", "")
    return v
end

local function PlainText(v)
    v = tostring(v or "")
    v = string.gsub(v, "|c%x%x%x%x%x%x%x%x", "")
    v = string.gsub(v, "|r", "")
    v = string.gsub(v, "|T.-|t", "")
    v = string.gsub(v, "||", "|")
    return Trim(v)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l end
    return nil
end

local function SafeMethod(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil, false end
    local ok, value = pcall(object[method], object, ...)
    if not ok then return nil, false end
    return value, true
end

local function UnitExistsSafe(unit)
    return unit and type(UnitExists) == "function" and SafeCall(UnitExists, unit) and true or false
end

local function UnitDead(unit)
    if not UnitExistsSafe(unit) then return false end
    if type(UnitIsDeadOrGhost) == "function" and SafeCall(UnitIsDeadOrGhost, unit) then return true end
    if type(UnitIsDead) == "function" and SafeCall(UnitIsDead, unit) then return true end
    return false
end

local function UnitAlive(unit)
    return UnitExistsSafe(unit) and not UnitDead(unit)
end

local function Friendly(unit)
    if not UnitAlive(unit) then return false end
    if type(UnitCanAssist) == "function" then return SafeCall(UnitCanAssist, "player", unit) and true or false end
    return unit == "player"
end

local function SameUnit(a, b)
    if not a or not b then return false end
    if type(UnitIsUnit) == "function" then
        local same = SafeCall(UnitIsUnit, a, b)
        if same ~= nil then return same and true or false end
    end
    if type(UnitGUID) == "function" then
        local ga, gb = SafeCall(UnitGUID, a), SafeCall(UnitGUID, b)
        if ga and gb then return ga == gb end
    end
    return tostring(a) == tostring(b)
end

local function FriendlyUnits()
    local units = {"player"}
    local raid = type(GetNumRaidMembers) == "function" and tonumber(SafeCall(GetNumRaidMembers) or 0) or 0
    local party = type(GetNumPartyMembers) == "function" and tonumber(SafeCall(GetNumPartyMembers) or 0) or 0
    if raid > 0 then
        for i = 1, math.min(40, raid) do units[#units + 1] = "raid" .. i end
    else
        for i = 1, math.min(4, party) do units[#units + 1] = "party" .. i end
    end
    return units
end

local function PlayerGrouped()
    local raid = type(GetNumRaidMembers) == "function" and tonumber(SafeCall(GetNumRaidMembers) or 0) or 0
    local party = type(GetNumPartyMembers) == "function" and tonumber(SafeCall(GetNumPartyMembers) or 0) or 0
    return raid > 0 or party > 0
end

local function AssignedGroupRole(unit)
    if not unit then return nil end

    if type(GetPartyAssignment) == "function" and SafeCall(GetPartyAssignment, "MAINTANK", unit) then
        return "TANK", "maintank-assignment", 1.0
    end

    if type(UnitGroupRolesAssigned) == "function" then
        local role = SafeCall(UnitGroupRolesAssigned, unit)
        role = string.upper(tostring(role or ""))
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
            return role, "group-role-api", 1.0
        end
    end

    local raidIndex = string.match(tostring(unit or ""), "^raid(%d+)$")
    if raidIndex and type(GetRaidRosterInfo) == "function" then
        local _, _, _, _, _, _, _, _, _, role = SafeCall(GetRaidRosterInfo, tonumber(raidIndex))
        if role == "MAINTANK" then return "TANK", "raid-maintank", 1.0 end
        if role == "MAINASSIST" then return "ASSIST", "raid-mainassist", 1.0 end
    end

    return nil
end

-- Keep learned tank identity stable across brief boss target swaps/loose mobs.
local tankInference = {
    unit = nil,
    candidate = nil,
    candidateSince = 0,
    lastEvidence = 0,
    evidence = 0,
    switchSuppressed = 0,
}

local function InferCombatTankUnit()
    local now = Now()
    local inCombat = type(UnitAffectingCombat) == "function" and SafeCall(UnitAffectingCombat, "player") and true or false
    if not PlayerGrouped() or not inCombat then
        if tankInference.lastEvidence > 0 and (now - tankInference.lastEvidence) > 8 then
            tankInference.unit = nil
            tankInference.candidate = nil
            tankInference.evidence = 0
            tankInference.switchSuppressed = 0
        end
        return nil, 0
    end

    local friends = FriendlyUnits()
    local counts, seenEnemy = {}, {}
    for i = 1, #friends do counts[friends[i]] = 0 end

    -- Each group member's current hostile target gives us another enemy we can
    -- inspect. The enemy's target then tells us which friendly is holding it.
    for i = 1, #friends do
        local observer = friends[i]
        local enemy = observer == "player" and "target" or (observer .. "target")
        if UnitAlive(enemy) and type(UnitCanAttack) == "function" and SafeCall(UnitCanAttack, "player", enemy) then
            local enemyKey = type(UnitGUID) == "function" and SafeCall(UnitGUID, enemy) or nil
            enemyKey = enemyKey or enemy
            if not seenEnemy[enemyKey] then
                seenEnemy[enemyKey] = true
                local victim = enemy .. "target"
                if UnitExistsSafe(victim) then
                    for j = 1, #friends do
                        local friend = friends[j]
                        if Friendly(friend) and SameUnit(victim, friend) then
                            counts[friend] = (counts[friend] or 0) + 1
                            break
                        end
                    end
                end
            end
        end
    end

    local best, bestScore, currentScore = nil, 0, 0
    for i = 1, #friends do
        local unit = friends[i]
        local score = counts[unit] or 0
        if tankInference.unit and SameUnit(unit, tankInference.unit) then currentScore = score end
        if score > bestScore or (score == bestScore and score > 0 and tankInference.unit and SameUnit(unit, tankInference.unit)) then
            best, bestScore = unit, score
        end
    end

    local current = tankInference.unit
    if current and Friendly(current) then
        if currentScore > 0 then
            tankInference.lastEvidence = now
            tankInference.evidence = currentScore
            tankInference.candidate = current
            tankInference.candidateSince = now
            return current, currentScore
        end

        if best and bestScore > 0 and not SameUnit(best, current) then
            if not (tankInference.candidate and SameUnit(best, tankInference.candidate)) then
                tankInference.candidate = best
                tankInference.candidateSince = now
            end
            local switchDelay = bestScore >= 3 and 0.75 or (bestScore >= 2 and 1.5 or 4.0)
            local oldEvidenceAge = now - (tankInference.lastEvidence or 0)
            local candidateAge = now - (tankInference.candidateSince or now)
            if oldEvidenceAge >= switchDelay and candidateAge >= switchDelay then
                tankInference.unit = best
                tankInference.lastEvidence = now
                tankInference.evidence = bestScore
                tankInference.switchSuppressed = 0
                return best, bestScore
            end
            tankInference.switchSuppressed = (tankInference.switchSuppressed or 0) + 1
            if oldEvidenceAge <= 8 then return current, tankInference.evidence or 1 end
        elseif (now - (tankInference.lastEvidence or 0)) <= 5 then
            return current, tankInference.evidence or 1
        end
    end

    if best and bestScore > 0 then
        if not (tankInference.candidate and SameUnit(best, tankInference.candidate)) then
            tankInference.candidate = best
            tankInference.candidateSince = now
        end
        -- A single mob briefly targeting someone is weak evidence.  Require a few
        -- seconds of persistence before learning a tank from one target; two or
        -- more independently observed enemies may establish the tank immediately.
        local stable = bestScore >= 2 or (now - (tankInference.candidateSince or now)) >= 3.0
        if stable then
            tankInference.unit = best
            tankInference.lastEvidence = now
            tankInference.evidence = bestScore
            tankInference.switchSuppressed = 0
            return best, bestScore
        end
    end

    return nil, bestScore or 0
end

local tankCacheAt, tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence = 0, nil, "none", 0, 0

local function EvidenceConfidence(evidence)
    evidence = tonumber(evidence or 0) or 0
    if evidence <= 0 then return 0 end
    return math.min(0.95, 0.58 + (evidence - 1) * 0.12)
end

function TR.GetGroupTankUnit(force)
    local now = Now()
    if not force and (now - tankCacheAt) < 0.15 then
        return tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence
    end

    local units = FriendlyUnits()
    for i = 1, #units do
        local unit = units[i]
        if Friendly(unit) and type(GetPartyAssignment) == "function" and SafeCall(GetPartyAssignment, "MAINTANK", unit) then
            tankCacheAt, tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence = now, unit, "maintank-assignment", 1.0, 99
            return tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence
        end
    end

    for i = 1, #units do
        local unit = units[i]
        local role = AssignedGroupRole(unit)
        if Friendly(unit) and role == "TANK" then
            tankCacheAt, tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence = now, unit, "group-role", 1.0, 99
            return tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence
        end
    end

    local inferred, evidence = InferCombatTankUnit()
    if inferred then
        tankCacheAt, tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence = now, inferred, "combat-target-evidence", EvidenceConfidence(evidence), evidence
        return tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence
    end

    tankCacheAt, tankCacheUnit, tankCacheSource, tankCacheConfidence, tankCacheEvidence = now, nil, "none", 0, evidence or 0
    return nil, "none", 0, evidence or 0
end

function TR.GetGroupRole(unit)
    if not UnitExistsSafe(unit) then return nil, "missing", 0 end

    local role, source, confidence = AssignedGroupRole(unit)
    if role then return role, source, confidence end

    local tank, tankSource, tankConfidence = TR.GetGroupTankUnit(false)
    if tank and SameUnit(unit, tank) then
        return "TANK", tankSource, tankConfidence
    end

    return nil, "unknown", 0
end

function TR.GetTankDetectionState()
    local unit, source, confidence, evidence = TR.GetGroupTankUnit(true)
    return {
        unit = unit,
        name = unit and type(UnitName) == "function" and SafeCall(UnitName, unit) or nil,
        guid = unit and type(UnitGUID) == "function" and SafeCall(UnitGUID, unit) or nil,
        source = source,
        confidence = confidence,
        evidence = evidence,
        switchSuppressed = tankInference.switchSuppressed or 0,
        version = VERSION,
    }
end

-- ---------------------------------------------------------------------------
-- Standalone Triumvirate Mythic bridge
-- ---------------------------------------------------------------------------

local mythicCache, mythicCacheAt = nil, 0
local timerCache = {frame=nil, tier=nil, tierText=nil, dungeonText=nil, mapId=nil, capturedAt=nil}

local DUNGEON_MAP_IDS = {
    ["utgarde keep"] = 574,
    ["utgarde pinnacle"] = 575,
    ["the nexus"] = 576,
    ["the oculus"] = 578,
    ["the culling of stratholme"] = 595,
    ["halls of stone"] = 599,
    ["drak'tharon keep"] = 600,
    ["azjol-nerub"] = 601,
    ["halls of lightning"] = 602,
    ["gundrak"] = 604,
    ["the violet hold"] = 608,
    ["ahn'kahet: the old kingdom"] = 619,
    ["the forge of souls"] = 632,
    ["trial of the champion"] = 650,
    ["pit of saron"] = 658,
    ["halls of reflection"] = 668,
    ["mana-tombs"] = 557,
}

local function CopyAffixes()
    local result = {}
    local frame = rawget(_G, "MythicPlusFrame")
    local source
    if frame then
        local ok, value = pcall(function() return frame.currentAffixes end)
        if ok then source = value end
    end
    if type(source) == "table" then
        for i = 1, math.min(4, #source) do
            local name = PlainText(source[i])
            if name ~= "" then result[#result + 1] = name end
        end
    end
    return result
end

local function AffixText(affixes)
    if type(affixes) ~= "table" or #affixes == 0 then return nil end
    return table.concat(affixes, ", ")
end

local function InstanceSnapshot()
    local data = {inInstance=false, instanceType="none"}
    if type(IsInInstance) == "function" then
        local ok, inside, kind = pcall(IsInInstance)
        if ok then
            data.inInstance = inside and true or false
            data.instanceType = tostring(kind or "none")
        end
    end
    if type(GetInstanceInfo) == "function" then
        local ok, name, kind, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic = pcall(GetInstanceInfo)
        if ok then
            data.instanceName = name
            data.instanceType = tostring(kind or data.instanceType or "none")
            data.difficultyID = Num(difficultyID)
            data.difficultyName = difficultyName
            data.maxPlayers = Num(maxPlayers)
            data.dynamicDifficulty = Num(dynamicDifficulty)
            data.isDynamic = isDynamic and true or false
        end
    end
    return data
end

local function FontRegionTexts(frame)
    local texts, seen = {}, {}
    if not frame or type(frame.GetRegions) ~= "function" then return texts end
    local ok, regions = pcall(function() return {frame:GetRegions()} end)
    if not ok or type(regions) ~= "table" then return texts end
    for i = 1, #regions do
        local region = regions[i]
        local objectType
        if region and type(region.GetObjectType) == "function" then
            local typeOk, value = pcall(region.GetObjectType, region)
            if typeOk then objectType = value end
        end
        if objectType == "FontString" and type(region.GetText) == "function" then
            local textOk, value = pcall(region.GetText, region)
            local plain = textOk and PlainText(value) or ""
            if plain ~= "" and not seen[plain] then
                seen[plain] = true
                texts[#texts + 1] = plain
            end
        end
    end
    return texts
end

local function TierFromText(text)
    text = PlainText(text)
    if text == "" then return nil end
    local tier = tonumber(string.match(text, "[Ll][Ee][Vv][Ee][Ll]%s*%+?%s*(%d+)"))
    if tier and tier > 0 and tier < 1000 then return tier end
    return nil
end

local function DungeonFromTexts(texts)
    for i = 1, #(texts or {}) do
        local plain = PlainText(texts[i])
        local mapId = DUNGEON_MAP_IDS[lower(plain)]
        if mapId then return plain, mapId end
    end
    return nil, nil
end

local function TimeTextFromTexts(texts)
    for i = 1, #(texts or {}) do
        local plain = PlainText(texts[i])
        if plain == "OVERTIME" or string.match(plain, "^%d+:%d%d$") then return plain end
    end
    return nil
end

local function TimerUISnapshot()
    local result = {detected=false, framePresent=false, frameShown=false, frameStopped=false, active=false}
    local ui = rawget(_G, "MythicBossTimerUI")
    if type(ui) ~= "table" or not ui.frame then
        timerCache.frame, timerCache.tier, timerCache.tierText, timerCache.dungeonText, timerCache.mapId, timerCache.capturedAt = nil, nil, nil, nil, nil, nil
        return result
    end

    local frame = ui.frame
    result.detected = true
    result.framePresent = true
    if timerCache.frame ~= frame then
        timerCache.frame, timerCache.tier, timerCache.tierText, timerCache.dungeonText, timerCache.mapId, timerCache.capturedAt = frame, nil, nil, nil, nil, nil
    end

    local shown, shownKnown = SafeMethod(frame, "IsShown")
    result.frameShown = shownKnown and shown and true or (not shownKnown)
    result.frameStopped = frame.stopped and true or false

    local texts = FontRegionTexts(frame)
    result.regionCount = #texts

    local directTier = Num(ui.tier or ui.level or ui.keyLevel)
    local tier, tierText
    if directTier and directTier > 0 then
        tier, tierText = directTier, tostring(directTier)
    else
        for i = 1, #texts do
            local candidate = TierFromText(texts[i])
            if candidate then tier, tierText = candidate, texts[i]; break end
        end
    end

    local dungeonText, mapId = DungeonFromTexts(texts)
    local clockText = TimeTextFromTexts(texts)
    if not clockText and ui.timerText and type(ui.timerText.GetText) == "function" then
        local ok, value = pcall(ui.timerText.GetText, ui.timerText)
        if ok then clockText = PlainText(value) end
    end

    if tier then
        timerCache.tier, timerCache.tierText, timerCache.capturedAt = tier, tierText, Now()
    end
    if dungeonText then
        timerCache.dungeonText, timerCache.mapId = dungeonText, mapId
    end

    result.tier = tier or timerCache.tier
    result.tierText = tierText or timerCache.tierText
    result.dungeonText = dungeonText or timerCache.dungeonText
    result.mapId = mapId or timerCache.mapId
    result.clockText = clockText
    result.capturedAt = timerCache.capturedAt
    result.active = result.framePresent and result.frameShown and result.tier and result.tier > 0 and true or false

    result.deaths = Num(ui.deaths)
    result.maxDeaths = Num(ui.maxDeaths)
    result.enemyForcesCurrent = Num(ui.enemiesCurrent)
    result.enemyForcesRequired = Num(ui.enemiesRequired)
    if ui.enemyProgressFrame then
        local value, known = SafeMethod(ui.enemyProgressFrame, "GetValue")
        if known then result.enemyForcesPercentage = Num(value) end
    end
    if not result.enemyForcesPercentage and ui.enemyPercentText and type(ui.enemyPercentText.GetText) == "function" then
        local ok, value = pcall(ui.enemyPercentText.GetText, ui.enemyPercentText)
        if ok then result.enemyForcesPercentage = Num(string.match(PlainText(value), "([%d%.]+)%%")) end
    end
    result.overtime = clockText == "OVERTIME" and true or false
    return result
end

local function BuildMythicContext()
    local state = rawget(_G, "MythicPlusCharRunState")
    local statePresent = type(state) == "table"
    local stateRawActive = statePresent and Bool(state.active)
    local stateTier = statePresent and Num(state.tier) or nil
    local stateActive = stateRawActive and stateTier and stateTier > 0 and true or false
    local timer = TimerUISnapshot()
    local timerActive = timer.active and true or false

    local active, tier, source
    if stateActive then
        active, tier, source = true, stateTier, "restored-state"
    elseif timerActive then
        active, tier, source = true, timer.tier, "timer-ui"
    else
        active = false
        tier = stateTier or timer.tier
        if timer.detected then
            source = timer.tier and "timer-ui-inactive" or "timer-ui-unresolved"
        elseif statePresent then
            source = "MythicPlusCharRunState"
        else
            source = "not-detected"
        end
    end

    local instance = InstanceSnapshot()
    local affixes = CopyAffixes()
    local forces = statePresent and type(state.enemyForces) == "table" and state.enemyForces or nil

    return {
        detected = statePresent or timer.detected,
        statePresent = statePresent,
        stateRawActive = stateRawActive,
        stateActive = stateActive,
        stateTier = stateTier,
        timerDetected = timer.detected,
        timerFramePresent = timer.framePresent,
        timerFrameShown = timer.frameShown,
        timerFrameStopped = timer.frameStopped,
        timerActive = timerActive,
        timerTier = timer.tier,
        timerTierText = timer.tierText,
        timerDungeonText = timer.dungeonText,
        timerClockText = timer.clockText,
        active = active,
        tier = tier,
        level = tier,
        mapId = (stateActive and Num(state.mapId)) or timer.mapId or (statePresent and Num(state.mapId) or nil),
        duration = stateActive and Num(state.duration) or nil,
        elapsed = stateActive and Num(state.elapsed) or nil,
        overtime = (stateActive and Bool(state.overtime)) or timer.overtime or false,
        deaths = (stateActive and Num(state.deaths)) or timer.deaths,
        maxDeaths = (stateActive and Num(state.maxDeaths)) or timer.maxDeaths,
        enemyForcesCurrent = (stateActive and forces and Num(forces.current)) or timer.enemyForcesCurrent,
        enemyForcesRequired = (stateActive and forces and Num(forces.required)) or timer.enemyForcesRequired,
        enemyForcesPercentage = (stateActive and forces and Num(forces.percentage)) or timer.enemyForcesPercentage,
        affixes = affixes,
        affixText = AffixText(affixes),
        source = source,
        detectorVersion = VERSION,
        inInstance = instance.inInstance,
        instanceType = instance.instanceType,
        instanceName = instance.instanceName,
        difficultyID = instance.difficultyID,
        difficultyName = instance.difficultyName,
        maxPlayers = instance.maxPlayers,
        dynamicDifficulty = instance.dynamicDifficulty,
        isDynamic = instance.isDynamic,
    }
end

function TR.GetMythicPlusContext(force)
    local now = Now()
    if not force and mythicCache and (now - mythicCacheAt) < 0.20 then return mythicCache end
    mythicCache = BuildMythicContext()
    mythicCacheAt = now
    return mythicCache
end

function TR.GetStandaloneDetectionStatus()
    return {
        version = VERSION,
        tank = TR.GetTankDetectionState(),
        mythic = TR.GetMythicPlusContext(true),
    }
end
