-- This module contains utility functions for managing player loadouts, such as setting equipped items and mounts. All function arguments requesting an entity will accept either an entity ID or an entity object.

local module = {}

local function to_entity_id(ent)
    if ent == nil or type(ent) == "number" then
        return ent
    else
        return ent.uid
    end
end

local function to_entity_object(ent)
    if type(ent) == "number" then
        return get_entity(ent)
    else
        return ent
    end
end

function module.set_held_item(player, held_item_ent_type)
    player = to_entity_object(player)

    -- Check the player's current held item and drop it if necessary.
    local held_item_id = player.holding_uid
    if held_item_id >= 0 and get_entity(held_item_id).type.id ~= held_item_ent_type then
        -- The player should not be holding this item.
        drop(player.uid, held_item_id)
        -- The falling item could cause injuries, so safely place it below the player.
        module.move_entity_to_bottom_of_entity(held_item_id, player, true)
        held_item_id = -1
    end

    if held_item_id < 0 and held_item_ent_type then
        -- Spawn a new held item for the player.
        local x, y, layer = get_position(player.uid)
        pick_up(player.uid, spawn_entity(held_item_ent_type, x, y, layer, 0, 0))
    end
end

function module.set_back_item(player, back_item_ent_type)
    player = to_entity_object(player)

    -- Check the player's current back item and unequip it if necessary.
    local back_item_id = player:worn_backitem()
    if back_item_id >= 0 and get_entity(back_item_id).type.id ~= back_item_ent_type then
        -- The player should not be wearing this back item.
        player:unequip_backitem()
        -- The falling item could cause injuries, so safely place it below the player.
        module.move_entity_to_bottom_of_entity(back_item_id, player, true)
        back_item_id = -1
    end

    if back_item_id < 0 and back_item_ent_type then
        -- Spawn a new back item for the player. Picking up the back item equips it immediately and does not seem to interfere with held items. This can allow a player to wear a different back item than the one being held, but this is an edge case that doesn't appear to cause any problems.
        local x, y, layer = get_position(player.uid)
        pick_up(player.uid, spawn_entity(back_item_ent_type, x, y, layer, 0, 0))
    end
end

function module.set_mount(player, mount_ent_type)
    player = to_entity_object(player)

    -- Check the player's current mount and dismount them if necessary.
    local riding_mount = module.get_mount(player)
    if riding_mount and riding_mount.type.id ~= mount_ent_type then
        -- The player should not be riding this mount.
        entity_remove_item(riding_mount.uid, player.uid)
        module.move_entity_to_bottom_of_entity(player, riding_mount, false)
        riding_mount = nil
    end

    if not riding_mount and mount_ent_type then
        -- Spawn a new mount for the player.
        local x, y, layer = get_position(player.uid)
        local mount_id = spawn_entity_snapped_to_floor(mount_ent_type, x, y, layer)
        local mount = get_entity(mount_id)
        mount.tamed = true
        if test_flag(player.flags, ENT_FLAG.FACING_LEFT) then
            flip_entity(mount_id)
        end
        carry(mount_id, player.uid)
    end
end

function module.get_mount(rider)
    rider = to_entity_object(rider)
    local mount = rider.overlay
    -- Check that the overlay is actually the rider's mount. The overlay variable is used for other entity relationships too.
    if mount and test_flag(mount.type.search_flags, MASK.MOUNT) and mount.rider_uid == rider.uid then
        return mount
    else
        return nil
    end
end

function module.set_powerup(player, powerup_ent_type, should_have_powerup)
    player = to_entity_object(player)

    if should_have_powerup then
        if not player:has_powerup(powerup_ent_type) then
            player:give_powerup(powerup_ent_type)
        end
    else
        if player:has_powerup(powerup_ent_type) then
            player:remove_powerup(powerup_ent_type)
        end
    end
end

-- Moves an entity so that its bottom is aligned with the target entity's bottom and its origin is horizontally aligned with the target entity's origin. This means that if the target is resting on a solid floor, then this will place the entity on that floor without it falling or clipping. If handle_mount is true and the target is riding a mount, then the entity is aligned with the bottom of the mount instead.
function module.move_entity_to_bottom_of_entity(entity, target, handle_mount)
    entity = to_entity_object(entity)
    local target_id = to_entity_id(target)

    if handle_mount then
        -- This is safe even if the target can't ride a mount, since no mount will exist with it as the rider.
        local mount = module.get_mount(target_id)
        if mount then
            target_id = mount.uid
        end
    end
    local target_x, target_y, target_layer = get_position(target_id)
    local target_offset_y = target_y - get_hitbox(target_id).bottom
    local _, entity_y = get_position(entity.uid)
    local entity_offset_y = entity_y - get_hitbox(entity.uid).bottom
    target_y = target_y - target_offset_y + entity_offset_y
    move_entity(entity.uid, target_x, target_y, 0, 0)
    entity:set_layer(target_layer)
end

-- Moves an entity so that its bottom is aligned to the target Y and its origin is horizontally aligned with the target X. This means that if the target is the top of a solid floor, then this will place the entity on that floor without it falling or clipping.
function module.move_entity_bottom_to_position(entity, target_x, target_y)
    entity = to_entity_object(entity)

    local _, entity_y = get_position(entity.uid)
    local entity_offset_y = entity_y - get_hitbox(entity.uid).bottom
    target_y = target_y + entity_offset_y
    move_entity(entity.uid, target_x, target_y, 0, 0)
end

return module
