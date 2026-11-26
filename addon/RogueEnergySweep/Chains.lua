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
local palette={{.75,.53,1},{.76,.51,.29},{1,.29,.26},{1,.78,.22},{.30,.85,.48},{.30,.75,1},{1,.55,.80},{.9,.9,.9}}
local function number(v,d,lo,hi) if type(v)~="number" or v~=v then v=d end; return math.max(lo,math.min(hi,v)) end
local function Normalize(c)
    c=type(c)=="table" and c or {}
    c.enabled=c.enabled==true; c.fraction=c.fraction~=false; c.hideInactive=c.hideInactive==true
    c.size=number(c.size,7,4,13); c.spacing=number(c.spacing,2,1,6); c.opacity=number(c.opacity,1,.2,1)
    c.offset=number(c.offset,0,-12,12); c.regen=number(c.regen,10,0,30)
    c.maxPips=math.floor(number(c.maxPips,4,1,6))
    c.rules=type(c.rules)=="table" and c.rules or {}; c.colors=type(c.colors)=="table" and c.colors or {}
    c.template=c.template or "minimal"
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
local function GetColor(id)
    local index=cfg.colors[id]
    if type(index)~="number" or not palette[index] then
        local e=catalog[id]; local name=e and e.name or ""
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
    return {repeatPips=r.repeatPips==true,follow=type(r.follow)=="table" and r.follow or {}}
