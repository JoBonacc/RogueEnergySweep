-- GCD-aware energy rendering. No arithmetic or branching on protected values.
local _,ns=...
local G={}; ns.GCD=G
local api,db,maxEnergy,credit= nil,nil,100,0
local onGCD,cache,known={}, {}, {}
local status="off"
local gateCurve,gate,active,enabled=nil,1,nil,false
local fallbackCount,projectCount,lastFallback=0,0,"none"
local observedUntil,castUntil=0,0
local function Now() return type(GetTime)=="function" and api.safe(GetTime()) or nil end
function G.Configure(a) api=a end
function G.Init(d) db=d; d.gcdAware=d.gcdAware==true; onGCD={}; cache={}; known={}; observedUntil=0; castUntil=0; fallbackCount=0; projectCount=0; lastFallback="none" end
function G.CooldownEvent(records)
    if not db or not db.gcdAware or not C_Spell or not C_Spell.GetSpellCooldown then return end
    local seen={}; local newlyActive=false
    for _,r in ipairs(records) do
        local id=r.spellID
        if id and not seen[id] then
            seen[id]=true; local prior=onGCD[id]; onGCD[id]=nil
            local ok,v=pcall(function() local info=C_Spell.GetSpellCooldown(id); return info.isOnGCD end)
            if ok and not api.secret(v) and type(v)=="boolean" then onGCD[id]=v; if v and prior~=true then newlyActive=true end end
        end
    end
    if newlyActive then local now=Now(); if now then observedUntil=math.max(observedUntil,now+1) end end
end
local function Regen()
    local function Read(fn,...)
        if type(fn)~="function" then return nil end
        local ok,a,b=pcall(fn,...)
        if ok then return api.safe(b) or api.safe(a) end
    end
    local r=Read(GetPowerRegenForPowerType,Enum and Enum.PowerType and Enum.PowerType.Energy or 3) or Read(GetPowerRegen)
    if r and r>=0 and r<=100 then return r end
end
local function Credit(rate,remaining)
    if not rate or not remaining or remaining<=0 or remaining>2 then return 0 end
    -- Round down to quarter-energy bins, avoiding optimistic readiness and
    -- limiting curve rebuilds during the GCD.
    return math.floor(rate*remaining*4)/4
end
local function CanProject(id)
    if onGCD[id]==true then return true end
    if known[id]~=nil then return known[id] end
    -- If the legacy public base-cooldown API is present, its second return
    -- identifies the spell's start recovery; otherwise stay conservative.
    if type(GetSpellBaseCooldown)=="function" then
        local ok,_,gcd=pcall(GetSpellBaseCooldown,id)
        gcd=ok and api.safe(gcd) or nil
        if gcd then known[id]=gcd>0; return known[id] end
    end
    -- Public spell names for the core Forever rogue GCD-bound attacks. This
    -- avoids a stale false isOnGCD snapshot before the cooldown event arrives.
    -- Unknown abilities are not assumed to be on the GCD.
    if C_Spell and C_Spell.GetSpellInfo then
        local ok,name=pcall(function() local info=C_Spell.GetSpellInfo(id); return info.name end)
        if ok and not api.secret(name) and type(name)=="string" then
            local core={["Sinister Strike"]=true,Backstab=true,Gouge=true,Kick=true,Eviscerate=true,["Slice and Dice"]=true}
            known[id]=core[name]==true; return known[id]
        end
    end
    return false
end
-- Public success event for a known GCD-bound spell. Used only if the client
-- provides neither an active flag nor a usable native duration. This is a
-- bounded visual hold, not a reconstruction of protected energy/timing.
function G.Cast(id)
    if not db or not db.gcdAware or not id or not CanProject(id) then return end
    local now=Now(); if now then castUntil=now+1; observedUntil=math.max(observedUntil,castUntil) end
end
local function NativeGate(d)
    local ok,a=pcall(function()
        if not gateCurve then
            local c=C_CurveUtil.CreateCurve(); c:AddPoint(0,1); c:AddPoint(.001,0); c:AddPoint(86400,0); gateCurve=c
        end
        return d:EvaluateRemainingDuration(gateCurve)
    end)
    if ok and (api.secret(a) or api.safe(a)~=nil) then return a end
