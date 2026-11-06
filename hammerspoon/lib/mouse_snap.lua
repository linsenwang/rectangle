-- ============================================
-- 鼠标贴边吸附（Rectangle 风格拖拽）
--
-- 拖动窗口时：
--   左右边缘 -> 半屏
--   顶部     -> 最大化（沿用应用边距）
--   四角     -> 1/4 屏
--
-- 性能要点：
--   1. 不监听 leftMouseDragged。拖动事件全部交给系统原生处理，
--      避免每个事件同步穿过 Lua 桥导致掉帧（hs.eventtap 的已知问题）。
--   2. 用 60Hz 定时器轮询鼠标位置和按键，高频路径只有两次轻量 API 调用
--      + 纯 Lua 的坐标判断。
--   3. 拖动过程中只画 hs.canvas 预览，松开鼠标时才真正设置窗口 frame。
--      实时调用 win:setFrame() 会因 AX 桥接产生明显卡顿。
--   4. 预览只在跨越吸附区域时更新一次，窗口 frame 只用于确认「真的在拖窗口」。
-- ============================================

local M = {}

local cfg = MouseSnapConfig or {}
local EDGE = cfg.edgeSize or 24
local TOP_EDGE = cfg.topEdgeSize or 10
local CORNER_RATIO = cfg.cornerRatio or 0.15
local MIN_DRAG = cfg.minDrag or 20
local MIN_FRAME_CHANGE = cfg.minFrameChange or 8
local FRAME_CHECK_INTERVAL = 0.08
local APPLY_DELAY = 0.01
local POLL_INTERVAL = 1 / 60

local preview = nil
local previewShowing = false
local pollTimer = nil
local buttonWasDown = false
local state = nil

-- ============================================
-- 基础工具
-- ============================================

local function pointInFrame(point, frame)
    return point.x >= frame.x and point.x <= frame.x + frame.w
       and point.y >= frame.y and point.y <= frame.y + frame.h
end

local function isEligible(win)
    if not win then return false end
    local ok, standard, fullscreen = pcall(function()
        return win:isStandard(), win:isFullScreen()
    end)
    return ok and standard and not fullscreen
end

-- 正在拖动的窗口。优先用焦点窗口（拖动一个可见窗口时它通常已经获得焦点），
-- 只有焦点窗口不包含鼠标位置时才退回有序窗口列表。
local function windowAtPoint(point)
    local focused = hs.window.focusedWindow()
    if isEligible(focused) then
        local ok, frame = pcall(function() return focused:frame() end)
        if ok and frame and pointInFrame(point, frame) then
            return focused
        end
    end

    local ok, windows = pcall(hs.window.orderedWindows)
    if not ok or not windows then return nil end
    for _, win in ipairs(windows) do
        if isEligible(win) then
            local okFrame, frame = pcall(function() return win:frame() end)
            if okFrame and frame and pointInFrame(point, frame) then
                return win
            end
        end
    end

    return nil
end

-- 一次性缓存所有屏幕的 frame 与可用区域，拖动期间不再查询屏幕 API
local function collectScreens(win)
    local screens = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local ok, frame = pcall(function() return screen:frame() end)
        if ok and frame then
            screens[#screens + 1] = {
                screen = screen,
                frame = frame,
                area = getUsableArea(frame, win),
            }
        end
    end
    return screens
end

-- ============================================
-- 吸附区域判断（纯 Lua）
-- ============================================

local function zoneAt(point, screens)
    for _, entry in ipairs(screens) do
        local frame = entry.frame
        if pointInFrame(point, frame) then
            local area = entry.area
            local nearLeft = point.x <= frame.x + EDGE
            local nearRight = point.x >= frame.x + frame.w - EDGE
            local nearTop = point.y <= frame.y + TOP_EDGE

            local cornerH = math.min(math.max(area.h * CORNER_RATIO, 50), 120)
            local inTopCorner = point.y <= area.y + cornerH
            local inBottomCorner = point.y >= area.y + area.h - cornerH

            if nearLeft and inTopCorner then
                return { type = "corner", pos = "tl" }, entry
            elseif nearRight and inTopCorner then
                return { type = "corner", pos = "tr" }, entry
            elseif nearLeft and inBottomCorner then
                return { type = "corner", pos = "bl" }, entry
            elseif nearRight and inBottomCorner then
                return { type = "corner", pos = "br" }, entry
            elseif nearLeft then
                return { type = "left-half", ratio = 0.5 }, entry
            elseif nearRight then
                return { type = "right-half", ratio = 0.5 }, entry
            elseif nearTop then
                return { type = "maximized" }, entry
            end
            return nil, entry
        end
    end
    return nil, nil
end

-- ============================================
-- 预览画布
-- ============================================

local function ensurePreview()
    if preview then return preview end

    preview = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    preview:level(hs.canvas.windowLevels.overlay)
    preview:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
        + hs.canvas.windowBehaviors.stationary
        + hs.canvas.windowBehaviors.ignoresCycle)
    preview:clickActivating(false)
    preview:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = cfg.previewColor or { red = 0.04, green = 0.52, blue = 1.0, alpha = 0.22 },
        roundedRectRadii = { xRadius = 10, yRadius = 10 },
    }, {
        type = "rectangle",
        action = "stroke",
        strokeColor = cfg.previewBorderColor or { red = 0.04, green = 0.52, blue = 1.0, alpha = 0.85 },
        strokeWidth = 2,
        roundedRectRadii = { xRadius = 10, yRadius = 10 },
    })
    return preview
