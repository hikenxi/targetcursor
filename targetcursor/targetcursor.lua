addon.name    = 'targetcursor'
addon.author  = 'Jyouya (original), yzyii (sub cursor), Hiken (fork)'
addon.version = '1.1'
addon.desc    = 'Displays a cursor of your choice that can be colored and scaled, anchored correctly on every model'

-- A fork of `customtarget`, written by Jyouya and extended by yzyii, whose v0.6
-- this started from. Horizontal position from the model's render base, height
-- from the anchor bone scaled by the model's own render scale.

-- See README.md for configuration, the range-color rule, and credits.


require('common')


-- * Edit this part to match your custom cursor * --
local filepathForCursor    = 'edit/default_cursor.png'
                                 -- default: 'edit/default_cursor.png'
local filepathForCursorSub = 'edit/default_subcursor.png'
                                 -- default: 'edit/default_subcursor.png'
local cursorWidth          = 20  -- Width of ONE frame in the sheet. default: 20
local cursorHeight         = 32  -- Height of ONE frame in the sheet. default: 32
local animFrames           = 6   -- Frames in the sheet, left to right (1 = no animation).
                                 -- default: 6
local animFPS              = 15  -- Animation speed. FFXI's UI runs at 30fps and holds each
                                 -- cursor frame for 2 ticks, so 15 is the game's own rate.
                                 -- default: 15
local cursorScaleFactor    = 1.0 -- On-screen size multiplier. To match the size
                                 -- the game draws its own cursor:
                                 --   scale = background height / menu height
                                 --
                                 -- 1.0 when they match; a 1440p background with a
                                 -- 1080p menu wants 1.333.
                                 -- default: 1.0
-- * ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ * --

