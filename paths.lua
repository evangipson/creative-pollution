local path_prefix = "__base__/graphics/"
local icons_path_prefix = path_prefix.."icons/"
local technology_path_prefix = path_prefix.."technology/"
local fluid_icons_path_prefix = icons_path_prefix.."fluid/"
local mod_path_prefix = "__creative-pollution__/graphics/"
local mod_icons_path_prefix = mod_path_prefix.."icons/"
local mod_entity_path_prefix = mod_path_prefix.."entity/"

return {
    ---Paths to the physical image assets for icons.
    icons = {
        sodium = mod_icons_path_prefix.."cp-sodium.png",
        chlorine = mod_icons_path_prefix.."cp-chlorine.png",
        outfall = mod_icons_path_prefix.."cp-outfall.png",
        water = fluid_icons_path_prefix.."water.png",
        fluid_handling = technology_path_prefix.."fluid-handling.png",
        sulfur_processing = technology_path_prefix.."sulfur-processing.png",
    },
    ---Folders holding each entity's sprites.
    entities = {
        outfall = mod_entity_path_prefix.."outfall/",
    },
}