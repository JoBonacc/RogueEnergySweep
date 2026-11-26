-- GCD-aware energy rendering. No arithmetic or branching on protected values.
local _,ns=...
local G={}; ns.GCD=G
local api,db,maxEnergy,credit= nil,nil,100,0
local onGCD,cache={},{}
local status="off"
function G.Configure(a) api=a end
function G.Init(d) db=d; d.gcdAware=d.gcdAware==true; onGCD={}; cache={} end
function G.CooldownEvent(records)
    if not db or not db.gcdAware or not C_Spell or not C_Spell.GetSpellCooldown then return end
    local seen={}
    for _,r in ipairs(records) do
        local id=r.spellID
        if id and not seen[id] then
            seen[id]=true; onGCD[id]=nil
            local ok,info=pcall(C_Spell.GetSpellCooldown,id)
            if ok and not api.secret(info) and type(info)=="table" then
                local v=info.isOnGCD
                if not api.secret(v) and type(v)=="boolean" then onGCD[id]=v end
            end
        end
    end
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
    if onGCD[id]~=nil then return onGCD[id] end
    -- If the legacy public base-cooldown API is present, its second return
    -- identifies the spell's start recovery; otherwise stay conservative.
    if type(GetSpellBaseCooldown)=="function" then
        local ok,_,gcd=pcall(GetSpellBaseCooldown,id)
        gcd=ok and api.safe(gcd) or nil
        if gcd then return gcd>0 end
    end
    return false
end
function G.Begin(max,demo)
    if maxEnergy~=max then cache={} end
    maxEnergy=max; credit=0
    if not db or not db.gcdAware or demo then status="off"; return end
    status="actual energy (GCD or regen unavailable)"
    if not C_Spell or not C_Spell.GetSpellCooldownDuration then return end
    local ok,d=pcall(C_Spell.GetSpellCooldownDuration,61304,false)
    local remaining
    if ok and not api.secret(d) and d~=nil then
        local good,v=pcall(function() return d:GetRemainingDuration() end)
        remaining=good and api.safe(v) or nil
    end
    -- A duration object can be restricted while its public recovery field is
    -- still accessible. Only use documented, independently public timing.
    if remaining==nil and C_Spell.GetSpellCooldown then
        local good,info=pcall(C_Spell.GetSpellCooldown,61304)
        if good and not api.secret(info) and type(info)=="table" then
            remaining=api.safe(info.timeUntilEndOfStartRecovery)
            if remaining==nil and type(GetTime)=="function" then
                local start,duration,modRate=api.safe(info.startTime),api.safe(info.duration),api.safe(info.modRate)
                local now=api.safe(GetTime())
                if start and duration and now and (modRate==1 or (modRate==nil and not api.secret(info.modRate))) then remaining=math.max(0,start+duration-now) end
            end
        end
    end
    if remaining==nil then return end
    if remaining<=0 then status="actual energy (no GCD)"; return end
    local rate=Regen()
    if not rate then return end
    credit=Credit(rate,remaining)
    status=string.format("public GCD: %.2fs / %.1f energy per sec / +%.2f projected",remaining,rate,credit)
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
    if credit<=0 or cost>maxEnergy or not CanProject(id) then return fill,deficit,visibility,ready,false end
    local v,ok=Evaluate(cost,"visibility")
    local r,ok2=Evaluate(cost,"ready")
    if not ok or not ok2 then return fill,deficit,visibility,ready,false end
    -- Countdown snapshots stay based on actual energy, only visibility/readiness
    -- are projected. Energy-based fill can use the projected value directly.
    if countdown then return fill,deficit,v,r,true end
    local f,a=Evaluate(cost,"fill"); local d,b=Evaluate(cost,"deficit")
    if a and b then return f,d,v,r,true end
    return fill,deficit,visibility,ready,false
end
function G.Status() return status end
