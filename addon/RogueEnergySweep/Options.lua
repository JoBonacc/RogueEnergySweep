-- Unified intent-based settings. Only this module creates the normal settings UI.
-- Native, nonsecure controls; no runtime energy sampling in the options window.
local _,ns=...
local O={}; ns.Options=O
local api,window,content,scroll,preview,previewRecords,launcher
local pools,used,nav={},{},{}
local page,sub="bars","home"
local busy,rendering,playing=false,false,false
local energy,start=15,15
local sourceID
local GOLD={1,.79,.35}
local WHITE={.93,.90,.84}
local MUTED={.70,.68,.63}
local BG={.12,.12,.13}
local W=512
local y=0
local function DB() return api.db() end
local function HidePreview()
    playing=false
    if window then window:SetScript("OnUpdate",nil) end
    if preview then preview:Hide(); if previewRecords then api.previewClear(previewRecords) end end
end
local function Take(kind,create)
    used[kind]=(used[kind] or 0)+1
    local i=used[kind]; pools[kind]=pools[kind] or {}
    local f=pools[kind][i]
    if not f then f=create(); pools[kind][i]=f end
    f:ClearAllPoints(); f:Show(); return f
end
local function Reset()
    HidePreview()
    for _,list in pairs(pools) do for _,f in ipairs(list) do f:Hide() end end
    used={}; y=12
end
local function At(f,x,top) f:SetPoint("TOPLEFT",content,"TOPLEFT",x,-top) end
local function Text(text,x,top,width,color,font)
    local f=Take("text",function() return content:CreateFontString(nil,"OVERLAY","GameFontHighlight") end)
    if f.SetFontObject then f:SetFontObject(font or GameFontHighlight) end
    f:SetTextColor(unpack(color or WHITE)); f:SetWidth(width or W-x); f:SetJustifyH("LEFT")
    if f.SetJustifyV then f:SetJustifyV("TOP") end
    f:SetText(text); At(f,x,top)
    return f
end
local function Rect(x,top,w,h,r,g,b,a)
    local f=Take("rect",function() return content:CreateTexture(nil,"ARTWORK") end)
    f:SetSize(w,h); At(f,x,top); f:SetColorTexture(r,g,b,a or 1); return f
end
local function Paragraph(text,color)
    local f=Text(text,0,y,W,color or MUTED)
    local h=f.GetStringHeight and f:GetStringHeight() or 18
    y=y+math.max(18,h)+9
end
local function Heading(title,desc)
    Text(title,0,y,W,GOLD,GameFontNormalLarge); y=y+27
    if desc then Paragraph(desc) end
end
local function Section(title,desc)
    y=y+8; Rect(0,y,W,1,.36,.30,.21,.8); y=y+12
    Text(title,0,y,W,GOLD,GameFontNormal); y=y+22
    if desc then Paragraph(desc) end
end
local Render
local function Commit(fn,rebuild)
    if busy or rendering then return end
    busy=true
    local ok,err=pcall(function() fn(); api.apply() end)
    busy=false
    if not ok then api.say("Settings change failed: "..tostring(err)) end
    if rebuild then O.Refresh() elseif page=="bars" and preview and preview:IsShown() then api.previewPaint(previewRecords,energy,start) end
end
local function Go(p,s)
    page=p; sub=s or "home"; if scroll then scroll:SetVerticalScroll(0) end
    O.Refresh()
end
local function Button(label,x,top,width,fn,selected,disabled)
    local b=Take("button",function() return CreateFrame("Button",nil,content,"UIPanelButtonTemplate") end)
    b:SetSize(width,25); At(b,x,top); b:SetText(label); b:SetScript("OnClick",fn)
    b:SetScript("OnEnter",nil); b:SetScript("OnLeave",nil)
    if b.resSwatch then b.resSwatch:Hide() end
    if b.LockHighlight and b.UnlockHighlight then if selected then b:LockHighlight() else b:UnlockHighlight() end end
    if disabled then b:Disable() else b:Enable() end
    return b
end
local function Link(label,fn)
    Button(label,0,y,W,fn); y=y+32
