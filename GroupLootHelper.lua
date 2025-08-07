-- Group Loot Helper Addon for World of Warcraft
-- Version: 1.1.0
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
        windowTimeout = 15,
        enableOpenWorld = true,
        minItemLevel = 620,
        instanceOnly = false
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
    
    -- If instance only mode is enabled, require being in a dungeon/raid
    if GroupLootHelperDB.settings.instanceOnly then
        return inInstance and (instanceType == "party" or instanceType == "raid")
    end
    
    -- If open world is enabled, allow both instances and open world
    if GroupLootHelperDB.settings.enableOpenWorld then
        return true -- Always valid if open world is enabled
    end
    
    -- Default behavior: only dungeons/raids
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

local function MeetsItemLevelRequirement(itemLink)
    if not itemLink then return false end
    
    local itemLevel = GetDetailedItemLevelInfo(itemLink)
    if not itemLevel then
        -- Fallback: try to get item level from item info
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, itemLevelFromInfo = GetItemInfo(itemLink)
        itemLevel = itemLevelFromInfo
    end
    
    if not itemLevel or itemLevel == 0 then
        return true -- If we can't determine item level, allow it
    end
    
    return itemLevel >= GroupLootHelperDB.settings.minItemLevel
end

-- Communication functions
local function SendAddonMessage(message, distribution)
    if not IsInGroup() then return end
    
    local channel = IsInRaid() and "RAID" or "PARTY"
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel)
end

local function BroadcastLootDrop(itemLink)
    if not itemLink or not IsInValidInstance() or not IsInGroup() then return end
    
    -- Check if item meets item level requirement
    if not MeetsItemLevelRequirement(itemLink) then
        local itemLevel = GetDetailedItemLevelInfo(itemLink) or 0
        print("|cffff9900[Group Loot Helper]|r Item level " .. itemLevel .. " below threshold (" .. GroupLootHelperDB.settings.minItemLevel .. "): " .. itemLink)
        return
    end
    
    local message = "LOOT:" .. itemLink
    SendAddonMessage(message, "GROUP")
    
    local itemLevel = GetDetailedItemLevelInfo(itemLink) or "?"
    print("|cff00ff00[Group Loot Helper]|r Announced loot (iLvl " .. itemLevel .. "): " .. itemLink)
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

