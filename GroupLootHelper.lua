-- Group Loot Helper Addon for World of Warcraft
-- Version: 1.0.0
-- Compatible with WoW 11.2.0

local ADDON_NAME = "GroupLootHelper"
local ADDON_PREFIX = "GLH_LOOT"

-- Initialize addon
local GroupLootHelper = CreateFrame("Frame")
GroupLootHelper:RegisterEvent("ADDON_LOADED")
GroupLootHelper:RegisterEvent("CHAT_MSG_LOOT")
GroupLootHelper:RegisterEvent("CHAT_MSG_ADDON")
GroupLootHelper:RegisterEvent("GROUP_ROSTER_UPDATE")

-- Saved variables
GroupLootHelperDB = GroupLootHelperDB or {
    interests = {},
    settings = {
        enabled = true,
        windowTimeout = 15
    }
}

-- Local variables
local activeInterestWindows = {}
local pendingInterests = {}
local isInValidInstance = false

-- Class armor and weapon compatibility tables
local CLASS_ARMOR_TYPES = {
    ["WARRIOR"] = {"Plate", "Mail", "Leather", "Cloth"},
    ["PALADIN"] = {"Plate", "Mail", "Leather", "Cloth"},
    ["HUNTER"] = {"Mail", "Leather", "Cloth"},
    ["ROGUE"] = {"Leather", "Cloth"},
    ["PRIEST"] = {"Cloth"},
    ["SHAMAN"] = {"Mail", "Leather", "Cloth"},
    ["MAGE"] = {"Cloth"},
    ["WARLOCK"] = {"Cloth"},
    ["MONK"] = {"Leather", "Cloth"},
    ["DRUID"] = {"Leather", "Cloth"},
    ["DEMONHUNTER"] = {"Leather", "Cloth"},
    ["DEATHKNIGHT"] = {"Plate", "Mail", "Leather", "Cloth"},
    ["EVOKER"] = {"Mail", "Leather", "Cloth"}
}

local CLASS_WEAPON_RESTRICTIONS = {
    ["PRIEST"] = {"Staff", "Wand", "Dagger", "Mace"},
    ["MAGE"] = {"Staff", "Wand", "Sword", "Dagger"},
    ["WARLOCK"] = {"Staff", "Wand", "Sword", "Dagger"},
    ["PALADIN"] = {"Sword", "Mace", "Axe", "Polearm", "Shield"},
    ["HUNTER"] = {"Bow", "Crossbow", "Gun", "Polearm", "Staff", "Sword", "Axe", "Dagger", "Fist Weapon"},
    -- Add more as needed, jewelry is always allowed
}

-- Utility functions
local function IsInValidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

local function IsInGroup()
    return IsInGroup() or IsInRaid()
end

local function CanUseItem(itemLink)
    if not itemLink then return false end
    
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return false end
    
    local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subClassID = GetItemInfo(itemLink)
    if not equipLoc then return false end
    
    -- Jewelry is always usable
    if equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then
        return true
    end
    
    local playerClass = select(2, UnitClass("player"))
    
    -- Check armor type
    if classID == 4 then -- Armor
        local armorType = select(7, GetItemInfo(itemLink))
        local allowedArmor = CLASS_ARMOR_TYPES[playerClass]
        if allowedArmor then
            for _, armor in ipairs(allowedArmor) do
                if armorType == armor then
                    return true
                end
            end
        end
        return false
    end
    
    -- Check weapon type (simplified - WoW handles most restrictions automatically)
    if classID == 2 then -- Weapons
        -- For now, let WoW's built-in restrictions handle this
        -- This could be expanded with more detailed checks if needed
        return true
    end
    
    return true
end

local function IsItemTradeable(itemLink)
    if not itemLink then return false end
    
    -- Create a temporary tooltip to check for soulbound status
    local tooltip = CreateFrame("GameTooltip", "GLHTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(itemLink)
    
    -- Check tooltip text for binding status
    for i = 1, tooltip:NumLines() do
        local line = _G["GLHTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and (string.find(text, "Soulbound") or string.find(text, "Seelengeb") or 
                        string.find(text, "Binds when picked up") or string.find(text, "Wird beim Aufheben gebunden")) then
                tooltip:Hide()
                return false
            end
        end
    end
    
    tooltip:Hide()
    return true
end

-- Communication functions
local function SendAddonMessage(message, distribution)
    if not IsInGroup() then return end
    
    local channel = IsInRaid() and "RAID" or "PARTY"
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel)
end