-- * Opacity * --
-- 1.0 = art as it is, 0.0 = invisible. A MULTIPLY on the art's own per-pixel
-- alpha, so soft edges stay soft. 0.80 matches the game's own sub cursor.
local cursorOpacity    = 1.0   -- main cursor. default: 1.0
local subCursorOpacity = 1.0   -- sub cursor.  default: 1.0  (0.80 matches the game's own)
-- * ^^^^^^^^ * --

-- * Main cursor tint * --
-- nil = draw the cursor art exactly as it is (default).
-- Set to {r,g,b} to recolor it, e.g. {120,255,140} for green.
-- The tint is a MULTIPLY, so it is applied to the neutral (gray) sheet below
-- rather than the colored art - tinting already-colored art muddies it.
local colorMainCursor = nil    -- default: nil
-- * ^^^^^^^^^^^^^^^^^^^^ * --

-- * Sub cursor range colors * --
-- The game tints its sub cursor by whether the selected action reaches the
-- target. Sampled from the game's own cursor, applied to the neutral sheet.
local rangeColors     = true               -- default: true
local colorInRange    = {121,107,255}  -- blue  - action will reach.     default: {121,107,255}
local colorNearRange  = {255,255,103}  -- yellow- just out of reach.     default: {255,255,103}
local colorOutOfRange = {255,108,97}  -- red   - out of range.          default: {255,108,97}
-- Neutral (gray) sheet, used both by the range colors above and by
-- colorMainCursor. Tinting already-colored art multiplies the two and muddies it.
--
-- nil DERIVES it from filepathForCursor by inserting '_neutral' before the
-- extension. Set it only for art that does not follow that naming.
local filepathForCursorRange = nil         -- default: nil
-- * ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ * --

-- Range thresholds. All read from the client, so there is no spell table and
-- nothing to maintain:
--
--   blue  <=>  sqrt(GetDistance + dz^2) <= ActionTargetMaxYalms + hitbox
--
-- A ranged attack (ActionId 0) gets no hitbox.
--
-- ModelHitboxSize is already scaled - do not multiply it by the model scale.
-- NOTES.md section 7b has the calibration behind these numbers.
local rangeBaseOffset = 0.00   -- constant added to (range + hitbox). default: 0.00
local rangeYellowBand = 0.95   -- width of the yellow "almost in range" band. default: 0.95
local rangeDefaultHitbox = 1.0 -- fallback when the entity reports no hitbox. default: 1.0

-- Placement. Measured against the game's own cursor; none of it should need
-- changing.
local anchorBone      = 2      -- Bone supplying the anchor height. Bone 2 is the top of the body on
                               -- every skeleton measured. -1 = model base. default: 2
local anchorHeight    = 0.0    -- Extra world-units nudge after scaling. POSITIVE raises.
                               -- default: 0.0
local anchorSmoothing = 0.04   -- How fast the damped height follows the bone. Lower = steadier.
                               -- default: 0.04
local objectPosOffset = 0x34   -- Position offset inside a target-actor struct that has no entity
                               -- index (moghouse doors). Copies also exist at 0xC4 and 0xD4.
                               -- Only change this if a client update moves the field.
                               -- default: 0x34

-- Library bindings. Below the settings so the editable values come first.
local d3d               = require('d3d8')
local d3d8dev           = d3d.get_device()
local ffi               = require('ffi')
local C                 = ffi.C

local cursorRect        = ffi.new('RECT', { 0, 0, cursorWidth, cursorHeight })

-- Point cursorRect at the current animation frame.
local function setAnimFrame()
    if (animFrames <= 1) then
        return
    end

    local frame = math.floor(os.clock() * animFPS) % animFrames

    cursorRect.left   = frame * cursorWidth
    cursorRect.right  = cursorRect.left + cursorWidth
    cursorRect.top    = 0
    cursorRect.bottom = cursorHeight
end
local cursorPos         = ffi.new('D3DXVECTOR2', { 0, 0 })
local cursorPosSub      = ffi.new('D3DXVECTOR2', { 0, 0 })
local cursorScale       = ffi.new('D3DXVECTOR2', { cursorScaleFactor, cursorScaleFactor })

local cursorTex
local cursorTexSub
local cursorTexRange
local triedCursorTexRange = false

-- GetSubTargetFlags reads 0xFFFFFFFF when nothing is being selected.
local SUBTARGET_NONE = 0xFFFFFFFF

local _, viewport = d3d8dev:GetViewport()
local width       = viewport.Width
local height      = viewport.Height

-- Scratch matrix, reused every call to avoid allocating one per frame.
local viewProj = ffi.new('D3DXMATRIX')

-- view * projection, written INTO `out` rather than returned.
local function matrixMultiply(out, m1, m2)
    out._11 = m1._11 * m2._11 + m1._12 * m2._21 + m1._13 * m2._31 + m1._14 * m2._41
    out._12 = m1._11 * m2._12 + m1._12 * m2._22 + m1._13 * m2._32 + m1._14 * m2._42
    out._13 = m1._11 * m2._13 + m1._12 * m2._23 + m1._13 * m2._33 + m1._14 * m2._43
    out._14 = m1._11 * m2._14 + m1._12 * m2._24 + m1._13 * m2._34 + m1._14 * m2._44

    out._21 = m1._21 * m2._11 + m1._22 * m2._21 + m1._23 * m2._31 + m1._24 * m2._41
    out._22 = m1._21 * m2._12 + m1._22 * m2._22 + m1._23 * m2._32 + m1._24 * m2._42
    out._23 = m1._21 * m2._13 + m1._22 * m2._23 + m1._23 * m2._33 + m1._24 * m2._43
    out._24 = m1._21 * m2._14 + m1._22 * m2._24 + m1._23 * m2._34 + m1._24 * m2._44

    out._31 = m1._31 * m2._11 + m1._32 * m2._21 + m1._33 * m2._31 + m1._34 * m2._41
    out._32 = m1._31 * m2._12 + m1._32 * m2._22 + m1._33 * m2._32 + m1._34 * m2._42
    out._33 = m1._31 * m2._13 + m1._32 * m2._23 + m1._33 * m2._33 + m1._34 * m2._43
    out._34 = m1._31 * m2._14 + m1._32 * m2._24 + m1._33 * m2._34 + m1._34 * m2._44

    out._41 = m1._41 * m2._11 + m1._42 * m2._21 + m1._43 * m2._31 + m1._44 * m2._41
    out._42 = m1._41 * m2._12 + m1._42 * m2._22 + m1._43 * m2._32 + m1._44 * m2._42
    out._43 = m1._41 * m2._13 + m1._42 * m2._23 + m1._43 * m2._33 + m1._44 * m2._43
    out._44 = m1._41 * m2._14 + m1._42 * m2._24 + m1._43 * m2._34 + m1._44 * m2._44
end

-- Row-vector convention: v * (view * projection), then NDC -> raster.
local function worldToScreen(x, y, z, view, projection)
    matrixMultiply(viewProj, view, projection)

    local rhw = 1 / (viewProj._14 * x + viewProj._24 * y + viewProj._34 * z + viewProj._44)

    local ndcX = (viewProj._11 * x + viewProj._21 * y + viewProj._31 * z + viewProj._41) * rhw
    local ndcY = (viewProj._12 * x + viewProj._22 * y + viewProj._32 * z + viewProj._42) * rhw
    local ndcZ = (viewProj._13 * x + viewProj._23 * y + viewProj._33 * z + viewProj._43) * rhw

    return math.floor((ndcX + 1) * 0.5 * width),
        math.floor((1 - ndcY) * 0.5 * height),
        ndcZ
end

-- The base position the model is actually RENDERED at this frame, free of
-- animation movement. This is what the nameplate follows.
local function getActorBase(actorPointer)
    return ashita.memory.read_float(actorPointer + 0x678),
        ashita.memory.read_float(actorPointer + 0x680),
        ashita.memory.read_float(actorPointer + 0x67C)
end

-- actor -> skeleton, three dereferences. Each can be null, so each is checked.
local function skeletonOf(actorPointer)
    local skeletonBaseAddress = ashita.memory.read_uint32(actorPointer + 0x6B8)
    if (skeletonBaseAddress == 0) then return 0 end

    local skeletonOffsetAddress = ashita.memory.read_uint32(skeletonBaseAddress + 0x0C)
    if (skeletonOffsetAddress == 0) then return 0 end

    return ashita.memory.read_uint32(skeletonOffsetAddress)
end

-- The anchor bone's height offset ABOVE THE RENDER BASE, in model space.
--
local function getBoneOffsetZ(actorPointer, bone)
    local skeletonAddress = skeletonOf(actorPointer)
    if (skeletonAddress == 0) then return 0 end

    local boneCount = ashita.memory.read_uint16(skeletonAddress + 0x32)

    -- Generators follow the bone records: header 0x04, then 0x1E per bone.
    local generatorsAddress = skeletonAddress + 0x30 + 0x04 + 0x1E * boneCount + 4

    -- 0x1A per generator record; the offset triplet starts at +0x0E and dz - the
    -- vertical axis - is the SECOND float of the three.
    return ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x4)
