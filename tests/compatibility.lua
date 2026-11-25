local f = assert(io.open('addon/RogueEnergySweep/RogueEnergySweep.lua')); local src=f:read('*a'); f:close()
local safe=assert(src:match('local function IsSecret%(value%).-\nend\n\nlocal function SafeNumber%(value%).-\nend'))
local block=assert(src:match('local SUPPORTED_INTERFACE = %d+.-\n\nlocal function Status%(%)')):gsub('\n\nlocal function Status%(%)$','')
local messages={}; local db={}; local env=setmetatable({DB=db,Say=function(s) messages[#messages+1]=s end},{__index=_G})
local status,check,clientBuild,checkBuild=assert(load(safe..'\n'..block..'\nreturn CompatibilityStatus, CheckCompatibility, ClientBuild, CheckBuild','diagnostic','t',env))()
local function interface(n) env.GetBuildInfo=function() return 'x','y','z',n end end
local function clear() for i=#messages,1,-1 do messages[i]=nil end end
local function contains(s) assert(messages[#messages]:find(s,1,true),messages[#messages]) end
interface(16001); assert(status()=='match'); check(true); assert(#messages==0); check(false); contains('matches target'); clear()
interface(16002); assert(status()=='newer'); check(true); contains('newer than target'); check(true); assert(#messages==1); check(false); assert(#messages==2); clear()
interface(16003); check(true); assert(#messages==1); clear()
interface(15999); assert(status()=='older'); check(true); contains('older than target'); clear()
interface(16001); check(true); assert(db.lastInterfaceWarning==nil); interface(16002); check(true); assert(#messages==1); clear()
for _,invalid in ipairs({0,-1,16001.5,'16001',math.huge}) do interface(invalid); assert(status()=='unknown'); check(true); assert(#messages==0) end
interface(nil); assert(status()=='unknown'); check(false); contains('unavailable'); clear()
env.GetBuildInfo=function() error('unavailable') end; assert(status()=='unknown'); check(true); assert(#messages==0)
env.GetBuildInfo=false; assert(status()=='unknown')
interface(16002); env.issecretvalue=function(v) return v==16002 end; assert(status()=='unknown'); check(true); assert(#messages==0)
assert(src:find('if event == "PLAYER_ENTERING_WORLD" then CheckCompatibility(true); CheckBuild(true); RequestScan()',1,true))
assert(src:find('CheckCompatibility(false)\n    CheckBuild(false)\nend',1,true))
print('PASS: compatibility matching, mismatch, deduplication, recovery, invalid/secret values, and event/status wiring')

env.issecretvalue=nil
local function build(n) env.GetBuildInfo=function() return '1.60.1',n,'date',16001 end end
build("71091"); assert(clientBuild()==71091); checkBuild(true); assert(#messages==0)
checkBuild(false); contains("last live-tested: not recorded"); clear()
build(71092); checkBuild(true); contains("New client build"); checkBuild(true); assert(#messages==1); clear()
build("71093"); checkBuild(true); assert(#messages==1); clear()
build("71091"); checkBuild(true); assert(db.lastBuildWarning==nil); build("71093"); checkBuild(true); assert(#messages==1); clear()
for _,invalid in ipairs({"bad","1.2",0,-1,71091.5,math.huge,{}}) do build(invalid); assert(clientBuild()==nil); checkBuild(true); assert(#messages==0) end
build(nil); assert(clientBuild()==nil); checkBuild(false); contains("not recorded"); clear()
build("71094"); env.issecretvalue=function(v) return v=="71094" end; assert(clientBuild()==nil); checkBuild(true); assert(#messages==0)
env.GetBuildInfo=function() error("unavailable") end; assert(clientBuild()==nil)
print("PASS: build parsing, independent same-interface alerts, deduplication, invalid and protected build values")
