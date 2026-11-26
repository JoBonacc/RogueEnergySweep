-- Rogue Energy Sweep 0.7.0 (WoW Forever)
-- Action discovery and energy curve approach adapted from Rogue Energy Need 0.2.1
-- by Vryllak / Rogue Energy Need contributors (MIT; see LICENSE).
local ADDON_NAME = ...
local _, playerClass = UnitClass("player")
if playerClass ~= "ROGUE" then return end
local ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
local DB
local overlays, records, knownButtons, groups = {}, {}, {}, {}
local lastMaxEnergy = 100
local updatePending, rescanPending, rescanScheduled, costPending, bindingPending = false, false, false, false, false
local progressGeneration = 0
local demo = false
local demoGeneration = 0
local lastSource, lastError = "not evaluated", "none"
local refreshLiveStatus
local function Say(message) print("|cffffcc66Energy Sweep:|r " .. message) end
local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    if value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local MODES = {bar=true, rising=true, perimeter=true, radial=true, auto=true}
local COLORS = {amber={1,0.78,0.16}, white={1,1,1}, cyan={0.22,0.85,1}, green={0.3,1,0.35}, black={0,0,0}}
local function InitDB()
    if type(RogueEnergySweepDB) ~= "table" then RogueEnergySweepDB = {} end
    DB = RogueEnergySweepDB
    if type(DB.enabled) ~= "boolean" then DB.enabled = true end
    DB.combatOnly = DB.combatOnly == true
    if not MODES[DB.mode] or DB.mode == "auto" then DB.mode = "rising" end
    if not COLORS[DB.color] then DB.color = "amber" end
    DB.thickness = math.floor(math.max(2, math.min(8, SafeNumber(DB.thickness) or 4))+0.5)
    DB.tint = DB.tint ~= false
    if DB.progress ~= "countdown" then DB.progress = "energy" end
    DB.opacity = math.max(0.15, math.min(1.00, SafeNumber(DB.opacity) or 0.90))
end

local function RefreshMaxEnergy()
    if type(UnitPowerMax) ~= "function" then return end
    local ok, result = pcall(UnitPowerMax, "player", ENERGY)
    local value = ok and SafeNumber(result) or nil
    if value and value > 0 then lastMaxEnergy = value end
end

-- x = energy / maximum energy; y = fraction of ability cost still missing.
-- The native evaluator can consume a secret resource and return a secret result.
local function MakeCurve(cost, kind)
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil end
    local ok, curve = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
            c:SetType(Enum.LuaCurveType.Linear)
        end
        local threshold = math.min(1, cost / lastMaxEnergy)
        if kind == "visibility" then
            if cost > lastMaxEnergy then c:AddPoint(0, 1); c:AddPoint(1, 1)
            else
                c:AddPoint(0, 1)
                local edge = math.max(0, threshold - 0.5 / lastMaxEnergy)
                if edge > 0 then c:AddPoint(edge, 1) end
                c:AddPoint(threshold, 0)
                if threshold < 1 then c:AddPoint(1, 0) end
            end
        elseif kind == "startFill" or kind == "startDeficit" then
            -- Clamp the snapshot just below readiness to keep the native range nonzero.
            local fill = kind == "startFill"
            local edge = math.min(1, cost / lastMaxEnergy * 0.999)
            local ratio = math.min(0.999, edge * lastMaxEnergy / cost)
            c:AddPoint(0, fill and 0 or 1)
            c:AddPoint(edge, fill and ratio or 1-ratio)
            if edge < 1 then c:AddPoint(1, fill and ratio or 1-ratio) end
        else
            local fill = kind == "fill"
            c:AddPoint(0, fill and 0 or 1)
            local ratio = math.min(1, lastMaxEnergy / cost)
            c:AddPoint(threshold, fill and ratio or 1-ratio)
            if threshold < 1 then c:AddPoint(1, fill and 1 or 0) end
        end
        return c
    end)
    return ok and curve or nil
end

local function GetButtonSlot(button)
    if not button then
        return nil
    end

    local slot = SafeNumber(button.action)
    if slot and slot > 0 then
        return slot
    end

    slot = SafeNumber(button._state_action)
    if slot and slot > 0 then
        return slot
    end

    -- Reading a secure attribute is safe; never write secure button state.
    if button.GetAttribute then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok then
            value = SafeNumber(value)
            if value and value > 0 then
                return value
            end
        end
    end

    return nil
end

local function GetSpellFromSlot(slot)
    if not slot or not C_ActionBar or not C_ActionBar.GetSpell then
        return nil
    end

    local ok, spellID = pcall(C_ActionBar.GetSpell, slot)
    if not ok then
        return nil
    end

    spellID = SafeNumber(spellID)
    if spellID and spellID > 0 then
        return spellID
    end

    return nil
end