end

-- Opacity as a D3DCOLOR alpha byte, clamped so a typo cannot wrap.
local function alphaByte(o)
    if (type(o) ~= 'number' or o ~= o) then return 255 end
    if (o < 0) then o = 0 elseif (o > 1) then o = 1 end
    return math.floor(o * 255 + 0.5)
end

-- 'edit/ffxi_cursor.png' -> 'edit/ffxi_cursor_neutral.png'.
local function neutralPathFor(p)
    if (p == nil) then return nil end
    local base, ext = p:match('^(.*)%.([^.]+)$')
    if (base == nil) then return p .. '_neutral.png' end
    return base .. '_neutral.' .. ext
end

local function loadCursorTex(filepath)
    if (not filepath) then
        return nil
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    if (C.D3DXCreateTextureFromFileA(d3d8dev, addon.path .. filepath, texture_ptr) ~= C.S_OK) then
        return nil
    end

    return d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]))
end

local function loadSprite()
    local sprite_ptr = ffi.new('ID3DXSprite*[1]')
    if (C.D3DXCreateSprite(d3d8dev, sprite_ptr) ~= C.S_OK) then
        error('failed to make sprite obj')
    end

    return d3d.gc_safe_release(ffi.cast('ID3DXSprite*', sprite_ptr[0]))
