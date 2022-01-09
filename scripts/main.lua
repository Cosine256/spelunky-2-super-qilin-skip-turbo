meta.name = "Super Qilin Skip Turbo"
meta.version = "1.0.0"
meta.description = "You can use Ctrl+F4 to change the mod options and access the buttons at any time in Playlunky. Most changes will take effect after reloading the level. Enter the big door in the camp or use the warp button to go straight to the Tiamat level. This mod is designed for the unmodded level layout and some features may not work if the level is modded."
meta.author = "Cosine"

local Linked_List = require "linked_list"
local loadout_utils = require "loadout_utils"
local Ordered_Options = require "ordered_options"

-- Note: The lasers are called "force fields" in the game, but I have decided to consistently refer to them as "lasers" in this script out of habit and for shorter variable names.
-- The number of frames in a laser period (one active and one inactive duration).
local LASER_PERIOD = 122
-- The number of frames that a laser has a damaging hitbox.
local LASER_ACTIVE_DURATION = 60
local LASER_HEIGHT = 0.5
local LASER_EDGE_LEFT = 2.5
local LASER_EDGE_RIGHT = 32.5
-- These are the expected positions of the horizontal laser emitters. It's important that they are ordered from bottom to top.
local LASER_POSITIONS = {
    { x = 33, y =  93},
    { x =  2, y =  97},
    { x = 33, y = 101},
    { x =  2, y = 105},
    { x = 33, y = 109},
    { x =  2, y = 113}
}

-- These constants refer to the 2x1 tile gap below the first laser.
local GAP_LEFT, GAP_RIGHT = 16.5, 18.5
local GAP_BOTTOM = 91.5
local GAP_CHECK_SLOPPY_THRESHOLD = 0.5

-- Note: I believe the game's physics engine uses single precision floats, but Lua numbers are double precision floats. This may affect some calculations, but mispredictions caused by this should be incredibly rare.
local BUBBLE_WIDTH, BUBBLE_HEIGHT = 0.6, 0.5
local BUBBLE_MAX_VEL_Y = get_type(ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM).max_speed
local BUBBLE_ACCEL_Y = get_type(ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM).acceleration
local BUBBLE_GAP_MIN_X = GAP_LEFT + (BUBBLE_WIDTH / 2)
local BUBBLE_GAP_MAX_X = GAP_RIGHT - (BUBBLE_WIDTH / 2)
-- The height of a bubble's interpolated hitbox with no rider. See laser safety code for an explanation of what an interpolated bubble hitbox is.
local BUBBLE_INTERP_HEIGHT_BASE = BUBBLE_HEIGHT + (BUBBLE_MAX_VEL_Y * (LASER_ACTIVE_DURATION - 1))
-- The distance a bubble at maximum vertical velocity will travel during one laser period.
local BUBBLE_LASER_PERIOD_DIST = BUBBLE_MAX_VEL_Y * LASER_PERIOD

local BUBBLE_RIDERS = {
    NONE = { display_name = "None", height = 0.0 },
    DUCKING_PLAYER = { display_name = "Ducking player", height = 0.55 },
    STANDING_PLAYER = { display_name = "Standing player", height = 0.7 },
    DUCKING_PLAYER_ON_TURKEY = { display_name = "Ducking player on turkey", height = 0.93 },
    DUCKING_PLAYER_ON_ROCK_DOG = { display_name = "Ducking player on rock dog", height = 0.93 },
    DUCKING_PLAYER_ON_AXOLOTL = { display_name = "Ducking player on axolotl", height = 0.83 },
    DUCKING_PLAYER_ON_QILIN = { display_name = "Ducking player on qilin", height = 0.93 },
}
local BUBBLE_RIDER_ORDER = {
    "NONE",
    "DUCKING_PLAYER",
    "STANDING_PLAYER",
    "DUCKING_PLAYER_ON_TURKEY",
    "DUCKING_PLAYER_ON_ROCK_DOG",
    "DUCKING_PLAYER_ON_AXOLOTL",
    "DUCKING_PLAYER_ON_QILIN"
}

-- Show interpolated hitboxes for bubbles which are at most this many tiles below their next laser.
local BUBBLE_INTERP_HITBOX_DRAW_THRESHOLD = 12

local ARTIFICIAL_BUBBLE_SPAWN_X = 17.5
local ARTIFICIAL_BUBBLE_SPAWN_Y = 78
local ARTIFICIAL_BUBBLE_SPAWN_DEVIATION_CLEAN = 1 - (BUBBLE_WIDTH / 2)
local ARTIFICIAL_BUBBLE_SPAWN_DEVIATION_SLOPPY = ARTIFICIAL_BUBBLE_SPAWN_DEVIATION_CLEAN + 1
local ARTIFICIAL_BUBBLE_SPAWN_ATTEMPTS = 5
local ARTIFICIAL_BUBBLE_CHECK_MIN_Y = 70
local ARTIFICIAL_BUBBLE_CHECK_MAX_Y = 91
-- The number of frames between artificial bubble spawn attempts.
local ARTIFICIAL_BUBBLE_DELAY_MIN = 60
local ARTIFICIAL_BUBBLE_DELAY_MAX = 120

local PIT_MIN_X, PIT_MIN_Y = 16, 51
local PIT_MAX_X, PIT_MAX_Y = 19, 52

local GROUND_HAZARD_MIN_X, GROUND_HAZARD_MIN_Y = 2, 50
local GROUND_HAZARD_MAX_X, GROUND_HAZARD_MAX_Y = 33, 64
local GROUND_HAZARD_HITBOX = AABB:new(GROUND_HAZARD_MIN_X, GROUND_HAZARD_MAX_Y, GROUND_HAZARD_MAX_X, GROUND_HAZARD_MIN_Y)
local GROUND_HAZARD_ENT_TYPES = {
    ENT_TYPE.ITEM_POT,
    ENT_TYPE.MONS_SKELETON
}

local SIDE_ROPE_POSITIONS = {
    { x = 16, y = 91 },
    { x = 19, y = 91 },
    { x = 16, y = 84 },
    { x = 19, y = 84 },
    { x = 16, y = 77 },
    { x = 19, y = 77 },
    { x = 16, y = 70 },
    { x = 19, y = 70 },
    { x = 16, y = 63 },
    { x = 19, y = 63 },
    { x = 16, y = 56 },
    { x = 19, y = 56 }
}

local ROPE_ANIM_FRAME_PROJECTILE = 156
local ROPE_ANIM_FRAME_HEAD = 157
local ROPE_ANIM_FRAMES_UNROLLING = { [193] = true, [194] = true, [195] = true, [196] = true }

local BAD_ROPE_BOXES = {
    { min_x = 17, min_y = 51, max_x = 18, max_y = 92 }, -- Below the gap
    { min_x = 0, min_y = 92, max_x = 35, max_y = 114 }, -- Horizontal laser area
    { min_x = 15, min_y = 114, max_x = 20, max_y = 118 } -- Vertical laser area
}

