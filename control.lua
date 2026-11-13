local Config = require('config')
local Game = require('game')
local Variants = require('variants')

local OUTFALL = Game.buildings.outfall_pump.name
local CHLORINE = Game.fluids.chlorine.name
local T = Config.tuning
local STEPS = Config.taint_steps

--[[
How it works

Every outfall is a small storage tank. Twice a second each one is emptied by this script:

  * a pollutant goes into the outfall's `pending` ledger and taints the water, nearest first.
    Water is tainted one tint at a time (see variants.lua): each step makes a tile one level
    stronger and costs 1 / STEPS of "units per tile", so a fully tainted tile costs exactly
    "units per tile". What has been spent moves to the `load` ledger.
  * chlorine is held in the outfall and treats tainted water the same way, one level at a time,
    but only while no outfall feeding the same slick has dumped a pollutant recently.
  * anything else is simply voided.

Every pass over the water moves each tile at most one step, so slicks fade in, mix and fade
out instead of jumping from one colour to another.

Outfalls whose slicks touch form a group. The group's water heads for a target tint: its two
biggest pollutants blended in proportion to how much of each it has dumped. New water is tainted
with the biggest one. Fully tainted water shifts toward the target blend for free.

The tiles themselves are the state of the water: nothing per tile is stored in `storage`.

storage.outfalls[unit_number] =
{
  entity, surface_index, x, y,   -- the outfall and where it stands
  origin,                        -- the water tile in front of it, once found
  pending = {pollutant = n},     -- dumped, not yet turned into tiles
  load = {pollutant = n},        -- dumped and turned into tiles
  chlorine = n,                  -- chlorine taken in, not yet used
  reach = n,                     -- furthest this outfall has tainted, in tiles
  taint = {radius = n, ...},     -- search state for water to taint
  clean = {radius = n, ...},     -- search state for water to treat
  queue, qi, queue_tag,          -- tiles found by the last search, nearest first
  target, repaint,               -- the tint its group heads for (see assign_groups)
  group_active, blocked,         -- set every update by assign_groups
  last_dump_tick, sees_chlorine, status
}
]]

--------------------------------------------------------------------------------
-- Lookup tables derived from prototypes. Rebuilt after every load, never saved.
--------------------------------------------------------------------------------

local maps

-- A tint is named by a short key, the same for every clean water tile:
--   "clean"       untainted
--   "p<a>:<l>"    pollutant `a` (index into Config.pollutants) at level `l`; level STEPS is fully tainted
--   "b<a>:<b>:<k>" fully tainted, a blend of pollutants a < b with `k` of STEPS parts being `b`
local function pure_key(a, level) return "p" .. a .. ":" .. level end

-- A fully tainted tint on the line between pollutants x < y, `k` steps of the way to y.
local function full_key(x, y, k)
  if not y or k <= 0 then return pure_key(x, STEPS) end
  if k >= STEPS then return pure_key(y, STEPS) end
  return "b" .. x .. ":" .. y .. ":" .. k
end

