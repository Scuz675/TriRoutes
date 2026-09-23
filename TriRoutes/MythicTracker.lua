-- TriRoutes Mythic+ chat tracker
-- Passive Triumvirate [Mythic+] completion parsing, player history and rotation UI.

TriRoutes = TriRoutes or {}
local TR = TriRoutes

local lower = string.lower
local format = string.format
local tinsert = table.insert
local sort = table.sort

local function TrackerChat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFD54FTriRoutes:|r " .. tostring(msg))
    end
end

local function Trim(s)
    s = tostring(s or "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function StripChatFormatting(s)
    s = tostring(s or "")
    -- Preserve the visible text of links before removing colour/texture escapes.
    s = string.gsub(s, "|H.-|h(.-)|h", "%1")
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|T.-|t", "")
    return Trim(s)
end

local function NormalizePlayerName(name)
    name = Trim(name)
    name = string.gsub(name, "^%[", "")
    name = string.gsub(name, "%]$", "")
    return lower(name)
end

local function CompactKey(name)
    local s = lower(tostring(name or ""))
    s = string.gsub(s, "[^%a%d]", "")
    return s
end

local function EnsureTrackerDB()
    TriRoutesDB = TriRoutesDB or {}
    local tracker = TriRoutesDB.mythicTracker
    if type(tracker) ~= "table" then
        tracker = {}
        TriRoutesDB.mythicTracker = tracker
    end
    if type(tracker.players) ~= "table" then tracker.players = {} end
    if type(tracker.dungeons) ~= "table" then tracker.dungeons = {} end
    return tracker
end

local function ResolveDungeon(dungeonName)
    dungeonName = Trim(dungeonName)
    local target = type(TR.ResolveCollectionTarget) == "function" and TR.ResolveCollectionTarget(dungeonName) or nil
    if target then return target.key, target.label end
    local key = CompactKey(dungeonName)
    if key == "" then return nil, dungeonName end
    return key, dungeonName
end

function TR:ParseMythicCompletionAnnouncement(message)
    local clean = StripChatFormatting(message)
    if clean == "" or not string.find(clean, "[Mythic+]", 1, true) then return nil end

    local level, dungeon = string.match(clean, "[Cc]ompleted%s+an?%s+[Mm]ythic%s*%+(%d+)%s+(.+)$")
    level = tonumber(level)
    if not level or not dungeon then return nil end
    dungeon = Trim(string.gsub(dungeon, "[%.!]+%s*$", ""))
    if dungeon == "" then return nil end

    local prefix = string.match(clean, "^%s*%[Mythic%+%]%s*(.-)%s+[Hh]ave%s+pushed")
        or string.match(clean, "^%s*%[Mythic%+%]%s*(.-)%s+[Hh]as%s+pushed")
        or string.match(clean, "^%s*%[Mythic%+%]%s*(.-)%s+[Cc]ompleted")
    if not prefix then return nil end

    local players = {}
    for name in string.gmatch(prefix, "%[([^%]]+)%]") do
        name = Trim(name)
        if name ~= "" and lower(name) ~= "mythic+" then tinsert(players, name) end
    end
    if #players == 0 then return nil end

    local dungeonKey, dungeonLabel = ResolveDungeon(dungeon)
    if not dungeonKey then return nil end
    return {
        players = players,
        level = level,
        dungeon = dungeonLabel,
        dungeonKey = dungeonKey,
        raw = clean,
    }
end

-- Keystone links are rotation evidence only.  Anyone can link an item, so these
-- observations must never change a player's personal Mythic+ completion record.
function TR:ParseMythicKeystoneLinks(message)
    local clean = StripChatFormatting(message)
    if clean == "" or not string.find(lower(clean), "mythic keystone:", 1, true) then return {} end

    local found = {}
    local seen = {}
    for dungeon, levelText in string.gmatch(clean, "%[[Mm]ythic%s+[Kk]eystone:%s*(.-)%s+%+(%d+)%]") do
        local level = tonumber(levelText)
        dungeon = Trim(dungeon)
        if level and level > 0 and dungeon ~= "" then
            local dungeonKey, dungeonLabel = ResolveDungeon(dungeon)
            if dungeonKey then
                local sig = tostring(dungeonKey) .. "|" .. tostring(level)
                if not seen[sig] then
                    seen[sig] = true
                    tinsert(found, {
                        level = level,
                        dungeon = dungeonLabel,
                        dungeonKey = dungeonKey,
                        raw = clean,
                    })
                end
            end
        end
    end
    return found
end

local lastAnnouncementSignature, lastAnnouncementAt

function TR:RecordMythicCompletion(players, level, dungeonName, seenAt)
    level = tonumber(level)
    if not level or level < 1 or type(players) ~= "table" or #players == 0 then return false end
    local dungeonKey, dungeonLabel = ResolveDungeon(dungeonName)
    if not dungeonKey then return false end

    local tracker = EnsureTrackerDB()
    local now = tonumber(seenAt) or (time and time()) or 0
    if not tracker.rotationStartedAt then tracker.rotationStartedAt = now end

    local dungeon = tracker.dungeons[dungeonKey]
    if type(dungeon) ~= "table" then
        dungeon = { key=dungeonKey, label=dungeonLabel, firstSeen=now, completions=0 }
        tracker.dungeons[dungeonKey] = dungeon
    end
    dungeon.label = dungeonLabel or dungeon.label
    if not dungeon.firstSeen or dungeon.firstSeen == 0 then dungeon.firstSeen = now end
    dungeon.lastSeen = now
    dungeon.completions = (tonumber(dungeon.completions) or 0) + 1
    if not dungeon.highestSeen or level > dungeon.highestSeen then dungeon.highestSeen = level end

    for _, displayName in ipairs(players) do
        local playerKey = NormalizePlayerName(displayName)
        if playerKey ~= "" then
            local profile = tracker.players[playerKey]
            if type(profile) ~= "table" then
                profile = { name=displayName, dungeons={} }
                tracker.players[playerKey] = profile
            end
            if type(profile.dungeons) ~= "table" then profile.dungeons = {} end
            profile.name = displayName
            profile.lastSeen = now
            profile.lastDungeonKey = dungeonKey
            profile.lastDungeon = dungeonLabel
            profile.lastLevel = level
            if not profile.highest or level > profile.highest then profile.highest = level end

            local best = profile.dungeons[dungeonKey]
            if type(best) ~= "table" then
                best = { key=dungeonKey, label=dungeonLabel, firstSeen=now }
                profile.dungeons[dungeonKey] = best
            end
            best.label = dungeonLabel
            best.lastSeen = now
            best.completions = (tonumber(best.completions) or 0) + 1
            if not best.highest or level > best.highest then best.highest = level end
        end
    end

    if type(self.UpdateDungeonFinderNeeds) == "function" then self:UpdateDungeonFinderNeeds() end
    return true
end

local lastKeystoneSignature, lastKeystoneAt

function TR:RecordMythicKeystone(level, dungeonName, seenAt)
    level = tonumber(level)
    if not level or level < 1 then return false end
    local dungeonKey, dungeonLabel = ResolveDungeon(dungeonName)
    if not dungeonKey then return false end

    local tracker = EnsureTrackerDB()
    local now = tonumber(seenAt) or (time and time()) or 0
    if not tracker.rotationStartedAt then tracker.rotationStartedAt = now end

    local dungeon = tracker.dungeons[dungeonKey]
    if type(dungeon) ~= "table" then
        dungeon = { key=dungeonKey, label=dungeonLabel, firstSeen=now, completions=0, advertisements=0 }
        tracker.dungeons[dungeonKey] = dungeon
    end
    dungeon.label = dungeonLabel or dungeon.label
    if not dungeon.firstSeen or dungeon.firstSeen == 0 then dungeon.firstSeen = now end
    dungeon.lastSeen = now
    dungeon.lastKeystoneSeen = now
    dungeon.advertisements = (tonumber(dungeon.advertisements) or 0) + 1
    if not dungeon.highestAdvertised or level > dungeon.highestAdvertised then
        dungeon.highestAdvertised = level
    end

    if type(self.UpdateDungeonFinderNeeds) == "function" then self:UpdateDungeonFinderNeeds() end
    return true
end

function TR:HandleMythicAnnouncement(message)
    if not TriRoutesDB or TriRoutesDB.trackMythicAnnouncements == false then return false end

    local handled = false
    local parsed = self:ParseMythicCompletionAnnouncement(message)
    if parsed then
        local now = GetTime and GetTime() or 0
        local sig = table.concat(parsed.players, ",") .. "|" .. tostring(parsed.level) .. "|" .. tostring(parsed.dungeonKey)
        if not (sig == lastAnnouncementSignature and lastAnnouncementAt and (now - lastAnnouncementAt) < 2) then
            lastAnnouncementSignature, lastAnnouncementAt = sig, now
            self:RecordMythicCompletion(parsed.players, parsed.level, parsed.dungeon)
        end
        handled = true
    end

    local links = self:ParseMythicKeystoneLinks(message)
    if #links > 0 then
        local now = GetTime and GetTime() or 0
        for _, link in ipairs(links) do
            local sig = tostring(link.dungeonKey) .. "|" .. tostring(link.level)
            if not (sig == lastKeystoneSignature and lastKeystoneAt and (now - lastKeystoneAt) < 2) then
                lastKeystoneSignature, lastKeystoneAt = sig, now
                self:RecordMythicKeystone(link.level, link.dungeon)
            end
        end
        handled = true
    end

    return handled
end

function TR:GetMythicProfile(name)
    local tracker = EnsureTrackerDB()
    local key = NormalizePlayerName(name)
    if key == "" then return nil end
    return tracker.players[key]
end

function TR:GetMythicRotationEntry(keyOrName)
    local tracker = EnsureTrackerDB()
    local key = tostring(keyOrName or "")
    if tracker.dungeons[key] then return tracker.dungeons[key] end
    local dungeonKey = ResolveDungeon(keyOrName)
    return dungeonKey and tracker.dungeons[dungeonKey] or nil
end

function TR:GetMythicRotationEntries()
    local tracker = EnsureTrackerDB()
    local result = {}
    for _, entry in pairs(tracker.dungeons) do tinsert(result, entry) end
    sort(result, function(a, b) return lower(tostring(a.label or a.key)) < lower(tostring(b.label or b.key)) end)
    return result
end

local function FormatPlayerProfile(profile)
    if not profile then return nil end
    local parts = {}
    for _, best in pairs(profile.dungeons or {}) do
        tinsert(parts, { label=best.label or best.key or "?", level=tonumber(best.highest) or 0 })
    end
    sort(parts, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return lower(a.label) < lower(b.label)
    end)
    return parts
end

function TR:HandleMythicSlash(rest)
    rest = Trim(rest)

    local importText = string.match(rest, "^[Ii][Mm][Pp][Oo][Rr][Tt]%s+(.+)$")
    if importText then
        if self:HandleMythicAnnouncement(importText) then
            TrackerChat("Imported Mythic+ chat evidence.")
        else
            TrackerChat("Could not parse Mythic+ completion or keystone evidence from that text.")
        end
        return
    end

    if lower(rest) == "resetrotation" then
        local tracker = EnsureTrackerDB()
        tracker.dungeons = {}
        tracker.rotationStartedAt = (time and time()) or 0
        if type(self.UpdateDungeonFinderNeeds) == "function" then self:UpdateDungeonFinderNeeds() end
        TrackerChat("Mythic+ observed rotation reset; player personal-bests preserved.")
        return
    end

    if rest ~= "" then
        local profile = self:GetMythicProfile(rest)
        if not profile then
            TrackerChat("No observed Mythic+ completions for " .. rest .. ".")
            return
        end
        TrackerChat(format("%s | Mythic+ Best: +%d", tostring(profile.name or rest), tonumber(profile.highest) or 0))
        local parts = FormatPlayerProfile(profile)
        local shown = 0
        for _, best in ipairs(parts) do
            TrackerChat(format("  %s +%d", tostring(best.label), tonumber(best.level) or 0))
            shown = shown + 1
            if shown >= 8 then break end
        end
        return
    end

    local entries = self:GetMythicRotationEntries()
    if #entries == 0 then
        TrackerChat("Mythic+ observed rotation: no completion or keystone evidence seen yet.")
        return
    end
    TrackerChat("Mythic+ observed rotation:")
    for _, entry in ipairs(entries) do
        local completion = tonumber(entry.highestSeen)
        local advertised = tonumber(entry.highestAdvertised)
        if completion and advertised then
            TrackerChat(format("  %s | completed +%d | key +%d", tostring(entry.label or entry.key), completion, advertised))
        elseif completion then
            TrackerChat(format("  %s | completed +%d", tostring(entry.label or entry.key), completion))
        elseif advertised then
            TrackerChat(format("  %s | key +%d", tostring(entry.label or entry.key), advertised))
        else
            TrackerChat(format("  %s | observed", tostring(entry.label or entry.key)))
        end
    end
end

-- Public read API for TriAudit or other Triumvirate addons.
TriRoutesAPI = TriRoutesAPI or {}
TriRoutesAPI.GetMythicProfile = function(name) return TR:GetMythicProfile(name) end
TriRoutesAPI.GetMythicRotationEntry = function(name) return TR:GetMythicRotationEntry(name) end
TriRoutesAPI.GetMythicRotationEntries = function() return TR:GetMythicRotationEntries() end
TriRoutesAPI.RecordMythicKeystone = function(level, dungeonName) return TR:RecordMythicKeystone(level, dungeonName) end

local function AddMythicLineToTooltip(tooltip)
    if not tooltip or not TriRoutesDB or TriRoutesDB.showMythicTooltip == false then return end
    if tooltip.trRoutesMythicUnitAdded then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local profile = name and TR:GetMythicProfile(name) or nil
    if not profile or not profile.highest then return end

    tooltip:AddLine("Mythic+ Best: +" .. tostring(profile.highest), 1.00, 0.82, 0.20, true)
    if profile.lastDungeon and profile.lastLevel then
        tooltip:AddLine("Last observed: " .. tostring(profile.lastDungeon) .. " +" .. tostring(profile.lastLevel), 0.78, 0.86, 0.96, true)
    end
    tooltip.trRoutesMythicUnitAdded = true
    tooltip:Show()
end

local function HookPlayerTooltip()
    if not GameTooltip or GameTooltip.trRoutesMythicHooked or not GameTooltip.HookScript then return end
    GameTooltip:HookScript("OnTooltipSetUnit", AddMythicLineToTooltip)
    GameTooltip:HookScript("OnTooltipCleared", function(self) self.trRoutesMythicUnitAdded = nil end)
    GameTooltip.trRoutesMythicHooked = true
end

local inspectText
local function EnsureInspectText()
    local frame = rawget(_G, "InspectFrame")
    if inspectText or not frame or not frame.CreateFontString then return inspectText end
    inspectText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inspectText:SetPoint("TOP", frame, "TOP", 0, -36)
    inspectText:SetTextColor(1.00, 0.82, 0.20)
    inspectText:SetText("")
    inspectText:Hide()
    return inspectText
end

local function RefreshInspectMythic()
    local text = EnsureInspectText()
    if not text or not TriRoutesDB or TriRoutesDB.showMythicInspect == false then
        if text then text:Hide() end
        return
    end
    local frame = rawget(_G, "InspectFrame")
    if not frame or not frame:IsShown() then text:Hide(); return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then
        unit = UnitExists("target") and "target" or nil
    end
    local name = unit and UnitName(unit) or nil
    local profile = name and TR:GetMythicProfile(name) or nil
    if profile and profile.highest then
        text:SetText("Mythic+ Best: +" .. tostring(profile.highest))
        text:Show()
    else
        text:Hide()
    end
end

local inspectHooked = false
local function TryHookInspectFrame()
    local frame = rawget(_G, "InspectFrame")
    if not frame or inspectHooked or not frame.HookScript then return false end
    frame:HookScript("OnShow", RefreshInspectMythic)
    frame:HookScript("OnHide", function() if inspectText then inspectText:Hide() end end)
    inspectHooked = true
    RefreshInspectMythic()
    return true
end

local chatFrameHandlerHooked = false
local function TryHookDisplayedChat()
    if chatFrameHandlerHooked then return true end
    if type(hooksecurefunc) ~= "function" or type(rawget(_G, "ChatFrame_MessageEventHandler")) ~= "function" then return false end

    -- Triumvirate can emit custom announcements and player keystone links
    -- through different CHAT_MSG_* event families.  The common invariant is
    -- that displayed text reaches the stock chat-frame handler.  Hooking it
    -- makes Mythic+ evidence capture independent of the chosen chat event;
    -- duplicate guards prevent multiple chat windows from double counting.
    hooksecurefunc("ChatFrame_MessageEventHandler", function(self, event, ...)
        local message = select(1, ...)
        if type(message) == "string" and string.find(message, "Mythic", 1, true) then
            TR:HandleMythicAnnouncement(message)
        end
    end)
    chatFrameHandlerHooked = true
    return true
end

local trackerFrame = CreateFrame("Frame")
trackerFrame:RegisterEvent("ADDON_LOADED")
trackerFrame:RegisterEvent("CHAT_MSG_SYSTEM")
trackerFrame:RegisterEvent("CHAT_MSG_CHANNEL")
trackerFrame:RegisterEvent("CHAT_MSG_GUILD")
trackerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
trackerFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "TriRoutes" then
            EnsureTrackerDB()
            HookPlayerTooltip()
            TryHookInspectFrame()
            TryHookDisplayedChat()
        elseif arg1 == "Blizzard_InspectUI" then
            TryHookInspectFrame()
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        if inspectHooked then RefreshInspectMythic() end
        return
    end
    TR:HandleMythicAnnouncement(arg1)
end)
