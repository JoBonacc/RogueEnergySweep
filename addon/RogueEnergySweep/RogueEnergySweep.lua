-- Rogue Energy Sweep 0.1.0 (WoW Forever)
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
local demo = false
local demoGeneration = 0
local lastSource, lastError = "not evaluated", "none"
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

local function InitDB()
    if type(RogueEnergySweepDB) ~= "table" then RogueEnergySweepDB = {} end
    DB = RogueEnergySweepDB
    if type(DB.enabled) ~= "boolean" then DB.enabled = true end
    DB.combatOnly = DB.combatOnly == true
    if DB.mode ~= "bar" and DB.mode ~= "radial" then DB.mode = "auto" end
    if DB.color ~= "black" then DB.color = "amber" end
    DB.opacity = math.max(0.15, math.min(0.90, SafeNumber(DB.opacity) or 0.65))
end

local function RefreshMaxEnergy()
    if type(UnitPowerMax) ~= "function" then return end
    local ok, result = pcall(UnitPowerMax, "player", ENERGY)
    local value = ok and SafeNumber(result) or nil
    if value and value > 0 then lastMaxEnergy = value end
end

-- x = energy / maximum energy; y = fraction of ability cost still missing.
-- The native evaluator can consume a secret resource and return a secret result.
local function MakeCurve(cost)
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil end
    local ok, curve = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
            c:SetType(Enum.LuaCurveType.Linear)
        end
        local threshold = math.min(1, cost / lastMaxEnergy)
        c:AddPoint(0, 1)
        c:AddPoint(threshold, math.max(0, 1 - lastMaxEnergy / cost))
        if threshold < 1 then c:AddPoint(1, 0) end
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
                return cost, true
            end
        end
    end

    return nil, false
end

local function Clear(record)
    record.radial:Hide()
    record.bar:Hide()
    record.mode = nil
end

local function ClearAll()
    for _, record in pairs(overlays) do Clear(record) end
end

local function Style(record)
    local r, g, b = 0.29, 0.16, 0.025
    if DB.color == "black" then r, g, b = 0, 0, 0 end
    record.radial:SetVertexColor(r, g, b, DB.opacity)
    -- Thin gold deficit bar is intentionally distinct from the cooldown swipe.
    record.bar:SetStatusBarColor(1, 0.67, 0.14, DB.opacity)
end

local function MakeOverlay(button)
    if overlays[button] then return overlays[button] end
    local frame = CreateFrame("Frame", nil, button)
    local icon = button.icon or button.Icon
    if not icon or IsSecret(icon) or not pcall(frame.SetAllPoints, frame, icon) then
        frame:ClearAllPoints()
        frame:SetAllPoints(button)
    end
    frame:EnableMouse(false)
    frame:SetFrameLevel(button:GetFrameLevel() + 1)
    local radial = frame:CreateTexture(nil, "ARTWORK")
    radial:SetAllPoints(frame)
    radial:SetTexture("Interface\\Buttons\\WHITE8X8")
    local native = type(radial.SetRadialProgressBarPercent) == "function"
    if native then
        -- Full circle. The documented default origin is six o'clock.
        if radial.SetRadialProgressBarReverse then pcall(radial.SetRadialProgressBarReverse, radial, true) end
        native = pcall(radial.SetRadialProgressBarPercent, radial, 0)
    end
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:EnableMouse(false)
    bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    bar:SetHeight(4)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    if bar.SetReverseFill then bar:SetReverseFill(true) end
    local record = {button=button, frame=frame, radial=radial, bar=bar, native=native}
    overlays[button] = record
    Style(record)
    Clear(record)
    return record
end

local function RebuildGroups()
    wipe(groups)
    ClearAll()
    for _, record in ipairs(records) do
        local cost = record.cost
        if cost and cost > 0 then
            local group = groups[cost]
            if not group then
                group = {curve=MakeCurve(cost), records={}}
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

local function Paint(record, value)
    -- Never compare/branch on protected power or on a widget's secret properties.
    if DB.mode ~= "bar" and record.native then
        local ok, err = pcall(record.radial.SetRadialProgressBarPercent, record.radial, value)
        if ok then
            if record.mode ~= "radial" then record.bar:Hide(); record.radial:Show(); record.mode = "radial" end
            return
        end
        ErrorNote(err)
    end
    if DB.mode ~= "radial" then
        local ok, err = pcall(record.bar.SetValue, record.bar, value)
        if ok then
            if record.mode ~= "bar" then record.radial:Hide(); record.bar:Show(); record.mode = "bar" end
            return
        end
        ErrorNote(err)
    end
    Clear(record)
end

