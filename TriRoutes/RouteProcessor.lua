-- TriRoutes 0.1.0-test6c route processor
-- Converts raw recorded movement into a smaller navigation path while preserving
-- real corridor travel, pull starts, boss/manual landmarks, and meaningful turns.

TriRoutes = TriRoutes or {}
local TR = TriRoutes

local sqrt = math.sqrt
local acos = math.acos
local min = math.min
local max = math.max
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local tinsert = table.insert
local tremove = table.remove

local function SameMap(a, b)
    if not (a and b and a.c == b.c and (a.z or 0) == (b.z or 0)) then return false end
    if a.section and b.section and a.section ~= b.section then return false end
    -- A real WDM floor is reusable across runs; recorder phase numbers are only
    -- session-local. Prefer floor identity whenever both points provide it.
    if a.floor and b.floor and a.floor > 0 and b.floor > 0 then
        if a.floor ~= b.floor then return false end
    elseif a.phase and b.phase and a.phase ~= b.phase then
        return false
    end
    return true
end

local function Dist(a, b)
    if not SameMap(a, b) then return 999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return sqrt(dx * dx + dy * dy)
end

local function CopyPoint(s)
    if not s then return nil end
    return {
        c = s.c,
        z = s.z or 0,
        x = s.x,
        y = s.y,
        t = s.t,
        section = s.section,
        phase = s.phase,
        floor = s.floor,
        mapFile = s.mapFile,
        recovery = s.recovery,
        breakBefore = s.breakBefore,
    }
end

