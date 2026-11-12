local Config = require('config')
local Game = require('game')
local Paths = require('paths')
local Order = require('order')

-----------------------------
-- The outfall is a small storage tank that must be built on a shoreline, exactly like an offshore pump.
-- The control script empties it into the water.
-- It borrows the offshore pump's placement rules, sounds and remnants; the sprites are its own.
-----------------------------

-- Each sprite covers 3x3 tiles centred on the entity; each shadow covers 4x3 tiles and reaches one tile further east, the way shadows fall in the base game.
local function get_outfall_pump_image(direction)
	return {
		layers = {
			{filename = Paths.entities.outfall.."outfall-"..direction ..".png",  priority = "high", width = 192, height = 192, scale = 0.5},
			{filename = Paths.entities.outfall.."outfall-"..direction .."-shadow.png", priority = "high", width = 256, height = 192, shift = {0.5, 0}, scale = 0.5, draw_as_shadow = true},
		},
	}
end

-- reference to live game data for the offshore pump (which much of the outfall pump is based on)
local offshore_pump_data = data.raw["offshore-pump"]["offshore-pump"]

data:extend({
	-- add outfall pipe behavior
	{
		type = Game.types.storage_tank,
		name = Game.buildings.outfall_pump.name,
		icons = {{icon = Paths.icons.outfall, icon_size = Game.buildings.outfall_pump.icon_size}},
		flags = table.deepcopy(offshore_pump_data.flags),
		collision_mask = table.deepcopy(offshore_pump_data.collision_mask),
		tile_buildability_rules = table.deepcopy(offshore_pump_data.tile_buildability_rules),
		collision_box = table.deepcopy(offshore_pump_data.collision_box),
		selection_box = table.deepcopy(offshore_pump_data.selection_box),
		tile_width = Game.buildings.outfall_pump.tile_size,
		tile_height = Game.buildings.outfall_pump.tile_size,
		minable = {mining_time = Game.buildings.outfall_pump.mining_time, result = Game.buildings.outfall_pump.name},
		max_health = Game.buildings.outfall_pump.max_health,
		corpse = offshore_pump_data.corpse,
		dying_explosion = offshore_pump_data.dying_explosion,
		resistances = table.deepcopy(offshore_pump_data.resistances),
		damaged_trigger_effect = table.deepcopy(offshore_pump_data.damaged_trigger_effect),
		fluid_box = {volume = Config.tuning.outfall_volume, pipe_covers = table.deepcopy(offshore_pump_data.fluid_box.pipe_covers), pipe_connections = {{position = {0, 0}, direction = defines.direction.south}}},
		two_direction_only = false,
		window_bounding_box = Game.buildings.outfall_pump.bounds,
		flow_length_in_ticks = Game.buildings.outfall_pump.flow_ticks,
		pictures = {picture = {north = get_outfall_pump_image("north"), east = get_outfall_pump_image("east"), south = get_outfall_pump_image("south"), west = get_outfall_pump_image("west")}},
		impact_category = offshore_pump_data.impact_category,
		open_sound = table.deepcopy(offshore_pump_data.open_sound),
		close_sound = table.deepcopy(offshore_pump_data.close_sound),
		placeable_position_visualization = table.deepcopy(offshore_pump_data.placeable_position_visualization),
	},
	-- add outfall pipe item
	{
		type = Game.types.item,
		name = Game.buildings.outfall_pump.name,
		icons = {{icon = Paths.icons.outfall, icon_size = Game.buildings.outfall_pump.icon_size}},
		subgroup = Game.categories.extraction_machine,
		order = Order.new():with("b", Game.types.fluid.."s"):with("a", Game.buildings.offshore_pump):with("b", Game.buildings.outfall_pump.name):to_string(), -- "b[fluids]-a[offshore-pump]-b[cp-outfall]"
		place_result = Game.buildings.outfall_pump.name,
		stack_size = Game.buildings.outfall_pump.stack_size,
	},
	-- add outfall pipe recipe
	{
		type = Game.types.recipe,
		name = Game.buildings.outfall_pump.name,
		enabled = false,
		ingredients = {Game.with_amount(Game.types.item, Game.items.pipe, 5), Game.with_amount(Game.types.item, Game.items.iron_gear, 2)},
		results = {Game.single(Game.types.item, Game.buildings.outfall_pump.name)},
	},
})
