-- Opt-in, read-only Forever API diagnostics. Never persist raw combat data.
local _,ns=...
local D={}; ns.APIDiagnostics=D
local api,frame,panel,edit,status,report,refresh
local recording=false; local started=0; local elapsed=0; local entries={}; local dropped=0
local ids={53,1752,1776,1777,1766,1833,408,8643,2094,13741,13750}
local spells={}; local extra={}
local LIMIT=480
local function Secret(v)
    if type(issecretvalue)=="function" then return issecretvalue(v) end
    return false
end
local function Safe(v)
    if Secret(v) then return nil end
    return v
end
local function Format(v)
    if Secret(v) then return "<secret>" end
    if v==nil then return "<nil>" end
    if type(v)=="number" then return v==math.floor(v) and string.format("%.0f",v) or string.format("%.4f",v):gsub("0+$",""):gsub("%.$","") end
    if type(v)=="boolean" then return tostring(v) end
    if type(v)=="string" then return v:gsub("[\r\n]"," "):sub(1,100) end
    return "<"..type(v)..">"
end
local function Call(fn,...)
    if type(fn)~="function" then return false,"<missing>" end
    local ok,a,b,c,d=pcall(fn,...)
    if not ok then return false,"<error>" end
    return true,a,b,c,d
end
local function Query(fn,...)
    local ok,a,b=Call(fn,...)
    if not ok then return a end
    return Format(a)..(Secret(b) and " / <secret>" or b~=nil and " / "..Format(b) or "")
end
local function PublicTable(v) return not Secret(v) and type(v)=="table" end
local function Read(fn,...)
    local ok,v=Call(fn,...); if ok then return Safe(v) end
end
local function Name(id)
    local v=Read(C_Spell and C_Spell.GetSpellInfo,id)
    if PublicTable(v) then return Format(v.name) end
    return "?"
