local damage_format = "-%d"
local heal_format = "+%d"
local maxAlpha = 0.75
local updateFrame
local feedback = {}
local originalHeight = {}
local color 
local colors = {
    STANDARD            = { 1, 1, 1 }, -- color for everything not in the list below
    -- damage colors
    IMMUNE              = { 1, 1, 1 },
    DAMAGE              = { 1, 0, 0 },
    CRUSHING            = { 1, 0, 0 },
    CRITICAL            = { 1, 0, 0 },
    GLANCING            = { 1, 0, 0 },
    ABSORB              = { 1, 1, 1 },
    BLOCK               = { 1, 1, 1 },
    RESIST              = { 1, 1, 1 },
    MISS                = { 1, 1, 1 },
    -- heal colors
    HEAL                = { 0, 1, 0 },
    CRITHEAL            = { 0, 1, 0 },
    -- energize colors
    ENERGIZE            = { 0.41, 0.8, 0.94 },
    CRITENERGIZE        = { 0.41, 0.8, 0.94 },
}

local function createUpdateFrame()
    if updateFrame then return end
    updateFrame = CreateFrame("Frame")
    updateFrame:Hide()
    updateFrame:SetScript("OnUpdate", function()
        if next(feedback) == nil then
            updateFrame:Hide()
            return
        end
        for object, startTime in pairs(feedback) do
            local maxalpha = object.CombatFeedbackText.maxAlpha
            local elapsedTime = GetTime() - startTime
            if ( elapsedTime < COMBATFEEDBACK_FADEINTIME ) then
                local alpha = maxalpha*(elapsedTime / COMBATFEEDBACK_FADEINTIME)
                object.CombatFeedbackText:SetAlpha(alpha)
                object.CombatFeedbackText:SetTextHeight(math.abs(alpha*20)+1)
            elseif ( elapsedTime < (COMBATFEEDBACK_FADEINTIME + COMBATFEEDBACK_HOLDTIME) ) then
                object.CombatFeedbackText:SetAlpha(maxalpha)
                object.CombatFeedbackText:SetTextHeight(18)
            elseif ( elapsedTime < (COMBATFEEDBACK_FADEINTIME + COMBATFEEDBACK_HOLDTIME + COMBATFEEDBACK_FADEOUTTIME) ) then
                local alpha = maxalpha - maxalpha*((elapsedTime - COMBATFEEDBACK_HOLDTIME - COMBATFEEDBACK_FADEINTIME) / COMBATFEEDBACK_FADEOUTTIME)
                object.CombatFeedbackText:SetAlpha(alpha)
                object.CombatFeedbackText:SetTextHeight(math.abs(alpha*20)+1)
            else
                object.CombatFeedbackText:Hide()
                feedback[object] = nil
            end
        end        
    end)
end


local function combat(self, event, ...)
    local FeedbackText = self.CombatFeedbackText
    local fColors = FeedbackText.colors
    local font, fontHeight, fontFlags = FeedbackText:GetFont()
    fontHeight = FeedbackText.origHeight -- always start at original height
    local text, arg
    color = fColors and fColors.STANDARD or colors.STANDARD
    
    local timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, amount, resisted, blocked, absorbed, critical, _
    timestamp, eventType = ...
    if eventType:find("SPELL") then
        timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, _, amount, _, resisted, blocked, absorbed, critical = ...
    elseif eventType:find("SWING") then
        timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, amount, _, resisted, blocked, absorbed, critical = ...
    end

    if destGUID ~= self.guid then return end

    if eventType:match("%w_DAMAGE") then
        if amount and tonumber(amount) and tonumber(amount) > 0 then
            if critical then
                color = fColors and fColors.CRITICAL or colors.CRITICAL
                fontHeight = fontHeight * 1.5
            else
                color = fColors and fColors.DAMAGE or colors.DAMAGE
            end
            text = damage_format
            arg = amount
        elseif absorbed and tonumber(absorbed) and tonumber(absorbed) > 0 then
            color = fColors and fColors.ABSORB or colors.ABSORB
            fontHeight = fontHeight * 0.75
            text = CombatFeedbackText["ABSORB"]
        elseif blocked then
            color = fColors and fColors.BLOCK or colors.BLOCK
            fontHeight = fontHeight * 0.75
            text = CombatFeedbackText["BLOCK"]
        elseif resisted then
            color = fColors and fColors.RESIST or colors.RESIST
            fontHeight = fontHeight * 0.75
            text = CombatFeedbackText["RESIST"]
        else
            color = fColors and fColors.MISS or colors.MISS
            text = CombatFeedbackText["MISS"]
        end
    elseif eventType:find("_HEAL") then
        if amount and amount > 0 then
            text = heal_format
            arg = amount
            if critical then
                color = fColors and fColors.CRITHEAL or colors.CRITHEAL
                fontHeight = fontHeight * 1.3
            else
                color = fColors and fColors.HEAL or colors.HEAL
            end
        end
    end

    if text then
        FeedbackText:SetFont(font,fontHeight,fontFlags)
        FeedbackText:SetFormattedText(text, arg or 0)
        FeedbackText:SetTextColor(unpack(color))
        FeedbackText:SetAlpha(0)
        FeedbackText:Show()
        feedback[self] = GetTime()
        updateFrame:Show() -- start our onupdate
    end
end

-- One shared COMBAT_LOG_EVENT_UNFILTERED listener dispatching by destGUID.
-- Registering every unit frame for the combat log made each event run through
-- every frame ever created (they are never destroyed between arenas).
local objectsByGUID = {}
local dispatcher = CreateFrame("Frame")
dispatcher:SetScript("OnEvent", function(_, event, ...)
    local destGUID = select(6, ...)
    local list = destGUID and objectsByGUID[destGUID]
    if not list then return end
    for object in pairs(list) do
        if object:IsVisible() then
            combat(object, event, ...)
        end
    end
end)

function addCombatFeedback(object)
    if not object.CombatFeedbackText then return end
    -- store the original starting height
    local font, fontHeight, fontFlags = object.CombatFeedbackText:GetFont()
    object.CombatFeedbackText.origHeight = fontHeight
    object.CombatFeedbackText.maxAlpha = object.CombatFeedbackText.maxAlpha or maxAlpha
    createUpdateFrame()
    if object.guid then
        objectsByGUID[object.guid] = objectsByGUID[object.guid] or {}
        objectsByGUID[object.guid][object] = true
        dispatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

function clearCombatFeedback()
    for _, list in pairs(objectsByGUID) do
        for object in pairs(list) do
            object.CombatFeedbackText:Hide()
            feedback[object] = nil
        end
    end
    wipe(objectsByGUID)
    dispatcher:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