local function BroadcastLootDrop(itemLink)
    if not itemLink or not IsInValidInstance() or not IsInGroup() then return end
    
    local message = "LOOT:" .. itemLink
    SendAddonMessage(message, "GROUP")
    
    print("|cff00ff00[Group Loot Helper]|r Announced loot: " .. itemLink)
end

local function SendInterest(itemLink, senderName)
    if not itemLink or not senderName then return end
    
    local message = "INTEREST:" .. itemLink .. ":" .. UnitName("player")
    SendAddonMessage(message, "GROUP")
end

-- UI Functions
local function CreateInterestWindow(itemLink, senderName)
    if activeInterestWindows[itemLink] then
        activeInterestWindows[itemLink]:Hide()
    end
    
    local frame = CreateFrame("Frame", "GLH_InterestWindow_" .. GetTime(), UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(250, 100)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    
    -- Position at cursor
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -8)
    frame.title:SetText("Loot Interest")
    
    -- Item link
    frame.itemButton = CreateFrame("Button", nil, frame)
    frame.itemButton:SetSize(200, 20)
    frame.itemButton:SetPoint("TOP", frame.title, "BOTTOM", 0, -10)
    
    local itemName, itemLink2, itemRarity = GetItemInfo(itemLink)
    if itemName then
        local r, g, b = GetItemQualityColor(itemRarity)
        frame.itemButton:SetText(itemName)
        frame.itemButton:GetFontString():SetTextColor(r, g, b)
    end
    
    -- Tooltip on hover
    frame.itemButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)
    frame.itemButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Interest button (green checkmark)
    frame.interestButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.interestButton:SetSize(60, 25)
    frame.interestButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 15)
    frame.interestButton:SetText("✓ Yes")
    frame.interestButton:SetScript("OnClick", function()
        SendInterest(itemLink, senderName)
        frame:Hide()
        activeInterestWindows[itemLink] = nil
        print("|cff00ff00[Group Loot Helper]|r Interest sent for: " .. itemLink)
    end)
    
    -- Decline button (red X)
    frame.declineButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.declineButton:SetSize(60, 25)
    frame.declineButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 15)
    frame.declineButton:SetText("✗ No")
    frame.declineButton:SetScript("OnClick", function()
        frame:Hide()
        activeInterestWindows[itemLink] = nil
    end)
    
    -- Auto-close timer
    C_Timer.After(GroupLootHelperDB.settings.windowTimeout, function()
        if frame and frame:IsShown() then
            frame:Hide()
            activeInterestWindows[itemLink] = nil
        end
    end)
    
    activeInterestWindows[itemLink] = frame
    frame:Show()
end

local function CreateInterestListGUI()
    if GroupLootHelper.interestFrame and GroupLootHelper.interestFrame:IsShown() then
        GroupLootHelper.interestFrame:Hide()
        return
    end
    
    local frame = CreateFrame("Frame", "GLH_InterestListFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 300)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -8)
    frame.title:SetText("Loot Interest Overview")
    
    -- Scroll frame for interests
    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)
    
    frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.scrollChild:SetSize(350, 1)
    frame.scrollFrame:SetScrollChild(frame.scrollChild)
    
    -- Close button
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(80, 25)
    frame.closeButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    frame.closeButton:SetText("Close")
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    GroupLootHelper.interestFrame = frame
    
    -- Update the list
    GroupLootHelper:UpdateInterestList()
    
    frame:Show()
end

function GroupLootHelper:UpdateInterestList()
    if not self.interestFrame or not self.interestFrame:IsShown() then return end
    
    -- Clear existing entries
    local scrollChild = self.interestFrame.scrollChild
    for i = 1, scrollChild:GetNumChildren() do
        local child = select(i, scrollChild:GetChildren())
        child:Hide()
    end
    
    local yOffset = -10
    local entryHeight = 25
    
    for itemLink, interests in pairs(pendingInterests) do
        for _, playerName in ipairs(interests) do
            local entry = CreateFrame("Frame", nil, scrollChild)
            entry:SetSize(340, entryHeight)
            entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
            
            local itemName = GetItemInfo(itemLink) or "Unknown Item"
            local text = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", entry, "LEFT", 5, 0)
            text:SetText(playerName .. " wants: " .. itemName)
            
            yOffset = yOffset - entryHeight
        end
    end
    
    scrollChild:SetHeight(math.abs(yOffset))