local START_PLATFORM_MIN_X = 20
local START_PLATFORM_MAX_X = 22
local START_PLATFORM_Y = 85
local START_PLATFORM_SPAWN_X = (START_PLATFORM_MIN_X + START_PLATFORM_MAX_X) / 2
local START_PLATFORM_SPAWN_Y = START_PLATFORM_Y + 0.5
local START_PLATFORM_FRAME_LEFT = 50
local START_PLATFORM_FRAME_MIDDLE = 51
local START_PLATFORM_FRAME_RIGHT = 52

-- The number of frames in the Tiamat cutscene.
local TIAMAT_CUTSCENE_DURATION = 379

local HITBOX_LINE_COLOR_ALPHA = 0.5
local HITBOX_FILL_COLOR_ALPHA = 0.125
-- This color is a shade of purple.
local LASER_HITBOX_LINE_UCOLOR = Color:new(0.75, 0.25, 1, HITBOX_LINE_COLOR_ALPHA):get_ucolor()
local LASER_HITBOX_FILL_UCOLOR = Color:new(0.75, 0.25, 1, HITBOX_FILL_COLOR_ALPHA):get_ucolor()

local BUBBLE_COLORS = {
    NORMAL = { display_name = "Normal", color = Color:new(1, 1, 1, 1) },
    RED = { display_name = "Red", color = Color:new(1, 0, 0, 1) },
    YELLOW = { display_name = "Yellow", color = Color:new(1, 1, 0, 1) },
    GREEN = { display_name = "Green", color = Color:new(0, 1, 0, 1) },
    CYAN = { display_name = "Cyan", color = Color:new(0, 1, 1, 1) },
    BLUE = { display_name = "Blue", color = Color:new(0, 0, 1, 1) },
    MAGENTA = { display_name = "Magenta", color = Color:new(1, 0, 1, 1) },
    BLACK = { display_name = "Black", color = Color:new(0, 0, 0, 1) },
    DARK = { display_name = "Dark", color = Color:new(0.25, 0.25, 0.25, 1) }
}
local BUBBLE_COLOR_ORDER = {
    "NORMAL",
    "RED",
    "YELLOW",
    "GREEN",
    "CYAN",
    "BLUE",
    "MAGENTA",
    "BLACK",
    "DARK"
}

local LASER_CHECKS = {
    ALL = { display_name = "All lasers" },
    FIRST = { display_name = "Only first laser" },
    NONE = { display_name = "None" }
}
local LASER_CHECK_ORDER = {
    "ALL", "FIRST", "NONE"
}

local BUBBLE_INTERP_HITBOX_CHOICES = {
    ALL = { display_name = "All bubbles" },
    LAST_TOUCHED = { display_name = "Last bubble touched" },
    NONE = { display_name = "None" }
}
local BUBBLE_INTERP_HITBOX_CHOICE_ORDER = {
    "ALL", "LAST_TOUCHED", "NONE"
}

local START_BACK_ITEMS = {
    CURRENT = { display_name = "Current" },
    NONE = { display_name = "None" },
    VLADS_CAPE = { display_name = "Vlad's cape", ent_type = ENT_TYPE.ITEM_VLADS_CAPE },
    CAPE = { display_name = "Cape", ent_type = ENT_TYPE.ITEM_CAPE },
    JETPACK = { display_name = "Jetpack", ent_type = ENT_TYPE.ITEM_JETPACK },
    HOVERPACK = { display_name = "Hoverpack", ent_type = ENT_TYPE.ITEM_HOVERPACK },
    TELEPACK = { display_name = "Telepack", ent_type = ENT_TYPE.ITEM_TELEPORTER_BACKPACK },
    POWERPACK = { display_name = "Powerpack", ent_type = ENT_TYPE.ITEM_POWERPACK }
}
local START_BACK_ITEM_ORDER = {
    "CURRENT",
    "NONE",
    "VLADS_CAPE",
    "CAPE",
    "JETPACK",
    "HOVERPACK",
    "TELEPACK",
    "POWERPACK"
}

local START_HELD_ITEMS = {
    CURRENT = { display_name = "Current" },
    NONE = { display_name = "None" },
    TELEPORTER = { display_name = "Teleporter", ent_type = ENT_TYPE.ITEM_TELEPORTER },
    SHOTGUN = { display_name = "Shotgun", ent_type = ENT_TYPE.ITEM_SHOTGUN },
    FREEZE_RAY = { display_name = "Freeze ray", ent_type = ENT_TYPE.ITEM_FREEZERAY },
    WEBGUN = { display_name = "Webgun", ent_type = ENT_TYPE.ITEM_WEBGUN },
    PLASMA_CANNON = { display_name = "Plasma cannon", ent_type = ENT_TYPE.ITEM_PLASMACANNON },
    SCEPTER = { display_name = "Scepter", ent_type = ENT_TYPE.ITEM_SCEPTER },
    CLONE_GUN = { display_name = "Clone gun", ent_type = ENT_TYPE.ITEM_CLONEGUN },
    MATTOCK = { display_name = "Mattock", ent_type = ENT_TYPE.ITEM_MATTOCK },
    LANDMINE = { display_name = "Landmine", ent_type = ENT_TYPE.ITEM_LANDMINE }
}
local START_HELD_ITEM_ORDER = {
    "CURRENT",
    "NONE",
    "TELEPORTER",
    "SHOTGUN",
    "FREEZE_RAY",
    "WEBGUN",
    "PLASMA_CANNON",
    "SCEPTER",
    "CLONE_GUN",
    "MATTOCK",
    "LANDMINE"
}

local START_MOUNTS = {
    CURRENT = { display_name = "Current" },
    NONE = { display_name = "None" },
    TURKEY = { display_name = "Turkey", ent_type = ENT_TYPE.MOUNT_TURKEY,
            bubble_rider_mount_override = BUBBLE_RIDERS.DUCKING_PLAYER_ON_TURKEY },
    ROCK_DOG = { display_name = "Rock dog", ent_type = ENT_TYPE.MOUNT_ROCKDOG,
            bubble_rider_mount_override = BUBBLE_RIDERS.DUCKING_PLAYER_ON_ROCK_DOG },
    AXOLOTL = { display_name = "Axolotl", ent_type = ENT_TYPE.MOUNT_AXOLOTL,
            bubble_rider_mount_override = BUBBLE_RIDERS.DUCKING_PLAYER_ON_AXOLOTL },
    QILIN = { display_name = "Qilin", ent_type = ENT_TYPE.MOUNT_QILIN,
            bubble_rider_mount_override = BUBBLE_RIDERS.DUCKING_PLAYER_ON_QILIN },
    MECH = { display_name = "Mech", ent_type = ENT_TYPE.MOUNT_MECH }
}
local START_MOUNT_ORDER = {
    "CURRENT",
    "NONE",
    "TURKEY",
    "ROCK_DOG",
    "AXOLOTL",
    "QILIN",
    "MECH"
}

