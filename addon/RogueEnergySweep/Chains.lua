-- Ability Chains: static public thresholds -> native curve -> native widgets.
local _,ns=...
local C={}; ns.Chains=C
local api,db,cfg,maxEnergy= nil,nil,nil,100
local catalog,ordered,tracked,curves,samples={},{},{},{},{}
local panel,refresh,signature
local errorText="none"
local WHITE="Interface\\Buttons\\WHITE8X8"
local CIRCLE="Interface\\AddOns\\RogueEnergySweep\\ChainCircle"
local DIAMOND="Interface\\AddOns\\RogueEnergySweep\\ChainDiamond"
local WARNING="Interface\\AddOns\\RogueEnergySweep\\ChainWarning"
local palette={{.75,.53,1},{.76,.51,.29},{1,.29,.26},{1,.78,.22},{.30,.85,.48},{.30,.75,1},{1,.55,.80},{.9,.9,.9}}
local function number(v,d,lo,hi) if type(v)~="number" or v~=v then v=d end; return math.max(lo,math.min(hi,v)) end
local function Normalize(c)
    c=type(c)=="table" and c or {}
    c.enabled=c.enabled==true; c.fraction=c.fraction~=false; c.hideInactive=c.hideInactive==true
    c.size=number(c.size,7,4,13); c.spacing=number(c.spacing,2,1,6); c.opacity=number(c.opacity,1,.2,1)
    c.offset=number(c.offset,0,-12,12); c.regen=number(c.regen,10,0,30)
    c.maxPips=math.floor(number(c.maxPips,4,1,6))
    c.rules=type(c.rules)=="table" and c.rules or {}; c.colors=type(c.colors)=="table" and c.colors or {}
    c.globalFollow=type(c.globalFollow)=="table" and c.globalFollow or {}
    c.pulseWarnings=c.pulseWarnings~=false
    for id,mode in pairs(c.globalFollow) do if type(id)~="number" or (mode~="warning" and mode~="opportunity") then c.globalFollow[id]=nil end end
    local templates={minimal=true,builders=true,pvp=true,finishers=true,custom=true}
    c.template=templates[c.template] and c.template or "minimal"
    return c
end
function C.Configure(a) api=a end
function C.Init(d) db=d; d.chains=Normalize(d.chains); cfg=d.chains; signature=nil; catalog={}; ordered={} end
local function RepeatThreshold(cost,n,regen)
    return cost+(n-1)*math.max(0,cost-regen)
end
local function FollowThreshold(first,next,regen)
    return math.max(first,first+next-regen)
