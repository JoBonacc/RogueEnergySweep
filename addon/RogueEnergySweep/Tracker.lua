-- Standalone, nonsecure Energy Tracker. All live progress comes from the
-- main engine's native energy curves and countdown snapshots.
local _,ns=...
local T={}
ns.Tracker=T
local api,db,cfg,root,panel,refresh,signature
local catalog,rows,byCost,costs,pool={},{},{},{},{}
local dial,maximum,active,lastError,source=nil,100,false,"none","not evaluated"
local layoutOK=false
local WHITE="Interface\\Buttons\\WHITE8X8"
local DIAL="Interface\\AddOns\\RogueEnergySweep\\TrackerDial"
local RING="Interface\\AddOns\\RogueEnergySweep\\TrackerRing"
local layouts={dial=true,bars=true,icons=true,freeform=true,rings=true}
local modes={rising=true,bar=true,perimeter=true,radial=true}
local colors={amber={1,.78,.16},white={1,1,1},cyan={.22,.85,1},green={.3,1,.35},red={1,.24,.24},purple={.72,.42,1},orange={1,.48,.12}}
local function number(v,default,lo,hi)
    if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then v=default end
    return math.max(lo,math.min(hi,v))
end
local function Normalize(c)
    c=type(c)=="table" and c or {}
    c.enabled=c.enabled==true; c.actionBars=not c.enabled or c.actionBars~=false
    c.layout=layouts[c.layout] and c.layout or "dial"
    c.iconMode=modes[c.iconMode] and c.iconMode or "rising"
    c.color=colors[c.color] and c.color or "amber"
    c.opacity=number(c.opacity,.9,.15,1)
    c.scale=number(c.scale,1,.5,2)
    c.iconSize=number(c.iconSize,40,24,64)
    c.barWidth=number(c.barWidth,200,100,320)
    c.barHeight=number(c.barHeight,18,12,32)
    c.spacing=number(c.spacing,7,2,24)
    c.x=number(c.x,0,-4000,4000); c.y=number(c.y,-180,-4000,4000)
    c.locked=c.locked~=false; c.auto=c.auto~=false; c.vertical=c.vertical==true
    c.showNames=c.showNames~=false; c.showCosts=c.showCosts~=false
    c.hideReady=c.hideReady==true; c.readyEffects=c.readyEffects~=false
    c.selected=type(c.selected)=="table" and c.selected or {}
    c.positions=type(c.positions)=="table" and c.positions or {}
    return c
end
function T.Configure(a) api=a end
function T.Init(d)
    db=d; db.tracker=Normalize(db.tracker); cfg=db.tracker; signature=nil
end
function T.Appearance()
    return {mode=cfg.iconMode,color=cfg.color,customColor=nil,opacity=cfg.opacity,thickness=3,tint=true,tintOpacity=.25,fillEffect="luminous",reverse=false,
        readyEffect=cfg.readyEffects and db.readyEffect or "none"}
end
local function Color() return unpack(colors[cfg.color]) end
local function Label(parent,text,size)
    local f=parent:CreateFontString(nil,"OVERLAY",size or "GameFontHighlightSmall")
    f:SetText(text); return f
end
local function Texture(parent,path,layer)
    local t=parent:CreateTexture(nil,layer or "ARTWORK"); t:SetTexture(path); return t
end
local function Frame(parent)
    local f=CreateFrame("Frame",nil,parent); f:EnableMouse(false); return f
end
local function Bar(parent,texture,radial)
    local b=CreateFrame("StatusBar",nil,parent); b:EnableMouse(false)
    b:SetStatusBarTexture(texture or WHITE); b:SetMinMaxValues(0,1); b:SetValue(0)
    if radial then
        local ok=pcall(function() b:SetRenderMode(Enum and Enum.StatusBarRenderMode and Enum.StatusBarRenderMode.Radial or 1) end)
        if not ok then b:Hide(); return nil end
    end
    return b
