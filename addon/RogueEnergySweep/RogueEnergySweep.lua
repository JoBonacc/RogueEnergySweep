-- Rogue Energy Sweep 0.20.1 (WoW Forever)
-- Action discovery and energy curve approach adapted from Rogue Energy Need 0.2.1
-- by Vryllak / Rogue Energy Need contributors (MIT; see LICENSE).
local ADDON_NAME, ns = ...
local Tracker=ns and ns.Tracker
local Chains=ns and ns.Chains
local GCD=ns and ns.GCD
local Options=ns and ns.Options
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
local ClearReady
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
local COLORS = {amber={1,0.78,0.16}, white={1,1,1}, cyan={0.22,0.85,1}, green={0.3,1,0.35}, black={0,0,0}, red={1,0.24,0.24}, purple={0.72,0.42,1}, orange={1,0.48,0.12}}
local PRESETS = {{"amber","Gold"},{"white","White"},{"cyan","Cyan"},{"green","Green"},{"red","Red"},{"purple","Purple"},{"orange","Orange"},{"black","Black"}}
local function ValidRGB(r,g,b)
    r,g,b=SafeNumber(r),SafeNumber(g),SafeNumber(b)
    if not r or not g or not b then return nil end
    return {math.max(0,math.min(1,r)),math.max(0,math.min(1,g)),math.max(0,math.min(1,b))}
end
local function ResolveColor()
    local c=DB.customColor
    if DB.color=="custom" and type(c)=="table" then
        return ValidRGB(c[1],c[2],c[3]) or COLORS.amber
    end
    return COLORS[DB.color] or COLORS.amber
end
local function ColorHex(c)
    return string.format("#%02X%02X%02X",math.floor(c[1]*255+0.5),math.floor(c[2]*255+0.5),math.floor(c[3]*255+0.5))
end
local function SetCustomColor(r,g,b)
    local c=ValidRGB(r,g,b)
    if not c then return false end
    DB.color="custom"; DB.customColor=c
    return true
end
local function SetColorHex(value)
    local hex=value:match("^#?(%x%x%x%x%x%x)$")
    if not hex then return false end
    return SetCustomColor(tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255)
end
local function OpenCustomColorPicker(apply)
    local picker=ColorPickerFrame
    if not picker or not picker.SetupColorPickerAndShow or not picker.GetColorRGB then
        return false
    end
    local ownerMode=DB.mode
    local previous=DB.color
    local saved=DB.customColor
    local original=saved and {saved[1],saved[2],saved[3]} or nil
    local c=ResolveColor()
    local function restore()
        if DB.mode==ownerMode then DB.color=previous; DB.customColor=original; apply()
        elseif DB.stylePrefs and DB.stylePrefs[ownerMode] then
            DB.stylePrefs[ownerMode].color=previous; DB.stylePrefs[ownerMode].customColor=original
        end
    end
    local ok=pcall(function()
        picker:SetupColorPickerAndShow({
            r=c[1],g=c[2],b=c[3],hasOpacity=false,
            swatchFunc=function()
                if DB.mode==ownerMode and SetCustomColor(picker:GetColorRGB()) then apply() end
            end,
            cancelFunc=restore
        })
    end)
    if not ok then restore(); return false end
    return true
end
local FILL_EFFECTS={solid=true,gradient=true,luminous=true}
local READY_EFFECTS={none=true,burst=true,flash=true,proc=true,halo=true,border=true,pulse=true,softflash=true}
local READY_ONESHOT={burst=true,flash=true,softflash=true}
local function AppearanceSnapshot(source)
    local c=source.customColor
    c=type(c)=="table" and ValidRGB(c[1],c[2],c[3]) or nil
    local color=source.color
    if not COLORS[color] and not (color=="custom" and c) then color="amber" end
    return {color=color,customColor=c,
        opacity=math.max(.15,math.min(1,SafeNumber(source.opacity) or .90)),
        thickness=math.floor(math.max(2,math.min(8,SafeNumber(source.thickness) or 4))+.5),
        tint=source.tint~=false,
        tintOpacity=math.max(0,math.min(1,SafeNumber(source.tintOpacity) or .15)),
        reverse=source.reverse==true,
        fillEffect=FILL_EFFECTS[source.fillEffect] and source.fillEffect or "solid"}
end
local function LoadAppearance(source)
    local a=AppearanceSnapshot(source)
    DB.color=a.color; DB.customColor=a.customColor; DB.opacity=a.opacity
    DB.thickness=a.thickness; DB.tint=a.tint; DB.tintOpacity=a.tintOpacity; DB.reverse=a.reverse; DB.fillEffect=a.fillEffect
end
local function SaveAppearance()
    DB.stylePrefs[DB.mode]=AppearanceSnapshot(DB)
end
local function SetStyle(mode)
    if not MODES[mode] then return false end
    if mode=="auto" then mode="radial" end
    if DB.mode==mode then return false end
    SaveAppearance()
    DB.mode=mode
    LoadAppearance(DB.stylePrefs[mode] or {})
    SaveAppearance()
    return true
end
local function ResetAppearance()
    LoadAppearance({}); SaveAppearance()
end
local function InitDB()
    if type(RogueEnergySweepDB) ~= "table" then RogueEnergySweepDB = {} end
    DB = RogueEnergySweepDB
    if type(DB.enabled) ~= "boolean" then DB.enabled = true end
    DB.combatOnly = DB.combatOnly == true
    DB.finisherComboOnly = DB.finisherComboOnly == true
    DB.hideCooldowns = DB.hideCooldowns == true
    if not READY_EFFECTS[DB.readyEffect] then DB.readyEffect="none" end
    DB.readyMatchColor=DB.readyMatchColor==true
    DB.readyFallback=DB.readyFallback~=false
    DB.readyOpacity=math.max(.15,math.min(1,SafeNumber(DB.readyOpacity) or .7))
    if type(DB.showCategories)~="table" then DB.showCategories={} end
    for _,key in ipairs({"builder","finisher","other"}) do DB.showCategories[key]=DB.showCategories[key]~=false end
    if type(DB.excludedSpells)~="table" then DB.excludedSpells={} end
    for id,excluded in pairs(DB.excludedSpells) do
        if not SafeNumber(id) or id<=0 or excluded~=true then DB.excludedSpells[id]=nil end
    end
    if not MODES[DB.mode] or DB.mode == "auto" then DB.mode = "rising" end
    -- Migrate the previous shared appearance to all four modes. The active
    -- top-level fields remain authoritative for old saved settings and slash commands.
    LoadAppearance(DB)
    if type(DB.stylePrefs)~="table" then DB.stylePrefs={} end
    for _,mode in ipairs({"rising","bar","perimeter","radial"}) do
        local stored=DB.stylePrefs[mode]
        DB.stylePrefs[mode]=AppearanceSnapshot(type(stored)=="table" and stored or DB)
    end
    SaveAppearance()
    if DB.progress ~= "countdown" then DB.progress = "energy" end
    if Tracker then Tracker.Init(DB) end
    if Chains then Chains.Init(DB) end
    if GCD then GCD.Init(DB) end
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
        if kind=="dial" then
            c:AddPoint(0,0); c:AddPoint(1,.75)
        elseif kind == "visibility" or kind == "ready" then
            local below,above=1,0
            if kind=="ready" then below,above=0,1 end
            if cost > lastMaxEnergy then c:AddPoint(0, below); c:AddPoint(1, below)
            else
                c:AddPoint(0, below)
                local edge = math.max(0, threshold - 0.5 / lastMaxEnergy)
                if edge > 0 then c:AddPoint(edge, below) end
                c:AddPoint(threshold, above)
                if threshold < 1 then c:AddPoint(1, above) end
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

-- Standard Forever finishers, including their Classic ranks. The power-cost
-- metadata also identifies other spells that require combo points.
local FINISHERS = {
    [2098]=true,[6760]=true,[6761]=true,[6762]=true,[8623]=true,[8624]=true,[11299]=true,[11300]=true,[31016]=true, -- Eviscerate
    [5171]=true,[6774]=true, -- Slice and Dice
    [8647]=true,[8649]=true,[8650]=true,[11197]=true,[11198]=true, -- Expose Armor
    [1943]=true,[8639]=true,[8640]=true,[11273]=true,[11274]=true,[11275]=true, -- Rupture
    [408]=true,[8643]=true, -- Kidney Shot
    [1316709]=true, -- Death Mark (Forever)
}
-- Known combo-point generating spells and ranks. Unknown or conditionally
-- generating abilities remain Other rather than being guessed from names.
local BUILDERS = {
    [1752]=true,[1757]=true,[1758]=true,[1759]=true,[1760]=true,[8621]=true,[11293]=true,[11294]=true,
    [53]=true,[2589]=true,[2590]=true,[2591]=true,[8721]=true,[11279]=true,[11280]=true,[11281]=true,[25300]=true,
    [1776]=true,[1777]=true,[8629]=true,[11285]=true,[11286]=true,
    [703]=true,[8631]=true,[8632]=true,[8633]=true,[11289]=true,[11290]=true,
    [8676]=true,[8724]=true,[8725]=true,[11267]=true,[11268]=true,[11269]=true,
    [1833]=true,[14278]=true,[16511]=true,[17347]=true,[17348]=true,[26864]=true,
    [1329]=true,[34411]=true,[34412]=true,[34413]=true,[14183]=true,
}
local function SpellCategory(id,finisher)
    if finisher or FINISHERS[id] then return "finisher" end
    if BUILDERS[id] then return "builder" end
    return "other"
