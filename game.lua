local function get_item_with_amount(type, name, amount) return {type = type, name = name, amount = amount} end

---A collection of fluid values that are used throughout the creative pollution mod.
return {
    ---Gets a table representing an `amount` of items with `type` and `name`.
    with_amount = get_item_with_amount,
    ---Gets a table representing a single item of `type` and `name`.
    single = function(type, name) return get_item_with_amount(type, name, 1) end,
    ---A collection of widely-used category names.
    categories = {
        chemistry = "chemistry",
        raw_material = "raw-material",
        technology = "technology",
        oil_products = "oil-products",
        fluid_recipes = "fluid-recipes",
        extraction_machine = "extraction-machine",
    },
    ---A collection of widely-used fluid type names.
    types = {
        fluid = "fluid",
        item = "item",
        recipe = "recipe",
        storage_tank = "storage-tank",
    },
    ---A collection of widely-used raw material data.
    raw_materials = {
        ---Definition of static data for the "sodium" raw material introduced by this mod.
        sodium = {
            name = "cp-sodium",
            icon_size = 64,
        }
    },
    ---A collection of widely-used science item names.
    sciences = {
        red = "automation-science-pack",
        green = "logistic-science-pack",
    },
    ---A collection of widely-used fluid names.
    fluids = {
        crude_oil = "crude-oil",
        heavy_oil = "heavy-oil",
        light_oil = "light-oil",
        lubricant = "lubricant",
        sulfuric_acid = "sulfuric-acid",
        water = "water",
        steam = "steam",
        ---Definition of static data for the "chlorine" fluid introduced by this mod.
        chlorine = {
            name = "cp-chlorine",
            icon_size = 64,
            temperature = 15,
        },
    },
    ---A collection of widely-used item names.
    items = {
        pipe = "pipe",
        iron_gear = "iron-gear-wheel"
    },
    ---A collection of widely-used building data.
    buildings = {
        offshore_pump = "offshore_pump",
        ---Definition of static data for the "outfall pump" building introduced by this mod.
        outfall_pump = {
            name = "cp-outfall",
            icon_size = 64,
            tile_size = 1,
            bounds = {{-0.1, -0.1}, {0.1, 0.1}},
            max_health = 150,
            mining_time = 0.1,
            flow_ticks = 360,
            stack_size = 20,
        },
    }
}