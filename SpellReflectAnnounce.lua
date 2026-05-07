-- SpellReflectAnnounce
-- Announces in chat when Spell Reflection (spell ID 23920) is buffed on the player.
-- Midnight-safe: uses the C_UnitAuras instance-ID delta model (UNIT_AURA updateInfo)
-- instead of polling UnitAura indices, and never touches the secure combat log.
--
-- Scope: only active inside instances (dungeons / raids / scenarios / PvP).
--
-- Taint avoidance: UNIT_AURA can fire synchronously inside the spellcast secure
-- dispatch chain (the cast that just applied the buff). If we run any insecure
-- Lua inside that chain, taint propagates onto the secure call stack and the
-- next protected action triggers "Interface action failed because of an AddOn".
-- We therefore defer ALL UNIT_AURA processing to the next frame via
-- RunNextFrame, which guarantees our code runs on a clean (insecure) stack.

local addonName, ns = ...

local SPELL_REFLECT_ID = 23920

local function IsInsideInstance()
    local inInstance, instanceType = IsInInstance()
    -- instanceType is one of: "none", "pvp", "arena", "party", "raid", "scenario".
    return inInstance and instanceType ~= "none"
end

-- Default config; merged into SpellReflectAnnounceDB on ADDON_LOADED.
ns.defaults = {
    message = "Spell Reflect up!",
    channel = "SAY", -- one of: SAY, YELL, PARTY, RAID, INSTANCE_CHAT
}

-- Channels we will silently downgrade away from when the player is not in the
-- appropriate group context, to avoid the "You are not in a raid group." spam.
local function ResolveChannel(channel)
    if channel == "RAID" then
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return "SAY"
    elseif channel == "PARTY" then
        if IsInGroup() then return "PARTY" end
        return "SAY"
    elseif channel == "INSTANCE_CHAT" then
        -- Note: Blizzard's own 12.x code still uses the legacy
        -- LE_PARTY_CATEGORY_INSTANCE global. There is no Enum.PartyCategory
        -- in Midnight, so don't be tempted to "modernize" this.
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return "SAY"
    end
    return channel -- SAY / YELL always allowed
end

-- Per-instance throttle: each fresh application has a new auraInstanceID, so we
-- only announce once per cast and never re-announce on refresh/duration ticks.
local announcedInstances = {} -- [auraInstanceID] = true

local function IsSpellReflect(aura)
    return aura and aura.spellId == SPELL_REFLECT_ID
end

local function Announce(aura)
    if announcedInstances[aura.auraInstanceID] then return end
    announcedInstances[aura.auraInstanceID] = true

    local db = SpellReflectAnnounceDB or ns.defaults
    local message = (db.message and db.message ~= "") and db.message or ns.defaults.message
    local channel = ResolveChannel(db.channel or ns.defaults.channel)
    SendChatMessage(message, channel)
end

local function ScanFullPlayerBuffs(silent)
    -- Full rebuild path: walk current HELPFUL auras. Used on login and on
    -- isFullUpdate UNIT_AURA events.
    --
    -- When `silent` is true (login / reload / full update), we record any
    -- already-active Spell Reflect into the throttle table WITHOUT announcing,
    -- so we don't spam chat for buffs that were applied before this scan.
    -- Fresh applications still go through the addedAuras path and announce.
    local seen = {}
    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
        if aura then
            seen[aura.auraInstanceID] = true
            if IsSpellReflect(aura) then
                if silent then
                    announcedInstances[aura.auraInstanceID] = true
                else
                    Announce(aura)
                end
            end
        end
    end, true)

    -- Drop entries for auras that no longer exist so the table can't grow
    -- without bound across a long session.
    for id in pairs(announcedInstances) do
        if not seen[id] then announcedInstances[id] = nil end
    end
end

local function OnUnitAura(unit, updateInfo)
    if unit ~= "player" then return end
    if not IsInsideInstance() then return end

    if not updateInfo or updateInfo.isFullUpdate then
        -- Full update: don't re-announce auras that were already active.
        ScanFullPlayerBuffs(true)
        return
    end

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if IsSpellReflect(aura) then
                Announce(aura)
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            announcedInstances[id] = nil
        end
    end
end

-- Trampoline: defer the real handler to the next frame so we never run inside
-- the secure dispatch chain that may have triggered UNIT_AURA. RunNextFrame
-- is the modern, taint-safe primitive for this; C_Timer.After(0, ...) works
-- but RunNextFrame is preferred in 11.x+ FrameXML.
local function OnUnitAuraDeferred(unit, updateInfo)
    RunNextFrame(function()
        OnUnitAura(unit, updateInfo)
    end)
end

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_AURA" then
        OnUnitAuraDeferred(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Suppress announcement on login / reload / zone change for buffs that
        -- are already up; only fresh applications should trigger chat.
        if IsInsideInstance() then
            RunNextFrame(function() ScanFullPlayerBuffs(true) end)
        end
    elseif event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            SpellReflectAnnounceDB = SpellReflectAnnounceDB or {}
            for k, v in pairs(ns.defaults) do
                if SpellReflectAnnounceDB[k] == nil then
                    SpellReflectAnnounceDB[k] = v
                end
            end
        end
    end
end)
