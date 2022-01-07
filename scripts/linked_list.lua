-- This class is a singly linked list with just the necessary features to operate as a queue.
local Linked_List = {
    size = 0
}
Linked_List.__index = Linked_List

function Linked_List:new()
    local o = {}
    setmetatable(o, self)
    return o
end

function Linked_List:add_last(o)
    local node = {
        element = o
    }
    if self.last then
        self.last.next = node
    else
        -- The list is empty.
        self.first = node
    end
    self.last = node
    self.size = self.size + 1
end

function Linked_List:pop_first()
    if self.first then
        local node = self.first
        self.first = self.first.next
        if not self.first then
            self.last = nil
        end
        self.size = self.size - 1
        return node.element
    else
        -- The list is empty.
        return nil
    end
end

function Linked_List:to_array()
    local array = {}
    local node = self.first
    while node do
        table.insert(array, node.element)
        node = node.next
    end
    return array
end

return Linked_List