end
local function EditRule(e)
    local r=Rule(e); local copy={repeatPips=r.repeatPips,follow={}}
    for _,id in ipairs(r.follow) do copy.follow[#copy.follow+1]=id end
    cfg.rules[e.id]=copy; return copy
end
local function Curve(lo,hi,partial)
    local key=lo..":"..hi..":"..tostring(partial)
    if curves[key]~=nil then return curves[key] or nil,key end
    local ok,c=pcall(function()
        local curve=C_CurveUtil.CreateCurve()
        if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then curve:SetType(Enum.LuaCurveType.Linear) end
        local start=partial and lo or hi-.5
        local function Value(e)
            return math.max(0,math.min(1,(e-start)/math.max(.001,hi-start)))
        end
        local points={0,maxEnergy}
        if start>0 and start<maxEnergy then points[#points+1]=start end
        if hi>0 and hi<maxEnergy then points[#points+1]=hi end
        table.sort(points)
        for _,e in ipairs(points) do curve:AddPoint(e/maxEnergy,Value(e)) end
        return curve
    end)
    curves[key]=ok and c or false
    return curves[key] or nil,key
end
local function NewPip(parent)
    local f=CreateFrame("Frame",nil,parent); f:EnableMouse(false)
    local bg=f:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(f)
    local bar=CreateFrame("StatusBar",nil,f); bar:EnableMouse(false); bar:SetAllPoints(f)
    bar:SetOrientation("VERTICAL"); bar:SetMinMaxValues(0,1); bar:SetValue(0)
    return {frame=f,bg=bg,bar=bar}
end
local function Clear(record)
    local r=tracked[record]
    if r then r.frame:Hide() end
end
C.Clear=Clear
function C.Hide() for _,r in pairs(tracked) do r.frame:Hide() end end
local function Setup(record,entry)
    local rule=Rule(entry)
    local defs={}
    local previous=0
    if rule.repeatPips then
        for n=1,cfg.maxPips do
            local threshold=RepeatThreshold(entry.cost,n,cfg.regen)
            if threshold>maxEnergy and (not cfg.fraction or previous>=maxEnergy) then break end
            defs[#defs+1]={lo=previous,hi=threshold,partial=cfg.fraction,kind="repeat",id=entry.id,n=n}
            previous=threshold
            if threshold>maxEnergy then break end
        end
    end
    local count,seen=0,{}
    for _,id in ipairs(rule.follow) do
        local e=catalog[id]
        if e and e.current and id~=entry.id and not seen[id] and not api.excluded({spellID=id,category=e.category}) then
            local threshold=FollowThreshold(entry.cost,e.cost,cfg.regen)
            if threshold<=maxEnergy then
                defs[#defs+1]={lo=0,hi=threshold,partial=false,kind="follow",id=id,n=count+1}
                count=count+1; seen[id]=true
            end
            if count>=3 then break end
        end
    end
    if #defs==0 then if tracked[record] then tracked[record].count=0 end; Clear(record); return end
    local r=tracked[record]
    if not r then
        if InCombatLockdown and InCombatLockdown() then return end
        local frame=CreateFrame("Frame",nil,record.comboGate)
        frame:EnableMouse(false); frame:SetAllPoints(record.frame); frame:SetFrameLevel(record.frame:GetFrameLevel()+9); frame:Hide()
        r={frame=frame,pips={}}; tracked[record]=r
    end
    r.count=#defs; r.frame:SetAlpha(cfg.opacity)
    for i,d in ipairs(defs) do
        local p=r.pips[i]
        if not p then
            if InCombatLockdown and InCombatLockdown() then r.count=i-1; break end
            p=NewPip(r.frame); r.pips[i]=p
        end
        local texture=d.kind=="repeat" and CIRCLE or DIAMOND
        p.frame:SetSize(cfg.size,cfg.size); p.frame:ClearAllPoints()
        if d.kind=="repeat" then
            p.frame:SetPoint("TOPLEFT",r.frame,"TOPLEFT",1+(d.n-1)*(cfg.size+cfg.spacing),cfg.offset-1)
        else
            p.frame:SetPoint("BOTTOMLEFT",r.frame,"BOTTOMLEFT",1+(d.n-1)*(cfg.size+cfg.spacing),-cfg.offset+1)
        end
        p.bg:SetTexture(texture); p.bg:SetVertexColor(.15,.13,.11,.85)
        p.bar:SetStatusBarTexture(texture)
        local color=GetColor(d.id); p.bar:SetStatusBarColor(color[1],color[2],color[3],1)
        p.curve,p.key=Curve(d.lo,d.hi,d.partial and d.hi>d.lo)
        -- Hide-inactive uses a separate readiness curve, not a Lua test on energy.
        p.alphaCurve,p.alphaKey=Curve(0,d.partial and math.min(d.hi,d.lo+.5) or d.hi,false)
        p.bar:SetValue(0); p.frame:SetAlpha(1); p.frame:Show()
    end
    for i=r.count+1,#r.pips do r.pips[i].frame:Hide() end
end
function C.Sync(records,max)
    if not cfg or not api then return end
    Remember(records); maxEnergy=max
    local bits={tostring(cfg.enabled),cfg.template,tostring(cfg.fraction),tostring(cfg.hideInactive),cfg.size,cfg.spacing,cfg.opacity,cfg.offset,cfg.regen,cfg.maxPips,max}
    for _,e in ipairs(ordered) do
        local r=Rule(e); bits[#bits+1]=e.id..":"..e.cost..":"..tostring(r.repeatPips)..":"..select(2,GetColor(e.id))
        for _,id in ipairs(r.follow) do bits[#bits+1]=tostring(id) end
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
                    if not ok then errorText=tostring(err); Clear(r) end
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
                p.bar:SetValue(value)
                if cfg.hideInactive then
                    local alpha,good=Sample(p.alphaCurve,p.alphaKey)
                    if good then p.frame:SetAlpha(alpha) else p.frame:SetAlpha(0) end
                else p.frame:SetAlpha(1) end
                p.frame:Show()
            else p.frame:Hide() end
        end
        r.frame:Show()
    end)
    if not ok then errorText=tostring(err); Clear(record) end
end
function C.Status()
    if not cfg then return "not initialized" end
    return (cfg.enabled and "on" or "off").." | "..cfg.template.." | "..cfg.regen.." assumed energy/GCD | "..#ordered.." discovered | last error "..errorText
end
function C.Command(arg)
    if arg=="on" then cfg.enabled=true
    elseif arg=="off" then cfg.enabled=false
    elseif arg=="minimal" or arg=="builders" or arg=="pvp" or arg=="finishers" or arg=="custom" then cfg.template=arg; cfg.rules={}; cfg.enabled=true
    else return false end
    signature=nil; return true
end
function C.Open()
    if not cfg then return end
    if not panel then
        panel=CreateFrame("Frame","RogueEnergySweepChainsOptions",UIParent,"BasicFrameTemplateWithInset")
        panel:SetSize(508,482); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
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
        Text("Templates replace custom rules. Circles = repeats; diamonds = alternatives.",16,-64)
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
        Text("Choose up to 3 alternative follow-ups (energy only).",16,-302)
        local choices={}
        for i=1,6 do
            local x=16+((i-1)%2)*242; local y=-320-math.floor((i-1)/2)*25
            local l=Text("",x+28,y-6)
            local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate"); b:SetSize(24,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y)
            local row={b=b,l=l}
            b:SetScript("OnClick",function(self)
                local e=ordered[index]; if not e or not row.id then return end
                local r=EditRule(e); local found
                for j,id in ipairs(r.follow) do if id==row.id then found=j; break end end
                if self:GetChecked() and not found and #r.follow<3 then r.follow[#r.follow+1]=row.id
                elseif not self:GetChecked() and found then table.remove(r.follow,found) end
                signature=nil; api.apply()
            end)
            choices[i]=row
        end
        local page=Text("",195,-403)
        Button("Prev targets",16,-397,105,function() targetPage=targetPage-1; refresh() end)
        Button("Next targets",382,-397,105,function() targetPage=targetPage+1; refresh() end)
        Text("Assumes one GCD between presses; ignores refunds, cooldowns and combo changes.",16,-438)
        Button("Done",398,-452,90,function() panel:Hide() end)
        refresh=function()
            syncing=true
            enabled:SetChecked(cfg.enabled); fraction:SetChecked(cfg.fraction); hide:SetChecked(cfg.hideInactive)
            for key,b in pairs(templates) do if b.LockHighlight and b.UnlockHighlight then if cfg.template==key then b:LockHighlight() else b:UnlockHighlight() end end end
            for key,row in pairs(sliders) do row.b:SetValue(cfg[key]*row.factor); row.l:SetText(row.t..": "..math.floor(cfg[key]*row.factor+.5)) end
            index=math.max(1,math.min(index,#ordered))
            local e=ordered[index]; selected:SetText(e and (e.name.." ("..e.cost..")") or "No discovered abilities")
            local r=e and Rule(e) or {follow={}}
            repeatBox:SetChecked(r.repeatPips==true)
            if e then repeatBox:Enable(); color:Enable(); local c=GetColor(e.id); swatch:SetVertexColor(c[1],c[2],c[3],1)
            else repeatBox:Disable(); color:Disable() end
            local targets={}
            for _,n in ipairs(ordered) do if e and n.id~=e.id then targets[#targets+1]=n end end
            local pages=math.max(1,math.ceil(#targets/6)); targetPage=math.max(1,math.min(targetPage,pages)); page:SetText(targetPage.." / "..pages)
            local chosen={}; for _,id in ipairs(r.follow) do chosen[id]=true end
            for i,row in ipairs(choices) do
                local n=targets[(targetPage-1)*6+i]; row.id=n and n.id
                if n then row.b:Show(); row.l:Show(); row.l:SetText(n.name.." ("..n.cost..")"); row.b:SetChecked(chosen[n.id]==true)
                    if chosen[n.id] or #r.follow<3 then row.b:Enable() else row.b:Disable() end
                else row.b:Hide(); row.l:Hide() end
            end
            syncing=false
        end
    end
    panel:Show(); refresh()
end