end
local function GetColor(id,name)
    local index=cfg.colors[id]
    if type(index)~="number" or not palette[index] then
        local e=catalog[id]; name=name or (e and e.name) or ""
        local defaults={["Sinister Strike"]=1,Backstab=2,Gouge=3,Eviscerate=4,Kick=5}
        index=defaults[name] or ((id%#palette)+1)
    end
    return palette[index],index
end
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok,info=pcall(C_Spell.GetSpellInfo,id)
        if ok and not api.secret(info) and type(info)=="table" and not api.secret(info.name) and type(info.name)=="string" then return info.name end
    end
    return "Spell "..id
end
local function Remember(records)
    for _,e in pairs(catalog) do e.current=false end
    for _,r in ipairs(records) do
        if r.spellID and r.cost and r.cost>0 then
            local e=catalog[r.spellID] or {id=r.spellID,name=SpellName(r.spellID)}
            e.cost=r.cost; e.category=r.category; e.finisher=r.finisher; e.current=true; catalog[r.spellID]=e
        end
    end
    ordered={}
    for _,e in pairs(catalog) do if e.current then ordered[#ordered+1]=e end end
    table.sort(ordered,function(a,b) if a.name==b.name then return a.id<b.id end return a.name<b.name end)
end
local function DefaultRule(e)
    if cfg.template=="custom" then return {repeatPips=false,follow={}} end
    local rule={repeatPips=e.category=="builder" and not e.finisher,follow={}}
    if cfg.template=="minimal" then return rule end
    for _,n in ipairs(ordered) do
        if n.id~=e.id then
            local include=cfg.template=="builders" and e.category=="builder" and n.category=="builder"
                or cfg.template=="pvp" and (n.name=="Kick" or n.name=="Gouge")
                or cfg.template=="finishers" and n.finisher
            if include and #rule.follow<3 then rule.follow[#rule.follow+1]=n.id end
        end
    end
    return rule
end
local function Rule(e)
    local r=cfg.rules[e.id]
    if type(r)~="table" then return DefaultRule(e) end
    return {repeatPips=r.repeatPips==true,follow=type(r.follow)=="table" and r.follow or {},conditions=type(r.conditions)=="table" and r.conditions or {}}
end
local function EditRule(e)
    local r=Rule(e); local copy={repeatPips=r.repeatPips,follow={},conditions={}}
    for _,id in ipairs(r.follow) do copy.follow[#copy.follow+1]=id; if r.conditions then copy.conditions[id]=r.conditions[id] end end
    cfg.rules[e.id]=copy; return copy
end
local function BuildPipCurve(lo,hi,partial,maximum)
    local ok,c=pcall(function()
        local curve=C_CurveUtil.CreateCurve()
        if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then curve:SetType(Enum.LuaCurveType.Linear) end
        local start=partial and lo or hi-.5
        local function Value(e)
            return math.max(0,math.min(1,(e-start)/math.max(.001,hi-start)))
        end
        local points={0,maximum}
        if start>0 and start<maximum then points[#points+1]=start end
        if hi>0 and hi<maximum then points[#points+1]=hi end
        table.sort(points)
        for _,e in ipairs(points) do curve:AddPoint(e/maximum,Value(e)) end
        return curve
    end)
    return ok and c or nil
end
C.BuildPipCurve=BuildPipCurve
-- Warning window: the source is affordable, but the reserved follow-up
-- is not affordable after the assumed intervening regeneration. Upper
-- threshold may exceed the energy cap; in that case the warning persists.
local function BuildWarningCurve(low,high,maximum)
    local ok,c=pcall(function()
        local curve=C_CurveUtil.CreateCurve()
        if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then curve:SetType(Enum.LuaCurveType.Linear) end
        local points={0,maximum}
        for _,e in ipairs({low-.5,low,high-.5,high}) do if e>0 and e<maximum then points[#points+1]=e end end
        table.sort(points)
        local previous
        for _,e in ipairs(points) do
            if previous~=e then
                local value=high>low and math.min(math.max(0,math.min(1,(e-low+.5)/.5)),math.max(0,math.min(1,(high-e)/.5))) or 0
                curve:AddPoint(e/maximum,value); previous=e
            end
        end
        return curve
    end)
    return ok and c or nil
end
C.BuildWarningCurve=BuildWarningCurve
local function WarningCurve(low,high)
    local key="warning:"..low..":"..high
    if curves[key]==nil then curves[key]=BuildWarningCurve(low,high,maxEnergy) or false end
    return curves[key] or nil,key
end
local function Curve(lo,hi,partial)
    local key=lo..":"..hi..":"..tostring(partial)
    if curves[key]==nil then curves[key]=BuildPipCurve(lo,hi,partial,maxEnergy) or false end
    return curves[key] or nil,key
end
local function NewPip(parent)
    local f=CreateFrame("Frame",nil,parent); f:EnableMouse(false)
    local bg=f:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(f)
    local bar=CreateFrame("StatusBar",nil,f); bar:EnableMouse(false); bar:SetAllPoints(f)
    bar:SetOrientation("VERTICAL"); bar:SetMinMaxValues(0,1); bar:SetValue(0)
    local pulse
    if bar.CreateAnimationGroup then
        local ok,group=pcall(function()
            local a=bar:CreateAnimationGroup(); a:SetLooping("BOUNCE")
            local fade=a:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(.38); fade:SetDuration(.4)
            return a
        end)
        if ok then pulse=group end
    end
    return {frame=f,bg=bg,bar=bar,pulse=pulse}
end
local function StopPulse(p)
    if p.pulse and p.pulsing then p.pulse:Stop(); p.pulsing=false end
    if p.bar.SetAlpha then p.bar:SetAlpha(1) end
end
local function HideTracked(r)
    r.frame:Hide()
    for _,p in ipairs(r.pips) do StopPulse(p) end
end
local function Clear(record)
    local r=tracked[record]
    if r then HideTracked(r) end
end
C.Clear=Clear
function C.Hide() for _,r in pairs(tracked) do HideTracked(r) end end
local function RepeatDefinitions(id,cost,maximum,limit,regen,fraction)
    local defs={}; local previous=0
    for n=1,limit do
        local threshold=RepeatThreshold(cost,n,regen)
        if threshold>maximum and (not fraction or previous>=maximum) then break end
        defs[#defs+1]={lo=previous,hi=threshold,partial=fraction and threshold>previous,kind="repeat",id=id,n=n}
        previous=threshold
        if threshold>maximum then break end
    end
    return defs
end
C.RepeatDefinitions=RepeatDefinitions
-- The standalone view shares the exact palette, budget and optional partial
-- pip semantics even when action-bar Chains is disabled. No dependency on
-- the current action page for manually selected tracker abilities.
function C.ArsenalSpec(entry,maximum,allRepeats)
    local id=entry.spellID
    local color,index=GetColor(id,entry.name)
    local rule=cfg.rules[id]
    local repeatEnabled=entry.category=="builder" and not entry.finisher
    if type(rule)=="table" then repeatEnabled=rule.repeatPips==true end
    local limit=(allRepeats or repeatEnabled) and cfg.maxPips or 1
    return {color=color,colorIndex=index,limit=limit,regen=cfg.regen,fraction=cfg.fraction,hideInactive=cfg.hideInactive,
        defs=RepeatDefinitions(id,entry.cost,maximum,limit,cfg.regen,cfg.fraction)}
end
local function FollowDefinitions(entry,rule)
    local defs,seen={},{}
    local function Add(id,condition)
        local e=catalog[id]
        if #defs>=3 or not e or not e.current or id==entry.id or seen[id] or api.excluded({spellID=id,category=e.category}) then return end
        local threshold=FollowThreshold(entry.cost,e.cost,cfg.regen)
        local warning=condition=="warning"
        if (warning and threshold>entry.cost and entry.cost<=maxEnergy) or (not warning and threshold<=maxEnergy) then
            defs[#defs+1]={lo=warning and entry.cost or 0,hi=threshold,partial=false,kind="follow",warning=warning,id=id,n=#defs+1}
            seen[id]=true
        end
    end
    -- Global warnings first, then global opportunities, then local rules.
    -- A global relationship overrides a local one for the same target.
    for _,condition in ipairs({"warning","opportunity"}) do
        for _,e in ipairs(ordered) do if cfg.globalFollow[e.id]==condition then Add(e.id,condition) end end
    end
    for _,id in ipairs(rule.follow) do if not cfg.globalFollow[id] then Add(id,rule.conditions and rule.conditions[id] or "opportunity") end end
    return defs
end
local function Setup(record,entry)
    local rule=Rule(entry)
    local defs=rule.repeatPips and RepeatDefinitions(entry.id,entry.cost,maxEnergy,cfg.maxPips,cfg.regen,cfg.fraction) or {}
    for _,d in ipairs(FollowDefinitions(entry,rule)) do defs[#defs+1]=d end
    if #defs==0 then if tracked[record] then tracked[record].count=0 end; Clear(record); return end
    local r=tracked[record]
    if not r then
        if InCombatLockdown and InCombatLockdown() then return end
        local frame=CreateFrame("Frame",nil,record.comboGate)
        frame:EnableMouse(false); frame:SetAllPoints(record.frame); frame:SetFrameLevel(record.frame:GetFrameLevel()+9); frame:Hide()
        r={frame=frame,pips={}}; tracked[record]=r
    end
    r.count=#defs; r.frame:SetAlpha(cfg.opacity)
    local width=36
    if record.frame.GetWidth then local ok,v=pcall(record.frame.GetWidth,record.frame); if ok then width=api.safe(v) or width end end
    local repeatCount,followCount=0,0
    for _,d in ipairs(defs) do if d.kind=="repeat" then repeatCount=repeatCount+1 else followCount=followCount+1 end end
    local function Fit(count)
        local gap=math.min(cfg.spacing,math.max(1,(width-2)/math.max(1,count)*.25))
        local size=math.max(2,math.min(cfg.size,(width-2-(count-1)*gap)/math.max(1,count)))
        return size,gap
    end
    local repeatSize,repeatGap=Fit(repeatCount); local followSize,followGap=Fit(followCount)
    for i,d in ipairs(defs) do
        local p=r.pips[i]
        if not p then
            if InCombatLockdown and InCombatLockdown() then r.count=i-1; break end
            p=NewPip(r.frame); r.pips[i]=p
        end
        StopPulse(p)
        local texture=d.kind=="repeat" and CIRCLE or (d.warning and WARNING or DIAMOND)
        local size,gap=repeatSize,repeatGap
        if d.kind=="follow" then size,gap=followSize,followGap end
        p.frame:SetSize(size,size); p.frame:ClearAllPoints()
        if d.kind=="repeat" then
            p.frame:SetPoint("TOPLEFT",r.frame,"TOPLEFT",1+(d.n-1)*(size+gap),cfg.offset-1)
        else
            p.frame:SetPoint("BOTTOMLEFT",r.frame,"BOTTOMLEFT",1+(d.n-1)*(size+gap),-cfg.offset+1)
        end
        p.bg:SetTexture(texture); p.bg:SetVertexColor(.15,.13,.11,.85)
        p.bar:SetStatusBarTexture(texture)
        local color=GetColor(d.id); p.bar:SetStatusBarColor(color[1],color[2],color[3],1)
        p.warning=d.warning==true
        if p.warning then
            p.curve,p.key=WarningCurve(d.lo,d.hi)
            p.alphaCurve,p.alphaKey=p.curve,p.key
            p.bg:Hide(); p.bar:SetValue(1); p.frame:SetAlpha(0)
        else
            p.bg:Show(); p.curve,p.key=Curve(d.lo,d.hi,d.partial and d.hi>d.lo)
            -- Hide-inactive uses a separate readiness curve, not a Lua test on energy.
            p.alphaCurve,p.alphaKey=Curve(0,d.partial and math.min(d.hi,d.lo+.5) or d.hi,false)
            p.bar:SetValue(0); p.frame:SetAlpha(1)
        end
        p.frame:Show()
    end
    for i=r.count+1,#r.pips do r.pips[i].frame:Hide() end
end
function C.Sync(records,max)
    if not cfg or not api then return end
    Remember(records); maxEnergy=max
    local bits={tostring(cfg.enabled),cfg.template,tostring(cfg.fraction),tostring(cfg.hideInactive),tostring(cfg.pulseWarnings),cfg.size,cfg.spacing,cfg.opacity,cfg.offset,cfg.regen,cfg.maxPips,max}
    for _,e in ipairs(ordered) do
        local r=Rule(e); bits[#bits+1]=e.id..":"..e.cost..":"..tostring(r.repeatPips)..":"..select(2,GetColor(e.id))
        bits[#bits+1]="global:"..tostring(cfg.globalFollow[e.id])
        for _,id in ipairs(r.follow) do bits[#bits+1]=tostring(id)..":"..tostring(r.conditions and r.conditions[id]) end
    end
    for _,r in ipairs(records) do bits[#bits+1]=tostring(r)..":"..tostring(r.spellID)..":"..tostring(api.excluded(r)) end
    local key=table.concat(bits,"|")
    if key~=signature or (not InCombatLockdown or not InCombatLockdown()) then
        signature=key; C.Hide(); curves={}; samples={}
        for _,r in pairs(tracked) do r.count=0 end
        if cfg.enabled then
            for _,r in ipairs(records) do
                local e=catalog[r.spellID]
                if e and r.cost and r.cost>0 and not api.excluded(r) then
                    local ok,err=pcall(Setup,r,e)
                    if not ok then errorText=tostring(err); if tracked[r] then tracked[r].count=0 end; Clear(r) end
                end
            end
        end
    end
    if refresh and panel:IsShown() then refresh() end
end
function C.Begin() samples={} end
local function Sample(curve,key)
    if not curve then return nil,false end
    local s=samples[key]
    if not s then local value,ok=api.evaluate(curve); s={value=value,ok=ok}; samples[key]=s end
    return s.value,s.ok
end
function C.Update(record,eligible)
    local r=tracked[record]
    if not cfg.enabled or not eligible or not r or r.count==0 then Clear(record); return end
    local ok,err=pcall(function()
        for i=1,r.count do
            local p=r.pips[i]; local value,valid=Sample(p.curve,p.key)
            if valid then
                if p.warning then
                    -- Native alpha gates the complete warning glyph. The pulse
                    -- animates only its child and never reads protected alpha.
                    p.bar:SetValue(1); p.frame:SetAlpha(value)
                    if cfg.pulseWarnings and p.pulse and not p.pulsing then p.pulse:Play(); p.pulsing=true end
                else
                p.bar:SetValue(value)
                if cfg.hideInactive then
                    local alpha,good=Sample(p.alphaCurve,p.alphaKey)
                    if good then p.frame:SetAlpha(alpha) else p.frame:SetAlpha(0) end
                else p.frame:SetAlpha(1) end
                end
                p.frame:Show()
            else StopPulse(p); p.frame:Hide() end
        end
        r.frame:Show()
    end)
    if not ok then errorText=tostring(err); Clear(record) end
end
function C.Status()
    if not cfg then return "not initialized" end
    local globals=0; for _ in pairs(cfg.globalFollow) do globals=globals+1 end
    return (cfg.enabled and "on" or "off").." | "..globals.." global follow-ups | "..cfg.template.." | "..cfg.regen.." assumed energy/GCD | "..#ordered.." discovered | last error "..errorText
end
function C.Command(arg)
    if arg=="on" then cfg.enabled=true
    elseif arg=="off" then cfg.enabled=false
    elseif arg=="kick" then
        for _,e in ipairs(ordered) do if e.name=="Kick" then
            local count=0; for _ in pairs(cfg.globalFollow) do count=count+1 end
            if count>=3 and not cfg.globalFollow[e.id] then return false end
            cfg.globalFollow[e.id]="warning"; cfg.enabled=true; signature=nil; return true
        end end
        return false
    elseif arg=="minimal" or arg=="builders" or arg=="pvp" or arg=="finishers" or arg=="custom" then cfg.template=arg; cfg.rules={}; cfg.enabled=true
    else return false end
    signature=nil; return true
end
function C.Open()
    if not cfg then return end
    if not panel then
        panel=CreateFrame("Frame","RogueEnergySweepChainsOptions",UIParent,"BasicFrameTemplateWithInset")
        panel:SetSize(528,554); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
        if panel.TitleText then panel.TitleText:SetText("Ability Chains") end
        if UISpecialFrames then table.insert(UISpecialFrames,panel:GetName()) end
        local function Text(t,x,y)
            local f=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); f:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); f:SetText(t); return f
        end
        local function Button(t,x,y,w,fn)
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate"); b:SetSize(w,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); b:SetText(t); b:SetScript("OnClick",fn); return b
        end
        local function Check(t,x,y,fn)
            local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate"); b:SetSize(24,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); Text(t,x+28,y-6)
            b:SetScript("OnClick",function(self) fn(self:GetChecked() and true or false); signature=nil; api.apply() end); return b
        end
        local function Change(key,value) cfg[key]=value; signature=nil; api.apply() end
        local enabled=Check("Enable pips",16,-33,function(v) cfg.enabled=v end)
        local fraction=Check("Partial repeat pips",178,-33,function(v) cfg.fraction=v end)
        local hide=Check("Hide inactive",355,-33,function(v) cfg.hideInactive=v end)
        Text("Templates replace local rules. Circles = repeats; diamonds = follow-ups.",16,-64)
        local templates={}
        for i,e in ipairs({{"minimal","Minimal"},{"builders","Builders"},{"pvp","PvP"},{"finishers","Finishers"},{"custom","Custom"}}) do
            local key=e[1]; templates[key]=Button(e[2],16+(i-1)*96,-83,92,function() C.Command(key); api.apply() end)
        end
        local syncing=false; local sliders={}
        local function Slider(key,title,x,y,lo,hi,step,factor)
            local label=Text(title,x,y)
            local b=CreateFrame("Slider","RogueEnergySweepChain"..key,panel,"OptionsSliderTemplate")
            b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y-16); b:SetSize(215,16); b:SetMinMaxValues(lo,hi); b:SetValueStep(step)
            for _,suffix in ipairs({"Text","Low","High"}) do local l=_G[b:GetName()..suffix]; if l then l:SetText("") end end
            if b.SetObeyStepOnDrag then b:SetObeyStepOnDrag(true) end
            b:SetScript("OnValueChanged",function(_,v) if not syncing then Change(key,math.floor(v+.5)/factor) end end)
            sliders[key]={b=b,l=label,t=title,factor=factor}
        end
        Slider("size","Pip size",16,-118,4,13,1,1); Slider("spacing","Spacing",260,-118,1,6,1,1)
        Slider("opacity","Opacity %",16,-157,20,100,5,100); Slider("offset","Vertical offset",260,-157,-12,12,1,1)
        Slider("regen","Assumed energy per GCD",16,-196,0,30,1,1); Slider("maxPips","Max repeat pips",260,-196,1,6,1,1)
        local index,targetPage=1,1
        local selected=Text("",116,-243)
        Button("Previous",16,-236,90,function() index=index-1; targetPage=1; refresh() end)
        Button("Next",398,-236,90,function() index=index+1; targetPage=1; refresh() end)
        local repeatBox=Check("Repeat pips",16,-268,function(v) local e=ordered[index]; if e then EditRule(e).repeatPips=v end end)
        local color=Button("Pip color",260,-268,120,function()
            local e=ordered[index]; if e then local _,i=GetColor(e.id); cfg.colors[e.id]=i%#palette+1; signature=nil; api.apply() end
        end)
        local swatch=color:CreateTexture(nil,"OVERLAY"); swatch:SetSize(12,12); swatch:SetPoint("LEFT",color,"LEFT",6,0); swatch:SetTexture(WHITE)
        local global=Button("Global: Off",16,-300,175,function()
            local e=ordered[index]; if not e then return end
            local old=cfg.globalFollow[e.id]
            if old=="opportunity" then cfg.globalFollow[e.id]="warning"
            elseif old=="warning" then cfg.globalFollow[e.id]=nil
            else
                local count=0; for _ in pairs(cfg.globalFollow) do count=count+1 end
                if count>=3 then return end
                cfg.globalFollow[e.id]="opportunity"
            end
            signature=nil; api.apply()
        end)
        local pulseWarnings=Check("Pulse warnings",260,-300,function(v) cfg.pulseWarnings=v end)
        Text("Global applies this selected ability to all other energy abilities.",16,-331)
        Text("Local follow-ups: click Off / + / ! to cycle. Max 3 visible, globals first.",16,-349)
        local choices={}
        for i=1,6 do
            local x=16+((i-1)%2)*248; local y=-369-math.floor((i-1)/2)*25
            local l=Text("",x+48,y-6)
            local row={l=l}
            local b=Button("Off",x,y,43,function()
                local e=ordered[index]; if not e or not row.id or cfg.globalFollow[row.id] then return end
                local r=EditRule(e); local found
                for j,id in ipairs(r.follow) do if id==row.id then found=j; break end end
                if not found and #r.follow<3 then r.follow[#r.follow+1]=row.id; r.conditions[row.id]="opportunity"
                elseif found and r.conditions[row.id]~="warning" then r.conditions[row.id]="warning"
                elseif found then table.remove(r.follow,found); r.conditions[row.id]=nil end
                signature=nil; api.apply()
            end)
            row.b=b
            choices[i]=row
        end
        local page=Text("",195,-452)
        Button("Prev targets",16,-446,105,function() targetPage=targetPage-1; refresh() end)
        Button("Next targets",402,-446,105,function() targetPage=targetPage+1; refresh() end)
        Text("+ = affordable afterward; ! = cannot afford afterward (energy only).",16,-480)
        Text("Uses assumed GCD regeneration; ignores target cooldowns and combo changes.",16,-500)
        Button("Done",418,-523,90,function() panel:Hide() end)
        refresh=function()
            syncing=true
            enabled:SetChecked(cfg.enabled); fraction:SetChecked(cfg.fraction); hide:SetChecked(cfg.hideInactive); pulseWarnings:SetChecked(cfg.pulseWarnings)
            for key,b in pairs(templates) do if b.LockHighlight and b.UnlockHighlight then if cfg.template==key then b:LockHighlight() else b:UnlockHighlight() end end end
            for key,row in pairs(sliders) do row.b:SetValue(cfg[key]*row.factor); row.l:SetText(row.t..": "..math.floor(cfg[key]*row.factor+.5)) end
            index=math.max(1,math.min(index,#ordered))
            local e=ordered[index]; selected:SetText(e and (e.name.." ("..e.cost..")") or "No discovered abilities")
            local r=e and Rule(e) or {follow={}}
            repeatBox:SetChecked(r.repeatPips==true)
            if e then repeatBox:Enable(); color:Enable(); global:Enable(); local c=GetColor(e.id); swatch:SetVertexColor(c[1],c[2],c[3],1)
                local condition=cfg.globalFollow[e.id]; global:SetText("Global: "..(condition=="warning" and "Warning !" or condition=="opportunity" and "Opportunity +" or "Off"))
            else repeatBox:Disable(); color:Disable(); global:Disable(); global:SetText("Global: Off") end
            local targets={}
            for _,n in ipairs(ordered) do if e and n.id~=e.id then targets[#targets+1]=n end end
            local pages=math.max(1,math.ceil(#targets/6)); targetPage=math.max(1,math.min(targetPage,pages)); page:SetText(targetPage.." / "..pages)
            local chosen={}; for _,id in ipairs(r.follow) do chosen[id]=true end
            for i,row in ipairs(choices) do
                local n=targets[(targetPage-1)*6+i]; row.id=n and n.id
                if n then
                    local mode=cfg.globalFollow[n.id] or (chosen[n.id] and (r.conditions and r.conditions[n.id] or "opportunity"))
                    row.b:Show(); row.l:Show(); row.l:SetText(n.name.." ("..n.cost..")"..(cfg.globalFollow[n.id] and " *" or ""))
                    row.b:SetText(mode=="warning" and "!" or mode=="opportunity" and "+" or "Off")
                    if not cfg.globalFollow[n.id] and (chosen[n.id] or #r.follow<3) then row.b:Enable() else row.b:Disable() end
                else row.b:Hide(); row.l:Hide() end
            end
            syncing=false
        end
    end
    panel:Show(); refresh()
end
