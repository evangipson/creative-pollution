local Game = require('game')
local Palette = require('palette')

-- definition of all pollutants for the creative pollution mod
local pollutants = {
    {fluid = Game.fluids.crude_oil, potency = 1.5, flow = 0.5, heat_capacity = "1.4kJ", max_temperature = 130},
    {fluid = Game.fluids.heavy_oil, potency = 1.25, flow = 0.6, heat_capacity = "1.5kJ", max_temperature = 125},
    {fluid = Game.fluids.light_oil, potency = 1, flow = 0.8, heat_capacity = "1.6kJ", max_temperature = 115},
    {fluid = Game.fluids.lubricant, potency = 1, flow = 0.7, heat_capacity = "1.5kJ", max_temperature = 120},
    {fluid = Game.fluids.sulfuric_acid, potency = 2, flow = 1.2, heat_capacity = "1.8kJ", max_temperature = 105},
}

-- augment each pollutant with the appropriate palette before using them and create a "by-fluid" lookup
local pollutants_by_fluid = {}
for _, pollutant in ipairs(pollutants) do
	local palette = assert(Palette.fluids[pollutant.fluid], "\""..pollutant.fluid.."\" color palette not found, verify it exists in palette.lua.")
	pollutant.water_color = palette.polluted_water
	pollutant.map_color = palette.polluted_water_map
	pollutant.foam_color = palette.polluted_shoreline
    pollutants_by_fluid[pollutant.fluid] = pollutant
end

---A collection of fluids that taint water when they are dumped through an outfall.
return {
    ---An ordered list of all pollutants for the creative pollution mod.
    ordered = pollutants,
    ---A collection of fluid name keys and pollutant values for the creative pollution mod.
    lookup = pollutants_by_fluid,
}