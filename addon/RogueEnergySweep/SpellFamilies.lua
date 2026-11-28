-- Explicit Classic rank families; unknown Forever abilities remain independent.
local _,ns=...
local F={}; ns.SpellFamilies=F
local families={
    {1752,1757,1758,1759,1760,8621,11293,11294},
    {53,2589,2590,2591,8721,11279,11280,11281},
    {1776,1777,8629,11285,11286},
    {703,8631,8632,8633,11289,11290},
    {8676,8724,8725,11267,11268,11269},
    {2098,6760,6761,6762,8623,8624,11299,11300},
    {5171,6774},{8647,8649,8650,11197,11198},
    {1943,8639,8640,11273,11274,11275},{408,8643},
    {6770,2070,11297},{1784,1785,1786,1787},
    {1804,},{1856,1857},{1725,},{2983,8696,11305}
}
local function Secret(v) return type(issecretvalue)=="function" and issecretvalue(v) end
function F.Known(id)
    local fn=C_SpellBook and C_SpellBook.IsSpellKnown
    if type(fn)~="function" then return nil end
    local ok,v=pcall(fn,id,0)
    if ok and not Secret(v) and type(v)=="boolean" then return v end
end
-- Migrate only forward to a publicly confirmed learned rank. Higher-rank
-- explicit settings win conflicts. Never replace an unknown family by name.
function F.Migrate(db)
    local map={}
    for _,family in ipairs(families) do
        local highest
        for i=#family,1,-1 do if F.Known(family[i])==true then highest=i; break end end
        if highest then for i=1,highest-1 do map[family[i]]=family[highest] end end
    end
    local function Move(t)
        if type(t)~="table" then return end
        for _,family in ipairs(families) do
            for i=#family,1,-1 do
                local old=family[i]; local new=map[old]
                if new and t[old]~=nil then if t[new]==nil then t[new]=t[old] end; t[old]=nil end
            end
        end
    end
    Move(db.excludedSpells)
    local c=db.chains
    if type(c)=="table" then
        Move(c.rules); Move(c.colors); Move(c.globalFollow)
        for source,r in pairs(c.rules or {}) do
            if type(r)=="table" then
                Move(r.conditions); Move(r.timing)
                if type(r.follow)=="table" then
                    local list,seen={},{}
                    for _,id in ipairs(r.follow) do
                        local new=map[id] or id
                        if new~=source and not seen[new] then list[#list+1]=new; seen[new]=true end
                    end
                    r.follow=list
                end
            end
        end
    end
    local t=db.tracker
    if type(t)=="table" then Move(t.selected); Move(t.positions) end
end