local DEFAULT_OPTION_VALUES = {
    start_tiamat_level = true,
    start_near_lasers = true,
    skip_fade_in = true,
    skip_tiamat_cutscene = true,
    kill_tiamat = false,
    create_bubble_pit = false,
    remove_ground_hazards = true,
    create_side_ropes = true,
    artificial_bubbles_enabled = true,
    artificial_bubbles_fit_gap = false,
    start_health = -1,
    start_bombs = -1,
    start_ropes = -1,
    start_with_spring_shoes = false,
    start_with_climbing_gloves = false,
    start_with_paste = false,
    start_with_pitchers_mitt = false,
    start_with_parachute = false,
    start_with_true_crown = false,
    start_with_punish_ball = false,
    start_with_back_item = "CURRENT",
    start_with_held_item = "CURRENT",
    start_with_mount = "CURRENT",
    bubble_rider = "DUCKING_PLAYER",
    bubble_rider_mount_override = true,
    show_bubble_safety_colors = true,
    bubble_color_safe = "NORMAL",
    bubble_color_unsafe = "RED",
    laser_check = "ALL",
    show_bubble_interp_hitboxes = "LAST_TOUCHED",
    show_laser_hitboxes = true,
    precise_gap_check = true,
    bubble_processing_rate = 10
}

local ordered_options
local script_active = false
local bubble_queue
local bubble_table
local last_touched_bubbles
local artificial_bubble_delay
local laser_cache
local draw_callback_id

-- Merges two tables. If both tables contain the same key, then the value from table2 is used. A nil table is handled as though it were an empty table.
local function merge_tables(table1, table2)
    local merged_table = {}
    if table1 then
        for k, v in pairs(table1) do
            merged_table[k] = v
        end
    end
    if table2 then
        for k, v in pairs(table2) do
            merged_table[k] = v
        end
    end
    return merged_table
end

local function is_level_tiamat()
    return state.world == 6 and state.level == 4 and state.theme == THEME.TIAMAT
end

local function set_start_level_tiamat()
    state.world_start = 6
    state.level_start = 4
    state.theme_start = THEME.TIAMAT
end

local function set_next_level_tiamat()
    state.world_next = 6
    state.level_next = 4
    state.theme_next = THEME.TIAMAT
end

local function try_warp_and_start_at_tiamat()
    if state.screen == ON.LEVEL or state.screen == ON.CAMP then
        warp(6, 4, THEME.TIAMAT)
        set_start_level_tiamat()
    else
        -- Warps behave oddly when used outside of a level. Warping from the main menu will leave the main menu music playing on top of the level music. Other warps may do nothing or spawn the player already dead. Play it safe and only allow warping from within levels.
        print("The warp button can only be used from within the camp or a level.")
    end
end

-- Returns an array of living player entities. This is different from the "players" array, which also includes player corpses.
local function get_live_players()
    local live_players = {}
    for _, player in ipairs(players) do
        if player.health > 0 then
            table.insert(live_players, player)
        end
    end
    return live_players
end

local function start_with_powerup(option_name, powerup_ent_type)
    local should_have_powerup = ordered_options:get_value(option_name)
    for _, player in ipairs(get_live_players()) do
        loadout_utils.set_powerup(player, powerup_ent_type, should_have_powerup)
    end
end

-- The lasers are accessed very frequently. Cache them for better performance. The lasers are cached in the same order as they appear in LASER_POSITIONS. This caching behavior does not support lasers being removed from the level after they are cached.
local function build_laser_cache()
    laser_cache = {}
    for _, laser_pos in ipairs(LASER_POSITIONS) do
        local laser_id = get_grid_entity_at(laser_pos.x, laser_pos.y, LAYER.FRONT)
        local laser_ent = get_entity(laser_id)
        if laser_ent and laser_ent.type.id == ENT_TYPE.FLOOR_HORIZONTAL_FORCEFIELD then
            table.insert(laser_cache, {
                id = laser_id,
                x = laser_pos.x,
                y = laser_pos.y,
                bottom = laser_pos.y - (LASER_HEIGHT / 2),
                top = laser_pos.y + (LASER_HEIGHT / 2)
            })
        end
    end
end

local function get_bubble_rider_height()
    if ordered_options:get_value("bubble_rider_mount_override") then
        local start_mount = START_MOUNTS[ordered_options:get_value("start_with_mount")]
        if start_mount.bubble_rider_mount_override then
            return start_mount.bubble_rider_mount_override.height
        end
    end
    return BUBBLE_RIDERS[ordered_options:get_value("bubble_rider")].height
end

local function get_bubble_color(safe)
    if safe then
        return BUBBLE_COLORS[ordered_options:get_value("bubble_color_safe")].color
    else
        return BUBBLE_COLORS[ordered_options:get_value("bubble_color_unsafe")].color
    end
end

local function get_next_laser(bubble_id)
    local bubble_x, bubble_y = get_position(bubble_id)
    local bubble_bottom = bubble_y - (BUBBLE_HEIGHT / 2)
    -- Find the lowest laser that could intersect with this bubble.
    for _, laser in ipairs(laser_cache) do
        if laser.top >= bubble_bottom then
            return laser
        end
        if ordered_options:get_value("laser_check") == "FIRST" then
            -- Pretend that there aren't any more lasers above this bubble.
            break
        end
    end
    -- There are no lasers above this bubble.
    return nil
end

-- Gets the number of frames until the next time a laser's damage hitbox will activate. If the damage hitbox is currently active, then the number returned will be zero or negative and indicate how many frames ago it activated. The laser damage hitbox is active for 60 frames of its 122 frame period. Notably, the first frame of the laser's active state does not have a damage hitbox.
-- When is_on = true:
--     1 frame inactive (timer = 60)
--     60 frames active (timer = 59 to 0)
-- When is_on = false:
--     61 frames inactive (timer = 60 to 0)
local function get_frames_until_laser_activation(laser_id)
    local laser = get_entity(laser_id)
    if laser.is_on then
        if laser.timer == 60 then
            return 1
        else
            return laser.timer - 59
        end
    else
        return laser.timer + 2
    end
end

-- Simulates the movement of a bubble until it reaches its maximum upward velocity. No simulation will occur for a bubble which is already at maximum velocity. There are no checks for collision with solids or other hazards.
-- Returns: The Y position of the bubble at the end of the simulation, and the number of frames that were simulated.
local function simulate_bubble_to_stability(bubble_id)
    local _, pos_y = get_position(bubble_id)
    local _, start_vel_y = get_velocity(bubble_id)

    -- Compute the number of frames until the bubble either reaches maximum upward velocity, or is one frame from reaching it. It's fine if the simulation stops one frame away from maximum velocity because the bubble will be updated to maximum velocity on the next frame before it moves again.
    local frame_count = math.floor((BUBBLE_MAX_VEL_Y - start_vel_y) / BUBBLE_ACCEL_Y)
    -- Add the distance travelled by the bubble during those frames. This is like computing a definite integral of the linear function mapping time to velocity for an object under constant acceleration, but the graph is approximated by flat steps that are one frame wide and have their top-right corners aligned to the line.
    pos_y = pos_y + (frame_count * (start_vel_y + (BUBBLE_ACCEL_Y * (frame_count + 1) / 2)))

    return pos_y, frame_count
end

local function create_bubble_interp_draw_item(box, divider_y, color)
    local color_line = Color:new(color)
    color_line.a = HITBOX_LINE_COLOR_ALPHA
    local color_fill = Color:new(color)
    color_fill.a = HITBOX_FILL_COLOR_ALPHA
    local draw_item = {
        box = box,
        ucolor_line = color_line:get_ucolor(),
        ucolor_fill = color_fill:get_ucolor()
    }
    -- Only include the divider if it's inside the box.
    if divider_y and box.bottom < divider_y and divider_y < box.top then
        draw_item.line = {
            { x = box.left, y = divider_y },
            { x = box.right, y = divider_y }
        }
    end
    return draw_item
