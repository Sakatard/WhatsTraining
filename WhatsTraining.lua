local _, wt = ...

local _G = _G
local GetCoinTextureString = GetCoinTextureString
local GetMoney = GetMoney
local GetFileIDFromPath = GetFileIDFromPath
local GetSpellInfo = GetSpellInfo
local GetQuestDifficultyColor = GetQuestDifficultyColor
local IsSpellKnown = IsSpellKnown
local UnitLevel = UnitLevel
local FauxScrollFrame_Update = FauxScrollFrame_Update
local FauxScrollFrame_GetOffset = FauxScrollFrame_GetOffset
local FauxScrollFrame_OnVerticalScroll = FauxScrollFrame_OnVerticalScroll
local CreateFrame = CreateFrame
local tinsert = tinsert
local format = format
local hooksecurefunc = hooksecurefunc
local wipe = wipe
local sort = sort
local select = select
local ipairs = ipairs
local pairs = pairs
local Spell = Spell
local MAX_SKILLLINE_TABS = MAX_SKILLLINE_TABS
local GREEN_FONT_COLOR_CODE = GREEN_FONT_COLOR_CODE
local ORANGE_FONT_COLOR_CODE = ORANGE_FONT_COLOR_CODE
local RED_FONT_COLOR_CODE = RED_FONT_COLOR_CODE
local LIGHTYELLOW_FONT_COLOR_CODE = LIGHTYELLOW_FONT_COLOR_CODE
local GRAY_FONT_COLOR_CODE = GRAY_FONT_COLOR_CODE
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local HIGHLIGHT_FONT_COLOR_CODE = HIGHLIGHT_FONT_COLOR_CODE
local PARENS_TEMPLATE = PARENS_TEMPLATE

local MAX_ROWS = 22
local ROW_HEIGHT = 14
local HIGHLIGHT_TEXTURE_FILEID = GetFileIDFromPath("Interface\\AddOns\\WhatsTraining\\highlight")
local LEFT_BG_TEXTURE_FILEID = GetFileIDFromPath("Interface\\AddOns\\WhatsTraining\\left")
local RIGHT_BG_TEXTURE_FILEID = GetFileIDFromPath("Interface\\AddOns\\WhatsTraining\\right")
local TAB_TEXTURE_FILEID = GetFileIDFromPath("Interface\\Icons\\INV_Misc_QuestionMark")
local AVAILABLE_KEY = "available"
local MISSINGREQS_KEY = "missingReqs"
local NEXTLEVEL_KEY = "nextLevel"
local NOTLEVEL_KEY = "notLevel"
local IGNORED_KEY = "ignored"
local KNOWN_KEY = "known"
local COMINGSOON_FONT_COLOR_CODE = "|cff82c5ff"

local spellInfoCache = {}
-- done has param cacheHit
local function getSpellInfo(spell, level, done)
    if (spellInfoCache[spell.id] ~= nil) then
        done(true)
        return
    end
    local si = Spell:CreateFromSpellID(spell.id)
    si:ContinueOnSpellLoad(
        function()
            if (spellInfoCache[spell.id] ~= nil) then
                done(true)
                return
            end
            local subText = si:GetSpellSubtext()
            local formattedSubText = (subText and subText ~= "") and format(PARENS_TEMPLATE, subText) or ""
            spellInfoCache[spell.id] = {
                id = spell.id,
                name = si:GetSpellName(),
                subText = subText,
                formattedSubText = formattedSubText,
                icon = select(3, GetSpellInfo(spell.id)),
                cost = spell.cost,
                formattedCost = GetCoinTextureString(spell.cost),
                level = level,
                formattedLevel = format(wt.L.LEVEL_FORMAT, level)
            }
            done(false)
        end
    )
end

local function isIgnoredByCTP(spellId)
    return wt.ctpDb ~= nil and wt.ctpDb[spellId]
end

local headers = {
    {
        name = wt.L.AVAILABLE_HEADER,
        color = GREEN_FONT_COLOR_CODE,
        hideLevel = true,
        key = AVAILABLE_KEY
    },
    {
        name = wt.L.MISSINGREQS_HEADER,
        color = ORANGE_FONT_COLOR_CODE,
        hideLevel = true,
        key = MISSINGREQS_KEY
    },
    {
        name = wt.L.NEXTLEVEL_HEADER,
        color = COMINGSOON_FONT_COLOR_CODE,
        key = NEXTLEVEL_KEY
    },
    {
        name = wt.L.NOTLEVEL_HEADER,
        color = RED_FONT_COLOR_CODE,
        key = NOTLEVEL_KEY
    },
    {
        name = wt.L.IGNORED_HEADER,
        color = LIGHTYELLOW_FONT_COLOR_CODE,
        costFormat = wt.L.TOTALSAVINGS_FORMAT,
        key = IGNORED_KEY
    },
    {
        name = wt.L.KNOWN_HEADER,
        color = GRAY_FONT_COLOR_CODE,
        hideLevel = true,
        key = KNOWN_KEY
    }
}

