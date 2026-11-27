-- GCD-aware energy: only project from public, measured time and regeneration.
local _,ns=...
local G={}; ns.GCD=G
local api,db,maxEnergy,credit=nil,nil,100,0
local onGCD,cache,known={},{},{}
local status,source="off","unavailable"
local projections,blocked,lastBlocked=0,0,"none"
local observations={}
local function Read(fn,...)
    if type(fn)~="function" then return nil,"missing" end
    local ok,v=pcall(fn,...)
    if not ok then return nil,"error" end
    if api.secret(v) then return nil,"protected" end
    if v==nil then return nil,"nil" end
    return v,"public"
end
local function Field(id,key)
    if not C_Spell then return nil,"missing" end
    -- Individual fields can be public even if the other fields are secret.
    return Read(function() return C_Spell.GetSpellCooldown(id)[key] end)
end
local function Number(v,kind)
    if kind=="public" and api.safe(v)==nil then return nil,"invalid" end
    return v,kind
end
local function Remaining(id)
    if not C_Spell then return nil,"missing" end
    local exists,why=Read(C_Spell.DoesSpellExist,id)
    if exists==false and why=="public" then return nil,"spell absent" end
    local active=Field(id,"isActive")
    local remain,kind=Number(Read(function()
        local d=C_Spell.GetSpellCooldownDuration(id,false)
        return d:GetRemainingDuration()
    end))
    if remain~=nil and remain>0 and remain<=2 then return remain,"duration object" end
    if active==false then return 0,"inactive" end
    local recovery,rkind=Number(Field(id,"timeUntilEndOfStartRecovery"))
    if recovery~=nil and recovery>=0 and recovery<=2 then
        if recovery>0 or active~=true then return recovery,"start recovery" end
    end
    local st,skind=Number(Field(id,"startTime"))
    local du,dkind=Number(Field(id,"duration"))
    local mod,mkind=Number(Field(id,"modRate"))
    local now=api.safe(type(GetTime)=="function" and GetTime() or nil)
    if st and du and now and (mod==1 or mkind=="nil") then
        local left=math.max(0,st+du-now)
        if left<=2 and (left>0 or active~=true) then return left,"public cooldown" end
    end
    if remain==0 and active~=true then return 0,"duration object" end
    return nil,"active="..tostring(active).." remaining="..kind.." recovery="..rkind.." start="..skind.." duration="..dkind.." rate="..mkind
end
local function Regen()
    local function Rate(fn,...)
        if type(fn)~="function" then return nil,"missing" end
        local ok,a,b=pcall(fn,...)
        if not ok then return nil,"error" end
        local r
        -- The active-casting rate is preferred; never substitute a public
        -- inactive rate for a protected active rate.
        if api.secret(b) then return nil,"protected" end
        if b~=nil then r=api.safe(b) else r=api.safe(a) end
        if r and r>=0 and r<=100 then return r,"public" end
        return nil,api.secret(a) and "protected" or "invalid"
    end
    local r,k=Rate(GetPowerRegenForPowerType,Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
    if r~=nil then return r,"power type" end
    local rr,kk=Rate(GetPowerRegen)
    if rr~=nil then return rr,"player" end
    return nil,k.."/"..kk
end
function G.Configure(a) api=a end
function G.Init(d)
    db=d; d.gcdAware=d.gcdAware==true; onGCD={}; cache={}; known={}
    projections,blocked,lastBlocked=0,0,"none"; observations={}
end
function G.CooldownEvent(records)
    if not db or not db.gcdAware then return end
    local seen={}
    for _,r in ipairs(records) do
        local id=r.spellID
        if id and not seen[id] then
            seen[id]=true; onGCD[id]=nil
            local v,kind=Field(id,"isOnGCD")
            if kind=="public" and type(v)=="boolean" then onGCD[id]=v end
        end
    end
end
local function CanProject(id)
    if onGCD[id]==true then return true end
    if known[id]~=nil then return known[id] end
    if type(GetSpellBaseCooldown)=="function" then
        local ok,_,gcd=pcall(GetSpellBaseCooldown,id)
        gcd=ok and api.safe(gcd) or nil
        if gcd~=nil then known[id]=gcd>0; return known[id] end
    end
    return false
end
function G.Begin(max,demo)
    if maxEnergy~=max then cache={} end
    maxEnergy=max; credit=0
    if not db or not db.gcdAware or demo then status="off"; return end
    -- Forever uses TEST Scorch, 29515. Prefer it over the Retail dummy.
    -- Do not try an alternative if a supported source reports protected time.
    local remaining,why=Remaining(29515)
    source="29515"
    if remaining==nil and (why=="spell absent" or why=="missing") then
        remaining,why=Remaining(61304); source="61304"
    end
    if remaining==nil then
        status="actual energy (GCD time unavailable)"
        blocked=blocked+1; lastBlocked=source.." "..why; observations[source]=why
        return
    end
    if remaining<=0 then status="actual energy (no GCD)"; return end
    local rate,rwhy=Regen()
    if rate==nil then
        status="actual energy (regen unavailable)"
        blocked=blocked+1; lastBlocked="regen "..rwhy; observations.regen=rwhy
        return
    end
    credit=math.floor(rate*remaining*4)/4
    status=string.format("public GCD %s: %.2fs / %.1f energy per sec / +%.2f projected",source,remaining,rate,credit)
    observations[source]="public "..why; observations.regen="public "..rwhy
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
    if not ok or not ok2 then blocked=blocked+1; lastBlocked="native curve unavailable"; return fill,deficit,visibility,ready,false end
    if countdown then projections=projections+1; return fill,deficit,v,r,true end
    local f,a=Evaluate(cost,"fill"); local d,b=Evaluate(cost,"deficit")
    if a and b then projections=projections+1; return f,d,v,r,true end
    blocked=blocked+1; lastBlocked="native curve unavailable"
    return fill,deficit,visibility,ready,false
end
function G.Status()
    local seen={}; for k,v in pairs(observations) do seen[#seen+1]=k..": "..v end; table.sort(seen)
    return status.." | projected "..projections.." | unavailable "..blocked.." | last unavailable "..lastBlocked.." | "..table.concat(seen,"; ")
end