end
local function GetEnergyCost(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then
        return nil, false
    end

    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or IsSecret(costs) or type(costs) ~= "table" then
        return nil, false
    end

    local energyCost,hasEnergy,energyKnown=nil,false,true
    local finisher=FINISHERS[spellID]==true
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
                if cost == nil then energyKnown=false
                elseif energyKnown and not hasEnergy then energyCost,hasEnergy=cost,true end
            elseif powerType==4 or (not IsSecret(row.name) and row.name=="COMBO_POINTS") then
                local min=SafeNumber(row.minCost)
                local cost=SafeNumber(row.cost)
                if (min and min>0) or (min==nil and cost and cost>0) then finisher=true end
            end
        end
    end
    if not energyKnown then return nil,false,false,finisher end
    return energyCost,hasEnergy,true,finisher
end

-- Forever combo points belong to the current target. Never substitute generic
-- UnitPower/UnitPowerPercent: those values can refer to the previous target.
-- Public points can be compared; protected points may only feed a native curve.
local comboGateCurve
local function TargetComboAlpha()
    if type(UnitExists)=="function" then
        local ok,exists=pcall(UnitExists,"target")
        if ok and not IsSecret(exists) and exists==false then return 0,"no target" end
    end
    if type(GetComboPoints)~="function" then return 0,"target API unavailable" end
    local ok,points=pcall(GetComboPoints,"player","target")
    if not ok then return 0,"target API rejected" end
    local public=SafeNumber(points)
    if public then return public>0 and 1 or 0,"target points (public)" end
    if not IsSecret(points) then return 0,"target points unavailable" end
    local accepted,alpha=pcall(function()
        if not comboGateCurve then
            local c=C_CurveUtil.CreateCurve()
            if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then c:SetType(Enum.LuaCurveType.Linear) end
            c:AddPoint(0,0); c:AddPoint(1,1); c:AddPoint(10,1)
            comboGateCurve=c
        end
        return comboGateCurve:Evaluate(points)
    end)
    if accepted and (IsSecret(alpha) or SafeNumber(alpha)) then return alpha,"target points (native curve)" end
    return 0,"protected target points unavailable"
end

local function ApplyComboGate(record,alpha,enabled)
    local value=1
    if enabled and record.finisher then value=alpha end
    local public=SafeNumber(value)
    if public~=nil and record.comboPublicAlpha==public then return true end
    local ok=pcall(record.comboGate.SetAlpha,record.comboGate,value)
    record.comboPublicAlpha=ok and public or nil
    if not ok then
        -- Fail closed for a finisher if the protected alpha is not accepted.
        pcall(record.comboGate.SetAlpha,record.comboGate,0)
    end
    return ok
end

-- An independent display-only gate keeps energy and combo-point alpha intact.
local cooldownCurve
local function CooldownAlpha(spellID)
    if not C_Spell or type(C_Spell.GetSpellCooldownDuration)~="function" then return 1,"unavailable" end
    local ok,alpha=pcall(function()
        -- Explicitly exclude the global cooldown. Never inspect secret timing values.
        local duration=C_Spell.GetSpellCooldownDuration(spellID,true)
        if not IsSecret(duration) and duration==nil then return 1 end
        local remaining=duration:GetRemainingDuration()
        local public=SafeNumber(remaining)
        if public then return public<=0 and 1 or 0 end
        if not IsSecret(remaining) then error("remaining duration unavailable") end
        if not cooldownCurve then
            local c=C_CurveUtil.CreateCurve()
            c:AddPoint(0,1); c:AddPoint(0.001,0); c:AddPoint(86400,0)
            cooldownCurve=c
        end
        return duration:EvaluateRemainingDuration(cooldownCurve)
    end)
    if ok and (IsSecret(alpha) or SafeNumber(alpha)) then return alpha,"native cooldown" end
    return 1,"unavailable"
end
local function ApplyCooldownGate(record,alpha)
    local public=SafeNumber(alpha)
    if public~=nil and record.cooldownPublicAlpha==public then return true end
    local ok=pcall(record.cooldownGate.SetAlpha,record.cooldownGate,alpha)
    record.cooldownPublicAlpha=ok and public or nil
    if not ok then pcall(record.cooldownGate.SetAlpha,record.cooldownGate,1) end
    return ok
end
local function IsExcluded(record)
    return DB.excludedSpells[record.spellID]==true or (DB.showCategories and DB.showCategories[record.category or "other"]==false) or false
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
    for _, record in pairs(overlays) do Clear(record); if ClearReady then ClearReady(record) end end
    if Tracker then Tracker.Hide() end
    if Chains then Chains.Hide() end
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Reversal changes public geometry only. Never manipulate protected energy.
local function EdgeRange(i,reverse)
    local segment=reverse and 5-i or i
    local flipped=(i==2 or i==3)
    if reverse then flipped=not flipped end
    return (segment-1)/4,segment/4,flipped
end
local function ApplyDirection(record)
    local reverse=DB.reverse==true
    if record.direction==reverse then return end
    if record.native and record.radial.SetRadialProgressBarReverse then pcall(record.radial.SetRadialProgressBarReverse,record.radial,not reverse) end
    if record.bar.SetReverseFill then record.bar:SetReverseFill(reverse) end
    if record.rising.SetReverseFill then record.rising:SetReverseFill(reverse) end
    if record.riseTint.SetReverseFill then record.riseTint:SetReverseFill(reverse) end
    if record.line and record.rising.GetStatusBarTexture then
        local tex=record.rising:GetStatusBarTexture()
        local edge=reverse and "BOTTOM" or "TOP"
        record.line:ClearAllPoints()
        record.line:SetPoint(edge.."LEFT",tex,edge.."LEFT",0,0)
        record.line:SetPoint(edge.."RIGHT",tex,edge.."RIGHT",0,0)
    end
    for i,edge in ipairs(record.edges) do
        local low,high,flip=EdgeRange(i,reverse)
        edge:SetMinMaxValues(low,high)
        if edge.SetReverseFill then edge:SetReverseFill(flip) end
    end
    record.direction=reverse
end
-- The gradient is an independent white texture anchored to the native fill
-- region. It stretches with that region rather than cropping a fixed gradient.
-- Only public appearance values are used here; protected energy stays in bars.
local function RisingFillStyle(record,r,g,b)
    local alpha=DB.tint and DB.opacity*(DB.tintOpacity or .15) or 0
    local requested=DB.mode=="rising" and DB.tint and DB.fillEffect or "solid"
    local gradient=record.riseGradient
    local actual="solid"
    if record.line and record.line.SetBlendMode then
        pcall(record.line.SetBlendMode,record.line,"BLEND")
    end
    if gradient then gradient:Hide() end
    if gradient and requested~="solid" then
        local luminous=requested=="luminous"
        local peak=math.min(1,alpha*(luminous and 3 or 2.5))
        local trail=alpha*.06
        local low,high=trail,peak
        if DB.reverse then low,high=high,low end
        local ok=pcall(function()
            gradient:SetBlendMode(luminous and "ADD" or "BLEND")
            gradient:SetGradient("VERTICAL",CreateColor(r,g,b,low),CreateColor(r,g,b,high))
            gradient:Show()
        end)
        if ok then
            actual=requested
            -- Bright leading stripe, with the soft additive glow inside the fill.
            if luminous and record.line and record.line.SetBlendMode then
                local blended=pcall(record.line.SetBlendMode,record.line,"ADD")
                if not blended then
                    gradient:Hide()
                    actual="solid"
                end
            end
        else gradient:Hide() end
    end
    record.riseTint:SetStatusBarColor(r,g,b,actual=="solid" and alpha or 0)
    record.fillEffectActual=actual
end

local function Style(record)
    -- A newly created default record already uses the original geometry.
    if DB.reverse==true or record.direction~=nil then ApplyDirection(record) end
    if record.countdownRadial and record.radialDirection~=(DB.reverse==true) then
        local texture=record.countdownRadial:GetStatusBarTexture()
        if texture and texture.SetRadialProgressBarReverse then texture:SetRadialProgressBarReverse(DB.reverse~=true) end
        record.radialDirection=DB.reverse==true
    end
    local color = ResolveColor()
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
    RisingFillStyle(record,lr,lg,lb)
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
    local cooldownGate=CreateFrame("Frame",nil,button)
    cooldownGate:SetAllPoints(button); cooldownGate:EnableMouse(false)
    local gate = CreateFrame("Frame",nil,cooldownGate)
    gate:SetAllPoints(button); gate:EnableMouse(false)
    local gcdGate=CreateFrame("Frame",nil,gate)
    gcdGate:SetAllPoints(button); gcdGate:EnableMouse(false)
    local frame = CreateFrame("Frame", nil, gcdGate)
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
    local riseGradient
    -- Allocate once; failure leaves the existing solid tint path intact.
    local ok=pcall(function()
        local nativeFill=tint:GetStatusBarTexture()
        local gradient=tint:CreateTexture(nil,"OVERLAY")
        gradient:Hide(); gradient:SetTexture(WHITE)
        gradient:SetAllPoints(nativeFill)
        if type(gradient.SetGradient)~="function" or type(CreateColor)~="function" or type(gradient.SetBlendMode)~="function" then return end
        riseGradient=gradient
    end)
    if not ok then riseGradient=nil end
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
    local record = {button=button,frame=frame,comboGate=gate,cooldownGate=cooldownGate,gcdGate=gcdGate,radial=radial,bar=bar,native=native,track=track,rising=rising,riseTint=tint,riseGradient=riseGradient,line=line,edges=edges}
    if not preview then overlays[button]=record end
    Style(record); Clear(record)
    return record
end

-- Ready effects are independent siblings of the insufficient-energy frame.
-- Never read a secret alpha back or use a secret as an animation trigger.
local function ReadySignal(record,alpha)
    local public=SafeNumber(alpha)
    if public~=nil then return public>=1,"public energy" end
    -- Public spell usability is a conservative secondary signal only for
    -- non-finishers. A missing combo point is not an energy transition.
    if IsSecret(alpha) and not record.gcdProjected and not record.finisher and C_Spell and type(C_Spell.IsSpellUsable)=="function" then
        local ok,usable,insufficient=pcall(C_Spell.IsSpellUsable,record.spellID)
        if ok and not IsSecret(usable) and not IsSecret(insufficient) and type(usable)=="boolean" and type(insufficient)=="boolean" then
            if insufficient then return false,"public power usability" end
            if usable then return true,"public power usability" end
        end
    end
    return nil,"protected threshold"
end
local function ReadyTransition(record,ready,source)
    local fire=ready==true and record.readyPrevious==false and record.readySignalSource==source
    record.readyPrevious=ready
    record.readySignalSource=source
    return fire
end
local function ReadyChoice(effect,signal,fallback)
    if READY_ONESHOT[effect] and signal==nil then
        return fallback and "pulse" or "none"
    end
    return effect
end
local function StopReadyVisual(record)
    local visual=record.readyVisual
    record.readyVisual=nil
    if not visual then return end
    if visual.anim then pcall(visual.anim.Stop,visual.anim) end
    pcall(visual.frame.Hide,visual.frame)
end
ClearReady=function(record)
    StopReadyVisual(record)
    record.readyPrevious=nil; record.readySignalSource=nil; record.readyRequested=nil
    record.readyActual=nil; record.readyReason=nil
    if record.readyGate and record.readyGateActive then pcall(record.readyGate.SetAlpha,record.readyGate,0); record.readyGateActive=false end
end
local function ReadyAtlas(texture,atlas)
    if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(atlas) then error("Missing atlas "..atlas) end
    texture:SetAtlas(atlas,false)
end
local function ReadyTexture(parent,atlas,inset)
    local t=parent:CreateTexture(nil,"ARTWORK")
    t:SetPoint("TOPLEFT",parent,"TOPLEFT",inset,-inset)
    t:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-inset,inset)
    if atlas then ReadyAtlas(t,atlas) else t:SetTexture(WHITE) end
    return t
end
local function ReadyAnim(group,kind,target,duration,order)
    local a=group:CreateAnimation(kind)
    a:SetTarget(target); a:SetDuration(duration); a:SetOrder(order or 1)
    return a