local function CreateSettingsGUI()
    if GroupLootHelper.settingsFrame and GroupLootHelper.settingsFrame:IsShown() then
        GroupLootHelper.settingsFrame:Hide()
        return
    end
    
    local frame = CreateFrame("Frame", "GLH_SettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(350, 250)
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
    frame.title:SetText("Group Loot Helper Settings")
    
    -- Enable Open World checkbox
    frame.openWorldCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.openWorldCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)
    frame.openWorldCheck:SetChecked(GroupLootHelperDB.settings.enableOpenWorld)
    frame.openWorldCheck.text = frame.openWorldCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.openWorldCheck.text:SetPoint("LEFT", frame.openWorldCheck, "RIGHT", 5, 0)
    frame.openWorldCheck.text:SetText("Enable in Open World")
    
    -- Instance Only checkbox
    frame.instanceOnlyCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.instanceOnlyCheck:SetPoint("TOPLEFT", frame.openWorldCheck, "BOTTOMLEFT", 0, -10)
    frame.instanceOnlyCheck:SetChecked(GroupLootHelperDB.settings.instanceOnly)
    frame.instanceOnlyCheck.text = frame.instanceOnlyCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.instanceOnlyCheck.text:SetPoint("LEFT", frame.instanceOnlyCheck, "RIGHT", 5, 0)
    frame.instanceOnlyCheck.text:SetText("Instance Only Mode")
    
    -- Min Item Level setting
    frame.itemLevelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.itemLevelLabel:SetPoint("TOPLEFT", frame.instanceOnlyCheck, "BOTTOMLEFT", 5, -20)
    frame.itemLevelLabel:SetText("Minimum Item Level:")
    
    frame.itemLevelEditBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.itemLevelEditBox:SetSize(80, 25)
    frame.itemLevelEditBox:SetPoint("LEFT", frame.itemLevelLabel, "RIGHT", 10, 0)
    frame.itemLevelEditBox:SetText(tostring(GroupLootHelperDB.settings.minItemLevel))
    frame.itemLevelEditBox:SetAutoFocus(false)
    
    -- Window Timeout setting
    frame.timeoutLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.timeoutLabel:SetPoint("TOPLEFT", frame.itemLevelLabel, "BOTTOMLEFT", 0, -30)
    frame.timeoutLabel:SetText("Window Timeout (seconds):")
    
    frame.timeoutEditBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.timeoutEditBox:SetSize(80, 25)
    frame.timeoutEditBox:SetPoint("LEFT", frame.timeoutLabel, "RIGHT", 10, 0)
    frame.timeoutEditBox:SetText(tostring(GroupLootHelperDB.settings.windowTimeout))
    frame.timeoutEditBox:SetAutoFocus(false)
    
    -- Save button
    frame.saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.saveButton:SetSize(80, 25)
    frame.saveButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 15)
    frame.saveButton:SetText("Save")
    frame.saveButton:SetScript("OnClick", function()
        -- Save settings
        GroupLootHelperDB.settings.enableOpenWorld = frame.openWorldCheck:GetChecked()
        GroupLootHelperDB.settings.instanceOnly = frame.instanceOnlyCheck:GetChecked()
        
        local itemLevel = tonumber(frame.itemLevelEditBox:GetText())
        if itemLevel and itemLevel >= 0 then
            GroupLootHelperDB.settings.minItemLevel = itemLevel
        end
        
        local timeout = tonumber(frame.timeoutEditBox:GetText())
        if timeout and timeout > 0 then
            GroupLootHelperDB.settings.windowTimeout = timeout
        end
        
        print("|cff00ff00[Group Loot Helper]|r Settings saved!")
        frame:Hide()
    end)
    
    -- Cancel button
    frame.cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.cancelButton:SetSize(80, 25)
    frame.cancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 15)
    frame.cancelButton:SetText("Cancel")
    frame.cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    GroupLootHelper.settingsFrame = frame
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
        if IsItemTradeable(itemLink) and CanUseItem(itemLink) and MeetsItemLevelRequirement(itemLink) then
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
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    
    local command = args[1] or ""
    
    if command == "interests" or command == "" then
        CreateInterestListGUI()
    elseif command == "clear" then
        pendingInterests = {}
        print("|cff00ff00[Group Loot Helper]|r Interest list cleared.")
        GroupLootHelper:UpdateInterestList()
    elseif command == "settings" or command == "config" then
        CreateSettingsGUI()
    elseif command == "itemlevel" or command == "ilvl" then
        local level = tonumber(args[2])
        if level and level >= 0 then
            GroupLootHelperDB.settings.minItemLevel = level
            print("|cff00ff00[Group Loot Helper]|r Minimum item level set to: " .. level)
        else
            print("|cff00ff00[Group Loot Helper]|r Current minimum item level: " .. GroupLootHelperDB.settings.minItemLevel)
            print("Usage: /glh itemlevel [number]")
        end
    elseif command == "openworld" then
        GroupLootHelperDB.settings.enableOpenWorld = not GroupLootHelperDB.settings.enableOpenWorld
        local status = GroupLootHelperDB.settings.enableOpenWorld and "enabled" or "disabled"
        print("|cff00ff00[Group Loot Helper]|r Open world mode " .. status)
    elseif command == "instanceonly" then
        GroupLootHelperDB.settings.instanceOnly = not GroupLootHelperDB.settings.instanceOnly
        local status = GroupLootHelperDB.settings.instanceOnly and "enabled" or "disabled"
        print("|cff00ff00[Group Loot Helper]|r Instance only mode " .. status)
    elseif command == "status" then
        print("|cff00ff00[Group Loot Helper]|r Current Settings:")
        print("  Minimum Item Level: " .. GroupLootHelperDB.settings.minItemLevel)
        print("  Open World: " .. (GroupLootHelperDB.settings.enableOpenWorld and "Enabled" or "Disabled"))
        print("  Instance Only: " .. (GroupLootHelperDB.settings.instanceOnly and "Enabled" or "Disabled"))
        print("  Window Timeout: " .. GroupLootHelperDB.settings.windowTimeout .. " seconds")
        local inInstance, instanceType = IsInInstance()
        print("  Current Location: " .. (inInstance and instanceType or "Open World"))
        print("  Valid for Loot: " .. (IsInValidInstance() and "Yes" or "No"))
    else
        print("|cff00ff00[Group Loot Helper]|r Commands:")
        print("  /glh or /glh interests - Show interest overview")
        print("  /glh settings - Open settings GUI")
        print("  /glh clear - Clear interest list")
        print("  /glh itemlevel [number] - Set/show minimum item level")
        print("  /glh openworld - Toggle open world mode")
        print("  /glh instanceonly - Toggle instance only mode")
        print("  /glh status - Show current settings and status")
        print("  /sendloot [itemID] - Test loot announcement")
    end
end