end

local function update_bubble_safety(bubble)
    -- Draw items are recalculated every time a bubble is processed.
    bubble.draw_items = nil

    local prev_safe = bubble.safe
    -- Nil means that it is currently unknown whether or not the bubble is safe.
    bubble.safe = nil

    local bubble_x, bubble_y = get_position(bubble.id)

    local precise_gap_check = ordered_options:get_value("precise_gap_check")
    if bubble.passes_gap == nil or bubble.precise_gap_check ~= precise_gap_check then
        --[[
        Calculate whether the bubble will pass through the horizontal gap.
        This check is a known source of mispredictions, even when using precise gap checks. The game engine has a nudging mechanic that can push a bubble horizontally into the gap if it grazes the corner of a gap tile. The rules for this nudging mechanic are not trivial. The distance that a bubble can be nudged depends on how deeply it collides with the tile on the frame of collision, and it isn't just a linear function based on how deep the collision is. It ranges from no nudging at all to being nudged by the distance it travels in half a frame.
        This code does not attempt to simulate the nudging mechnic, and instead assumes that the bubble will pop if any part of its hitbox touches a gap tile. The check deliberately favors false negatives for bubble safety: a bubble predicted to collide with the gap might get nudged into the gap and actually be safe, but a bubble predicted to pass the gap will never collide with it and be unsafe.
        ]]
        local min_x = BUBBLE_GAP_MIN_X
        local max_x = BUBBLE_GAP_MAX_X
        if not precise_gap_check then
            min_x = min_x - GAP_CHECK_SLOPPY_THRESHOLD
            max_x = max_x + GAP_CHECK_SLOPPY_THRESHOLD
        end
        bubble.passes_gap = min_x <= bubble_x and bubble_x <= max_x
        bubble.precise_gap_check = precise_gap_check
    end

    if not bubble.passes_gap then
        if bubble_y >= GAP_BOTTOM then
            -- The bubble was mispredicted to collide with the gap.
            bubble.passes_gap = true
        else
            -- The bubble misses the gap and is therefore not safe.
            bubble.safe = false
        end
    end

    if bubble.safe == nil then
        if ordered_options:get_value("laser_check") == "NONE" then
            -- Lasers are being ignored. Assume that this bubble is safe.
            bubble.safe = true
        else
            -- Get the lowest laser that could intersect with this bubble or its rider.
            local laser = get_next_laser(bubble.id)
            if not laser then
                -- There are no more lasers above this bubble.
                bubble.safe = true
            else
                --[[
                The following algorithm predicts whether the bubble or its rider will collide with the laser.
                The laser's "active timespan" is the timespan during which it has a damaging hitbox.
                The laser's "full timespan" is the combination of one active timespan and then one inactive timespan.
                The bubble's "interpolated hitbox" (shortened to "interp hitbox") is the union of all bubble and rider hitboxes that will exist for a specific active timespan. The interp hitbox's bottom is the bottom of the bubble's hitbox on the first frame that the laser is active. The interp hitbox's top is the top of the rider's hitbox on the last frame that the laser is active.
                There is one interp hitbox per full timespan. For each subsequent full timespan, the bubble will have floated a constant distance upward. The position of the bubble when the laser activates again is the bottom of the next interp hitbox. The next laser activation corresponds to another interp hitbox, and so on.
                This collection of interp hitboxes represents all space that the bubble and rider will ever occupy while the laser is active. If the N-th interp hitbox intersects with the laser hitbox, then it means that there is at least one frame of collision with the laser during its N-th active timespan, and the bubble is therefore unsafe.
                The gaps between the interp hitboxes represent the space that is only ever occupied by the bubble or rider while the laser is inactive. In order for a bubble to be safe, the laser hitbox has to fit entirely within one of these gaps. The laser will be inactive for the entire time that the bubble and rider's hitboxes are passing through that gap.
                The goal of this algorithm is to determine whether any of these interp hitboxes intersect with the laser.
                In order to calculate these interp hitboxes, the bubble's movement needs to be simulated. This simulation code assumes that the game engine runs these steps in the following order. I have not verified this assumption by looking at the actual game code, but testing indicates that this is sufficiently accurate.
                    1. Add the constant upward acceleration to the bubble's velocity.
                    2. Add the bubble's velocity to its position. Entities riding the bubble are using relative coordinates and therefore move at the same time.
                    3. Update the timer and is_on values for the lasers.
                    4. Handle bubble and rider collisions with active laser hitboxes. Hitbox boundaries are inclusive, meaning that edge or vertex overlap counts as a collision.
                    5. Run callbacks created by set_interval, which is where this simulation code is executed.
                ]]

                -- The bubble might not be moving at its maximum upward velocity if the player is actively manipulating it. The rest of this algorithm needs the bubble to be moving at maximum upward velocity, so simulate the bubble until it reaches that velocity. It's possible that the bubble will actually dip down into a laser below it, but this is a minor edge case that is not checked by this code. The bubble would pop within a few frames, so a safety misprediction would be visible for very little time.
                local bubble_sim_y, sim_frames = simulate_bubble_to_stability(bubble.id)
                -- Calculate how many frames it will be until the next laser activation. This value might be negative.
                local frames_until_laser_active = get_frames_until_laser_activation(laser.id) - sim_frames

                -- Calculate the first interp hitbox for the bubble.
                local bubble_rider_height = get_bubble_rider_height()
                local bubble_interp_bottom = bubble_sim_y + (BUBBLE_MAX_VEL_Y * frames_until_laser_active) - (BUBBLE_HEIGHT / 2)
                local bubble_interp_height = BUBBLE_INTERP_HEIGHT_BASE + bubble_rider_height

                -- Calculate the distance between the bottom of the bubble interp hitbox and the top of the laser hitbox. The lowest this distance can be is 0 due to how the next laser is chosen.
                local interp_bottom_to_laser_top_dist = laser.top - bubble_interp_bottom
                -- Jump to the highest interp hitbox that could intersect with the laser. This will be the highest interp hitbox whose bottom is less than or equal to the top of the laser hitbox.
                local last_bubble_interp_bottom = bubble_interp_bottom + (math.floor(interp_bottom_to_laser_top_dist / BUBBLE_LASER_PERIOD_DIST) * BUBBLE_LASER_PERIOD_DIST)

                -- The bubble is only safe if the last interp hitbox is fully below the active laser.
                bubble.safe = last_bubble_interp_bottom + bubble_interp_height < laser.bottom

                local show_bubble_interp_hitboxes = ordered_options:get_value("show_bubble_interp_hitboxes")
                if show_bubble_interp_hitboxes ~= "NONE" then
                    local draw_interp_hitbox = false
                    if show_bubble_interp_hitboxes == "ALL" then
                        draw_interp_hitbox = true
                    elseif show_bubble_interp_hitboxes == "LAST_TOUCHED" then
                        for _, last_touched_bubble_id in pairs(last_touched_bubbles) do
                            if bubble.id == last_touched_bubble_id then
                                draw_interp_hitbox = true
                                break
                            end
                        end
                    end
                    draw_interp_hitbox = draw_interp_hitbox and bubble_y > laser.y - BUBBLE_INTERP_HITBOX_DRAW_THRESHOLD

                    if draw_interp_hitbox then
                        bubble.draw_items = {}
                        local color = get_bubble_color(bubble.safe)
                        local bubble_bottom = bubble_y - (BUBBLE_HEIGHT / 2)
                        local box_left = bubble_x - (BUBBLE_WIDTH / 2)
                        local box_right = bubble_x + (BUBBLE_WIDTH / 2)

                        -- Calculate the distance between the top of the bubble interp hitbox and the top of the laser hitbox.
                        local interp_top_to_laser_top_dist = laser.top - bubble_interp_bottom - bubble_interp_height
                        -- Display the highest interp hitbox whose top is lower than the top of the laser hitbox.
                        local display_bubble_interp_bottom = bubble_interp_bottom + (math.floor(interp_top_to_laser_top_dist / BUBBLE_LASER_PERIOD_DIST) * BUBBLE_LASER_PERIOD_DIST)

                        local box_1_bottom = math.max(display_bubble_interp_bottom, bubble_bottom)
                        local box_1_top = display_bubble_interp_bottom + bubble_interp_height
                        if bubble_bottom <= box_1_top then
                            local box_1 = AABB:new(box_left, box_1_top, box_right, box_1_bottom)
                            local divider_1_y
                            if bubble_rider_height > 0 then
                                divider_1_y = box_1_top - bubble_rider_height
                            end
                            table.insert(bubble.draw_items, create_bubble_interp_draw_item(box_1, divider_1_y, color))
                        end

                        -- Also display the interp hitbox above that.
                        display_bubble_interp_bottom = display_bubble_interp_bottom + BUBBLE_LASER_PERIOD_DIST

                        local box_2_bottom = math.max(display_bubble_interp_bottom, bubble_bottom)
                        local box_2_top = display_bubble_interp_bottom + bubble_interp_height
                        local box_2 = AABB:new(box_left, box_2_top, box_right, box_2_bottom)
                        local divider_2_y
                        if bubble_rider_height > 0 then
                            divider_2_y = box_2_top - bubble_rider_height
                        end
                        table.insert(bubble.draw_items, create_bubble_interp_draw_item(box_2, divider_2_y, color))
                    end
                end
            end
        end
    end

    if bubble.safe == nil then
        -- The bubble's safety should be known at this point. Assume the bubble is unsafe if its safety is still unknown.
        bubble.safe = false
    end

    local show_bubble_safety_colors = ordered_options:get_value("show_bubble_safety_colors")
    if bubble.safe ~= prev_safe or bubble.show_bubble_safety_colors ~= show_bubble_safety_colors then
        -- Update the color of the bubble.
        bubble.show_bubble_safety_colors = show_bubble_safety_colors
        if show_bubble_safety_colors then
            get_entity(bubble.id).color = get_bubble_color(bubble.safe)
        else
            get_entity(bubble.id).color = BUBBLE_COLORS.NORMAL.color
        end
    end