local categories = {
    _spellsByCategoryKey = {},
    Insert = function(self, key, spellInfo)
        tinsert(self._spellsByCategoryKey[key], spellInfo)
    end,
    Initialize = function(self)
        for _, cat in ipairs(headers) do
            cat.spells = {}
            self._spellsByCategoryKey[cat.key] = cat.spells
            cat.formattedName = cat.color .. cat.name .. FONT_COLOR_CODE_CLOSE
            cat.isHeader = true
            tinsert(self, cat)
        end
    end,
    ClearSpells = function(self)
        for _, cat in ipairs(self) do
            cat.cost = 0
            wipe(cat.spells)
        end
    end
}
categories:Initialize()

local spellsAndHeaders = {}
local function rebuildSpells(playerLevel, isLevelUpEvent)
    categories:ClearSpells()
    wipe(spellsAndHeaders)
    for level, spellsAtLevel in pairs(wt.SpellsByLevel) do
        for _, spell in ipairs(spellsAtLevel) do
            local spellInfo = spellInfoCache[spell.id]
            if (spellInfo ~= nil) then
                local categoryKey
                if (IsSpellKnown(spellInfo.id)) then
                    categoryKey = KNOWN_KEY
                elseif (isIgnoredByCTP(spellInfo.id)) then
                    categoryKey = IGNORED_KEY
                elseif (level > playerLevel) then
                    categoryKey = level <= playerLevel + 2 and NEXTLEVEL_KEY or NOTLEVEL_KEY
                else
                    local hasReqs = true
                    if (spell.requiredIds ~= nil) then
                        for j = 1, #spell.requiredIds do
                            local reqId = spell.requiredIds[j]
                            hasReqs = hasReqs and IsSpellKnown(reqId)
                        end
                    end
                    categoryKey = hasReqs and AVAILABLE_KEY or MISSINGREQS_KEY
                end
                if (categoryKey ~= nil) then
                    categories:Insert(categoryKey, spellInfo)
                end
            end
        end
    end

    local function byNameAndLevel(a, b)
        if (a.level == b.level) then
            return a.name < b.name
        end
        return a.level < b.level
    end
    for _, category in ipairs(categories) do
        if (#category.spells > 0) then
            tinsert(spellsAndHeaders, category)
            sort(category.spells, byNameAndLevel)
            local totalCost = 0
            for _, s in ipairs(category.spells) do
                local effectiveLevel = s.level
                -- when a player levels up and this is triggered from that event, GetQuestDifficultyColor won't
                -- have the correct player level, it will be off by 1 for whatever reason (just like UnitLevel)
                if (isLevelUpEvent) then
                    effectiveLevel = effectiveLevel - 1
                end
                s.levelColor = GetQuestDifficultyColor(effectiveLevel)
                s.hideLevel = category.hideLevel
                totalCost = totalCost + s.cost
                tinsert(spellsAndHeaders, s)
            end
            category.cost = totalCost
        end
    end
    if (wt.MainFrame == nil) then
        return
    end
    FauxScrollFrame_Update(
        wt.MainFrame.scrollBar,
        #spellsAndHeaders,
        MAX_ROWS,
        ROW_HEIGHT,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        true
    )
end
local function rebuildIfNotCached(fromCache)
    if (fromCache or wt.MainFrame == nil) then
        return
    end
    rebuildSpells(UnitLevel("player"))
end

for level, spellsByLevel in pairs(wt.SpellsByLevel) do
    for _, spell in ipairs(spellsByLevel) do
        getSpellInfo(spell, level, rebuildIfNotCached)
    end
end
rebuildSpells(UnitLevel("player"))

local tooltip = CreateFrame("GameTooltip", "WhatsTrainingTooltip", UIParent, "GameTooltipTemplate")
function wt.SetTooltip(spellInfo)
    if (spellInfo.id) then
        tooltip:SetSpellByID(spellInfo.id)
    else
        tooltip:ClearLines()
    end
    local coloredCoinString = spellInfo.formattedCost or GetCoinTextureString(spellInfo.cost)
    if (GetMoney() < spellInfo.cost) then
        coloredCoinString = RED_FONT_COLOR_CODE .. coloredCoinString .. FONT_COLOR_CODE_CLOSE
    end
    local formatString = spellInfo.isHeader and (spellInfo.costFormat or wt.L.TOTALCOST_FORMAT) or wt.L.COST_FORMAT

    tooltip:AddLine(HIGHLIGHT_FONT_COLOR_CODE .. format(formatString, coloredCoinString) .. FONT_COLOR_CODE_CLOSE)
    tooltip:Show()
end

function wt.SetRowSpell(row, spell)
    if (spell == nil) then
        row.currentSpell = nil
        row:Hide()
        return
    elseif (spell.isHeader) then
        row.spell:Hide()
        row.header:Show()
        row.header:SetText(spell.formattedName)
        row:SetID(0)
        row.highlight:SetTexture(nil)
    elseif (spell ~= nil) then
        local rowSpell = row.spell
        row.header:Hide()
        row.isHeader = false
        row.highlight:SetTexture(HIGHLIGHT_TEXTURE_FILEID)
        rowSpell:Show()
        rowSpell.label:SetText(spell.name)
        rowSpell.subLabel:SetText(spell.formattedSubText)
        if (not spell.hideLevel) then
            rowSpell.level:Show()
            rowSpell.level:SetText(spell.formattedLevel)
            local color = spell.levelColor
            rowSpell.level:SetTextColor(color.r, color.g, color.b)
        else
            rowSpell.level:Hide()
        end
        row:SetID(spell.id)
        rowSpell.icon:SetTexture(spell.icon)
    end
    row.currentSpell = spell
    if (tooltip:IsOwned(row)) then
        wt.SetTooltip(spell)
    end
    row:Show()
end

-- When holding down left mouse on the slider knob, it will keep firing update even though
-- the offset hasn't changed so this will help throttle that
local lastOffset = -1
function wt.Update(frame, forceUpdate)
    local scrollBar = frame.scrollBar
    local offset = FauxScrollFrame_GetOffset(scrollBar)
    if (offset == lastOffset and not forceUpdate) then
        return
    end
    for i, row in ipairs(frame.rows) do
        local spellIndex = i + offset
        local spell = spellsAndHeaders[spellIndex]
        wt.SetRowSpell(row, spell)
    end
    lastOffset = offset
end

local hasFrameShown = false
function wt.CreateFrame()
    local mainFrame = CreateFrame("Frame", "WhatsTrainingFrame", SpellBookFrame)
    mainFrame:SetPoint("TOPLEFT", SpellBookFrame, "TOPLEFT", 0, 0)
    mainFrame:SetPoint("BOTTOMRIGHT", SpellBookFrame, "BOTTOMRIGHT", 0, 0)
    mainFrame:SetFrameStrata("HIGH")
    local left = mainFrame:CreateTexture(nil, "ARTWORK")
    left:SetTexture(LEFT_BG_TEXTURE_FILEID)
    left:SetWidth(256)
    left:SetHeight(512)
    left:SetPoint("TOPLEFT", mainFrame)
    local right = mainFrame:CreateTexture(nil, "ARTWORK")
    right:SetTexture(RIGHT_BG_TEXTURE_FILEID)
    right:SetWidth(128)
    right:SetHeight(512)
    right:SetPoint("TOPRIGHT", mainFrame)
    mainFrame:Hide()

    local skillLineTab = _G["SpellBookSkillLineTab" .. MAX_SKILLLINE_TABS - 1]
    hooksecurefunc(
        "SpellBookFrame_UpdateSkillLineTabs",
        function()
            skillLineTab:SetNormalTexture(TAB_TEXTURE_FILEID)
            skillLineTab.tooltip = wt.L.TAB_TEXT
            skillLineTab:Show()
            if (SpellBookFrame.selectedSkillLine == MAX_SKILLLINE_TABS - 1) then
                skillLineTab:SetChecked(true)
                mainFrame:Show()
            else
                skillLineTab:SetChecked(false)
                mainFrame:Hide()
            end
        end
    )

    local scrollBar = CreateFrame("ScrollFrame", "$parentScrollBar", mainFrame, "FauxScrollFrameTemplate")
    scrollBar:SetPoint("TOPLEFT", 0, -75)
    scrollBar:SetPoint("BOTTOMRIGHT", -65, 81)
    scrollBar:SetScript(
        "OnVerticalScroll",
        function(self, offset)
            FauxScrollFrame_OnVerticalScroll(
                self,
                offset,
                ROW_HEIGHT,
                function()
                    wt.Update(mainFrame)
                end
            )
        end
    )
    scrollBar:SetScript(
        "OnShow",
        function()
            if (not hasFrameShown) then
                rebuildSpells(UnitLevel("player"))
                hasFrameShown = true
            end
            wt.Update(mainFrame, true)
        end
    )
    mainFrame.scrollBar = scrollBar

    local rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", "$parentRow" .. i, mainFrame)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse()
        row:SetScript(
            "OnEnter",
            function(self)
                tooltip:SetOwner(self, "ANCHOR_RIGHT")
                wt.SetTooltip(self.currentSpell)
            end
        )
        row:SetScript(
            "OnLeave",
            function()
                tooltip:Hide()
            end
        )
        local highlight = row:CreateTexture("$parentHighlight", "HIGHLIGHT")
        highlight:SetAllPoints()

        local spell = CreateFrame("Frame", "$parentSpell", row)
        spell:SetPoint("LEFT", row, "LEFT")
        spell:SetPoint("TOP", row, "TOP")
        spell:SetPoint("BOTTOM", row, "BOTTOM")

        local spellIcon = spell:CreateTexture(nil, "OVERLAY")
        spellIcon:SetPoint("TOPLEFT", spell)
        spellIcon:SetPoint("BOTTOMLEFT", spell)
        local iconWidth = ROW_HEIGHT
        spellIcon:SetWidth(iconWidth)
        local spellLabel = spell:CreateFontString("$parentLabel", "OVERLAY", "GameFontNormal")
        spellLabel:SetPoint("TOPLEFT", spell, "TOPLEFT", iconWidth + 4, 0)
        spellLabel:SetPoint("BOTTOM", spell)
        spellLabel:SetJustifyV("MIDDLE")
        local spellSublabel = spell:CreateFontString("$parentSubLabel", "OVERLAY", "NewSubSpellFont")
        spellSublabel:SetPoint("TOPLEFT", spellLabel, "TOPRIGHT", 2, 0)
        spellSublabel:SetPoint("BOTTOM", spellLabel)
        spellSublabel:SetJustifyV("MIDDLE")
        local spellLevelLabel = spell:CreateFontString("$parentLevelLabel", "OVERLAY", "GameFontWhite")
        spellLevelLabel:SetPoint("TOPRIGHT", spell, -4, 0)
        spellLevelLabel:SetPoint("BOTTOMLEFT", spellSublabel, "BOTTOMRIGHT")
        spellLevelLabel:SetJustifyH("RIGHT")
        spellLevelLabel:SetJustifyV("MIDDLE")

        local headerLabel = row:CreateFontString("$parentHeaderLabel", "OVERLAY", "GameFontWhite")
        headerLabel:SetAllPoints()
        headerLabel:SetJustifyV("MIDDLE")
        headerLabel:SetJustifyH("CENTER")

        spell.label = spellLabel
        spell.subLabel = spellSublabel
        spell.icon = spellIcon
        spell.level = spellLevelLabel
        row.highlight = highlight
        row.header = headerLabel
        row.spell = spell

        if (rows[i - 1] == nil) then
            row:SetPoint("TOPLEFT", mainFrame, 26, -78)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
        end
        row:SetPoint("RIGHT", scrollBar)

        rawset(rows, i, row)
    end
    mainFrame.rows = rows
    wt.MainFrame = mainFrame
end

local function hookCTP()
    wt.ctpDb = ClassTrainerPlusDBPC
    hooksecurefunc(
        "CTP_UpdateService",
        function()
            rebuildSpells(UnitLevel("player"))
        end
    )
end

if (CTP_UpdateService) then
    hookCTP()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript(
    "OnEvent",
    function(self, event, ...)
        if (event == "ADDON_LOADED" and ... == "ClassTrainerPlus") then
            hookCTP()
            self:UnregisterEvent("ADDON_LOADED")
        elseif (event == "PLAYER_ENTERING_WORLD") then
            local isLogin, isReload = ...
            if (isLogin or isReload) then
                rebuildSpells(UnitLevel("player"))
                wt.CreateFrame()
            end
        elseif (event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_LEVEL_UP") then
            local isLevelUp = event == "PLAYER_LEVEL_UP"
            rebuildSpells(isLevelUp and ... or UnitLevel("player"), isLevelUp)
            if (wt.MainFrame and wt.MainFrame:IsVisible()) then
                wt.Update(wt.MainFrame, true)
            end
        end
    end
)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
