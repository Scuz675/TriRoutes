-- TriRoutes 0.1.0-test6c
-- WotLK 3.3.5a prototype: WDM/Astrolabe dungeon route overlays.

TriRoutes = TriRoutes or {}
local TR = TriRoutes
TR.VERSION = "0.1.0-test6c"

local floor = math.floor
local sqrt = math.sqrt
local abs = math.abs
local min = math.min
local max = math.max
local tinsert = table.insert
local tremove = table.remove
local format = string.format
local lower = string.lower
local find = string.find
local pi = math.pi
local rad = math.rad
local deg = math.deg
local atan = math.atan
local atan2_native = math.atan2
local sin = math.sin
local cos = math.cos

local function atan2deg(x, y)
    if atan2_native then
        return deg(atan2_native(x, y))
    end
    if y == 0 then
        if x > 0 then return 90 end
        if x < 0 then return -90 end
        return 0
    end
    local a = deg(atan(x / y))
    if y < 0 then
        if x >= 0 then a = a + 180 else a = a - 180 end
    end
    return a
end

local DEFAULTS = {
    enabled = true,
    showWorldMap = true,
    showMinimap = true,
    showLiveTrail = true,
    showComparisonOverlay = true,
    showDungeonFinderNeeds = true,
    trackMythicAnnouncements = true,
    showMythicDungeonFinder = true,
    showMythicTooltip = true,
    showMythicInspect = true,
    mythicTracker = { players={}, dungeons={} },
    autoUseLastRoute = true,
    routeMode = "auto", -- auto, off
    minimapAhead = 9,
    minimapBehind = 2,
    minimapScaleMode = "auto", -- auto, indoor, outdoor
    routePointSpacing = 0.0045,
    livePointSpacing = 0.0030,
    maxRoutePoints = 220,
    hud = true,
    arrow = true,
    arrowLocked = false,
    arrowScale = 1.15,
    arrowShowDistance = true,
    arrowPosition = {"CENTER", 0, -100},
    arrowLookAhead = 1,
    arrowHintShown = false,
    -- Stateful route progress. Normal movement advances against a continuous
    -- segment projection; large forward re-syncs are deliberately conservative
    -- so crossings/nearby later corridors cannot yank navigation ahead.
    routeProgressImmediateSegments = 6,
    routeProgressForwardSegments = 60,
    routeProgressGenericResyncMinIndex = 8,
    routeProgressResyncRadius = 0.018,
    routeProgressLocalRejectRadius = 0.035,
    routeProgressResyncConfirmSeconds = 0.45,
    routeProcessing = true,
    routeInputSpacing = 0.0015,
    routeSimplifyEpsilon = 0.0048,
    routeShortLoopRadius = 0.0065,
    routeShortLoopSeconds = 12,
    routeShortLoopMaxExtent = 0.025,
    routeTurnAngleDegrees = 48,
    routeTurnMinLeg = 0.010,
}

local db
local astrolabe
local libMapData
local activeRoute
local activeComparisonRoute
local activeRunId
local activeRouteIndex = 1
local activeRouteProgress = 1
local activeRouteProgressSynced = false
local activeRouteResyncCandidate
local activeRouteSkippedBranches = {}
local lastContextKey

local ROUTE_COLOR = {0.18, 0.82, 1.00, 0.94}
-- Route progression colours. Completed/behind is deliberately subdued, the
-- active leg is bright blue, and later route geometry is purple. This makes
-- crossings/return visits readable on compact dungeon maps and the minimap.
local ROUTE_PAST_COLOR = {0.20, 0.50, 0.78, 0.48}
local ROUTE_CURRENT_COLOR = {0.12, 0.68, 1.00, 1.00}
local ROUTE_NEXT_COLOR = {0.68, 0.34, 1.00, 0.92}
local ROUTE_PAST_DOT_COLOR = {0.28, 0.58, 0.82, 0.62}
local ROUTE_CURRENT_DOT_COLOR = {0.30, 0.80, 1.00, 1.00}
local ROUTE_NEXT_DOT_COLOR = {0.76, 0.48, 1.00, 1.00}
local TRAIL_COLOR = {0.65, 0.90, 1.00, 0.62}
local ROUTE_DOT_COLOR = {0.35, 0.90, 1.00, 1.00}
local ROUTE_PULL_DOT_COLOR = {1.00, 0.48, 0.10, 1.00}
local ROUTE_BOSS_DOT_COLOR = {1.00, 0.22, 0.22, 1.00}
local ROUTE_START_DOT_COLOR = {0.35, 1.00, 0.45, 1.00}
local ROUTE_END_DOT_COLOR = {0.78, 0.52, 1.00, 1.00}
local ROUTE_TURN_DOT_COLOR = {1.00, 0.92, 0.42, 1.00}
local TRAIL_DOT_COLOR = {0.45, 0.88, 1.00, 0.90}

-- Secondary route comparison colours. The primary route remains the only route
-- that owns progression, NEXT distance and the arrow. A Mythic comparison is
-- warm gold; a Normal/Heroic comparison is green. Segments that substantially
-- overlap the primary route are intentionally much fainter than divergences.
local COMPARE_MYTHIC_COLOR = {1.00, 0.67, 0.20, 0.66}
local COMPARE_MYTHIC_NEAR_COLOR = {1.00, 0.67, 0.20, 0.28}
local COMPARE_MYTHIC_SAME_COLOR = {1.00, 0.67, 0.20, 0.09}
local COMPARE_STANDARD_COLOR = {0.38, 0.96, 0.52, 0.58}
local COMPARE_STANDARD_NEAR_COLOR = {0.38, 0.96, 0.52, 0.25}
local COMPARE_STANDARD_SAME_COLOR = {0.38, 0.96, 0.52, 0.08}
local TRANSPARENT_DOT_COLOR = {1.00, 1.00, 1.00, 0.00}


-- Dungeon Finder route-collection dashboard.
--
-- TriRoutes intentionally does not reorder, resize, or replace Blizzard's LFD
-- controls.  It decorates the stock 3.3.5 specific-dungeon rows after Blizzard
-- has populated them, leaving checkboxes/locks/scrolling under Blizzard control.
-- N/H is one collection target because our curated standard routes are compatible
-- across Normal/Heroic.  Mythic is only requested for dungeons whose Mythic
-- availability has been confirmed on Triumvirate; unknown Mythic entries stay
-- out of the UI rather than becoming speculative chores.
local DUNGEON_COLLECTION_TARGETS = {
    -- Wrath
    { key="ahnkahet", label="Ahn'kahet: The Old Kingdom", group="WotLK", nh=true, aliases={"ahnkahettheoldkingdom", "ahnkahetoldkingdom"} },
    { key="azjolnerub", label="Azjol-Nerub", group="WotLK", nh=true, aliases={"azjolnerub"} },
    { key="draktharon", label="Drak'Tharon Keep", group="WotLK", nh=true, mythicConfirmed=true, aliases={"draktharonkeep", "draktharon"} },
    { key="gundrak", label="Gundrak", group="WotLK", nh=true, mythicConfirmed=true, aliases={"gundrak"} },
    { key="hallsoflightning", label="Halls of Lightning", group="WotLK", nh=true, aliases={"hallsoflightning"} },
    { key="hallsofstone", label="Halls of Stone", group="WotLK", nh=true, aliases={"hallsofstone"} },
    { key="pitofsaron", label="Pit of Saron", group="WotLK", nh=true, aliases={"pitofsaron"} },
    { key="culling", label="The Culling of Stratholme", group="WotLK", nh=true, aliases={"thecullingofstratholme", "cullingofstratholme"} },
    { key="forgeofsouls", label="The Forge of Souls", group="WotLK", nh=true, aliases={"theforgeofsouls", "forgeofsouls"} },
    { key="nexus", label="The Nexus", group="WotLK", nh=true, mythicConfirmed=true, aliases={"thenexus", "nexus"} },
    { key="oculus", label="The Oculus", group="WotLK", nh=true, aliases={"theoculus", "oculus"} },
    { key="utgardekeep", label="Utgarde Keep", group="WotLK", nh=true, mythicConfirmed=true, aliases={"utgardekeep"} },
    { key="utgardepinnacle", label="Utgarde Pinnacle", group="WotLK", nh=true, aliases={"utgardepinnacle"} },
    { key="violethold", label="Violet Hold", group="WotLK", nh=true, mythicConfirmed=true, aliases={"violethold"} },

    -- Burning Crusade
    { key="auchenai", label="Auchenai Crypts", group="TBC", nh=true, aliases={"auchenaicrypts", "auchindounauchenaicrypts"} },
    { key="bloodfurnace", label="Blood Furnace", group="TBC", nh=true, aliases={"bloodfurnace", "thebloodfurnace", "hellfirecitadelthebloodfurnace"} },
    { key="hellfireramparts", label="Hellfire Ramparts", group="TBC", nh=true, aliases={"hellfireramparts", "hellfirecitadelramparts", "hellfirecitadelhellfireramparts"} },
    { key="magistersterrace", label="Magisters' Terrace", group="TBC", nh=true, aliases={"magistersterrace"} },
    { key="manatombs", label="Mana-Tombs", group="TBC", nh=true, aliases={"manatombs", "auchindounmanatombs"} },
    { key="sethekk", label="Sethekk Halls", group="TBC", nh=true, aliases={"sethekkhalls", "auchindounsethekkhalls"} },
    { key="shadowlab", label="Shadow Labyrinth", group="TBC", nh=true, aliases={"shadowlabyrinth", "auchindounshadowlabyrinth"} },
    { key="shatteredhalls", label="Shattered Halls", group="TBC", nh=true, aliases={"shatteredhalls", "theshatteredhalls", "hellfirecitadeltheshatteredhalls"} },
    { key="slavepens", label="Slave Pens", group="TBC", nh=true, mythicConfirmed=true, aliases={"slavepens", "theslavepens", "coilfangtheslavepens", "coilfangreservoirtheslavepens"} },
    { key="arcatraz", label="The Arcatraz", group="TBC", nh=true, aliases={"thearcatraz", "arcatraz", "tempestkeepthearcatraz"} },
    { key="blackmorass", label="The Black Morass", group="TBC", nh=true, aliases={"theblackmorass", "blackmorass", "cavernsoftimetheblackmorass"} },
    { key="botanica", label="The Botanica", group="TBC", nh=true, aliases={"thebotanica", "botanica", "tempestkeepthebotanica"} },
    { key="durnholde", label="Escape From Durnholde", group="TBC", nh=true, aliases={"escapefromdurnholde", "oldhillsbradfoothills", "cavernsoftimeoldhillsbradfoothills"} },
    { key="mechanar", label="The Mechanar", group="TBC", nh=true, aliases={"themechanar", "mechanar", "tempestkeepthemechanar"} },
    { key="steamvault", label="The Steamvault", group="TBC", nh=true, aliases={"thesteamvault", "steamvault", "coilfangthesteamvault", "coilfangreservoirthesteamvault"} },
    { key="underbog", label="The Underbog", group="TBC", nh=true, aliases={"theunderbog", "underbog", "coilfangtheunderbog", "coilfangreservoirtheunderbog"} },
}

local collectionTargetByKey = {}
local collectionAliasToKey = {}
for _, target in ipairs(DUNGEON_COLLECTION_TARGETS) do
    collectionTargetByKey[target.key] = target
    for _, alias in ipairs(target.aliases or {}) do
        collectionAliasToKey[alias] = target.key
    end
end

local function CompactDungeonName(name)
    local s = lower(tostring(name or ""))
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "[^%a%d]", "")
    return s
end

local function ResolveCollectionTarget(name)
    local compact = CompactDungeonName(name)
    if compact == "" then return nil end
    local exact = collectionAliasToKey[compact]
    if exact then return collectionTargetByKey[exact] end

    -- Some 3.3.5 clients include wing/container prefixes in the API name even
    -- when the visible row is shorter.  Prefer the longest contained alias so
    -- generic aliases such as "nexus" cannot steal a more specific match.
    local bestKey, bestLen
    for alias, key in pairs(collectionAliasToKey) do
        if find(compact, alias, 1, true) then
            local n = string.len(alias)
            if not bestLen or n > bestLen then
                bestKey, bestLen = key, n
            end
        end
    end
    return bestKey and collectionTargetByKey[bestKey] or nil
end
TR.ResolveCollectionTarget = ResolveCollectionTarget

local function GetCollectionCoverage()
    local coverage = {}
    for _, target in ipairs(DUNGEON_COLLECTION_TARGETS) do
        coverage[target.key] = { nh=false, mythic=false, mythicTier=nil }
    end

    local pack = rawget(_G, "TriRoutesBuiltInRoutes")
    local routes = pack and type(pack.routes) == "table" and pack.routes or nil
    if routes then
        for _, route in ipairs(routes) do
            if route and route.instanceType == "party" then
                local target = ResolveCollectionTarget(route.instanceName)
                if target then
                    local entry = coverage[target.key]
                    if route.difficultyKey == "normal" or route.difficultyKey == "heroic" then
                        entry.nh = true
                    elseif route.difficultyKey == "mythic" then
                        entry.mythic = true
                        local tier = tonumber(route.recordedMythicTier or route.mythicTier)
                        if tier and (not entry.mythicTier or tier > entry.mythicTier) then
                            entry.mythicTier = tier
                        end
                    end
                end
            end
        end
    end
    return coverage
end

local function GetCollectionNeed(target, coverage)
    if not target then return nil end
    local have = coverage and coverage[target.key] or nil
    local needNH = target.nh and not (have and have.nh)
    local needMythic = target.mythicConfirmed and not (have and have.mythic)
    if not needNH and not needMythic then return nil end
    return { nh=not not needNH, mythic=not not needMythic }
end

function TR:GetDungeonFinderNeedsSummary()
    local coverage = GetCollectionCoverage()
    local result = { nh=0, mythic=0, total=0, haveNH=0, haveMythic=0, wotlkNH=0, tbcNH=0, entries={} }
    for _, target in ipairs(DUNGEON_COLLECTION_TARGETS) do
        local have = coverage[target.key]
        if have and have.nh then result.haveNH = result.haveNH + 1 end
        if have and have.mythic then result.haveMythic = result.haveMythic + 1 end

        local need = GetCollectionNeed(target, coverage)
        if need then
            if need.nh then
                result.nh = result.nh + 1
                if target.group == "WotLK" then result.wotlkNH = result.wotlkNH + 1 end
                if target.group == "TBC" then result.tbcNH = result.tbcNH + 1 end
            end
            if need.mythic then result.mythic = result.mythic + 1 end
            result.total = result.total + (need.nh and 1 or 0) + (need.mythic and 1 or 0)
            tinsert(result.entries, { key=target.key, label=target.label, group=target.group, nh=need.nh, mythic=need.mythic })
        end
    end
    return result, coverage
end

local dungeonFinderNeedsHooked = false
local dungeonFinderSummaryText

local function GetLFGDungeonNameByID(dungeonID)
    if not dungeonID or type(LFGGetDungeonInfoByID) ~= "function" then return nil end
    local ok, info = pcall(LFGGetDungeonInfoByID, dungeonID)
    if not ok or type(info) ~= "table" then return nil end
    local index = rawget(_G, "LFG_RETURN_VALUES")
    index = type(index) == "table" and index.name or nil
    return index and info[index] or nil
end