end

local function try_spawn_artificial_bubble()
    local spawn_deviation
    if ordered_options:get_value("artificial_bubbles_fit_gap") then
        spawn_deviation = ARTIFICIAL_BUBBLE_SPAWN_DEVIATION_CLEAN
    else
        spawn_deviation = ARTIFICIAL_BUBBLE_SPAWN_DEVIATION_SLOPPY
    end
    -- Look for a spot to spawn an artificial bubble.
    for _ = 1, ARTIFICIAL_BUBBLE_SPAWN_ATTEMPTS do
        local spawn_x = ARTIFICIAL_BUBBLE_SPAWN_X + (((math.random() * 2) - 1) * spawn_deviation)
        -- Check that there are no nearby bubbles above or below this spawn point.
        local hitbox = AABB:new(spawn_x - (BUBBLE_WIDTH / 2), ARTIFICIAL_BUBBLE_CHECK_MAX_Y,
            spawn_x + (BUBBLE_WIDTH / 2), ARTIFICIAL_BUBBLE_CHECK_MIN_Y)
        if #get_entities_overlapping_hitbox(ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM, MASK.ANY, hitbox, LAYER.FRONT) == 0 then
            -- Spawn an artificial bubble.
            spawn_entity(ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM, spawn_x, ARTIFICIAL_BUBBLE_SPAWN_Y, LAYER.FRONT, 0, 0)
            break
        end
    end
end

local function on_draw_gui(draw_ctx)
    if not is_level_tiamat() or state.camera_layer ~= LAYER.FRONT or state.screen ~= ON.LEVEL then
        return
    end

    for _, bubble in pairs(bubble_table) do
        if bubble.draw_items then
            for _, item in ipairs(bubble.draw_items) do
                if item.box then
                    local x1, y1 = screen_position(item.box.left, item.box.bottom)
                    local x2, y2 = screen_position(item.box.right, item.box.top)
                    draw_ctx:draw_rect_filled(x1, y1, x2, y2, 0, item.ucolor_fill)
                    draw_ctx:draw_rect(x1, y1, x2, y2, 1, 0, item.ucolor_line)
                end
                if item.line then
                    local x1, y1 = screen_position(item.line[1].x, item.line[1].y)
                    local x2, y2 = screen_position(item.line[2].x, item.line[2].y)
                    draw_ctx:draw_line(x1, y1, x2, y2, 1, item.ucolor_line)
                end
            end
        end
    end

    if ordered_options:get_value("show_laser_hitboxes") then
        for _, laser in ipairs(laser_cache) do
            local x1, y1 = screen_position(LASER_EDGE_LEFT, laser.bottom)
            local x2, y2 = screen_position(LASER_EDGE_RIGHT, laser.top)
            draw_ctx:draw_rect_filled(x1, y1, x2, y2, 0, LASER_HITBOX_FILL_UCOLOR)
            draw_ctx:draw_rect(x1, y1, x2, y2, 1, 0, LASER_HITBOX_LINE_UCOLOR)
        end
    end
end