end

local function showPreview(rect)
    if cfg.preview == false then return end
    local canvas = ensurePreview()
    canvas:frame({ x = rect.x, y = rect.y, w = rect.w, h = rect.h })
    if not previewShowing then
        canvas:show()
        previewShowing = true
    end
end

local function hidePreview()
    if preview and previewShowing then
        preview:hide()
        previewShowing = false
    end
end

-- ============================================
-- 拖动状态
-- ============================================

local function resetState()
    state = nil
    hidePreview()
end

local function initDrag(point)
    local win = windowAtPoint(point)
    if not win then return nil end

    local ok, frame = pcall(function() return win:frame() end)
    if not ok or not frame then return nil end

    return {
        win = win,
        initialized = true,
        baseFrame = frame,
        screens = collectScreens(win),
        armed = false,
        invalid = false,
        lastCheck = 0,
    }
end

-- 确认窗口真的被移动（而不是选文字/拖文件）：位置变化且尺寸基本不变
local function checkFrameChanged(st)
    local ok, frame = pcall(function() return st.win:frame() end)
    if not ok or not frame then
        st.invalid = true
        return false, false
    end

    local base = st.baseFrame
    local moved = math.abs(frame.x - base.x) > MIN_FRAME_CHANGE
               or math.abs(frame.y - base.y) > MIN_FRAME_CHANGE
    local resized = math.abs(frame.w - base.w) > MIN_FRAME_CHANGE
                 or math.abs(frame.h - base.h) > MIN_FRAME_CHANGE
    return moved, resized
end

local function shouldArm(st, now)
    if st.armed or st.invalid then return st.armed end
    if now - st.lastCheck < FRAME_CHECK_INTERVAL then return false end
    st.lastCheck = now

    local moved, resized = checkFrameChanged(st)
    if resized then
        st.invalid = true
        return false
    end
    if moved then st.armed = true end
    return st.armed
end

local function updatePreview(st, zone, entry)
    if not zone or st.invalid or not st.armed then
        hidePreview()
        return
    end

    local frame = layoutFrameFor(zone, entry.frame, st.win)
    if frame then
        showPreview(frame)
    else
        hidePreview()
    end
end

local function applySnap(win, zone, entry)
    if not isEligible(win) then return end
    local ok, frame = pcall(function() return win:frame() end)
    if not ok or not frame then return end

    if not detectLayoutMode(win) then
        saveWindowState(win)
    end

    local target = layoutFrameFor(zone, entry.frame, win)
    if target then setWinFrame(win, target) end
end

-- ============================================
-- 轮询状态机
-- ============================================

local function finishDrag(st)
    if not st or not st.initialized or st.invalid then return end
    if not st.zone or not st.entry then return end

    -- 鼠标移动很快时可能还没通过节流检查，这里做最终确认
    if not st.armed then
        local moved, resized = checkFrameChanged(st)
        if not moved or resized then return end
    else
        local _, resized = checkFrameChanged(st)
        if resized then return end
    end

    local win, zone, entry = st.win, st.zone, st.entry
    hs.timer.doAfter(APPLY_DELAY, function()
        applySnap(win, zone, entry)
    end)
end

local function poll()
    local down = hs.eventtap.checkMouseButtons().left == true

    if not down then
        if buttonWasDown then
            buttonWasDown = false
            local st = state
            resetState()
            finishDrag(st)
        end
        return
    end

    -- 空闲时不读鼠标位置，只有按住左键拖动期间才轮询坐标
    local point = hs.mouse.absolutePosition()

    if not buttonWasDown then
        buttonWasDown = true
        hidePreview()
        state = {
            down = point,
            initialized = false,
            zone = nil,
            entry = nil,
            invalid = false,
        }
        return
    end

    local st = state
    if not st or st.invalid then return end

    if not st.initialized then
        local dx = point.x - st.down.x
        local dy = point.y - st.down.y
        if dx * dx + dy * dy < MIN_DRAG * MIN_DRAG then return end

        local dragState = initDrag(point)
        if not dragState then
            st.invalid = true
            return
        end
        dragState.down = st.down
        state = dragState
        st = dragState
    end

    local zone, entry = zoneAt(point, st.screens)
    if zone ~= st.zone or entry ~= st.entry then
        st.zone = zone
        st.entry = entry
    end

    if zone and not st.armed and not st.invalid then
        shouldArm(st, hs.timer.secondsSinceEpoch())
    end

    updatePreview(st, zone, entry)
end

-- ============================================
-- 启停
-- ============================================

function M.start()
    if pollTimer then return end
    ensurePreview()
    pollTimer = hs.timer.doEvery(POLL_INTERVAL, poll)
    print("[MouseSnap] 鼠标贴边吸附已启动")
end

function M.stop()
    if pollTimer then
        pollTimer:stop()
        pollTimer = nil
    end
    buttonWasDown = false
    resetState()
    print("[MouseSnap] 鼠标贴边吸附已停止")
end

function M.isRunning()
    return pollTimer ~= nil and pollTimer:running()
end

MouseSnap = M

if cfg.enabled ~= false then
    M.start()
end

return M