end

-- Anchor a cursor on a model. Horizontal comes from the model's render base,
-- which is frame-accurate and free of animation. Only the HEIGHT comes from the
-- bone, low-pass filtered so breathing and run cycles do not reach the cursor.
-- The filter state is keyed on target index, and indices are RECYCLED slots, so
-- it records which actor each value belongs to and drops it when that changes.
local smoothDelta = {} -- targetIndex -> damped bone height offset
local smoothOwner = {} -- targetIndex -> actor pointer that value belongs to

-- A jump larger than this is a change of subject, not animation, so the filter
-- restarts rather than sliding across it.
local anchorSnapJump = 0.5 -- world units

-- The model's render scale, per creature. The game hangs its cursor at the
-- anchor bone's height MULTIPLIED by this. Copies live at 0x69C/0x6A0/0x754.
local function getModelScale(pointer)
    local s = ashita.memory.read_float(pointer + 0x698)
    if (s ~= s or s <= 0.01 or s > 20.0) then
        return 1.0
    end
    return s
end

local function anchorFromModel(pointer, idx)
    local scale = getModelScale(pointer)
    local bx, by, bz = getActorBase(pointer)

    local delta = 0
    if (anchorBone >= 0) then
        delta = getBoneOffsetZ(pointer, anchorBone)
    end

    -- New occupant on this index: throw the inherited value away and snap.
    if (smoothOwner[idx] ~= pointer) then
        smoothOwner[idx] = pointer
        smoothDelta[idx] = nil
    end

    local prev = smoothDelta[idx]
    if (prev == nil or math.abs(delta - prev) > anchorSnapJump) then
        prev = delta
    end
    local damped = prev + (delta - prev) * anchorSmoothing
    smoothDelta[idx] = damped

    return bx, by, bz + (damped * scale) - anchorHeight
end

local function rangeColorFor(idx)
    if (not rangeColors or idx == nil or idx == 0) then return nil end
    local tgt = AshitaCore:GetMemoryManager():GetTarget()
    if (tgt == nil or tgt:GetActionTargetActive() == 0) then return nil end

    local maxY = tgt:GetActionTargetMaxYalms()
    if (maxY == 0) then return nil end
    if (maxY == 0xFF) then return colorInRange end   -- self-only action

    local ent = AshitaCore:GetMemoryManager():GetEntity()
    local sq  = ent:GetDistance(idx)                 -- squared, horizontal only
    if (sq == nil or sq < 0) then return nil end

    -- The client's check is 3D; GetDistance is horizontal, so height is added here.
    local party = AshitaCore:GetMemoryManager():GetParty()
    local me    = party and party:GetMemberTargetIndex(0) or 0
    local dz    = 0
    if (me ~= 0 and me ~= idx) then
        dz = ent:GetLocalPositionZ(idx) - ent:GetLocalPositionZ(me)
        if (dz ~= dz) then dz = 0 end
    end

    local dist = math.sqrt(sq + (dz * dz))

    -- Already scaled by the client. Do not multiply by the model scale.
    local hb = ent:GetModelHitboxSize(idx)
    if (hb == nil or hb ~= hb or hb <= 0 or hb > 20) then hb = rangeDefaultHitbox end

    -- A ranged attack (no action id) gets no hitbox allowance. Everything else is
    -- checked edge to edge, so the caster's own hitbox counts too.
    local isRanged = (tgt:GetActionId() == 0)
    local hbSelf = 0
    if (isRanged) then
        hb = 0
    elseif (me ~= 0) then
        hbSelf = ent:GetModelHitboxSize(me)
        if (hbSelf == nil or hbSelf ~= hbSelf or hbSelf <= 0 or hbSelf > 20) then
            hbSelf = 0
        end
    end

    local blueAt = maxY + hb + hbSelf + rangeBaseOffset

    local c
    if (dist <= blueAt) then                       c = colorInRange
    elseif (dist <= blueAt + rangeYellowBand) then c = colorNearRange
    else                                           c = colorOutOfRange end
    return c
end

