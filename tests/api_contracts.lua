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
local code=section("local function IsSecret","local MODES")..section("local function MakeCurve","local function GetButtonSlot")..section("local function GetSpellFromSlot","local function Clear(")..section("local function ErrorNote","local function Paint")..section("local function Evaluate","-- A native radial StatusBar")..section("local function Countdown","local function ResetProgress")
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