end
local function ReadyFlipbook(group,target,duration,rows,columns,frames)
    local a=ReadyAnim(group,"FlipBook",target,duration)
    a:SetFlipBookRows(rows); a:SetFlipBookColumns(columns); a:SetFlipBookFrames(frames)
    return a
end
local function ReadyBorder(parent,textures)
    for i=1,4 do
        local t=parent:CreateTexture(nil,"OVERLAY")
        t:SetTexture(WHITE)
        if i==1 then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(2)
        elseif i==2 then t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(2)
        elseif i==3 then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(2)
        else t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(2) end
        t:SetBlendMode("ADD"); textures[#textures+1]=t
    end
end
local function BuildReadyVisual(record,effect)
    if not record.readyGate then
        local gate=CreateFrame("Frame",nil,record.gcdGate or record.comboGate)
        gate:EnableMouse(false); gate:SetAllPoints(record.frame)
        gate:SetFrameLevel(record.frame:GetFrameLevel()+4); gate:SetAlpha(0)
        record.readyGate=gate
    end
    record.readyVisuals=record.readyVisuals or {}
    if record.readyVisuals[effect]~=nil then return record.readyVisuals[effect] or nil end
    local frame
    local ok,visual=pcall(function()
        frame=CreateFrame("Frame",nil,record.readyGate)
        frame:Hide(); frame:EnableMouse(false); frame:SetAllPoints(record.readyGate)
        local content=CreateFrame("Frame",nil,frame)
        content:EnableMouse(false); content:SetAllPoints(frame)
        local v={frame=frame,content=content,textures={},effect=effect}
        local function Texture(atlas,inset)
            local t=ReadyTexture(content,atlas,inset)
            v.textures[#v.textures+1]=t; return t
        end
        local function Anim()
            if not v.anim then v.anim=content:CreateAnimationGroup() end
            return v.anim
        end
        if effect=="burst" then
            local t=Texture("UI-HUD-ActionBar-Casting-Complete-Glow",-3)
            t:SetBlendMode("ADD")
            local mask=content:CreateMaskTexture(nil,"ARTWORK")
            mask:SetPoint("TOPLEFT",content,"TOPLEFT",-12,12)
            mask:SetPoint("BOTTOMRIGHT",content,"BOTTOMRIGHT",12,-12)
            mask:SetAtlas("UI-HUD-ActionBar-CastingChannel-Complete-Mask",false)
            t:AddMaskTexture(mask)
            local a=ReadyAnim(Anim(),"Scale",t,.5)
            a:SetScaleFrom(.15,.15); a:SetScaleTo(1.7,1.7); a:SetSmoothing("OUT")
            local fade=ReadyAnim(Anim(),"Alpha",t,.5); fade:SetFromAlpha(1); fade:SetToAlpha(0)
        elseif effect=="flash" then
            local t=Texture("UI-HUD-ActionBar-GCD-Flipbook",0)
            ReadyFlipbook(Anim(),t,.75,11,2,22)
        elseif effect=="proc" then
            local t=Texture("UI-HUD-ActionBar-Proc-Loop-Flipbook",-6)
            ReadyFlipbook(Anim(),t,1,6,5,30)
            v.anim:SetLooping("REPEAT")
        elseif effect=="halo" then
            local t=Texture("UI-HUD-RotationHelper-ProcAltGlow",-5)
            t:SetBlendMode("ADD")
        elseif effect=="border" or effect=="pulse" then
            ReadyBorder(content,v.textures)
            if effect=="pulse" then
                local a=ReadyAnim(Anim(),"Alpha",content,.6); a:SetFromAlpha(.15); a:SetToAlpha(1); a:SetSmoothing("IN_OUT")
                v.anim:SetLooping("BOUNCE")
            end
        elseif effect=="softflash" then
            local t=Texture(nil,0); t:SetBlendMode("ADD")
            local a=ReadyAnim(Anim(),"Alpha",t,.28); a:SetFromAlpha(.65); a:SetToAlpha(0); a:SetSmoothing("OUT")
        else error("Unknown ready effect") end
        if v.anim and READY_ONESHOT[effect] then
            v.anim:SetScript("OnFinished",function()
                if record.readyVisual==v then
                    record.readyVisual=nil; v.frame:Hide()
                end
            end)
        end
        return v
    end)
    if not ok then
        if frame then pcall(frame.Hide,frame) end
        record.readyVisuals[effect]=false
        record.readyError=tostring(visual)
        return nil
    end
    record.readyVisuals[effect]=visual
    return visual
end
local function StyleReadyVisual(visual)
    local c=ResolveColor()
    local r,g,b=1,1,1
    if DB.readyMatchColor then
        r,g,b=c[1],c[2],c[3]
        if r==0 and g==0 and b==0 then r,g,b=1,1,1 end
    elseif visual.effect=="border" or visual.effect=="pulse" or visual.effect=="softflash" then r,g,b=1,.78,.16 end
    local key=string.format("%.3f:%.3f:%.3f:%.3f",r,g,b,DB.readyOpacity)
    if visual.styleKey==key then return end
    visual.frame:SetAlpha(DB.readyOpacity)
    for _,t in ipairs(visual.textures) do t:SetVertexColor(r,g,b,1) end
    visual.styleKey=key
end
local function UpdateReady(record,alpha,eligible,preview)
    local effect=DB.readyEffect
    if not eligible or effect=="none" or (not IsSecret(alpha) and SafeNumber(alpha)==nil) then ClearReady(record); return end
    if record.readyRequested~=effect then
        ClearReady(record); record.readyRequested=effect
    end
    local signal,source,fire
    if READY_ONESHOT[effect] then
        signal,source=ReadySignal(record,alpha)
        fire=ReadyTransition(record,signal,source)
    else
        source=IsSecret(alpha) and "native protected alpha" or "public energy"
        fire=false
    end
    local desired=ReadyChoice(effect,signal,DB.readyFallback)
    record.readyReason=source
    if desired=="none" then StopReadyVisual(record); record.readyActual="none"; return end
    local oneshot=READY_ONESHOT[desired]==true
    local public=SafeNumber(alpha)
    if public~=nil and public<1 then StopReadyVisual(record); record.readyActual=desired; return end
    if oneshot and signal==false then StopReadyVisual(record); record.readyActual=desired; return end
    if oneshot and not fire and not (record.readyVisual and READY_ONESHOT[record.readyVisual.effect]) then
        if record.readyVisual then StopReadyVisual(record) end
        record.readyActual=desired; return
    end
    local visual=BuildReadyVisual(record,desired)
    local actual=desired
    if not visual then
        actual=oneshot and "softflash" or "border"
        visual=BuildReadyVisual(record,actual)
        record.readyReason=source.." / artwork fallback"
    end
    if not visual then StopReadyVisual(record); record.readyActual="none"; return end
    record.readyActual=actual
    -- Native alpha is the only protected input; the animation itself is
    -- public and never reads the visibility or alpha back from a widget.
    local ok=pcall(record.readyGate.SetAlpha,record.readyGate,alpha)
    record.readyGateActive=ok
    if not ok then
        StopReadyVisual(record); record.readyReason="native ready alpha rejected"; record.readyActual="none"; return
    end
    StyleReadyVisual(visual)
    if record.readyVisual~=visual or (oneshot and fire) then
        StopReadyVisual(record)
        record.readyVisual=visual
        visual.frame:Show()
        if visual.anim then visual.anim:Play() end
    end
end
local function SafeUpdateReady(record,alpha,eligible,preview)
    if DB.readyEffect=="none" and not record.readyGate and not record.readyRequested then return end
    local ok,err=pcall(UpdateReady,record,alpha,eligible,preview)
    if not ok then
        ClearReady(record); record.readyError=tostring(err); record.readyReason="ready renderer rejected"
    end
end

local function RebuildGroups()
    local previous = groups
    groups = {}
    ClearAll()
    if Tracker then Tracker.Sync(records,lastMaxEnergy) end
    if Chains then Chains.Sync(records,lastMaxEnergy) end
    local function AddCost(cost)
        local group=groups[cost]
        if not group then
            group=previous[cost]
            if not group or group.maxEnergy~=lastMaxEnergy then
                group={curve=MakeCurve(cost,"fill"),deficit=MakeCurve(cost,"deficit"),visibility=MakeCurve(cost,"visibility"),maxEnergy=lastMaxEnergy}
            end
            group.records={}; groups[cost]=group
        end
        return group
    end
    for _,record in ipairs(records) do
        if record.cost and record.cost>0 then
            local group=AddCost(record.cost)
            group.records[#group.records+1]=record
        end
    end
    if Tracker then for cost in pairs(Tracker.Costs()) do AddCost(cost) end end
    if Options then Options.Refresh() end
end

local function RegisterButton(button, costs)
    local slot = GetButtonSlot(button)
    if not slot then return end
    local spellID = GetSpellFromSlot(slot)
    if not spellID then return end
    local entry = costs[spellID]
    if not entry then
        local cost, hasEnergyCost, _, finisher = GetEnergyCost(spellID)
        entry = {cost=cost, hasEnergyCost=hasEnergyCost, finisher=finisher}
        costs[spellID] = entry
    end
    if not entry.hasEnergyCost then return end
    local record = overlays[button]
    if not record then
        if InCombatLockdown() then rescanPending = true; return end
        record = MakeOverlay(button)
    end
    record.spellID, record.cost, record.finisher = spellID, entry.cost, entry.finisher
    record.category=SpellCategory(spellID,entry.finisher)
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
    for _, record in pairs(overlays) do record.spellID, record.cost, record.finisher, record.category = nil, nil, nil, nil end
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
            local cost, found, _, finisher = GetEnergyCost(record.spellID)
            entry = {cost=found and cost or nil,finisher=finisher}
            costs[record.spellID] = entry
        end
        record.finisher=entry.finisher
        record.category=SpellCategory(record.spellID,entry.finisher)
        if entry.cost ~= record.cost then record.cost = entry.cost; changed = true end
    end
    if Tracker and Tracker.Sync(records,lastMaxEnergy) then changed=true end
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
    if texture.SetRadialProgressBarReverse then texture:SetRadialProgressBarReverse(DB.reverse~=true) end
    record.countdownRadial=bar; record.radialDirection=DB.reverse==true
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
    local reverse=DB.reverse==true
    local key=tostring(w)..":"..tostring(h)..":"..tostring(DB.thickness)..":"..tostring(reverse)
    if record.countdownLayout~=key then
        for i,edge in ipairs(record.countdownEdges) do
            local clip=record.countdownClips[i]
            edge:ClearAllPoints()
            local flip=(i==2 or i==3)
            if reverse then flip=not flip end
            if edge.SetReverseFill then edge:SetReverseFill(flip) end
            if reverse then
                if i==1 then edge:SetSize(4*w,DB.thickness); edge:SetPoint("RIGHT",clip,"RIGHT",3*w,0)
                elseif i==2 then edge:SetSize(DB.thickness,4*h); edge:SetPoint("BOTTOM",clip,"BOTTOM",0,-2*h)
                elseif i==3 then edge:SetSize(4*w,DB.thickness); edge:SetPoint("LEFT",clip,"LEFT",-w,0)
                else edge:SetSize(DB.thickness,4*h); edge:SetPoint("TOP",clip,"TOP",0,0) end
            else
                if i==1 then edge:SetSize(4*w,DB.thickness); edge:SetPoint("LEFT",clip,"LEFT",0,0)
                elseif i==2 then edge:SetSize(DB.thickness,4*h); edge:SetPoint("TOP",clip,"TOP",0,h)
                elseif i==3 then edge:SetSize(4*w,DB.thickness); edge:SetPoint("RIGHT",clip,"RIGHT",2*w,0)
                else edge:SetSize(DB.thickness,4*h); edge:SetPoint("BOTTOM",clip,"BOTTOM",0,-3*h) end
            end
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
        return fill,deficit,true,"protected snapshot (direct range requested)",true
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

local lastComboSource="not evaluated"
local lastCooldownSource="off"
local performanceSample={enabled=false,updates=0,total=0,max=0,requests=0,coalesced=0}
local function UpdateCore()
    updatePending = false
    if not DB or not DB.enabled or (DB.combatOnly and not InCombatLockdown() and not demo) then ClearAll(); if DB and DB.progress=="countdown" then ResetProgress() end; if refreshLiveStatus then refreshLiveStatus() end; return end
    local trackerActive=Tracker and Tracker.Begin(demo)
    if Chains then Chains.Begin() end
    if GCD then GCD.Begin(lastMaxEnergy,demo) end
    local publicEnergy,triedPublic = nil,false
    local comboAlpha=1
    local gateEnabled=DB.finisherComboOnly and not demo
    if gateEnabled then comboAlpha,lastComboSource=TargetComboAlpha()
    else lastComboSource=demo and "demo bypass" or "off" end
    local cooldowns={}
    local cooldownEnabled=DB.hideCooldowns and not demo
    lastCooldownSource=cooldownEnabled and "native cooldown" or (demo and "demo bypass" or "off")
    lastSource = "no tracked energy abilities"
    for cost,group in pairs(groups) do
        local fill,deficit,visibility,valid
        if demo then
            fill,deficit,visibility,valid,lastSource = 0.5,0.5,1,true,"demo (50%)"
        else
            local a,b,c,source
            fill,a,source = Evaluate(group.curve)
            visibility,b = Evaluate(group.visibility)
            if DB.mode == "radial" or DB.mode == "auto" or DB.progress == "countdown" then deficit,c = Evaluate(group.deficit)
            elseif trackerActive then deficit=Evaluate(group.deficit); c=true
            else c=true end
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
        local readyAlpha
        if valid and not demo and (DB.readyEffect~="none" or trackerActive) then
            local public=SafeNumber(visibility)
            if public~=nil then readyAlpha=1-public
            else
                if not group.readyCurve then group.readyCurve=MakeCurve(cost,"ready") end
                local alpha,ok=Evaluate(group.readyCurve)
                if ok then readyAlpha=alpha end
            end
        end
        local directRange, countdownOK, source
        if valid and not demo and DB.progress == "countdown" then
            fill,deficit,countdownOK,source,directRange=Countdown(group,cost,fill,deficit)
            lastSource=source
        end
        if trackerActive then Tracker.Group(cost,group,fill,deficit,visibility,readyAlpha,valid,directRange,comboAlpha,gateEnabled,cooldowns,cooldownEnabled,demo) end
        for _,record in ipairs(group.records) do
            record.renderError=nil
            local comboOK=ApplyComboGate(record,comboAlpha,gateEnabled)
            if not comboOK then lastComboSource="native gate rejected" end
            local excluded=not demo and IsExcluded(record)
            if excluded then
                if Chains then Chains.Clear(record) end; Clear(record); ClearReady(record); record.progressState="excluded"
            elseif valid then
                local alpha=1
                if cooldownEnabled then
                    local cached=cooldowns[record.spellID]
                    if not cached then
                        local value,source=CooldownAlpha(record.spellID)
                        cached={value=value,source=source}; cooldowns[record.spellID]=cached
                    end
                    alpha=cached.value
                    if cached.source=="unavailable" then lastCooldownSource="partial/unavailable" end
                end
                local cooldownOK=ApplyCooldownGate(record,alpha)
                if not cooldownOK then lastCooldownSource="partial/unavailable" end
                local comboPublic=gateEnabled and record.finisher and SafeNumber(comboAlpha) or nil
                local cooldownPublic=SafeNumber(alpha)
                if Chains then Chains.Update(record,not demo and comboOK and cooldownOK and comboPublic~=0 and cooldownPublic~=0) end
                if DB.tracker and DB.tracker.actionBars==false and not demo then
                    Clear(record); ClearReady(record); record.progressState="action sweep off"
                else
                local actualFill,actualDeficit,actualVisibility,actualReady=fill,deficit,visibility,readyAlpha
                local gcdAlpha,suppressReady=1,false
                if GCD then
                    fill,deficit,visibility,readyAlpha,record.gcdProjected,gcdAlpha,suppressReady=GCD.Project(record.spellID,cost,fill,deficit,visibility,readyAlpha,DB.progress=="countdown")
                    GCD.Apply(record,gcdAlpha)
                end
                SafeUpdateReady(record,readyAlpha,not suppressReady and not demo and comboOK and cooldownOK and comboPublic~=0 and cooldownPublic~=0,false)
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
                        record.progressState=record.mode and "energy fallback" or "unavailable"
                    end
                else
                    local rendered=Paint(record,fill,deficit,visibility)
                    if demo then record.progressState="demo"
                    elseif DB.progress=="countdown" then record.progressState=countdownOK and "public countdown" or "energy fallback"
                    else record.progressState="energy" end
                    if not rendered and not record.mode then record.progressState="unavailable" end
                end
                fill,deficit,visibility,readyAlpha=actualFill,actualDeficit,actualVisibility,actualReady
                end
            else Clear(record); ClearReady(record); if Chains then Chains.Clear(record) end; record.progressState="unavailable"; lastSource="energy unavailable" end
        end
    end
    if trackerActive then Tracker.Finish(demo) end
    if refreshLiveStatus then refreshLiveStatus() end
end

local function RecordTiming(sample,elapsed)
    if not SafeNumber(elapsed) or elapsed<0 then return end
    sample.updates=sample.updates+1; sample.total=sample.total+elapsed
    sample.max=math.max(sample.max,elapsed)
end
local function Update()
    if not performanceSample.enabled or type(debugprofilestop)~="function" then UpdateCore(); return end
    local started=debugprofilestop()
    UpdateCore()
    RecordTiming(performanceSample,debugprofilestop()-started)
end
local function SetProfiling(enabled)
    if enabled then
        if type(debugprofilestop)~="function" then return false end
        performanceSample={enabled=true,updates=0,total=0,max=0,requests=0,coalesced=0}
    else performanceSample.enabled=false end
    return true
end
local function RequestUpdate()
    if performanceSample.enabled then
        performanceSample.requests=performanceSample.requests+1
        if updatePending then performanceSample.coalesced=performanceSample.coalesced+1 end
    end
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
    for _,key in ipairs({"native countdown","public countdown","energy fallback","energy","demo","excluded","unavailable"}) do
        if states[key] then parts[#parts+1]=string.format("%s: %d",key,states[key]) end
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
    Say(string.format("v0.20.1 | %d energy buttons | %d radial-capable | %d radial / %d bar active", count, native, radial, bar))
    Say(string.format("%d rising / %d perimeter active",rising,perimeter))
    Say("source: " .. lastSource .. " | max energy used: " .. lastMaxEnergy .. " | mode: " .. DB.mode .. " | progress: " .. DB.progress)
    Say("actual progress: "..ProgressSummary())
    Say("ready effect: "..DB.readyEffect.." | protected fallback: "..tostring(DB.readyFallback).." (see diagnostics)")
    local finishers=0
    for _,record in ipairs(records) do if record.finisher and record.cost and record.cost>0 then finishers=finishers+1 end end
    Say("finisher gate: "..(DB.finisherComboOnly and "on" or "off").." | "..finishers.." finishers | "..lastComboSource)
    Say("cooldown gate: "..(DB.hideCooldowns and "on" or "off").." | "..lastCooldownSource)
    for _,record in ipairs(records) do
        if record.cost and record.renderError then Say("spell "..tostring(record.spellID).." / "..DB.mode..": "..record.renderError) end
    end
    Say("last API error (historical): " .. lastError)
    CheckCompatibility(false)
    CheckBuild(false)
end
local function DiagnosticReport()
    local state,interface=CompatibilityStatus()
    local count,finishers,excluded=0,0,0
    local errors={}
    for _,record in ipairs(records) do
        if record.cost and record.cost>0 then
            count=count+1
            if record.finisher then finishers=finishers+1 end
            if IsExcluded(record) then excluded=excluded+1 end
            if record.renderError then errors[#errors+1]="Spell "..tostring(record.spellID)..": "..record.renderError end
        end
    end
    local providers={}
    for _,name in ipairs({"Bartender4","Dominos","ElvUI"}) do
        local loader=C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        if type(loader)=="function" then local ok,value=pcall(loader,name); if ok and not IsSecret(value) and value then providers[#providers+1]=name end end
    end
    local p=performanceSample
    local readySources,readyActuals={},{}
    for _,record in ipairs(records) do
        if record.cost and record.cost>0 then
            local source=record.readyReason or "inactive"
            local actual=record.readyActual or "none"
            readySources[source]=(readySources[source] or 0)+1
            readyActuals[actual]=(readyActuals[actual] or 0)+1
            if record.readyError then errors[#errors+1]="Ready spell "..tostring(record.spellID)..": "..record.readyError end
        end
    end
    local function Counts(t)
        local parts={}; for key,n in pairs(t) do parts[#parts+1]=key..": "..n end; table.sort(parts); return table.concat(parts," | ")
    end
    local fillFallback=0
    if DB.mode=="rising" and DB.tint and DB.fillEffect~="solid" then
        for _,record in ipairs(records) do if record.cost and record.cost>0 and record.fillEffectActual~=DB.fillEffect then fillFallback=fillFallback+1 end end
    end
    local lines={
        "Rogue Energy Sweep v0.20.1 diagnostic report",
        "Client build: "..tostring(ClientBuild() or "unknown").." | interface: "..tostring(interface or "unknown").." ("..state..")",
        "Reviewed baseline: "..KNOWN_BUILD.." | complete live checklist: "..tostring(LAST_TESTED_BUILD or "not recorded"),
        "Bar addons detected: "..(#providers>0 and table.concat(providers,", ") or "none of the three known providers"),
        "Tracked energy buttons: "..count.." | finishers: "..finishers.." | filtered buttons: "..excluded,
        "Categories: builders="..tostring(DB.showCategories.builder).." finishers="..tostring(DB.showCategories.finisher).." other="..tostring(DB.showCategories.other),
        "Enabled: "..tostring(DB.enabled).." | combat only: "..tostring(DB.combatOnly),
        "Style: "..DB.mode.." | progress: "..DB.progress.." | reversed: "..tostring(DB.reverse),
        "Color: "..ColorHex(ResolveColor()).." | opacity: "..math.floor(DB.opacity*100+.5).."% | thickness: "..DB.thickness,
        "Tint: "..tostring(DB.tint).." | tint opacity: "..math.floor(DB.tintOpacity*100+.5).."% | fill: "..DB.fillEffect,
        "Rising fill fallback buttons: "..fillFallback,
        "Ready effect: "..DB.readyEffect.." | intensity: "..math.floor(DB.readyOpacity*100+.5).."% | match color: "..tostring(DB.readyMatchColor).." | pulse fallback: "..tostring(DB.readyFallback),
        "Ready paths: "..Counts(readyActuals),
        "Tracker: "..(Tracker and Tracker.Status() or "module unavailable"),
        "Ability Chains: "..(Chains and Chains.Status() or "module unavailable"),
        "GCD-aware: "..(GCD and GCD.Status() or "module unavailable"),
        "Ready signals: "..Counts(readySources),
        "Actual progress: "..ProgressSummary(),
        "Energy source: "..lastSource.." | max energy used: "..lastMaxEnergy,
        "Finisher gate: "..tostring(DB.finisherComboOnly).." | "..lastComboSource,
        "Cooldown gate: "..tostring(DB.hideCooldowns).." | "..lastCooldownSource,
        string.format("Update profiling: %s | %d updates | avg %.3f ms | max %.3f ms",p.enabled and "running" or "stopped",p.updates,p.updates>0 and p.total/p.updates or 0,p.max),
        string.format("Update requests: %d | coalesced: %d",p.requests,p.coalesced),
        "Last API error (historical): "..lastError,
    }
    local memoryAPI=UpdateAddOnMemoryUsage
    if type(memoryAPI)=="function" and type(GetAddOnMemoryUsage)=="function" then
        local ok,kb=pcall(function() memoryAPI(); return GetAddOnMemoryUsage(ADDON_NAME) end)
        kb=ok and SafeNumber(kb) or nil
        if kb then lines[#lines+1]=string.format("Reported addon memory: %.1f KiB (client estimate)",kb) end
    end
    for _,line in ipairs(errors) do lines[#lines+1]=line end
    return table.concat(lines,"\n")
end
local diagnosticPanel,refreshDiagnostic
local function OpenDiagnostics()
    if not diagnosticPanel then
        local panel=CreateFrame("Frame","RogueEnergySweepDiagnostics",UIParent,"BasicFrameTemplateWithInset")
        diagnosticPanel=panel
        panel:SetSize(580,410); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
        if panel.TitleText then panel.TitleText:SetText("Rogue Energy Sweep diagnostics") end
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=panel:GetName() end
        local hint=panel:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-32)
        hint:SetText("Select report, then Ctrl+C. Review before sharing.")
        local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-54)
        scroll:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-36,44)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(508); edit:SetHeight(330)
        edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnMouseDown",function() edit:SetFocus() end)
        local function Button(text,x,w,click)
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
            b:SetSize(w,24); b:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",x,12)
            b:SetText(text); b:SetScript("OnClick",click); return b
        end
        Button("Select report",16,114,function() edit:SetFocus(); edit:HighlightText() end)
        Button("Refresh",136,90,function() refreshDiagnostic() end)
        local profileButton
        profileButton=Button("Start sampling",232,146,function()
            if not SetProfiling(not performanceSample.enabled) then Say("Performance timer unavailable.") end
            refreshDiagnostic()
        end)
        Button("Close",466,90,function() panel:Hide() end)
        refreshDiagnostic=function()
            local report=DiagnosticReport()
            local _,newlines=report:gsub("\n","")
            edit:SetHeight(math.max(330,(newlines+1)*21+40))
            edit:SetText(report); edit:ClearFocus()
            scroll:SetVerticalScroll(0)
            profileButton:SetText(performanceSample.enabled and "Stop sampling" or "Start sampling")
        end
        panel:SetScript("OnHide",function() edit:ClearFocus() end)
    end
    diagnosticPanel:Show(); refreshDiagnostic()
end

local optionsPanel, settingsCategory, refreshPanel, refreshAbilityFilters, abilityFilters
local readyOptions,refreshReadyOptions
local function ApplySettings()
    SaveAppearance()
    if Tracker and Tracker.Sync(records,lastMaxEnergy) then RebuildGroups() end
    if Chains then Chains.Sync(records,lastMaxEnergy) end
    for _,record in pairs(overlays) do Style(record) end
    Update()
    if refreshPanel then refreshPanel() end
    if refreshAbilityFilters and abilityFilters and abilityFilters:IsShown() then refreshAbilityFilters() end
    if refreshReadyOptions and readyOptions and readyOptions:IsShown() then refreshReadyOptions() end
    if Options then Options.Refresh() end
end

-- Keep options availability separate from saved preferences.
local function StyleOptions(mode)
    return mode=="rising", mode=="rising" or mode=="bar" or mode=="perimeter"
end
local function SetControlAvailable(control,label,available)
    if available then control:Enable(); control:Show(); label:Show()
    else control:Disable(); control:Hide(); label:Hide() end
end

-- Positive distances from the top of the panel; use one shared layout so
-- controls and section boundaries can be checked together.
local OPTION_LAYOUT = {
    thickness=198, tint=240, fillEffect=274, progress=309, progressButtons=327, progressStatus=356,
    appearance=381, colors=399, colorLabel=427, opacity=427,
    preview=477, previewSliders=495, previewIcons=541, previewCosts=594, footer=654,
    sliderOffset=20, sliderHeight=16, buttonHeight=24
}

local function AbilityFilterEntries()
    local entries,seen={},{}
    local function Add(id,tracked,category)
        if not SafeNumber(id) or seen[id] then return end
        seen[id]=true
        local name,icon
        if C_Spell and C_Spell.GetSpellInfo then
            local ok,info=pcall(C_Spell.GetSpellInfo,id)
            if ok and not IsSecret(info) and type(info)=="table" then
                if not IsSecret(info.name) and type(info.name)=="string" then name=info.name end
                icon=SafeNumber(info.iconID)
            end
        end
        entries[#entries+1]={id=id,name=name or ("Spell "..id),icon=icon,tracked=tracked,category=category}
    end
    for _,record in ipairs(records) do if record.cost and record.cost>0 then Add(record.spellID,true,record.category) end end
    for id in pairs(DB.excludedSpells) do Add(id,false) end
    table.sort(entries,function(a,b) if a.name==b.name then return a.id<b.id end return a.name<b.name end)
    return entries
end

local function OpenAbilityFilters()
    if not abilityFilters then
        local panel=CreateFrame("Frame","RogueEnergySweepAbilityFilters",UIParent,"BasicFrameTemplateWithInset")
        abilityFilters=panel
        panel:SetSize(460,426); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
        panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart",function(self) self:StartMoving() end)
        panel:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        if panel.TitleText then panel.TitleText:SetText("Ability filters") end
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=panel:GetName() end
        local function Label(text,x,y,template)
            local f=panel:CreateFontString(nil,"ARTWORK",template or "GameFontHighlight")
            f:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); f:SetText(text); return f
        end
        local function Button(text,x,y,w,click)
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
            b:SetSize(w,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",click); return b
        end
        Label("Uncheck abilities to hide their energy effects.",16,-36)
        Label("Choose categories, then individual abilities below.",16,-55,"GameFontHighlightSmall")
        local categoryBoxes={}
        for i,entry in ipairs({{"builder","Builders"},{"finisher","Finishers"},{"other","Other / utility"}}) do
            local key,name=entry[1],entry[2]
            local x=16+(i-1)*140
            local box=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
            box:SetSize(24,24); box:SetPoint("TOPLEFT",panel,"TOPLEFT",x,-75)
            local label=Label(name,x+28,-81,"GameFontHighlightSmall")
            local hit=CreateFrame("Button",nil,panel)
            hit:SetPoint("TOPLEFT",label,"TOPLEFT",-2,3); hit:SetPoint("BOTTOMRIGHT",label,"BOTTOMRIGHT",3,-3)
            hit:SetScript("OnClick",function() box:Click() end)
            box:SetScript("OnClick",function(self) DB.showCategories[key]=self:GetChecked() and true or false; ApplySettings() end)
            categoryBoxes[key]=box
        end
        local page=1
        local pageLabel=Label("",190,-373,"GameFontHighlightSmall")
        local empty=Label("No energy abilities found. Put abilities on your bars.",16,-126,"GameFontHighlightSmall")
        local rows={}
        for i=1,8 do
            local y=-112-(i-1)*30
            local box=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
            box:SetSize(24,24); box:SetPoint("TOPLEFT",panel,"TOPLEFT",16,y)
            local icon=panel:CreateTexture(nil,"ARTWORK")
            icon:SetSize(22,22); icon:SetPoint("TOPLEFT",panel,"TOPLEFT",46,y-1)
            local label=Label("",76,y-5)
            local hit=CreateFrame("Button",nil,panel)
            hit:SetPoint("TOPLEFT",label,"TOPLEFT",-2,4); hit:SetPoint("BOTTOMRIGHT",label,"BOTTOMRIGHT",4,-4)
            hit:SetScript("OnClick",function() box:Click() end)
            local row={box=box,icon=icon,label=label,hit=hit}
            box:SetScript("OnClick",function(self)
                if row.id then
                    if self:GetChecked() then DB.excludedSpells[row.id]=nil else DB.excludedSpells[row.id]=true end
                    ApplySettings()
                end
            end)
            rows[i]=row
        end
        local prev=Button("Previous",16,-365,100,function() page=page-1; refreshAbilityFilters() end)
        local nextPage=Button("Next",344,-365,100,function() page=page+1; refreshAbilityFilters() end)
        Button("Reset filters",16,-394,140,function() DB.excludedSpells={}; DB.showCategories={builder=true,finisher=true,other=true}; ApplySettings() end)
        Button("Done",344,-394,100,function() panel:Hide() end)
        refreshAbilityFilters=function()
            local entries=AbilityFilterEntries()
            for key,box in pairs(categoryBoxes) do box:SetChecked(DB.showCategories[key]~=false) end
            local pages=math.max(1,math.ceil(#entries/#rows))
            page=math.max(1,math.min(page,pages))
            pageLabel:SetText(page.." / "..pages)
            if page>1 then prev:Enable() else prev:Disable() end
            if page<pages then nextPage:Enable() else nextPage:Disable() end
            if #entries==0 then empty:Show() else empty:Hide() end
            for i,row in ipairs(rows) do
                local entry=entries[(page-1)*#rows+i]
                row.id=entry and entry.id or nil
                if entry then
                    local categoryHidden=entry.category and DB.showCategories[entry.category]==false
                    row.box:SetChecked(not DB.excludedSpells[entry.id])
                    if categoryHidden then row.box:Disable(); row.hit:Disable() else row.box:Enable(); row.hit:Enable() end
                    row.icon:SetTexture(entry.icon or 134400)
                    row.label:SetText(entry.name..(not entry.tracked and " (not on bars)" or categoryHidden and " (category hidden)" or "").."  |cff999999#"..entry.id.."|r")
                    row.box:Show(); row.icon:Show(); row.label:Show(); row.hit:Show()
                else row.box:Hide(); row.icon:Hide(); row.label:Hide(); row.hit:Hide() end
            end
        end
        panel:SetScript("OnShow",refreshAbilityFilters)
    end
    abilityFilters:Show(); refreshAbilityFilters()
end

local function OpenReadyOptions()
    if not readyOptions then
        local panel=CreateFrame("Frame","RogueEnergySweepReadyOptions",UIParent,"BasicFrameTemplateWithInset")
        readyOptions=panel
        panel:SetSize(480,342); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
        if panel.TitleText then panel.TitleText:SetText("Energy ready effects") end
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=panel:GetName() end
        local function Label(text,x,y,template)
            local f=panel:CreateFontString(nil,"ARTWORK",template or "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); f:SetText(text); return f
        end
        local function Button(text,x,y,w,click)
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
            b:SetSize(w,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",click); return b
        end
        local function Check(text,x,y,click)
            local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
            b:SetSize(24,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y)
            local label=Label(text,x+28,y-6,"GameFontHighlight")
            local hit=CreateFrame("Button",nil,panel)
            hit:SetPoint("TOPLEFT",label,"TOPLEFT",-2,3); hit:SetPoint("BOTTOMRIGHT",label,"BOTTOMRIGHT",3,-3)
            hit:SetScript("OnClick",function() if b:IsEnabled() then b:Click() end end)
            b:SetScript("OnClick",function(self) click(self:GetChecked() and true or false); ApplySettings() end)
            b.label=label; b.hit=hit
            return b
        end
        Label("Show a separate effect when an ability has enough energy.",16,-36)
        Label("Respects enabled filters; energy-ready does not guarantee castability.",16,-53)
        local buttons={}
        local descriptions={
            none="No extra effect when energy is sufficient.",
            burst="Native expanding cast-completion ring (one-shot).",
            flash="Native cooldown-completion flipbook (one-shot).",
            proc="Native animated spell activation glow (while ready).",
            halo="Soft native proc halo (while ready).",
            border="Thin gold or colored outline (while ready).",
            pulse="Gently pulsing outline (while ready).",
            softflash="Short additive flash across the icon (one-shot)."
        }
        local sample=CreateFrame("Frame",nil,panel)
        sample:SetSize(56,56); sample:SetPoint("TOPLEFT",panel,"TOPLEFT",26,-247)
        sample.icon=sample:CreateTexture(nil,"BACKGROUND"); sample.icon:SetAllPoints(sample); sample.icon:SetTexture("Interface\\Icons\\Ability_Rogue_Eviscerate")
        local record=MakeOverlay(sample,true)
        local function Preview()
            ClearReady(record)
            SafeUpdateReady(record,0,true,true)
            SafeUpdateReady(record,1,true,true)
        end
        for i,entry in ipairs({{"none","None"},{"burst","Cast burst"},{"flash","Cooldown flash"},{"proc","Proc glow"},{"halo","Halo"},{"border","Border"},{"pulse","Pulse"},{"softflash","Soft flash"}}) do
            local key,name=entry[1],entry[2]
            buttons[key]=Button(name,16+((i-1)%4)*113,-75-math.floor((i-1)/4)*28,109,function()
                DB.readyEffect=key; ApplySettings(); Preview()
            end)
        end
        local description=Label("",16,-134)
        local match=Check("Match indicator color",16,-153,function(v) DB.readyMatchColor=v; Preview() end)
        local fallback=Check("Pulse if a one-shot trigger is protected",16,-178,function(v) DB.readyFallback=v end)
        Label("The one-shot animation needs a readable transition.",44,-204)
        local opacityText=Label("",240,-153)
        local syncing=false
        local slider=CreateFrame("Slider","RogueEnergySweepReadyOpacitySlider",panel,"OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT",panel,"TOPLEFT",240,-172); slider:SetSize(220,16)
        -- Keep the intensity slider away from the long fallback label.
        slider:ClearAllPoints(); slider:SetPoint("TOPLEFT",panel,"TOPLEFT",240,-233)
        opacityText:ClearAllPoints(); opacityText:SetPoint("TOPLEFT",panel,"TOPLEFT",240,-215)
        for _,suffix in ipairs({"Text","Low","High"}) do local l=_G["RogueEnergySweepReadyOpacitySlider"..suffix]; if l then l:SetText("") end end
        slider:SetMinMaxValues(15,100); slider:SetValueStep(5)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider:SetScript("OnValueChanged",function(_,v)
            if not syncing then DB.readyOpacity=math.floor(v+.5)/100; ApplySettings(); Preview() end
        end)
        Button("Preview",100,-258,110,Preview)
        Button("Done",350,-300,110,function() panel:Hide() end)
        Label("Preview only; no spell is cast.",100,-286)
        refreshReadyOptions=function()
            syncing=true
            for key,b in pairs(buttons) do
                if b.LockHighlight and b.UnlockHighlight then
                    if DB.readyEffect==key then b:LockHighlight() else b:UnlockHighlight() end
                end
            end
            description:SetText(descriptions[DB.readyEffect] or "")
            match:SetChecked(DB.readyMatchColor); fallback:SetChecked(DB.readyFallback)
            local can=READY_ONESHOT[DB.readyEffect]==true
            if can then fallback:Enable(); fallback.hit:Enable(); fallback.label:SetTextColor(1,1,1)
            else fallback:Disable(); fallback.hit:Disable(); fallback.label:SetTextColor(.5,.5,.5) end
            slider:SetValue(DB.readyOpacity*100)
            opacityText:SetText(string.format("Effect intensity: %d%%",math.floor(DB.readyOpacity*100+.5)))
            syncing=false
        end
        panel:SetScript("OnHide",function() ClearReady(record) end)
    end
    readyOptions:Show(); refreshReadyOptions()
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
        local label=Label(text,x+28,y-6,"GameFontHighlight")
        b:SetScript("OnClick",function(self) click(self:GetChecked() and true or false); ApplySettings() end)
        -- The label is also a click target.
        local hit=CreateFrame("Button",nil,panel)
        hit:SetPoint("TOPLEFT",label,"TOPLEFT",-2,3)
        hit:SetPoint("BOTTOMRIGHT",label,"BOTTOMRIGHT",3,-3)
        hit:SetScript("OnClick",function() if b:IsEnabled() then b:Click() end end)
        b.optionLabelHit=hit
        return b,label
    end
    local layout=OPTION_LAYOUT
    local function Section(text,y)
        local heading=Label(text,16,y,"GameFontNormal")
        local line=panel:CreateTexture(nil,"ARTWORK")
        -- Align the divider with its heading, not with the previous control.
        line:SetPoint("LEFT",heading,"RIGHT",12,0)
        line:SetPoint("RIGHT",panel,"TOPLEFT",444,y-6)
        line:SetHeight(1); line:SetColorTexture(0.52,0.45,0.30,0.45)
        return heading
    end
    local function SelectButton(b,selected)
        if b.LockHighlight and b.UnlockHighlight then
            b:Enable()
            if selected then b:LockHighlight() else b:UnlockHighlight() end
        elseif selected then b:Disable() else b:Enable() end
    end
    Label("Rogue Energy Sweep",16,-12,"GameFontNormalLarge")
    Label("Customize energy readiness on your action bars.",16,-32,"GameFontHighlightSmall")
    Section("Behavior", -52)
    local enabled=Check("Enable overlays",16,-68,function(v) DB.enabled=v; if v then RequestScan() end end)
    local combat=Check("Only in combat",225,-68,function(v) DB.combatOnly=v end)
    local comboOnly=Check("Finishers only with combo points on target",16,-91,function(v) DB.finisherComboOnly=v end)
    local cooldownOnly=Check("Hide on cooldown (ignore GCD)",16,-116,function(v) DB.hideCooldowns=v end)
    local filtersButton=Button("Ability filters...",324,-116,120,OpenAbilityFilters)
    Section("Animation style", -150)
    local modes={}
    for i,entry in ipairs({{"rising","Rising line"},{"bar","Bottom bar"},{"perimeter","Perimeter"},{"radial","Radial sweep"}}) do
        local key,text=entry[1],entry[2]
        modes[key]=Button(text,16+(i-1)*110,-168,106,function() if SetStyle(key) then ApplySettings() end end)
    end
    Section("Progress mode", -layout.progress)
    local progressButtons={}
    progressButtons.energy=Button("Energy-based",16,-layout.progressButtons,132,function() SetProgress("energy"); ApplySettings() end)
    progressButtons.countdown=Button("Countdown",156,-layout.progressButtons,132,function() SetProgress("countdown"); ApplySettings() end)
    local readyButton=Button("Ready effects...",300,-layout.progressButtons,144,OpenReadyOptions)
    if Tracker then Button("Energy Tracker...",304,-18,140,function() Tracker.Open() end) end
    if Chains then Button("Ability Chains...",304,-(layout.previewCosts+8),140,function() Chains.Open() end) end
    local gcdAware=Check("Account for global cooldown regeneration",16,-(layout.previewCosts+31),function(v) DB.gcdAware=v end)
    local liveStatus=Label("Countdown starts after spending energy (experimental).",16,-layout.progressStatus,"GameFontHighlightSmall")
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
    Section("Appearance", -layout.appearance)
    local colors,selectedMarks={},{}
    for i,entry in ipairs(PRESETS) do
        local key,name=entry[1],entry[2]
        local b=Button("",16+(i-1)*35,-layout.colors,32,function() DB.color=key; ApplySettings() end)
        colors[key]=b
        local swatch=b:CreateTexture(nil,"ARTWORK")
        swatch:SetPoint("TOPLEFT",b,"TOPLEFT",5,-4)
        swatch:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-5,4)
        local c=COLORS[key]
        swatch:SetColorTexture(c[1],c[2],c[3],1)
        local mark=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        mark:SetPoint("CENTER",b,"CENTER",0,0); mark:SetText("*")
        local contrast=(key=="white" or key=="amber" or key=="cyan" or key=="green" or key=="orange") and 0 or 1
        mark:SetTextColor(contrast,contrast,contrast)
        selectedMarks[key]=mark
        b:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:SetText(name.." "..ColorHex(c))
            if key=="black" then GameTooltip:AddLine("Black preset: white for linear styles.",1,1,1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    local custom=Button("Custom...",304,-layout.colors,140,function()
        if not OpenCustomColorPicker(ApplySettings) then Say("Color picker unavailable. Use /resweep color #RRGGBB.") end
    end)
    local customSwatch=custom:CreateTexture(nil,"OVERLAY")
    customSwatch:SetSize(13,13); customSwatch:SetPoint("LEFT",custom,"LEFT",10,0)
    local colorLabel=Label("",16,-layout.colorLabel,"GameFontHighlightSmall")
    local function Slider(name,x,y,low,high,step,callback)
        local label=Label(name,x,y)
        local sliderName="RogueEnergySweep"..name.."Slider"
        local slider=CreateFrame("Slider",sliderName,panel,"OptionsSliderTemplate")
        for _,suffix in ipairs({"Text","Low","High"}) do local f=_G[sliderName..suffix]; if f then f:SetText("") end end
        slider:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y-layout.sliderOffset); slider:SetSize(180,layout.sliderHeight)
        slider:SetMinMaxValues(low,high); slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider:SetScript("OnValueChanged",function(_,v) callback(math.floor(v+0.5)) end)
        return slider,label
    end
    local syncing=false
    local opacity,opacityLabel=Slider("Opacity",240,-layout.opacity,15,100,5,function(v) if not syncing then DB.opacity=v/100; ApplySettings() end end)
    -- Style-specific settings live immediately below the style selector.
    local thickness,thicknessLabel=Slider("Thickness",16,-layout.thickness,2,8,1,function(v)
        local _,available=StyleOptions(DB.mode)
        if not syncing and available then DB.thickness=v; ApplySettings() end
    end)
    local tint,tintLabel=Check("Tint filled area",16,-layout.tint,function(v)
        if DB.mode=="rising" then DB.tint=v end
    end)
    local tintOpacity,tintOpacityLabel=Slider("TintOpacity",240,-(layout.tint-8),0,100,5,function(v)
        if not syncing and DB.mode=="rising" and DB.tint then DB.tintOpacity=v/100; ApplySettings() end
    end)
    local direction=Button("Reverse direction",240,-layout.thickness,204,function() DB.reverse=not DB.reverse; ApplySettings() end)
    Button("Reset style",16,-(layout.opacity+18),120,function() ResetAppearance(); ApplySettings() end)
    local fillLabel=Label("Fill effect",16,-(layout.fillEffect+5),"GameFontHighlightSmall")
    local fillButtons={}
    for i,entry in ipairs({{"solid","Solid"},{"gradient","Gradient"},{"luminous","Luminous"}}) do
        local key,name=entry[1],entry[2]
        fillButtons[key]=Button(name,112+(i-1)*110,-layout.fillEffect,106,function()
            if DB.mode=="rising" and DB.tint then DB.fillEffect=key; ApplySettings() end
        end)
    end
    local radialHint=Label("Radial sweep uses color and opacity below.",16,-206,"GameFontHighlightSmall")
    Section("Preview", -layout.preview)
    local previewEnergy=15
    local previewRecords={}
    local previewStart=15
    local previewPlaying=false
    local playButton, refreshPreview
    local function StopPreview()
        previewPlaying=false; panel:SetScript("OnUpdate",nil)
        if playButton then playButton:SetText("Animate") end
    end
    local previewSlider,previewLabel=Slider("Energy",16,-layout.previewSliders,0,100,1,function(v) if not syncing then StopPreview(); previewEnergy=v; if refreshPreview then refreshPreview() end end end)
    local previewStartSlider,previewStartLabel=Slider("StartEnergy",240,-layout.previewSliders,0,100,1,function(v) if not syncing then StopPreview(); previewStart=v; if refreshPreview then refreshPreview() end end end)
    for i,entry in ipairs({{45,"Interface\\Icons\\Spell_Shadow_RitualOfSacrifice"},{35,"Interface\\Icons\\Ability_Rogue_Eviscerate"},{25,"Interface\\Icons\\Ability_Kick"}}) do
        local button=CreateFrame("Frame",nil,panel)
        button:SetSize(48,48); button:SetPoint("TOPLEFT",panel,"TOPLEFT",16+(i-1)*82,-layout.previewIcons)
        button.icon=button:CreateTexture(nil,"BACKGROUND"); button.icon:SetAllPoints(button); button.icon:SetTexture(entry[2])
        local record=MakeOverlay(button,true)
        record.previewCost=entry[1]; previewRecords[#previewRecords+1]=record
        Label(tostring(entry[1]).." energy",16+(i-1)*82,-layout.previewCosts,"GameFontHighlightSmall")
    end
    playButton=Button("Animate",240,-layout.previewIcons,80,function()
        if previewPlaying then StopPreview(); return end
        previewEnergy=DB.progress=="countdown" and previewStart or 0
        previewPlaying=true; playButton:SetText("Stop")
        if refreshPreview then refreshPreview() end
        local accumulated=0
        panel:SetScript("OnUpdate",function(_,elapsed)
            accumulated=accumulated+elapsed
            if accumulated<.033 then return end
            previewEnergy=math.min(100,previewEnergy+accumulated*10); accumulated=0
            refreshPreview()
            if previewEnergy>=100 then StopPreview() end
        end)
    end)
    Button("Test on bars",324,-layout.previewIcons,120,function() SlashCmdList.ROGUEENERGYSWEEP("demo") end)
    Button("Diagnostics",240,-(layout.previewIcons+30),80,function() SlashCmdList.ROGUEENERGYSWEEP("diagnostics") end)
    Button("Reset all",324,-(layout.previewIcons+30),120,function()
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs.ROGUEENERGYSWEEP_RESET={text="Reset all Rogue Energy Sweep settings?",button1="Reset",button2="Cancel",OnAccept=function() SlashCmdList.ROGUEENERGYSWEEP("reset") end,timeout=0,whileDead=true,hideOnEscape=true}
            StaticPopup_Show("ROGUEENERGYSWEEP_RESET")
        else Say("Use /resweep reset to confirm resetting all settings.") end
    end)
    refreshPreview=function()
        local wasSyncing=syncing; syncing=true
        previewSlider:SetValue(math.floor(previewEnergy+.5)); previewStartSlider:SetValue(previewStart)
        previewLabel:SetText(string.format("Energy: %d / 100",math.floor(previewEnergy+.5)))
        previewStartLabel:SetText(string.format("Post-spend start: %d",previewStart))
        for _,record in ipairs(previewRecords) do
            local fill=math.min(1,previewEnergy/record.previewCost)
            if DB.progress=="countdown" then
                local start=math.min(previewStart,record.previewCost-0.001)
                fill=math.max(0,math.min(1,(previewEnergy-start)/(record.previewCost-start)))
            end
            Paint(record,fill,1-fill,previewEnergy<record.previewCost and 1 or 0)
            SafeUpdateReady(record,previewEnergy>=record.previewCost and 1 or 0,true,true)
        end
        syncing=wasSyncing
    end
    refreshPanel=function()
        refreshLiveStatus()
        syncing=true
        gcdAware:SetChecked(DB.gcdAware==true)
        enabled:SetChecked(DB.enabled); combat:SetChecked(DB.combatOnly); tint:SetChecked(DB.tint); comboOnly:SetChecked(DB.finisherComboOnly); cooldownOnly:SetChecked(DB.hideCooldowns)
        local excludedCount=0; for _ in pairs(DB.excludedSpells) do excludedCount=excludedCount+1 end
        local categoryCount=0; for _,key in ipairs({"builder","finisher","other"}) do if not DB.showCategories[key] then categoryCount=categoryCount+1 end end
        local totalFilters=excludedCount+categoryCount
        filtersButton:SetText(totalFilters>0 and ("Filters ("..totalFilters..")...") or "Ability filters...")
        for key,b in pairs(modes) do SelectButton(b,key==DB.mode) end
        for key,b in pairs(progressButtons) do SelectButton(b,key==DB.progress) end
        readyButton:SetText(DB.readyEffect=="none" and "Ready effects..." or ("Ready: "..DB.readyEffect.."..."))
        local tintAvailable,thicknessAvailable=StyleOptions(DB.mode)
        SetControlAvailable(tint,tintLabel,tintAvailable)
        if tintAvailable then tint.optionLabelHit:Show() else tint.optionLabelHit:Hide() end
        SetControlAvailable(thickness,thicknessLabel,thicknessAvailable)
        if thicknessAvailable then radialHint:Hide() else radialHint:Show() end
        SetControlAvailable(tintOpacity,tintOpacityLabel,tintAvailable and DB.tint)
        local showFill=tintAvailable and DB.tint
        if showFill then fillLabel:Show() else fillLabel:Hide() end
        for key,b in pairs(fillButtons) do
            if showFill then b:Show(); SelectButton(b,key==DB.fillEffect) else b:Hide(); b:Disable() end
        end
        tintOpacity:SetValue(DB.tintOpacity*100)
        tintOpacityLabel:SetText(string.format("Tint opacity: %d%%",math.floor(DB.tintOpacity*100+.5)))
        direction:Enable()
        if direction.LockHighlight and direction.UnlockHighlight then
            if DB.reverse then direction:LockHighlight() else direction:UnlockHighlight() end
        end
        direction:SetText(DB.reverse and "Direction: reversed" or "Direction: default")
        for key,b in pairs(colors) do
            if key==DB.color then selectedMarks[key]:Show() else selectedMarks[key]:Hide() end
        end
        local c=ResolveColor()
        customSwatch:SetColorTexture(c[1],c[2],c[3],1)
        local name="Custom"
        for _,entry in ipairs(PRESETS) do if entry[1]==DB.color then name=entry[2] end end
        colorLabel:SetText(name.."  "..ColorHex(c)..(DB.color=="black" and "  (linear styles use white)" or ""))
        opacity:SetValue(DB.opacity*100); thickness:SetValue(DB.thickness)
        opacityLabel:SetText(string.format("Opacity: %d%%",math.floor(DB.opacity*100+0.5)))
        thicknessLabel:SetText(string.format("%s thickness: %d px",DB.mode=="bar" and "Bar" or DB.mode=="perimeter" and "Border" or "Line",DB.thickness))
        SetControlAvailable(previewStartSlider,previewStartLabel,DB.progress=="countdown")
        for _,record in ipairs(previewRecords) do Style(record) end
        refreshPreview()
        syncing=false
    end
    panel:SetScript("OnShow",refreshPanel)
    panel:SetScript("OnHide",function() StopPreview(); if abilityFilters then abilityFilters:Hide() end; if readyOptions then readyOptions:Hide() end; for _,record in ipairs(previewRecords) do ClearReady(record) end end)
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
    Say("/resweep options | status | demo | on | off | rescan | combat | finishers on/off | cooldowns on/off | filters | diagnostics | profile on/off | opacity 90 | color preset/#RRGGBB | mode rising/bar/perimeter/radial | progress energy/countdown | thickness 4 | reverse | tintopacity 15 | fill solid/gradient/luminous | ready none/burst/flash/proc/halo/border/pulse/softflash | tracker | chains | gcd on/off | resetstyle | reset")
end
SLASH_ROGUEENERGYSWEEP1 = "/resweep"
SlashCmdList.ROGUEENERGYSWEEP = function(msg)
    if not DB then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "options" then if Options and Options.Open("bars") then return end; OpenOptions(); return
    elseif cmd=="legacy" then OpenOptions(); return
    elseif cmd == "status" then Status(); return
    elseif cmd == "filters" then if Options and Options.Open("bars","filters") then return end; OpenAbilityFilters(); return
    elseif cmd == "diagnostics" then OpenDiagnostics(); return
    elseif cmd=="gcd" then
        if arg=="on" then DB.gcdAware=true elseif arg=="off" then DB.gcdAware=false else Help(); return end
    elseif cmd=="chains" and Chains then
        if arg=="" then if Options and Options.Open("planning") then return end; Chains.Open(); return end
        if not Chains.Command(arg) then Help(); return end
    elseif cmd=="tracker" and Tracker then
        if arg=="" then if Options and Options.Open("hud") then return end; Tracker.Open(); return end
        if not Tracker.Command(arg) then Help(); return end
    elseif cmd=="ready" then
        if arg=="" then if Options and Options.Open("bars","ready") then return end; OpenReadyOptions(); return end
        if not READY_EFFECTS[arg] then Help(); return end
        DB.readyEffect=arg
    elseif cmd == "profile" and (arg=="on" or arg=="off") then
        if SetProfiling(arg=="on") then Say("Update profiling: "..arg) else Say("Performance timer unavailable.") end
        return
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
    elseif cmd == "finishers" and (arg=="on" or arg=="off" or arg=="") then
        if arg=="" then DB.finisherComboOnly=not DB.finisherComboOnly else DB.finisherComboOnly=arg=="on" end
        Say("Finishers require target combo points: "..tostring(DB.finisherComboOnly))
    elseif cmd=="cooldowns" and (arg=="on" or arg=="off" or arg=="") then
        if arg=="" then DB.hideCooldowns=not DB.hideCooldowns else DB.hideCooldowns=arg=="on" end
        Say("Hide on cooldown: "..tostring(DB.hideCooldowns))
    elseif cmd == "opacity" and tonumber(arg) then DB.opacity = math.max(0.15, math.min(1.00, tonumber(arg)/100))
    elseif cmd == "color" then
        if COLORS[arg] then DB.color=arg
        elseif arg=="gold" then DB.color="amber"
        elseif not SetColorHex(arg) then Say("Choose amber, white, cyan, green, red, purple, orange, black or #RRGGBB."); return end
    elseif cmd == "mode" and MODES[arg] then SetStyle(arg)
    elseif cmd == "progress" and (arg == "energy" or arg == "countdown") then SetProgress(arg)
    elseif cmd == "reverse" then DB.reverse=not DB.reverse
    elseif cmd == "tintopacity" and tonumber(arg) then DB.tintOpacity=math.max(0,math.min(100,tonumber(arg)))/100
    elseif cmd=="fill" and FILL_EFFECTS[arg] then
        if DB.mode~="rising" then Say("Fill effects apply to Rising Line only."); return end
        DB.fillEffect=arg
    elseif cmd == "resetstyle" then ResetAppearance()
    elseif cmd == "thickness" and tonumber(arg) then DB.thickness = math.floor(math.max(2,math.min(8,tonumber(arg)))+0.5)
    elseif cmd == "reset" then RogueEnergySweepDB = {}; InitDB(); ResetProgress(); lastError = "none"; RequestScan()
    else Help(); return end
    ApplySettings()
end

-- Appearance-only proxy: the tracker reuses the exact native icon renderer
-- without modifying saved action-bar settings or changing the shared progress state.
if Tracker then
    local function WithTrackerAppearance(fn,...)
        local original=DB
        local appearance=Tracker.Appearance()
        DB=setmetatable(appearance,{__index=original})
        local ok,a,b=pcall(fn,...)
        DB=original
        if not ok then error(a) end
        return a,b
    end
    Tracker.Configure({
        safe=SafeNumber,secret=IsSecret,excluded=IsExcluded,
        curve=MakeCurve,evaluate=Evaluate,cooldown=CooldownAlpha,
        make=function(button) return WithTrackerAppearance(MakeOverlay,button,true) end,
        style=function(record) return WithTrackerAppearance(Style,record) end,
        paint=function(record,fill,deficit,visibility,group,direct)
            if direct and WithTrackerAppearance(PaintDirect,record,fill,deficit,visibility,group) then return true end
            return WithTrackerAppearance(Paint,record,fill,deficit,visibility)
        end,
        clear=Clear,clearReady=ClearReady,
        ready=function(record,alpha,eligible) return WithTrackerAppearance(SafeUpdateReady,record,alpha,eligible,false) end,
        apply=ApplySettings,update=Update,
        cost=GetEnergyCost,category=SpellCategory,
        say=Say,
        project=function(...) if GCD then return GCD.Project(...) end end,
        gcdGate=function(record,alpha) if GCD then GCD.Apply(record,alpha) end end,
    })
end
if Chains then Chains.Configure({safe=SafeNumber,secret=IsSecret,excluded=IsExcluded,evaluate=Evaluate,apply=ApplySettings}) end
if GCD then GCD.Configure({safe=SafeNumber,secret=IsSecret,evaluate=Evaluate}) end
if Options then Options.Configure({
    db=function() return DB end, apply=ApplySettings, scan=RequestScan, say=Say,
    style=SetStyle, progress=SetProgress, resetStyle=ResetAppearance, color=ResolveColor,
    presets=PRESETS, colors=COLORS, custom=function() return OpenCustomColorPicker(ApplySettings) end,
    filters=AbilityFilterEntries, excluded=IsExcluded, diagnostic=OpenDiagnostics,
    status=ProgressSummary, profile=SetProfiling, profiling=function() return performanceSample.enabled end,
    command=function(text) SlashCmdList.ROGUEENERGYSWEEP(text) end,
    previewMake=function(parent)
        local result={}
        for i,e in ipairs({{45,"Interface\\Icons\\Spell_Shadow_RitualOfSacrifice"},{35,"Interface\\Icons\\Ability_Rogue_Eviscerate"},{25,"Interface\\Icons\\Ability_Kick"}}) do
            local button=CreateFrame("Frame",nil,parent); button:SetSize(42,42); button:SetPoint("TOPLEFT",parent,"TOPLEFT",20+(i-1)*79,-6)
            button.icon=button:CreateTexture(nil,"BACKGROUND"); button.icon:SetAllPoints(button); button.icon:SetTexture(e[2])
            local rec=MakeOverlay(button,true); rec.previewCost=e[1]; result[#result+1]=rec
            local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); label:SetPoint("TOP",button,"BOTTOM",0,-4); label:SetText(e[1].." energy")
        end
        return result
    end,
    previewPaint=function(list,energy,start)
        for _,rec in ipairs(list) do
            local cost=rec.previewCost; local fill=math.min(1,energy/cost)
            if DB.progress=="countdown" then local low=math.min(start,cost-.001); fill=math.max(0,math.min(1,(energy-low)/(cost-low))) end
            Style(rec); Paint(rec,fill,1-fill,energy<cost and 1 or 0); SafeUpdateReady(rec,energy>=cost and 1 or 0,true,true)
        end
    end,
    previewClear=function(list) for _,rec in ipairs(list) do ClearReady(rec); Clear(rec) end end,
}) end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
    "ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","SPELLS_CHANGED","PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_TALENT_UPDATE","ACTIVE_TALENT_GROUP_CHANGED","UPDATE_SHAPESHIFT_FORM","UPDATE_STEALTH","PLAYER_TARGET_CHANGED","COMBO_TARGET_CHANGED","UNIT_COMBO_POINTS","SPELL_UPDATE_COOLDOWN","ACTIONBAR_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES","SPELL_UPDATE_USABLE"}) do
    pcall(events.RegisterEvent, events, event)
end
for _, event in ipairs({"UNIT_POWER_FREQUENT","UNIT_POWER_UPDATE","UNIT_MAXPOWER","UNIT_AURA","UNIT_SPELLCAST_SUCCEEDED"}) do
    pcall(events.RegisterUnitEvent, events, event, "player")
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then InitDB(); local ok,err=pcall(function() if Options then Options.Register() else CreateOptions() end end); if not ok then ErrorNote(err); Say("Options initialization failed; use /resweep options or /resweep legacy.") end
        elseif DB and (name == "Bartender4" or name == "Dominos" or name == "ElvUI") then RequestScan() end
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then CheckCompatibility(true); CheckBuild(true); RequestScan()
    elseif event=="SPELL_UPDATE_USABLE" then
        if DB.enabled and READY_ONESHOT[DB.readyEffect] then RequestUpdate() end
    elseif event=="SPELL_UPDATE_COOLDOWN" or event=="ACTIONBAR_UPDATE_COOLDOWN" or event=="SPELL_UPDATE_CHARGES" then
        if event=="SPELL_UPDATE_COOLDOWN" and GCD then GCD.CooldownEvent(records) end
        if DB.enabled and (DB.hideCooldowns or DB.gcdAware) then RequestUpdate() end
    elseif event=="PLAYER_TARGET_CHANGED" or event=="COMBO_TARGET_CHANGED" or event=="UNIT_COMBO_POINTS" then
        if DB.enabled and DB.finisherComboOnly then RequestUpdate() end
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        local unit, power = ...
        if DB.enabled and not IsSecret(unit) and unit == "player" and not IsSecret(power) and (power == "ENERGY" or (DB.finisherComboOnly and power=="COMBO_POINTS")) then RequestUpdate() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if DB.enabled and DB.gcdAware and GCD and not IsSecret(unit) and unit=="player" then
            GCD.Cast(SafeNumber(spellID)); RequestUpdate()
            -- Expiry refresh even if no energy event occurs (e.g. at cap).
            C_Timer.After(1.05,function() if DB and DB.enabled and DB.gcdAware then RequestUpdate() end end)
        end
        if DB.enabled and DB.finisherComboOnly and not IsSecret(unit) and unit=="player" then RequestUpdate() end
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
        if Chains then Chains.Sync(records,lastMaxEnergy) end
        Update()
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_STEALTH" then RequestBindings()
    elseif event == "SPELLS_CHANGED" then RequestBindings(); RequestScan() end
end)