local function getPos(targetIndex, slot)
    -- Save the entity manager for ease of use
    local entity = AshitaCore:GetMemoryManager():GetEntity()

    local haveIndex = (targetIndex ~= nil and targetIndex ~= 0)

    -- Only meaningful when there is an entity index to look up
    local entityType, renderFlags, isSelf
    if (haveIndex) then
        entityType = entity:GetType(targetIndex)
        renderFlags = entity:GetRenderFlags0(targetIndex)

        -- Is this us?
        local party = AshitaCore:GetMemoryManager():GetParty()
        isSelf = (party ~= nil and targetIndex == party:GetMemberTargetIndex(0))
    end

    local tx, ty, tz
    if (not haveIndex) then
-- Moghouse doors report target index 0 - a null entity at the zone origin, so
-- drive everything from the target structure's own actor pointer.
        local targetActor = 0
        if (slot ~= nil) then
            local tgt = AshitaCore:GetMemoryManager():GetTarget()
            if (tgt ~= nil) then
                targetActor = tgt:GetActorPointer(slot) or 0
            end
        end

        if (targetActor == 0) then
            return nil, nil, nil
        end
        -- Not an XiModel: +0x678 is an orientation vector. Real coordinates live at
        -- objectPosOffset, in the same memory order the rest of the addon uses.
        tx = ashita.memory.read_float(targetActor + objectPosOffset)
        tz = ashita.memory.read_float(targetActor + objectPosOffset + 4)
        ty = ashita.memory.read_float(targetActor + objectPosOffset + 8)
        if (tx == 0 and ty == 0 and tz == 0) then
            tx, ty, tz = getActorBase(targetActor)
        end
    elseif (isSelf) then
        local selfPointer = entity:GetActorPointer(targetIndex)
        if (selfPointer ~= nil and selfPointer ~= 0) then
            tx, ty, tz = anchorFromModel(selfPointer, targetIndex)
        else
            tx = entity:GetLocalPositionX(targetIndex)
            ty = entity:GetLocalPositionY(targetIndex)
            tz = entity:GetLocalPositionZ(targetIndex) - anchorHeight
        end
    elseif (entityType == 3) then -- If target is a door or something similar
        -- Doors that DO have an entity index use the entity position.
        tx = entity:GetLocalPositionX(targetIndex)
        ty = entity:GetLocalPositionY(targetIndex)
        tz = entity:GetLocalPositionZ(targetIndex)
    elseif (renderFlags == 0 and entityType == 0) then
        tx = entity:GetLastPositionX(targetIndex)
        ty = entity:GetLastPositionY(targetIndex)
        tz = entity:GetLastPositionZ(targetIndex)
    else
        -- Mobs, NPCs and other players: same anchoring as the self case.
        local targetPointer = entity:GetActorPointer(targetIndex)
        if (targetPointer ~= nil and targetPointer ~= 0) then
            tx, ty, tz = anchorFromModel(targetPointer, targetIndex)
        else
            tx = entity:GetLocalPositionX(targetIndex)
            ty = entity:GetLocalPositionY(targetIndex)
            tz = entity:GetLocalPositionZ(targetIndex) - anchorHeight
        end
    end

    -- Get the transformation matrices for the scene
    local _, view = d3d8dev:GetTransform(C.D3DTS_VIEW)
    local _, projection = d3d8dev:GetTransform(C.D3DTS_PROJECTION)

    -- Screen coordinates for our nameplate. These MUST be locals - Ashita shares
    -- one Lua state between addons.
    local x, y, ndcZ = worldToScreen(tx, tz, ty, view, projection)

    -- Adjust the coordinates so the cursor is in the right place
    x = x - (cursorWidth * cursorScaleFactor) / 2
    y = y - (cursorHeight * cursorScaleFactor)

    return x, y, ndcZ
end

local chat = require('chat')

