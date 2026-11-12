data:extend({
  {type = "int-setting", name = "cp-units-per-tile", setting_type = "runtime-global", default_value = 200, minimum_value = 1, maximum_value = 100000, order = "a"},
  {type = "int-setting", name = "cp-chlorine-per-tile", setting_type = "runtime-global", default_value = 100, minimum_value = 1, maximum_value = 100000, order = "b"},
  {type = "int-setting", name = "cp-taint-seconds", setting_type = "runtime-global", default_value = 30, minimum_value = 1, maximum_value = 3600, order = "c"},
  {type = "int-setting", name = "cp-max-slick-radius", setting_type = "runtime-global", default_value = 64, minimum_value = 8, maximum_value = 256, order = "d"},
  {type = "double-setting", name = "cp-air-pollution", setting_type = "runtime-global", default_value = 5, minimum_value = 0, maximum_value = 1000, order = "e"},
})