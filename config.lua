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
	tuning = {
		update_interval = 30, -- ticks between updates of every outfall
		outfall_volume = 2000, -- fluid an outfall holds; also the most it can dump per update
		start_radius = 6, -- tiles; where an outfall starts looking for water to taint or treat
		radius_step = 4, -- tiles the search grows by when everything in reach is done
		max_tiles_per_update = 60, -- tiles one outfall may change per update
		rescan_backoff = 600, -- ticks to wait before looking again once nothing is left to do
		margin = 4, -- tiles of slack when deciding whether two slicks touch
		pump_search_radius = 2, -- tiles around a changed tile to look for offshore pumps
		kill_fish = true, -- a flag to indicate if fish can die from water pollution
	},
}

function Config.tainted_fluid(pollutant) return "cp-tainted-water-"..pollutant end

function Config.tainted_tile(pollutant, tile) return "cp-"..pollutant.."-"..tile end

return Config