local function GetEnergyCost(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then
        return nil, false
    end

    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or IsSecret(costs) or type(costs) ~= "table" then
        return nil, false
    end

    for i = 1, #costs do
        local row = costs[i]
        if not IsSecret(row) and type(row) == "table" then
            local powerType = SafeNumber(row.type)
            local isEnergy = powerType == ENERGY or (not IsSecret(row.name) and row.name == "ENERGY")

            if isEnergy then
                local cost = SafeNumber(row.minCost)
                if cost == nil then
                    cost = SafeNumber(row.cost)
                end
                -- Unknown/restricted costs are not free abilities.
                if cost == nil then return nil, false end
                return cost, true, true
            end
        end
    end

    return nil, false, true -- readable list with no energy cost
end

local function Clear(record)
    record.radial:Hide()
    record.bar:Hide()
    record.rising:Hide()
    if record.line then record.line:Hide() end
    record.riseTint:Hide()
    for _, edge in ipairs(record.edges) do edge:Hide() end
    record.track:Hide()
    if record.countdownRadial then record.countdownRadial:Hide() end
    if record.countdownClips then for _,clip in ipairs(record.countdownClips) do clip:Hide() end end
    record.mode = nil; record.progressState = nil
end

local function ClearAll()
    for _, record in pairs(overlays) do Clear(record) end
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function Style(record)
    local color = COLORS[DB.color] or COLORS.amber
    local r,g,b = color[1],color[2],color[3]
    -- Black remains useful for radial shading; use a visible light fill for linear styles.
    local lr,lg,lb = r,g,b
    if DB.color == "black" then lr,lg,lb = 1,1,1 end
    record.radial:SetVertexColor(r,g,b,DB.opacity * 0.65)
    if record.countdownRadial then record.countdownRadial:SetStatusBarColor(r,g,b,DB.opacity * 0.65) end
    if record.countdownEdges then for _,edge in ipairs(record.countdownEdges) do edge:SetStatusBarColor(lr,lg,lb,DB.opacity) end end
    record.bar:SetStatusBarColor(lr,lg,lb,DB.opacity)
    record.bar:SetHeight(DB.thickness)
    record.track:SetHeight(DB.thickness)
    record.track:SetVertexColor(0,0,0,0.65)
    record.rising:SetStatusBarColor(lr,lg,lb,record.line and 0 or DB.opacity * 0.5)
    if record.line then
        record.line:SetVertexColor(lr,lg,lb,DB.opacity)
        record.line:SetHeight(DB.thickness)
    end
    -- Optional low-opacity fill behind the bright leading stripe.
    record.riseTint:SetStatusBarColor(lr,lg,lb,DB.tint and DB.opacity * 0.15 or 0)
    for i,edge in ipairs(record.edges) do
        edge:SetStatusBarColor(lr,lg,lb,DB.opacity)
        if i%2==1 then edge:SetHeight(DB.thickness) else edge:SetWidth(DB.thickness) end
    end
end

local function NewBar(frame, low, high, orientation, reverse)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(low,high)
    bar:SetValue(low)
    if bar.SetOrientation then bar:SetOrientation(orientation or "HORIZONTAL") end
    if bar.SetReverseFill then bar:SetReverseFill(reverse or false) end
    return bar
end

local function MakeOverlay(button, preview)
    if not preview and overlays[button] then return overlays[button] end
    local frame = CreateFrame("Frame", nil, button)
    local icon = button.icon or button.Icon
    if not icon or IsSecret(icon) or not pcall(frame.SetAllPoints, frame, icon) then
        frame:ClearAllPoints(); frame:SetAllPoints(button)
    end
    frame:EnableMouse(false)
    frame:SetFrameLevel(button:GetFrameLevel() + 1)
    local radial = frame:CreateTexture(nil, "ARTWORK")
    radial:SetAllPoints(frame)
    radial:SetTexture(WHITE)
    local native = type(radial.SetRadialProgressBarPercent) == "function"
    if native then
        -- Preserve the native full-circle geometry used in v0.1.0.
        -- Explicit endpoints 0 and 1 may collapse to the same angle.
        if radial.SetRadialProgressBarReverse then pcall(radial.SetRadialProgressBarReverse, radial, true) end
        native = pcall(radial.SetRadialProgressBarPercent, radial, 0)
    end
    local bar = NewBar(frame,0,1)
    bar:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",1,1)
    bar:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-1,1)
    local track = frame:CreateTexture(nil,"BACKGROUND")
    track:SetTexture(WHITE)
    track:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",1,1)
    track:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-1,1)
    local tint = NewBar(frame,0,1,"VERTICAL")
    tint:SetAllPoints(frame)
    local rising = NewBar(frame,0,1,"VERTICAL")
    rising:SetAllPoints(frame)
    rising:SetFrameLevel(frame:GetFrameLevel()+2)
    local line
    if rising.GetStatusBarTexture then
        local ok, result = pcall(function()
            local fillTexture = rising:GetStatusBarTexture()
            local stripe = rising:CreateTexture(nil,"OVERLAY")
            stripe:SetTexture(WHITE)
            stripe:SetPoint("TOPLEFT",fillTexture,"TOPLEFT",0,0)
            stripe:SetPoint("TOPRIGHT",fillTexture,"TOPRIGHT",0,0)
            return stripe
        end)
        if ok then line=result end
    end
    local edges = {}
    for i=1,4 do
        local edge = NewBar(frame,(i-1)/4,i/4,i%2==1 and "HORIZONTAL" or "VERTICAL",i==2 or i==3)
        edges[i]=edge
    end
    edges[1]:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); edges[1]:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
    edges[2]:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0); edges[2]:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
    edges[3]:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0); edges[3]:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
    edges[4]:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); edges[4]:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0)
    local record = {button=button,frame=frame,radial=radial,bar=bar,native=native,track=track,rising=rising,riseTint=tint,line=line,edges=edges}
    if not preview then overlays[button]=record end
    Style(record); Clear(record)
    return record