end
local function Check(label,value,fn,desc)
    local b=Take("check",function() return CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate") end)
    b:SetSize(24,24); At(b,0,y); b:SetChecked(value==true); b:Enable()
    local l=Text(label,30,y+5,W-30,WHITE)
    b:SetScript("OnClick",function(self) Commit(function() fn(self:GetChecked() and true or false) end,true) end)
    local hit=Take("hit",function() return CreateFrame("Button",nil,content) end)
    hit:SetPoint("TOPLEFT",l,"TOPLEFT",-2,3); hit:SetPoint("BOTTOMRIGHT",l,"BOTTOMRIGHT",2,-3)
    hit:SetScript("OnClick",function() b:Click() end)
    y=y+27
    if desc then local t=Text(desc,30,y,W-30,MUTED); y=y+math.max(16,t.GetStringHeight and t:GetStringHeight() or 16)+7 end
end
local function Slider(label,v,lo,hi,step,fn,unit,previewOnly)
    local l=Text(label..": "..v..(unit or ""),0,y,W,WHITE)
    local b=Take("slider",function()
        local name="RogueEnergySweepUnifiedSlider"..used.slider
        local slider=CreateFrame("Slider",name,content,"OptionsSliderTemplate")
        for _,suffix in ipairs({"Text","Low","High"}) do local t=_G[name..suffix]; if t then t:SetText("") end end
        return slider
    end)
    b:SetScript("OnValueChanged",nil); b:SetSize(W-16,16); At(b,6,y+22)
    b:SetMinMaxValues(lo,hi); b:SetValueStep(step); if b.SetObeyStepOnDrag then b:SetObeyStepOnDrag(true) end
    b:SetValue(v); b:Enable()
    b:SetScript("OnValueChanged",function(_,value)
        local n=math.floor(value/step+.5)*step
        l:SetText(label..": "..n..(unit or ""))
        if previewOnly then fn(n); api.previewPaint(previewRecords,energy,start) else Commit(function() fn(n) end,false) end
    end)
    y=y+49
    return b,l
end
local function Choices(items,current,fn,columns)
    columns=columns or math.min(3,#items)
    local width=math.floor((W-(columns-1)*6)/columns)
    for i,e in ipairs(items) do
        local key=e[1]; Button(e[2],((i-1)%columns)*(width+6),y+math.floor((i-1)/columns)*31,width,function() Commit(function() fn(key) end,true) end,current==key)
    end
    y=y+math.ceil(#items/columns)*31
end
local function Back(p) Link("Back to overview",function() Go(p) end) end
local function SetEnabled() DB().enabled=true; api.scan() end
local function Preview()
    if not preview then
        preview=CreateFrame("Frame",nil,content); preview:SetSize(W,68)
        previewRecords=api.previewMake(preview)
    end
    preview:ClearAllPoints(); At(preview,0,y); preview:Show()
    api.previewPaint(previewRecords,energy,start)
    local previewSlider,previewLabel,animatingSlider=false,false,false
    Button("Animate",350,y+6,150,function()
        if playing then playing=false; window:SetScript("OnUpdate",nil); return end
        playing=true; energy=DB().progress=="countdown" and start or 0
        local acc=0
        window:SetScript("OnUpdate",function(_,elapsed)
            acc=acc+elapsed
            if acc<.04 then return end
            energy=math.min(100,energy+10*acc); acc=0
            api.previewPaint(previewRecords,energy,start)
            if previewSlider then
                animatingSlider=true; previewSlider:SetValue(math.floor(energy+.5)); animatingSlider=false
                if previewLabel then previewLabel:SetText("Preview energy: "..math.floor(energy+.5)) end
            end
            if energy>=100 then playing=false; window:SetScript("OnUpdate",nil) end
        end)
    end)
    Button("Test on my bars",350,y+36,150,function() api.command("demo") end)
    y=y+73
    previewSlider,previewLabel=Slider("Preview energy",math.floor(energy+.5),0,100,1,function(v) if not animatingSlider then energy=v; playing=false; window:SetScript("OnUpdate",nil) end end,nil,true)
    if DB().progress=="countdown" then Slider("Post-spend start",start,0,100,1,function(v) start=v end,nil,true) end
end
local function Colors(current,entries,palette,set,custom)
    local cols=8; local width=math.floor((W-7*5)/cols)
    for i,e in ipairs(entries) do
        local key,label=e[1],e[2]
        local b=Button(current==key and "*" or "",(i-1)*(width+5),y,width,function() Commit(function() set(key) end,true) end,current==key)
        if not b.resSwatch then b.resSwatch=b:CreateTexture(nil,"OVERLAY") end
        local tex=b.resSwatch; tex:ClearAllPoints(); tex:SetSize(width-14,12); tex:SetPoint("CENTER",b,"CENTER"); local c=palette[key]
        tex:SetColorTexture(c[1],c[2],c[3],1); tex:Show()
        if b.SetScript then
            b:SetScript("OnEnter",function(self) if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText(label); GameTooltip:Show() end end)
            b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        end
    end
    y=y+32
    if custom then Link("Custom color...",function() if not api.custom() then api.say("Use /resweep color #RRGGBB.") end end) end
end
local function Bars()
    local d=DB()
    if sub=="filters" then
        Heading("Which abilities?","Choose which energy abilities receive action-bar and HUD indicators.")
        Back("bars")
        for _,e in ipairs({{"builder","Builders"},{"finisher","Finishers"},{"other","Utility and other"}}) do
            local key=e[1]; Check(e[2],d.showCategories[key],function(v) d.showCategories[key]=v end)
        end
        Section("Individual abilities","Unchecked abilities are excluded from the addon.")
        local entries=api.filters()
        for _,e in ipairs(entries) do local id=e.id; Check(e.name,not d.excludedSpells[id],function(v) d.excludedSpells[id]=not v and true or nil end,e.tracked and nil or "Not on current action bars") end
        return
    elseif sub=="ready" then
        Heading("Ready effects","Optional feedback at the moment an ability has enough energy.")
        Back("bars"); Preview()
        Choices({{"none","None"},{"burst","Burst"},{"flash","Flash"},{"proc","Proc glow"},{"halo","Halo"},{"border","Border"},{"pulse","Pulse"},{"softflash","Soft flash"}},d.readyEffect,function(v) d.readyEffect=v end,3)
        if d.readyEffect~="none" then
            Slider("Intensity",math.floor(d.readyOpacity*100+.5),15,100,5,function(v) d.readyOpacity=v/100 end,"%")
            Check("Match indicator color",d.readyMatchColor,function(v) d.readyMatchColor=v end)
            Check("Use pulse when one-shot timing is protected",d.readyFallback,function(v) d.readyFallback=v end)
        end
        return
    elseif sub=="appearance" then
        Heading("Indicator appearance","Adjust only the controls relevant to your selected style.")
        Back("bars"); Preview()
        Section("Color"); Colors(d.color,api.presets,api.colors,function(v) d.color=v end,true)
        Slider("Opacity",math.floor(d.opacity*100+.5),15,100,5,function(v) d.opacity=v/100 end,"%")
        if d.mode~="radial" then Slider("Thickness",d.thickness,2,8,1,function(v) d.thickness=v end," px") end
        Check("Reverse direction",d.reverse,function(v) d.reverse=v end)
        if d.mode=="rising" then
            Check("Tint filled area",d.tint,function(v) d.tint=v end)
            if d.tint then
                Slider("Tint opacity",math.floor(d.tintOpacity*100+.5),0,100,5,function(v) d.tintOpacity=v/100 end,"%")
                Choices({{"solid","Solid"},{"gradient","Gradient"},{"luminous","Luminous"}},d.fillEffect,function(v) d.fillEffect=v end)
            end
        end
        Link("Reset this style",function() Commit(api.resetStyle,true) end)
        return
    elseif sub=="behavior" then
        Heading("Indicator behavior","Choose when an ability should show energy progress.")
        Back("bars")
        Choices({{"energy","Energy-based"},{"countdown","Countdown"}},d.progress,api.progress,2)
        Paragraph(d.progress=="countdown" and "Countdown starts from the energy remaining after spending. Falls back to energy progress if restricted." or "Energy-based tracks current energy toward the ability cost.")
        Check("Only show finishers with combo points",d.finisherComboOnly,function(v) d.finisherComboOnly=v end)
        Check("Hide while an ability is on cooldown",d.hideCooldowns,function(v) d.hideCooldowns=v end,"Ignores the global cooldown. Shared with ability planning and individual HUD abilities.")
        Check("Predict energy at the end of the GCD",d.gcdAware,function(v) d.gcdAware=v end,"Experimental; actual energy is used if timing is protected.")
        return
    end
    Heading("Action-bar indicators","See when abilities will have enough energy, directly on your action buttons.")
    Check("Show energy readiness indicators",d.tracker.actionBars,function(v) d.tracker.actionBars=v; if v then SetEnabled() end end)
    if not d.tracker.actionBars then Paragraph("Planning pips can still be enabled separately in Ability planning.") end
    Preview()
    Section("Indicator style")
    Choices({{"rising","Rising line"},{"bar","Bottom bar"},{"perimeter","Perimeter"},{"radial","Radial sweep"}},d.mode,api.style,2)
    Link("Appearance: color, opacity and fill",function() Go("bars","appearance") end)
    Link("Behavior: countdown, cooldowns and GCD",function() Go("bars","behavior") end)
    Link("Ready effects: "..d.readyEffect,function() Go("bars","ready") end)
    Link("Choose abilities / filters",function() Go("bars","filters") end)
end
local layouts={
    {"arsenal","Cast counts","How many casts can I afford?",{"arsenal"}},
    {"segments","Energy thresholds","Where are the next cost breakpoints?",{"segments","staircase","lights","arc"}},
    {"icons","Ability progress","When will each ability be energy-ready?",{"bars","rings","icons","freeform"}},
    {"dial","Energy dial","Energy around a circular gauge.",{"dial"}},
}
local function Family(layout)
    for _,e in ipairs(layouts) do for _,v in ipairs(e[4]) do if layout==v then return e end end end
    return layouts[4]
end
O.Family=Family
local function Mini(layout,x,top)
    local gold={.93,.68,.25}; local colors={{.75,.53,1},{.76,.51,.29},{.3,.85,.48}}
    local function R(dx,dy,w,h,c,a) Rect(x+dx,top+dy,w,h,c[1],c[2],c[3],a or 1) end
    if layout=="arsenal" then
        for i,c in ipairs(colors) do for j=1,4-i do R((j-1)*15,(i-1)*12,12,9,c) end end
    elseif layout=="segments" or layout=="staircase" or layout=="lights" or layout=="arc" then
        if layout=="arc" then
            for i=0,10 do local a=math.pi+i*math.pi/10; R(26+20*math.cos(a),24+20*math.sin(a),5,5,gold,i<8 and 1 or .23) end
        else
            R(0,17,62,5,gold,.23)
            for i=1,4 do
                if layout=="lights" then R((i-1)*17,13,8,12,gold,i<4 and 1 or .25)
                else local h=layout=="staircase" and 7+i*4 or 10; R((i-1)*16,22-h,14,h,gold,i<4 and 1 or .25) end
            end
        end
    elseif layout=="dial" or layout=="rings" then
        for i=0,14 do local a=i*math.pi*1.5/14; R(30+18*math.cos(a),19+18*math.sin(a),4,4,gold,i<10 and 1 or .23) end
        if layout=="rings" then for i=0,9 do local a=i*math.pi*2/10; R(30+10*math.cos(a),19+10*math.sin(a),3,3,colors[1]) end end
    else
        for i=0,2 do
            if layout=="bars" then R(0,i*12,10,9,colors[i+1]); R(14,i*12,42,9,gold,.2); R(14,i*12,12+i*9,9,gold)
            else R(i*20,6+(layout=="freeform" and (i%2)*9 or 0),17,24,colors[i+1],.45); R(i*20,20+(layout=="freeform" and (i%2)*9 or 0),17,10,gold) end
        end
    end
end
local function LayoutVariants(items,current,set)
    for i,e in ipairs(items) do
        local key=e[1]; local x=((i-1)%2)*258; local top=y+math.floor((i-1)/2)*52
        Mini(key,x+4,top+3)
        Button(e[2],x+76,top+5,176,function() Commit(function() set(key) end,true) end,current==key)
    end
    y=y+math.ceil(#items/2)*52
end
local function HUD()
    local d=DB(); local t=d.tracker
    if sub=="abilities" then
        Heading("Choose HUD abilities","The automatic list follows your current action bars. Choose manually for a smaller, more consistent display.")
        Back("hud")
        Check("Automatically track current bar abilities",t.auto,function(v)
            if not v and t.auto then for _,e in ipairs(ns.Tracker.OptionsEntries()) do if e.current then t.selected[e.spellID]=true end end end
            t.auto=v
        end)
        if not t.auto then
            for _,e in ipairs(ns.Tracker.OptionsEntries()) do
                local id=e.spellID; Check(e.name.." ("..e.cost..")",t.selected[id],function(v) t.selected[id]=v and true or nil end,e.current and nil or "Previously discovered / manually selected")
            end
        end
        return
    elseif sub=="position" then
        Heading("HUD position and size","Unlock the actual HUD to drag it. Lock it when finished.")
        Back("hud")
        Check("Lock position",t.locked,function(v) t.locked=v end)
        Slider("Scale",math.floor(t.scale*100+.5),50,200,5,function(v) t.scale=v/100 end,"%")
        local family=Family(t.layout)[1]
        if family=="arsenal" or family=="icons" or t.layout=="dial" then Slider(family=="arsenal" and "Pip / icon size" or "Icon size",t.iconSize,24,64,2,function(v) t.iconSize=v end) end
        if t.layout=="bars" or (family=="segments" and t.layout~="arc") then Slider("Width",t.barWidth,100,320,10,function(v) t.barWidth=v end); Slider("Height",t.barHeight,12,32,2,function(v) t.barHeight=v end) end
        if family=="arsenal" or family=="icons" or t.layout=="dial" then Slider("Spacing",t.spacing,2,24,1,function(v) t.spacing=v end) end
        Link("Reset HUD position",function() Commit(ns.Tracker.ResetPosition,true) end)
        return
    elseif sub=="appearance" then
        Heading("HUD appearance","Only settings relevant to the chosen layout are shown.")
        Back("hud")
        local family=Family(t.layout)[1]
        Slider("Opacity",math.floor(t.opacity*100+.5),15,100,5,function(v) t.opacity=v/100 end,"%")
        if family=="arsenal" then
            Choices({{"circle","Circles"},{"diamond","Diamonds"},{"charge","Charges"},{"count","Counts"}},t.arsenalStyle,function(v) t.arsenalStyle=v end,2)
            Check("Vertical stacks",t.vertical,function(v) t.vertical=v end)
            Check("Show ability icons",t.arsenalIcons,function(v) t.arsenalIcons=v end)
            Check("Show ability names",t.showNames,function(v) t.showNames=v end)
            Check("Show energy costs",t.showCosts,function(v) t.showCosts=v end)
            Check("Repeat all abilities (energy only)",t.arsenalAllRepeats,function(v) t.arsenalAllRepeats=v end)
            Link("Cast-count colors and calculation settings",function() Go("planning","appearance") end)
        else
            local palette={amber={1,.78,.16},white={1,1,1},cyan={.22,.85,1},green={.3,1,.35},red={1,.24,.24},purple={.72,.42,1},orange={1,.48,.12}}
            Colors(t.color,{{"amber","Gold"},{"white","White"},{"cyan","Cyan"},{"green","Green"},{"red","Red"},{"purple","Purple"},{"orange","Orange"}},palette,function(v) t.color=v end)
            Check("Show energy costs / thresholds",t.showCosts,function(v) t.showCosts=v end)
            if t.layout=="bars" or t.layout=="rings" then Check("Show ability names",t.showNames,function(v) t.showNames=v end) end
            if t.layout=="icons" then Check("Vertical icons",t.vertical,function(v) t.vertical=v end) end
            if t.layout=="icons" or t.layout=="freeform" then Choices({{"rising","Rising line"},{"bar","Bottom bar"},{"perimeter","Perimeter"},{"radial","Radial sweep"}},t.iconMode,function(v) t.iconMode=v end,2) end
            if family=="icons" or family=="dial" then
                if t.layout~="dial" then Check("Hide affordable abilities",t.hideReady,function(v) t.hideReady=v end) end
                Check("Show ready effects",t.readyEffects,function(v) t.readyEffects=v end)
            end
        end
        return
    end
    Heading("Standalone energy HUD","Choose what information you want near your character.")
    Check("Enable energy HUD",t.enabled,function(v) t.enabled=v; if v then SetEnabled() end end)
    Section("What do you want to see?")
    local selected=Family(t.layout)
    for _,e in ipairs(layouts) do
        local family=e; local current=selected==e
        Button((current and "* " or "")..e[2],76,y,W-76,function() Commit(function() t.layout=family[1] end,true) end,current)
        Mini(current and t.layout or e[1],4,y)
        Text(e[3],78,y+29,W-78,MUTED); y=y+53
    end
    if selected[1]=="segments" then
        Section("Threshold style")
        LayoutVariants({{"segments","Segments"},{"staircase","Staircase"},{"lights","Threshold lights"},{"arc","Arc"}},t.layout,function(v) t.layout=v end)
    elseif selected[1]=="icons" then
        Section("Ability layout")
        LayoutVariants({{"bars","Bars"},{"rings","Rings"},{"icons","Icons"},{"freeform","Freeform"}},t.layout,function(v) t.layout=v end)
    elseif selected[1]=="arsenal" then
        Section("Cast-count style")
        Choices({{"circle","Circles"},{"diamond","Diamonds"},{"charge","Charges"},{"count","Counts"}},t.arsenalStyle,function(v) t.arsenalStyle=v end,2)
        Check("Vertical stacks",t.vertical,function(v) t.vertical=v end)
    end
    Link("Choose HUD abilities",function() Go("hud","abilities") end)
    Link("Position and size",function() Go("hud","position") end)
    Link("Customize selected layout",function() Go("hud","appearance") end)
end
local function Cycle(mode)
    return mode=="opportunity" and "warning" or mode=="warning" and "off" or "opportunity"
end
O.Cycle=Cycle
local function ModeLabel(mode)
    return mode=="warning" and "Warn !" or mode=="opportunity" and "Show +" or "Off"
end
local function Planning()
    local d=DB(); local c=d.chains; local C=ns.Chains
    local entries=C.OptionsEntries()
    local kick
    for _,e in ipairs(entries) do if e.name=="Kick" then kick=e; break end end
    if sub=="appearance" then
        Heading("Pips and cast counts","These settings are shared by action-button planning and the cast-count HUD.")
        Back("planning")
        Check("Show partial repeat pips",c.fraction,function(v) c.fraction=v end)
        Check("Hide inactive pips",c.hideInactive,function(v) c.hideInactive=v end)
        Check("Pulse warning diamonds",c.pulseWarnings,function(v) c.pulseWarnings=v end)
        Slider("Action-button pip size",c.size,4,13,1,function(v) c.size=v end)
        Slider("Action-button spacing",c.spacing,1,6,1,function(v) c.spacing=v end)
        Slider("Action-button opacity",math.floor(c.opacity*100+.5),20,100,5,function(v) c.opacity=v/100 end,"%")
        Slider("Action-button vertical offset",c.offset,-12,12,1,function(v) c.offset=v end)
        Slider("Maximum repeat pips",c.maxPips,1,6,1,function(v) c.maxPips=v end)
        Section("Ability colors","Change a color once; it stays consistent in all planning views.")
        for _,e in ipairs(entries) do
            local id=e.id; local color,index=C.OptionsColor(id); Text(e.name,0,y+5,W-100,WHITE)
            Button("Next color",W-110,y,110,function() Commit(function() C.SetColor(id,index%#C.OptionsPalette()+1) end,true) end)
            Rect(W-145,y+5,20,15,color[1],color[2],color[3]); y=y+30
        end
        return
    elseif sub=="rules" then
        Heading("Custom follow-ups","Choose a source ability, then what you want to know after casting it.")
        Back("planning")
        if #entries==0 then Paragraph("Put energy abilities on your action bars to discover them."); return end
        local source
        for _,e in ipairs(entries) do if e.id==sourceID then source=e end end
        if not source then source=entries[1]; sourceID=source.id end
        Section("After using...")
        local opts={}; for _,e in ipairs(entries) do opts[#opts+1]={e.id,e.name} end
        Choices(opts,sourceID,function(v) sourceID=v end,2)
        local rule=C.OptionsRule(sourceID)
        Check("Show consecutive-use pips for "..source.name,rule.repeatPips,function(v) C.SetRepeat(sourceID,v) end)
        Section("What can I do afterward?","Show + lights up when affordable. Warn ! lights up when the source is affordable but the target is not. Off hides the relationship.")
        local chosen={}; for _,id in ipairs(rule.follow) do chosen[id]=true end
        for _,e in ipairs(entries) do
            if e.id~=sourceID then
                local target=e.id; local global=c.globalFollow[target]
                local mode=global or (chosen[target] and (rule.conditions and rule.conditions[target] or "opportunity")) or "off"
                Text(e.name.." ("..e.cost..")"..(global and "  [global]" or ""),0,y+5,W-116,WHITE)
                Button(ModeLabel(mode),W-110,y,110,function() Commit(function() if not C.SetLocal(sourceID,target,Cycle(mode)) then api.say("At most three local follow-ups per source.") end end,true) end,false,global~=nil)
                y=y+30
            end
        end
        return
    elseif sub=="global" then
        Heading("Global follow-ups","Apply a rule to all other tracked energy-spending abilities. Useful for interrupts or important utility.")
        Back("planning"); Paragraph("Up to three global rules. Warnings are prioritized when space is limited.")
        for _,e in ipairs(entries) do
            local id=e.id; local mode=c.globalFollow[id] or "off"
            Text(e.name.." ("..e.cost..")",0,y+5,W-116,WHITE)
            Button(ModeLabel(mode),W-110,y,110,function() Commit(function() local nextMode=Cycle(mode); if not C.SetGlobal(id,nextMode) then api.say("At most three global follow-ups.") elseif nextMode~="off" then c.enabled=true; SetEnabled() end end,true) end)
            y=y+30
        end
        return
    elseif sub=="templates" then
        Heading("Starting templates","Templates replace local repeat and follow-up rules. Global reservations are retained.")
        Back("planning")
        for _,e in ipairs({{"minimal","Minimal","Repeat pips for builders."},{"builders","Builders","Repeat pips and builder follow-ups."},{"pvp","PvP","Follow-up opportunities for control and interrupts."},{"finishers","Finishers","Follow-up opportunities for finishers."},{"custom","Custom","Start with no automatic local relationships."}}) do
            local key=e[1]; Button(e[2],0,y,160,function() Commit(function() C.Command(key); SetEnabled() end,true) end,c.template==key)
            Text(e[3],170,y+5,W-170,MUTED); y=y+34
        end
        return
    end
    Heading("Ability planning","Understand the consequences of spending your energy.")
    Check("Enable action-button planning pips",c.enabled,function(v) c.enabled=v; if v then SetEnabled() end end,"Works independently of the energy readiness animation.")
    Section("Consecutive casts","Colored circles represent repeat uses of the same ability.")
    Check("Show consecutive-use pips",c.repeatEnabled,function(v) c.repeatEnabled=v; if v then c.enabled=true; SetEnabled() end end,"Applies to action buttons; cast-count HUD settings are unchanged.")
    for i=1,3 do Rect((i-1)*18,y,14,14,.75,.53,1,i==3 and .35 or 1) end; y=y+21
    Link("Configure repeat pips and follow-ups",function() Go("planning","rules") end)
    Section("Reserve energy for Kick","Warn when another affordable action would leave too little energy for your next interrupt.")
    if kick then
        local id=kick.id
        Check("Warn when Kick would be unaffordable",c.globalFollow[id]=="warning",function(v)
            if C.SetGlobal(id,v and "warning" or "off") then if v then c.enabled=true; SetEnabled() end else api.say("At most three global follow-ups.") end
        end)
    else Paragraph("Kick must be on an action bar to configure this shortcut.") end
    Link("Other global reservations and opportunities",function() Go("planning","global") end)
    Link("Pip appearance and ability colors",function() Go("planning","appearance") end)
    Link("Starting templates",function() Go("planning","templates") end)
    Paragraph("Predictions are energy-only, not guarantees of cooldown, combo-point or positional eligibility.")
end
local function Advanced()
    local d=DB(); local c=d.chains
    Heading("Advanced settings","Shared behavior, calculation assumptions and troubleshooting.")
    Check("Enable Rogue Energy Sweep",d.enabled,function(v) d.enabled=v; if v then api.scan() end end,"Master switch for all features.")
    Check("Only show indicators in combat",d.combatOnly,function(v) d.combatOnly=v end)
    Check("Predict energy at the end of the GCD",d.gcdAware,function(v) d.gcdAware=v end,"Experimental; falls back to actual energy when timing is unavailable.")
    Section("Calculation assumptions")
    Slider("Assumed regeneration per GCD",c.regen,0,30,1,function(v) c.regen=v end," energy")
    Paragraph("Used by repeat pips and follow-up budgets, not by the live energy sweep.")
    Section("Troubleshooting")
    Check("Profile update performance",api.profiling(),function(v) api.profile(v) end)
    Link("Diagnostics report",api.diagnostic)
    Link("Rescan action buttons",function() api.command("rescan") end)
    Link("Test on action bars",function() api.command("demo") end)
    Link("Legacy settings (fallback)",function() window:Hide(); api.command("legacy") end)
    Section("Reset settings")
    Link("Reset all settings...",function()
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs.ROGUEENERGYSWEEP_UNIFIED_RESET={text="Reset all Rogue Energy Sweep settings?",button1="Reset",button2="Cancel",OnAccept=function() api.command("reset"); Go("bars") end,timeout=0,whileDead=true,hideOnEscape=true}
            StaticPopup_Show("ROGUEENERGYSWEEP_UNIFIED_RESET")
        else api.say("Use /resweep reset to confirm resetting all settings.") end
    end)
end
local function Setup()
    Heading("Quick setup","Enable only the information you want. These shortcuts add a feature without resetting your other settings.")
    for _,e in ipairs({
        {"Action-bar readiness","See when each ability has enough energy.",function() DB().tracker.actionBars=true; SetEnabled() end,"bars"},
        {"Standalone cast counts","See how many casts you have available.",function() DB().tracker.enabled=true; DB().tracker.layout="arsenal"; SetEnabled() end,"hud"},
        {"Energy thresholds","See your next energy breakpoints.",function() DB().tracker.enabled=true; DB().tracker.layout="segments"; SetEnabled() end,"hud"},
        {"Ability planning","See repeat casts and selected follow-up opportunities.",function() DB().chains.enabled=true; SetEnabled() end,"planning"},
    }) do
        local item=e; Text(e[1],0,y,W,GOLD,GameFontNormal); y=y+22; Paragraph(e[2])
        Link("Enable and configure",function() Commit(item[3],false); Go(item[4]) end)
    end
end
local pages={bars=Bars,hud=HUD,planning=Planning,advanced=Advanced,setup=Setup}
Render=function()
    Reset()
    for key,b in pairs(nav) do if key==page then b:LockHighlight() else b:UnlockHighlight() end end
    (pages[page] or Bars)()
    content:SetHeight(math.max(y+20,scroll:GetHeight()))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
end
function O.Refresh()
    if not window or not window:IsShown() or busy or rendering then return end
    rendering=true
    local ok,err=pcall(Render)
    rendering=false
    if not ok then window:Hide(); api.say("Unified settings error: "..tostring(err)..". Use /resweep legacy.") end
end
local function Create()
    window=CreateFrame("Frame","RogueEnergySweepUnifiedOptions",UIParent,"BasicFrameTemplateWithInset")
    window:SetSize(760,620); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:EnableMouse(true)
    if UIParent.GetWidth and UIParent.GetHeight then window:SetScale(math.min(1,UIParent:GetWidth()/780,UIParent:GetHeight()/640)) end
    window:SetMovable(true); window:SetClampedToScreen(true); window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart",function(self) self:StartMoving() end); window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    if window.TitleText then window.TitleText:SetText("Rogue Energy Sweep") end
    if UISpecialFrames then table.insert(UISpecialFrames,window:GetName()) end
    window:SetScript("OnHide",HidePreview)
    local divider=window:CreateTexture(nil,"ARTWORK"); divider:SetSize(1,520); divider:SetPoint("TOPLEFT",window,"TOPLEFT",184,-50); divider:SetColorTexture(.4,.34,.24,.8)
    for i,e in ipairs({{"bars","Action bars"},{"hud","Energy HUD"},{"planning","Ability planning"},{"advanced","Advanced"},{"setup","Quick setup"}}) do
        local key=e[1]; local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        b:SetSize(158,34); b:SetPoint("TOPLEFT",window,"TOPLEFT",16,-51-(i-1)*42); b:SetText(e[2]); b:SetScript("OnClick",function() Go(key) end); nav[key]=b
    end
    local footer=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); footer:SetPoint("BOTTOMLEFT",window,"BOTTOMLEFT",16,23); footer:SetText("Settings saved automatically.")
    scroll=CreateFrame("ScrollFrame","RogueEnergySweepUnifiedScroll",window,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",window,"TOPLEFT",202,-45); scroll:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-36,36)
    content=CreateFrame("Frame",nil,scroll); content:SetSize(W,540); scroll:SetScrollChild(content)
    window:Hide()
end
function O.Configure(a) api=a end
function O.Open(p,s)
    if not api or not DB() then return false end
    local ok,err=pcall(function()
        if not window then Create() end
        page=p or "bars"; sub=s or "home"; window:Show(); scroll:SetVerticalScroll(0)
        rendering=true; Render(); rendering=false
    end)
    rendering=false
    if not ok then if window then window:Hide() end; api.say("Unified settings unavailable: "..tostring(err)); return false end
    return true
end
function O.Register()
    if launcher then return end
    launcher=CreateFrame("Frame","RogueEnergySweepSettingsLauncher")
    local title=launcher:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-16); title:SetText("Rogue Energy Sweep")
    local desc=launcher:CreateFontString(nil,"ARTWORK","GameFontHighlight"); desc:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-12); desc:SetWidth(420); desc:SetJustifyH("LEFT"); desc:SetText("Manage energy readiness, HUD layouts and ability planning in one window.")
    local open=CreateFrame("Button",nil,launcher,"UIPanelButtonTemplate"); open:SetSize(240,28); open:SetPoint("TOPLEFT",desc,"BOTTOMLEFT",0,-18); open:SetText("Open Rogue Energy Sweep settings"); open:SetScript("OnClick",function() O.Open("bars") end)
    local setup=CreateFrame("Button",nil,launcher,"UIPanelButtonTemplate"); setup:SetSize(240,28); setup:SetPoint("TOPLEFT",open,"BOTTOMLEFT",0,-8); setup:SetText("Quick setup"); setup:SetScript("OnClick",function() O.Open("setup") end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category=Settings.RegisterCanvasLayoutCategory(launcher,"Rogue Energy Sweep"); Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then launcher.name="Rogue Energy Sweep"; InterfaceOptions_AddCategory(launcher) end
end
