-------------------------------------------------------------------------
-- Replay timeline: play/pause, skip and a draggable seek bar.         --
-- Server -> addon: CHAT_MSG_ADDON "ACREPLAY" (WHISPER)                --
--   STATE;at=<ms>;len=<ms>;paused=<0/1>;  and  END;                   --
-- Addon -> server: .replay pause/resume/seek <sec>/state              --
-------------------------------------------------------------------------

local SKIP_SECONDS = 10
local WIDTH = 520

local state = { at = 0, len = 0, paused = false, dragging = false }

local function FormatTime(ms)
    local s = math.floor(math.max(ms, 0) / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function SendReplay(cmd)
    SendChatMessage(".replay " .. cmd, "SAY")
end

-- Parented to WorldFrame so it stays visible while the spectator UI hides UIParent. At the top, under the arena
-- timer: the bottom of the screen belongs to the spectator's big player frames and cast bars.
local bar = CreateFrame("Frame", "ArenacraftReplayBar", WorldFrame)
bar:SetWidth(WIDTH)
bar:SetHeight(46)
bar:SetPoint("TOP", WorldFrame, "TOP", 0, -110)
bar:SetFrameStrata("HIGH")
bar:EnableMouse(true)
bar:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 2, edgeSize = 2,
})
bar:SetBackdropColor(0, 0, 0, 0.7)
bar:SetBackdropBorderColor(0.6, 0.6, 0.2, 0.9)
bar:Hide()

local function MakeButton(label, width)
    local b = CreateFrame("Button", nil, bar)
    b:SetWidth(width)
    b:SetHeight(20)
    b.texture = b:CreateTexture(nil, "BACKGROUND")
    b.texture:SetAllPoints(b)
    b.texture:SetTexture(0.6, 0.6, 0.2, 0.9)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    return b
end

local back = MakeButton("-" .. SKIP_SECONDS .. "s", 44)
back:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)

local play = MakeButton("Pause", 60)
play:SetPoint("LEFT", back, "RIGHT", 4, 0)

local forward = MakeButton("+" .. SKIP_SECONDS .. "s", 44)
forward:SetPoint("LEFT", play, "RIGHT", 4, 0)

local timeText = bar:CreateFontString(nil, "OVERLAY")
timeText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
timeText:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -8, 7)
timeText:SetText("0:00 / 0:00")

local slider = CreateFrame("Slider", "ArenacraftReplaySlider", bar)
slider:SetOrientation("HORIZONTAL")
slider:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -5)
slider:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -5)
slider:SetHeight(14)
slider:SetMinMaxValues(0, 1)
slider:SetValue(0)
slider:SetValueStep(1)
slider:EnableMouse(true)

slider.track = slider:CreateTexture(nil, "BACKGROUND")
slider.track:SetPoint("LEFT", 0, 0)
slider.track:SetPoint("RIGHT", 0, 0)
slider.track:SetHeight(6)
slider.track:SetTexture(0.25, 0.25, 0.25, 1)

slider.fill = slider:CreateTexture(nil, "ARTWORK")
slider.fill:SetPoint("LEFT", slider.track, "LEFT", 0, 0)
slider.fill:SetHeight(6)
slider.fill:SetTexture(0.8, 0.8, 0.3, 1)

local thumb = slider:CreateTexture(nil, "OVERLAY")
thumb:SetWidth(8)
thumb:SetHeight(14)
thumb:SetTexture(1, 1, 1, 1)
slider:SetThumbTexture(thumb)

-- Hover tooltip: the time the cursor points at.
local hoverText = slider:CreateFontString(nil, "OVERLAY")
hoverText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
hoverText:Hide()

local function Refresh()
    local len = math.max(state.len, 1)
    local at = math.min(math.max(state.at, 0), len)
    if not state.dragging then
        slider:SetMinMaxValues(0, len / 1000)
        slider:SetValue(at / 1000)
    end
    local shown = state.dragging and slider:GetValue() * 1000 or at
    slider.fill:SetWidth(math.max(1, slider.track:GetWidth() * shown / len))
    timeText:SetText(FormatTime(shown) .. " / " .. FormatTime(state.len))
    play.text:SetText(state.paused and "Play" or "Pause")
end

local function CursorSeconds()
    local left, width = slider:GetLeft(), slider:GetWidth()
    if not left or width <= 0 then return 0 end
    local x = GetCursorPosition() / slider:GetEffectiveScale()
    local frac = math.min(math.max((x - left) / width, 0), 1)
    return frac * state.len / 1000
end

slider:SetScript("OnMouseDown", function(self)
    state.dragging = true
    self:SetValue(CursorSeconds())
    Refresh()
end)

slider:SetScript("OnValueChanged", function()
    if state.dragging then Refresh() end
end)

slider:SetScript("OnMouseUp", function(self)
    if not state.dragging then return end
    state.dragging = false
    local target = math.floor(self:GetValue())
    state.at = target * 1000
    Refresh()
    SendReplay("seek " .. target)
end)

slider:SetScript("OnEnter", function(self) hoverText:Show() end)
slider:SetScript("OnLeave", function(self) hoverText:Hide() end)

back:SetScript("OnClick", function()
    state.at = math.max(state.at - SKIP_SECONDS * 1000, 0)
    Refresh()
    SendReplay("seek -" .. SKIP_SECONDS)
end)

forward:SetScript("OnClick", function()
    state.at = math.min(state.at + SKIP_SECONDS * 1000, state.len)
    Refresh()
    SendReplay("seek +" .. SKIP_SECONDS)
end)

play:SetScript("OnClick", function()
    state.paused = not state.paused
    Refresh()
    SendReplay(state.paused and "pause" or "resume")
end)

-- Between STATE messages (about once a second) advance the position locally.
bar:SetScript("OnUpdate", function(self, elapsed)
    if not state.paused and not state.dragging and state.at < state.len then
        state.at = state.at + elapsed * 1000
    end
    if hoverText:IsShown() then
        local sec = CursorSeconds()
        hoverText:ClearAllPoints()
        hoverText:SetPoint("BOTTOM", slider, "BOTTOMLEFT", slider:GetWidth() * sec * 1000 / math.max(state.len, 1), 14)
        hoverText:SetText(FormatTime(sec * 1000))
    end
    Refresh()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, prefix, body, channel)
    if event == "PLAYER_ENTERING_WORLD" then
        -- The server announces a running replay itself; hide until it does.
        bar:Hide()
        return
    end
    if prefix ~= "ACREPLAY" or channel ~= "WHISPER" or not body then return end

    if body:find("^STATE;") then
        local at = tonumber(body:match("at=(%d+)"))
        local len = tonumber(body:match("len=(%d+)"))
        if at and len then
            state.at = at
            state.len = len
            state.paused = body:match("paused=(%d)") == "1"
            bar:Show()
            Refresh()
        end
    elseif body:find("^END;") then
        state.dragging = false
        bar:Hide()
    end
end)

SLASH_ACREPLAY1 = "/replaybar"
SlashCmdList.ACREPLAY = function()
    SendReplay("state")
end
