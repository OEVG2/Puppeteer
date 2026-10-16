-- PTPool: a private, garbage-free table pool for Puppeteer.
--
-- Drop-in replacement for the parts of Compost-2.0 that Puppeteer uses (GetTable, Acquire, AcquireHash, Erase,
-- Reclaim), written for Lua 5.0's stop-the-world collector:
--   * Pooled tables are held by strong references, so a garbage collection never throws the pool away
--     (Compost keeps only 10 tables strongly and parks the rest in a weak table that every GC empties).
--   * Erasing a table keeps its allocated array/hash capacity, so a reused table does not have to grow again
--     (Compost's Erase forces a rehash that shrinks the table to nothing).
--   * No statistics bookkeeping, no gcinfo() calls, no varargs, no closures.
-- The pool is bounded; tables released beyond the cap are simply left to the collector.

PTPool = {}
local PTPool = PTPool

local MAX_POOLED = 3000

local pool = {}
local pooled = 0
local inPool = {} -- Set of tables currently sitting in the pool, used to ignore double releases

local next = next
local pairs = pairs
local type = type
local setmetatable = setmetatable
local getmetatable = getmetatable
local table_setn = table.setn

-- Clears every key of the table without shrinking it, and resets its table.getn size.
local function Wipe(t)
    if getmetatable(t) then
        setmetatable(t, nil)
    end
    for k in pairs(t) do
        t[k] = nil
    end
    table_setn(t, 0)
    return t
end
PTPool.Wipe = Wipe

local function Get()
    if pooled > 0 then
        local t = pool[pooled]
        pool[pooled] = nil
        pooled = pooled - 1
        inPool[t] = nil
        if next(t) then -- Something wrote to it after releasing it; never hand out a dirty table
            Wipe(t)
        end
        return t
    end
    return {}
end
PTPool.Get = Get

local function Release(t)
    if inPool[t] then -- Already released; pooling it twice would hand the same table to two owners
        return
    end
    Wipe(t)
    if pooled < MAX_POOLED then
        pooled = pooled + 1
        pool[pooled] = t
        inPool[t] = true
    end
end
PTPool.Release = Release

-- Releases the table and, down to the given depth, every table it contains.
local function ReleaseDeep(t, depth)
    if depth and depth > 0 then
        for _, v in pairs(t) do
            if type(v) == "table" then
                ReleaseDeep(v, depth - 1)
            end
        end
    end
    Release(t)
end
PTPool.ReleaseDeep = ReleaseDeep

-- Compost-compatible method interface, so existing "compost:Method(...)" call sites work unchanged.

function PTPool:GetTable()
    return Get()
end

function PTPool:Reclaim(t, depth)
    if type(t) ~= "table" then
        return
    end
    ReleaseDeep(t, depth)
end

function PTPool:Erase(t)
    if type(t) ~= "table" then
        return
    end
    return Wipe(t)
end

function PTPool:Acquire(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    local t = Get()
    local n = 0
    if a1 ~= nil then n = n + 1 t[n] = a1 end
    if a2 ~= nil then n = n + 1 t[n] = a2 end
    if a3 ~= nil then n = n + 1 t[n] = a3 end
    if a4 ~= nil then n = n + 1 t[n] = a4 end
    if a5 ~= nil then n = n + 1 t[n] = a5 end
    if a6 ~= nil then n = n + 1 t[n] = a6 end
    if a7 ~= nil then n = n + 1 t[n] = a7 end
    if a8 ~= nil then n = n + 1 t[n] = a8 end
    if a9 ~= nil then n = n + 1 t[n] = a9 end
    if a10 ~= nil then n = n + 1 t[n] = a10 end
    table_setn(t, n)
    return t
end

function PTPool:AcquireHash(k1, v1, k2, v2, k3, v3, k4, v4, k5, v5, k6, v6, k7, v7, k8, v8)
    local t = Get()
    if k1 ~= nil then t[k1] = v1 end
    if k2 ~= nil then t[k2] = v2 end
    if k3 ~= nil then t[k3] = v3 end
    if k4 ~= nil then t[k4] = v4 end
    if k5 ~= nil then t[k5] = v5 end
    if k6 ~= nil then t[k6] = v6 end
    if k7 ~= nil then t[k7] = v7 end
    if k8 ~= nil then t[k8] = v8 end
    return t
end

function PTPool.GetPooledCount()
    return pooled
end
