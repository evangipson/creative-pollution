local Order = {}
Order.__index = Order

function Order.new()
    local self = setmetatable({}, Order)
    self._current = {}
    return self
end

function Order:with(key, string)
    table.insert(self._current, key.."["..string.."]")
    return self
end

function Order:to_string() return table.concat(self._current, "-") end

return Order