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