local function EnsureDungeonFinderButtonDecoration(button)
    if not button or button.trRoutesNeedsMarker then return end
    local marker = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marker:SetWidth(56)
    marker:SetJustifyH("RIGHT")
    marker:SetText("")
    marker:Hide()
    button.trRoutesNeedsMarker = marker

    -- Mythic+ rotation is deliberately a separate visual concept from route
    -- coverage. HC/M remain text coverage markers; this small gold rune means
    -- the dungeon has been observed through a completion or linked keystone.
    local mythicPlus = button:CreateTexture(nil, "OVERLAY")
    mythicPlus:SetWidth(13)
    mythicPlus:SetHeight(13)
    mythicPlus:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
    mythicPlus:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mythicPlus:SetVertexColor(1.00, 0.78, 0.18)
    mythicPlus:Hide()
    button.trRoutesMythicPlusMarker = mythicPlus

    if button.HookScript then
        button:HookScript("OnEnter", function(self)
            local have = self.trRoutesCoverage
            local observed = self.trRoutesMythicPlusObserved
            if not have and not observed then return end
            if GameTooltip then
                if not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
                if have then
                    local yes = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"
                    local no = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t"
                    local mythic = "Mythic"
                    if have.mythic and have.mythicTier then
                        mythic = "Mythic(+" .. tostring(have.mythicTier) .. ")"
                    end
                    GameTooltip:AddLine("HC " .. (have.nh and yes or no) .. "  " .. mythic .. " " .. (have.mythic and yes or no), 1.00, 1.00, 1.00, true)
                end
                if observed then
                    GameTooltip:AddLine("Mythic+ rotation: observed", 1.00, 0.82, 0.20, true)
                    if observed.highestSeen then
                        GameTooltip:AddLine("Highest observed completion: +" .. tostring(observed.highestSeen), 0.92, 0.92, 0.92, true)
                    end
                    if observed.highestAdvertised then
                        GameTooltip:AddLine("Highest advertised keystone: +" .. tostring(observed.highestAdvertised), 0.92, 0.92, 0.92, true)
                    end
                    if observed.highestSeen and observed.highestAdvertised then
                        GameTooltip:AddLine("Evidence: completions + linked keystones", 0.72, 0.76, 0.84, true)
                    elseif observed.highestSeen then
                        GameTooltip:AddLine("Evidence: completion announcements", 0.72, 0.76, 0.84, true)
                    elseif observed.highestAdvertised then
                        GameTooltip:AddLine("Evidence: linked keystones", 0.72, 0.76, 0.84, true)
                    end
                end
                GameTooltip:Show()
            end
        end)
        button:HookScript("OnLeave", function(self)
            if (self.trRoutesCoverage or self.trRoutesMythicPlusObserved) and GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
    end
end

function TR:DecorateDungeonFinderButton(button, dungeonID, coverage)
    if not button then return end
    EnsureDungeonFinderButtonDecoration(button)
    local marker = button.trRoutesNeedsMarker
    local mythicPlus = button.trRoutesMythicPlusMarker
    button.trRoutesNeed = nil
    button.trRoutesNeedTarget = nil
    button.trRoutesCoverage = nil
    button.trRoutesMythicPlusObserved = nil
    marker:Hide()
    if mythicPlus then mythicPlus:Hide() end

    if not db or (not db.showDungeonFinderNeeds and not db.showMythicDungeonFinder) then return end
    if type(LFGIsIDHeader) == "function" then
        local ok, isHeader = pcall(LFGIsIDHeader, dungeonID)
        if ok and isHeader then return end
    end

    local target = ResolveCollectionTarget(GetLFGDungeonNameByID(dungeonID))
    if not target then return end
    coverage = coverage or GetCollectionCoverage()
    local have = coverage[target.key] or { nh=false, mythic=false, mythicTier=nil }
    local need = GetCollectionNeed(target, coverage)
    local observed = nil
    if db.showMythicDungeonFinder and type(TR.GetMythicRotationEntry) == "function" then
        observed = TR:GetMythicRotationEntry(target.key)
    end

    -- Keep the historical fields populated for compatibility with any local
    -- debugging/macros, but the visible row now reports coverage we HAVE.
    button.trRoutesNeed = need
    button.trRoutesNeedTarget = target
    button.trRoutesCoverage = db.showDungeonFinderNeeds and have or nil
    button.trRoutesMythicPlusObserved = observed

    if observed and mythicPlus then
        mythicPlus:ClearAllPoints()
        if button.level and button.level:IsShown() then
            mythicPlus:SetPoint("RIGHT", button.level, "LEFT", -3, 0)
        else
            mythicPlus:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        end
        mythicPlus:Show()
    end

    local text
    if db.showDungeonFinderNeeds then
        if have.nh and have.mythic then
            text = "|cff79d8ffHC|r |cffbf86ffM|r"
        elseif have.nh then
            text = "|cff79d8ffHC|r"
        elseif have.mythic then
            text = "|cffbf86ffM|r"
        end
    end

    if text then
        marker:SetText(text)
        marker:ClearAllPoints()
        if observed and mythicPlus then
            marker:SetPoint("RIGHT", mythicPlus, "LEFT", -2, 0)
        elseif button.level and button.level:IsShown() then
            marker:SetPoint("RIGHT", button.level, "LEFT", -3, 0)
        else
            marker:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        end
        marker:Show()
    end

    -- Blizzard's own setter has just reset this anchor. Move only the right edge
    -- of the dungeon name left of our decorations; checkbox/level/lock geometry
    -- stays untouched.
    if button.instanceName then
        if text then
            button.instanceName:SetPoint("RIGHT", marker, "LEFT", -4, 0)
        elseif observed and mythicPlus then
            button.instanceName:SetPoint("RIGHT", mythicPlus, "LEFT", -4, 0)
        end
    end
end

local function EnsureDungeonFinderSummary()
    if dungeonFinderSummaryText then return dungeonFinderSummaryText end
    local parent = rawget(_G, "LFDQueueFrameSpecific")
    if not parent or not parent.CreateFontString then return nil end
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local firstButton = rawget(_G, "LFDQueueFrameSpecificListButton1")
    if firstButton then
        text:SetPoint("BOTTOMLEFT", firstButton, "TOPLEFT", 0, 2)
    else
        text:SetPoint("TOPLEFT", parent, "TOPLEFT", 25, -147)
    end
    text:SetWidth(285)
    text:SetJustifyH("LEFT")
    text:SetText("")
    dungeonFinderSummaryText = text
    return text
end

function TR:UpdateDungeonFinderNeeds()
    local summary = EnsureDungeonFinderSummary()
    if not db or (not db.showDungeonFinderNeeds and not db.showMythicDungeonFinder) then
        if summary then summary:Hide() end
        for i=1, tonumber(rawget(_G, "NUM_LFD_CHOICE_BUTTONS") or 15) do
            local button = rawget(_G, "LFDQueueFrameSpecificListButton" .. i)
            if button and button.trRoutesNeedsMarker then
                button.trRoutesNeed = nil
                button.trRoutesCoverage = nil
                button.trRoutesMythicPlusObserved = nil
                button.trRoutesNeedsMarker:Hide()
                if button.trRoutesMythicPlusMarker then button.trRoutesMythicPlusMarker:Hide() end
            end
        end
        return
    end

    local needs, coverage = self:GetDungeonFinderNeedsSummary()
    if summary then
        if db.showDungeonFinderNeeds then
            summary:SetText(format("|cffffd54fTriRoutes:|r %d |cff79d8ffHC|r  |  %d |cffbf86ffM|r routes", needs.haveNH or 0, needs.haveMythic or 0))
            summary:Show()
        else
            summary:Hide()
        end
    end

    for i=1, tonumber(rawget(_G, "NUM_LFD_CHOICE_BUTTONS") or 15) do
        local button = rawget(_G, "LFDQueueFrameSpecificListButton" .. i)
        if button and button:IsShown() and button.id then
            self:DecorateDungeonFinderButton(button, button.id, coverage)
        elseif button and button.trRoutesNeedsMarker then
            button.trRoutesNeed = nil
            button.trRoutesCoverage = nil
            button.trRoutesMythicPlusObserved = nil
            button.trRoutesNeedsMarker:Hide()
            if button.trRoutesMythicPlusMarker then button.trRoutesMythicPlusMarker:Hide() end
        end
    end
end

function TR:TryHookDungeonFinderNeeds()
    if dungeonFinderNeedsHooked then
        self:UpdateDungeonFinderNeeds()
        return true
    end
    if type(hooksecurefunc) ~= "function" then return false end
    if type(rawget(_G, "LFDQueueFrameSpecificListButton_SetDungeon")) ~= "function" then return false end
    if type(rawget(_G, "LFDQueueFrameSpecificList_Update")) ~= "function" then return false end

    hooksecurefunc("LFDQueueFrameSpecificListButton_SetDungeon", function(button, dungeonID)
        if db then TR:DecorateDungeonFinderButton(button, dungeonID) end
    end)
    hooksecurefunc("LFDQueueFrameSpecificList_Update", function()
        if db then TR:UpdateDungeonFinderNeeds() end
    end)

    local parent = rawget(_G, "LFDParentFrame")
    if parent and parent.HookScript then
        parent:HookScript("OnShow", function() if db then TR:UpdateDungeonFinderNeeds() end end)
    end
    dungeonFinderNeedsHooked = true
    self:UpdateDungeonFinderNeeds()
    return true
end

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

local function Chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFD54FTriRoutes:|r " .. tostring(msg))
    end
end

local function GetAstrolabe()
    if astrolabe then return astrolabe end
    if DongleStub then
        local ok, lib = pcall(DongleStub, "Astrolabe-0.4")
        if ok and lib then
            astrolabe = lib
            return astrolabe
        end
    end
    return nil
end
TR.GetAstrolabe = GetAstrolabe

local function GetLibMapData()
    if libMapData then return libMapData end
    if LibStub then
        local ok, lib = pcall(LibStub, "LibMapData-1.0", true)
        if ok and lib then
            libMapData = lib
            return libMapData
        end
    end
    return nil
end
TR.GetLibMapData = GetLibMapData

-- Questie-335-Triumvirate already has a heavily-tested HereBeDragons compatibility
-- layer that successfully places dungeon quest pins on the user's minimap. Prefer
-- that exact navigation stack when it is available instead of maintaining a
-- second interpretation of WDM dungeon coordinates.
local function GetQuestieNavigation()
    local QC = rawget(_G, "QuestieCompat")
    local HBD = type(QC) == "table" and QC.HBD or nil
    local Pins = type(QC) == "table" and QC.HBDPins or nil

    -- Match Questie's own waypoint-arrow import path: its fork can expose HBD
    -- either through QuestieCompat or through the embedded LibStub libraries.
    if LibStub then
        if not HBD then
            local ok, lib = pcall(LibStub, "HereBeDragonsQuestie-2.0", true)
            if ok and lib then HBD = lib end
        end
        if not HBD then
            local ok, lib = pcall(LibStub, "HereBeDragons-2.0", true)
            if ok and lib then HBD = lib end
        end
        if not Pins then
            local ok, lib = pcall(LibStub, "HereBeDragonsQuestie-Pins-2.0", true)
            if ok and lib then Pins = lib end
        end
        if not Pins then
            local ok, lib = pcall(LibStub, "HereBeDragons-Pins-2.0", true)
            if ok and lib then Pins = lib end
        end
    end

    local uiMapID
    if type(QC) == "table" and type(QC.GetCurrentUiMapID) == "function" then
        local ok, id = pcall(QC.GetCurrentUiMapID)
        if ok and type(id) == "number" then uiMapID = id end
    end
    if (not uiMapID) and HBD and type(HBD.GetPlayerZone) == "function" then
        local ok, id = pcall(HBD.GetPlayerZone, HBD)
        if ok and type(id) == "number" then uiMapID = id end
    end
    if not HBD then return nil end
    return HBD, Pins, uiMapID
end
TR.GetQuestieNavigation = GetQuestieNavigation

local lastMapMetrics
local function CanonicalDungeonMapFile(rawMapFile, instanceName)
    local BM = rawget(_G, "TriRoutesBundledMapMetrics")
    if BM and type(BM.CanonicalMapFile) == "function" then
        local ok, canonical = pcall(BM.CanonicalMapFile, BM, rawMapFile, instanceName)
        if ok and canonical and canonical ~= "" then return canonical end
    end
    return rawMapFile
end
local function GetDungeonMapMetrics(force)
    -- Keep the last confirmed dungeon dimensions while the world map is open;
    -- users can pan/zoom the visible map without breaking minimap navigation.
    if not force and lastMapMetrics and WorldMapFrame and WorldMapFrame:IsShown() then
        return lastMapMetrics.width, lastMapMetrics.height, lastMapMetrics.mapFile, lastMapMetrics.floor, lastMapMetrics.source
    end

    local function ReadCurrentMetrics()
        local rawMapFile = GetMapInfo and GetMapInfo() or nil
        local instanceName = GetInstanceInfo and GetInstanceInfo() or nil
        local mapFile = CanonicalDungeonMapFile(rawMapFile, instanceName)
        local mapFloor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
        local areaID = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
        local width, height, source
        local LMD = GetLibMapData()

        if LMD and LMD.MapArea then
            -- WDM-restored maps can report a stale/mismatched numeric area ID.
            -- Prefer the explicit map file; use areaID only as a fallback.
            if mapFile then
                local ok, w, h = pcall(LMD.MapArea, LMD, mapFile, mapFloor)
                if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
                    width, height, source = w, h, "LibMapData-file"
                end
            end
            if (not width) and areaID and areaID > 0 then
                local ok, w, h = pcall(LMD.MapArea, LMD, areaID, mapFloor)
                if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
                    width, height, source = w, h, "LibMapData-area"
                end
            end
        end

        -- test4f bundles the factual 3.3.5/WDM dungeon dimensions TriRoutes
        -- needs for local minimap scaling. The MPQ can provide the restored map
        -- without loading a Lua addon named WDM, so do not make minimap routing
        -- depend on WDM/LibMapData being present as addons.
        if not width then
            local BM = rawget(_G, "TriRoutesBundledMapMetrics")
            if BM and type(BM.Get) == "function" then
                local ok, w, h = pcall(BM.Get, BM, mapFile, areaID, mapFloor, instanceName)
                if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
                    width, height, source = w, h, "TriRoutes-bundled-WDM"
                end
            end
        end

        -- WDM extends GetCurrentMapZone() with map bounds. This works even if
        -- the companion LibMapData addon is not installed, provided the current
        -- map has first been switched to the actual instance map.
        if (not width) and GetCurrentMapZone then
            local _, left, top, right, bottom = GetCurrentMapZone()
            if type(left) == "number" and type(top) == "number" and type(right) == "number" and type(bottom) == "number" then
                local w = abs(right - left)
                local h = abs(top - bottom)
                if w > 1 and h > 1 then
                    width, height, source = w, h, "WDM-map-bounds"
                end
            end
        end

        return width, height, mapFile, mapFloor, source, areaID
    end

    local width, height, mapFile, mapFloor, source, areaID = ReadCurrentMetrics()
    local key = tostring(areaID or mapFile or "?") .. "|" .. tostring(mapFloor or 0)
    if not force and lastMapMetrics and lastMapMetrics.key == key then
        return lastMapMetrics.width, lastMapMetrics.height, lastMapMetrics.mapFile, lastMapMetrics.floor, lastMapMetrics.source
    end

    if (not width) and SetMapToCurrentZone and (not WorldMapFrame or not WorldMapFrame:IsShown()) then
        -- Crucially, repeat *all* probes after SetMapToCurrentZone(). test4c
        -- retried LibMapData here but forgot to retry WDM's raw map bounds.
        SetMapToCurrentZone()
        width, height, mapFile, mapFloor, source, areaID = ReadCurrentMetrics()
        key = tostring(areaID or mapFile or "?") .. "|" .. tostring(mapFloor or 0)
    end

    if width and height then
        lastMapMetrics = {key=key, width=width, height=height, mapFile=mapFile, floor=mapFloor, source=source}
        return width, height, mapFile, mapFloor, source
    end
    return nil, nil, mapFile, mapFloor, nil
end
TR.GetDungeonMapMetrics = GetDungeonMapMetrics

local function NormalizeDifficulty(instanceType, difficultyIndex, difficultyName, mythic)
    if mythic and mythic.active and mythic.inInstance and (mythic.instanceType == "party" or instanceType == "party") then
        return "mythic", "triroutes-mythic"
    end
    local n = lower(tostring(difficultyName or ""))
    if find(n, "mythic", 1, true) then return "mythic", "instance-name" end
    if find(n, "heroic", 1, true) then return "heroic", "instance-api" end
    if find(n, "normal", 1, true) then return "normal", "instance-api" end
    local idx = tonumber(difficultyIndex)
    if instanceType == "party" and idx == 2 then return "heroic", "instance-api" end
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

function TR:GetContext()
    if TriRoutesRecorderRuntime and TriRoutesRecorderRuntime.GetContext then
        local ok, ctx = pcall(TriRoutesRecorderRuntime.GetContext)
        if ok and ctx then return ctx end
    end
    local name, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic = GetInstanceInfo()
    local inInstance = IsInInstance()
    local mythic = type(TR.GetMythicPlusContext) == "function" and TR.GetMythicPlusContext(true) or nil
    local difficultyKey, difficultySource = NormalizeDifficulty(instanceType, difficultyIndex, difficultyName, mythic)
    local raidSize = NormalizeRaidSize(instanceType, maxPlayers, difficultyIndex)
    return {
        inInstance = inInstance and true or false,
        instanceName = name,
        instanceType = instanceType,
        difficultyIndex = difficultyIndex,
        difficultyName = difficultyName,
        difficultyKey = difficultyKey,
        difficultySource = difficultySource,
        mythicTier = mythic and mythic.tier or nil,
        mythicSource = mythic and mythic.source or nil,
        maxPlayers = maxPlayers,
        raidSize = raidSize,
        raidMode = raidSize and (tostring(raidSize) .. "-" .. tostring(difficultyKey)) or nil,
        dynamicDifficulty = dynamicDifficulty,
        isDynamic = isDynamic,
    }
end

local function ContextKey(ctx)
    if not ctx or not ctx.inInstance then return "world" end
    local raidPart = ctx.instanceType == "raid" and ("|" .. tostring(ctx.raidSize or ctx.maxPlayers or "?")) or ""
    return tostring(ctx.instanceName or "?") .. "|" .. tostring(ctx.difficultyKey or "?") .. raidPart
end

local function GetPlayerPosition()
    local A = GetAstrolabe()
    if A and A.GetCurrentPlayerPosition then
        local c, z, x, y = A:GetCurrentPlayerPosition()
        if c and x and y and x > 0 and y > 0 then
            return c, z or 0, x, y
        end
    end
    local x, y = GetPlayerMapPosition("player")
    if x and y and (x > 0 or y > 0) then
        return GetCurrentMapContinent(), GetCurrentMapZone(), x, y
    end
end
TR.GetPlayerPosition = GetPlayerPosition

local function CurrentSectionIndex()
    local run = TriRoutesRecorderRuntime and TriRoutesRecorderRuntime.currentRun
    return run and (run.sectionIndex or 1) or nil
end

local function SameRouteContext(a, b)
    if not a or not b or a.c ~= b.c or a.z ~= b.z then return false end
    -- Recorder section numbers are provenance, not physical navigation context.
    -- A wipe/release creates a continuation run with sectionIndex+1; rejecting
    -- route points from the previous section made the arrow/minimap disappear
    -- even though the player was still in the same dungeon. Real discontinuities
    -- are represented by floor/phase context and explicit breakBefore markers.
    -- Built-in routes must survive across recorder sessions, so WDM floor is a
    -- stronger identity than the recorder's run-local mapPhase counter.
    if a.floor and b.floor and a.floor > 0 and b.floor > 0 then
        if a.floor ~= b.floor then return false end
    elseif a.phase and b.phase and a.phase ~= b.phase then
        return false
    end
    return true
end

local function CanonicalSingleFloor(mapFile, floor)
    local BM = rawget(_G, "TriRoutesBundledMapMetrics")
    local entry = BM and BM.byName and mapFile and BM.byName[mapFile] or nil
    local floors = entry and entry.floors or nil
    if type(floors) ~= "table" then return floor end
    local onlyFloor, count
    count = 0
    for k in pairs(floors) do
        count = count + 1
        onlyFloor = k
        if count > 1 then return floor end
    end
    if count == 1 then return tonumber(onlyFloor) or floor end
    return floor
end

local function MakePlayerPoint(c, z, x, y)
    local run = TriRoutesRecorderRuntime and TriRoutesRecorderRuntime.currentRun
    local rawMapFile = GetMapInfo and GetMapInfo() or nil
    local instanceName = GetInstanceInfo and GetInstanceInfo() or nil
    local mapFile = CanonicalDungeonMapFile(rawMapFile, instanceName)
    local mapFloor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or nil
    if not mapFloor or mapFloor <= 0 then mapFloor = run and run.currentMapFloor or nil end

    -- Restored WDM dungeon coordinates use c=-1.  Astrolabe can briefly expose
    -- a different zone index after a reload/instance transition even though x/y
    -- are still in the same dungeon-local coordinate space.  Built-in routes are
    -- intentionally stored with z=0, so canonicalise the live point too rather
    -- than making minimap visibility depend on that transient value.
    local localDungeon = c and c < 0
    if localDungeon then
        z = 0
        -- Ahn'kahet and other single-floor restored maps can also transiently
        -- report floor 0/2 while the recorder is initialising.  If the bundled
        -- WDM metric proves the map has exactly one floor, that floor is the only
        -- meaningful navigation context and is safe to canonicalise.
        mapFloor = CanonicalSingleFloor(mapFile, mapFloor)
    end

    return {
        c=c, z=z or 0, x=x, y=y,
        section=run and (run.sectionIndex or 1) or nil,
        phase=run and (run.mapPhase or 1) or nil,
        floor=mapFloor, mapFile=mapFile,
    }
end

local function DistNorm(a, b)
    if not SameRouteContext(a, b) then return 999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return sqrt(dx * dx + dy * dy)
end

local function DistYards(a, b)
    if not a or not b then return nil end
    local norm = DistNorm(a, b)
    if a.c and b.c and a.c >= 0 and b.c >= 0 then
        local A = GetAstrolabe()
        if A and A.ComputeDistance then
            local ok, d = pcall(A.ComputeDistance, A, a.c, a.z or 0, a.x, a.y, b.c, b.z or 0, b.x, b.y)
            if ok and d and (d > 0.01 or norm <= 0.00001) then return d end
        end
    end
    if SameRouteContext(a, b) then
        local width, height = GetDungeonMapMetrics(false)
        if width and height then
            local dx = ((b.x or 0) - (a.x or 0)) * width
            local dy = ((b.y or 0) - (a.y or 0)) * height
            return sqrt(dx * dx + dy * dy)
        end
        -- Diagnostic-only fallback if the WDM LibMapData helper is absent.
        return norm * 10000
    end
end

local function RouteDeltaYards(a, b)
    if not SameRouteContext(a, b) then return nil end
    if a.c and a.c >= 0 then
        local A = GetAstrolabe()
        if A and A.ComputeDistance then
            local ok, d, dx, dy = pcall(A.ComputeDistance, A, a.c, a.z or 0, a.x, a.y, b.c, b.z or 0, b.x, b.y)
            if ok and d and dx and dy then return d, dx, dy end
        end
    end
    local width, height = GetDungeonMapMetrics(false)
    if width and height then
        local dx = ((b.x or 0) - (a.x or 0)) * width
        local dy = ((b.y or 0) - (a.y or 0)) * height
        return sqrt(dx * dx + dy * dy), dx, dy
    end
end

local lastArrowNavSource = "none"
local lastMinimapNavSource = "none"

local function GetQuestieRouteVector(player, targetPoint)
    local HBD, _, uiMapID = GetQuestieNavigation()
    if not HBD or not uiMapID or not HBD.GetWorldCoordinatesFromZone or not HBD.GetPlayerWorldPosition then return nil end

    local okT, targetX, targetY, targetInstance = pcall(HBD.GetWorldCoordinatesFromZone, HBD, targetPoint.x, targetPoint.y, uiMapID)
    local okP, playerX, playerY, playerInstance = pcall(HBD.GetPlayerWorldPosition, HBD)
    if not okT or not okP or not targetX or not targetY or not playerX or not playerY then return nil end
    if targetInstance and playerInstance and targetInstance ~= playerInstance then return nil end

    local distance
    if HBD.GetWorldDistance then
        local okD, d = pcall(HBD.GetWorldDistance, HBD, playerInstance or targetInstance, playerX, playerY, targetX, targetY)
        if okD then distance = d end
    end

    -- Match the proven Questie arrow exactly. HBD converts local map positions
    -- as left-width*x/top-height*y, so player-target world coordinates are the
    -- map-style vector to the destination. The 1.5 X correction is retained
    -- from the user's Questie fork because it fixed the old 3.3.5 arrow heading.
    local xDelta = (playerX - targetX) * 1.5
    local yDelta = (playerY - targetY)
    return distance, xDelta, yDelta, "Questie-HBD"
end

local function GetRouteVector(player, targetPoint)
    if player and targetPoint and player.c and targetPoint.c and player.c < 0 and targetPoint.c < 0 then
        local d, dx, dy, source = GetQuestieRouteVector(player, targetPoint)
        if dx and dy then return d, dx, dy, source end
    end

    local d, dx, dy = RouteDeltaYards(player, targetPoint)
    if dx and dy then return d, dx, dy, "WDM-yards" end

    -- Last-resort heading fallback. Direction should never disappear merely
    -- because map dimensions are unavailable; normalized WDM coordinates are
    -- still enough to point toward the next node.
    if player and targetPoint and SameRouteContext(player, targetPoint) then
        dx = ((targetPoint.x or 0) - (player.x or 0)) * 1.5
        dy = ((targetPoint.y or 0) - (player.y or 0))
        if abs(dx) > 0.000001 or abs(dy) > 0.000001 then
            return nil, dx, dy, "WDM-normalized"
        end
    end
    return nil
end

-- Questie's proven 3.3.5 waypoint-line texture renderer.

-- Iriel/Blizzard taxi-route style texture line drawing, adapted for 3.3.5.
local ROUTE_LINE_TEXTURE = "Interface\\AddOns\\TriRoutes\\Media\\Waypoint-Line.blp"

local function HideLines(canvas)
    if not canvas or not canvas.TriRoutesLinesUsed then return end
    canvas.TriRoutesLinesFree = canvas.TriRoutesLinesFree or {}
    for i = #canvas.TriRoutesLinesUsed, 1, -1 do
        local tex = tremove(canvas.TriRoutesLinesUsed)
        tex:Hide()
        tinsert(canvas.TriRoutesLinesFree, tex)
    end
end

-- Ported from Questie's 3.3.5 Compat.CreateLine path. The BLP has internal
-- padding, hence the same *15 thickness conversion used by Questie.
local function DrawLine(canvas, sx, sy, ex, ey, width, color, layer)
    if not canvas then return end
    canvas.TriRoutesLinesFree = canvas.TriRoutesLinesFree or {}
    canvas.TriRoutesLinesUsed = canvas.TriRoutesLinesUsed or {}

    local T = tremove(canvas.TriRoutesLinesFree) or canvas:CreateTexture(nil, layer or "OVERLAY")
    T:SetTexture(ROUTE_LINE_TEXTURE)
    T:SetDrawLayer(layer or "OVERLAY")
    T:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    tinsert(canvas.TriRoutesLinesUsed, T)

    local lineWidth = (width or 1.5) * 15
    local lineFactor = 1.2 * 0.5
    local dx, dy = ex - sx, ey - sy
    local cx, cy = (sx + ex) / 2, (sy + ey) / 2
    if dx < 0 then dx, dy = -dx, -dy end
    local lineLength = sqrt((dx * dx) + (dy * dy))
    if lineLength <= 0.001 then
        T:Hide()
        return T
    end

    local sn, cs = -dy / lineLength, dx / lineLength
    local sncs = sn * cs
    local bw, bh, blx, bly, tlx, tly, trx, try_, brx, bry
    if dy >= 0 then
        bw = ((lineLength * cs) - (lineWidth * sn)) * lineFactor
        bh = ((lineWidth * cs) - (lineLength * sn)) * lineFactor
        blx = (lineWidth / lineLength) * sncs
        bly = sn * sn
        bry = (lineLength / lineWidth) * sncs
        brx = 1 - bly
        tlx = bly
        tly = 1 - bry
        trx = 1 - blx
        try_ = brx
    else
        bw = ((lineLength * cs) + (lineWidth * sn)) * lineFactor
        bh = ((lineWidth * cs) + (lineLength * sn)) * lineFactor
        blx = sn * sn
        bly = -(lineLength / lineWidth) * sncs
        brx = 1 + (lineWidth / lineLength) * sncs
        bry = blx
        tlx = 1 - brx
        tly = 1 - blx
        try_ = 1 - bly
        trx = tly
    end

    T:ClearAllPoints()
    T:SetTexCoord(tlx, tly, blx, bly, trx, try_, brx, bry)
    T:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", cx - bw, cy - bh)
    T:SetPoint("TOPRIGHT", canvas, "BOTTOMLEFT", cx + bw, cy + bh)
    T:Show()
    return T
end

local function NewDot(parent, size, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(size)
    f:SetHeight(size)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    f.tex = t
    f:Hide()
    return f
end

local worldRouteDots = {}
local worldCompareDots = {}
local worldTrailDots = {}
local miniRouteDots = {}
local miniCompareDots = {}
local miniTrailDots = {}

local function GetDot(pool, index, parent, size, color)
    local f = pool[index]
    if not f then
        f = NewDot(parent, size, color)
        pool[index] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    f:SetWidth(size)
    f:SetHeight(size)
    return f
end

local function HideWorldDots(pool, from)
    for i = from or 1, #pool do pool[i]:Hide() end
end

local function ClearMiniDots(pool)
    local A = GetAstrolabe()
    local _, QPins = GetQuestieNavigation()
    for i = 1, #pool do
        local f = pool[i]
        if f._trQuestiePlaced and QPins and QPins.RemoveMinimapIcon then
            pcall(QPins.RemoveMinimapIcon, QPins, TR, f)
        end
        if f._trPlaced and A and A.RemoveIconFromMinimap then
            pcall(A.RemoveIconFromMinimap, A, f)
        end
        f._trQuestiePlaced = nil
        f._trPlaced = nil
        f:Hide()
    end
end

local function SampleToPoint(s)
    if not s then return nil end
    return {c = s.c, z = s.z or 0, x = s.x, y = s.y, t = s.t, section = s.section, phase = s.phase, floor = s.floor, mapFile = s.mapFile, recovery = s.recovery}
end

local function SimplifySamples(samples, spacing, maxPoints)
    if not samples or #samples == 0 then return {} end
    spacing = spacing or 0.004
    maxPoints = maxPoints or 220

    local function Pass(gap)
        local out = {}
        local last
        for i = 1, #samples do
            local s = samples[i]
            if s and not s.recovery and s.c and s.x and s.y then
                local p = SampleToPoint(s)
                if not last or not SameRouteContext(p, last) or DistNorm(p, last) >= gap then
                    out[#out + 1] = p
                    last = p
                end
            end
        end
        local tail = samples[#samples]
        if tail and not tail.recovery and tail.c and tail.x and tail.y then
            local p = SampleToPoint(tail)
            if #out == 0 or DistNorm(p, out[#out]) > 0.0001 or not SameRouteContext(p, out[#out]) then
                out[#out + 1] = p
            end
        end
        return out
    end

    local gap = spacing
    local out = Pass(gap)
    local guard = 0
    while #out > maxPoints and guard < 8 do
        gap = gap * 1.45
        out = Pass(gap)
        guard = guard + 1
    end
    return out
end

local function IsSparsePartyGeometryTrack(run, track)
    if not run or run.instanceType ~= "party" or not track or track.isPlayer or type(track.samples) ~= "table" then return false end
    local playerTrack = run.player and run.tracks and run.tracks[run.player.guid]
    local playerN = playerTrack and playerTrack.samples and #playerTrack.samples or 0
    local n = #track.samples
    return playerN >= 20 and (n < 20 or n < playerN * 0.25)
end

local function TrackScore(track, run)
    if not track or not track.samples then return -1 end
    local score = #track.samples
    local sparse = IsSparsePartyGeometryTrack(run, track)
    if not sparse and track.routeLeader then score = score + 20000 end
    if track.isPlayer then score = score + 1000 end
    if not sparse and track.leader then score = score + 2500 end
    if not sparse and track.role == "TANK" then score = score + 10000 end
    return score
end

local function SelectTrack(run)
    if not run or type(run.tracks) ~= "table" then return nil end
    if run.preferredTrackGuid and run.tracks[run.preferredTrackGuid] and not IsSparsePartyGeometryTrack(run, run.tracks[run.preferredTrackGuid]) then
        return run.tracks[run.preferredTrackGuid]
    end
    local best, bestScore
    for _, track in pairs(run.tracks) do
        local score = TrackScore(track, run)
        if not bestScore or score > bestScore then
            best, bestScore = track, score
        end
    end
    return best
end

local function ScoreRunForRouting(run)
    local track = SelectTrack(run)
    if not track or type(track.samples) ~= "table" or #track.samples < 2 then return -1 end

    -- A completed recording can contain one final outdoor position after the
    -- PLAYER_ENTERING_WORLD that ended the dungeon run.  Score only the dominant
    -- continent/map context so that exit jump cannot make a tiny run look large.
    local continentCounts = {}
    local dominantC, dominantCount
    for i = 1, #track.samples do
        local s = track.samples[i]
        if s and s.c ~= nil and s.x and s.y then
            local key = tostring(s.c)
            continentCounts[key] = (continentCounts[key] or 0) + 1
            if not dominantCount or continentCounts[key] > dominantCount then
                dominantC, dominantCount = s.c, continentCounts[key]
            end
        end
    end
    if dominantC == nil then return -1 end

    local minX, maxX, minY, maxY
    local pathLength = 0
    local last
    local valid = 0
    for i = 1, #track.samples do
        local s = track.samples[i]
        if s and s.c == dominantC and s.x and s.y then
            valid = valid + 1
            minX = (not minX or s.x < minX) and s.x or minX
            maxX = (not maxX or s.x > maxX) and s.x or maxX
            minY = (not minY or s.y < minY) and s.y or minY
            maxY = (not maxY or s.y > maxY) and s.y or maxY
            if last and SameRouteContext(SampleToPoint(s), SampleToPoint(last)) then
                local dx, dy = s.x - last.x, s.y - last.y
                local step = sqrt(dx * dx + dy * dy)
                if step < 0.20 then pathLength = pathLength + step end
            end
            last = s
        end
    end
    if valid < 2 or not minX or not maxX or not minY or not maxY then return -1 end

    local dx, dy = maxX - minX, maxY - minY
    local coverage = sqrt(dx * dx + dy * dy)
    local combats = type(run.combats) == "table" and #run.combats or 0

    return (coverage * 100000)
        + (min(pathLength, 4.0) * 6000)
        + (combats * 450)
        + (min(valid, 600) * 0.20)
end

local function CopySessionPos(pos, run)
    if not pos then return nil end
    return {c=pos.c, z=pos.z or 0, x=pos.x, y=pos.y, section=run.sectionIndex or 1, phase=pos.phase or 1, floor=pos.floor or run.mapFloor, mapFile=run.mapFile}
end

local function BuildMergedSessionRun(runs)
    if not runs or #runs == 0 then return nil end
    table.sort(runs, function(a,b)
        local sa,sb = a.sectionIndex or 1, b.sectionIndex or 1
        if sa == sb then return (a.startedAt or 0) < (b.startedAt or 0) end
        return sa < sb
    end)
    if #runs == 1 then return runs[1] end
    local first = runs[1]
    local merged = {
        schema=first.schema or 3, addonVersion=first.addonVersion, sessionId=first.sessionId, sectionIndex=1, sectionCount=#runs,
        instanceName=first.instanceName, instanceType=first.instanceType, difficultyKey=first.difficultyKey, difficultySource=first.difficultySource,
        maxPlayers=first.maxPlayers, raidSize=first.raidSize or (first.instanceType == "raid" and first.maxPlayers or nil), raidMode=first.raidMode,
        routeLeaderGuid=first.routeLeaderGuid, routeLeaderName=first.routeLeaderName, routeLeaderSource=first.routeLeaderSource,
        tracks={}, combats={}, events={}, endedAt=runs[#runs].endedAt, duration=0, _sessionRuns=runs,
    }
    local cursor = 0
    for _,run in ipairs(runs) do
        local sec = run.sectionIndex or 1
        for guid,tr in pairs(run.tracks or {}) do
            local dst = merged.tracks[guid]
            if not dst then
                dst = {guid=guid,name=tr.name,class=tr.class,role=tr.role,roleSource=tr.roleSource,roleConfidence=tr.roleConfidence,roleSpec=tr.roleSpec,leader=tr.leader,routeLeader=tr.routeLeader,routeLeaderSource=tr.routeLeaderSource,routeLeaderConfidence=tr.routeLeaderConfidence,isPlayer=tr.isPlayer,samples={}}
                merged.tracks[guid]=dst
            else
                if tr.role == "TANK" then dst.role="TANK"; dst.roleSource=tr.roleSource; dst.roleConfidence=tr.roleConfidence; dst.roleSpec=tr.roleSpec end
                if tr.leader then dst.leader=true end
                if tr.routeLeader then dst.routeLeader=true; dst.routeLeaderSource=tr.routeLeaderSource; dst.routeLeaderConfidence=tr.routeLeaderConfidence end
            end
            for _,sm in ipairs(tr.samples or {}) do
                if not sm.recovery then
                    dst.samples[#dst.samples+1] = {t=cursor+(sm.t or 0),c=sm.c,z=sm.z or 0,x=sm.x,y=sm.y,f=sm.f,section=sec,phase=sm.phase or 1,floor=sm.floor or run.mapFloor,mapFile=run.mapFile,recovery=sm.recovery}
                end
            end
        end
        for _,combat in ipairs(run.combats or {}) do
            local c = {start=cursor+(combat.start or 0), finish=combat.finish and cursor+combat.finish or nil, duration=combat.duration, reason=combat.reason, npcs=combat.npcs, startPos=CopySessionPos(combat.startPos,run), endPos=CopySessionPos(combat.endPos,run)}
            merged.combats[#merged.combats+1]=c
        end
        for _,e in ipairs(run.events or {}) do
            local ne={}
            for k,v in pairs(e) do ne[k]=v end
            ne.t=cursor+(e.t or 0); ne.section=sec; ne.phase=e.phase or 1; ne.floor=e.floor or run.mapFloor; ne.mapFile=e.mapFile or run.mapFile
            merged.events[#merged.events+1]=ne
        end
        local dur = tonumber(run.duration) or 0
        cursor = cursor + dur + 0.5
    end
    merged.duration=cursor
    -- A later section may have resolved/overridden the raid movement leader.
    for i = #runs, 1, -1 do
        local r = runs[i]
        if r.routeLeaderGuid and merged.tracks[r.routeLeaderGuid] then
            merged.routeLeaderGuid=r.routeLeaderGuid
            merged.routeLeaderName=r.routeLeaderName
            merged.routeLeaderSource=r.routeLeaderSource
            break
        end
    end
    if merged.instanceType == "raid" and merged.routeLeaderGuid and merged.tracks[merged.routeLeaderGuid] then
        merged.preferredTrackGuid=merged.routeLeaderGuid
    else
        local bestGuid,bestScore
        for guid,tr in pairs(merged.tracks) do
            local score=TrackScore(tr, merged)
            if not bestScore or score>bestScore then bestGuid,bestScore=guid,score end
        end
        merged.preferredTrackGuid=bestGuid
    end
    return merged
end

local function DifficultyPreferenceGroups(requested)
    -- Dungeon geometry fallback: Normal/Heroic are interchangeable, while a
    -- genuine Mythic route must always beat non-Mythic geometry.
    if requested == "mythic" then
        return {
            {"mythic"},
            {"heroic", "normal"},
        }
    elseif requested == "heroic" then
        return {
            {"heroic"},
            {"normal"},
        }
    end
    return {
        {"normal"},
        {"heroic"},
    }
end

local function RaidDifficultyGroups(requested)
    -- Raids resolve exact difficulty before falling back by size. This produces
    -- e.g. 25H -> other-size H -> 25N -> other-size N.
    if requested == "mythic" then
        return {{"mythic"}, {"heroic"}, {"normal"}}
    elseif requested == "heroic" then
        return {{"heroic"}, {"normal"}}
    end
    return {{"normal"}, {"heroic"}}
end

local function DifficultyInGroup(key, group)
    for i = 1, #group do
        if key == group[i] then return true end
    end
    return false
end

local function ItemRaidSize(item)
    if not item then return nil end
    local n = tonumber(item.raidSize)
    if n and n > 0 then return n end
    if item.instanceType == "raid" then
        n = tonumber(item.maxPlayers)
        if n and n > 0 then return n end
    end
    return nil
end

local function CompatibilityTiers(ctx)
    local tiers = {}
    local requested = ctx and ctx.difficultyKey or "normal"
    if ctx and ctx.instanceType == "raid" then
        local requestedSize = tonumber(ctx.raidSize or ctx.maxPlayers)
        for _, group in ipairs(RaidDifficultyGroups(requested)) do
            -- Exact raid size first, then any other/legacy size at the same
            -- difficulty. Quality decides within each tier.
            tiers[#tiers + 1] = {difficulties=group, raidSize=requestedSize, sizeMode="exact"}
            tiers[#tiers + 1] = {difficulties=group, raidSize=requestedSize, sizeMode="other"}
        end
    else
        for _, group in ipairs(DifficultyPreferenceGroups(requested)) do
            tiers[#tiers + 1] = {difficulties=group, sizeMode="dungeon"}
        end
    end
    return tiers
end

local function MatchesCompatibility(item, ctx, tier)
    if not item or not ctx or item.instanceName ~= ctx.instanceName then return false end
    if not DifficultyInGroup(item.difficultyKey, tier.difficulties) then return false end

    if ctx.instanceType == "raid" then
        local size = ItemRaidSize(item)
        if item.instanceType ~= "raid" and not size then return false end
        local requestedSize = tonumber(tier.raidSize)
        if tier.sizeMode == "exact" then
            return requestedSize and size and size == requestedSize or false
        end
        -- "other" deliberately includes legacy raid recordings with no stored
        -- size so they remain usable, but only after an exact-size route fails.
        return (not requestedSize) or (not size) or size ~= requestedSize
    end

    if item.instanceType == "raid" or ItemRaidSize(item) then return false end
    return true
end

local function FindBestMatchingBuiltIn(ctx)
    local pack = rawget(_G, "TriRoutesBuiltInRoutes")
    if not pack or type(pack.routes) ~= "table" then return nil end

    local requested = ctx and ctx.difficultyKey or "normal"
    local requestedSize = ctx and tonumber(ctx.raidSize or ctx.maxPlayers) or nil
    local tiers = CompatibilityTiers(ctx)
    for priority = 1, #tiers do
        local tier = tiers[priority]
        local best, bestScore
        for i = 1, #pack.routes do
            local route = pack.routes[i]
            if MatchesCompatibility(route, ctx, tier) then
                local score = tonumber(route.qualityScore) or 0
                if not bestScore or score > bestScore then
                    best, bestScore = route, score
                end
            end
        end
        if best then
            local selectedSize = ItemRaidSize(best)
            local diffMatch = (best.difficultyKey == requested) and "exact" or "fallback"
            local sizeMatch = ctx.instanceType == "raid" and ((requestedSize and selectedSize == requestedSize) and "exact" or "fallback") or nil
            return best, bestScore, best.difficultyKey, diffMatch, priority, selectedSize, sizeMatch
        end
    end
end

local function BuildRouteFromBuiltIn(route)
    if not route or type(route.points) ~= "table" or #route.points < 2 then return nil end
    return {
        runId = "builtin:" .. tostring(route.id or "route"),
        run = nil,
        track = nil,
        points = route.points,
        processStats = route.stats,
        sourceName = route.sourceName or "Built-in",
        sourceRole = route.sourceRole,
        sourceSpec = route.sourceSpec,
        routePolicy = route.routePolicy,
        optionalBranches = route.optionalBranches,
        resyncHints = route.resyncHints,
        recordedDifficultyKey = route.recordedDifficultyKey,
        recordedMythicTier = tonumber(route.recordedMythicTier),
        recordedMythicSource = route.recordedMythicSource,
        mythicTierAsHeroicMax = tonumber(route.mythicTierAsHeroicMax),
        sessionId = nil,
        sectionCount = route.sectionCount or 1,
        sourceKind = "built-in",
        builtInId = route.id,
        raidSize = ItemRaidSize(route),
    }
end

local function SameGeometryContext(a, b)
    if not a or not b or a.c ~= b.c or a.z ~= b.z then return false end
    if a.floor and b.floor and a.floor > 0 and b.floor > 0 and a.floor ~= b.floor then return false end
    return true
end

local function PointToSegmentDistanceNorm(px, py, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local denom = dx * dx + dy * dy
    if denom <= 0.0000000001 then
        local ex, ey = px - a.x, py - a.y
        return sqrt(ex * ex + ey * ey)
    end
    local t = ((px - a.x) * dx + (py - a.y) * dy) / denom
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = a.x + t * dx, a.y + t * dy
    local ex, ey = px - qx, py - qy
    return sqrt(ex * ex + ey * ey)
end

local function BuildComparisonSegmentColors(primary, comparison)
    if not primary or not primary.points or not comparison or not comparison.points then return nil end
    local isMythic = comparison.selectedDifficulty == "mythic"
    local sameColor = isMythic and COMPARE_MYTHIC_SAME_COLOR or COMPARE_STANDARD_SAME_COLOR
    local nearColor = isMythic and COMPARE_MYTHIC_NEAR_COLOR or COMPARE_STANDARD_NEAR_COLOR
    local farColor = isMythic and COMPARE_MYTHIC_COLOR or COMPARE_STANDARD_COLOR
    local out = {}

    for i = 2, #comparison.points do
        local a, b = comparison.points[i - 1], comparison.points[i]
        if b.breakBefore or not SameRouteContext(a, b) then
            out[i] = farColor
        else
            local mx, my = (a.x + b.x) * 0.5, (a.y + b.y) * 0.5
            local best
            for j = 2, #primary.points do
                local p1, p2 = primary.points[j - 1], primary.points[j]
                if not p2.breakBefore and SameGeometryContext(a, p1) and SameGeometryContext(a, p2) then
                    local d = PointToSegmentDistanceNorm(mx, my, p1, p2)
                    if not best or d < best then best = d end
                end
            end
            if best and best <= 0.010 then
                out[i] = sameColor
            elseif best and best <= 0.025 then
                out[i] = nearColor
            else
                out[i] = farColor
            end
        end
    end
    return out
end

local function FindComparisonBuiltIn(ctx, primary)
    if not db or not db.showComparisonOverlay or not ctx or not primary then return nil end
    if primary.routePolicy == "fixed" then return nil end

    -- A Mythic fallback that is already following N/H has nothing useful to
    -- compare against. Only show the reverse N/H ghost when a real Mythic route
    -- is actually primary.
    if ctx.difficultyKey == "mythic" and primary.selectedDifficulty ~= "mythic" then return nil end

    local wanted = ctx.difficultyKey == "mythic" and "heroic" or "mythic"
    local compareCtx = {
        inInstance = ctx.inInstance,
        instanceName = ctx.instanceName,
        instanceType = ctx.instanceType,
        difficultyKey = wanted,
        raidSize = ctx.raidSize,
        maxPlayers = ctx.maxPlayers,
    }
    local route, score, selectedDifficulty = FindBestMatchingBuiltIn(compareCtx)
    if not route then return nil end

    -- For N/H play, only an actual Mythic route is interesting. For Mythic play,
    -- require a true Normal/Heroic counterpart rather than another Mythic route.
    if ctx.difficultyKey == "mythic" then
        if route.difficultyKey == "mythic" then return nil end
    elseif route.difficultyKey ~= "mythic" then
        return nil
    end

    if primary.builtInId and primary.builtInId == route.id then return nil end
    if route.routePolicy == "fixed" then return nil end
    if (primary.routePolicy == "platform" or route.routePolicy == "platform") and not (primary.routePolicy == "platform" and route.routePolicy == "platform") then
        return nil
    end

    local comparison = BuildRouteFromBuiltIn(route)
    if not comparison then return nil end
    comparison.qualityScore = score
    comparison.selectedDifficulty = selectedDifficulty or route.difficultyKey
    comparison.requestedDifficulty = ctx.difficultyKey
    comparison.isComparison = true
    comparison.segmentColors = BuildComparisonSegmentColors(primary, comparison)
    return comparison
end

local function MythicAsHeroicCutoff(instanceName)
    local pack = rawget(_G, "TriRoutesBuiltInRoutes")
    if not pack or type(pack.routes) ~= "table" or not instanceName then return nil end
    local best
    for i = 1, #pack.routes do
        local route = pack.routes[i]
        if route and route.instanceName == instanceName and route.difficultyKey ~= "mythic" then
            local cutoff = tonumber(route.mythicTierAsHeroicMax)
            if cutoff and cutoff > 0 and (not best or cutoff > best) then best = cutoff end
        end
    end
    return best
end

local function FindBestMatchingRun(ctx)
    if not TriRoutesRecorderDB or type(TriRoutesRecorderDB.runs) ~= "table" then return nil end

    local requested = ctx and ctx.difficultyKey or "normal"
    local requestedSize = ctx and tonumber(ctx.raidSize or ctx.maxPlayers) or nil
    local tiers = CompatibilityTiers(ctx)
    local mythicAsHeroicCutoff = requested == "mythic" and MythicAsHeroicCutoff(ctx and ctx.instanceName) or nil

    -- Compatibility priority is resolved before quality. For raids this means
    -- exact difficulty+size first, then alternate size, then fallback difficulty.
    for priority = 1, #tiers do
        local tier = tiers[priority]
        local groups, order = {}, {}

        for i = 1, #TriRoutesRecorderDB.runs do
            local run = TriRoutesRecorderDB.runs[i]
            local demotedLowMythic = run and mythicAsHeroicCutoff and run.difficultyKey == "mythic" and tonumber(run.mythicTier) and tonumber(run.mythicTier) <= mythicAsHeroicCutoff
            if run and run.endedAt and not demotedLowMythic and MatchesCompatibility(run, ctx, tier) then
                local rsize = ItemRaidSize(run)
                local key = tostring(run.difficultyKey or "?") .. "|size:" .. tostring(rsize or "?") .. "|" .. (run.sessionId and ("session:" .. tostring(run.sessionId)) or ("run:" .. tostring(i)))
                if not groups[key] then groups[key]={}; order[#order+1]=key end
                groups[key][#groups[key]+1]=run
            end
        end

        local bestRun,bestLabel,bestScore,bestOrder,bestDifficulty,bestRaidSize
        for oi,key in ipairs(order) do
            local merged=BuildMergedSessionRun(groups[key])
            local score=merged and ScoreRunForRouting(merged) or -1
            if score and score>=0 and (not bestScore or score>bestScore or (score==bestScore and oi>bestOrder)) then
                bestRun,bestScore,bestOrder=merged,score,oi
                bestDifficulty=merged.difficultyKey or (groups[key][1] and groups[key][1].difficultyKey) or "normal"
                bestRaidSize=ItemRaidSize(merged) or ItemRaidSize(groups[key][1])
                if merged.sessionId and (merged.sectionCount or 1)>1 then
                    bestLabel="session "..tostring(merged.sessionId).."/"..tostring(merged.sectionCount).." sections"
                else
                    bestLabel=tostring((groups[key][#groups[key]] and groups[key][#groups[key]].id) or oi)
                end
            end
        end

        if bestRun then
            local diffMatch = (bestDifficulty == requested) and "exact" or "fallback"
            local sizeMatch = ctx.instanceType == "raid" and ((requestedSize and bestRaidSize == requestedSize) and "exact" or "fallback") or nil
            return bestRun,bestLabel,bestScore,bestDifficulty,diffMatch,priority,bestRaidSize,sizeMatch
        end
    end
end

local function BuildRouteFromRun(run, runId)
    local track = SelectTrack(run)
    if not track or not track.samples or #track.samples < 2 then return nil end

    local points, processStats
    if db.routeProcessing and type(TR.ProcessRunRoute) == "function" then
        points, processStats = TR.ProcessRunRoute(run, track, {
            inputSpacing = db.routeInputSpacing,
            simplifyEpsilon = db.routeSimplifyEpsilon,
            shortLoopRadius = db.routeShortLoopRadius,
            shortLoopSeconds = db.routeShortLoopSeconds,
            shortLoopMaxExtent = db.routeShortLoopMaxExtent,
            turnAngleDegrees = db.routeTurnAngleDegrees,
            turnMinLeg = db.routeTurnMinLeg,
            maxPoints = db.maxRoutePoints,
        })
    else
        points = SimplifySamples(track.samples, db.routePointSpacing, db.maxRoutePoints)
    end

    if not points or #points < 2 then return nil end
    return {
        runId = runId,
        run = run,
        track = track,
        points = points,
        processStats = processStats,
        sourceName = track.name or "Unknown",
        sourceRole = track.role,
        sessionId = run.sessionId,
        sectionCount = run.sectionCount or 1,
        sourceKind = "recorder",
        raidSize = ItemRaidSize(run),
    }
end

function TR:RefreshRoute(force)
    if not db or not db.enabled or db.routeMode == "off" or not db.autoUseLastRoute then
        activeRoute = nil
        activeComparisonRoute = nil
        activeRunId = nil
        activeRouteIndex = 1
        activeRouteProgress = 1
        activeRouteProgressSynced = false
        activeRouteResyncCandidate = nil
        activeRouteSkippedBranches = {}
        return
    end
    local ctx = self:GetContext()
    local key = ContextKey(ctx)
    if not force and key == lastContextKey and activeRoute then return end
    lastContextKey = key
    activeRouteIndex = 1
    activeRouteProgress = 1
    activeRouteProgressSynced = false
    activeRouteResyncCandidate = nil
    activeRouteSkippedBranches = {}
    activeRoute = nil
    activeComparisonRoute = nil
    activeRunId = nil

    if not ctx.inInstance or (ctx.instanceType ~= "party" and ctx.instanceType ~= "raid") then return end
    local builtIn, builtInScore, builtInDifficulty, builtInMatch, builtInPriority, builtInRaidSize, builtInRaidSizeMatch = FindBestMatchingBuiltIn(ctx)
    local run, runId, routeScore, selectedDifficulty, difficultyMatch, difficultyPriority, selectedRaidSize, raidSizeMatch = FindBestMatchingRun(ctx)

    -- Difficulty compatibility always wins first (e.g. a real Mythic recording
    -- beats a bundled Heroic fallback). Inside the same tier, curated built-ins
    -- are the stable default; a recorder candidate must beat the curated quality
    -- by a meaningful margin before it can replace it for testing.
    local useBuiltIn = false
    if builtIn then
        if not run then
            useBuiltIn = true
        elseif (builtIn.routePolicy == "fixed" or builtIn.routePolicy == "platform") and (builtInPriority or 99) <= (difficultyPriority or 99) then
            -- Some instances are deliberately non-learnable as a literal trace.
            -- Fixed routes cover random event sequences (Violet Hold), while
            -- platform routes intentionally reduce 3D flight to ordered landing
            -- destinations (The Oculus). Neither should be displaced by a noisy
            -- raw recorder trace merely because it scores higher.
            useBuiltIn = true
        elseif (builtInPriority or 99) < (difficultyPriority or 99) then
            useBuiltIn = true
        elseif (builtInPriority or 99) == (difficultyPriority or 99) then
            local curatedMargin = 5000
            if (tonumber(routeScore) or 0) <= (tonumber(builtInScore) or 0) + curatedMargin then
                useBuiltIn = true
            end
        end
    end

    if useBuiltIn then
        activeRoute = BuildRouteFromBuiltIn(builtIn)
        if activeRoute then
            activeRoute.qualityScore = builtInScore
            activeRoute.requestedDifficulty = ctx.difficultyKey
            activeRoute.selectedDifficulty = builtInDifficulty or builtIn.difficultyKey
            activeRoute.difficultyMatch = builtInMatch or ((activeRoute.selectedDifficulty == ctx.difficultyKey) and "exact" or "fallback")
            activeRoute.difficultyPriority = builtInPriority or 1
            activeRoute.requestedRaidSize = ctx.instanceType == "raid" and tonumber(ctx.raidSize or ctx.maxPlayers) or nil
            activeRoute.selectedRaidSize = builtInRaidSize
            activeRoute.raidSizeMatch = builtInRaidSizeMatch
        end
        activeRunId = activeRoute and activeRoute.runId or nil
    elseif run then
        activeRoute = BuildRouteFromRun(run, runId)
        if activeRoute then
            activeRoute.qualityScore = routeScore
            activeRoute.requestedDifficulty = ctx.difficultyKey
            activeRoute.selectedDifficulty = selectedDifficulty or run.difficultyKey
            activeRoute.difficultyMatch = difficultyMatch or ((activeRoute.selectedDifficulty == ctx.difficultyKey) and "exact" or "fallback")
            activeRoute.difficultyPriority = difficultyPriority or 1
            activeRoute.requestedRaidSize = ctx.instanceType == "raid" and tonumber(ctx.raidSize or ctx.maxPlayers) or nil
            activeRoute.selectedRaidSize = selectedRaidSize
            activeRoute.raidSizeMatch = raidSizeMatch
        end
        activeRunId = runId
    end

    activeComparisonRoute = FindComparisonBuiltIn(ctx, activeRoute)
end

function TR:GetActiveRoute()
    return activeRoute
end

function TR:GetComparisonRoute()
    return activeComparisonRoute
end

local function GetCurrentRun()
    return TriRoutesRecorderRuntime and TriRoutesRecorderRuntime.currentRun or nil
end

local function GetLivePlayerPoints()
    local run = GetCurrentRun()
    if not run or not run.tracks then return nil end
    local playerGUID = UnitGUID("player")
    local track = playerGUID and run.tracks[playerGUID]
    if not track then
        for _, t in pairs(run.tracks) do if t.isPlayer then track = t break end end
    end
    if not track then return nil end
    return SimplifySamples(track.samples, db.livePointSpacing, 180)
end

local function FirstPlatformPointIndex(route)
    if not route or route.routePolicy ~= "platform" or not route.points then return nil end
    for i = 1, #route.points do
        if route.points[i] and route.points[i].kind == "platform" then return i end
    end
end

local function ProjectPlayerToRouteSegment(player, a, b)
    if not player or not a or not b or b.breakBefore then return nil end
    if not SameRouteContext(a, b) or not SameRouteContext(player, a) or not SameRouteContext(player, b) then return nil end

    local dx, dy = (b.x or 0) - (a.x or 0), (b.y or 0) - (a.y or 0)
    local denom = dx * dx + dy * dy
    if denom <= 0.0000000001 then
        return DistNorm(player, a), 0
    end

    local px, py = (player.x or 0) - (a.x or 0), (player.y or 0) - (a.y or 0)
    local t = (px * dx + py * dy) / denom
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = (a.x or 0) + t * dx, (a.y or 0) + t * dy
    local ex, ey = (player.x or 0) - qx, (player.y or 0) - qy
    return sqrt(ex * ex + ey * ey), t
end

local function FindBestRouteProjection(route, player, startSegment, endSegment, currentProgress)
    if not route or not route.points or #route.points < 2 or not player then return nil end
    local points = route.points
    startSegment = max(1, tonumber(startSegment) or 1)
    endSegment = min(#points - 1, tonumber(endSegment) or (#points - 1))
    if endSegment < startSegment then return nil end

    local best
    local tie = 0.0015
    for i = startSegment, endSegment do
        local a, b = points[i], points[i + 1]
        local d, t = ProjectPlayerToRouteSegment(player, a, b)
        if d then
            local progress = i + t
            -- Progress is monotonic. A tiny backwards allowance keeps the
            -- projection stable while circling a pull or rounding a sharp turn.
            if not currentProgress or progress >= currentProgress - 0.35 then
                if not best or d < best.distance - tie or (abs(d - best.distance) <= tie and progress < best.progress) then
                    best = {distance=d, t=t, segment=i, progress=progress}
                end
            end
        end
    end
    return best
end

local function FindRouteResyncHint(route, currentProgress, candidateProgress)
    local hints = route and route.resyncHints
    if type(hints) ~= "table" then return nil end
    for i = 1, #hints do
        local hint = hints[i]
        local fromIndex = tonumber(hint and hint.fromIndex)
        local throughIndex = tonumber(hint and hint.throughIndex) or fromIndex
        local rejoinIndex = tonumber(hint and hint.rejoinIndex)
        local lead = tonumber(hint and hint.rejoinLead) or 3
        if fromIndex and rejoinIndex and currentProgress and candidateProgress then
            if currentProgress >= fromIndex - 1 and currentProgress <= throughIndex + 1
                and candidateProgress >= rejoinIndex - 1 and candidateProgress <= rejoinIndex + lead then
                return hint
            end
        end
    end
end

local function MarkSkippedBranches(route, oldProgress, newProgress)
    local branches = route and route.optionalBranches
    if type(branches) ~= "table" or not oldProgress or not newProgress then return end
    for i = 1, #branches do
        local branch = branches[i]
        local startIndex = tonumber(branch and branch.startIndex)
        local rejoinIndex = tonumber(branch and branch.rejoinIndex)
        local id = branch and (branch.id or branch.label or tostring(i))
        if id and startIndex and rejoinIndex
            and oldProgress < startIndex - 0.25 and newProgress >= rejoinIndex - 0.25 then
            activeRouteSkippedBranches[id] = true
        end
    end
end

local function CommitRouteProgress(route, progress, resyncHint)
    if not progress then return end
    local oldProgress = activeRouteProgress or activeRouteIndex or 1
    if progress <= oldProgress then return end
    activeRouteProgress = progress
    local idx = floor(progress + 0.0001)
    if route and route.points then idx = min(#route.points, idx) end
    if idx > (activeRouteIndex or 1) then activeRouteIndex = idx end
    MarkSkippedBranches(route, oldProgress, progress)
    if resyncHint and type(resyncHint.skips) == "table" then
        for i = 1, #resyncHint.skips do
            activeRouteSkippedBranches[tostring(resyncHint.skips[i])] = true
        end
    end
    activeRouteProgressSynced = true
    activeRouteResyncCandidate = nil
end

local function ResyncCandidateConfirmed(progress, source)
    local now = GetTime and GetTime() or 0
    local anchor = floor(progress or 0)
    local confirmSeconds = tonumber(db and db.routeProgressResyncConfirmSeconds) or 0.45
    local previous = activeRouteResyncCandidate
    if not previous or previous.source ~= source or abs((previous.anchor or 0) - anchor) > 3 then
        activeRouteResyncCandidate = {anchor=anchor, progress=progress, source=source, firstSeen=now, lastSeen=now}
        return confirmSeconds <= 0
    end
    previous.anchor = anchor
    previous.progress = progress
    previous.lastSeen = now
    return (now - (previous.firstSeen or now)) >= confirmSeconds
end

local function FindNearestRouteIndex(route, player)
    if not route or not route.points or #route.points == 0 or not player then return 1 end
    local points = route.points
    local platformStart = FirstPlatformPointIndex(route)

    -- A platform route is normal ground navigation until the first explicit
    -- platform. From that point onward, advance only in recorded stage order.
    -- This prevents an Oculus player from being snapped to a later platform
    -- simply because two 2D map projections happen to be close together.
    if platformStart and (activeRouteIndex or 1) >= platformStart then
        local idx = activeRouteIndex or platformStart
        if idx < platformStart then idx = platformStart end
        if idx > #points then idx = #points end

        local guard = 0
        while idx < #points and guard < 4 do
            local nextPoint = points[idx + 1]
            if not nextPoint or not SameRouteContext(player, nextPoint) then break end
            local radius = tonumber(nextPoint.arrivalRadius)
            if not radius then
                radius = (nextPoint.kind == "platform" or nextPoint.kind == "boss" or nextPoint.kind == "finish") and 0.045 or 0.018
            end
            local dNorm = DistNorm(player, nextPoint)
            if dNorm <= radius then
                idx = idx + 1
                activeRouteIndex = idx
                activeRouteProgress = max(activeRouteProgress or 1, idx)
                activeRouteProgressSynced = true
                guard = guard + 1
            else
                break
            end
        end

        local target = points[min(#points, idx + 1)]
        local d = target and DistYards(player, target) or nil
        return activeRouteIndex or idx, d
    end

    local currentProgress = max(activeRouteProgress or 1, activeRouteIndex or 1)
    local currentIndex = min(#points, max(1, floor(currentProgress)))
    local immediateSegments = max(2, tonumber(db and db.routeProgressImmediateSegments) or 6)
    local forwardSegments = max(immediateSegments + 1, tonumber(db and db.routeProgressForwardSegments) or 60)
    local resyncRadius = tonumber(db and db.routeProgressResyncRadius) or 0.018
    local localRejectRadius = tonumber(db and db.routeProgressLocalRejectRadius) or 0.035

    -- Normal progress is continuous projection against the current and nearby
    -- forward segments. This makes a waypoint "passed" as soon as the player
    -- genuinely moves onto the following leg; touching a waypoint circle is no
    -- longer required.
    local immediateStart = max(1, currentIndex - 2)
    local immediateEnd = min(#points - 1, currentIndex + immediateSegments)
    if platformStart then immediateEnd = min(immediateEnd, platformStart - 1) end
    local immediate = FindBestRouteProjection(route, player, immediateStart, immediateEnd, currentProgress)

    if immediate then
        -- A close early projection establishes safe initial sync. At route
        -- crossings, FindBestRouteProjection deliberately favours the earlier
        -- plausible segment when distances are nearly tied.
        if immediate.distance <= localRejectRadius then activeRouteProgressSynced = true end
        if immediate.progress > currentProgress then
            CommitRouteProgress(route, immediate.progress)
            currentProgress = activeRouteProgress or immediate.progress
            currentIndex = min(#points, max(1, floor(currentProgress)))
        end
    end

    -- Search farther forward independently. A large jump is accepted only when
    -- the later geometry is a very strong match and the nearby expected path is
    -- no longer plausible, or when curated topology explicitly names a valid
    -- rejoin. The candidate must persist briefly to reject one-frame map noise.
    local farStart = max(immediateEnd + 1, currentIndex + immediateSegments + 1)
    local farEnd
    if activeRouteProgressSynced then
        farEnd = min(#points - 1, currentIndex + forwardSegments)
    else
        -- On reload/re-entry there may be no remembered index. Allow a global
        -- scan only until we establish a strong initial projection.
        farEnd = #points - 1
    end
    if platformStart then farEnd = min(farEnd, platformStart - 1) end

    local far = FindBestRouteProjection(route, player, farStart, farEnd, currentProgress)
    if far and far.distance <= resyncRadius then
        local hint = FindRouteResyncHint(route, currentProgress, far.progress)
        local localWeak = (not immediate) or immediate.distance >= localRejectRadius
        local genericMinIndex = max(2, tonumber(db and db.routeProgressGenericResyncMinIndex) or 8)
        local genericAllowed = localWeak and ((not activeRouteProgressSynced) or currentIndex >= genericMinIndex)
        if hint or genericAllowed then
            local source = hint and ("hint:" .. tostring(hint.id or hint.label or hint.rejoinIndex or "rejoin")) or "forward"
            if ResyncCandidateConfirmed(far.progress, source) then
                CommitRouteProgress(route, far.progress, hint)
                currentProgress = activeRouteProgress or far.progress
                currentIndex = min(#points, max(1, floor(currentProgress)))
            end
        else
            activeRouteResyncCandidate = nil
        end
    else
        activeRouteResyncCandidate = nil
    end

    -- Keep point-index consumers compatible while progression itself is
    -- fractional. activeRouteIndex means "last route point passed".
    local projectedIndex = min(#points, max(1, floor(activeRouteProgress or currentProgress or 1)))
    if projectedIndex > (activeRouteIndex or 1) then activeRouteIndex = projectedIndex end
    local target = points[min(#points, (activeRouteIndex or 1) + 1)]
    local targetDistance = target and DistYards(player, target) or (immediate and immediate.distance)
    return activeRouteIndex or projectedIndex, targetDistance
end

function TR:GetRouteProgressState()
    local skipped = {}
    for id in pairs(activeRouteSkippedBranches or {}) do skipped[#skipped + 1] = id end
    table.sort(skipped)
    return {
        index = activeRouteIndex or 1,
        progress = activeRouteProgress or activeRouteIndex or 1,
        synced = activeRouteProgressSynced and true or false,
        skippedBranches = skipped,
        resyncPending = activeRouteResyncCandidate and activeRouteResyncCandidate.progress or nil,
    }
end

local hud = CreateFrame("Frame", "TriRoutesHUD", UIParent)
hud:SetWidth(180)
hud:SetHeight(28)
hud:SetPoint("TOP", Minimap, "BOTTOM", 0, -5)
hud:SetFrameStrata("MEDIUM")
local hudBg = hud:CreateTexture(nil, "BACKGROUND")
hudBg:SetAllPoints(hud)
hudBg:SetTexture("Interface\\Buttons\\WHITE8X8")
hudBg:SetVertexColor(0, 0, 0, 0.52)
local hudText = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hudText:SetPoint("CENTER", hud, "CENTER", 0, 0)
hudText:SetWidth(174)
hudText:SetJustifyH("CENTER")
hudText:SetText("")
hud:Hide()

local function UpdateHUD(player, nearestDistance)
    if not db.hud or not db.enabled then hud:Hide() return end
    local ctx = TR:GetContext()
    local run = GetCurrentRun()
    if not ctx.inInstance then hud:Hide() return end

    local parts = {}
    if run then parts[#parts + 1] = "|cff65D7FFREC|r" end
    parts[#parts + 1] = tostring(ctx.difficultyKey or "?")
    if activeRoute then
        local finalPoint = activeRoute.points[#activeRoute.points]
        local finalNorm = player and finalPoint and DistNorm(player, finalPoint) or 999
        local platformDone = activeRoute.routePolicy == "platform" and (activeRouteIndex or 1) >= #activeRoute.points
        if platformDone or ((activeRouteIndex or 1) >= #activeRoute.points and finalNorm <= 0.0045) then
            parts[#parts + 1] = "DONE"
        else
            local nextIndex = min(#activeRoute.points, (activeRouteIndex or 1) + 1)
            local nextPoint = activeRoute.points[nextIndex]
            local d = player and nextPoint and DistYards(player, nextPoint) or nearestDistance
            if d then
                local kind = nextPoint and nextPoint.kind and string.upper(nextPoint.kind) or "NEXT"
                if kind == "TURN" or kind == "START" or kind == "FINISH" then kind = "NEXT" end
                parts[#parts + 1] = format("%s %.0f yd", kind, d)
            elseif activeRoute.routePolicy == "platform" and nextPoint then
                parts[#parts + 1] = "FLY -> " .. tostring(nextPoint.label or "next platform")
            else
                parts[#parts + 1] = "ROUTE"
            end
        end
    elseif run then
        parts[#parts + 1] = "learning route"
    else
        parts[#parts + 1] = "no saved route"
    end
    hudText:SetText(table.concat(parts, "  |  "))
    hud:Show()
end


-- TriRoutes directional arrow.
-- This intentionally mirrors the user's proven Questie waypoint-arrow frame
-- structure rather than merely copying the atlas math.  TriRoutes owns its
-- target/visibility, but the presentation and texture handling follow Questie.
local ARROW_TEXTURE = "Interface\\AddOns\\TriRoutes\\Media\\arrow.tga"
local ARROW_COLOR = {0.20, 0.84, 1.00, 1.00}
local arrowFrame
local arrowElapsed = 0

local function ResolveArrowTexture()
    -- Prefer Questie's already-resolved texture path when its integrated arrow
    -- exists.  This makes TriRoutes use the exact asset the user's Questie build
    -- is successfully rendering.  Keep our bundled byte-identical atlas as a
    -- standalone fallback.
    local qtex = rawget(_G, "QuestieWaypointArrowTexture")
    if qtex and qtex.GetTexture then
        local ok, texture = pcall(qtex.GetTexture, qtex)
        if ok and texture then return texture end
    end
    return ARROW_TEXTURE
end

local function ApplyArrowPosition()
    if not arrowFrame or not db then return end
    local p = db.arrowPosition or {"CENTER", 0, -100}
    arrowFrame:ClearAllPoints()
    arrowFrame:SetPoint(p[1] or "CENTER", UIParent, p[1] or "CENTER", p[2] or 0, p[3] or -100)
    if arrowFrame.content then
        local scale = tonumber(db.arrowScale) or 1.15
        if scale < 0.5 then scale = 0.5 end
        if scale > 3.0 then scale = 3.0 end
        db.arrowScale = scale
        arrowFrame.content:SetScale(scale)
    end
end

local function HideRouteArrow()
    if arrowFrame and arrowFrame.content then arrowFrame.content:Hide() end
end

local function GetArrowTarget(player)
    if not activeRoute or not activeRoute.points or #activeRoute.points < 2 or not player then return nil end

    local idx = FindNearestRouteIndex(activeRoute, player) or activeRouteIndex or 1
    if idx < 1 then idx = 1 end
    if idx > #activeRoute.points then idx = #activeRoute.points end

    local finalPoint = activeRoute.points[#activeRoute.points]
    if idx >= #activeRoute.points then
        if activeRoute.routePolicy == "platform" then
            activeRouteIndex = #activeRoute.points
            activeRouteProgress = #activeRoute.points
            activeRouteProgressSynced = true
            return nil, #activeRoute.points, true
        elseif finalPoint and SameRouteContext(player, finalPoint) and DistNorm(player, finalPoint) <= 0.0045 then
            activeRouteIndex = #activeRoute.points
            activeRouteProgress = #activeRoute.points
            activeRouteProgressSynced = true
            return nil, #activeRoute.points, true
        end
    end

    local nextIndex = min(#activeRoute.points, idx + (tonumber(db.arrowLookAhead) or 1))
    local guard = 0
    while nextIndex < #activeRoute.points and guard < 6 do
        local p = activeRoute.points[nextIndex]
        if not p or not SameRouteContext(player, p) or DistNorm(player, p) > 0.0030 then break end
        idx = nextIndex
        if idx > activeRouteIndex then activeRouteIndex = idx end
        activeRouteProgress = max(activeRouteProgress or 1, idx)
        activeRouteProgressSynced = true
        nextIndex = min(#activeRoute.points, idx + (tonumber(db.arrowLookAhead) or 1))
        guard = guard + 1
    end

    return activeRoute.points[nextIndex], nextIndex, false
end

local function ApplyArrowDragState()
    if not arrowFrame or not db then return end
    arrowFrame:EnableMouse(not db.arrowLocked)
end

local function CreateRouteArrow()
    if arrowFrame then return end

    -- Match QuestieWaypointArrow.lua: the movable parent is only the arrow
    -- itself.  The wider text/content hangs from it without creating a visible
    -- edit frame.
    arrowFrame = CreateFrame("Frame", "TriRoutesWaypointArrowFrame", UIParent)
    arrowFrame:SetWidth(48)
    arrowFrame:SetHeight(36)
    arrowFrame:SetClampedToScreen(true)
    arrowFrame:SetMovable(true)
    arrowFrame:RegisterForDrag("LeftButton")
    arrowFrame:SetScript("OnDragStart", function(self)
        if db and ((not db.arrowLocked) or IsShiftKeyDown()) then
            self:StartMoving()
        end
    end)
    arrowFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not db then return end
        local point, _, _, x, y = self:GetPoint(1)
        db.arrowPosition = {point or "CENTER", x or 0, y or -100}
    end)

    arrowFrame.content = CreateFrame("Frame", nil, arrowFrame)
    arrowFrame.content:SetPoint("TOPLEFT", arrowFrame, "TOPLEFT", -80, 0)
    arrowFrame.content:SetPoint("BOTTOMRIGHT", arrowFrame, "BOTTOMRIGHT", 80, -58)

    -- Use the same draw-layer argument and dimensions as the proven Questie
    -- implementation.  The atlas cell is 56x42 but is displayed at 48x36.
    arrowFrame.model = arrowFrame.content:CreateTexture("TriRoutesWaypointArrowTexture", "OVERLAY")
    arrowFrame.model:SetTexture(ResolveArrowTexture())
    arrowFrame.model:SetBlendMode("BLEND")
    arrowFrame.model:SetAlpha(1)
    arrowFrame.model:SetTexCoord(0, 0, 0.109375, 0.08203125)
    arrowFrame.model:SetWidth(48)
    arrowFrame.model:SetHeight(36)
    arrowFrame.model:SetPoint("TOP", arrowFrame.content, "TOP", 0, 0)
    arrowFrame.model:SetVertexColor(unpack(ARROW_COLOR))

    -- Unlike Questie, TriRoutes has no quest-objective icon to overlay. The
    -- old 26px map icon covered most of the directional atlas in test4d.
    arrowFrame.texture = nil

    arrowFrame.title = arrowFrame.content:CreateFontString(nil, "HIGH", "GameFontNormal")
    arrowFrame.title:SetPoint("TOP", arrowFrame.model, "BOTTOM", 0, -10)
    arrowFrame.title:SetWidth(220)
    arrowFrame.title:SetJustifyH("CENTER")
    arrowFrame.title:SetText("|cff33D6FFTriRoute|r")

    arrowFrame.description = arrowFrame.content:CreateFontString(nil, "HIGH", "GameFontWhite")
    arrowFrame.description:SetPoint("TOP", arrowFrame.title, "BOTTOM", 0, -2)
    arrowFrame.description:SetWidth(220)
    arrowFrame.description:SetJustifyH("CENTER")
    arrowFrame.description:SetTextColor(1, 1, 1, 1)
    arrowFrame.description:SetText("")

    arrowFrame.distance = arrowFrame.content:CreateFontString(nil, "HIGH", "GameFontWhiteSmall")
    arrowFrame.distance:SetPoint("TOP", arrowFrame.description, "BOTTOM", 0, -2)
    arrowFrame.distance:SetWidth(220)
    arrowFrame.distance:SetJustifyH("CENTER")
    arrowFrame.distance:SetTextColor(0.8, 0.8, 0.8, 1)
    arrowFrame.distance:SetText("")

    arrowFrame.content:Hide()
    arrowFrame:Show()
    ApplyArrowPosition()
    ApplyArrowDragState()
end

local function UpdateRouteArrow(elapsed)
    if not db or not db.enabled or not db.arrow then
        HideRouteArrow()
        return
    end

    arrowElapsed = arrowElapsed + (elapsed or 0)
    if arrowElapsed < 0.05 then return end
    arrowElapsed = 0

    local ctx = TR:GetContext()
    if not ctx.inInstance or (ctx.instanceType ~= "party" and ctx.instanceType ~= "raid") or not activeRoute then
        HideRouteArrow()
        return
    end

    CreateRouteArrow()
    -- Do NOT re-apply the saved position here: doing so every update prevents
    -- StartMoving() from ever moving the frame. Questie only applies position
    -- during refresh/config changes.
    ApplyArrowDragState()

    -- If Questie finished creating its integrated arrow after TriRoutes did,
    -- pick up its resolved texture path now.
    if arrowFrame.model and not arrowFrame._questieTextureResolved then
        local qtex = rawget(_G, "QuestieWaypointArrowTexture")
        if qtex and qtex.GetTexture then
            local ok, texture = pcall(qtex.GetTexture, qtex)
            if ok and texture then
                arrowFrame.model:SetTexture(texture)
                arrowFrame._questieTextureResolved = true
            end
        end
    end

    local c, z, x, y = GetPlayerPosition()
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not c or not x or not y or not facing then
        HideRouteArrow()
        return
    end

    local player = MakePlayerPoint(c, z, x, y)
    local targetPoint, targetIndex, complete = GetArrowTarget(player)
    if complete then
        HideRouteArrow()
        return
    end
    if not targetPoint or not SameRouteContext(player, targetPoint) then
        HideRouteArrow()
        return
    end

    -- Questie's arrow compensates for HereBeDragons world coordinates being
    -- inverted. TriRoutes records WDM's already-local map coordinates, so using
    -- that HBD inversion points exactly 180 degrees backwards. Work in real
    -- local-map yard deltas (target - player) instead.
    local navDistance, xDelta, yDelta, navSource = GetRouteVector(player, targetPoint)
    if not xDelta or not yDelta then
        HideRouteArrow()
        lastArrowNavSource = "none"
        return
    end
    lastArrowNavSource = navSource or "unknown"
    local dir = atan2deg(xDelta, -yDelta)
    dir = dir > 0 and 360 - dir or -dir
    if dir < 0 then dir = dir + 360 end

    local angle = rad(dir) - facing
    local cell = floor((angle / (pi * 2) * 108) + 0.5)
    cell = cell - floor(cell / 108) * 108
    local column = cell - floor(cell / 9) * 9
    local row = floor(cell / 9)
    local xstart = (column * 56) / 512
    local ystart = (row * 42) / 512
    local xend = ((column + 1) * 56) / 512
    local yend = ((row + 1) * 42) / 512

    arrowFrame.model:SetTexCoord(xstart, xend, ystart, yend)
    arrowFrame.model:SetVertexColor(unpack(ARROW_COLOR))

    local targetKind = targetPoint.kind and string.upper(targetPoint.kind) or nil
    local targetLabel = targetPoint.label or targetKind or "Next route point"
    arrowFrame.title:SetText("|cff33D6FFTriRoute|r  |cffffffff" .. tostring(targetIndex) .. "/" .. tostring(#activeRoute.points) .. "|r")
    if targetKind and targetKind ~= "TURN" and targetKind ~= "START" and targetKind ~= "FINISH" then
        arrowFrame.description:SetText("|cffFFD36A" .. targetKind .. "|r: " .. tostring(targetLabel))
    else
        arrowFrame.description:SetText(tostring(targetLabel))
    end

    if db.arrowShowDistance then
        local d = navDistance or DistYards(player, targetPoint)
        if d and d > 0.01 then
            local formatted
            if d >= 1000 then formatted = format("%.1fk yd", d / 1000) else formatted = tostring(floor(d + 0.5)) .. " yd" end
            arrowFrame.distance:SetText("|cffaaaaaaDistance: " .. formatted .. "|r")
        else
            arrowFrame.distance:SetText("")
        end
    else
        arrowFrame.distance:SetText("")
    end

    arrowFrame.content:Show()
end

local function RoutePointColor(p, fallback)
    if not p then return fallback end
    if p.kind == "boss" then return ROUTE_BOSS_DOT_COLOR end
    if p.kind == "pull" then return ROUTE_PULL_DOT_COLOR end
    if p.kind == "start" then return ROUTE_START_DOT_COLOR end
    if p.kind == "finish" then return ROUTE_END_DOT_COLOR end
    if p.kind == "turn" then return ROUTE_TURN_DOT_COLOR end
    if p.kind == "warning" then return ROUTE_BOSS_DOT_COLOR end
    return fallback
end

local function BuildRouteProgress(route, player)
    if not route or not route.points or #route.points == 0 or not player then return nil end
    local idx = FindNearestRouteIndex(route, player) or activeRouteIndex or 1
    if idx < 1 then idx = 1 end
    if idx > #route.points then idx = #route.points end

    -- Treat the path from our current position to the next meaningful encounter
    -- landmark as the active blue leg. Everything after it is the purple next
    -- route. Turns remain geometry rather than splitting the route into tiny legs.
    local activeEnd = #route.points
    for i = idx + 1, #route.points do
        local kind = route.points[i] and route.points[i].kind
        if kind == "pull" or kind == "boss" or kind == "platform" or kind == "finish" or kind == "warning" then
            activeEnd = i
            break
        end
    end
    return {current=idx, activeEnd=activeEnd}
end

local function ProgressLineColor(segmentEndIndex, progress, fallback)
    if not progress then return fallback end
    if segmentEndIndex <= progress.current then return ROUTE_PAST_COLOR end
    if segmentEndIndex <= progress.activeEnd then return ROUTE_CURRENT_COLOR end
    return ROUTE_NEXT_COLOR
end

local function ProgressDotColor(pointIndex, p, progress, fallback)
    if p and p.kind then return RoutePointColor(p, fallback) end
    if not progress then return fallback end
    if pointIndex <= progress.current then return ROUTE_PAST_DOT_COLOR end
    if pointIndex <= progress.activeEnd then return ROUTE_CURRENT_DOT_COLOR end
    return ROUTE_NEXT_DOT_COLOR
end

local function GetWorldMapCanvas()
    -- Questie's 3.3.5 compatibility layer explicitly uses WorldMapButton as the
    -- canvas. WDM also paints its restored dungeon maps there.
    local QC = rawget(_G, "QuestieCompat")
    if QC and QC.WorldMapFrame and QC.WorldMapFrame.GetCanvas then
        local ok, canvas = pcall(QC.WorldMapFrame.GetCanvas, QC.WorldMapFrame)
        if ok and canvas then return canvas end
    end
    return rawget(_G, "WorldMapButton") or rawget(_G, "WorldMapDetailFrame")
end

local function CanUseLocalWorldMapPoints()
    local px, py = GetPlayerMapPosition("player")
    if not px or not py or (px <= 0 and py <= 0) then return false end
    local c = GetCurrentMapContinent and GetCurrentMapContinent() or nil
    return c == nil or c < 0
end

local function DrawWorldPath(points, color, dotColor, dotPool, width, progress, lineOnly, segmentColors)
    local canvas = GetWorldMapCanvas()
    if not canvas or not points or #points < 1 then return end
    local A = GetAstrolabe()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or not h or w <= 1 or h <= 1 then return end

    local localDungeon = CanUseLocalWorldMapPoints()
    local c,z,x,y = GetPlayerPosition()
    local liveContext = c and MakePlayerPoint(c,z,x,y) or nil
    local used = 0
    local lastX, lastY, lastPoint
    for i = 1, #points do
        local p = points[i]
        local nx, ny
        local dot = GetDot(dotPool, used + 1, canvas, lineOnly and 2 or (p.kind and 7 or 5), dotColor)
        local thisColor = lineOnly and TRANSPARENT_DOT_COLOR or ProgressDotColor(i, p, progress, dotColor)
        dot.tex:SetVertexColor(thisColor[1], thisColor[2], thisColor[3], thisColor[4] or 1)
        dot:ClearAllPoints()

        if liveContext and not SameRouteContext(liveContext, p) then
            dot:Hide()
        elseif p.c and p.c < 0 and localDungeon then
            -- WDM dungeon coordinates are already normalized to the displayed
            -- instance map. No translation library is required here.
            nx, ny = p.x, p.y
            if nx and ny and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                dot:SetPoint("CENTER", canvas, "TOPLEFT", nx * w, -ny * h)
                dot:Show()
            else
                dot:Hide()
            end
        elseif A and A.PlaceIconOnWorldMap then
            local ok, ax, ay = pcall(A.PlaceIconOnWorldMap, A, canvas, dot, p.c, p.z or 0, p.x, p.y)
            if ok then nx, ny = ax, ay end
        else
            local c, z = GetCurrentMapContinent(), GetCurrentMapZone()
            if p.c == c and p.z == z then
                nx, ny = p.x, p.y
                dot:SetPoint("CENTER", canvas, "TOPLEFT", nx * w, -ny * h)
                dot:Show()
            else
                dot:Hide()
            end
        end

        if nx and ny and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
            used = used + 1
            local px, py = nx * w, (1 - ny) * h
            if lastX and lastY and lastPoint and not p.breakBefore and SameRouteContext(lastPoint, p) then
                local segColor = (segmentColors and segmentColors[i]) or ProgressLineColor(i, progress, color)
                DrawLine(canvas, lastX, lastY, px, py, width, segColor, "OVERLAY")
            end
            lastX, lastY, lastPoint = px, py, p
        else
            lastX, lastY, lastPoint = nil, nil, nil
        end
    end
    HideWorldDots(dotPool, used + 1)
end

function TR:DrawWorldMap()
    local canvas = GetWorldMapCanvas()
    if not db or not db.enabled or not db.showWorldMap or not canvas then
        if canvas then HideLines(canvas) end
        HideWorldDots(worldRouteDots, 1)
        HideWorldDots(worldCompareDots, 1)
        HideWorldDots(worldTrailDots, 1)
        return
    end
    HideLines(canvas)
    HideWorldDots(worldRouteDots, 1)
    HideWorldDots(worldCompareDots, 1)
    HideWorldDots(worldTrailDots, 1)

    if activeComparisonRoute and activeComparisonRoute.points then
        local compareColor = activeComparisonRoute.selectedDifficulty == "mythic" and COMPARE_MYTHIC_COLOR or COMPARE_STANDARD_COLOR
        DrawWorldPath(activeComparisonRoute.points, compareColor, TRANSPARENT_DOT_COLOR, worldCompareDots, 1.35, nil, true, activeComparisonRoute.segmentColors)
    end

    if activeRoute and activeRoute.points then
        local c, z, x, y = GetPlayerPosition()
        local player = c and MakePlayerPoint(c,z,x,y) or nil
        local progress = BuildRouteProgress(activeRoute, player)
        DrawWorldPath(activeRoute.points, ROUTE_COLOR, ROUTE_DOT_COLOR, worldRouteDots, 2.1, progress)
    end
    if db.showLiveTrail then
        local live = GetLivePlayerPoints()
        if live and #live > 1 then DrawWorldPath(live, TRAIL_COLOR, TRAIL_DOT_COLOR, worldTrailDots, 1.25) end
    end
end

local MINIMAP_SIZE = {
    indoor = {[0]=300,[1]=240,[2]=180,[3]=120,[4]=80,[5]=50},
    outdoor = {[0]=466.6666667,[1]=400,[2]=333.3333333,[3]=266.3333333,[4]=200,[5]=133.3333333},
}

local function GetMinimapScaleState(localDungeon)
    local zoom = Minimap and Minimap:GetZoom() or 0
    local mode = db and db.minimapScaleMode or "auto"
    local outside, source

    if mode == "indoor" then
        outside, source = false, "manual-indoor"
    elseif mode == "outdoor" then
        outside, source = true, "manual-outdoor"
    else
        -- The coordinate system (WDM C-1) and the minimap zoom table are two
        -- separate concerns. Astrolabe cannot translate C-1 positions, but its
        -- MINIMAP_UPDATE_ZOOM probe still reliably tells us which Blizzard
        -- minimap scale table the client is currently using. test4f forced all
        -- C-1 dungeon maps to the indoor table, which made the overlay too large
        -- whenever the client was actually using the outdoor table.
        local A = GetAstrolabe()
        if A and A.minimapOutside ~= nil then
            outside, source = A.minimapOutside and true or false, "Astrolabe"
        else
            local outsideZoom = tonumber(GetCVar and GetCVar("minimapZoom") or nil)
            local insideZoom = tonumber(GetCVar and GetCVar("minimapInsideZoom") or nil)
            if outsideZoom ~= nil and insideZoom ~= nil and outsideZoom ~= insideZoom then
                if zoom == outsideZoom then
                    outside, source = true, "CVar"
                elseif zoom == insideZoom then
                    outside, source = false, "CVar"
                end
            end
        end

        if outside == nil then
            local inInstance = IsInInstance()
            outside, source = not inInstance, "instance-fallback"
        end
    end

    local tbl = outside and MINIMAP_SIZE.outdoor or MINIMAP_SIZE.indoor
    local diameter = tbl[zoom] or tbl[0]
    return diameter, outside and "outdoor" or "indoor", zoom, source
end

local function GetMinimapDiameter(localDungeon)
    local diameter = GetMinimapScaleState(localDungeon)
    return diameter
end

local function MapPointToMinimapPixels(player, point, mapWidthYards, mapHeightYards)
    if not SameRouteContext(player, point) then return nil end
    local mapW, mapH = Minimap:GetWidth(), Minimap:GetHeight()
    if not mapW or not mapH or mapW <= 1 or mapH <= 1 then return nil end
    local diameter = GetMinimapDiameter(player.c and player.c < 0)
    if not diameter or diameter <= 0 then return nil end

    local xDist = ((point.x or 0) - (player.x or 0)) * mapWidthYards
    local yDist = ((point.y or 0) - (player.y or 0)) * mapHeightYards

    if GetCVar("rotateMinimap") ~= "0" then
        local facing = GetPlayerFacing and GetPlayerFacing() or 0
        local sn, cs = sin(facing), cos(facing)
        local dx, dy = xDist, yDist
        xDist = (dx * cs) - (dy * sn)
        yDist = (dx * sn) + (dy * cs)
    end

    local xScale = diameter / mapW
    local yScale = diameter / mapH
    return xDist / xScale, -yDist / yScale
end

local function ClipSegmentToRect(x1, y1, x2, y2, xmin, xmax, ymin, ymax)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    local function clip(p, q)
        if abs(p) < 0.000001 then return q >= 0 end
        local r = q / p
        if p < 0 then
            if r > t1 then return false end
            if r > t0 then t0 = r end
        else
            if r < t0 then return false end
            if r < t1 then t1 = r end
        end
        return true
    end
    if clip(-dx, x1 - xmin) and clip(dx, xmax - x1) and clip(-dy, y1 - ymin) and clip(dy, ymax - y1) then
        return x1 + t0*dx, y1 + t0*dy, x1 + t1*dx, y1 + t1*dy
    end
end

local function DrawMiniLocalPath(points, pool, color, dotColor, width, player, mapWidthYards, mapHeightYards, progress, lineOnly, segmentColors)
    if not Minimap or not points or #points < 1 then return end
    local mw, mh = Minimap:GetWidth(), Minimap:GetHeight()
    local halfW, halfH = mw/2 - 4, mh/2 - 4
    local coords = {}

    for i = 1, #points do
        local p = points[i]
        local x, y = MapPointToMinimapPixels(player, p, mapWidthYards, mapHeightYards)
        coords[i] = x and {x=x,y=y,p=p} or nil
        local dot = GetDot(pool, i, Minimap, lineOnly and 2 or (p.kind and 7 or 4), dotColor)
        local thisColor = lineOnly and TRANSPARENT_DOT_COLOR or ProgressDotColor(i, p, progress, dotColor)
        dot.tex:SetVertexColor(thisColor[1], thisColor[2], thisColor[3], thisColor[4] or 1)
        dot:ClearAllPoints()
        if x and abs(x) <= halfW and abs(y) <= halfH then
            dot:SetPoint("CENTER", Minimap, "CENTER", x, y)
            dot:Show()
        else
            dot:Hide()
        end
    end
    for i = #points + 1, #pool do pool[i]:Hide() end

    for i = 2, #points do
        local a, b = coords[i-1], coords[i]
        if a and b and not b.p.breakBefore and SameRouteContext(a.p,b.p) then
            local x1,y1,x2,y2 = ClipSegmentToRect(a.x,a.y,b.x,b.y,-halfW,halfW,-halfH,halfH)
            if x1 then
                local segColor = (segmentColors and segmentColors[i]) or ProgressLineColor(i, progress, color)
                DrawLine(Minimap, halfW+4+x1, halfH+4+y1, halfW+4+x2, halfH+4+y2, width, segColor, "OVERLAY")
            end
        end
    end
end

local function DrawMiniAstrolabePath(points, pool, color, dotColor, width, lineOnly, segmentColors)
    local A = GetAstrolabe()
    if not A or not points or #points < 1 then return end
    local placed = {}
    for i = 1, #points do
        local p = points[i]
        local dot = GetDot(pool, i, Minimap, lineOnly and 2 or (p.kind and 7 or 4), dotColor)
        local thisColor = lineOnly and TRANSPARENT_DOT_COLOR or RoutePointColor(p, dotColor)
        dot.tex:SetVertexColor(thisColor[1], thisColor[2], thisColor[3], thisColor[4] or 1)
        local ok, result = pcall(A.PlaceIconOnMinimap, A, dot, p.c, p.z or 0, p.x, p.y)
        if ok and result == 0 then
            dot._trPlaced = true
            placed[#placed + 1] = dot
        else
            dot._trPlaced = nil
            dot:Hide()
        end
    end
    for i = #points + 1, #pool do pool[i]:Hide() end

    local ml, mb = Minimap:GetLeft(), Minimap:GetBottom()
    if not ml or not mb then return end
    for i = 2, #placed do
        local a, b = placed[i - 1], placed[i]
        local edgeA = A.IsIconOnEdge and A:IsIconOnEdge(a)
        local edgeB = A.IsIconOnEdge and A:IsIconOnEdge(b)
        if not edgeA and not edgeB then
            local x1,y1 = a:GetCenter()
            local x2,y2 = b:GetCenter()
            local segColor = (segmentColors and segmentColors[i]) or color
            if x1 and x2 then DrawLine(Minimap, x1-ml, y1-mb, x2-ml, y2-mb, width, segColor, "OVERLAY") end
        end
    end
end

-- When the user's Questie build is loaded, use its own HBDPins minimap engine.
-- We know this path works in restored WDM dungeons because the Questie quest
-- markers are visibly positioned on the same minimap. TriRoutes only owns the
-- cyan dots/lines; Questie owns the coordinate translation and minimap clipping.
local minimapLineSets = {}

local function DrawMiniQuestiePath(points, pool, color, dotColor, width, player, progress, lineOnly, segmentColors)
    local HBD, QPins, uiMapID = GetQuestieNavigation()
    if not HBD or not QPins or not uiMapID or not QPins.AddMinimapIconMap then return false end
    if not points or #points < 1 then return false end

    -- Validate that Questie's current UiMapID actually understands this dungeon
    -- coordinate space before registering any pins.
    if HBD.GetWorldCoordinatesFromZone then
        local ok, wx = pcall(HBD.GetWorldCoordinatesFromZone, HBD, player.x, player.y, uiMapID)
        if not ok or not wx then return false end
    end

    local dots = {}
    for i = 1, #points do
        local p = points[i]
        local dot = GetDot(pool, i, Minimap, lineOnly and 2 or (p.kind and 7 or 4), dotColor)
        local thisColor = lineOnly and TRANSPARENT_DOT_COLOR or ProgressDotColor(i, p, progress, dotColor)
        dot.tex:SetVertexColor(thisColor[1], thisColor[2], thisColor[3], thisColor[4] or 1)
        dot:ClearAllPoints()
        dot:Hide()
        local ok = pcall(QPins.AddMinimapIconMap, QPins, TR, dot, uiMapID, p.x, p.y, false, false)
        if ok then
            dot._trQuestiePlaced = true
            dots[#dots + 1] = dot
        end
    end
    for i = #points + 1, #pool do pool[i]:Hide() end

    if #dots > 0 then
        minimapLineSets[#minimapLineSets + 1] = {dots=dots, color=color, width=width, pins=QPins, progress=progress, segmentColors=segmentColors}
        lastMinimapNavSource = "Questie-HBDPins"
        return true
    end
    return false
end

local function DrawQuestieMinimapLines()
    if not Minimap or #minimapLineSets == 0 then return end
    HideLines(Minimap)
    local ml, mb = Minimap:GetLeft(), Minimap:GetBottom()
    if not ml or not mb then return end

    for _, set in ipairs(minimapLineSets) do
        local previous
        for i = 1, #set.dots do
            local dot = set.dots[i]
            if dot and dot:IsShown() then
                local onEdge = set.pins and set.pins.IsMinimapIconOnEdge and set.pins:IsMinimapIconOnEdge(dot)
                if previous and not onEdge then
                    local prevEdge = set.pins and set.pins.IsMinimapIconOnEdge and set.pins:IsMinimapIconOnEdge(previous)
                    if not prevEdge then
                        local x1, y1 = previous:GetCenter()
                        local x2, y2 = dot:GetCenter()
                        if x1 and y1 and x2 and y2 then
                            local segColor = (set.segmentColors and set.segmentColors[i]) or ProgressLineColor(i, set.progress, set.color)
                            DrawLine(Minimap, x1-ml, y1-mb, x2-ml, y2-mb, set.width, segColor, "OVERLAY")
                        end
                    end
                end
                previous = dot
            else
                previous = nil
            end
        end
    end
end

function TR:DrawMinimap()
    ClearMiniDots(miniRouteDots)
    ClearMiniDots(miniCompareDots)
    ClearMiniDots(miniTrailDots)
    HideLines(Minimap)
    minimapLineSets = {}
    lastMinimapNavSource = "none"

    if not db or not db.enabled or not db.showMinimap or not Minimap then return end

    local c, z, x, y = GetPlayerPosition()
    local player = c and MakePlayerPoint(c,z,x,y) or nil
    if not player then return end

    local nearestDistance
    local widthYards, heightYards = GetDungeonMapMetrics(false)
    local useLocal = player.c < 0 and widthYards and heightYards

    if activeComparisonRoute and activeComparisonRoute.points then
        local comparePoints = activeComparisonRoute.points
        local compareColor = activeComparisonRoute.selectedDifficulty == "mythic" and COMPARE_MYTHIC_COLOR or COMPARE_STANDARD_COLOR
        if useLocal then
            DrawMiniLocalPath(comparePoints, miniCompareDots, compareColor, TRANSPARENT_DOT_COLOR, 1.0, player, widthYards, heightYards, nil, true, activeComparisonRoute.segmentColors)
        else
            local usedQuestie = false
            if player.c < 0 then
                usedQuestie = DrawMiniQuestiePath(comparePoints, miniCompareDots, compareColor, TRANSPARENT_DOT_COLOR, 1.0, player, nil, true, activeComparisonRoute.segmentColors)
            end
            if not usedQuestie then
                DrawMiniAstrolabePath(comparePoints, miniCompareDots, compareColor, TRANSPARENT_DOT_COLOR, 1.0, true, activeComparisonRoute.segmentColors)
            end
        end
    end

    if activeRoute and activeRoute.points then
        local idx, d = FindNearestRouteIndex(activeRoute, player)
        nearestDistance = d
        local progress = BuildRouteProgress(activeRoute, player)

        -- Draw the ENTIRE saved route and let the minimap clip it spatially.
        -- The old index window (2 behind / 9 ahead) hid later branches that were
        -- physically nearby, which made a crossing route look incomplete.
        local routePoints = activeRoute.points
        if useLocal then
            DrawMiniLocalPath(routePoints, miniRouteDots, ROUTE_COLOR, ROUTE_DOT_COLOR, 1.9, player, widthYards, heightYards, progress)
            lastMinimapNavSource = "WDM-local-full"
        else
            local usedQuestie = false
            if player.c < 0 then
                usedQuestie = DrawMiniQuestiePath(routePoints, miniRouteDots, ROUTE_COLOR, ROUTE_DOT_COLOR, 1.9, player, progress)
            end
            if not usedQuestie then
                DrawMiniAstrolabePath(routePoints, miniRouteDots, ROUTE_COLOR, ROUTE_DOT_COLOR, 1.9)
                lastMinimapNavSource = "Astrolabe-full"
            end
        end
    end

    if db.showLiveTrail then
        local live = GetLivePlayerPoints()
        if live and #live > 1 then
            local localPoints = {}
            local first = max(1, #live - 12)
            for i = first, #live do localPoints[#localPoints + 1] = live[i] end

            -- Keep the live breadcrumb on the same minimap renderer as the
            -- saved route whenever WDM local metrics are available. Mixing a
            -- WDM-local saved route with Questie HBDPins for the live trail is
            -- unsafe because Questie's line refresh clears the shared minimap
            -- line pool before redrawing its own pins, which made the saved
            -- route disappear as soon as recording/trail samples existed.
            if useLocal then
                DrawMiniLocalPath(localPoints, miniTrailDots, TRAIL_COLOR, TRAIL_DOT_COLOR, 1.0, player, widthYards, heightYards, nil)
                if lastMinimapNavSource == "none" then lastMinimapNavSource = "WDM-local" end
            else
                local usedQuestie = false
                if player.c < 0 then
                    usedQuestie = DrawMiniQuestiePath(localPoints, miniTrailDots, TRAIL_COLOR, TRAIL_DOT_COLOR, 1.0, player, nil)
                end
                if not usedQuestie then
                    DrawMiniAstrolabePath(localPoints, miniTrailDots, TRAIL_COLOR, TRAIL_DOT_COLOR, 1.0)
                    if lastMinimapNavSource == "none" then lastMinimapNavSource = "Astrolabe" end
                end
            end
        end
    end

    -- HBD pins reposition on Questie's own update frame, so draw once now and
    -- again from our lightweight minimap-line refresh loop below.
    DrawQuestieMinimapLines()
    UpdateHUD(player, nearestDistance)
end

function TR:Status()
    local ctx = self:GetContext()
    local A = GetAstrolabe()
    local c, z, x, y = GetPlayerPosition()
    local LMD = GetLibMapData()
    local QHBD, QPins, QMapID = GetQuestieNavigation()
    local mapW, mapH, mapFile, mapFloor, mapSource = GetDungeonMapMetrics(true)
    local BM = rawget(_G, "TriRoutesBundledMapMetrics")
    Chat(format("v%s | Astrolabe: %s | WDM addon: %s | LibMapData: %s | bundled WDM metrics: %s | Questie HBD: %s", self.VERSION, A and "YES" or "NO", IsAddOnLoaded("WDM") and "loaded" or "not loaded (MPQ is OK)", LMD and "YES" or "NO", BM and "YES" or "NO", (QHBD and QPins) and "YES" or "NO"))
    if QHBD then Chat("Questie mapID: " .. tostring(QMapID or "?")) end
    Chat("Navigation: arrow=" .. tostring(lastArrowNavSource) .. " | minimap=" .. tostring(lastMinimapNavSource))
    local miniDiameter, miniEnv, miniZoom, miniScaleSource = GetMinimapScaleState(c and c < 0)
    Chat(format("Minimap scale: mode=%s | zoom=%s | %s %.1f yd | source=%s", tostring(db.minimapScaleMode or "auto"), tostring(miniZoom), tostring(miniEnv), tonumber(miniDiameter) or 0, tostring(miniScaleSource or "?")))
    Chat("Route colours: dim blue=completed | blue=current leg | purple=next route")
    local rawArea = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
    local rawFile = GetMapInfo and GetMapInfo() or nil
    local rawFloor = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or nil
    Chat("Map probe: file=" .. tostring(rawFile or "?") .. " area=" .. tostring(rawArea or "?") .. " floor=" .. tostring(rawFloor or "?"))
    if mapW and mapH then Chat(format("Map metrics: %s floor=%s | %.1f x %.1f yd | source=%s", tostring(mapFile), tostring(mapFloor), mapW, mapH, tostring(mapSource))) end
    Chat(format("Instance: %s | type=%s | difficulty=%s | source=%s (index=%s name=%s)%s", tostring(ctx.instanceName), tostring(ctx.instanceType), tostring(ctx.difficultyKey), tostring(ctx.difficultySource or "?"), tostring(ctx.difficultyIndex), tostring(ctx.difficultyName), ctx.instanceType == "raid" and (" | raid size=" .. tostring(ctx.raidSize or ctx.maxPlayers or "?")) or ""))
    if ctx.mythicTier then Chat("Mythic tier: +" .. tostring(ctx.mythicTier) .. " | source=" .. tostring(ctx.mythicSource or "?")) end
    if type(TR.GetTankDetectionState) == "function" then
        local tank = TR.GetTankDetectionState()
        if tank and tank.unit then
            Chat(format("Tank detector: %s (%s) | source=%s | confidence=%.2f | evidence=%s", tostring(tank.name or "?"), tostring(tank.unit), tostring(tank.source or "?"), tonumber(tank.confidence or 0) or 0, tostring(tank.evidence or 0)))
        end
    end
    if c then
        Chat(format("Position: C%s Z%s %.4f %.4f", tostring(c), tostring(z), x, y))
    else
        Chat("Position: unavailable (this is the key WDM/Astrolabe test).")
    end
    if activeRoute then
        local requestedDifficulty = activeRoute.requestedDifficulty or ctx.difficultyKey or "?"
        local selectedDifficulty = activeRoute.selectedDifficulty or (activeRoute.run and activeRoute.run.difficultyKey) or "?"
        local difficultyMatch = activeRoute.difficultyMatch or ((requestedDifficulty == selectedDifficulty) and "exact" or "fallback")
        local raidText = ""
        if ctx.instanceType == "raid" then
            raidText = format(" | raid requested=%s using=%s %s", tostring(activeRoute.requestedRaidSize or ctx.raidSize or "?"), tostring(activeRoute.selectedRaidSize or "?"), tostring(activeRoute.raidSizeMatch or "fallback"))
        end
        Chat(format("Route: BEST %s, %d points, store=%s, source=%s role=%s, sections=%d, quality=%.0f | requested=%s using=%s %s%s", tostring(activeRunId), #activeRoute.points, tostring(activeRoute.sourceKind or "unknown"), tostring(activeRoute.sourceName), tostring(activeRoute.sourceRole), tonumber(activeRoute.sectionCount) or 1, tonumber(activeRoute.qualityScore) or 0, tostring(requestedDifficulty), tostring(selectedDifficulty), tostring(difficultyMatch), raidText))
        if activeRoute.recordedDifficultyKey == "mythic" and activeRoute.recordedMythicTier then
            Chat(format("Curated source: recorded Mythic +%d (%s), classified as %s-compatible", tonumber(activeRoute.recordedMythicTier) or 0, tostring(activeRoute.recordedMythicSource or "unknown"), tostring(selectedDifficulty)))
        end
        if activeComparisonRoute then
            Chat(format("Comparison overlay: %s route (%s), line-only; arrow/NEXT remain on primary", tostring(activeComparisonRoute.selectedDifficulty or "?"), tostring(activeComparisonRoute.builtInId or activeComparisonRoute.runId or "?")))
        elseif db.showComparisonOverlay then
            Chat("Comparison overlay: none useful/curated for this primary route")
        else
            Chat("Comparison overlay: OFF")
        end
        local ps = activeRoute.processStats
        if ps then
            Chat(format("Processed: %d raw -> %d route | pulls=%d bosses=%d turns=%d | short loops=%d (%d pts)", tonumber(ps.rawSamples) or 0, tonumber(ps.outputPoints) or #activeRoute.points, tonumber(ps.pullAnchors) or 0, tonumber(ps.bossAnchors) or 0, tonumber(ps.turnPoints) or 0, tonumber(ps.shortLoopsRemoved) or 0, tonumber(ps.shortLoopPointsRemoved) or 0))
        end
    else
        Chat("Route: none for this instance or any compatible fallback difficulty yet.")
    end
    local run = GetCurrentRun()
    Chat("Recorder: " .. (run and ("ACTIVE run " .. tostring(run.id or "?")) or "idle"))
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("WORLD_MAP_UPDATE")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("LFG_UPDATE")
eventFrame:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "TriRoutes" then
        TriRoutesDB = CopyDefaults(DEFAULTS, TriRoutesDB)
        db = TriRoutesDB
        TR:RefreshRoute(true)
        TR:TryHookDungeonFinderNeeds()
        local pack = rawget(_G, "TriRoutesBuiltInRoutes")
        local routeCount = pack and type(pack.routes) == "table" and #pack.routes or 0
        local needs = TR:GetDungeonFinderNeedsSummary()
        Chat(format("v%s loaded; %d curated built-in routes. Dungeon Finder coverage: %d HC, %d M. /troutes status", TR.VERSION, routeCount, needs.haveNH or 0, needs.haveMythic or 0))
        if not db.arrowHintShown then
            Chat("Drag the cyan route arrow where you want it; /troutes arrow lock when finished.")
            db.arrowHintShown = true
        end
    elseif not db then
        return
    elseif event == "LFG_UPDATE" or event == "LFG_UPDATE_RANDOM_INFO" then
        TR:TryHookDungeonFinderNeeds()
        TR:UpdateDungeonFinderNeeds()
    elseif event == "WORLD_MAP_UPDATE" then
        if WorldMapFrame and WorldMapFrame:IsShown() then TR:DrawWorldMap() end
    else
        TR:RefreshRoute(true)
    end
end)

if WorldMapFrame and WorldMapFrame.HookScript then
    WorldMapFrame:HookScript("OnShow", function() if db then TR:DrawWorldMap() end end)
end

local updateFrame = CreateFrame("Frame")
local miniElapsed, miniLineElapsed, mapElapsed, routeElapsed = 0, 0, 0, 0
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not db or not db.enabled then
        HideRouteArrow()
        return
    end
    UpdateRouteArrow(elapsed)
    miniElapsed = miniElapsed + elapsed
    miniLineElapsed = miniLineElapsed + elapsed
    mapElapsed = mapElapsed + elapsed
    routeElapsed = routeElapsed + elapsed

    if miniLineElapsed >= 0.10 and #minimapLineSets > 0 then
        miniLineElapsed = 0
        DrawQuestieMinimapLines()
    end

    if routeElapsed >= 2.0 then
        routeElapsed = 0
        if not dungeonFinderNeedsHooked then TR:TryHookDungeonFinderNeeds() end
        local ctx = TR:GetContext()
        local key = ContextKey(ctx)
        if key ~= lastContextKey or (not activeRoute and db.autoUseLastRoute) then TR:RefreshRoute(true) end
    end
    if miniElapsed >= 0.50 then
        miniElapsed = 0
        TR:DrawMinimap()
    end
    if mapElapsed >= 1.0 then
        mapElapsed = 0
        if WorldMapFrame and WorldMapFrame:IsShown() then TR:DrawWorldMap() end
    end
end)

SLASH_TRIROUTES1 = "/troutes"
SlashCmdList.TRIROUTES = function(msg)
    local rawMsg = tostring(msg or "")
    msg = lower(rawMsg)
    local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
    local _, rawRest = string.match(rawMsg, "^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "help" then
        Chat("/troutes status | map on/off | minimap on/off | overlay on/off | needs on/off | mythic [player/resetrotation/import] | miniscale auto/indoor/outdoor | trail on/off | route auto/off | process on/off | arrow on/off/reset/lock/unlock | refresh")
    elseif cmd == "status" then
        TR:Status()
    elseif cmd == "map" then
        db.showWorldMap = rest ~= "off"
        Chat("world map route " .. (db.showWorldMap and "ON" or "OFF"))
        TR:DrawWorldMap()
    elseif cmd == "minimap" then
        db.showMinimap = rest ~= "off"
        Chat("minimap route " .. (db.showMinimap and "ON" or "OFF"))
    elseif cmd == "overlay" then
        db.showComparisonOverlay = rest ~= "off"
        TR:RefreshRoute(true)
        TR:DrawMinimap()
        TR:DrawWorldMap()
        Chat("N/H <-> Mythic comparison overlay " .. (db.showComparisonOverlay and "ON" or "OFF"))
    elseif cmd == "needs" then
        db.showDungeonFinderNeeds = rest ~= "off"
        TR:TryHookDungeonFinderNeeds()
        TR:UpdateDungeonFinderNeeds()
        Chat("Dungeon Finder route coverage markers " .. (db.showDungeonFinderNeeds and "ON" or "OFF"))
    elseif cmd == "mythic" then
        if type(TR.HandleMythicSlash) == "function" then
            TR:HandleMythicSlash(rawRest or rest)
        else
            Chat("Mythic+ tracker is unavailable.")
        end
    elseif cmd == "miniscale" then
        if rest == "indoor" or rest == "outdoor" or rest == "auto" then
            db.minimapScaleMode = rest
            Chat("minimap scale mode " .. string.upper(rest))
            TR:DrawMinimap()
        else
            Chat("miniscale: " .. tostring(db.minimapScaleMode or "auto") .. " (use auto, indoor, or outdoor)")
        end
    elseif cmd == "trail" then
        db.showLiveTrail = rest ~= "off"
        Chat("live breadcrumb " .. (db.showLiveTrail and "ON" or "OFF"))
    elseif cmd == "route" then
        if rest == "off" then
            db.routeMode = "off"
            activeRoute = nil
            activeComparisonRoute = nil
            TR:DrawMinimap()
            TR:DrawWorldMap()
            Chat("saved route overlay OFF")
        else
            db.routeMode = "auto"
            db.autoUseLastRoute = true
            TR:RefreshRoute(true)
            Chat("saved route overlay AUTO")
        end
    elseif cmd == "process" then
        db.routeProcessing = rest ~= "off"
        TR:RefreshRoute(true)
        Chat("cleaned route processing " .. (db.routeProcessing and "ON" or "OFF"))
    elseif cmd == "arrow" then
        local sub, value = string.match(rest or "", "^(%S*)%s*(.-)$")
        if sub == "off" then
            db.arrow = false
            HideRouteArrow()
            Chat("route arrow OFF")
        elseif sub == "reset" then
            db.arrowPosition = {"CENTER", 0, -100}
            ApplyArrowPosition()
            Chat("route arrow position reset")
        elseif sub == "lock" then
            db.arrowLocked = true
            ApplyArrowDragState()
            Chat("route arrow locked")
        elseif sub == "unlock" then
            db.arrowLocked = false
            ApplyArrowDragState()
            Chat("route arrow unlocked - drag the cyan arrow itself")
        elseif sub == "scale" then
            local n = tonumber(value)
            if n then
                if n < 0.5 then n = 0.5 end
                if n > 3.0 then n = 3.0 end
                db.arrowScale = n
                ApplyArrowPosition()
                Chat("route arrow scale " .. tostring(n))
            else
                Chat("usage: /troutes arrow scale 1.15")
            end
        else
            db.arrow = true
            CreateRouteArrow()
            ApplyArrowPosition()
            Chat("route arrow ON")
        end
    elseif cmd == "refresh" then
        TR:RefreshRoute(true)
        TR:DrawMinimap()
        TR:DrawWorldMap()
        Chat("route refreshed")
    else
        Chat("Unknown command. /troutes help")
    end
end