local function build_maps()
  local m =
  {
    info = {},       -- tile name -> {clean = clean tile name, a, b, k, level, pollutant = fluid it yields}; only `clean` for clean water
    tile_for = {},   -- clean tile name -> tint key -> tile name
    waterish = {},   -- every clean or tainted water tile name
    tainted = {},    -- every tainted tile name
    needs = {},      -- target signature -> {any = names, free = names}; filled on demand by `needs`
    fluids = {},     -- dumpable fluid name -> {pollutant = fluid name, potency = n, dilution = n}
    index = {},      -- pollutant fluid name -> index into Config.pollutants
    order = {}       -- pollutants in config order; ties in dominance go to the earlier one
  }

  local clean = {}
  for name, tile in pairs(prototypes.tile) do
    local fluid = tile.fluid
    if fluid and fluid.name == "water" then clean[#clean + 1] = name end
  end
  table.sort(clean)

  local used = {}
  for _, name in ipairs(clean) do
    m.info[name] = {clean = name}
    m.tile_for[name] = {clean = name}
    m.waterish[#m.waterish + 1] = name
    for _, variant in ipairs(Variants.for_source(name)) do
      if prototypes.tile[variant.name] then
        local key = variant.b and full_key(variant.a, variant.b, variant.k) or pure_key(variant.a, variant.level)
        local dominant = Variants.dominant(variant)
        m.info[variant.name] = {clean = name, a = variant.a, b = variant.b, k = variant.k, level = variant.level, pollutant = Config.pollutants[dominant].fluid}
        m.tile_for[name][key] = variant.name
        m.waterish[#m.waterish + 1] = variant.name
        m.tainted[#m.tainted + 1] = variant.name
        used[variant.a] = true
      end
    end
  end

  for index, pollutant in ipairs(Config.pollutants) do
    local fluid = pollutant.fluid
    if used[index] and prototypes.fluid[fluid] then
      local potency = pollutant.potency or 1
      m.index[fluid] = index
      m.order[#m.order + 1] = fluid
      m.fluids[fluid] = {pollutant = fluid, potency = potency, dilution = 1}
      local tainted_fluid = Config.tainted_fluid(fluid)
      if prototypes.fluid[tainted_fluid] then
        local dilution = Config.tainted_water_potency
        m.fluids[tainted_fluid] = {pollutant = fluid, potency = potency * dilution, dilution = dilution}
      end
    end
  end

  return m
end

local function get_maps()
  if not maps then maps = build_maps() end
  return maps
end

--------------------------------------------------------------------------------
-- Tints: one step at a time
--------------------------------------------------------------------------------

-- One step along the line between pollutants x < y, from `k` toward `goal`.
local function step_toward(x, y, k, goal)
  if k < goal then return full_key(x, y, k + 1) end
  if k > goal then return full_key(x, y, k - 1) end
end

-- One step from pollutant p, fully tainted, toward pollutant q.
local function slide(p, q)
  if p < q then return full_key(p, q, 1) end
  return full_key(q, p, STEPS - 1)
end

-- The next tint of a tile on its way to the group's `target`, and whether that step costs
-- pollutant. Returns nil once the tile shows the target.
--   target = {a, b, k, dominant, signature}: pollutants a < b blended k of STEPS toward b
--   (b is nil and k is 0 for a single pollutant); `dominant` is the one new water is tainted with.
local function next_taint(info, target)
  local a, b, k = target.a, target.b, target.k
  -- clean water, or water not yet fully tainted: one level stronger, in the dominant pollutant
  if not info.a then return pure_key(target.dominant, 1), true end
  if not info.b and info.level < STEPS then
    if info.a == target.dominant then return pure_key(info.a, info.level + 1), true end
    -- faint water of another pollutant takes the dominant one's colour at the same strength
    return pure_key(target.dominant, info.level), false
  end

  -- Fully tainted water moves along blends, for free.
  local x, y = info.a, info.b
  if not y then
    if not b then
      if x == a then return nil end
      return slide(x, a), false
    end
    if x == a then return step_toward(a, b, 0, k), false end
    if x == b then return step_toward(a, b, STEPS, k), false end
    return slide(x, target.dominant), false
  end
  if x == a and y == b then return step_toward(x, y, info.k, k), false end
  -- a blend that is not the target's: first back to whichever of its pollutants the target
  -- has, or else its larger one
  local goal
  if x == a or x == b then goal = 0
  elseif y == a or y == b then goal = STEPS
  elseif info.k <= STEPS / 2 then goal = 0
  else goal = STEPS end
  return step_toward(x, y, info.k, goal), false
end

-- The next tint of a tile being treated with chlorine, and whether the step takes pollutant out
-- of the water (rather than only unmixing a blend). Returns nil for clean water.
local function next_clean(info)
  if not info.a then return nil end
  if not info.b then
    if info.level <= 1 then return "clean", true end
    return pure_key(info.a, info.level - 1), true
  end
  -- a blend first settles on its larger pollutant, then fades
  if info.k <= STEPS / 2 then return full_key(info.a, info.b, info.k - 1), false end
  return full_key(info.a, info.b, info.k + 1), false
end

-- The water tile names that still have a step to take toward `target`: `any` for when the
-- outfall can pay, `free` for the steps that cost nothing.
local function needs(m, target)
  local cached = m.needs[target.signature]
  if cached then return cached end
  local any, free = {}, {}
  for _, name in ipairs(m.waterish) do
    local info = m.info[name]
    local tint, costs = next_taint(info, target)
    if tint and m.tile_for[info.clean][tint] then
      any[#any + 1] = name
      if not costs then free[#free + 1] = name end
    end
  end
  cached = {any = any, free = free}
  m.needs[target.signature] = cached
  return cached
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- Packs a tile position into one number so queues stay small in the save file.
local OFFSET, SPAN = 2 ^ 20, 2 ^ 21

local function key(x, y)
  return (x + OFFSET) * SPAN + (y + OFFSET)
end

local function unkey(k)
  local y = k % SPAN
  return (k - y) / SPAN - OFFSET, y - OFFSET
end

local function total(ledger)
  local sum = 0
  for _, amount in pairs(ledger) do sum = sum + amount end
  return sum
end

local function read_settings()
  local global = settings.global
  return
  {
    units_per_tile = global["cp-units-per-tile"].value,
    chlorine_per_tile = global["cp-chlorine-per-tile"].value,
    taint_ticks = global["cp-taint-seconds"].value * 60,
    max_radius = global["cp-max-slick-radius"].value,
    air_pollution = global["cp-air-pollution"].value
  }
end

local function set_status(outfall, name, diode)
  if outfall.status == name then return end
  outfall.status = name
  if name then
    outfall.entity.custom_status = {diode = defines.entity_status_diode[diode], label = {"cp-status." .. name}}
  else
    outfall.entity.custom_status = nil
  end
end

--------------------------------------------------------------------------------
-- Registering outfalls
--------------------------------------------------------------------------------

local function new_search()
  return {radius = T.start_radius}
end

local function register(entity)
  if not (entity and entity.valid and entity.name == OUTFALL) then return end
  storage.outfalls = storage.outfalls or {}
  if storage.outfalls[entity.unit_number] then return end
  local position = entity.position
  storage.outfalls[entity.unit_number] =
  {
    entity = entity,
    surface_index = entity.surface_index,
    x = position.x,
    y = position.y,
    pending = {},
    load = {},
    chlorine = 0,
    reach = 0,
    taint = new_search(),
    clean = new_search(),
    blocked = false,
    group_active = false
  }
end

local function register_all()
  storage.outfalls = storage.outfalls or {}
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({name = OUTFALL})) do
      register(entity)
    end
  end
end

-- The water tile nearest to the outfall. Looked up rather than computed from the outfall's
-- direction, so it stays right however the entity is rotated.
local function find_origin(outfall, surface, m)
  local tiles = surface.find_tiles_filtered({position = {outfall.x, outfall.y}, radius = 2.5, name = m.waterish})
  local best, best_distance
  for index = 1, #tiles do
    local position = tiles[index].position
    local dx, dy = position.x + 0.5 - outfall.x, position.y + 0.5 - outfall.y
    local distance = dx * dx + dy * dy
    if not best_distance or distance < best_distance then
      best, best_distance = {x = position.x, y = position.y}, distance
    end
  end
  return best
end

--------------------------------------------------------------------------------
-- Searching the water
--------------------------------------------------------------------------------

-- Finds the tiles named in `names` that are connected by water to `origin` and within `radius`.
-- Returns their packed positions nearest first, the number of water tiles connected to the
-- origin inside the search square, how many matches lay in the square but outside the radius,
-- and the set of connected water tiles (keyed by packed position).
-- Returns nil if the origin is not water any more.
local function scan(surface, origin, radius, names, m)
  local ox, oy = origin.x, origin.y
  local area = {{ox - radius, oy - radius}, {ox + radius + 1, oy + radius + 1}}
  local connected = surface.get_connected_tiles(origin, m.waterish, false, area)
  local connected_count = #connected
  if connected_count == 0 then return nil end

  local member = {}
  for index = 1, connected_count do
    local position = connected[index]
    member[key(position.x, position.y)] = true
  end
  if #names == 0 then return {}, connected_count, 0, member end

  local found = surface.find_tiles_filtered({area = area, name = names})
  local radius_squared = radius * radius
  local list, count, outside = {}, 0, 0
  for index = 1, #found do
    local position = found[index].position
    local k = key(position.x, position.y)
    if member[k] then
      local dx, dy = position.x - ox, position.y - oy
      local distance = dx * dx + dy * dy
      if distance <= radius_squared then
        count = count + 1
        list[count] = {k, distance}
      else
        outside = outside + 1
      end
    end
  end

  table.sort(list, function(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)

  local candidates = {}
  for index = 1, count do candidates[index] = list[index][1] end
  return candidates, connected_count, outside, member
end

-- Makes sure the outfall has a queue of tiles for the job described by `tag`.
--   "ok"         there are tiles queued
--   "empty"      nothing in reach yet; the search radius was grown for the next update
--   "exhausted"  nothing left anywhere in reach
--   "wait"       exhausted recently, not looking again yet
--   "no-origin"  the water in front of the outfall is gone
-- With `fixed` the radius never grows and an empty search is simply "exhausted".
-- When "exhausted", also returns the set of water tiles that was searched and whether that set
-- is the entire water body (as opposed to the part of it within the maximum radius).
local function refill(outfall, search, tag, names, settings_now, tick, surface, m, fixed)
  if outfall.queue and outfall.queue_tag == tag and outfall.qi <= #outfall.queue then return "ok" end
  outfall.queue, outfall.queue_tag = nil, nil
  if tick < (search.next_scan or 0) then return "wait" end

  local radius = search.radius
  local candidates, connected_count, outside, member = scan(surface, outfall.origin, radius, names, m)
  if not candidates then
    outfall.origin = nil
    return "no-origin"
  end

  -- If a wider search reached no new water, the whole water body is already inside it.
  local grew = search.scanned_radius and radius > search.scanned_radius
  local contained = grew and connected_count == search.scanned_connected
  search.scanned_radius, search.scanned_connected = radius, connected_count

  if #candidates > 0 then
    outfall.queue, outfall.queue_tag, outfall.qi = candidates, tag, 1
    return "ok"
  end
  local whole_body = contained and outside == 0
  if fixed then return "exhausted", member, whole_body end
  if radius >= settings_now.max_radius or whole_body then
    search.next_scan = tick + T.rescan_backoff
    return "exhausted", member, whole_body
  end
  search.radius = math.min(settings_now.max_radius, radius + T.radius_step)
  return "empty"
end

--------------------------------------------------------------------------------
-- Changing tiles
--------------------------------------------------------------------------------

local pump_warning_logged = false

-- An offshore pump keeps the fluid it was built on. Point it at whatever its tile yields now.
local function refresh_pump(pump)
  local expected = pump.get_fluid_source_fluid()
  if not expected then return end
  local filter = pump.get_fluid_filter(1)
  if filter and filter.name == expected then return end
  if not pump.set_fluid_filter(1, expected) then error("set_fluid_filter refused " .. expected) end
end

local SEARCH_PUMPS = {"offshore-pump"}
local SEARCH_PUMPS_AND_FISH = {"offshore-pump", "fish"}

local function apply_tiles(surface, tiles, tainting)
  -- Tile correction must stay on: it is also what redraws the shoreline of the land around the
  -- changed tiles. Without it the land's edge is not drawn over them and every tile at the coast
  -- shows as a hard square. It never changes the tiles around them.
  surface.set_tiles(tiles, true, false, false, false)

  local types = (tainting and T.kill_fish) and SEARCH_PUMPS_AND_FISH or SEARCH_PUMPS
  local pumps
  for index = 1, #tiles do
    local position = tiles[index].position
    local x, y = position[1], position[2]
    local nearby = surface.find_entities_filtered({position = {x + 0.5, y + 0.5}, radius = T.pump_search_radius, type = types})
    for _, entity in pairs(nearby) do
      if entity.type == "fish" then
        local where = entity.position
        if math.floor(where.x) == x and math.floor(where.y) == y then entity.die() end
      elseif entity.unit_number then
        pumps = pumps or {}
        pumps[entity.unit_number] = entity
      end
    end
  end

  if pumps then
    for _, pump in pairs(pumps) do
      if pump.valid then
        -- This is the least certain call in the mod, so a failure is logged instead of fatal.
        local ok, message = pcall(refresh_pump, pump)
        if not ok and not pump_warning_logged then
          pump_warning_logged = true
          log("[creative-pollution] could not retarget an offshore pump after its water changed: " .. tostring(message))
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Ledgers
--------------------------------------------------------------------------------

-- Moves `cost` from pending to load. Returns false, changing nothing, if there is not enough.
local function pay(outfall, cost)
  if total(outfall.pending) < cost then return false end
  local remaining = cost
  for pollutant, amount in pairs(outfall.pending) do
    local take = math.min(amount, remaining)
    local left = amount - take
    outfall.pending[pollutant] = left > 0.000001 and left or nil
    outfall.load[pollutant] = (outfall.load[pollutant] or 0) + take
    remaining = remaining - take
    if remaining <= 0 then break end
  end
  return true
end

-- Outfalls whose slick may overlap what `cleaner` can reach.
local function polluters_near(cleaner)
  local result = {}
  for _, outfall in pairs(storage.outfalls) do
    if outfall.surface_index == cleaner.surface_index and (outfall.reach > 0 or next(outfall.load)) then
      local dx, dy = outfall.x - cleaner.x, outfall.y - cleaner.y
      local limit = outfall.reach + cleaner.clean.radius + T.margin
      if dx * dx + dy * dy <= limit * limit then result[#result + 1] = outfall end
    end
  end
  return result
end

-- Treating tiles removes that much pollutant from the ledgers of the outfalls that put it there.
local function settle_ledgers(cleaner, amount)
  local polluters = polluters_near(cleaner)
  local sum = 0
  for _, outfall in ipairs(polluters) do sum = sum + total(outfall.load) end
  if sum <= 0 then return end
  local keep = math.max(0, 1 - amount / sum)
  for _, outfall in ipairs(polluters) do
    for pollutant, load in pairs(outfall.load) do
      local left = load * keep
      outfall.load[pollutant] = left > 0.5 and left or nil
    end
  end
end

-- Called when `cleaner` finds no tainted water at all. An idle outfall starts over with empty
-- ledgers if its slick must be gone: either it stands on the water body that was searched in
-- full (`member` is the searched water, `whole_body` says it was all of it), or its whole reach
-- lay inside the searched radius.
local function reset_ledgers(cleaner, member, whole_body)
  for _, outfall in ipairs(polluters_near(cleaner)) do
    local origin = outfall.origin
    local same_water = whole_body and origin and member[key(origin.x, origin.y)]
    local dx, dy = outfall.x - cleaner.x, outfall.y - cleaner.y
    local covered = math.sqrt(dx * dx + dy * dy) + outfall.reach <= cleaner.clean.radius
    if (same_water or covered) and not outfall.group_active then
      outfall.load = {}
      outfall.reach = 0
    end
  end
end

--------------------------------------------------------------------------------
-- One update of one outfall
--------------------------------------------------------------------------------

-- Empties the outfall's tank into its ledgers.
local function drain(outfall, tick, settings_now, m)
  local entity = outfall.entity
  local chlorine_cap = settings_now.chlorine_per_tile / STEPS * T.max_tiles_per_update
  outfall.sees_chlorine = false

  for index = 1, entity.fluids_count do
    local fluid = entity.get_fluid(index)
    if fluid and fluid.amount > 0 then
      if fluid.name == CHLORINE then
        -- Chlorine is left in the pipe while it cannot be used, so none is wasted.
        outfall.sees_chlorine = true
        local room = chlorine_cap - outfall.chlorine
        if not outfall.blocked and room > 0 then
          local removed = entity.remove_fluid(index, math.min(fluid.amount, room))
          if removed then outfall.chlorine = outfall.chlorine + removed.amount end
        end
      else
        local removed = entity.remove_fluid(index, fluid.amount)
        local spec = m.fluids[fluid.name]
        if spec and removed and removed.amount > 0 then
          outfall.pending[spec.pollutant] = (outfall.pending[spec.pollutant] or 0) + removed.amount * spec.potency
          outfall.last_dump_tick = tick
          if settings_now.air_pollution > 0 then
            entity.surface.pollute(entity.position, removed.amount * spec.dilution * settings_now.air_pollution / 1000)
          end
        end
      end
    end
  end
end

local function taint_step(outfall, tick, settings_now, m, surface)
  local target = outfall.target
  local cost = settings_now.units_per_tile / STEPS
  local paid = total(outfall.pending) >= cost
  -- With pollutant to spend, any water that does not show the target yet is a target.
  -- Without, only the steps that cost nothing are: blending fully tainted water.
  local tag = (paid and "taint|" or "repaint|") .. target.signature
  local need = needs(m, target)
  local names = paid and need.any or need.free

  local result = refill(outfall, outfall.taint, tag, names, settings_now, tick, surface, m, not paid)
  if result ~= "ok" then
    if not paid then
      outfall.repaint = false
      set_status(outfall, nil)
    elseif result == "exhausted" or result == "wait" then
      -- Nowhere left for it to go: the rest is dumped without effect.
      outfall.pending = {}
      set_status(outfall, "saturated", "yellow")
    elseif result == "no-origin" then
      set_status(outfall, "no-water", "red")
    end
    return
  end

  -- Every tile in the queue takes one step. The queue is only searched again once it is used
  -- up, so no tile takes a second step before every other tile has had its first.
  local queue, qi, count = outfall.queue, outfall.qi, 0
  local reach = outfall.reach
  local tiles = {}
  while qi <= #queue and count < T.max_tiles_per_update do
    local x, y = unkey(queue[qi])
    local info = m.info[surface.get_tile(x, y).name]
    local tint, costs
    if info then tint, costs = next_taint(info, target) end
    local name = tint and m.tile_for[info.clean][tint]
    if name then
      if costs and not pay(outfall, cost) then
        -- out of pollutant: wait for more, unless only free steps were wanted anyway
        if paid then break end
      else
        count = count + 1
        tiles[count] = {name = name, position = {x, y}}
        local dx, dy = x + 0.5 - outfall.x, y + 0.5 - outfall.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > reach then reach = distance end
      end
    end
    qi = qi + 1
  end
  outfall.qi, outfall.reach = qi, reach

  if count > 0 then apply_tiles(surface, tiles, true) end
  if paid then set_status(outfall, "dumping", "green") end
end

local function clean_step(outfall, tick, settings_now, m, surface)
  if outfall.blocked then
    set_status(outfall, "blocked", "red")
    return
  end
  local cost = settings_now.chlorine_per_tile / STEPS
  if outfall.chlorine < cost then
    set_status(outfall, "treating", "green")
    return
  end

  local result, member, whole_body = refill(outfall, outfall.clean, "clean", m.tainted, settings_now, tick, surface, m, false)
  if result ~= "ok" then
    if result == "exhausted" then
      reset_ledgers(outfall, member, whole_body)
      set_status(outfall, "nothing-to-treat", "yellow")
    elseif result == "wait" then
      set_status(outfall, "nothing-to-treat", "yellow")
    elseif result == "no-origin" then
      set_status(outfall, "no-water", "red")
    end
    return
  end

  -- Like tainting, every tile in the queue takes one step: one level weaker, or a blend
  -- settling on its larger pollutant.
  local queue, qi, count, levels = outfall.queue, outfall.qi, 0, 0
  local tiles = {}
  while qi <= #queue and count < T.max_tiles_per_update and outfall.chlorine >= cost do
    local x, y = unkey(queue[qi])
    local info = m.info[surface.get_tile(x, y).name]
    local tint, removes
    if info then tint, removes = next_clean(info) end
    local name = tint and m.tile_for[info.clean][tint]
    if name then
      count = count + 1
      tiles[count] = {name = name, position = {x, y}}
      outfall.chlorine = outfall.chlorine - cost
      if removes then levels = levels + 1 end
    end
    qi = qi + 1
  end
  outfall.qi = qi

  if count > 0 then
    apply_tiles(surface, tiles, false)
    settle_ledgers(outfall, levels * settings_now.units_per_tile / STEPS)
  end
  set_status(outfall, "treating", "green")
end

local function act(outfall, tick, settings_now, m)
  local surface = outfall.entity.surface
  if not outfall.origin then
    outfall.origin = find_origin(outfall, surface, m)
    if not outfall.origin then
      outfall.pending = {}
      set_status(outfall, "no-water", "red")
      return
    end
  end

  if outfall.target and (outfall.repaint or total(outfall.pending) >= settings_now.units_per_tile / STEPS) then
    taint_step(outfall, tick, settings_now, m, surface)
  elseif outfall.sees_chlorine or outfall.chlorine >= settings_now.chlorine_per_tile / STEPS then
    clean_step(outfall, tick, settings_now, m, surface)
  elseif outfall.last_dump_tick and tick - outfall.last_dump_tick <= T.update_interval * 2 then
    set_status(outfall, "dumping", "green")
  else
    set_status(outfall, nil)
  end
end

--------------------------------------------------------------------------------
-- Groups: which pollutant wins, and where chlorine is blocked
--------------------------------------------------------------------------------

local function assign_groups(tick, settings_now, m)
  local polluters, count = {}, 0
  for _, outfall in pairs(storage.outfalls) do
    if outfall.reach > 0 or next(outfall.load) or next(outfall.pending) then
      count = count + 1
      polluters[count] = outfall
    else
      outfall.target, outfall.repaint, outfall.group_active = nil, false, false
    end
  end

  -- Union-find: two polluters share a group when their slicks could touch.
  local parent = {}
  for index = 1, count do parent[index] = index end
  local function find(index)
    while parent[index] ~= index do
      parent[index] = parent[parent[index]]
      index = parent[index]
    end
    return index
  end
  for i = 1, count - 1 do
    local a = polluters[i]
    for j = i + 1, count do
      local b = polluters[j]
      if a.surface_index == b.surface_index then
        local dx, dy = a.x - b.x, a.y - b.y
        local limit = a.reach + b.reach + T.margin
        if dx * dx + dy * dy <= limit * limit then
          local root_a, root_b = find(i), find(j)
          if root_a ~= root_b then parent[root_b] = root_a end
        end
      end
    end
  end

  local totals, active = {}, {}
  for index = 1, count do
    local outfall, root = polluters[index], find(index)
    local sums = totals[root]
    if not sums then
      sums = {}
      totals[root] = sums
    end
    for pollutant, amount in pairs(outfall.load) do sums[pollutant] = (sums[pollutant] or 0) + amount end
    for pollutant, amount in pairs(outfall.pending) do sums[pollutant] = (sums[pollutant] or 0) + amount end
    if outfall.last_dump_tick and tick - outfall.last_dump_tick <= settings_now.taint_ticks then active[root] = true end
  end

  -- Each group heads for a blend of its two biggest pollutants, in proportion to how much of
  -- each it has dumped, rounded to the nearest step.
  local targets = {}
  for index = 1, count do
    local outfall, root = polluters[index], find(index)
    local target = targets[root]
    if target == nil then
      local sums = totals[root]
      local first, second
      for _, pollutant in ipairs(m.order) do
        local amount = sums[pollutant]
        if amount and amount > 0 then
          if not first or amount > sums[first] then
            first, second = pollutant, first
          elseif not second or amount > sums[second] then
            second = pollutant
          end
        end
      end
      target = false
      if first then
        local dominant = m.index[first]
        local share = second and math.floor(STEPS * sums[second] / (sums[first] + sums[second]) + 0.5) or 0
        if share == 0 then
          target = {a = dominant, k = 0, dominant = dominant, signature = tostring(dominant)}
        else
          local other = m.index[second]
          local a, b = math.min(dominant, other), math.max(dominant, other)
          local k = b == other and share or STEPS - share
          target = {a = a, b = b, k = k, dominant = dominant, signature = a .. ":" .. b .. ":" .. k}
        end
      end
      targets[root] = target
    end
    local signature = target and target.signature
    if signature ~= (outfall.target and outfall.target.signature) then
      outfall.target = target or nil
      outfall.repaint = target and true or false
    end
    outfall.group_active = active[root] or false
  end

  -- Chlorine does nothing within reach of a slick that is still being fed.
  for _, outfall in pairs(storage.outfalls) do
    local blocked = false
    for index = 1, count do
      local polluter = polluters[index]
      if polluter.group_active and polluter.surface_index == outfall.surface_index then
        local dx, dy = polluter.x - outfall.x, polluter.y - outfall.y
        local limit = polluter.reach + outfall.clean.radius + T.margin
        if dx * dx + dy * dy <= limit * limit then
          blocked = true
          break
        end
      end
    end
    outfall.blocked = blocked
  end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function update(event)
  local outfalls = storage.outfalls
  if not outfalls or not next(outfalls) then return end
  local m = get_maps()
  local settings_now = read_settings()
  local tick = event.tick

  for unit_number, outfall in pairs(outfalls) do
    if not outfall.entity.valid then outfalls[unit_number] = nil end
  end

  -- Groups come first so that an outfall knows whether chlorine is blocked before it takes any.
  -- A pollutant dumped this update therefore starts spreading on the next one.
  assign_groups(tick, settings_now, m)

  for _, outfall in pairs(outfalls) do
    drain(outfall, tick, settings_now, m)
    act(outfall, tick, settings_now, m)
  end
end

script.on_nth_tick(T.update_interval, update)

script.on_init(register_all)

-- Up to 0.1.1 tiles were placed without tile correction, so the coast around them has no
-- shoreline. Placing the same tiles again with correction draws it. Only the water an outfall can
-- have reached is touched.
local function redraw_shorelines(m)
  local max_radius = settings.global["cp-max-slick-radius"].value + T.margin
  for _, outfall in pairs(storage.outfalls) do
    local entity = outfall.entity
    if entity.valid then
      local found = entity.surface.find_tiles_filtered({position = entity.position, radius = max_radius, name = m.waterish})
      local tiles = {}
      for index = 1, #found do tiles[index] = {name = found[index].name, position = found[index].position} end
      if #tiles > 0 then entity.surface.set_tiles(tiles, true, false, false, false) end
    end
  end
end

script.on_configuration_changed(function(data)
  register_all()
  -- Tile and fluid names may have changed with the mod set: drop anything derived from them.
  local m = get_maps()
  local change = data.mod_changes and data.mod_changes[script.mod_name]
  if change and change.old_version and helpers.compare_versions(change.old_version, "0.1.2") < 0 then
    redraw_shorelines(m)
  end
  for _, outfall in pairs(storage.outfalls) do
    outfall.queue, outfall.queue_tag, outfall.origin = nil, nil, nil
    outfall.taint, outfall.clean = new_search(), new_search()
    for _, ledger in pairs({outfall.pending, outfall.load}) do
      for pollutant in pairs(ledger) do
        if not m.index[pollutant] then ledger[pollutant] = nil end
      end
    end
    -- worked out again on the next update; `paint` is what saves before 0.1.2 kept instead
    outfall.target, outfall.repaint, outfall.paint = nil, false, nil
  end
end)

script.on_event(
  {
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.on_space_platform_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
    defines.events.on_entity_cloned
  },
  function(event)
    register(event.entity or event.destination)
  end
)

script.on_event(defines.events.on_player_rotated_entity, function(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == OUTFALL) then return end
  local outfall = storage.outfalls and storage.outfalls[entity.unit_number]
  if outfall then outfall.origin, outfall.queue, outfall.queue_tag = nil, nil, nil end
end)

commands.add_command("cp-status", {"cp-command.status-help"}, function(command)
  local player = command.player_index and game.get_player(command.player_index)
  if not player then return end
  local outfalls = storage.outfalls or {}
  local selected = player.selected
  local outfall = selected and selected.valid and selected.unit_number and outfalls[selected.unit_number]
  if not outfall then
    player.print({"cp-command.status-count", table_size(outfalls)})
    return
  end
  player.print(serpent.line(
  {
    status = outfall.status,
    target = outfall.target and outfall.target.signature,
    pending = outfall.pending,
    load = outfall.load,
    chlorine = outfall.chlorine,
    reach = outfall.reach,
    taint_radius = outfall.taint.radius,
    clean_radius = outfall.clean.radius,
    queued = outfall.queue and (#outfall.queue - outfall.qi + 1) or 0,
    group_active = outfall.group_active,
    blocked = outfall.blocked
  }))
end)
