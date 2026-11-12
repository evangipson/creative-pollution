local config = require("config")

-- Ground tiles list by name which water tiles they draw a shoreline against, and deep water
-- lists which tiles may sit next to it. Add every tainted tile wherever its clean original is
-- listed. This runs last so tiles added by other mods are covered as well.

local clones_of = {}  -- clean tile name -> names of its tainted variants
local all_clones = {}
for name, tile in pairs(data.raw.tile) do
  if tile.fluid == "water" then
    local clones = {}
    for _, pollutant in ipairs(config.pollutants) do
      local clone = config.tainted_tile(pollutant.fluid, name)
      if data.raw.tile[clone] then
        clones[#clones + 1] = clone
        all_clones[#all_clones + 1] = clone
      end
    end
    clones_of[name] = clones
  end
end

-- Many tiles share one list table, so each table is only patched once.
local patched = {}

local function add_missing(list, names, present)
  for _, name in ipairs(names) do
    if not present[name] then
      list[#list + 1] = name
      present[name] = true
    end
  end
end

local function patch(list, everything)
  if type(list) ~= "table" or patched[list] then return end
  patched[list] = true
  local present = {}
  for _, name in ipairs(list) do present[name] = true end
  if everything then
    add_missing(list, all_clones, present)
    return
  end
  for index = 1, #list do
    local clones = clones_of[list[index]]
    if clones then add_missing(list, clones, present) end
  end
end

for _, tile in pairs(data.raw.tile) do
  if tile.transitions then
    for _, transition in pairs(tile.transitions) do
      patch(transition.to_tiles, false)
    end
  end
  -- Clean water tiles with a neighbour restriction (deep water) must tolerate any tainted tile.
  if tile.allowed_neighbors and clones_of[tile.name] then
    patch(tile.allowed_neighbors, true)
  end
end