local function CountTable(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function BetterKind(oldKind, newKind)
    local rank = {
        boss = 100,
        warning = 90,
        stairs = 85,
        skip = 80,
        pull = 70,
        start = 60,
        finish = 60,
        turn = 20,
        note = 10,
    }
    if not oldKind then return newKind end
    if (rank[newKind] or 0) > (rank[oldKind] or 0) then return newKind end
    return oldKind
end

local function MarkPoint(p, kind, label, forced)
    if not p then return end
    p.kind = BetterKind(p.kind, kind)
    if label and label ~= "" then p.label = label end
    if forced then p.forced = true end
end

local function NormalizeSamples(samples, spacing, stats)
    local out = {}
    local last
    spacing = tonumber(spacing) or 0.0015

    -- Recorder shutdown can catch one outdoor coordinate immediately after
    -- leaving an instance.  Keep the dominant continent context for the route
    -- while still allowing z/floor changes within that context.
    local counts = {}
    local dominantC, dominantCount
    for i = 1, #(samples or {}) do
        local s = samples[i]
        if s and s.c ~= nil and s.x and s.y then
            local key = tostring(s.c)
            counts[key] = (counts[key] or 0) + 1
            if not dominantCount or counts[key] > dominantCount then
                dominantC, dominantCount = s.c, counts[key]
            end
        end
    end
    stats.dominantContinent = dominantC

    for i = 1, #(samples or {}) do
        local s = samples[i]
        if s and not s.recovery and s.c ~= nil and s.c == dominantC and s.x and s.y then
            local p = CopyPoint(s)
            local teleportJump = last and SameMap(last, p) and Dist(last, p) >= 0.20
            if not last or not SameMap(last, p) or Dist(last, p) >= spacing then
                -- Culling and a few custom/server routes can move the party with an
                -- in-instance teleport NPC. Preserve both sides of an implausibly
                -- large same-map jump, but never draw/navigate a straight segment
                -- across the teleport gap.
                if teleportJump then
                    p.breakBefore = true
                    p.forced = true
                    p.kind = "skip"
                    p.label = "Teleport skip"
                end
                out[#out + 1] = p
                last = p
            elseif p.t and last.t and (p.t - last.t) >= 6 then
                out[#out + 1] = p
                last = p
            end
        end
    end

    stats.normalizedSamples = #out
    return out
end

local function NearestPointIndex(points, t, pos)
    local best, bestScore
    for i = 1, #points do
        local p = points[i]
        local timeScore = (t and p.t) and math.abs(p.t - t) or 0
        local posScore = 0
        if pos and SameMap(p, pos) then
            posScore = Dist(p, pos) * 120
        elseif pos then
            posScore = 25
        end
        local score = timeScore + posScore
        if not bestScore or score < bestScore then
            best, bestScore = i, score
        end
    end
    return best
end

local function AddRunAnchors(points, run, stats)
    if #points == 0 then return end
    MarkPoint(points[1], "start", "Start", true)
    MarkPoint(points[#points], "finish", "End", true)

    local combats = run and run.combats or {}
    for i = 1, #combats do
        local combat = combats[i]
        local idx = NearestPointIndex(points, combat.start, combat.startPos)
        if idx then
            local count = CountTable(combat.npcs)
            local label = count > 0 and ("Pull " .. tostring(i) .. " (" .. tostring(count) .. " mobs)") or ("Pull " .. tostring(i))
            MarkPoint(points[idx], "pull", label, true)
            points[idx].combatIndex = i
            stats.pullAnchors = stats.pullAnchors + 1
        end

        -- Preserve the end location only when the fight moved a meaningful distance.
        -- This keeps chain-pull travel intact but doesn't force tiny combat shuffles.
        local endIdx = NearestPointIndex(points, combat.finish, combat.endPos)
        if idx and endIdx and endIdx > idx and combat.startPos and combat.endPos then
            if Dist(combat.startPos, combat.endPos) >= 0.018 then
                points[endIdx].forced = true
                points[endIdx].combatEnd = i
            end
        end
    end

    for _, e in ipairs(run and run.events or {}) do
        if e and (e.x and e.y) then
            local idx = NearestPointIndex(points, e.t, e)
            if idx then
                if e.kind == "boss_candidate" then
                    MarkPoint(points[idx], "boss", e.name or "Boss", true)
                    stats.bossAnchors = stats.bossAnchors + 1
                elseif e.kind == "mark" then
                    local kind = e.mark or "note"
                    local label = e.note and e.note ~= "" and e.note or string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2)
                    MarkPoint(points[idx], kind, label, true)
                    stats.manualAnchors = stats.manualAnchors + 1
                end
            end
        end
    end
end

local function HasForcedBetween(points, first, last)
    for i = first, last do
        if points[i] and points[i].forced then return true end
    end
    return false
end

local function RemoveShortLoops(points, opts, stats)
    local out = {}
    local radius = tonumber(opts.shortLoopRadius) or 0.0065
    local seconds = tonumber(opts.shortLoopSeconds) or 12
    local maxExtent = tonumber(opts.shortLoopMaxExtent) or 0.025
    local searchBack = tonumber(opts.shortLoopSearchBack) or 22

    for i = 1, #points do
        local p = points[i]
        out[#out + 1] = p

        if not p.forced and #out >= 4 then
            local lastIndex = #out
            local minIndex = max(1, lastIndex - searchBack)
            local loopAt
            for j = lastIndex - 2, minIndex, -1 do
                local a = out[j]
                local dt = (p.t and a.t) and (p.t - a.t) or 999
                if dt > seconds then break end
                if SameMap(a, p) and Dist(a, p) <= radius and not HasForcedBetween(out, j + 1, lastIndex - 1) then
                    local extent = 0
                    for k = j + 1, lastIndex - 1 do
                        extent = max(extent, Dist(a, out[k]))
                    end
                    if extent <= maxExtent then
                        loopAt = j
                        break
                    end
                end
            end

            if loopAt then
                local keep = out[#out]
                local removed = 0
                for k = #out - 1, loopAt + 1, -1 do
                    tremove(out, k)
                    removed = removed + 1
                end
                out[#out] = keep
                stats.shortLoopPointsRemoved = stats.shortLoopPointsRemoved + removed
                stats.shortLoopsRemoved = stats.shortLoopsRemoved + 1
            end
        end
    end

    return out
end

local function PerpDistance(p, a, b)
    if not SameMap(p, a) or not SameMap(a, b) then return 999 end
    local vx = (b.x or 0) - (a.x or 0)
    local vy = (b.y or 0) - (a.y or 0)
    local wx = (p.x or 0) - (a.x or 0)
    local wy = (p.y or 0) - (a.y or 0)
    local len2 = vx * vx + vy * vy
    if len2 <= 0.0000000001 then return Dist(p, a) end
    local u = (wx * vx + wy * vy) / len2
    if u < 0 then u = 0 elseif u > 1 then u = 1 end
    local px = (a.x or 0) + u * vx
    local py = (a.y or 0) + u * vy
    local dx = (p.x or 0) - px
    local dy = (p.y or 0) - py
    return sqrt(dx * dx + dy * dy)
end

local function RDPRange(points, first, last, epsilon, keep)
    if last <= first + 1 then return end
    local a, b = points[first], points[last]
    if not SameMap(a, b) then
        for i = first + 1, last - 1 do keep[i] = true end
        return
    end

    local bestIndex, bestDistance = nil, -1
    for i = first + 1, last - 1 do
        local d = PerpDistance(points[i], a, b)
        if d > bestDistance then
            bestDistance = d
            bestIndex = i
        end
    end

    if bestIndex and bestDistance > epsilon then
        keep[bestIndex] = true
        RDPRange(points, first, bestIndex, epsilon, keep)
        RDPRange(points, bestIndex, last, epsilon, keep)
    end
end

local function SimplifyPreservingAnchors(points, epsilon)
    if #points <= 2 then return points end

    -- Treat floor/phase/section changes as hard simplification boundaries.
    -- Without this, one combat spanning a WDM floor transition causes RDPRange
    -- to preserve every sample between its start/end anchors because the two
    -- endpoints intentionally fail SameMap().
    local anchorSet = {[1] = true, [#points] = true}
    for i = 2, #points - 1 do
        if points[i].forced then anchorSet[i] = true end
    end
    for i = 2, #points do
        if not SameMap(points[i - 1], points[i]) then
            anchorSet[i - 1] = true
            anchorSet[i] = true
        end
    end

    local anchors = {}
    for i = 1, #points do
        if anchorSet[i] then anchors[#anchors + 1] = i end
    end

    local keep = {[1] = true, [#points] = true}
    for i = 1, #anchors do keep[anchors[i]] = true end
    for i = 1, #anchors - 1 do
        RDPRange(points, anchors[i], anchors[i + 1], epsilon, keep)
    end

    local out = {}
    for i = 1, #points do
        if keep[i] then out[#out + 1] = points[i] end
    end
    return out
end

local function AddTurnKinds(points, opts, stats)
    local threshold = tonumber(opts.turnAngleDegrees) or 48
    local minLeg = tonumber(opts.turnMinLeg) or 0.010
    local cosThreshold = math.cos(math.rad(threshold))

    for i = 2, #points - 1 do
        local a, p, b = points[i - 1], points[i], points[i + 1]
        if SameMap(a, p) and SameMap(p, b) and not p.kind then
            local ax, ay = p.x - a.x, p.y - a.y
            local bx, by = b.x - p.x, b.y - p.y
            local al = sqrt(ax * ax + ay * ay)
            local bl = sqrt(bx * bx + by * by)
            if al >= minLeg and bl >= minLeg then
                local dot = (ax * bx + ay * by) / (al * bl)
                if dot < -1 then dot = -1 elseif dot > 1 then dot = 1 end
                if dot <= cosThreshold then
                    p.kind = "turn"
                    p.label = "Turn"
                    stats.turnPoints = stats.turnPoints + 1
                end
            end
        end
    end
end

local function LimitPoints(points, maxPoints)
    maxPoints = tonumber(maxPoints) or 220
    if #points <= maxPoints then return points end

    local forcedCount = 0
    for i = 1, #points do if points[i].forced then forcedCount = forcedCount + 1 end end
    if forcedCount >= maxPoints then return points end

    local ordinaryBudget = maxPoints - forcedCount
    local ordinaryCount = #points - forcedCount
    local stride = max(1, math.ceil(ordinaryCount / ordinaryBudget))
    local out, ordinarySeen = {}, 0
    for i = 1, #points do
        local p = points[i]
        if p.forced then
            out[#out + 1] = p
        else
            ordinarySeen = ordinarySeen + 1
            if ordinarySeen == 1 or (ordinarySeen % stride) == 0 or i == #points then
                out[#out + 1] = p
            end
        end
    end
    return out
end

function TR.ProcessRunRoute(run, track, opts)
    opts = opts or {}
    local samples = track and track.samples or nil
    if not samples or #samples < 2 then return nil, nil end

    local stats = {
        rawSamples = #samples,
        normalizedSamples = 0,
        shortLoopsRemoved = 0,
        shortLoopPointsRemoved = 0,
        pullAnchors = 0,
        bossAnchors = 0,
        manualAnchors = 0,
        turnPoints = 0,
    }

    local points = NormalizeSamples(samples, opts.inputSpacing or 0.0015, stats)
    if #points < 2 then return nil, stats end

    AddRunAnchors(points, run, stats)
    points = RemoveShortLoops(points, opts, stats)

    local epsilon = tonumber(opts.simplifyEpsilon) or 0.0048
    points = SimplifyPreservingAnchors(points, epsilon)
    AddTurnKinds(points, opts, stats)
    points = LimitPoints(points, opts.maxPoints or 220)

    stats.outputPoints = #points
    stats.removedPoints = stats.rawSamples - #points
    return points, stats
end