-- Activates all script functionality. Does nothing if the script is already active.
-- is_first_frame: Boolean for whether this is the first frame of the level.
local function activate_script(is_first_frame)
    if script_active then
        return
    end

    bubble_queue = Linked_List:new()
    bubble_table = {}
    last_touched_bubbles = {}
    artificial_bubble_delay = 0
    build_laser_cache()

    if is_first_frame then
        if ordered_options:get_value("start_near_lasers") then
            for x = START_PLATFORM_MIN_X, START_PLATFORM_MAX_X do
                if get_grid_entity_at(x, START_PLATFORM_Y, LAYER.FRONT) < 0 then
                    local tile_id = spawn_entity(ENT_TYPE.FLOORSTYLED_BABYLON, x, START_PLATFORM_Y, LAYER.FRONT, 0, 0)
                    local tile = get_entity(tile_id)
                    if x == START_PLATFORM_MIN_X then
                        tile.animation_frame = START_PLATFORM_FRAME_LEFT
                    elseif x == START_PLATFORM_MAX_X then
                        tile.animation_frame = START_PLATFORM_FRAME_RIGHT
                    else
                        tile.animation_frame = START_PLATFORM_FRAME_MIDDLE
                    end
                end
            end
            local snapped_camera = false
            for _, player in ipairs(get_live_players()) do
                local bottom_entity = player
                local mount = loadout_utils.get_mount(player)
                if mount then
                    bottom_entity = mount
                end
                loadout_utils.move_entity_bottom_to_position(bottom_entity, START_PLATFORM_SPAWN_X, START_PLATFORM_SPAWN_Y)
                if not snapped_camera then
                    -- The camera starts focused on the original spawn point. Snap it to the player immediately.
                    local x, y = get_position(player.uid)
                    state.camera.focus_x = x
                    state.camera.focus_y = y
                    state.camera.adjusted_focus_x = x
                    state.camera.adjusted_focus_y = y
                    snapped_camera = true
                end
            end
        end

        if ordered_options:get_value("skip_fade_in") and state.fadeout > 0 then
            -- I'm unsure why the variable to change is "fadeout" and not "fadein", but this seems to work.
            state.fadeout = 0
            state.fadevalue = 0
        end

        if ordered_options:get_value("skip_tiamat_cutscene") then
            -- This cutscene object only exists when the cutscene is active.
            if state.logic.tiamat_cutscene and state.logic.tiamat_cutscene.timer then
                state.logic.tiamat_cutscene.timer = TIAMAT_CUTSCENE_DURATION
                -- The cutscene only ends when the timer equals an exact value. If the timer is set any higher, then it will continue to increment and the cutscene will not end until after the timer variable overflows. This means that any future tweaks to this cutscene could cause it to get stuck until the player pauses and ends the level. Check the timer a bit later to detect whether this happened.
                set_global_timeout(function()
                    if state.logic.tiamat_cutscene and state.logic.tiamat_cutscene.timer
                            and state.logic.tiamat_cutscene.timer > TIAMAT_CUTSCENE_DURATION then
                        -- Warn the user and set the timer back to 0 so that the cutscene can finish normally.
                        print(F"Warning: Failed to skip cutscene. Consider disabling the Tiamat cutscene skip option and reporting this to the {meta.name} developers.")
                        state.logic.tiamat_cutscene.timer = 0
                    end
                end, 60)
            end
        end

        if ordered_options:get_value("kill_tiamat") then
            local tiamat_id = get_entities_by_type(ENT_TYPE.MONS_TIAMAT)[1]
            if tiamat_id then
                kill_entity(tiamat_id)
            end
        end

        if ordered_options:get_value("create_bubble_pit") then
            for x = PIT_MIN_X, PIT_MAX_X do
                for y = PIT_MIN_Y, PIT_MAX_Y do
                    tile_id = get_grid_entity_at(x, y, LAYER.FRONT)
                    if tile_id >= 0 and get_entity(tile_id).type.id == ENT_TYPE.FLOOR_GENERIC then
                        kill_entity(tile_id)
                    end
                end
            end
        end

        if ordered_options:get_value("remove_ground_hazards") then
            local hazard_ids = get_entities_overlapping_hitbox(GROUND_HAZARD_ENT_TYPES, MASK.ANY, GROUND_HAZARD_HITBOX, LAYER.FRONT)
            for _, hazard_id in ipairs(hazard_ids) do
                get_entity(hazard_id):destroy()
            end
        end

        if ordered_options:get_value("create_side_ropes") then
            local rope_texture
            if players[1] then
                rope_texture = players[1]:get_texture()
            else
                -- This is a really contrived edge case, but it's possible to reach this code with no player entities if a script activation occurs while no player corpses exist. Just use Ana's rope texture if this happens.
                rope_texture = TEXTURE.DATA_TEXTURES_CHAR_YELLOW_0
            end
            for _, rope_pos in ipairs(SIDE_ROPE_POSITIONS) do
                local rope_id = spawn_entity(ENT_TYPE.ITEM_ROPE, rope_pos.x, rope_pos.y, LAYER.FRONT, 0, 0)
                local rope_ent = get_entity(rope_id)
                rope_ent:set_texture(rope_texture)
                rope_ent.animation_frame = ROPE_ANIM_FRAME_PROJECTILE
            end
        end
    end

    local start_health = ordered_options:get_value("start_health")
    if start_health > 0 then
        for _, player in ipairs(get_live_players()) do
            player.health = start_health
        end
    end

    local start_bombs = ordered_options:get_value("start_bombs")
    if start_bombs >= 0 then
        for _, player in ipairs(get_live_players()) do
            player.inventory.bombs = start_bombs
        end
    end

    local start_ropes = ordered_options:get_value("start_ropes")
    if start_ropes >= 0 then
        for _, player in ipairs(get_live_players()) do
            player.inventory.ropes = start_ropes
        end
    end

    start_with_powerup("start_with_spring_shoes", ENT_TYPE.ITEM_POWERUP_SPRING_SHOES)
    start_with_powerup("start_with_climbing_gloves", ENT_TYPE.ITEM_POWERUP_CLIMBING_GLOVES)
    start_with_powerup("start_with_paste", ENT_TYPE.ITEM_POWERUP_PASTE)
    start_with_powerup("start_with_pitchers_mitt", ENT_TYPE.ITEM_POWERUP_PITCHERSMITT)
    start_with_powerup("start_with_parachute", ENT_TYPE.ITEM_POWERUP_PARACHUTE)
    start_with_powerup("start_with_true_crown", ENT_TYPE.ITEM_POWERUP_TRUECROWN)

    if ordered_options:get_value("start_with_punish_ball") then
        for _, player in ipairs(get_live_players()) do
            local ball_id = attach_ball_and_chain(player.uid, 0, 0)
            -- The falling ball could cause injuries, so safely place it below the player.
            loadout_utils.move_entity_to_bottom_of_entity(ball_id, player, true)
        end
    end

    local start_back_item = START_BACK_ITEMS[ordered_options:get_value("start_with_back_item")]
    if start_back_item ~= START_BACK_ITEMS.CURRENT then
        for _, player in ipairs(get_live_players()) do
            loadout_utils.set_back_item(player, start_back_item.ent_type)
        end
    end

    local start_held_item = START_HELD_ITEMS[ordered_options:get_value("start_with_held_item")]
    if start_held_item ~= START_HELD_ITEMS.CURRENT then
        for _, player in ipairs(get_live_players()) do
            loadout_utils.set_held_item(player, start_held_item.ent_type)
        end
    end

    local start_mount = START_MOUNTS[ordered_options:get_value("start_with_mount")]
    if start_mount ~= START_MOUNTS.CURRENT then
        for _, player in ipairs(get_live_players()) do
            loadout_utils.set_mount(player, start_mount.ent_type)
        end
    end

    -- Create a processing callback that runs on every frame.
    -- The callback is automatically cleared when the level is unloaded.
    set_interval(function()

        -- Handle artificial bubbles.
        if ordered_options:get_value("artificial_bubbles_enabled") then
            if artificial_bubble_delay > 0 then
                artificial_bubble_delay = artificial_bubble_delay - 1
            else
                try_spawn_artificial_bubble()
                artificial_bubble_delay = math.random(ARTIFICIAL_BUBBLE_DELAY_MIN, ARTIFICIAL_BUBBLE_DELAY_MAX)
            end
        end

        -- Update the last touched bubbles for each player.
        for _, player in ipairs(get_live_players()) do
            local riding_mount = loadout_utils.get_mount(player)
            local standing_on_id
            if riding_mount then
                standing_on_id = riding_mount.standing_on_uid
            else
                standing_on_id = player.standing_on_uid
            end
            if standing_on_id >= 0 and get_entity(standing_on_id).type.id == ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM then
                last_touched_bubbles[player.uid] = standing_on_id
            end
        end

        -- Check for new bubbles and add them to the processing queue.
        local bubble_ids = get_entities_by_type(ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM)
        for _, bubble_id in ipairs(bubble_ids) do
            if not bubble_table[bubble_id] then
                local bubble = {
                    id = bubble_id
                }
                bubble_queue:add_last(bubble)
                bubble_table[bubble_id] = bubble
            end
        end

        -- Process a limited number of bubbles per frame.
        for _ = 1, math.min(ordered_options:get_value("bubble_processing_rate"), bubble_queue.size) do
            local bubble = bubble_queue:pop_first()
            local bubble_ent = get_entity(bubble.id)
            if bubble_ent and bubble_ent.type.id == ENT_TYPE.ACTIVEFLOOR_BUBBLE_PLATFORM then
                -- Process this bubble and then add it to the end of the queue.
                update_bubble_safety(bubble)
                bubble_queue:add_last(bubble)
            else
                -- This bubble no longer exists.
                bubble_table[bubble.id] = nil
                for player_id, last_touched_bubble_id in pairs(last_touched_bubbles) do
                    if bubble.id == last_touched_bubble_id then
                        last_touched_bubbles[player_id] = nil
                    end
                end
            end
        end
    end, 1)

    -- Create a callback that will draw GUI elements on every graphical frame.
    draw_callback_id = set_callback(on_draw_gui, ON.GUIFRAME)

    script_active = true
