local Config = require('config')
local Game = require('game')
local Palette = require('palette')
local Paths = require('paths')
local Order = require('order')

-- vanilla boilers and recipes are filtered to "water", so they reject it automatically.
local function add_tainted_fluid(index, pollutant)
  	if not data.raw.fluid[pollutant.fluid] then return end
	data:extend({{
		type = Game.types.fluid,
		name = Config.tainted_fluid(pollutant.fluid),
		localised_name = {Game.types.fluid.."-name."..Config.tainted.."-"..Game.fluids.water, {Game.types.fluid.."-name."..pollutant.fluid}},
		localised_description = {Game.types.fluid.."-description."..Config.tainted.."-"..Game.fluids.water},
		subgroup = Game.types.fluid,
		order = Order.new():with("a", Game.types.fluid):with("a", Game.fluids.water):with("c", Config.tainted):to_string().."-"..index,
		icons = {{icon = Paths.icons.water, icon_size = 64, tint = Palette.get_rgba(Palette.brighten(pollutant.water_color, 0.25))}},
		default_temperature = 15,
		max_temperature = pollutant.max_temperature,
		heat_capacity = pollutant.heat_capacity,
		base_color = Palette.get_rgba(pollutant.water_color),
		flow_color = Palette.get_rgba(Palette.brighten(pollutant.water_color, 0.3)),
		auto_barrel = false,
	}})
end

-- one "tainted" water fluid per pollutant; this is what an offshore pump draws from tainted tiles
for k, v in ipairs(Config.pollutants) do add_tainted_fluid(k, v) end

-- add the fluid information for chlorine
data:extend({{
    type = Game.types.fluid,
    name = Game.fluids.chlorine.name,
    subgroup = Game.types.fluid,
    order = Order.new():with("a", Game.types.fluid):with("a", Game.fluids.water):with("d", Game.fluids.chlorine.name):to_string(),
    icons = {{icon = Paths.icons.chlorine, icon_size = Game.fluids.chlorine.icon_size}},
    default_temperature = Game.fluids.chlorine.temperature,
    base_color = Palette.get_rgba(Palette.fluids.chlorine.polluted_water),
    flow_color = Palette.get_rgba(Palette.fluids.chlorine.polluted_shoreline),
    auto_barrel = false,
}})