local Game = require('game')

---A collection of color palettes used in the creative pollution mod.
local Palette = {}

-- a list of keys for quad colors
local quad_keys = {"primary", "secondary", "tertiary", "quaternary"}

-- a completely transparent RGBA color
local transparent_rgba = {r = 0, g = 0, b = 0, a = 0}

-- a list of colors to create the palette from
local colors = {
    chocolate = {0.35, 0.16, 0.05},
    dark_chocolate = {0.30, 0.14, 0.05},
    tobacco = {0.55, 0.35, 0.20},
    oak = {0.60, 0.45, 0.08},
    sepia = {0.45, 0.35, 0.08},
    tan = {0.85, 0.75, 0.40},
    forest_green = {0.10, 0.38, 0.10},
    dark_emerald = {0.10, 0.30, 0.10},
    moss_green = {0.45, 0.70, 0.40},
    yellow_green = {0.62, 0.66, 0.10},
    olive_drab = {0.50, 0.55, 0.10},
    chartreuse = {0.90, 0.95, 0.45},
    ink = {0.05, 0.05, 0.06},
    lead = {0.07, 0.07, 0.08},
    dark_lava = {0.25, 0.22, 0.20},
    lavender = {0.85, 0.88, 0.95},
    pale_blue = {0.70, 0.75, 0.85},
    platinum = {0.90, 0.90, 0.90},
    cadet_blue = {0.80, 0.85, 0.95},
    pear = {0.70, 0.85, 0.20},
    green_yellow = {0.80, 1.00, 0.35},
    champagne = {0.85, 0.90, 0.60},
    citron = {0.75, 1.00, 0.10},
    taupe = {0.80, 0.62, 0.45},
    khaki = {0.90, 1.00, 0.60},
}

---A collection of fluid color palettes.
Palette.fluids = {
    [Game.fluids.crude_oil] = {polluted_water = colors.ink, polluted_water_map = colors.lead, polluted_shoreline = colors.dark_lava},
    [Game.fluids.heavy_oil] = {polluted_water = colors.chocolate, polluted_water_map = colors.dark_chocolate, polluted_shoreline = colors.tobacco},
    [Game.fluids.light_oil] = {polluted_water = colors.oak, polluted_water_map = colors.sepia, polluted_shoreline = colors.tan},
    [Game.fluids.lubricant] = {polluted_water = colors.forest_green, polluted_water_map = colors.dark_emerald, polluted_shoreline = colors.moss_green},
    [Game.fluids.sulfuric_acid] = {polluted_water = colors.yellow_green, polluted_water_map = colors.olive_drab, polluted_shoreline = colors.chartreuse},
    chlorine = {polluted_water = colors.pear, polluted_shoreline = colors.khaki},
}

---A collection of tint color palettes.
Palette.tints = {
    ---The color palette for sodium tints.
    sodium = {
        processing = {colors.lavender, colors.pale_blue, colors.platinum, colors.cadet_blue},
    },
    ---The color palette for chlorine tints.
    chlorine = {
        processing = {colors.pear, colors.green_yellow, colors.champagne, colors.citron},
    },
    effluent_dumping = {icon = colors.platinum},
    water_treatment = {icon = colors.platinum},
}

---Gets `color` in the shape of `{r, g, b, a}`.
---@param color table The color to get the rgba shape of.
---@return table # The color in RGB shape, defaults to a fully transparent RGBA color (`{r = 0, g = 0, b = 0, a = 0}`).
function Palette.get_rgba(color)
    if not color then return transparent_rgba end
    local r, g, b, a = color.r or color[1] or 0, color.g or color[2] or 0, color.b or color[3] or 0, color.a or color[4]
    if r > 1 or g > 1 or b > 1 or (a and a > 1) then r, g, b = r / 255, g / 255, b / 255 if a then a = a / 255 end end
    return {r = r, g = g, b = b, a = a or 1}
end

---Gets a color quad in the shape of `{primary, secondary, tertiary, quaternary}` for `colors_list`.
---@param colors_list table A collection of at least 4 colors.
---@return table # The color quad from `colors_list`.
function Palette.get_quad(colors_list)
    local quad = {}
    for index, key in ipairs(quad_keys) do quad[key] = Palette.get_rgba(colors_list[index]) end
    return quad
end

---Brightens a `color` by an `amount`.
---@param color table The color to brighten.
---@param amount number The amount to brighten `color` by (0.0 - 1.0).
---@return table # The brightened `color`.
function Palette.brighten(color, amount)
    local brightened_color = {}
    for _, channel in ipairs(color) do table.insert(brightened_color, math.max(0.0, math.min(1.0, channel + amount))) end
    return brightened_color
end

---Gets the "peak" of the color (i.e.: the value of the most intense color channel)
---@param color table The color to get the peak of.
---@return number # The value of the most intense color channel.
function Palette.get_peak(color) return math.max(color.r, color.g, color.b) end

---Gives `target` the brightness and alpha that `original` has relative to the plain water tile, so deep water stays darker and shallow water stays translucent.
---@param original table The original color to recolor from.
---@param target table The target color to recolor toward.
---@param reference_peak number The highest any recolored channel can be.
---@param lowest number The lowest factor of the recolor.
---@param highest number The highest factor of the recolor.
---@return table # The `original` color recolored toward its `target`.
function Palette.recolor(original, target, reference_peak, lowest, highest)
	local base = Palette.get_rgba(original)
	local factor = base and (Palette.get_peak(base) / reference_peak) or 1
	factor = math.min(highest, math.max(lowest, factor))
	return {r = target[1] * factor, g = target[2] * factor, b = target[3] * factor, a = base and base.a or 1}
end

return Palette