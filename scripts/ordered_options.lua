-- This class wraps the basic option functionality with additional features. Options are normally sorted alphabetically, but this class internally prefixes the option names so that they appear sorted in the order in which they are registered. As long as all options are registered and accessed through this class, the caller does not have to keep track of the prefixes.
local Ordered_Options = {
    initial_values = {},
    option_index = 0,
    options = {}
}
Ordered_Options.__index = Ordered_Options

-- initial_values: A table of option names mapped to their initial values. Any option registered with a nil initial value argument will look for a value in initial_values. If an option still can't find an initial value, then it will use a default value that depends on the data type of the option.
function Ordered_Options:new(initial_values)
    local o = {}
    setmetatable(o, self)

    self.initial_values = initial_values or {}

    return o
end

function Ordered_Options:register_option_int(raw_name, desc, long_desc, min_value, max_value, initial_value, save)
    local ordered_name = self:_add_name(raw_name, save)
    if initial_value == nil then
        initial_value = self.initial_values[raw_name]
        if initial_value == nil then
            initial_value = min_value
        end
    end
    register_option_int(ordered_name, desc, long_desc, initial_value, min_value, max_value)
end

function Ordered_Options:register_option_float(raw_name, desc, long_desc, min_value, max_value, initial_value, save)
    local ordered_name = self:_add_name(raw_name, save)
    if initial_value == nil then
        initial_value = self.initial_values[raw_name]
        if initial_value == nil then
            initial_value = min_value
        end
    end
    register_option_float(ordered_name, desc, long_desc, initial_value, min_value, max_value)
end

function Ordered_Options:register_option_bool(raw_name, desc, long_desc, initial_value, save)
    local ordered_name = self:_add_name(raw_name, save)
    if initial_value == nil then
        initial_value = self.initial_values[raw_name]
        if initial_value == nil then
            initial_value = false
        end
    end
    register_option_bool(ordered_name, desc, long_desc, initial_value)
end

function Ordered_Options:register_option_string(raw_name, desc, long_desc, initial_value, save)
    local ordered_name = self:_add_name(raw_name, save)
    if initial_value == nil then
        initial_value = self.initial_values[raw_name]
        if initial_value == nil then
            initial_value = ""
        end
    end
    register_option_string(ordered_name, desc, long_desc, initial_value)
end

-- In addition to being an ordered option, this version of register_option_combo also lets you provide an ordered collection of choices and specify the initial choice. The value returned when getting this option is the key of the current choice.
function Ordered_Options:register_option_combo(raw_name, desc, long_desc, choices, choice_order, initial_choice_key, save)
    local ordered_name = self:_add_name(raw_name, save)
    if initial_choice_key == nil then
        initial_choice_key = self.initial_values[raw_name]
        if initial_choice_key == nil then
            initial_choice_key = choice_order[1]
        end
    end
    if not choices[initial_choice_key] then
        -- The specified initial choice is not valid. Use the first choice as the initial choice instead.
        print(F"Warning: Option combo \"{raw_name}\" has invalid initial choice: {initial_choice_key}")
        initial_choice_key = choice_order[1]
    end
    -- The initial choice needs to be first in the list because register_option_combo always defaults to the first choice. I tried setting the combo option to a different value programmatically after registering it, but the options UI wouldn't update to reflect the new value.
    local choice_keys = { initial_choice_key }
    local choice_display_names = { choices[initial_choice_key].display_name }
    -- Add the rest of the choices.
    for i, choice_key in ipairs(choice_order) do
        if choice_key ~= initial_choice_key then
            local choice_data = choices[choice_key]
            if choice_data then
                table.insert(choice_keys, choice_key)
                table.insert(choice_display_names, choice_data.display_name)
            end
        end
    end
    local choices_string = table.concat(choice_display_names, "\0").."\0\0"
    register_option_combo(ordered_name, desc, long_desc, choices_string)
    local getter = function()
        return choice_keys[options[ordered_name]]
    end
    self:_set_getter(raw_name, getter)
end

function Ordered_Options:register_option_button(raw_name, desc, long_desc, on_click)
    local ordered_name = self:_add_name(raw_name, false)
    register_option_button(ordered_name, desc, long_desc, on_click)
end

function Ordered_Options:to_table()
    local option_table = {}
    for raw_name, ordered_option in pairs(self.options) do
        if ordered_option.save then
            option_table[raw_name] = self:get_value(raw_name)
        end
    end
    return option_table
end

function Ordered_Options:get_value(raw_name)
    local ordered_option = self.options[raw_name]
    if ordered_option then
        if ordered_option.getter then
            return ordered_option.getter()
        else
            return options[ordered_option.ordered_name]
        end
    else
        return nil
    end
end

function Ordered_Options:_add_name(raw_name, save)
    if save == nil then
        save = true
    end
    -- With this prefix, there is technically a limit of 10,000 options before the sorting breaks.
    local ordered_name = string.format("%04i_%s", self.option_index, raw_name)
    self.options[raw_name] = {
        ordered_name = ordered_name,
        save = save
    }
    self.option_index = self.option_index + 1
    return ordered_name
end

function Ordered_Options:_set_getter(raw_name, getter)
    local ordered_option = self.options[raw_name]
    if ordered_option then
        ordered_option.getter = getter
    end
end

return Ordered_Options