-- Live tuning. Session-only - put anything you want to keep in the block above.
ashita.events.register('command', 'targetcursor_cmd', function(e)
    local args = e.command:args()
    if (#args == 0 or args[1] ~= '/tc') then
        return
    end
    e.blocked = true

    local function report()
        print(chat.header('targetcursor'):append(chat.message(string.format(
            'bone=%d height=%.3f smoothing=%.3f  (session only)',
            anchorBone, anchorHeight, anchorSmoothing))))
    end

    if (#args >= 3 and args[2] == 'height') then
        anchorHeight = tonumber(args[3]) or anchorHeight
        -- Both tables, not just the damped values: smoothOwner is what decides
        -- whether an inherited value is thrown away, so clearing one without the
        -- other leaves the guard holding a stale owner. It happens to work out
        -- through the nil check below, but only by luck.
        smoothDelta = {}
        smoothOwner = {}
        report()
    elseif (#args >= 3 and args[2] == 'bone') then
        anchorBone = tonumber(args[3]) or anchorBone
        -- Both tables, not just the damped values: smoothOwner is what decides
        -- whether an inherited value is thrown away, so clearing one without the
        -- other leaves the guard holding a stale owner. It happens to work out
        -- through the nil check below, but only by luck.
        smoothDelta = {}
        smoothOwner = {}
        report()
    elseif (#args >= 3 and args[2] == 'smooth') then
        anchorSmoothing = tonumber(args[3]) or anchorSmoothing
        report()
    else
        print(chat.header('targetcursor'):append(chat.message(
            '/tc height <n>  vertical nudge, world units, positive raises')))
        print(chat.header('targetcursor'):append(chat.message(
            '/tc bone <n>    anchor bone, -1 = model base')))
        print(chat.header('targetcursor'):append(chat.message(
            '/tc smooth <n>  0-1, how fast the height follows the bone')))
        report()
    end
end)

ashita.events.register('load', 'targetcursor_load', function()
    local sprite = loadSprite()

    ashita.events.register('d3d_present', 'targetcursor_present', function()
        -- Save the target manager for ease of use
        local target = AshitaCore:GetMemoryManager():GetTarget()

        -- Determine if we are currently subtargetting
        local isSubTargetActive = target:GetIsSubTargetActive()

        -- Exit early only if NEITHER slot has an active target.
        --
        -- This used to be target:GetIsActive(isSubTargetActive) - checking only
        -- the slot isSubTargetActive currently points at. Bug: fighting mob A
        -- (locked, slot 0) while sub-targeting an ability onto mob B (slot 1)
        -- and mob A dies mid-selection clears slot 0's Active flag; with
        -- isSubTargetActive still 1 that alone should not have mattered, but
        -- the client also appears to drop out of sub-targeting the instant its
        -- locked target dies, which flips isSubTargetActive to 0 THIS SAME
        -- FRAME - so the very next line ends up testing slot 0 (mob A, now
        -- dead) instead of slot 1 (mob B, still a live, still-valid subtarget).
        -- That single check then bailed out of the WHOLE frame, before the
        -- independent targetIndexSub branch below ever ran - erasing the still-
        -- valid sub cursor over mob B along with the main cursor. The real
        -- client keeps its own cursor over mob B in this situation; checking
        -- both slots here before giving up lets this addon do the same.
        if (target:GetIsActive(0) == 0 and target:GetIsActive(1) == 0) then
            return
        end

        -- Get the index of your current target or subtarget (if any)
        local targetIndex = target:GetTargetIndex(isSubTargetActive)
        local targetIndexSub = nil
        if (isSubTargetActive == 1) then
            targetIndexSub = target:GetTargetIndex(0)
        end

        -- Get/load the cursor textures
        cursorTex = cursorTex or loadCursorTex(filepathForCursor)
        cursorTexSub = cursorTexSub or loadCursorTex(filepathForCursorSub)
        -- Load once, and warn once on failure rather than retrying every frame.
        if (not triedCursorTexRange) then
            triedCursorTexRange = true
            local wanted = filepathForCursorRange or neutralPathFor(filepathForCursor)
            cursorTexRange = loadCursorTex(wanted)
            if (cursorTexRange == nil and (colorMainCursor ~= nil or rangeColors)) then
                print(chat.header('targetcursor'):append(chat.error(
                    'Cannot load neutral sheet: ' .. tostring(wanted))))
                print(chat.header('targetcursor'):append(chat.message(
                    'Tinting and range colors are disabled until it exists.')))
            end
        end

        -- Main cursor: tinted only if the user asked for it.
        local mainA = alphaByte(cursorOpacity)
        local subA  = alphaByte(subCursorOpacity)

        local function drawMain(pos)
            if (colorMainCursor ~= nil and cursorTexRange ~= nil) then
                sprite:Draw(cursorTexRange, cursorRect, cursorScale, nil, 0.0, pos,
                    d3d.D3DCOLOR_ARGB(mainA, colorMainCursor[1], colorMainCursor[2],
                        colorMainCursor[3]))
            else
                sprite:Draw(cursorTex, cursorRect, cursorScale, nil, 0.0, pos,
                    d3d.D3DCOLOR_ARGB(mainA, 255, 255, 255))
            end
        end

        -- Draw the sub cursor tinted when an action selection is up, plain otherwise.
        -- States with no action target take colorInRange rather than the pre-tinted
        -- art, so one config value owns the sub cursor's color.
        local function drawSub(idx, pos)
            local c = rangeColorFor(idx) or (rangeColors and colorInRange or nil)
            if (c ~= nil and cursorTexRange ~= nil) then
                sprite:Draw(cursorTexRange, cursorRect, cursorScale, nil, 0.0, pos,
                    d3d.D3DCOLOR_ARGB(subA, c[1], c[2], c[3]))
            else
                sprite:Draw(cursorTexSub, cursorRect, cursorScale, nil, 0.0, pos,
                    d3d.D3DCOLOR_ARGB(subA, 255, 255, 255))
            end
        end

        -- Advance the shimmer animation for this frame
        setAnimFrame()

        -- Get target cursor position.
        --
        -- getPos returns nil, nil, nil when it cannot place this target at
        -- all - no entity index AND no target-struct actor pointer, which is
        -- exactly the state of a target that JUST DIED. Assigning nil straight
        -- into cursorPos.x/y would store nil into an FFI float field and
        -- throw, and an uncaught throw here kills the rest of this frame's
        -- drawing - every frame, until /addon reload - because nothing after
        -- it in this callback runs. Land the result in plain locals first and
        -- only touch the FFI vector once ndcZ confirms there is a real
        -- position to draw.
        local px, py, ndcZ = getPos(targetIndex, isSubTargetActive)

        -- Test if target cursor is in the viewing volume
        if (ndcZ ~= nil and ndcZ >= 0 and ndcZ <= 1) then
            cursorPos.x, cursorPos.y = px, py
            local flags = target:GetSubTargetFlags()

            -- Is the game showing its blue selection cursor? If so the addon
            -- draws the sub cursor rather than the main one.
            --
            -- SubTargetFlags is a per-action mask of valid target types, 0xFFFFFFFF when
            -- nothing is selected, so testing the sentinel is the only complete test.
            -- 'not targetIndexSub' because a separate sub target index is drawn below.
            if (flags ~= SUBTARGET_NONE and not targetIndexSub) then
                drawSub(targetIndex, cursorPos)
            else
                drawMain(cursorPos)
            end
        end

        if (targetIndexSub) then
		    -- Get subtarget cursor position. Same nil hazard as above, and the
            -- exact one that was crashing every frame once the early-exit fix
            -- stopped hiding it: targetIndexSub still pointed at the just-died
            -- locked target, getPos correctly gave up and returned nil, and
            -- the old code assigned that nil straight into cursorPosSub.x/y -
            -- via the "Pad subtarget" line below - before ever checking it.
            local pxSub, pySub, ndcZSub = getPos(targetIndexSub, 0)

            -- Test if subtarget cursor is in the viewing volume
            if (ndcZSub ~= nil and ndcZSub >= 0 and ndcZSub <= 1) then
                -- Pad subtarget, then draw it
                cursorPosSub.x, cursorPosSub.y = pxSub, pySub - 10
                drawSub(targetIndexSub, cursorPosSub)
            end

        end
    end)
end)