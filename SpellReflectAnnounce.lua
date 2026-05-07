-- SpellReflectAnnounce
-- Announces in chat when Spell Reflection (spell ID 23920) is buffed on the player.
-- Midnight-safe: uses the C_UnitAuras instance-ID delta model (UNIT_AURA updateInfo)
-- instead of polling UnitAura indices, and never touches the secure combat log.

local addonName, ns = ...

local SPELL_REFLECT_ID = 23920

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

local function ScanFullPlayerBuffs()
    -- Full rebuild path: walk current HELPFUL auras and announce any active
    -- Spell Reflect we haven't already flagged. Used on login and on
    -- isFullUpdate UNIT_AURA events.
    local seen = {}
    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
        if aura then
            seen[aura.auraInstanceID] = true
            if IsSpellReflect(aura) then
                Announce(aura)
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

    if not updateInfo or updateInfo.isFullUpdate then
        ScanFullPlayerBuffs()
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

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_AURA" then
        OnUnitAura(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanFullPlayerBuffs()
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
