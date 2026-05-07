-- SpellReflectAnnounce
-- Announces in chat when the player casts Spell Reflection (spell ID 23920).
--
-- Why we trigger off the *cast*, not the buff:
--   In Midnight, AuraData entries inside UNIT_AURA's `addedAuras` table are
--   flagged ConditionalSecretContents = true (UnitConstantsDocumentation.lua),
--   and most C_UnitAuras read functions are SecretWhenUnitAuraRestricted = true
--   (UnitAuraDocumentation.lua). While AddOnRestrictionType.Encounter /
--   ChallengeMode / PvPMatch / Combat is Active, the engine omits or wraps
--   class-defensive aura entries to defeat exactly this kind of automation,
--   so an aura-based detector NEVER sees Spell Reflect inside instanced
--   combat -- even on the local player. UNIT_SPELLCAST_SUCCEEDED on "player"
--   is not flagged HasRestrictions and continues to deliver the raw spellID.
--
-- Chat restriction:
--   SendChatMessage is HasRestrictions = true (ChatInfoDocumentation.lua) and
--   is silently dropped while AddOnRestrictionType.Chat is Active. We queue
--   announces in that case and flush on ADDON_RESTRICTION_STATE_CHANGED ->
--   Inactive and on PLAYER_REGEN_ENABLED. We always also echo to the local
--   chat frame so the player sees the proc immediately.
--
-- Scope: only active inside instances (dungeons / raids / scenarios / PvP).

local addonName, ns = ...

local SPELL_REFLECT_ID = 23920

local function IsInsideInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType ~= "none"
end

ns.defaults = {
    message = "Spell Reflect up!",
    channel = "SAY", -- one of: SAY, YELL, PARTY, RAID, INSTANCE_CHAT
}

local function ResolveChannel(channel)
    if channel == "RAID" then
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return "SAY"
    elseif channel == "PARTY" then
        if IsInGroup() then return "PARTY" end
        return "SAY"
    elseif channel == "INSTANCE_CHAT" then
        -- Blizzard 12.x still uses the legacy LE_PARTY_CATEGORY_INSTANCE
        -- global; there is no Enum.PartyCategory replacement yet.
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return "SAY"
    end
    return channel -- SAY / YELL always allowed
end

-- Pending queue for announces that we tried to send while
-- AddOnRestrictionType.Chat was Active.
local pendingAnnounces = {} -- array of { message=, channel= }

local function IsChatRestricted()
    local C_RA = C_RestrictedActions
    if not C_RA or not Enum or not Enum.AddOnRestrictionType then return false end
    return C_RA.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat)
end

local function TrySend(message, channel)
    if IsChatRestricted() then
        pendingAnnounces[#pendingAnnounces + 1] = { message = message, channel = channel }
        return false
    end
    SendChatMessage(message, channel)
    return true
end

local function FlushPending()
    if #pendingAnnounces == 0 then return end
    if IsChatRestricted() then return end
    local queue = pendingAnnounces
    pendingAnnounces = {}
    for _, entry in ipairs(queue) do
        SendChatMessage(entry.message, ResolveChannel(entry.channel))
    end
end

-- Cap announcements to once per ~3s so a macro-spammed cast can't flood SAY.
local lastAnnounceAt = 0

local function Announce()
    local now = GetTime()
    if now - lastAnnounceAt < 3 then return end
    lastAnnounceAt = now

    local db = SpellReflectAnnounceDB or ns.defaults
    local message = (db.message and db.message ~= "") and db.message or ns.defaults.message
    local channel = ResolveChannel(db.channel or ns.defaults.channel)
    TrySend(message, channel)
end

-- UNIT_SPELLCAST_SUCCEEDED payload: (unitTarget, castGUID, spellID).
-- We listen on "player" only via RegisterUnitEvent so we don't even see
-- party/raid casts.
local function OnSpellcastSucceeded(_, _, spellID)
    if spellID ~= SPELL_REFLECT_ID then return end
    if not IsInsideInstance() then return end
    -- Defer one frame so we never run insecure code inside a secure spellcast
    -- dispatch chain (taint avoidance).
    RunNextFrame(Announce)
end

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellcastSucceeded(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        RunNextFrame(FlushPending)
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType, state = ...
        if Enum and Enum.AddOnRestrictionType
            and restrictionType == Enum.AddOnRestrictionType.Chat
            and state == Enum.AddOnRestrictionState.Inactive then
            RunNextFrame(FlushPending)
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
