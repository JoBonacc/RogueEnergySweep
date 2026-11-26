-- Mock the native API contract around actual addon functions; not a live-client test.
local f=assert(io.open("addon/RogueEnergySweep/RogueEnergySweep.lua")); local src=f:read("*a"); f:close()
local function section(a,b)
    local start=assert(src:find(a,1,true))
    local stop=assert(src:find(b,start+1,true))
    return src:sub(start,stop-1)
end
local secret=setmetatable({}, {__add=function() error("secret arithmetic") end,__div=function() error("secret arithmetic") end,__lt=function() error("secret comparison") end})
local env=setmetatable({ENERGY=3,lastMaxEnergy=100,issecretvalue=function(v) return rawequal(v,secret) end}, {__index=_G})
env.C_CurveUtil={CreateCurve=function() return {points={},AddPoint=function(self,x,y) self.points[#self.points+1]={x,y} end} end}
local function eval(curve,x)
    local points=curve.points
    for i=2,#points do
        local a,b=points[i-1],points[i]
        if x<=b[1] then return a[2]+(b[2]-a[2])*(x-a[1])/(b[1]-a[1]) end
    end
    return points[#points][2]
end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." != "..tostring(b)) end
env.UnitPowerPercent=function(unit,power,raw,curve) assert(unit=="player" and power==3 and raw==false); return eval(curve,.15) end
local code=section("local function IsSecret","local MODES")..section("local function MakeCurve","local function GetButtonSlot")..section("local function GetSpellFromSlot","local function Clear(")..section("local function ErrorNote","local function Paint")..section("local function Evaluate","-- Native widgets consume protected ranges")..section("local function Countdown","local function ResetProgress")
local make,spell,cost,evaluate,countdown=assert(load(code.."\nreturn MakeCurve,GetSpellFromSlot,GetEnergyCost,Evaluate,Countdown","api mocks","t",env))()
local fill=make(45,"fill"); local deficit=make(45,"deficit"); local visible=make(45,"visibility")
near(eval(fill,.15),1/3); near(eval(deficit,.15),2/3); near(eval(fill,.45),1); near(eval(visible,.44),1); near(eval(visible,.45),0); near(eval(visible,.8),0)
near(eval(make(120,"fill"),1),100/120); near(eval(make(120,"visibility"),1),1)
local value,ok=evaluate(fill); assert(ok); near(value,1/3)
env.UnitPowerPercent=function() return secret end; value,ok=evaluate(fill); assert(ok and rawequal(value,secret))
env.UnitPowerPercent=function() error("API rejected") end; value,ok=evaluate(fill); assert(not ok and value==nil)
env.UnitPowerPercent=nil; value,ok=evaluate(fill); assert(not ok)
env.C_ActionBar={GetSpell=function() return 123 end}; assert(spell(1)==123)
env.C_ActionBar.GetSpell=function() return secret end; assert(spell(1)==nil)
env.C_ActionBar.GetSpell=function() error("restricted") end; assert(spell(1)==nil)
env.C_Spell={GetSpellPowerCost=function() return {{type=0,cost=5},{type=3,cost=45,minCost=40}} end}
local n,known=cost(123); assert(n==40 and known)
env.C_Spell.GetSpellPowerCost=function() return {{type=3,cost=45}} end; n,known=cost(123); assert(n==45 and known)
env.C_Spell.GetSpellPowerCost=function() return {{type=3,cost=secret}} end; n,known=cost(123); assert(n==nil and not known)
env.C_Spell.GetSpellPowerCost=function() return secret end; n,known=cost(123); assert(n==nil and not known)
env.C_Spell.GetSpellPowerCost=function() return {{type=0,cost=5}} end; local _,_,readable=cost(123); assert(readable)
local group={}; local p,d=countdown(group,45,1/3,2/3); near(p,0); near(d,1)
p,d=countdown(group,45,2/3,1/3); near(p,.5); near(d,.5)
p,d=countdown(group,45,1,0); near(p,1); near(d,0)
p,d=countdown(group,45,.2,.8); near(p,0); near(d,1)
env.C_CurveUtil.CreateCurve=function() error("missing curve") end; assert(make(45,"fill")==nil)
print("PASS: mock curve readiness, cost discovery, protected values, missing API fallback, public countdown")

-- Keep the original native radial geometry; explicit 0/1 offsets were associated
-- with an invisible radial overlay in live testing of v0.6.0.
local radialInit=section("local function MakeOverlay","local function RebuildGroups")
assert(not radialInit:find("SetRadialProgressBarStartOffset",1,true))
assert(not radialInit:find("SetRadialProgressBarEndOffset",1,true))
assert(radialInit:find("pcall(radial.SetRadialProgressBarPercent, radial, 0)",1,true))
print("PASS: default radial geometry regression guard (not a visual rendering test)")

-- Test actual direct rendering helpers using opaque mock values and widgets.
local directCode=section("local function IsSecret","local MODES")..section("local function Clear(","local function ClearAll")..section("local function ErrorNote","local function Countdown")
local function widget()
    local w={}
    function w:Hide() self.shown=false end
    function w:Show() self.shown=true end
    function w:SetAlpha(v) self.alpha=v end
    function w:SetMinMaxValues(lo,hi) if self.reject and rawequal(lo,secret) then error("rejected protected range") end; self.lo=lo; self.hi=hi end
    function w:SetValue(v) self.value=v end
    function w:SetRadialProgressBarPercent(v) self.value=v end
    return w
end
local env2=setmetatable({issecretvalue=env.issecretvalue,DB={mode="bar",thickness=4}}, {__index=_G})
local paint,paintDirect=assert(load(directCode.."\nreturn Paint,PaintDirect","direct mocks","t",env2))()
local rec={frame=widget(),radial=widget(),bar=widget(),rising=widget(),riseTint=widget(),line=widget(),track=widget(),edges={widget(),widget(),widget(),widget()},native=true}
local snapshot={start=secret,startDeficit=secret}
assert(paintDirect(rec,secret,secret,secret,snapshot))
assert(rawequal(rec.bar.lo,secret) and rawequal(rec.bar.value,secret) and rec.bar.hi==1 and rec.progressState=="native countdown")
assert(paint(rec,.5,.5,1)); assert(rec.bar.lo==0 and rec.bar.hi==1 and rec.bar.value==.5)
env2.DB.mode="rising"; assert(paintDirect(rec,secret,secret,secret,snapshot))
assert(rawequal(rec.rising.lo,secret) and rawequal(rec.riseTint.lo,secret) and rec.line.shown)
env2.DB.mode="radial"; rec.countdownRadial=widget()
assert(paintDirect(rec,secret,secret,secret,snapshot))
assert(rec.countdownRadial.lo==0 and rawequal(rec.countdownRadial.hi,secret) and rec.countdownRadial.shown)
assert(paint(rec,.5,.5,1) and not rec.countdownRadial.shown and rec.radial.shown)
env2.DB.mode="bar"; rec.bar.reject=true
assert(not paintDirect(rec,secret,secret,secret,snapshot)); assert(rec.renderError:find("rejected protected range",1,true))
assert(paint(rec,.4,.6,1) and rec.bar.lo==0 and rec.bar.value==.4)
print("PASS: direct native ranges, public range restoration, radial selection and rejected range fallback")

-- Perimeter uses four clipped copies of the full range; check public geometry
-- and native range forwarding independently from the client visual engine.
local function layoutWidget()
    local w=widget()
    function w:EnableMouse() end
    function w:SetAllPoints(relative) self.relative=relative end
    function w:SetClipsChildren(v) self.clips=v end
    function w:ClearAllPoints() self.anchor=nil end
    function w:SetSize(x,y) self.width=x; self.height=y end
    function w:SetPoint(p,r,rp,x,y) self.anchor={p,rp,x,y} end
    return w
end
env2.CreateFrame=function() return layoutWidget() end
env2.NewBar=function(parent,lo,hi,orientation,reverse)
    local w=layoutWidget(); w.orientation=orientation; w.reverse=reverse; w.parent=parent; return w
end
env2.Style=function() end
rec.frame.GetWidth=function() return 40 end
rec.frame.GetHeight=function() return 36 end
env2.DB.mode="perimeter"
assert(paintDirect(rec,secret,secret,secret,snapshot))
for i=1,4 do
    assert(rec.countdownClips[i].clips and rec.countdownClips[i].shown)
    assert(rawequal(rec.countdownEdges[i].lo,secret) and rawequal(rec.countdownEdges[i].value,secret))
end
assert(rec.countdownEdges[1].width==160 and rec.countdownEdges[1].anchor[3]==0)
assert(rec.countdownEdges[2].height==144 and rec.countdownEdges[2].anchor[4]==36)
assert(rec.countdownEdges[3].anchor[3]==80 and rec.countdownEdges[4].anchor[4]==-108)
assert(paint(rec,.5,.5,1))
for i=1,4 do assert(not rec.countdownClips[i].shown and rec.edges[i].shown) end
rec.countdownClips=nil; rec.countdownEdges=nil; rec.countdownLayout=nil
env2.CreateFrame=function() local w=layoutWidget(); w.SetClipsChildren=nil; return w end
assert(not paintDirect(rec,secret,secret,secret,snapshot))
assert(paint(rec,.5,.5,1))
-- Protected snapshot is retained until a subsequent generation, and is never
-- read back from a texture or used in Lua arithmetic.
env.UnitPowerPercent=function() return secret end
env.progressGeneration=1
local sg={startFillCurve={},startDeficitCurve={}}
local pf,pd,success,source,direct=countdown(sg,45,secret,secret)
assert(success and direct and sg.generation==1 and rawequal(sg.start,secret) and rawequal(pf,secret))
env.progressGeneration=2
pf,pd,success,source,direct=countdown(sg,45,secret,secret)
assert(success and direct and sg.generation==2 and rawequal(pd,secret))
print("PASS: protected snapshot generation, clipped perimeter geometry, missing clipping fallback")

-- Verify the diagnostic labels, not just the counts.
local summaryEnv=setmetatable({records={}}, {__index=_G})
local summary=assert(load(section("local function ProgressSummary()","local function Status()").."\nreturn ProgressSummary","summary mocks","t",summaryEnv))()
assert(summary()=="no active indicators")
for i=1,5 do summaryEnv.records[i]={cost=45,progressState="native countdown"} end
local label,counts=summary()
assert(label=="native countdown: 5" and counts["native countdown"]==5)
summaryEnv.records[5].progressState="energy fallback"
summaryEnv.records[6]={cost=0,progressState="energy"}
assert(summary()=="native countdown: 4 | energy fallback: 1")
print("PASS: actual progress diagnostic labels and mixed counts")

-- Test the actual color settings and native picker callback wiring.
local colorEnv=setmetatable({RogueEnergySweepDB={color="cyan"}},{__index=_G})
local colorCode=section("local function IsSecret","local function RefreshMaxEnergy")
local init,resolve,hex,setCustom,setHex,openPicker,getDB=assert(load("local DB\n"..colorCode.."\nreturn InitDB,ResolveColor,ColorHex,SetCustomColor,SetColorHex,OpenCustomColorPicker,function() return DB end","color mocks","t",colorEnv))()
init(); assert(getDB().color=="cyan" and hex(resolve())=="#38D9FF")
assert(setHex("#AB12EF") and hex(resolve())=="#AB12EF")
assert(not setHex("#123") and not setHex("xyzxyz") and hex(resolve())=="#AB12EF")
assert(not setCustom(nil,1,0) and not setCustom(math.huge,0,0))
assert(setCustom(-1,2,.5) and hex(resolve())=="#00FF80")
init(); assert(getDB().color=="custom" and hex(resolve())=="#00FF80")
local updates=0
local function applied() updates=updates+1 end
assert(not openPicker(applied))
local picker={}
function picker:SetupColorPickerAndShow(info) self.info=info end
function picker:GetColorRGB() return .1,.2,.3 end
colorEnv.ColorPickerFrame=picker
getDB().color="amber"
assert(openPicker(applied) and picker.info.hasOpacity==false)
assert(picker.info.r==1 and picker.info.g==.78)
picker.info.swatchFunc(); assert(getDB().color=="custom" and hex(resolve())=="#1A334D" and updates==1)
picker.info.cancelFunc(); assert(getDB().color=="amber" and updates==2 and hex(getDB().customColor)=="#00FF80")
assert(setHex("112233")); assert(openPicker(applied)); picker.info.swatchFunc(); picker.info.cancelFunc()
assert(getDB().color=="custom" and hex(resolve())=="#112233")
getDB().customColor={0/0,1,1}; init(); assert(getDB().color=="amber" and getDB().customColor==nil)
colorEnv.RogueEnergySweepDB={}; init(); assert(getDB().color=="amber")
print("PASS: color preset migration, custom RGB and hex, picker live callbacks and cancellation")

-- Target-specific finisher detection and safe independent opacity gate.
local comboEnv=setmetatable({ENERGY=3,issecretvalue=env.issecretvalue},{__index=_G})
local comboCode=section("local function IsSecret","local MODES")..section("local FINISHERS","local function Clear(")
local getCost,getAlpha,applyGate=assert(load(comboCode.."\nreturn GetEnergyCost,TargetComboAlpha,ApplyComboGate","combo mocks","t",comboEnv))()
comboEnv.C_Spell={GetSpellPowerCost=function() return {{type=3,cost=35},{type=4,cost=5,minCost=1}} end}
local c,e,readable,finisher=getCost(999); assert(c==35 and e and readable and finisher)
comboEnv.C_Spell.GetSpellPowerCost=function() return {{type=4,minCost=1,cost=5},{type=3,cost=25}} end
c,e,readable,finisher=getCost(999); assert(c==25 and finisher)
comboEnv.C_Spell.GetSpellPowerCost=function() return {{type=3,cost=35}} end
c,e,readable,finisher=getCost(6760); assert(finisher)
c,e,readable,finisher=getCost(1752); assert(not finisher)
comboEnv.C_Spell.GetSpellPowerCost=function() return {{type=3,cost=35},{type=4,minCost=0,cost=5}} end
c,e,readable,finisher=getCost(999); assert(not finisher)
local points=0
comboEnv.UnitExists=function(unit) assert(unit=="target"); return true end
comboEnv.GetComboPoints=function(unit,target) assert(unit=="player" and target=="target"); return points end
comboEnv.UnitPower=function() error("must not read generic combo points") end
assert(getAlpha()==0); points=1; assert(getAlpha()==1); points=5; assert(getAlpha()==1)
comboEnv.UnitExists=function() return false end; assert(getAlpha()==0)
comboEnv.UnitExists=function() return true end
points=secret
comboEnv.C_CurveUtil={CreateCurve=function() return {AddPoint=function() end,Evaluate=function(_,v) assert(rawequal(v,secret)); return secret end} end}
local alpha,source=getAlpha(); assert(rawequal(alpha,secret) and source=="target points (native curve)")
local gate={SetAlpha=function(self,v) self.alpha=v end}
local fin={finisher=true,comboGate=gate}
assert(applyGate(fin,alpha,true) and rawequal(gate.alpha,secret))
assert(applyGate(fin,0,false) and gate.alpha==1)
fin.finisher=false; assert(applyGate(fin,0,true) and gate.alpha==1)
fin.finisher=true; assert(applyGate(fin,0,true) and gate.alpha==0)
gate.SetAlpha=function(self,v) if rawequal(v,secret) then error("rejected") end; self.alpha=v end
assert(not applyGate(fin,secret,true) and gate.alpha==0)
comboEnv.GetComboPoints=nil; assert(getAlpha()==0)
assert(src:find('"PLAYER_TARGET_CHANGED","COMBO_TARGET_CHANGED"',1,true))
assert(src:find('power=="COMBO_POINTS"',1,true))
assert(src:find('DB.finisherComboOnly and not demo',1,true))
print("PASS: finisher detection, target-only combo gate, secret alpha forwarding and fail-closed behavior")

-- Verify context-sensitive controls remain unavailable for unrelated modes.
local optCode=section("local function StyleOptions","local function CreateOptions")
local styleOptions,available=assert(load(optCode.."\nreturn StyleOptions,SetControlAvailable","options mocks","t",_G))()
for _,case in ipairs({{"rising",true,true},{"bar",false,true},{"perimeter",false,true},{"radial",false,false}}) do
    local tint,thickness=styleOptions(case[1]); assert(tint==case[2] and thickness==case[3])
end
local function optionWidget()
    return {Enable=function(self) self.enabled=true end,Disable=function(self) self.enabled=false end,Show=function(self) self.visible=true end,Hide=function(self) self.visible=false end}
end
local control,label=optionWidget(),optionWidget()
available(control,label,false); assert(control.enabled==false and control.visible==false and label.visible==false)
available(control,label,true); assert(control.enabled and control.visible and label.visible)
assert(src:find("SetControlAvailable(tint,tintLabel,tintAvailable)",1,true))
assert(src:find("SetControlAvailable(thickness,thicknessLabel,thicknessAvailable)",1,true))
assert(src:find('if DB.mode=="rising" then DB.tint=v end',1,true))
print("PASS: context-sensitive options availability and guarded tint changes")

-- Layout contract: controls have their own rows and leave room for slider knobs.
local layoutCode=section("local OPTION_LAYOUT =","local function CreateOptions")
local layout=assert(load(layoutCode.."\nreturn OPTION_LAYOUT","layout checks","t",_G))()
local function sliderBottom(y) return y+layout.sliderOffset+layout.sliderHeight end
assert(layout.tint-sliderBottom(layout.thickness)>=6)
assert(layout.progress-(layout.tint+layout.buttonHeight)>=10)
assert(layout.appearance-(layout.progressStatus+12)>=10)
assert(layout.preview-sliderBottom(layout.opacity)>=12)
assert(layout.previewIcons-sliderBottom(layout.previewSliders)>=10)
assert(layout.previewCosts-(layout.previewIcons+48)>=4)
assert(layout.footer-(layout.previewCosts+12)>=10)
assert(src:find('line:SetPoint("LEFT",heading,"RIGHT",12,0)',1,true))
assert(src:find('Check("Tint filled area",16,-layout.tint',1,true))
print("PASS: options row separation and heading-aligned dividers")

-- Cooldown filtering must request ignoreGCD and never compare secret duration.
local filterEnv=setmetatable({DB={excludedSpells={}},issecretvalue=env.issecretvalue},{__index=_G})
local filterCode=section("local function IsSecret","local MODES")..section("local cooldownCurve","local function Clear(")
local cdAlpha,cdGate,excluded=assert(load(filterCode.."\nreturn CooldownAlpha,ApplyCooldownGate,IsExcluded","filter mocks","t",filterEnv))()
assert(cdAlpha(123)==1)
local remaining=0
filterEnv.C_Spell={GetSpellCooldownDuration=function(id,ignore) assert(id==123 and ignore==true); return {GetRemainingDuration=function() return remaining end,EvaluateRemainingDuration=function(_,curve) assert(curve); return secret end} end}
filterEnv.C_CurveUtil={CreateCurve=function() return {AddPoint=function() end} end}
assert(cdAlpha(123)==1)
remaining=12; assert(cdAlpha(123)==0)
remaining=secret; local alpha,source=cdAlpha(123); assert(rawequal(alpha,secret) and source=="native cooldown")
local r={spellID=123,cooldownGate={SetAlpha=function(self,v) self.alpha=v end}}
assert(cdGate(r,alpha) and rawequal(r.cooldownGate.alpha,secret))
r.cooldownGate.SetAlpha=function(self,v) if rawequal(v,secret) then error("rejected") end; self.alpha=v end
assert(not cdGate(r,secret) and r.cooldownGate.alpha==1)
filterEnv.C_Spell.GetSpellCooldownDuration=function() error("restricted") end
assert(cdAlpha(123)==1)
assert(not excluded(r)); filterEnv.DB.excludedSpells[123]=true; assert(excluded(r))
assert(src:find('not demo and IsExcluded(record)',1,true))
assert(src:find('DB.hideCooldowns and not demo',1,true))
print("PASS: cooldown GCD exclusion, native secret alpha, fail-open and ability exclusions")

local entriesEnv=setmetatable({records={{cost=35,spellID=123},{cost=35,spellID=123},{cost=0,spellID=999},{cost=25,spellID=234}},DB={excludedSpells={[123]=true,[345]=true}},C_Spell={GetSpellInfo=function(id) return {name="Ability "..id,iconID=id+1000} end}}, {__index=_G})
local entryCode=section("local function IsSecret","local MODES")..section("local function AbilityFilterEntries","local function OpenAbilityFilters")
local list=assert(load(entryCode.."\nreturn AbilityFilterEntries","entry mocks","t",entriesEnv))()
local entries=list()
assert(#entries==3 and entries[1].id==123 and entries[1].tracked and entries[2].id==234 and entries[3].id==345 and not entries[3].tracked)
assert(entries[1].icon==1123)
assert(src:find('Button("Test on bars",324,-layout.previewIcons',1,true))
print("PASS: deduplicated ability filter list, retained exclusions and compact preview actions")

-- Active appearance remains backward compatible and is copied on migration.
local prefsEnv=setmetatable({RogueEnergySweepDB={mode="rising",color="cyan",opacity=.7,thickness=2,tint=false,combatOnly=true,excludedSpells={[123]=true}}},{__index=_G})
local initPrefs,styleMode,resetStyle,saveStyle,getPrefs=assert(load("local DB\n"..colorCode.."\nreturn InitDB,SetStyle,ResetAppearance,SaveAppearance,function() return DB end","appearance mocks","t",prefsEnv))()
initPrefs()
local prefs=getPrefs()
assert(prefs.stylePrefs.bar.color=="cyan" and prefs.stylePrefs.radial.opacity==.7 and prefs.stylePrefs.rising.tint==false)
prefs.color="purple"; prefs.reverse=true; prefs.tintOpacity=.35
assert(styleMode("bar") and prefs.color=="cyan" and prefs.reverse==false)
prefs.color="white"; prefs.thickness=6; saveStyle()
assert(styleMode("rising") and prefs.color=="purple" and prefs.reverse==true and prefs.tintOpacity==.35)
resetStyle(); assert(prefs.color=="amber" and prefs.thickness==4 and prefs.reverse==false and prefs.combatOnly and prefs.excludedSpells[123])
assert(styleMode("bar") and prefs.color=="white" and prefs.thickness==6)
initPrefs(); assert(prefs.mode=="bar" and prefs.color=="white" and prefs.stylePrefs.rising.color=="amber")
local dirCode=section("local function EdgeRange","local function ApplyDirection")
local ranges=assert(load(dirCode.."\nreturn EdgeRange","edge order","t",_G))()
local a,b,flip=ranges(1,false); assert(a==0 and b==.25 and not flip)
a,b,flip=ranges(1,true); assert(a==.75 and b==1 and flip)
a,b,flip=ranges(4,true); assert(a==0 and b==.25 and flip)
-- Exercise reversed native clipped geometry with the existing opaque snapshot mocks.
env2.CreateFrame=function() return layoutWidget() end
rec.countdownClips=nil; rec.countdownEdges=nil; rec.countdownLayout=nil
env2.DB.mode="perimeter"; env2.DB.reverse=true
assert(paintDirect(rec,secret,secret,secret,snapshot))
assert(rec.countdownEdges[1].anchor[3]==120 and rec.countdownEdges[2].anchor[4]==-72)
assert(rec.countdownEdges[3].anchor[3]==-40 and rec.countdownEdges[4].anchor[4]==0)
env2.DB.reverse=false
assert(paintDirect(rec,secret,secret,secret,snapshot))
assert(rec.countdownEdges[1].anchor[3]==0 and rec.countdownEdges[4].anchor[4]==-108)
local timingCode=section("local function IsSecret","local MODES")..section("local function RecordTiming","local function Update()")
local timing=assert(load(timingCode.."\nreturn RecordTiming","timing mock","t",_G))()
local sample={updates=0,total=0,max=0}
timing(sample,.25); timing(sample,1.5); timing(sample,-1); timing(sample,0/0)
assert(sample.updates==2 and sample.total==1.75 and sample.max==1.5)
assert(src:find('panel:SetScript("OnUpdate",nil)',1,true))
assert(src:find('if previewEnergy>=100 then StopPreview() end',1,true))
assert(src:find('StopPreview(); if abilityFilters',1,true))
assert(src:find('if not performanceSample.enabled or type(debugprofilestop)',1,true))
print("PASS: appearance migration, per-style reset, reversed perimeter geometry, timing and preview lifecycle")

local categoryCode=section("local FINISHERS","local function GetEnergyCost")
local category=assert(load(categoryCode.."\nreturn SpellCategory","category mocks","t",_G))()
assert(category(1752,false)=="builder" and category(11294,false)=="builder")
assert(category(2098,false)=="finisher" and category(1316709,false)=="finisher")
assert(category(999,true)=="finisher" and category(1766,false)=="other")
assert(category(1329283,false)=="other") -- Shank can be a conditional builder.
filterEnv.DB.showCategories={builder=false,finisher=true,other=true}
filterEnv.DB.excludedSpells={}
r.category="builder"; assert(excluded(r))
r.category="other"; assert(not excluded(r))
filterEnv.DB.excludedSpells[123]=true; assert(excluded(r))
assert(src:find('record.category=SpellCategory(spellID,entry.finisher)',1,true))
assert(src:find('DB.showCategories[key]=self:GetChecked()',1,true))
assert(src:find('Slider("TintOpacity",240,-(layout.tint-8)',1,true))
print("PASS: known ability categories, conservative unknown handling and category/individual filters")

-- True gradient follows native fill geometry; no protected values are read.
local fillEnv=setmetatable({DB={mode="rising",tint=true,opacity=1,tintOpacity=.2,fillEffect="gradient",reverse=false},CreateColor=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end},{__index=_G})
local fillCode=section("local function RisingFillStyle","local function Style(record)")
local styleFill=assert(load(fillCode.."\nreturn RisingFillStyle","gradient mocks","t",fillEnv))()
local gradient={Hide=function(self) self.shown=false end,Show=function(self) self.shown=true end,SetBlendMode=function(self,v) self.blend=v end,SetGradient=function(self,o,lo,hi) self.orientation=o;self.low=lo;self.high=hi end}
local fillRecord={riseGradient=gradient,line={SetBlendMode=function(self,v) self.blend=v end},riseTint={SetStatusBarColor=function(self,r,g,b,a) self.alpha=a end}}
styleFill(fillRecord,.2,1,.3)
assert(gradient.shown and gradient.blend=="BLEND" and gradient.orientation=="VERTICAL")
assert(gradient.high.a==.5 and gradient.low.a<gradient.high.a and fillRecord.riseTint.alpha==0 and fillRecord.fillEffectActual=="gradient")
fillEnv.DB.reverse=true; styleFill(fillRecord,.2,1,.3)
assert(gradient.low.a==.5 and gradient.high.a<gradient.low.a)
fillEnv.DB.fillEffect="luminous"; styleFill(fillRecord,.2,1,.3)
assert(gradient.blend=="ADD" and fillRecord.line.blend=="ADD" and fillRecord.fillEffectActual=="luminous")
fillEnv.DB.tint=false; styleFill(fillRecord,.2,1,.3)
assert(not gradient.shown and fillRecord.riseTint.alpha==0 and fillRecord.line.blend=="BLEND")
fillEnv.DB.tint=true; fillEnv.DB.fillEffect="solid"; styleFill(fillRecord,.2,1,.3)
assert(not gradient.shown and fillRecord.riseTint.alpha==.2 and fillRecord.fillEffectActual=="solid")
fillEnv.DB.fillEffect="gradient"; gradient.SetGradient=function() error("unsupported") end
styleFill(fillRecord,.2,1,.3)
assert(not gradient.shown and fillRecord.riseTint.alpha==.2 and fillRecord.fillEffectActual=="solid")
fillRecord.riseGradient=nil; styleFill(fillRecord,.2,1,.3); assert(fillRecord.riseTint.alpha==.2)
assert(prefs.fillEffect=="solid")
prefs.fillEffect="luminous"; saveStyle(); assert(styleMode("rising") and prefs.fillEffect=="solid")
assert(styleMode("bar") and prefs.fillEffect=="luminous")
resetStyle(); assert(prefs.fillEffect=="solid")
assert(layout.fillEffect-(layout.tint-8+layout.sliderOffset+layout.sliderHeight)>=6)
assert(layout.progress-(layout.fillEffect+layout.buttonHeight)>=10)
assert(src:find('gradient:SetAllPoints(nativeFill)',1,true))
print("PASS: rising gradient endpoints, additive blend, direction, solid fallback, appearance persistence and spacing")

-- Readiness has its own native curve; it never needs 1-secret arithmetic.
env.C_CurveUtil={CreateCurve=function() return {points={},AddPoint=function(self,x,y) self.points[#self.points+1]={x,y} end} end}
near(eval(make(45,"ready"),.44),0); near(eval(make(45,"ready"),.45),1)
near(eval(make(45,"ready"),.9),1); near(eval(make(120,"ready"),1),0)
local readyEnv=setmetatable({issecretvalue=env.issecretvalue,READY_ONESHOT={burst=true,flash=true,softflash=true}},{__index=_G})
local readyCode=section("local function IsSecret","local MODES")..section("local function ReadySignal","local function StopReadyVisual")
local signal,transition,choice=assert(load(readyCode.."\nreturn ReadySignal,ReadyTransition,ReadyChoice","ready mocks","t",readyEnv))()
local rr={spellID=1752}
local ready,source=signal(rr,1); assert(ready==true and source=="public energy")
assert(not transition(rr,ready,source)) -- no flash on first sample
assert(not transition(rr,false,source)); assert(transition(rr,true,source)); assert(not transition(rr,true,source))
assert(not transition(rr,nil,"protected threshold")); assert(not transition(rr,true,source))
assert(choice("burst",nil,true)=="pulse" and choice("burst",nil,false)=="none")
assert(choice("flash",false,true)=="flash" and choice("proc",nil,false)=="proc")
readyEnv.C_Spell={IsSpellUsable=function(id) assert(id==1752); return false,true end}
ready,source=signal(rr,secret); assert(ready==false and source=="public power usability")
assert(not transition(rr,ready,source))
readyEnv.C_Spell.IsSpellUsable=function() return true,false end
ready,source=signal(rr,secret); assert(ready==true and transition(rr,ready,source))
rr.finisher=true; ready,source=signal(rr,secret); assert(ready==nil and source=="protected threshold")
rr.finisher=false; readyEnv.C_Spell.IsSpellUsable=function() return secret,secret end
ready,source=signal(rr,secret); assert(ready==nil)
assert(src:find('pcall(record.readyGate.SetAlpha,record.readyGate,alpha)',1,true))
assert(src:find('SafeUpdateReady(record,readyAlpha,not demo and comboOK and cooldownOK and comboPublic~=0 and cooldownPublic~=0',1,true))
assert(src:find('Clear(record); ClearReady(record); record.progressState="excluded"',1,true))
assert(src:find('UI-HUD-ActionBar-Casting-Complete-Glow',1,true))
assert(src:find('UI-HUD-ActionBar-GCD-Flipbook',1,true))
assert(src:find('UI-HUD-ActionBar-Proc-Loop-Flipbook',1,true))
print("PASS: ready curve, public transition and source changes, protected fallback, filter wiring and native asset selection")

-- Exercise the real visual lifecycle with mock native frames/animations.
local function nativeWidget(parent)
    local w={parent=parent,shown=false,animations={},scripts={},playCount=0}
    for _,method in ipairs({"EnableMouse","SetAllPoints","SetFrameLevel","SetPoint","SetHeight","SetWidth","SetTexture","SetAtlas","SetBlendMode","AddMaskTexture","SetVertexColor","SetTarget","SetDuration","SetOrder","SetScaleFrom","SetScaleTo","SetSmoothing","SetFromAlpha","SetToAlpha","SetFlipBookRows","SetFlipBookColumns","SetFlipBookFrames"}) do
        w[method]=function(self,...) self[method.."Args"]={...} end
    end
    function w:GetFrameLevel() return 1 end
    function w:SetAlpha(v) self.alpha=v end
    function w:Show() self.shown=true end
    function w:Hide() self.shown=false end
    function w:CreateTexture() return nativeWidget(self) end
    function w:CreateMaskTexture() return nativeWidget(self) end
    function w:CreateAnimationGroup() return nativeWidget(self) end
    function w:CreateAnimation(kind) local a=nativeWidget(self); a.kind=kind; self.animations[#self.animations+1]=a; return a end
    function w:SetScript(name,fn) self.scripts[name]=fn end
    function w:SetLooping(v) self.looping=v end
    function w:Play() self.playCount=self.playCount+1 end
    function w:Stop() self.stopped=true end
    return w
end
local visualEnv=setmetatable({issecretvalue=env.issecretvalue,WHITE="white",
    READY_ONESHOT={burst=true,flash=true,softflash=true},
    DB={readyEffect="burst",readyFallback=true,readyOpacity=.7,readyMatchColor=false},
    CreateFrame=function(_,_,parent) return nativeWidget(parent) end,
    C_Texture={GetAtlasInfo=function() return {} end},
    ResolveColor=function() return {.2,.5,1} end}, {__index=_G})
local visualCode=section("local function IsSecret","local MODES")..section("local function ReadySignal","local function RebuildGroups")
local updateReady,clearReady=assert(load(visualCode.."\nreturn SafeUpdateReady,ClearReady","ready lifecycle","t",visualEnv))()
local record={frame=nativeWidget(),comboGate=nativeWidget(),spellID=1752}
updateReady(record,1,true); assert(not record.readyVisual) -- no initial flash
updateReady(record,0,true); updateReady(record,1,true)
local burst=record.readyVisual
assert(burst and burst.effect=="burst" and burst.anim.playCount==1)
assert(burst.anim.animations[1].kind=="Scale" and burst.anim.animations[2].kind=="Alpha")
assert(burst.textures[1].SetAtlasArgs[1]=="UI-HUD-ActionBar-Casting-Complete-Glow")
assert(record.readyGate.parent==record.comboGate)
updateReady(record,1,true); assert(burst.anim.playCount==1)
burst.anim.scripts.OnFinished(); assert(not record.readyVisual and not burst.frame.shown)
updateReady(record,1,true); assert(burst.anim.playCount==1)
updateReady(record,0,true); updateReady(record,1,true); assert(burst.anim.playCount==2)
updateReady(record,1,false); assert(not record.readyVisual and record.readyPrevious==nil and record.readyGate.alpha==0)
visualEnv.DB.readyEffect="flash"; updateReady(record,secret,true)
assert(record.readyVisual.effect=="pulse" and record.readyVisual.anim.looping=="BOUNCE" and rawequal(record.readyGate.alpha,secret))
visualEnv.DB.readyFallback=false; updateReady(record,secret,true); assert(not record.readyVisual)
visualEnv.DB.readyEffect="proc"; updateReady(record,secret,true)
assert(record.readyVisual.effect=="proc" and record.readyVisual.anim.looping=="REPEAT")
local proc=record.readyVisual
assert(proc.anim.animations[1].SetFlipBookRowsArgs[1]==6 and proc.anim.animations[1].SetFlipBookFramesArgs[1]==30)
visualEnv.DB.readyEffect="flash"; updateReady(record,0,true); updateReady(record,1,true)
assert(record.readyVisual.effect=="flash" and record.readyVisual.anim.animations[1].SetFlipBookFramesArgs[1]==22)
visualEnv.DB.readyEffect="none"; updateReady(record,1,true); assert(not record.readyVisual)
visualEnv.DB.readyEffect="burst"; visualEnv.C_Texture.GetAtlasInfo=function() return nil end
local missing={frame=nativeWidget(),comboGate=nativeWidget(),spellID=1752}
updateReady(missing,0,true); updateReady(missing,1,true)
assert(missing.readyVisual.effect=="softflash" and missing.readyActual=="softflash" and missing.readyReason:find("artwork fallback",1,true))
clearReady(missing); assert(not missing.readyVisual)
print("PASS: actual ready lifecycle, one-shot non-repetition, native flipbooks, protected alpha, filter cleanup and missing-art fallback")

-- Standalone tracker consumes the same groups and retains conservative public geometry.
env.C_CurveUtil={CreateCurve=function() return {points={},AddPoint=function(self,x,y) self.points[#self.points+1]={x,y} end} end}
near(eval(make(100,"dial"),.5),.375); near(eval(make(100,"dial"),1),.75)
local tf=assert(io.open("addon/RogueEnergySweep/Tracker.lua")); local ts=tf:read("*a"); tf:close()
local function trackerSection(a,b)
    local start=assert(ts:find(a,1,true)); local stop=assert(ts:find(b,start+1,true)); return ts:sub(start,stop-1)
end
local dialPoint,sorted=assert(load(trackerSection("local function DialPoint","local function SpellInfo").."\nreturn DialPoint,SortedEntries","tracker geometry","t",_G))()
local x,y=dialPoint(0,100,100); near(x,0); near(y,-100)
x,y=dialPoint(100,100,100); near(x,100); near(y,0)
local entries=sorted({[1]={spellID=1,cost=45,current=true},[2]={spellID=2,cost=25,current=true},[3]={spellID=3,cost=35,current=false}},{[3]=true},false,function() return false end)
assert(#entries==1 and entries[1].spellID==3)
entries=sorted({[1]={spellID=1,cost=45,current=true},[2]={spellID=2,cost=25,current=true}},{},true,function() return false end)
assert(#entries==2 and entries[1].spellID==2)
assert(src:find("Tracker.Group(cost,group,fill,deficit,visibility,readyAlpha",1,true))
assert(src:find("for cost in pairs(Tracker.Costs()) do AddCost(cost)",1,true))
assert(ts:find("pcall(row.combo.SetAlpha,row.combo,c)",1,true))
assert(ts:find("pcall(dial.fill.SetRadialProgressBarPercent,dial.fill,value)",1,true))
print("PASS: tracker dial native curve, public threshold geometry, selection and shared group wiring")
assert(loadfile("addon/RogueEnergySweep/Tracker.lua"))

local trackerNS={}
local frames={}
local function trackerWidget(parent,kind,name)
    local w={parent=parent,kind=kind,name=name,shown=false,alpha=1,points={},children={},scripts={},scale=1}
    if parent and parent.children then parent.children[#parent.children+1]=w end
    for _,method in ipairs({"SetMovable","SetClampedToScreen","RegisterForDrag","SetFrameStrata","SetFrameLevel","SetDrawLayer","SetBlendMode","SetVertexColor","SetColorTexture","SetStatusBarColor","SetStatusBarTexture","SetRenderMode","SetRadialProgressBarReverse","SetRadialProgressBarPercent","SetMinMaxValues","SetValue","SetText","SetWidth","SetHeight","SetTexture","SetAllPoints","SetPoint","SetSize","ClearAllPoints","EnableMouse","SetScale","StartMoving","StopMovingOrSizing"}) do
        w[method]=function(self,...) self[method.."Args"]={...} end
    end
    function w:SetScript(k,v) self.scripts[k]=v end
    function w:GetFrameLevel() return 1 end
    function w:GetCenter() return 0,0 end
    function w:GetEffectiveScale() return 1 end
    function w:GetName() return self.name end
    function w:SetAlpha(v) self.alpha=v end
    function w:Show() self.shown=true end
    function w:Hide() self.shown=false end
    function w:IsShown() return self.shown end
    function w:SetShown(v) self.shown=v end
    function w:CreateTexture() return trackerWidget(self,"Texture") end
    function w:CreateFontString() return trackerWidget(self,"FontString") end
    return w
end
local ui=trackerWidget(nil,"UIParent")
local trackerEnv=setmetatable({UIParent=ui,unpack=table.unpack,issecretvalue=env.issecretvalue,
    C_Spell={GetSpellInfo=function(id) return {name="Ability "..id,iconID=id+100} end},
    UnitPower=function() return secret end,
    CreateFrame=function(kind,name,parent) local w=trackerWidget(parent,kind,name); frames[#frames+1]=w; return w end
},{__index=_G})
assert(loadfile("addon/RogueEnergySweep/Tracker.lua","t",trackerEnv))("RogueEnergySweep",trackerNS)
local tracker=trackerNS.Tracker
local paints,readies=0,0
tracker.Configure({safe=function(v) if rawequal(v,secret) then return nil end; if type(v)=="number" then return v end end,
    secret=env.issecretvalue,excluded=function() return false end,
    cost=function() return 35,true,true,true end,category=function() return "finisher" end,
    curve=function(cost,kind) return {cost=cost,kind=kind} end,
    evaluate=function() return secret,true end,
    make=function(button) return {button=button} end,
    style=function() end,clear=function() end,clearReady=function() end,
    ready=function(_,alpha) assert(rawequal(alpha,secret)); readies=readies+1 end,
    paint=function(_,fill,deficit,visibility,group,direct) assert(rawequal(fill,secret) and rawequal(visibility,secret)); paints=paints+1 end,
    cooldown=function() return secret,"native" end})
local trackerDB={readyEffect="none"}
tracker.Init(trackerDB)
assert(trackerDB.tracker.enabled==false and trackerDB.tracker.actionBars==true)
local tracked={{spellID=1,cost=35,finisher=true,category="finisher"},{spellID=2,cost=35,category="builder"},{spellID=3,cost=45,category="builder"}}
tracker.Command("dial"); assert(tracker.Sync(tracked,100)); assert(tracker.Begin(false))
assert(tracker.Costs()[35] and tracker.Costs()[45])
tracker.Group(35,{start=secret},secret,secret,secret,secret,true,true,secret,true,{},true,false)
tracker.Finish(false); assert(tracker.Status():find("native radial",1,true) and tracker.Status():find("last error none",1,true))
for _,layoutName in ipairs({"bars","rings","icons","freeform"}) do
    tracker.Command(layoutName); assert(tracker.Sync(tracked,100)); assert(tracker.Begin(false))
    tracker.Group(35,{start=secret},secret,secret,secret,secret,true,true,secret,true,{},true,false)
    assert(tracker.Status():find("last error none",1,true))
end
assert(paints==4 and readies==10)
trackerDB.tracker.auto=false; trackerDB.tracker.selected[1]=true
assert(tracker.Sync({tracked[3]},100)); assert(tracker.Costs()[35] and not tracker.Costs()[45])
tracker.Command("off"); assert(tracker.Sync(tracked,100)); assert(not tracker.Begin(false) and trackerDB.tracker.actionBars)
print("PASS: all five tracker layouts, protected group forwarding, manual selection, ready effects and disabled lifecycle")

assert(loadfile("addon/RogueEnergySweep/GCD.lua"))
assert(loadfile("addon/RogueEnergySweep/Chains.lua"))
local chainFile=assert(io.open("addon/RogueEnergySweep/Chains.lua")); local chainSrc=chainFile:read("*a"); chainFile:close()
local first=assert(chainSrc:find("local function RepeatThreshold",1,true)); local last=assert(chainSrc:find("local function GetColor",first,true))
local repeatCost,followCost=assert(load(chainSrc:sub(first,last-1).."\nreturn RepeatThreshold,FollowThreshold","chain thresholds","t",_G))()
assert(repeatCost(45,2,10)==80 and repeatCost(35,3,10)==85 and followCost(45,60,10)==95)
assert(followCost(45,25,10)==60 and followCost(45,5,10)==45)
print("PASS: repeat and follow-up threshold math")

local bpSource=assert(io.open("addon/RogueEnergySweep/Tracker.lua")); local bpText=bpSource:read("*a"); bpSource:close()
local bpFirst=assert(bpText:find("local function Breakpoints",1,true)); local bpLast=assert(bpText:find("local function BreakpointItem",bpFirst,true))
local points=assert(load(bpText:sub(bpFirst,bpLast-1).."\nreturn Breakpoints","breakpoints","t",_G))()
local bp=points({{cost=25},{cost=45},{cost=45},{cost=60},{cost=120}},100)
assert(#bp==5 and bp[1]==0 and bp[2]==25 and bp[3]==45 and bp[4]==60 and bp[5]==100)
bp=points({{cost=25},{cost=35},{cost=45},{cost=60}},100)
assert(#bp==6 and bp[3]==35)
print("PASS: unique breakpoint costs, over-cap handling and talent change")
local gcdNS={}
local gcdEnv=setmetatable({C_CurveUtil=env.C_CurveUtil,issecretvalue=env.issecretvalue,GetPowerRegen=function() return 10,10 end,
    C_Spell={GetSpellCooldownDuration=function() return {GetRemainingDuration=function() return 1 end} end,
        GetSpellCooldown=function(id) return {isOnGCD=id==1} end}},{__index=_G})
assert(loadfile("addon/RogueEnergySweep/GCD.lua","t",gcdEnv))("RogueEnergySweep",gcdNS)
local gcd=gcdNS.GCD
gcd.Configure({safe=function(v) if type(v)=="number" then return v end end,secret=env.issecretvalue,evaluate=function(c) return eval(c,.55),true end})
gcd.Init({gcdAware=true}); gcd.CooldownEvent({{spellID=1},{spellID=2}}); gcd.Begin(100,false)
local gf,gd,gv,gr,projected=gcd.Project(1,60,.55/ .6,1-.55/.6,1,0,false)
near(gf,1); near(gd,0); near(gv,0); near(gr,1); assert(projected)
gf,gd,gv,gr,projected=gcd.Project(2,60,.5,.5,1,0,false); near(gf,.5); near(gv,1); assert(not projected)
gf,gd,gv,gr,projected=gcd.Project(1,60,secret,secret,1,0,true); assert(rawequal(gf,secret) and rawequal(gd,secret)); near(gv,0); assert(projected)
gcdEnv.C_Spell.GetSpellCooldownDuration=function() return {GetRemainingDuration=function() return secret end} end
gcd.Begin(100,false); gf,gd,gv,gr,projected=gcd.Project(1,60,.5,.5,1,0,false); near(gf,.5); assert(not projected)
print("PASS: GCD projection, off-GCD exclusion, native countdown preservation and protected fallback")