end
local function Costs(id)
    local ok,v=Call(C_Spell and C_Spell.GetSpellPowerCost,id)
    if not ok then return v end
    if not PublicTable(v) then return Format(v) end
    local out={}
    for _,row in ipairs(v) do
        if PublicTable(row) then
            local fields={}
            for _,key in ipairs({"type","cost","minCost","costPercent","costPerSec","requiredAuraID","hasRequiredAura"}) do fields[#fields+1]=key.."="..Format(row[key]) end
            out[#out+1]=table.concat(fields,",")
        else out[#out+1]=Format(row) end
    end
    return #out>0 and table.concat(out,"; ") or "<empty>"
end
local function Aura(name,unit,filter)
    unit=unit or "player"; filter=filter or "HELPFUL"
    local ok,v=Call(C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName,unit,name,filter)
    if not ok then return v end
    if not PublicTable(v) then return Format(v) end
    return "id="..Format(v.spellId)..", stacks="..Format(v.applications)..", duration="..Format(v.duration)..", expiration="..Format(v.expirationTime)..", instance="..Format(v.auraInstanceID)
end
local function Cooldown(id,ignoreGCD)
    if ignoreGCD==nil then ignoreGCD=true end
    local ok,v=Call(C_Spell and C_Spell.GetSpellCooldownDuration,id,ignoreGCD)
    if not ok then return v end
    if Secret(v) or v==nil then return Format(v) end
    local good,result=pcall(function() return Query(v.GetRemainingDuration,v) end)
    return good and result or "<error>"
end
-- Both the Classic TEST Scorch and Retail dummy are probes, not assumed to
-- represent a usable GCD on this build. Keep raw cooldown fields distinct
-- from duration-object methods and from spell-specific cooldowns.
local function CooldownInfo(id,event)
    local ok,v=Call(C_Spell and C_Spell.GetSpellCooldown,id)
    if not ok then return v end
    if not PublicTable(v) then return Format(v) end
    local out={}
    for _,k in ipairs({"startTime","duration","modRate","isActive","isEnabled","timeUntilEndOfStartRecovery"}) do out[#out+1]=k.."="..Format(v[k]) end
    if event=="SPELL_UPDATE_COOLDOWN" then out[#out+1]="isOnGCD="..Format(v.isOnGCD) end
    return table.concat(out,",")
end
local function CooldownProbe(id,event)
    local s=C_Secrets
    return "secret="..Query(s and s.ShouldSpellCooldownBeSecret,id)..", remainingAll="..Cooldown(id,false)..", remainingIgnoringGCD="..Cooldown(id,true)..", "..CooldownInfo(id,event)
end
local function ControlProbe(id)
    return "secret="..Query(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret,id)..", aura="..Aura(Name(id),"target","HARMFUL")
end
local function CollectSpells()
    local found={}
    for _,id in ipairs(ids) do found[id]=true end
    for id in pairs(extra) do found[id]=true end
    if api and api.spells then
        for _,id in ipairs(api.spells()) do if type(id)=="number" then found[id]=true end end
    end
    local book=C_SpellBook
    local count=Read(book and book.GetNumSpellBookSkillLines)
    if type(count)=="number" then
        for i=1,math.min(count,30) do
            local line=Read(book.GetSpellBookSkillLineInfo,i)
            if PublicTable(line) then
                local offset,n=Safe(line.itemIndexOffset),Safe(line.numSpellBookItems)
                if type(offset)=="number" and type(n)=="number" then
                    for slot=offset+1,offset+math.min(n,300) do
                        local info=Read(book.GetSpellBookItemInfo,slot,0)
                        if PublicTable(info) then
                            local id=Safe(info.spellID)
                            if type(id)=="number" then
                                local cost=Read(C_Spell and C_Spell.GetSpellPowerCost,id)
                                if PublicTable(cost) then
                                    for _,row in ipairs(cost) do if PublicTable(row) and Safe(row.type)==3 then found[id]=true; break end end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local out={}; for id in pairs(found) do out[#out+1]=id end; table.sort(out)
    return out
end
local function TalentLines()
    local out={}
    local s,t=C_SpecializationInfo,C_Traits
    local group=Read(s and s.GetActiveSpecGroup)
    local config=type(group)=="number" and Read(s.GetCombatConfigIDForSpecGroup,group)
    out[#out+1]="trait group="..Format(group).." config="..Format(config)
    if type(config)~="number" then return out end
    local info=Read(t and t.GetConfigInfo,config)
    if not PublicTable(info) or not PublicTable(info.treeIDs) then out[#out+1]="trait trees unavailable"; return out end
    for _,tree in ipairs(info.treeIDs) do
        if not Secret(tree) then
            local nodes=Read(t.GetTreeNodes,tree)
            if PublicTable(nodes) then
                for _,nodeID in ipairs(nodes) do
                    local node=Read(t.GetNodeInfo,config,nodeID)
                    if PublicTable(node) and PublicTable(node.entryIDs) then
                        for _,entryID in ipairs(node.entryIDs) do
                            local e=Read(t.GetEntryInfo,config,entryID)
                            local def=PublicTable(e) and Read(t.GetDefinitionInfo,Safe(e.definitionID))
                            if PublicTable(def) then
                                local id=Safe(def.spellID)
                                local name=type(id)=="number" and Name(id) or Format(def.overrideName)
                                local rank=Safe(node.activeRank)
                                local active=PublicTable(node.activeEntry) and Safe(node.activeEntry.entryID)
                                if (type(rank)=="number" and rank>0 and (active==entryID or #node.entryIDs==1)) or name=="Improved Gouge" or id==13741 then
                                    out[#out+1]="trait node="..Format(nodeID).." entry="..Format(entryID).." spell="..Format(id).." "..name.." activeRank="..Format(node.activeRank).." currentRank="..Format(node.currentRank).." activeEntry="..Format(active)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end
local function Resources()
    local s=C_Secrets
    return "combat="..Query(InCombatLockdown).." energy="..Query(UnitPower,"player",3).." max="..Query(UnitPowerMax,"player",3).." combo="..Query(GetComboPoints,"player","target").." regen="..Query(GetPowerRegenForPowerType,3).." statsSecret="..Query(s and s.ShouldUnitStatsBeSecret)
end
local function Buffs()
    local parts={}
    for _,name in ipairs({"Poised","Adrenaline Rush","Composure","Flash of Steel"}) do parts[#parts+1]=name.."="..Aura(name) end
    return table.concat(parts," | ")
end
local function Now() return type(GetTime)=="function" and GetTime() or 0 end
local previous={}
local lastSample=-1
local function Capture(event,id,force)
    if not recording then return end
    local now=Now()
    -- Resource events can be very frequent. Preserve cast/target/combat and
    -- cooldown/aura events immediately; rate-limit generic resource polls.
    if not force and (event=="UNIT_POWER_FREQUENT" or event=="UNIT_POWER_UPDATE" or event=="sample") and now-lastSample<.10 then return end
    lastSample=now
    local ok,line=pcall(function()
        local changes={}
        local function Field(key,value)
            if previous[key]~=value then changes[#changes+1]=key.."="..value; previous[key]=value end
        end
        Field("resources",Resources()); Field("buffs",Buffs())
        Field("GougeEffect",ControlProbe(1776))
        for _,spell in ipairs({1766,1776,1777,29515,61304}) do
            Field("cooldown "..spell,CooldownProbe(spell,event))
        end
        -- Capture GCD status of actual casts as well as dummy candidates.
        if not Secret(id) and type(id)=="number" then
            Field("castCooldown "..id,CooldownProbe(id,event))
        end
        if event=="SPELL_UPDATE_COOLDOWN" then
            for _,spell in ipairs({53,1758,2589}) do Field("eventCooldown "..spell,CooldownProbe(spell,event)) end
        end
        for _,spell in ipairs(spells) do Field("cost "..spell,Costs(spell)) end
        if event=="start" or event=="PLAYER_REGEN_DISABLED" or event=="TRAIT_CONFIG_UPDATED" then
            Field("talents",table.concat(TalentLines(),"; "))
        end
        if #changes==0 then return "" end
        return table.concat(changes," | ")
    end)
    if not ok then line="<snapshot error>" end
    if not force and line=="" then return end
    if #entries>=LIMIT then recording=false; dropped=dropped+1; frame:UnregisterAllEvents(); frame:SetScript("OnUpdate",nil); if refresh then refresh() end; return end
    local label=""
    if Secret(id) then label=" spell=<secret>" elseif id~=nil then label=" spell="..Format(id) end
    entries[#entries+1]=string.format("%.3f %s%s%s",now-started,event,label,line~="" and " | "..line or " | unchanged")
end
function D.SelfTest()
    local out={"Rogue Energy Sweep v0.25.0 API self-test","Values: <secret>, <nil>, <missing>, <error> are distinct; no secret values are serialized."}
    local _,version,build,_,interface=Call(GetBuildInfo)
    out[#out+1]="client="..Format(version).." build="..Format(build).." interface="..Format(interface)
    out[#out+1]=Resources(); local s=C_Secrets
    for _,power in ipairs({3,4}) do
        out[#out+1]="power "..power.." policy="..Query(s and s.GetPowerTypeSecrecy,power).." currentSecret="..Query(s and s.ShouldUnitPowerBeSecret,"player",power).." maxSecret="..Query(s and s.ShouldUnitPowerMaxBeSecret,"player",power)
    end
    out[#out+1]=Buffs()
    out[#out+1]="GougeEffect "..ControlProbe(1776)
    for _,id in ipairs({1766,1776,1777,29515,61304}) do out[#out+1]="cooldown probe "..id.." "..Name(id).." "..CooldownProbe(id) end
    for _,line in ipairs(TalentLines()) do out[#out+1]=line end
    for _,id in ipairs(CollectSpells()) do
        out[#out+1]="spell "..id.." "..Name(id).." known="..Query(C_SpellBook and C_SpellBook.IsSpellKnown,id).." base="..Query(C_SpellBook and C_SpellBook.FindBaseSpellByID,id).." override="..Query(C_Spell and C_Spell.GetBaseSpell,id).." cooldownSecret="..Query(s and s.ShouldSpellCooldownBeSecret,id).." auraSecret="..Query(s and s.ShouldSpellAuraBeSecret,id).." cooldownRemaining="..Cooldown(id).." costs="..Costs(id)
    end
    -- Verify native sinks on isolated, hidden, insecure test widgets.
    local ok,why=pcall(function()
        local curve=C_CurveUtil.CreateCurve(); curve:AddPoint(0,0); curve:AddPoint(1,1)
        local value=UnitPowerPercent("player",3,false,curve)
        local bar=CreateFrame("StatusBar",nil,UIParent); bar:Hide()
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local tex=bar:CreateTexture(nil,"ARTWORK"); tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        out[#out+1]="curve result="..Format(value)
        local function Sink(label,fn) out[#out+1]=label.."="..(pcall(fn) and "accepted" or "rejected") end
        Sink("SetValue",function() bar:SetValue(value) end)
        Sink("SetMinMaxValues",function() bar:SetMinMaxValues(0,value) end)
        Sink("SetAlpha",function() bar:SetAlpha(value) end)
        Sink("SetRadialProgressBarPercent",function() tex:SetRadialProgressBarPercent(value) end)
    end)
    if not ok then out[#out+1]="native sink test setup failed" end
    report=table.concat(out,"\n"); return report
end
local EVENTS={"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","COMBO_TARGET_CHANGED","UNIT_COMBO_POINTS","UNIT_POWER_UPDATE","UNIT_POWER_FREQUENT","UNIT_MAXPOWER","UNIT_AURA","UNIT_SPELLCAST_SUCCEEDED","SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_USABLE","TRAIT_CONFIG_UPDATED"}
function D.Start()
    if recording then return false end
    if not frame then frame=CreateFrame("Frame") end
    entries={}; dropped=0; previous={}; lastSample=-1; elapsed=0; started=Now()
    spells=CollectSpells(); recording=true
    for _,event in ipairs(EVENTS) do pcall(frame.RegisterEvent,frame,event) end
    frame:SetScript("OnEvent",function(_,event,unit,_,id)
        if event:sub(1,5)=="UNIT_" then
            if Secret(unit) or (unit~="player" and not (event=="UNIT_AURA" and unit=="target")) then return end
        end
        local castID
        if event=="UNIT_SPELLCAST_SUCCEEDED" then castID=id end
        Capture(event,castID,event=="UNIT_SPELLCAST_SUCCEEDED" or event=="PLAYER_TARGET_CHANGED" or event=="PLAYER_REGEN_DISABLED" or event=="PLAYER_REGEN_ENABLED" or event=="SPELL_UPDATE_COOLDOWN")
    end)
    frame:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+dt
        if elapsed>=.10 then elapsed=0; Capture("sample") end
    end)
    Capture("start",nil,true); return true
end
function D.Stop()
    if not recording then return end
    Capture("stop",nil,true); recording=false
    frame:UnregisterAllEvents(); frame:SetScript("OnUpdate",nil)
end
function D.Status() return (recording and "Recording" or "Stopped").." | "..#entries.."/"..LIMIT.." snapshots"..(dropped>0 and " | limit reached" or "") end
function D.Report()
    return (report or "No API self-test yet.").."\n\n=== Combat trace (first snapshot full; subsequent fields are changes only) ===\n"..D.Status().."\n"..table.concat(entries,"\n")
end
function D.AddSpell(id) if type(id)=="number" and id>0 and id==math.floor(id) then extra[id]=true; return true end end
function D.Configure(a) api=a end
function D.Open()
    if not panel then
        panel=CreateFrame("Frame","RogueEnergySweepAPIDiagnostics",UIParent,"BasicFrameTemplateWithInset")
        panel:SetSize(740,540); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
        if panel.TitleText then panel.TitleText:SetText("Rogue Energy Sweep — API diagnostics") end
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=panel:GetName() end
        status=panel:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); status:SetPoint("TOPLEFT",16,-32)
        local hint=panel:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); hint:SetPoint("TOPLEFT",16,-52); hint:SetText("Recording is opt-in, session-only, and stops at 480 snapshots. Review before sharing.")
        local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",16,-76); scroll:SetPoint("BOTTOMRIGHT",-36,48)
        edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(668); edit:SetHeight(380); scroll:SetScrollChild(edit)
        edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        scroll:SetScript("OnMouseDown",function() edit:SetFocus() end)
        local function Button(text,x,w,fn)
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate"); b:SetSize(w,26); b:SetPoint("BOTTOMLEFT",x,12); b:SetText(text); b:SetScript("OnClick",fn); return b
        end
        local rec
        refresh=function()
            local text=D.Report(); local _,n=text:gsub("\n","")
            edit:SetHeight(math.max(380,(n+1)*28+#text/65*12)); edit:SetText(text); edit:ClearFocus(); scroll:SetVerticalScroll(0)
            status:SetText(D.Status()); rec:SetText(recording and "Stop recording" or "Start recording")
        end
        Button("Run self-test",16,126,function() D.SelfTest(); refresh() end)
        rec=Button("Start recording",148,136,function() if recording then D.Stop() else D.Start() end; refresh() end)
        Button("Refresh report",290,128,refresh)
        Button("Select all",424,112,function() refresh(); edit:SetFocus(); edit:HighlightText() end)
        Button("Close",542,90,function() panel:Hide() end)
        panel:SetScript("OnHide",function() edit:ClearFocus() end)
    end
    panel:Show(); refresh()
end
function D.Command(arg)
    if arg=="start" then D.Start(); if api then api.say(D.Status()) end
    elseif arg=="stop" then D.Stop(); if api then api.say(D.Status()) end; D.Open()
    elseif arg=="test" then D.SelfTest(); D.Open()
    elseif arg:match("^spell %d+$") then D.AddSpell(tonumber(arg:match("%d+"))); if api then api.say("Added diagnostic spell for next test/recording.") end
    else D.Open() end
end