end
function G.Begin(max,demo)
    if maxEnergy~=max then cache={} end
    maxEnergy=max; credit=0; gate=1; active=nil
    enabled=db and db.gcdAware and not demo
    if not enabled then status="off"; return end
    status="actual energy (GCD unavailable)"
    local remaining,duration,info
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok,d=pcall(C_Spell.GetSpellCooldownDuration,61304,false)
        if ok then
            if api.secret(d) or d~=nil then
                duration=d
                local good,v=pcall(function() return d:GetRemainingDuration() end)
                remaining=good and api.safe(v) or nil
            end
        end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok,infoActive,recovery,started,length,rate=pcall(function()
            local v=C_Spell.GetSpellCooldown(61304)
            return v.isActive,v.timeUntilEndOfStartRecovery,v.startTime,v.duration,v.modRate
        end)
        if ok then
            if not api.secret(infoActive) and type(infoActive)=="boolean" then active=infoActive end
            if remaining==nil or (remaining<=0 and active==true) then
                remaining=api.safe(recovery)
                if remaining==nil then
                    local now=Now()
                    local st,du,mod=api.safe(started),api.safe(length),api.safe(rate)
                    if now and st and du and (mod==1 or (mod==nil and not api.secret(rate))) then remaining=math.max(0,st+du-now) end
                end
            end
        end
    end
    if remaining and remaining>0 then
        active=true; gate=0
        local rate=Regen()
        if rate then
            credit=Credit(rate,remaining)
            status=string.format("public GCD: %.2fs / %.1f energy per sec / +%.2f projected",remaining,rate,credit)
        else status="GCD hold (regen unavailable)" end
        return
    end
    -- Prefer a confirmed public active flag, then the native opaque duration.
    -- A zero duration alongside active=true is inconsistent; hold conservatively.
    if active==true then gate=0; status="GCD hold (timing protected)"; return end
    local now=Now()
    if active==false or remaining~=nil then
        -- A successful public cast can arrive before the cooldown API updates.
        -- Cover this short race without forcing a hold on unrelated spells.
        if now and now<castUntil then active=true; gate=0; status="GCD hold (public cast event)"; return end
        active=false; status="actual energy (no GCD)"; return
    end
    if api.secret(duration) or duration~=nil then
        local alpha=NativeGate(duration)
        if api.secret(alpha) or api.safe(alpha)~=nil then
            gate=alpha; status="native GCD visibility gate"
            return
        end
    end
    if now and now<observedUntil then active=true; gate=0; status="GCD hold (public cast event)"; return end
    -- An event-confirmed on-GCD spell may be held even without timing data;
    -- a subsequent cooldown event clears it. Do not guess for unknown spells.
    status="GCD event fallback"
end
local function ProjectedCurve(cost,kind,bonus,max)
    local curve=C_CurveUtil.CreateCurve()
    if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then curve:SetType(Enum.LuaCurveType.Linear) end
    local edge=cost-bonus
    local function value(e)
        local fill=math.min(1,math.max(0,(e+bonus)/cost))
        if kind=="fill" then return fill end
        if kind=="deficit" then return 1-fill end
        if kind=="ready" then return math.max(0,math.min(1,(e-edge+.5)/.5)) end
        return 1-math.max(0,math.min(1,(e-edge+.5)/.5))
    end
    local points={0,max}
    if edge>0 and edge<max then points[#points+1]=edge end
    if (kind=="ready" or kind=="visibility") and edge-.5>0 and edge-.5<max then points[#points+1]=edge-.5 end
    table.sort(points)
    for _,e in ipairs(points) do curve:AddPoint(e/max,value(e)) end
    return curve
end
local function Evaluate(cost,kind)
    local key=cost..":"..kind..":"..credit
    if cache[key]==nil then
        local ok,c=pcall(ProjectedCurve,cost,kind,credit,maxEnergy)
        cache[key]=ok and c or false
    end
    if not cache[key] then return nil,false end
    return api.evaluate(cache[key])
end
function G.Project(id,cost,fill,deficit,visibility,ready,countdown)
    if not enabled or cost>maxEnergy or not CanProject(id) then return fill,deficit,visibility,ready,false,1,false end
    local function Fallback()
        local alpha=gate
        if status=="GCD event fallback" and onGCD[id]==true and not Now() then alpha=0 end
        local public=api.safe(alpha)
        if api.secret(alpha) or (public and public<1) then
            fallbackCount=fallbackCount+1; lastFallback=status
            return fill,deficit,visibility,ready,false,alpha,active==true or onGCD[id]==true
        end
        return fill,deficit,visibility,ready,false,1,false
    end
    if credit<=0 then return Fallback() end
    local v,ok=Evaluate(cost,"visibility")
    local r,ok2=Evaluate(cost,"ready")
    if not ok or not ok2 then return Fallback() end
    -- Countdown snapshots stay based on actual energy, only visibility/readiness
    -- are projected. Energy-based fill can use the projected value directly.
    if countdown then projectCount=projectCount+1; return fill,deficit,v,r,true,1,false end
    local f,a=Evaluate(cost,"fill"); local d,b=Evaluate(cost,"deficit")
    if a and b then projectCount=projectCount+1; return f,d,v,r,true,1,false end
    return Fallback()
end
function G.Apply(record,alpha,hold)
    if not record.gcdGate then return end
    local ok=pcall(record.gcdGate.SetAlpha,record.gcdGate,alpha)
    if not ok then pcall(record.gcdGate.SetAlpha,record.gcdGate,hold and 0 or 1) end
end
function G.Status() return status.." | projections "..projectCount.." | holds "..fallbackCount.." | last hold "..lastFallback end
