local Config = require('config')

---------------------------
-- Every tainted version of one clean water tile. Shared by the data stage, which creates them,
-- and the control stage, which steps the water through them, so both always agree on the names.
--
--   * each pollutant at every strength from 1 to `taint_steps`; the top strength is fully tainted
--   * at full strength, every blend of two pollutants in steps of 1 / `taint_steps`
--
-- A variant is {name, a, b, k, level}: `a` and `b` index `Config.pollutants` (a < b, `b` only in
-- blends), `k` is how many steps of a blend are `b` (0 for a single pollutant), and `level` is the
-- strength (always the top one in a blend).
---------------------------

local Variants = {}

---All tainted variants of the clean water tile `source`, whether or not their fluids exist in the game.
---@param source string The name of a clean water tile.
---@return table # A list of variants.
function Variants.for_source(source)
	local steps = Config.taint_steps
	local pollutants = Config.pollutants
	local list = {}
	for a, pollutant in ipairs(pollutants) do
		for level = 1, steps do
			list[#list + 1] = {name = Config.tainted_tile(pollutant.fluid, source, level), a = a, k = 0, level = level}
		end
	end
	for a = 1, #pollutants - 1 do
		for b = a + 1, #pollutants do
			for k = 1, steps - 1 do
				list[#list + 1] = {name = Config.blended_tile(pollutants[a].fluid, pollutants[b].fluid, k, source), a = a, b = b, k = k, level = steps}
			end
		end
	end
	return list
end

---The pollutant (index into `Config.pollutants`) whose tainted water a variant yields: its only one, or the larger share of a blend.
---@param variant table A variant from `Variants.for_source`.
---@return number # The index of the dominant pollutant.
function Variants.dominant(variant)
	if variant.b and variant.k > Config.taint_steps / 2 then return variant.b end
	return variant.a
end

return Variants