local function Update()
    updatePending = false
    if not DB or not DB.enabled or (DB.combatOnly and not InCombatLockdown() and not demo) then
        ClearAll(); return
    end
    local publicEnergy, triedPublic = nil, false
    lastSource = "no tracked energy abilities"
    for cost, group in pairs(groups) do
        local value, valid
        if demo then
            value, valid, lastSource = 0.5, true, "demo (50%)"
        elseif group.curve and type(UnitPowerPercent) == "function" then
            local ok, result = pcall(UnitPowerPercent, "player", ENERGY, false, group.curve)
            if ok then
                if IsSecret(result) then value, valid, lastSource = result, true, "native curve (secret)"
                elseif SafeNumber(result) then value, valid, lastSource = result, true, "native curve (public)" end
            else ErrorNote(result) end
        end
        if not valid and not demo then
            if not triedPublic then
                triedPublic = true
                if type(UnitPower) == "function" then
                    local ok, result = pcall(UnitPower, "player", ENERGY)
                    if ok then publicEnergy = SafeNumber(result) end
                end
            end
            if publicEnergy then
                value = math.max(0, math.min(1, (cost-publicEnergy)/cost))
                valid, lastSource = true, "public energy fallback"
            end
        end
        for _, record in ipairs(group.records) do
            if valid then Paint(record, value) else Clear(record); lastSource = "energy unavailable" end
        end
    end
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

local function Status()
    local count, radial, bar, native = 0,0,0,0
    for _, record in ipairs(records) do
        if record.cost and record.cost > 0 then
            count = count + 1
            if record.native then native = native + 1 end
            if record.mode == "radial" then radial = radial + 1 end
            if record.mode == "bar" then bar = bar + 1 end
        end
    end
    Say(string.format("v0.1.0 | %d energy buttons | %d radial-capable | %d radial / %d bar active", count, native, radial, bar))
    Say("source: " .. lastSource .. " | max energy used: " .. lastMaxEnergy .. " | mode: " .. DB.mode)
    Say("last API error: " .. lastError)
end
local function Help()
    Say("/resweep status | demo | on | off | rescan | combat | opacity 65 | color amber/black | mode auto/radial/bar | reset")
end
SLASH_ROGUEENERGYSWEEP1 = "/resweep"
SlashCmdList.ROGUEENERGYSWEEP = function(msg)
    if not DB then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "status" then Status(); return
    elseif cmd == "demo" then
        if not DB.enabled then Say("Enable the addon first with /resweep on."); return end
        if InCombatLockdown() then Say("Demo is available out of combat only."); return end
        demo = true; demoGeneration = demoGeneration + 1
        local generation = demoGeneration
        Update(); Say("Showing a 50% deficit for five seconds.")
        C_Timer.After(5, function() if generation == demoGeneration then demo = false; Update() end end)
        return
    elseif cmd == "on" then DB.enabled = true; RequestScan()
    elseif cmd == "off" then DB.enabled = false; demo = false
    elseif cmd == "rescan" then RequestScan(); Say(InCombatLockdown() and "Rescan deferred until combat ends." or "Rescan requested."); return
    elseif cmd == "combat" then DB.combatOnly = not DB.combatOnly; Say("Combat only: " .. tostring(DB.combatOnly))
    elseif cmd == "opacity" and tonumber(arg) then DB.opacity = math.max(0.15, math.min(0.90, tonumber(arg)/100))
    elseif cmd == "color" and (arg == "amber" or arg == "black") then DB.color = arg
    elseif cmd == "mode" and (arg == "auto" or arg == "radial" or arg == "bar") then DB.mode = arg
    elseif cmd == "reset" then RogueEnergySweepDB = {}; InitDB(); lastError = "none"; RequestScan()
    else Help(); return end
    for _, record in pairs(overlays) do Style(record) end
    Update()
end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
    "ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","SPELLS_CHANGED","PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_TALENT_UPDATE","ACTIVE_TALENT_GROUP_CHANGED","UPDATE_SHAPESHIFT_FORM","UPDATE_STEALTH"}) do
    pcall(events.RegisterEvent, events, event)
end
for _, event in ipairs({"UNIT_POWER_FREQUENT","UNIT_POWER_UPDATE","UNIT_MAXPOWER","UNIT_AURA"}) do
    pcall(events.RegisterUnitEvent, events, event, "player")
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then InitDB()
        elseif DB and (name == "Bartender4" or name == "Dominos" or name == "ElvUI") then RequestScan() end
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then RequestScan()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        local unit, power = ...
        if DB.enabled and unit == "player" and not IsSecret(power) and power == "ENERGY" then RequestUpdate() end
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_AURA" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then RequestCosts()
    elseif event == "PLAYER_REGEN_DISABLED" then demo = false; RefreshCosts(); Update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if rescanPending then ScanButtons() else RefreshCosts() end
        Update()
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_STEALTH" then RequestBindings()
    elseif event == "SPELLS_CHANGED" then RequestBindings(); RequestScan() end
end)
