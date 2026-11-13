local Pollutants = require('pollutants')

-- shared by the data stage (prototypes) and the control stage (runtime); everything worth tuning lives here or in the mod settings
local Config = {
	tainted = "cp-tainted",
	technologies = {
		effluent_dumping = "cp-effluent-dumping",
		water_treatment = "cp-water-treatment",
	},
	pollutants = Pollutants.ordered,
	by_fluid = Pollutants.lookup,
	tainted_water_potency = 0.1, -- pumping tainted water into clean water spreads the taint too, but it is diluted
	taint_steps = 8, -- tints between clean and fully tainted water, and between two pollutants in a blend; every step is one tile prototype per water tile, so keep it small
	tuning = {
		update_interval = 30, -- ticks between updates of every outfall
		outfall_volume = 2000, -- fluid an outfall holds; also the most it can dump per update
		start_radius = 6, -- tiles; where an outfall starts looking for water to taint or treat
		radius_step = 4, -- tiles the search grows by when everything in reach is done
		max_tiles_per_update = 120, -- tint steps one outfall may make per update (a tile takes one step at a time)
		rescan_backoff = 600, -- ticks to wait before looking again once nothing is left to do
		margin = 4, -- tiles of slack when deciding whether two slicks touch
		pump_search_radius = 2, -- tiles around a changed tile to look for offshore pumps
		kill_fish = true, -- a flag to indicate if fish can die from water pollution
	},
}

function Config.tainted_fluid(pollutant) return "cp-tainted-water-"..pollutant end

---The name of the clean water `tile` tainted by one `pollutant` at a `level` of strength (1 to `taint_steps`).
---Fully tainted tiles (no level, or the top level) keep the plain name so older saves still load them.
function Config.tainted_tile(pollutant, tile, level)
	if not level or level >= Config.taint_steps then return "cp-"..pollutant.."-"..tile end
	return "cp-"..pollutant.."-"..tile.."-"..level
end

---The name of the clean water `tile` fully tainted by a blend of two pollutants, `share` steps (1 to `taint_steps` - 1) of it being `second`.
function Config.blended_tile(first, second, share, tile) return "cp-"..first.."-and-"..second.."-"..share.."-"..tile end

return Config