end
local function SetRange(bar,fill,group,direct)
    if not bar then return false end
    local ok=pcall(function()
        if direct then bar:SetMinMaxValues(group.start,1) else bar:SetMinMaxValues(0,1) end
        bar:SetValue(fill)
    end)
    if not ok and direct then
        ok=pcall(function() bar:SetMinMaxValues(0,1); bar:SetValue(fill) end)
    end
    if ok then bar:Show() else bar:Hide() end
    return ok
end
local function DialPoint(cost,max,radius)
    local a=math.min(1,math.max(0,cost/max))*math.pi*1.5
    return -math.sin(a)*radius,-math.cos(a)*radius
end
local function SortedEntries(c,selection,auto,excluded)
    local entries={}
    for id,e in pairs(c) do
        if e.cost and e.cost>0 and (auto and e.current or not auto and selection[id]) and not excluded(e) then entries[#entries+1]=e end
    end
    table.sort(entries,function(a,b)
        if a.cost~=b.cost then return a.cost<b.cost end
        return a.spellID<b.spellID
    end)
    return entries
end
local function SpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok,info=pcall(C_Spell.GetSpellInfo,id)
        if ok and not api.secret(info) and type(info)=="table" then
            local name=not api.secret(info.name) and type(info.name)=="string" and info.name or nil
            return name or ("Spell "..id),api.safe(info.iconID) or 134400
        end
    end
    return "Spell "..id,134400
end
local function Remember(records)
    for _,e in pairs(catalog) do e.current=false end
    for _,r in ipairs(records) do
        if r.cost and r.cost>0 and r.spellID then
            local e=catalog[r.spellID]
            if not e then
                local name,icon=SpellInfo(r.spellID)
                e={spellID=r.spellID,name=name,icon=icon}; catalog[r.spellID]=e
            end
            e.cost=r.cost; e.finisher=r.finisher; e.category=r.category; e.current=true
        end
    end
    -- Explicitly selected abilities survive page swaps in this session;
    -- on reload, include off-bar spells only if a public known-spell API agrees.
    if not cfg.auto then
        for id,selected in pairs(cfg.selected) do
            if selected and type(id)=="number" and (not catalog[id] or not catalog[id].current) then
                local known=catalog[id]~=nil
                local checker=IsPlayerSpell or IsSpellKnown
                if type(checker)=="function" then
                    local ok,v=pcall(checker,id)
                    if ok and not api.secret(v) and type(v)=="boolean" then known=v end
                end
                if known then
                    local cost,has,_,finisher=api.cost(id)
                    if has and cost and cost>0 then
                        local e=catalog[id]
                        if not e then local name,icon=SpellInfo(id); e={spellID=id,name=name,icon=icon}; catalog[id]=e end
                        e.cost=cost; e.finisher=finisher; e.category=api.category(id,finisher)
                    elseif catalog[id] then catalog[id].cost=nil end
                elseif catalog[id] then catalog[id].cost=nil end
            end
        end
    end
end
local function SaveRoot()
    local x,y=root:GetCenter(); local ux,uy=UIParent:GetCenter()
    if api.safe(x) and api.safe(y) and api.safe(ux) and api.safe(uy) then
        local ratio=root:GetEffectiveScale()/UIParent:GetEffectiveScale()
        cfg.x=x*ratio-ux; cfg.y=y*ratio-uy
    end
end
local function PositionRoot()
    root:ClearAllPoints()
    root:SetPoint("CENTER",UIParent,"CENTER",cfg.x/cfg.scale,cfg.y/cfg.scale)
end
local function EnsureRoot()
    if root then return end
    root=Frame(UIParent); root:SetFrameStrata("MEDIUM"); root:SetMovable(true); root:SetClampedToScreen(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart",function(self) if not cfg.locked then self:StartMoving() end end)
    root:SetScript("OnDragStop",function(self) self:StopMovingOrSizing(); SaveRoot(); PositionRoot() end)
    root.handle=Label(root,"ENERGY TRACKER  •  drag to move","GameFontNormalSmall")
    root.handle:SetPoint("TOP",root,"TOP",0,12)
    root.back=Texture(root,WHITE,"BACKGROUND"); root.back:SetAllPoints(root); root.back:SetVertexColor(.08,.07,.05,.5); root.back:Hide()
    root:Hide()
end
local function ClearRow(row)
    if row.overlay then api.clear(row.overlay); api.clearReady(row.overlay) end
    row.frame:Hide()
end
function T.Hide()
    if active then for _,row in ipairs(rows) do ClearRow(row) end end
    if root then root:Hide() end
    active=false
end
local function MakeIcon(parent)
    local f=Frame(parent); f.icon=Texture(f,WHITE,"BACKGROUND"); f.icon:SetAllPoints(f)
    local border=Texture(f,WHITE,"BORDER"); border:SetPoint("TOPLEFT",f,"TOPLEFT",-1,1); border:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",1,-1)
    border:SetVertexColor(.22,.18,.10,.9)
    -- Keep the border behind the icon by putting icon on ARTWORK instead.
    f.icon:SetDrawLayer("ARTWORK")
    return f
end
local function NewRow(index)
    local frame=Frame(root); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    local cooldown=Frame(frame); cooldown:SetAllPoints(frame)
    local combo=Frame(cooldown); combo:SetAllPoints(cooldown)
    local row={frame=frame,cooldown=cooldown,combo=combo}
    row.icon=MakeIcon(combo)
    row.overlay=api.make(row.icon)
    row.bright=Texture(row.icon,WHITE,"OVERLAY"); row.bright:SetAllPoints(row.icon); row.bright:Hide()
    row.labels=Frame(combo); row.labels:SetAllPoints(combo); row.labels:SetFrameLevel(combo:GetFrameLevel()+8)
    row.name=Label(row.labels,""); row.costLabel=Label(row.labels,"")
    row.track=Texture(combo,WHITE,"BACKGROUND"); row.track:SetVertexColor(.11,.11,.11,.8)
    row.bar=Bar(combo)
    row.ringTrack=Texture(combo,RING,"BACKGROUND"); row.ringTrack:SetVertexColor(.26,.23,.17,.8)
    row.ring=Bar(combo,RING,true)
    row.connector=Texture(combo,WHITE,"BACKGROUND"); row.connector:SetColorTexture(.66,.55,.33,.65)
    row.marker=Texture(combo,WHITE,"ARTWORK"); row.marker:SetColorTexture(.92,.78,.46,.8)
    frame:SetScript("OnDragStart",function(self) if not cfg.locked and cfg.layout=="freeform" then self:StartMoving() end end)
    frame:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        if row.spellID then
            local x,y=self:GetCenter(); local a,b=root:GetCenter()
            if api.safe(x) and api.safe(y) and api.safe(a) and api.safe(b) then
                cfg.positions[row.spellID]={x=x-a,y=y-b}
                self:ClearAllPoints(); self:SetPoint("CENTER",root,"CENTER",x-a,y-b)
            end
        end
    end)
    pool[index]=row; return row
end
local function SetLocked()
    if not root then return end
    root:EnableMouse(not cfg.locked); root.handle:SetShown(not cfg.locked); root.back:SetShown(not cfg.locked)
    for _,row in ipairs(rows) do row.frame:EnableMouse(not cfg.locked and cfg.layout=="freeform") end
end
local function SetupDial()
    if not dial then
        local frame=Frame(root)
        local track=Texture(frame,DIAL,"BACKGROUND"); track:SetAllPoints(frame); track:SetVertexColor(.34,.30,.23,.85)
        local fill=Texture(frame,DIAL,"ARTWORK"); fill:SetAllPoints(frame)
        local native=pcall(function()
            fill:SetRadialProgressBarReverse(false)
            fill:SetRadialProgressBarPercent(0)
        end)
        local label=Label(frame,"ENERGY","GameFontNormalLarge"); label:SetPoint("CENTER",frame,"CENTER",0,7)
        local caption=Label(frame,"ENERGY","GameFontHighlightSmall"); caption:SetPoint("TOP",label,"BOTTOM",0,-3)
        local backup=Bar(frame); backup:SetSize(100,8); backup:SetPoint("CENTER",frame,"CENTER",0,-22); backup:Hide()
        dial={frame=frame,track=track,fill=fill,native=native,label=label,caption=caption,backup=backup}
    end
    dial.frame:SetSize(156,156); dial.frame:SetPoint("CENTER",root,"CENTER")
    local r,g,b=Color(); dial.fill:SetVertexColor(r,g,b,cfg.opacity); dial.backup:SetStatusBarColor(r,g,b,cfg.opacity)
    dial.curve=api.curve(maximum,"dial"); dial.fullCurve=api.curve(maximum,"fill")
    dial.frame:Show()
end
local function Layout(entries)
    EnsureRoot()
    root:SetScale(cfg.scale); PositionRoot()
    local n=#entries; local size=cfg.iconSize; local gap=cfg.spacing
    local dialPositions,lanes={},{}
    local extent=130
    if cfg.layout=="dial" then
        for i,e in ipairs(entries) do
            local a=math.min(1,e.cost/maximum)*270
            local lane=1
            -- Keep close-cost icons in distinct radial lanes. Their markers
            -- still remain at the exact same public resource threshold.
            while lanes[lane] and a-lanes[lane]<math.max(24,size*.8) do lane=lane+1 end
            lanes[lane]=a
            local radius=92+(lane-1)*(size+gap)
            local x,y=DialPoint(e.cost,maximum,radius)
            dialPositions[i]={x=x,y=y}
            extent=math.max(extent,math.abs(x)+size*.5+12,math.abs(y)+size*.5+22)
        end
    end
    local clusterSize=math.max(174,size*3.8)
    local clusterWidth=clusterSize+size+110
    local w,h=math.max(1,n)*(size+gap)-gap,size
    if cfg.layout=="bars" then w=cfg.barWidth+size+8; h=math.max(1,n)*(math.max(size,cfg.barHeight)+gap)-gap
    elseif cfg.layout=="dial" then w,h=extent*2,extent*2
    elseif cfg.layout=="rings" then w=clusterWidth; h=math.max(1,math.ceil(n/4))*(clusterSize+gap)-gap
    elseif cfg.layout=="freeform" then w,h=360,190
    elseif cfg.vertical then w,h=size,w end
    root:SetSize(math.max(w,1),math.max(h,1))
    if dial then dial.frame:Hide() end
    if cfg.layout=="dial" then SetupDial() end
    local r,g,b=Color()
    for i,e in ipairs(entries) do
        local row=pool[i] or NewRow(i)
        rows[i]=row; row.spellID=e.spellID; row.cost=e.cost; row.finisher=e.finisher; row.category=e.category
        row.overlay.spellID=e.spellID; row.overlay.finisher=e.finisher
        row.frame:ClearAllPoints(); row.icon:ClearAllPoints(); row.name:ClearAllPoints(); row.costLabel:ClearAllPoints()
        row.bar:ClearAllPoints(); row.track:ClearAllPoints(); row.ringTrack:ClearAllPoints()
        if row.ring then row.ring:ClearAllPoints(); row.ring:Hide() end
        row.connector:Hide(); row.marker:Hide(); row.track:Hide(); row.bar:Hide(); row.ringTrack:Hide(); row.bright:Hide()
        api.clear(row.overlay); api.clearReady(row.overlay)
        row.icon.icon:SetTexture(e.icon); row.icon.icon:SetVertexColor(1,1,1,1)
        row.bright:SetTexture(e.icon); row.bright:SetVertexColor(1,1,1,1)
        row.name:SetText(e.name); row.costLabel:SetText(tostring(e.cost))
        row.name:Hide(); row.costLabel:Hide()
        row.icon:SetSize(size,size)
        if cfg.layout=="bars" then
            local rh=math.max(size,cfg.barHeight)
            row.frame:SetSize(w,rh); row.frame:SetPoint("TOPLEFT",root,"TOPLEFT",0,-(i-1)*(rh+gap))
            row.icon:SetPoint("LEFT",row.combo,"LEFT")
            row.bar:SetSize(cfg.barWidth,cfg.barHeight); row.bar:SetPoint("LEFT",row.icon,"RIGHT",8,0)
            row.track:SetAllPoints(row.bar); row.track:Show()
            row.bar:SetStatusBarColor(r,g,b,cfg.opacity)
            row.name:SetPoint("LEFT",row.bar,"LEFT",5,0); row.costLabel:SetPoint("RIGHT",row.bar,"RIGHT",-5,0)
        elseif cfg.layout=="dial" then
            local x,y=dialPositions[i].x,dialPositions[i].y
            local ix,iy=DialPoint(e.cost,maximum,69)
            row.frame:SetSize(size,size); row.frame:SetPoint("CENTER",root,"CENTER",x,y)
            row.icon:SetPoint("CENTER",row.combo,"CENTER")
            row.costLabel:SetPoint("TOP",row.icon,"BOTTOM",0,-1)
            row.marker:ClearAllPoints(); row.marker:SetPoint("CENTER",root,"CENTER",ix,iy); row.marker:SetSize(4,4); row.marker:Show()
            row.icon.icon:SetVertexColor(.45,.45,.45,1)
            row.bright:SetAlpha(0); row.bright:Show()
        elseif cfg.layout=="rings" then
            local slot=(i-1)%4
            local cluster=math.floor((i-1)/4)
            local diameter=clusterSize*(1-slot*.19)
            local iconSize=math.min(size,clusterSize/4-5)
            row.frame:SetSize(clusterWidth,clusterSize); row.frame:SetPoint("TOPLEFT",root,"TOPLEFT",0,-cluster*(clusterSize+gap))
            row.icon:SetSize(iconSize,iconSize)
            row.icon:SetPoint("TOPLEFT",row.combo,"TOPLEFT",clusterSize+8,-slot*clusterSize/4-2)
            row.ringTrack:SetSize(diameter,diameter); row.ringTrack:SetPoint("LEFT",row.combo,"LEFT",(clusterSize-diameter)/2,0); row.ringTrack:Show()
            -- Modulate the shared hue slightly so adjacent rings are distinguishable.
            local shade=1-slot*.12
            if row.ring then row.ring:SetAllPoints(row.ringTrack); row.ring:SetStatusBarColor(r*shade,g*shade,b*shade,cfg.opacity)
            else row.bar:SetSize(70,5); row.bar:SetPoint("LEFT",row.icon,"RIGHT",5,-8); row.bar:SetStatusBarColor(r,g,b,cfg.opacity); row.track:SetAllPoints(row.bar); row.track:Show() end
            row.name:SetPoint("LEFT",row.icon,"RIGHT",5,5); row.costLabel:SetPoint("LEFT",row.icon,"RIGHT",5,-8)
        else
            row.frame:SetSize(size,size)
            if cfg.layout=="freeform" then
                local p=cfg.positions[e.spellID]
                local x=type(p)=="table" and number(p.x,0,-2000,2000) or ((i-1)%6-2.5)*(size+gap)
                local y=type(p)=="table" and number(p.y,0,-2000,2000) or 45-math.floor((i-1)/6)*(size+gap)
                row.frame:SetPoint("CENTER",root,"CENTER",x,y)
            else row.frame:SetPoint("TOPLEFT",root,"TOPLEFT",cfg.vertical and 0 or (i-1)*(size+gap),cfg.vertical and -(i-1)*(size+gap) or 0) end
            row.icon:SetPoint("CENTER",row.combo,"CENTER"); row.costLabel:SetPoint("TOP",row.icon,"BOTTOM",0,-1)
        end
        if cfg.showNames and (cfg.layout=="bars" or cfg.layout=="rings") then row.name:Show() end
        if cfg.showCosts then row.costLabel:Show() end
        api.style(row.overlay)
        row.frame:SetAlpha(1); row.combo:SetAlpha(1); row.cooldown:SetAlpha(1); row.frame:Show()
        byCost[e.cost]=byCost[e.cost] or {}; table.insert(byCost[e.cost],row); costs[e.cost]=true
    end
    for i=n+1,#pool do ClearRow(pool[i]) end
    SetLocked()
end
function T.Sync(records,maxEnergy)
    if not cfg or not api then return false end
    maximum=maxEnergy
    Remember(records)
    local entries=cfg.enabled and SortedEntries(catalog,cfg.selected,cfg.auto,api.excluded) or {}
    local bits={tostring(cfg.enabled),cfg.layout,cfg.iconMode,cfg.color,cfg.opacity,cfg.scale,cfg.iconSize,cfg.barWidth,cfg.barHeight,cfg.spacing,tostring(cfg.vertical),tostring(cfg.showNames),tostring(cfg.showCosts),tostring(cfg.readyEffects),tostring(maximum)}
    for _,e in ipairs(entries) do bits[#bits+1]=e.spellID..":"..e.cost..":"..tostring(e.finisher)..":"..tostring(e.category) end
    local key=table.concat(bits,"|")
    if signature==key then SetLocked(); if refresh and panel:IsShown() then refresh() end; return false end
    signature=key; T.Hide(); rows={}; byCost={}; costs={}; layoutOK=false
    if cfg.enabled then
        local ok,err=pcall(Layout,entries)
        layoutOK=ok
        if not ok then lastError=tostring(err); if root then root:Hide() end; rows={}; byCost={}; costs={} else lastError="none" end
    end
    if refresh and panel:IsShown() then refresh() end
    return true
end
function T.Costs() return costs end
function T.Begin(demo)
    if not cfg or not cfg.enabled or not root or not layoutOK or (#rows==0 and cfg.layout~="dial") then T.Hide(); return false end
    active=true; root:Show(); return true
end
function T.Group(cost,group,fill,deficit,visibility,ready,valid,direct,combo,comboEnabled,cooldowns,cooldownEnabled,demo)
    if not byCost[cost] then return end
    for _,row in ipairs(byCost[cost]) do
        local ok,err=pcall(function()
            if not valid then ClearRow(row); return end
            local c=1
            if comboEnabled and row.finisher then c=combo end
            local cd=1
            if cooldownEnabled then
                local cached=cooldowns[row.spellID]
                if not cached then local value,why=api.cooldown(row.spellID); cached={value=value,source=why}; cooldowns[row.spellID]=cached end
                cd=cached.value
            end
            -- Independent native alpha layers preserve protected gates.
            local comboOK=pcall(row.combo.SetAlpha,row.combo,c)
            if not comboOK then row.combo:SetAlpha(0) end
            local cdOK=pcall(row.cooldown.SetAlpha,row.cooldown,cd)
            if not cdOK then row.cooldown:SetAlpha(1) end
            if cfg.hideReady and cfg.layout~="dial" then row.frame:SetAlpha(visibility) else row.frame:SetAlpha(1) end
            row.frame:Show()
            if cfg.layout=="bars" then SetRange(row.bar,fill,group,direct)
            elseif cfg.layout=="rings" then SetRange(row.ring or row.bar,fill,group,direct)
            elseif cfg.layout=="dial" then
                if api.secret(ready) or api.safe(ready)~=nil then
                    if not pcall(row.bright.SetAlpha,row.bright,ready) then row.bright:SetAlpha(0) end
                else row.bright:SetAlpha(0) end
            else api.paint(row.overlay,fill,deficit,visibility,group,direct) end
            api.ready(row.overlay,ready,not demo and not cfg.hideReady and comboOK and cdOK and api.safe(c)~=0 and api.safe(cd)~=0)
        end)
        if not ok then lastError=tostring(err); ClearRow(row) end
    end
end
function T.Finish(demo)
    if cfg.layout~="dial" or not dial then return end
    local ok,err=pcall(function()
        local value,valid
        if demo then value,valid=.375,true else value,valid=api.evaluate(dial.curve) end
        local raw
        if demo then raw=maximum/2 elseif type(UnitPower)=="function" then local success,v=pcall(UnitPower,"player",Enum and Enum.PowerType and Enum.PowerType.Energy or 3); if success then raw=api.safe(v) end end
        if not valid and raw then value=.75*math.max(0,math.min(1,raw/maximum)); valid=true end
        if raw then dial.label:SetText(tostring(math.floor(raw+.5))); dial.caption:Show()
        else dial.label:SetText("ENERGY"); dial.caption:Hide() end
        if valid and dial.native and pcall(dial.fill.SetRadialProgressBarPercent,dial.fill,value) then
            dial.fill:Show(); dial.backup:Hide(); source="native radial"
        else
            local full,good
            if demo then full,good=.5,true else full,good=api.evaluate(dial.fullCurve) end
            if not good and raw then full,good=math.max(0,math.min(1,raw/maximum)),true end
            dial.fill:Hide()
            if good then SetRange(dial.backup,full,{},false); source="linear fallback" else dial.backup:Hide(); source="unavailable" end
        end
    end)
    if not ok then lastError=tostring(err); source="unavailable"; dial.fill:Hide(); dial.backup:Hide() end
end
function T.Status()
    if not cfg then return "not initialized" end
    return (cfg.enabled and cfg.layout or "off").." | "..#rows.." abilities | action bars "..tostring(cfg.actionBars).." | dial "..source.." | last error "..lastError
end
function T.Command(arg)
    if arg=="on" then cfg.enabled=true
    elseif arg=="off" then cfg.enabled=false; cfg.actionBars=true
    elseif arg=="lock" then cfg.locked=true
    elseif arg=="unlock" then cfg.locked=false
    elseif layouts[arg] then cfg.layout=arg; cfg.enabled=true
    else return false end
    return true
end
function T.Open()
    if not cfg then return end
    if not panel then
        panel=CreateFrame("Frame","RogueEnergySweepTrackerOptions",UIParent,"BasicFrameTemplateWithInset")
        panel:SetSize(500,548); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
        if panel.TitleText then panel.TitleText:SetText("Energy Tracker") end
        if UISpecialFrames then table.insert(UISpecialFrames,panel:GetName()) end
        local function Text(text,x,y)
            local f=Label(panel,text); f:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); return f
        end
        local function Button(text,x,y,w,click)
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate"); b:SetSize(w,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",click); return b
        end
        local function Change(key,value)
            cfg[key]=value
            if key=="actionBars" and not value then cfg.enabled=true end
            if key=="enabled" and not value then cfg.actionBars=true end
            api.apply()
        end
        local checks={}
        local function Check(key,text,x,y)
            local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
            b:SetSize(24,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y)
            local l=Text(text,x+28,y-6)
            local hit=CreateFrame("Button",nil,panel); hit:SetPoint("TOPLEFT",l,"TOPLEFT",-2,3); hit:SetPoint("BOTTOMRIGHT",l,"BOTTOMRIGHT",3,-3)
            hit:SetScript("OnClick",function() b:Click() end)
            b:SetScript("OnClick",function(self) Change(key,self:GetChecked() and true or false) end)
            checks[key]=b
        end
        Check("enabled","Enable tracker",16,-34); Check("actionBars","Action-bar overlays",245,-34)
        Check("locked","Lock position",16,-60); Check("vertical","Vertical icons",245,-60)
        local buttons={}
        for i,e in ipairs({{"dial","Dial"},{"bars","Bars"},{"icons","Icons"},{"freeform","Freeform"},{"rings","Rings"}}) do
            local key=e[1]; buttons[key]=Button(e[2],16+(i-1)*94,-88,90,function() Change("layout",key) end)
        end
        local styles={}
        for i,e in ipairs({{"rising","Rising"},{"bar","Bottom"},{"perimeter","Perimeter"},{"radial","Radial"}}) do
            local key=e[1]; styles[key]=Button(e[2],16+(i-1)*117,-118,113,function() Change("iconMode",key) end)
        end
        local syncing=false
        local sliders={}
        local function Slider(key,label,x,y,lo,hi,step,factor)
            local l=Text(label,x,y)
            local b=CreateFrame("Slider","RogueEnergySweepTracker"..key,panel,"OptionsSliderTemplate")
            b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y-18); b:SetSize(210,16); b:SetMinMaxValues(lo,hi); b:SetValueStep(step)
            if b.SetObeyStepOnDrag then b:SetObeyStepOnDrag(true) end
            for _,suffix in ipairs({"Text","Low","High"}) do local t=_G[b:GetName()..suffix]; if t then t:SetText("") end end
            b:SetScript("OnValueChanged",function(_,v) if not syncing then Change(key,math.floor(v+.5)/factor) end end)
            sliders[key]={bar=b,label=l,text=label,factor=factor}
        end
        Slider("scale","Scale %",16,-151,50,200,5,100); Slider("opacity","Opacity %",250,-151,15,100,5,100)
        Slider("iconSize","Icon size",16,-190,24,64,2,1); Slider("spacing","Spacing",250,-190,2,24,1,1)
        Slider("barWidth","Bar width",16,-229,100,320,10,1); Slider("barHeight","Bar height",250,-229,12,32,2,1)
        local colorButtons={}
        for i,key in ipairs({"amber","white","cyan","green","red","purple","orange"}) do
            local b=Button("",16+(i-1)*38,-270,34,function() Change("color",key) end)
            local t=Texture(b,WHITE,"ARTWORK"); t:SetPoint("TOPLEFT",b,"TOPLEFT",5,-4); t:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-5,4)
            t:SetVertexColor(unpack(colors[key])); colorButtons[key]=b
        end
        Button("Reset position",304,-270,160,function() cfg.x,cfg.y=0,-180; cfg.positions={}; signature=nil; api.apply() end)
        Check("showNames","Ability names",16,-300); Check("showCosts","Energy costs",245,-300)
        Check("hideReady","Hide affordable rows",16,-326); Check("readyEffects","Ready effects",245,-326)
        Check("auto","Track all current bar abilities",16,-352)
        Text("Uncheck above to choose abilities. Selected off-page spells may persist.",16,-380)
        local page=1; local choices={}
        for i=1,6 do
            local x=16+((i-1)%2)*235; local y=-400-math.floor((i-1)/2)*28
            local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate"); b:SetSize(24,24); b:SetPoint("TOPLEFT",panel,"TOPLEFT",x,y)
            local l=Text("",x+28,y-6); local row={b=b,l=l}
            b:SetScript("OnClick",function(self) if row.id then cfg.selected[row.id]=self:GetChecked() and true or nil; api.apply() end end)
            choices[i]=row
        end
        local pageLabel=Text("",180,-492)
        local prev=Button("Previous",16,-485,90,function() page=page-1; refresh() end)
        local nextPage=Button("Next",365,-485,90,function() page=page+1; refresh() end)
        Button("Done",365,-514,90,function() panel:Hide() end)
        Text("Unlock to drag. Freeform icons can be dragged individually.",16,-521)
        local function Highlight(b,selected) if b.LockHighlight and b.UnlockHighlight then if selected then b:LockHighlight() else b:UnlockHighlight() end end end
        refresh=function()
            syncing=true
            for key,b in pairs(checks) do b:SetChecked(cfg[key]) end
            for key,b in pairs(buttons) do Highlight(b,key==cfg.layout) end
            for key,b in pairs(styles) do Highlight(b,key==cfg.iconMode); if cfg.layout=="icons" or cfg.layout=="freeform" then b:Enable() else b:Disable() end end
            for key,b in pairs(colorButtons) do Highlight(b,key==cfg.color) end
            for key,row in pairs(sliders) do row.bar:SetValue(cfg[key]*row.factor); row.label:SetText(row.text..": "..math.floor(cfg[key]*row.factor+.5)) end
            local entries={}; for _,e in pairs(catalog) do if e.cost and e.cost>0 then entries[#entries+1]=e end end
            table.sort(entries,function(a,b) if a.name==b.name then return a.spellID<b.spellID end return a.name<b.name end)
            local pages=math.max(1,math.ceil(#entries/#choices)); page=math.max(1,math.min(page,pages)); pageLabel:SetText(page.." / "..pages)
            if page>1 then prev:Enable() else prev:Disable() end
            if page<pages then nextPage:Enable() else nextPage:Disable() end
            for i,row in ipairs(choices) do
                local e=entries[(page-1)*#choices+i]; row.id=e and e.spellID or nil
                if e then row.b:Show(); row.l:Show(); row.l:SetText(e.name.." ("..e.cost..")"); row.b:SetChecked(cfg.auto and e.current or cfg.selected[e.spellID]==true); if cfg.auto then row.b:Disable() else row.b:Enable() end
                else row.b:Hide(); row.l:Hide() end
            end
            syncing=false
        end
    end
    panel:Show(); refresh()
end