end

-- Deactivates all script functionality by cleaning up variables and callbacks. Does nothing if the script is already inactive.
local function deactivate_script()
    if not script_active then
        return
    end

    bubble_queue = nil
    bubble_table = nil
    last_touched_bubbles = nil
    laser_cache = nil
    clear_callback(draw_callback_id)
    draw_callback_id = nil

    script_active = false
end

local function remove_bad_ropes()
    if not script_active or not is_level_tiamat() then
        return
    end

    -- Fragmented ropes are unstable and can crash the game, especially if their head is removed. It's essential that the full rope is removed, even if only part of the rope is in a bad region. Gather a set of rope heads that have at least one segment that needs to be removed.
    local remove_full_ropes = {}
    local rope_ids = get_entities_by_type(ENT_TYPE.ITEM_CLIMBABLE_ROPE)
    for _, rope_id in ipairs(rope_ids) do
        local rope_ent = get_entity(rope_id)
        -- Note: A rope head's top-most entity will be itself, so this still works for that case.
        local rope_head_id = rope_ent:topmost().uid
        -- Check that this full rope isn't already slated for removal.
        if not remove_full_ropes[rope_head_id] then
            local rope_x, rope_y = get_position(rope_id)
            for _, box in ipairs(BAD_ROPE_BOXES) do
                if box.min_x <= rope_x and rope_x <= box.max_x and box.min_y <= rope_y and rope_y <= box.max_y then
                    -- Set up a full rope for this head. The full rope's segments will be gathered and removed later.
                    remove_full_ropes[rope_head_id] = {}
                    break
                end
            end
        end
    end

    -- Iterate through all of the rope segments again and fill out the full ropes that are slated for removal. Segments can't be removed yet because doing so may change another segment's head value in the middle of the iteration.
    for _, rope_id in ipairs(rope_ids) do
        local rope_ent = get_entity(rope_id)
        local full_rope = remove_full_ropes[rope_ent:topmost().uid]
        if full_rope then
            -- This rope segment is part of a full rope that's slated for removal.
            table.insert(full_rope, rope_id)
        end
    end

    -- Iterate through the full ropes and remove all of their rope segments.
    for _, full_rope in pairs(remove_full_ropes) do
        -- Check whether this rope is unrolling. Removing unrolling ropes can cause the game to crash.
        local can_remove = true
        for _, rope_id in ipairs(full_rope) do
            local rope_ent = get_entity(rope_id)
            -- The first frame of an unrolling rope is a single-segment rope with the unterminated head animation frame.
            -- For longer unrolling ropes, one segment will have an unrolling animation frame.
            if (rope_ent.animation_frame == ROPE_ANIM_FRAME_HEAD and #full_rope == 1)
                    or ROPE_ANIM_FRAMES_UNROLLING[rope_ent.animation_frame] then
                -- This rope is unrolling and cannot be safely removed.
                can_remove = false
                break
            end
        end
        if can_remove then
            for _, rope_id in ipairs(full_rope) do
                get_entity(rope_id):destroy()
            end
        end
    end
end

local function register_options(initial_values)
    ordered_options = Ordered_Options:new(merge_tables(DEFAULT_OPTION_VALUES, initial_values))

    ordered_options:register_option_button("remove_bad_ropes",
        "Remove interfering ropes",
        "Remove all deployed ropes in the gap and in the laser area. Use this to clean up accidental or unwanted ropes.",
        function() remove_bad_ropes() end)

    ordered_options:register_option_button("warp_tiamat_level",
        "Warp to Tiamat level",
        "Warp to the Tiamat level and set it as the starting level for restarts. This can only be used from within the camp or a level.",
        function() try_warp_and_start_at_tiamat() end)

    ordered_options:register_option_bool("start_tiamat_level",
        "Start at Tiamat level",
        "When transitioning to 1-1, go to the Tiamat level instead and set it as the starting level for restarts.")

    ordered_options:register_option_bool("start_near_lasers",
        "Start near lasers",
        "Start the Tiamat level on a small platform near the lasers instead of one of the doors at the bottom.")

    ordered_options:register_option_bool("skip_fade_in",
        "Skip fade-in",
        "Skip the brief pause and fade-in when entering the Tiamat level.")

    ordered_options:register_option_bool("skip_tiamat_cutscene",
        "Skip Tiamat cutscene",
        "Skip the Tiamat cutscene at the start of the level.")

    ordered_options:register_option_bool("kill_tiamat",
        "Kill Tiamat",
        "Kill Tiamat at the start of the level.")

    ordered_options:register_option_bool("create_bubble_pit",
        "Create bubble pit",
        "Create a pit below Tiamat to spawn bubbles for the skip.")

    ordered_options:register_option_bool("remove_ground_hazards",
        "Remove ground hazards",
        "Remove pots and live skeletons around Tiamat.")

    ordered_options:register_option_bool("create_side_ropes",
        "Create side ropes",
        "Create ropes on both sides of the gap below the lasers to hang on while waiting for bubbles.")

    ordered_options:register_option_bool("artificial_bubbles_enabled",
        "Spawn artificial bubbles",
        "Spawn bubbles a short distance below the gap. Use this to avoid long waiting times between natural bubbles. The artificial bubbles will be spawned at slightly randomized times and positions, and they will avoid spawning directly above or below other nearby bubbles. Disable the \"Create bubble pit\" option if you want to only use artificial bubbles.")

    ordered_options:register_option_bool("artificial_bubbles_fit_gap",
        "Artificial bubbles always pass gap",
        "If enabled, then artificial bubbles always spawn in a position that will pass through the gap. If disabled, then they may spawn a little too far to the sides.")

    ordered_options:register_option_int("start_health",
        "Starting health",
        "Start with the specified amount of health. Set to -1 to keep health from previous level, or to use default health if restarting.",
        -1, 99)

    ordered_options:register_option_int("start_bombs",
        "Starting bombs",
        "Start with the specified number of bombs. Set to -1 to keep bombs from previous level, or to use default bombs if restarting.",
        -1, 99)

    ordered_options:register_option_int("start_ropes",
        "Starting ropes",
        "Start with the specified number of ropes. Set to -1 to keep ropes from previous level, or to use default ropes if restarting.",
        -1, 99)

    ordered_options:register_option_bool("start_with_spring_shoes",
        "Start with spring shoes", "")

    ordered_options:register_option_bool("start_with_climbing_gloves",
        "Start with climbing gloves", "")

    ordered_options:register_option_bool("start_with_paste",
        "Start with paste", "")

    ordered_options:register_option_bool("start_with_pitchers_mitt",
        "Start with a pitcher's mitt", "")

    ordered_options:register_option_bool("start_with_parachute",
        "Start with a parachute", "")

    ordered_options:register_option_bool("start_with_true_crown",
        "Start with a true crown", "")

    ordered_options:register_option_bool("start_with_punish_ball",
        "Start with a punish ball", "")

    ordered_options:register_option_combo("start_with_back_item",
        "Start with back item",
        "Start the level wearing this back item.",
        START_BACK_ITEMS, START_BACK_ITEM_ORDER)

    ordered_options:register_option_combo("start_with_held_item",
        "Start with held item",
        "Start the level holding this item.",
        START_HELD_ITEMS, START_HELD_ITEM_ORDER)

    ordered_options:register_option_combo("start_with_mount",
        "Start with mount",
        "Start the level riding this mount.",
        START_MOUNTS, START_MOUNT_ORDER)

    ordered_options:register_option_combo("bubble_rider",
        "Bubble rider",
        "The type of entity that will be riding on top of the bubble. If a rider is specified, then the bubble will only be considered safe if both the bubble and rider will make it past the lasers.",
        BUBBLE_RIDERS, BUBBLE_RIDER_ORDER)

    ordered_options:register_option_bool("bubble_rider_mount_override",
        "Override bubble rider with starting mount",
        "If an eligible starting mount is chosen, then ignore the selected \"Bubble rider\" choice and instead use the matching \"Ducking player on [mount]\" choice.")

    ordered_options:register_option_bool("show_bubble_safety_colors",
        "Show bubble safety colors",
        "Apply a colored tint to bubbles depending on whether or not they are considered safe.")

    ordered_options:register_option_combo("bubble_color_safe",
        "Safe bubble color",
        "The color to indicate safe bubbles.",
        BUBBLE_COLORS, BUBBLE_COLOR_ORDER)

    ordered_options:register_option_combo("bubble_color_unsafe",
        "Unsafe bubble color",
        "The color to indicate unsafe bubbles.",
        BUBBLE_COLORS, BUBBLE_COLOR_ORDER)

    ordered_options:register_option_combo("laser_check",
        "Laser check",
        "Which laser timings to consider when evaluating the safety of a bubble. Only check the first laser if you just want to know whether a bubble will make it past that laser without hints about whether your rope or jump timings are correct afterward.",
        LASER_CHECKS, LASER_CHECK_ORDER)

    ordered_options:register_option_combo("show_bubble_interp_hitboxes",
        "Show interpolated bubble hitboxes",
        "Draw boxes showing where a bubble and its rider's hitboxes are going to be while the next laser is active. The small section on the top is the additional height of the rider. For a safe bubble, the laser will be in the empty gap between the boxes.",
        BUBBLE_INTERP_HITBOX_CHOICES, BUBBLE_INTERP_HITBOX_CHOICE_ORDER)

    ordered_options:register_option_bool("show_laser_hitboxes",
        "Show laser hitboxes",
        "Draw boxes showing the damaging region of the horizontal lasers.")

    ordered_options:register_option_bool("precise_gap_check",
        "Precise gap check",
        "If enabled, then bubbles are only considered safe if they will pass through the horizontal gap below the lasers. If disabled, then bubbles near the gap will also be considered safe even though they might not make it through. Bubbles that are obviously too far from the gap are always considered unsafe.")

    ordered_options:register_option_int("bubble_processing_rate",
        "Bubble processing rate",
        F"The number of bubbles to process per frame. Reduce this if you experience lag. Increase this for faster updates of bubble colors and interpolated hitboxes. There are {CONST.ENGINE_FPS} frames in a second. Roughly 30 bubbles exist at a time if only the necessary tiles have been bombed out.",
        1, 50)

    ordered_options:register_option_button("reset_options",
        "Reset options",
        "Reset all options to their default values.",
        register_options)
end

set_callback(function(ctx)
    local load_json = ctx:load()
    local load_table
    if not load_json or load_json == "" then
        load_table = {}
    else
        local success, result = pcall(function() return json.decode(load_json) or {} end)
        if success then
            load_table = result
        else
            print(F"Warning: Failed to read saved data: {result}")
            load_table = {}
        end
    end

    register_options(load_table.options)

    -- Activate the script immediately if the current level is Tiamat.
    if is_level_tiamat() and state.screen == ON.LEVEL then
        activate_script(false)
    end
end, ON.LOAD)

set_callback(function(ctx)
    -- Note: This callback is not called when exiting the game straight out of a level, and it isn't currently possible to save outside this callback without enabling unsafe mode.
    local save_json = json.encode({
        version = meta.version,
        options = ordered_options:to_table()
    })
    ctx:save(save_json)
end, ON.SAVE)

set_callback(function()
    -- The script needs to be deactivated and then activated whenever the Tiamat level is loaded. Some restart scenarios won't trigger a callback to deactivate it, so explicitly deactivate it here. If this isn't the Tiamat level, then leave it deactivated.
    deactivate_script()
    if is_level_tiamat() then
        activate_script(true)
    end
end, ON.LEVEL)

set_callback(function()
    if not is_level_tiamat() or (state.screen ~= ON.LEVEL and state.screen ~= ON.OPTIONS) then
        -- The game is loading into a level or menu that is not the Tiamat level. Deactivate the script.
        deactivate_script()
    end
    if ordered_options:get_value("start_tiamat_level") and state.loading == 1 and state.screen_next == ON.LEVEL
            and state.world_next == 1 and state.level_next == 1 and state.theme_next == THEME.DWELLING then
        -- The game is loading into 1-1. Go to Tiamat instead and set it as the starting level.
        set_start_level_tiamat()
        set_next_level_tiamat()
    end
end, ON.LOADING)
