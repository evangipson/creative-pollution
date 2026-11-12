local Config = require('config')
local Game = require('game')
local Order = require('order')
local Palette = require('palette')
local Paths = require('paths')
local Technology = require('technology')

data:extend({
  -- add sodium raw material
  {
    type = Game.types.item,
    name = Game.raw_materials.sodium.name,
    icons = {{icon = Paths.icons.sodium, icon_size = 64}},
    subgroup = Game.categories.raw_material,
    order = Order.new():with("b", Game.categories.chemistry):with("d", Game.raw_materials.sodium.name):to_string(), -- "b[chemistry]-d[cp-sodium]"
    stack_size = 50,
  },
  -- add sodium recipe
  {
    type = Game.types.recipe,
    name = Game.raw_materials.sodium.name,
    categories = {Game.categories.chemistry},
    energy_required = 2,
    enabled = false,
    ingredients = {Game.with_amount(Game.types.fluid, Game.fluids.water, 50), Game.with_amount(Game.types.fluid, Game.fluids.steam, 50)},
    results = {Game.single(Game.types.item, Game.raw_materials.sodium.name)},
    crafting_machine_tint = Palette.get_quad(Palette.tints.sodium.processing),
  },
  -- add chlorine recipe
  {
    type = Game.types.recipe,
    name = Game.fluids.chlorine.name,
    categories = {Game.categories.chemistry},
    subgroup = Game.categories.fluid_recipes,
    order = Order.new():with("c", Game.categories.oil_products):with("c", Game.fluids.chlorine.name):to_string(), -- "c[oil-products]-c[cp-chlorine]"
    energy_required = 1,
    enabled = false,
    ingredients = {Game.with_amount(Game.types.item, Game.raw_materials.sodium.name, 5), Game.with_amount(Game.types.fluid, Game.fluids.water, 50)},
    results = {Game.with_amount(Game.types.fluid, Game.fluids.chlorine.name, 50)},
    crafting_machine_tint = Palette.get_quad(Palette.tints.chlorine.processing),
  },
  -- add efflucent dumping technology node
  {
    type = Game.categories.technology,
    name = Config.technologies.effluent_dumping,
    icons = {{icon = Paths.icons.outfall, icon_size = Game.buildings.outfall_pump.icon_size, tint = Palette.get_rgba(Palette.tints.water_treatment.icon)}},
    prerequisites = {Technology.nodes.fluid_handling},
    effects = {{type = Technology.types.unlock_recipe, recipe = Game.buildings.outfall_pump.name}},
    unit = {count = 50, ingredients = {{Game.sciences.red, 1}, {Game.sciences.green, 1}}, time = 15},
  },
  -- add water treatment technology node
  {
    type = Game.categories.technology,
    name = Config.technologies.water_treatment,
    icons = {{icon = Paths.icons.sodium, icon_size = Game.raw_materials.sodium.icon_size, tint = Palette.get_rgba(Palette.tints.effluent_dumping.icon)}},
    prerequisites = {Config.technologies.effluent_dumping, Technology.nodes.oil_processing},
    effects = {{type = Technology.types.unlock_recipe, recipe = Game.raw_materials.sodium.name}, {type = Technology.types.unlock_recipe, recipe = Game.fluids.chlorine.name}},
    unit = {count = 100, ingredients = {{Game.sciences.red, 1}, {Game.sciences.green, 1}}, time = 30},
  },
})