end

-- Event handlers
local function OnAddonLoaded(self, event, addonName)
    if addonName ~= ADDON_NAME then return end
    
    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    
    -- Check initial instance status
    isInValidInstance = IsInValidInstance()
    
    print("|cff00ff00[Group Loot Helper]|r Loaded successfully!")
end

local function OnChatMsgLoot(self, event, message)
    if not isInValidInstance or not IsInGroup() then return end
    
    -- Parse loot message to extract item link
    -- Format: "Player receives loot: [Item Link]"
    local playerName, itemLink = string.match(message, "(.+) receives loot: (.+)")
    if not playerName or not itemLink then
        -- Try German format
        playerName, itemLink = string.match(message, "(.+) erhält Beute: (.+)")
    end
    
    if playerName and itemLink and playerName == UnitName("player") then
        -- This player received loot
        if IsItemTradeable(itemLink) then
            BroadcastLootDrop(itemLink)
        end
    end
end

local function OnChatMsgAddon(self, event, prefix, message, distribution, sender)
    if prefix ~= ADDON_PREFIX then return end
    if sender == UnitName("player") then return end -- Ignore own messages
    
    local command, data = string.match(message, "([^:]+):(.+)")
    if not command then return end
    
    if command == "LOOT" then
        local itemLink = data
        if IsItemTradeable(itemLink) and CanUseItem(itemLink) then
            CreateInterestWindow(itemLink, sender)
        end
    elseif command == "INTEREST" then
        local itemLink, playerName = string.match(data, "([^:]+):(.+)")
        if itemLink and playerName then
            if not pendingInterests[itemLink] then
                pendingInterests[itemLink] = {}
            end
            table.insert(pendingInterests[itemLink], playerName)
            
            print("|cff00ff00[Group Loot Helper]|r " .. playerName .. " is interested in: " .. itemLink)
            
            -- Update GUI if open
            GroupLootHelper:UpdateInterestList()
        end
    end
end

local function OnGroupRosterUpdate(self, event)
    isInValidInstance = IsInValidInstance()
end

-- Set event handlers
GroupLootHelper:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(self, event, ...)
    elseif event == "CHAT_MSG_LOOT" then
        OnChatMsgLoot(self, event, ...)
    elseif event == "CHAT_MSG_ADDON" then
        OnChatMsgAddon(self, event, ...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        OnGroupRosterUpdate(self, event, ...)
    end
end)

-- Slash commands
SLASH_SENDLOOT1 = "/sendloot"
SlashCmdList["SENDLOOT"] = function(msg)
    local itemID = tonumber(msg)
    if not itemID then
        print("|cffff0000[Group Loot Helper]|r Usage: /sendloot [itemID]")
        return
    end
    
    local itemLink = select(2, GetItemInfo(itemID))
    if not itemLink then
        print("|cffff0000[Group Loot Helper]|r Invalid item ID: " .. itemID)
        return
    end
    
    BroadcastLootDrop(itemLink)
end

SLASH_GLHINTEREST1 = "/glhinterest"
SlashCmdList["GLHINTEREST"] = function(msg)
    CreateInterestListGUI()
end

SLASH_GLH1 = "/glh"
SlashCmdList["GLH"] = function(msg)
    if msg == "interests" or msg == "" then
        CreateInterestListGUI()
    elseif msg == "clear" then
        pendingInterests = {}
        print("|cff00ff00[Group Loot Helper]|r Interest list cleared.")
        GroupLootHelper:UpdateInterestList()
    else
        print("|cff00ff00[Group Loot Helper]|r Commands:")
        print("  /glh or /glh interests - Show interest overview")
        print("  /glh clear - Clear interest list")
        print("  /sendloot [itemID] - Test loot announcement")
    end
end