-- SpellReflectAnnounceOptions
-- Builds an Interface Options canvas panel with:
--   * a dropdown to pick the chat channel
--   * an edit box to customise the announcement message
-- Also registers a /sra slash command to open the panel.

local addonName, ns = ...

-- Defensive: options file can load before ADDON_LOADED fires for the main
-- file in some edge cases. Make sure the saved table exists before any
-- control reads from it.
SpellReflectAnnounceDB = SpellReflectAnnounceDB or {}
for k, v in pairs(ns.defaults) do
    if SpellReflectAnnounceDB[k] == nil then
        SpellReflectAnnounceDB[k] = v
    end
end

local CHANNELS = {
    { value = "SAY",           label = "Say"      },
    { value = "YELL",          label = "Yell"     },
    { value = "PARTY",         label = "Party"    },
    { value = "RAID",          label = "Raid"     },
    { value = "INSTANCE_CHAT", label = "Instance" },
}

local function GetChannelLabel(value)
    for _, entry in ipairs(CHANNELS) do
        if entry.value == value then return entry.label end
    end
    return value
end

local panel = CreateFrame("Frame", "SpellReflectAnnounceOptionsPanel", UIParent)
panel:Hide()

-- Title
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Spell Reflect Announce")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(520)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Announces in chat when Spell Reflection (spell ID 23920) is active on you.")

-- Channel dropdown
local channelLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
channelLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -24)
channelLabel:SetText("Chat channel")

local channelDropdown = CreateFrame("DropdownButton", "SpellReflectAnnounceChannelDropdown", panel, "WowStyle1DropdownTemplate")
channelDropdown:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -6)
channelDropdown:SetWidth(200)

local function IsSelected(value)
    return (SpellReflectAnnounceDB and SpellReflectAnnounceDB.channel) == value
end

local function SetSelected(value)
    SpellReflectAnnounceDB.channel = value
end

channelDropdown:SetupMenu(function(_, rootDescription)
    for _, entry in ipairs(CHANNELS) do
        rootDescription:CreateRadio(entry.label, IsSelected, SetSelected, entry.value)
    end
end)

-- Message edit box
local messageLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
messageLabel:SetPoint("TOPLEFT", channelDropdown, "BOTTOMLEFT", 0, -20)
messageLabel:SetText("Announcement message")

local messageBox = CreateFrame("EditBox", "SpellReflectAnnounceMessageBox", panel, "InputBoxTemplate")
messageBox:SetPoint("TOPLEFT", messageLabel, "BOTTOMLEFT", 6, -8)
messageBox:SetSize(360, 24)
messageBox:SetAutoFocus(false)
messageBox:SetMaxLetters(255)

messageBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
messageBox:SetScript("OnEscapePressed", function(self)
    self:SetText(SpellReflectAnnounceDB and SpellReflectAnnounceDB.message or ns.defaults.message)
    self:ClearFocus()
end)
messageBox:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText()
    if not text or text == "" then
        text = ns.defaults.message
        self:SetText(text)
    end
    SpellReflectAnnounceDB.message = text
end)

-- Reset-to-default button
local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetButton:SetPoint("TOPLEFT", messageBox, "BOTTOMLEFT", -6, -16)
resetButton:SetSize(140, 22)
resetButton:SetText("Reset to defaults")
resetButton:SetScript("OnClick", function()
    SpellReflectAnnounceDB.message = ns.defaults.message
    SpellReflectAnnounceDB.channel = ns.defaults.channel
    messageBox:SetText(SpellReflectAnnounceDB.message)
    channelDropdown:GenerateMenu() -- refresh radio selection
end)

-- Refresh on show (keeps controls in sync if user edited the saved variables
-- from another source).
panel:SetScript("OnShow", function()
    SpellReflectAnnounceDB = SpellReflectAnnounceDB or {}
    for k, v in pairs(ns.defaults) do
        if SpellReflectAnnounceDB[k] == nil then
            SpellReflectAnnounceDB[k] = v
        end
    end
    messageBox:SetText(SpellReflectAnnounceDB.message)
    channelDropdown:GenerateMenu()
end)

-- Register with the modern Settings system as a canvas category.
local category = Settings.RegisterCanvasLayoutCategory(panel, "Spell Reflect Announce")
category.ID = "SpellReflectAnnounce"
Settings.RegisterAddOnCategory(category)

ns.settingsCategoryID = category:GetID()

-- /sra slash command -> open the panel, or "/sra debug" to toggle debug logging.
SLASH_SPELLREFLECTANNOUNCE1 = "/sra"
SLASH_SPELLREFLECTANNOUNCE2 = "/spellreflectannounce"
SlashCmdList["SPELLREFLECTANNOUNCE"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "debug" then
        SpellReflectAnnounceDB.debug = not SpellReflectAnnounceDB.debug
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSRA|r debug = " .. tostring(SpellReflectAnnounceDB.debug))
        return
    end
    if msg == "test" then
        -- Simulate an announce path so we can verify chat sending works
        -- without needing to actually cast Spell Reflection.
        if ns.Debug then ns.Debug("Manual /sra test invoked") end
        local fakeAura = { auraInstanceID = -GetTime(), spellId = 23920, name = "Spell Reflection" }
        if ns.Announce then ns.Announce(fakeAura) end
        return
    end
    Settings.OpenToCategory(ns.settingsCategoryID)
end