end

local function RebuildGroups()
    local previous = groups
    groups = {}
    ClearAll()
    for _, record in ipairs(records) do
        local cost = record.cost
        if cost and cost > 0 then
            local group = groups[cost]
            if not group then
                group = previous[cost]
                if not group or group.maxEnergy ~= lastMaxEnergy then
                    group = {curve=MakeCurve(cost,"fill"), deficit=MakeCurve(cost,"deficit"), visibility=MakeCurve(cost,"visibility"), maxEnergy=lastMaxEnergy}
                end
                group.records = {}
                groups[cost] = group
            end
            group.records[#group.records+1] = record
        end
    end
end

local function RegisterButton(button, costs)
    local slot = GetButtonSlot(button)
    if not slot then return end
    local spellID = GetSpellFromSlot(slot)
    if not spellID then return end
    local entry = costs[spellID]
    if not entry then
        local cost, hasEnergyCost = GetEnergyCost(spellID)
        entry = {cost=cost, hasEnergyCost=hasEnergyCost}
        costs[spellID] = entry
    end
    if not entry.hasEnergyCost then return end
    local record = overlays[button]
    if not record then
        if InCombatLockdown() then rescanPending = true; return end
        record = MakeOverlay(button)
    end
    record.spellID, record.cost = spellID, entry.cost
    records[#records+1] = record
end

local BUTTON_PREFIXES = {
    { "ActionButton", 12 },
    { "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 },
    { "MultiBarLeftButton", 12 },
    { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 },
    { "MultiBar7Button", 12 },
    { "BT4Button", 120 },
    { "DominosActionButton", 120 },
}

local function RefreshBindings()
    bindingPending = false
    wipe(records)
    for _, record in pairs(overlays) do record.spellID, record.cost = nil, nil end
    RefreshMaxEnergy()
    local costs = {}
    for _, button in ipairs(knownButtons) do RegisterButton(button, costs) end
    RebuildGroups()
end

local function ScanButtons()
    if InCombatLockdown() then rescanPending = true; return end
    rescanPending = false
    wipe(knownButtons)
    local seen = {}
    local function Add(button)
        if button and not seen[button] then
            seen[button] = true
            knownButtons[#knownButtons+1] = button
        end
    end
    for _, spec in ipairs(BUTTON_PREFIXES) do
        for n=1,spec[2] do Add(_G[spec[1] .. n]) end
    end
    for bar=1,15 do
        for n=1,12 do Add(_G["ElvUI_Bar" .. bar .. "Button" .. n]) end
    end
    -- Main buttons are pre-created so stealth/page swaps can be shown in combat.
    for n=1,12 do
        local button = _G["ActionButton" .. n]
        if button and not overlays[button] then MakeOverlay(button) end
    end
    RefreshBindings()
end

local function RefreshCosts()
    costPending = false
    local previousMax = lastMaxEnergy
    RefreshMaxEnergy()
    local changed = previousMax ~= lastMaxEnergy
    local costs = {}
    for _, record in ipairs(records) do
        local entry = costs[record.spellID]
        if not entry then
            local cost, found = GetEnergyCost(record.spellID)
            entry = {cost=found and cost or nil}
            costs[record.spellID] = entry
        end
        if entry.cost ~= record.cost then record.cost = entry.cost; changed = true end
    end
    if changed then RebuildGroups() end
end

local function ErrorNote(value)
    if not IsSecret(value) and type(value) == "string" then lastError = value
    else lastError = "native widget rejected value" end
end

local function Paint(record, fill, deficit, visibility)
    local mode = DB.mode == "auto" and "radial" or DB.mode
    -- Only native widgets consume secret values; never inspect their results.
    local function Apply(selected)
        if record.mode ~= selected or record.directRange or record.directActive then Clear(record) end
        record.directActive = false
        if record.directRange then
            record.bar:SetMinMaxValues(0,1); record.rising:SetMinMaxValues(0,1); record.riseTint:SetMinMaxValues(0,1)
            record.directRange = false
        end
        record.frame:SetAlpha(visibility)
        if selected == "radial" then
            if not record.native then error("radial API unavailable") end
            record.radial:SetRadialProgressBarPercent(deficit)
            record.radial:Show()
        elseif selected == "bar" then
            record.bar:SetValue(fill); record.track:Show(); record.bar:Show()
        elseif selected == "rising" then
            record.riseTint:SetValue(fill); record.rising:SetValue(fill)
            record.riseTint:Show(); record.rising:Show(); if record.line then record.line:Show() end
        elseif selected == "perimeter" then
            for _,edge in ipairs(record.edges) do edge:SetValue(fill); edge:Show() end
        end
        record.mode = selected
    end
    local ok,err = pcall(Apply,mode)
    if ok then return true end
    ErrorNote(err); record.renderError=lastError; Clear(record)
    ok,err = pcall(Apply,"bar")
    if ok then return false end
    ErrorNote(err); record.renderError=lastError; Clear(record)
    return false
end

local function Evaluate(curve)
    if not curve or type(UnitPowerPercent) ~= "function" then return nil,false end
    local ok,result = pcall(UnitPowerPercent,"player",ENERGY,false,curve)
    if not ok then ErrorNote(result); return nil,false end
    if IsSecret(result) then return result,true,"native curve (secret)" end
    if SafeNumber(result) then return result,true,"native curve (public)" end
    return nil,false
end

-- Native widgets consume protected ranges and values directly. No texture
-- readback, secret arithmetic, comparison, or timing estimate is needed.
local function SetDirectRange(bar, low, high, value)
    bar:SetMinMaxValues(low,high)
    bar:SetValue(value)
end

local function PrepareCountdownRadial(record)
    if record.countdownRadial then return record.countdownRadial end
    local bar=NewBar(record.frame,0,1)
    bar:Hide()
    bar:SetAllPoints(record.frame)
    bar:SetRenderMode(Enum and Enum.StatusBarRenderMode and Enum.StatusBarRenderMode.Radial or 1)
    local texture=bar:GetStatusBarTexture()
    -- Match the direction and default geometry of the working radial texture.
    if texture.SetRadialProgressBarReverse then texture:SetRadialProgressBarReverse(true) end
    record.countdownRadial=bar
    Style(record)
    return bar
end

-- Each clipped bar represents the same full countdown, but only one quarter
-- is visible. Offsets are calculated from public layout dimensions, never
-- from energy or a protected range. This preserves four sequential edges.
local function PrepareCountdownEdges(record)
    local w,h=SafeNumber(record.frame:GetWidth()),SafeNumber(record.frame:GetHeight())
    if not w or not h or w<=0 or h<=0 then error("countdown perimeter layout unavailable") end
    if not record.countdownClips then record.countdownClips={}; record.countdownEdges={} end
    for i=1,4 do
        if not record.countdownClips[i] then
            local clip=CreateFrame("Frame",nil,record.frame)
            clip:Hide(); clip:EnableMouse(false)
            clip:SetAllPoints(record.edges[i])
            clip:SetClipsChildren(true)
            local edge=NewBar(clip,0,1,i%2==1 and "HORIZONTAL" or "VERTICAL",i==2 or i==3)
            edge:EnableMouse(false)
            record.countdownClips[i]=clip; record.countdownEdges[i]=edge
        end
    end
    local key=tostring(w)..":"..tostring(h)..":"..tostring(DB.thickness)
    if record.countdownLayout~=key then
        for i,edge in ipairs(record.countdownEdges) do
            local clip=record.countdownClips[i]
            edge:ClearAllPoints()
            if i==1 then edge:SetSize(4*w,DB.thickness); edge:SetPoint("LEFT",clip,"LEFT",0,0)
            elseif i==2 then edge:SetSize(DB.thickness,4*h); edge:SetPoint("TOP",clip,"TOP",0,h)
            elseif i==3 then edge:SetSize(4*w,DB.thickness); edge:SetPoint("RIGHT",clip,"RIGHT",2*w,0)
            else edge:SetSize(DB.thickness,4*h); edge:SetPoint("BOTTOM",clip,"BOTTOM",0,-3*h) end
        end
        record.countdownLayout=key
        Style(record)
    end
end

local function PaintDirect(record,fill,deficit,visibility,group)
    local mode=DB.mode=="auto" and "radial" or DB.mode
    local ok,err=pcall(function()
        if record.mode~=mode or not record.directActive then Clear(record) end
        record.directActive=true
        record.frame:SetAlpha(visibility)
        if mode=="radial" then
            local bar=PrepareCountdownRadial(record)
            SetDirectRange(bar,0,group.startDeficit,deficit)
            bar:Show()
        elseif mode=="bar" then
            record.directRange=true
            SetDirectRange(record.bar,group.start,1,fill)
            record.track:Show(); record.bar:Show()
        elseif mode=="rising" then
            record.directRange=true
            SetDirectRange(record.riseTint,group.start,1,fill)
            SetDirectRange(record.rising,group.start,1,fill)
            record.riseTint:Show(); record.rising:Show(); if record.line then record.line:Show() end
        elseif mode=="perimeter" then
            PrepareCountdownEdges(record)
            for i,edge in ipairs(record.countdownEdges) do
                SetDirectRange(edge,group.start,1,fill)
                edge:Show(); record.countdownClips[i]:Show()
            end
        else error("unknown countdown renderer") end
        record.mode=mode; record.progressState="native countdown"
    end)
    if ok then return true end
    ErrorNote(err); record.renderError=lastError
    Clear(record)
    return false
end

local function Countdown(group, cost, fill, deficit)
    local public = SafeNumber(fill)
    local reset = group.public ~= (public ~= nil) or (not public and group.generation ~= progressGeneration)
    -- When energy is public, any actual spend (including outside spell events)
    -- can start a fresh countdown. Protected energy uses successful spell events.
    if public and (group.start == nil or (group.lastFill and public < group.lastFill-0.00001)) then reset=true end
    group.lastFill=public
    if reset then
        group.generation=progressGeneration; group.public=public ~= nil
        if public then
            group.start=math.min(0.999,math.max(0,public))
        else
            group.startFillCurve=group.startFillCurve or MakeCurve(cost,"startFill")
            group.startDeficitCurve=group.startDeficitCurve or MakeCurve(cost,"startDeficit")
            local sf,a=Evaluate(group.startFillCurve)
            local sd,b=Evaluate(group.startDeficitCurve)
            group.start=sf; group.startDeficit=sd; group.startValid=a and b
        end
    end
    if public then
        local p=math.max(0,math.min(1,(public-group.start)/(1-group.start)))
        return p,1-p,true,"countdown (public)"
    elseif group.startValid then
        return fill,deficit,true,"countdown (native direct range)",true
    end
    return fill,deficit,false,"energy fallback (countdown unavailable)"
end

local function ResetProgress()
    progressGeneration=progressGeneration+1
    for _,group in pairs(groups) do group.public=nil; group.lastFill=nil; group.start=nil; group.startValid=nil end
end
local function SetProgress(mode)
    if DB.progress ~= mode then DB.progress=mode; ResetProgress(); for _,record in pairs(overlays) do record.failedGroup=nil; record.failedError=nil end end
end

local function Update()
    updatePending = false
    if not DB or not DB.enabled or (DB.combatOnly and not InCombatLockdown() and not demo) then ClearAll(); if DB and DB.progress=="countdown" then ResetProgress() end; if refreshLiveStatus then refreshLiveStatus() end; return end
    local publicEnergy,triedPublic = nil,false
    lastSource = "no tracked energy abilities"
    for cost,group in pairs(groups) do
        local fill,deficit,visibility,valid
        if demo then
            fill,deficit,visibility,valid,lastSource = 0.5,0.5,1,true,"demo (50%)"
        else
            local a,b,c,source
            fill,a,source = Evaluate(group.curve)
            visibility,b = Evaluate(group.visibility)
            if DB.mode == "radial" or DB.mode == "auto" or DB.progress == "countdown" then deficit,c = Evaluate(group.deficit) else c=true end
            valid=a and b and c
            if valid then lastSource=source end
            if not valid then
                if not triedPublic then
                    triedPublic=true
                    if type(UnitPower)=="function" then local ok,result=pcall(UnitPower,"player",ENERGY); if ok then publicEnergy=SafeNumber(result) end end
                end
                if publicEnergy then
                    fill=math.max(0,math.min(1,publicEnergy/cost)); deficit=1-fill
                    visibility=publicEnergy<cost and 1 or 0
                    valid,lastSource=true,"public energy fallback"
                end
            end
        end
        local directRange, countdownOK, source
        if valid and not demo and DB.progress == "countdown" then
            fill,deficit,countdownOK,source,directRange=Countdown(group,cost,fill,deficit)
            lastSource=source
        end
        for _,record in ipairs(group.records) do
            record.renderError=nil
            if valid then
                if directRange then
                    -- Retry on a new snapshot, style change, or reload, not every power event.
                    local failed=record.failedGroup==group and record.failedGeneration==group.generation and record.failedMode==DB.mode
                    if not failed and PaintDirect(record,fill,deficit,visibility,group) then
                        record.failedGroup=nil; record.failedError=nil
                    else
                        if not failed then
                            record.failedGroup=group; record.failedGeneration=group.generation; record.failedMode=DB.mode
                            record.failedError=record.renderError
                        end
                        record.renderError=record.failedError
                        Paint(record,fill,deficit,visibility)
                        record.progressState="energy fallback"
                    end
                else
                    local rendered=Paint(record,fill,deficit,visibility)
                    if demo then record.progressState="demo"
                    elseif DB.progress=="countdown" then record.progressState=countdownOK and "public countdown" or "energy fallback"
                    else record.progressState="energy" end
                    if not rendered and not record.mode then record.progressState="unavailable" end
                end
            else Clear(record); record.progressState="unavailable"; lastSource="energy unavailable" end
        end
    end
    if refreshLiveStatus then refreshLiveStatus() end
end

local function RequestUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(0.03, Update)
end
local function RequestBindings()
    if bindingPending then return end
    bindingPending = true
    C_Timer.After(0.10, function() RefreshBindings(); Update() end)
end
local function RequestCosts()
    if costPending then return end
    costPending = true
    C_Timer.After(0.15, function() RefreshCosts(); Update() end)
end
local function RequestScan()
    if InCombatLockdown() then rescanPending = true; return end
    if rescanScheduled then return end
    rescanScheduled = true
    C_Timer.After(0.10, function() rescanScheduled = false; ScanButtons(); Update() end)
end

-- Compatibility diagnostics: GetBuildInfo returns the interface number as its fourth result.
-- An interface mismatch warrants testing, not automatic disabling.
local SUPPORTED_INTERFACE = 16001
local function CompatibilityStatus()
    if type(GetBuildInfo) ~= "function" then return "unknown", nil end
    local ok, _, _, _, interface = pcall(GetBuildInfo)
    local current = ok and SafeNumber(interface) or nil
    if not current or current <= 0 or current ~= math.floor(current) then return "unknown", nil end
    if current == SUPPORTED_INTERFACE then return "match", current end
    return current > SUPPORTED_INTERFACE and "newer" or "older", current
end
local function CheckCompatibility(notify)
    local state, current = CompatibilityStatus()
    local expected = tostring(SUPPORTED_INTERFACE)
    if state == "unknown" then
        if not notify then Say("Compatibility: client interface unavailable; target " .. expected) end
        return
    end
    if state == "match" then
        if notify then DB.lastInterfaceWarning = nil
        else Say("Compatibility: interface " .. current .. " matches target " .. expected .. " (not a live-test guarantee).") end
        return
    end
    if notify then
        local key = expected .. ":" .. tostring(current)
        if DB.lastInterfaceWarning == key then return end
        DB.lastInterfaceWarning = key
    end
    Say("Compatibility: client interface " .. current .. " (" .. state .. " than target " .. expected .. "). Addon remains enabled; test your overlays and check for updates.")
end

local KNOWN_BUILD = 71091
-- Set only after recording a successful live-client smoke test for this release.
local LAST_TESTED_BUILD = nil
local function ClientBuild()
    if type(GetBuildInfo) ~= "function" then return nil end
    local ok, _, build = pcall(GetBuildInfo)
    if not ok or IsSecret(build) then return nil end
    if type(build) == "string" and build:match("^%d+$") then build = tonumber(build) end
    build = SafeNumber(build)
    if not build or build <= 0 or build ~= math.floor(build) then return nil end
    return build
end
local function CheckBuild(notify)
    local build = ClientBuild()
    if not notify then
        Say("Build: client " .. tostring(build or "unavailable") .. " | reviewed baseline " .. KNOWN_BUILD .. " | last live-tested: " .. tostring(LAST_TESTED_BUILD or "not recorded"))
        if build and build > KNOWN_BUILD then Say("Build newer than reviewed baseline; test overlays and check for updates.") end
        return
    end
    if not build then return end
    if build <= KNOWN_BUILD then DB.lastBuildWarning = nil; return end
    local key = tostring(KNOWN_BUILD) .. ":" .. tostring(build)
    if DB.lastBuildWarning == key then return end
    DB.lastBuildWarning = key
    Say("New client build " .. build .. " (reviewed baseline " .. KNOWN_BUILD .. "). Addon remains enabled; run /resweep status and test overlays.")
end

local function ProgressSummary()
    local states={}
    for _,record in ipairs(records) do
        if record.cost and record.cost>0 and record.progressState then states[record.progressState]=(states[record.progressState] or 0)+1 end
    end
    local parts={}
    for _,key in ipairs({"native countdown","public countdown","energy fallback","energy","demo","unavailable"}) do
        if states[key] then parts[#parts+1]=states[key]..": "..states[key] end
    end
    return #parts>0 and table.concat(parts," | ") or "no active indicators",states
end

local function Status()
    local count, radial, bar, native, rising, perimeter = 0,0,0,0,0,0
    for _, record in ipairs(records) do
        if record.cost and record.cost > 0 then
            count = count + 1
            if record.native then native = native + 1 end
            if record.mode == "radial" then radial = radial + 1 end
            if record.mode == "bar" then bar = bar + 1 end
            if record.mode == "rising" then rising = rising + 1 end
            if record.mode == "perimeter" then perimeter = perimeter + 1 end
        end
    end
    Say(string.format("v0.7.0 | %d energy buttons | %d radial-capable | %d radial / %d bar active", count, native, radial, bar))
    Say(string.format("%d rising / %d perimeter active",rising,perimeter))
    Say("source: " .. lastSource .. " | max energy used: " .. lastMaxEnergy .. " | mode: " .. DB.mode .. " | progress: " .. DB.progress)
    Say("actual progress: "..ProgressSummary())
    for _,record in ipairs(records) do
        if record.cost and record.renderError then Say("spell "..tostring(record.spellID).." / "..DB.mode..": "..record.renderError) end
    end
    Say("last API error (historical): " .. lastError)
    CheckCompatibility(false)
    CheckBuild(false)
end
local optionsPanel, settingsCategory, refreshPanel
local function ApplySettings()
    for _,record in pairs(overlays) do Style(record) end
    Update()
    if refreshPanel then refreshPanel() end
end

local function CreateOptions()
    if optionsPanel then return end
    local panel=CreateFrame("Frame","RogueEnergySweepOptionsPanel")
    optionsPanel=panel
    local function Label(text,x,y,template)
        local f=panel:CreateFontString(nil,"ARTWORK",template or "GameFontNormal")
        f:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); f:SetText(text); return f
    end
    local function Button(text,x,y,w,click)
        local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
        b:SetSize(w,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y)
        b:SetText(text); b:SetScript("OnClick",click); return b
    end
    local function Check(text,x,y,click)
        local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
        b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); b:SetSize(24,24)
        Label(text,x+32,y-8,"GameFontHighlight")
        b:SetScript("OnClick",function(self) click(self:GetChecked() and true or false); ApplySettings() end)
        return b
    end
    Label("Rogue Energy Sweep",16,-16,"GameFontNormalLarge")
    Label("Track energy readiness directly on action buttons.",16,-42,"GameFontHighlight")
    local enabled=Check("Enable overlays",16,-65,function(v) DB.enabled=v; if v then RequestScan() end end)
    local combat=Check("Only in combat",225,-65,function(v) DB.combatOnly=v end)
    Label("Indicator style",16,-108)
    local modes={}
    for i,entry in ipairs({{"rising","Rising line"},{"bar","Bottom bar"},{"perimeter","Perimeter"},{"radial","Radial sweep"}}) do
        local key,text=entry[1],entry[2]
        modes[key]=Button(text,16+(i-1)*110,-130,106,function() DB.mode=key; ApplySettings() end)
    end
    Label("Progress mode",16,-161)
    local progressButtons={}
    progressButtons.energy=Button("Energy-based",16,-181,132,function() SetProgress("energy"); ApplySettings() end)
    progressButtons.countdown=Button("Countdown",156,-181,132,function() SetProgress("countdown"); ApplySettings() end)
    local liveStatus=Label("Countdown starts after spending energy (experimental).",16,-208,"GameFontHighlightSmall")
    local previousStatus
    refreshLiveStatus=function()
        if DB.progress~="countdown" then
            if previousStatus~="energy" then liveStatus:SetText("Energy-based: progress toward ability cost."); previousStatus="energy" end
            return
        end
        local summary,states=ProgressSummary()
        local message="Live: "..summary
        if states["energy fallback"] or states.unavailable then message="|cffffaa44"..message.."|r" end
        if previousStatus~=message then liveStatus:SetText(message); previousStatus=message end
    end
    Label("Indicator color",16,-232)
    local colors={}
    for i,entry in ipairs({{"amber","Gold"},{"white","White"},{"cyan","Cyan"},{"green","Green"},{"black","Black*"}}) do
        local key,text=entry[1],entry[2]
        colors[key]=Button(text,16+(i-1)*87,-251,82,function() DB.color=key; ApplySettings() end)
    end
    Label("*Black applies to radial; linear indicators use white.",16,-278,"GameFontHighlightSmall")
    local function Slider(name,x,y,low,high,step,callback)
        local label=Label(name,x,y)
        local sliderName="RogueEnergySweep"..name.."Slider"
        local slider=CreateFrame("Slider",sliderName,panel,"OptionsSliderTemplate")
        for _,suffix in ipairs({"Text","Low","High"}) do local f=_G[sliderName..suffix]; if f then f:SetText("") end end
        slider:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y-25); slider:SetSize(180,16)
        slider:SetMinMaxValues(low,high); slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider:SetScript("OnValueChanged",function(_,v) callback(math.floor(v+0.5)) end)
        return slider,label
    end
    local syncing=false
    local opacity,opacityLabel=Slider("Opacity",16,-303,15,100,5,function(v) if not syncing then DB.opacity=v/100; ApplySettings() end end)
    local thickness,thicknessLabel=Slider("Thickness",240,-303,2,8,1,function(v) if not syncing then DB.thickness=v; ApplySettings() end end)
    local tint=Check("Tint the filled area (rising line)",16,-351,function(v) DB.tint=v end)
    Label("Live preview  |  simulated energy",16,-386)
    local previewEnergy=15
    local previewRecords={}
    local previewStart=15
    local previewSlider,previewLabel=Slider("Energy",16,-410,0,100,1,function(v) if not syncing then previewEnergy=v; if refreshPanel then refreshPanel() end end end)
    local previewStartSlider,previewStartLabel=Slider("StartEnergy",240,-410,0,100,1,function(v) if not syncing then previewStart=v; if refreshPanel then refreshPanel() end end end)
    for i,entry in ipairs({{45,"Interface\\Icons\\Spell_Shadow_RitualOfSacrifice"},{35,"Interface\\Icons\\Ability_Rogue_Eviscerate"},{25,"Interface\\Icons\\Ability_Kick"}}) do
        local button=CreateFrame("Frame",nil,panel)
        button:SetSize(48,48); button:SetPoint("TOPLEFT",panel,"TOPLEFT",16+(i-1)*82,-455)
        button.icon=button:CreateTexture(nil,"BACKGROUND"); button.icon:SetAllPoints(button); button.icon:SetTexture(entry[2])
        local record=MakeOverlay(button,true)
        record.previewCost=entry[1]; previewRecords[#previewRecords+1]=record
        Label(tostring(entry[1]).." energy",16+(i-1)*82,-508,"GameFontHighlightSmall")
    end
    Button("Test on bars",16,-535,120,function() SlashCmdList.ROGUEENERGYSWEEP("demo") end)
    Button("Reset defaults",145,-535,120,function() SlashCmdList.ROGUEENERGYSWEEP("reset") end)
    refreshPanel=function()
        refreshLiveStatus()
        syncing=true
        enabled:SetChecked(DB.enabled); combat:SetChecked(DB.combatOnly); tint:SetChecked(DB.tint)
        for key,b in pairs(modes) do if key==DB.mode then b:Disable() else b:Enable() end end
        for key,b in pairs(progressButtons) do if key==DB.progress then b:Disable() else b:Enable() end end
        for key,b in pairs(colors) do if key==DB.color then b:Disable() else b:Enable() end end
        opacity:SetValue(DB.opacity*100); thickness:SetValue(DB.thickness); previewSlider:SetValue(previewEnergy); previewStartSlider:SetValue(previewStart)
        opacityLabel:SetText(string.format("Opacity: %d%%",math.floor(DB.opacity*100+0.5)))
        thicknessLabel:SetText(string.format("Thickness: %d px",DB.thickness))
        previewLabel:SetText(string.format("Energy: %d / 100",previewEnergy))
        previewStartLabel:SetText(string.format("Post-spend start: %d",previewStart))
        if DB.progress=="countdown" then previewStartSlider:Show(); previewStartLabel:Show() else previewStartSlider:Hide(); previewStartLabel:Hide() end
        for _,record in ipairs(previewRecords) do
            Style(record)
            local fill=math.min(1,previewEnergy/record.previewCost)
            if DB.progress=="countdown" then
                local start=math.min(previewStart,record.previewCost-0.001)
                fill=math.max(0,math.min(1,(previewEnergy-start)/(record.previewCost-start)))
            end
            Paint(record,fill,1-fill,previewEnergy<record.previewCost and 1 or 0)
        end
        syncing=false
    end
    panel:SetScript("OnShow",refreshPanel)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        settingsCategory=Settings.RegisterCanvasLayoutCategory(panel,"Rogue Energy Sweep")
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        panel.name="Rogue Energy Sweep"; InterfaceOptions_AddCategory(panel)
    end
    refreshPanel()
end

local function OpenOptions()
    if not optionsPanel then local ok,err=pcall(CreateOptions); if not ok then ErrorNote(err); optionsPanel=nil; Say("Options unavailable; use /resweep help."); return end end
    if settingsCategory and Settings.OpenToCategory then Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    else Say("Settings unavailable; use /resweep help.") end
end
local function Help()
    Say("/resweep options | status | demo | on | off | rescan | combat | opacity 90 | color amber/white/cyan/green/black | mode rising/bar/perimeter/radial | progress energy/countdown | thickness 4 | reset")
end
SLASH_ROGUEENERGYSWEEP1 = "/resweep"
SlashCmdList.ROGUEENERGYSWEEP = function(msg)
    if not DB then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "options" then OpenOptions(); return
    elseif cmd == "status" then Status(); return
    elseif cmd == "demo" then
        if not DB.enabled then Say("Enable the addon first with /resweep on."); return end
        if InCombatLockdown() then Say("Demo is available out of combat only."); return end
        demo = true; demoGeneration = demoGeneration + 1
        local generation = demoGeneration
        Update(); Say("Showing a 50% deficit for five seconds.")
        C_Timer.After(5, function() if generation == demoGeneration then demo = false; Update() end end)
        return
    elseif cmd == "on" then DB.enabled = true; RequestScan()
    elseif cmd == "off" then DB.enabled = false; demo = false; ResetProgress()
    elseif cmd == "rescan" then RequestScan(); Say(InCombatLockdown() and "Rescan deferred until combat ends." or "Rescan requested."); return
    elseif cmd == "combat" then DB.combatOnly = not DB.combatOnly; Say("Combat only: " .. tostring(DB.combatOnly))
    elseif cmd == "opacity" and tonumber(arg) then DB.opacity = math.max(0.15, math.min(1.00, tonumber(arg)/100))
    elseif cmd == "color" and COLORS[arg] then DB.color = arg
    elseif cmd == "mode" and MODES[arg] then DB.mode = arg == "auto" and "radial" or arg
    elseif cmd == "progress" and (arg == "energy" or arg == "countdown") then SetProgress(arg)
    elseif cmd == "thickness" and tonumber(arg) then DB.thickness = math.floor(math.max(2,math.min(8,tonumber(arg)))+0.5)
    elseif cmd == "reset" then RogueEnergySweepDB = {}; InitDB(); ResetProgress(); lastError = "none"; RequestScan()
    else Help(); return end
    ApplySettings()
end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
    "ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","SPELLS_CHANGED","PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_TALENT_UPDATE","ACTIVE_TALENT_GROUP_CHANGED","UPDATE_SHAPESHIFT_FORM","UPDATE_STEALTH"}) do
    pcall(events.RegisterEvent, events, event)
end
for _, event in ipairs({"UNIT_POWER_FREQUENT","UNIT_POWER_UPDATE","UNIT_MAXPOWER","UNIT_AURA","UNIT_SPELLCAST_SUCCEEDED"}) do
    pcall(events.RegisterUnitEvent, events, event, "player")
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then InitDB(); local ok,err=pcall(CreateOptions); if not ok then ErrorNote(err); optionsPanel=nil; Say("Options initialization failed; use /resweep help.") end
        elseif DB and (name == "Bartender4" or name == "Dominos" or name == "ElvUI") then RequestScan() end
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then CheckCompatibility(true); CheckBuild(true); RequestScan()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        local unit, power = ...
        if DB.enabled and unit == "player" and not IsSecret(power) and power == "ENERGY" then RequestUpdate() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if DB.enabled and DB.progress=="countdown" and not IsSecret(unit) and unit=="player" then
            local id=SafeNumber(spellID)
            local cost, hasEnergy, readable=GetEnergyCost(id)
            -- If spell identity/cost is restricted, reset on successful player
            -- casts rather than guessing which spell was used. Known free casts do not reset.
            if not id or not readable or (hasEnergy and cost>0) then
                progressGeneration=progressGeneration+1; RequestUpdate()
            end
        end
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_AURA" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then RequestCosts()
    elseif event == "PLAYER_REGEN_DISABLED" then demo = false; RefreshCosts(); Update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if rescanPending then ScanButtons() else RefreshCosts() end
        Update()
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_STEALTH" then RequestBindings()
    elseif event == "SPELLS_CHANGED" then RequestBindings(); RequestScan() end
end)
