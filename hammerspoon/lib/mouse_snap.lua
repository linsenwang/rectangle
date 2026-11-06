-- ============================================
-- 鼠标贴边吸附（Rectangle 风格拖拽）
--
-- 拖动窗口时：
--   左右边缘 -> 半屏
--   四角     -> 1/4 屏
--   顶部     -> 左 1/3 / 左 2/3 / 居中 2/3 / 右 2/3 / 右 1/3
--               （按鼠标水平位置决定，详见 topStripZone）
--
-- 顶部判定用「窗口上沿」而不是鼠标 Y 坐标：
--   窗口上沿顶到可用区上沿（菜单栏下方）时触发，
--   这样抓住标题栏任意位置拖上去都能触发，不需要把鼠标推进菜单栏。
--
-- 性能要点：
--   1. 不监听 leftMouseDragged。拖动事件全部交给系统原生处理，
--      避免每个事件同步穿过 Lua 桥导致掉帧。
--   2. 用 60Hz 定时器轮询鼠标位置和按键，空闲时不读鼠标位置。
--   3. 拖动过程中只画 hs.canvas 预览，松开鼠标时才真正设置窗口 frame。
--   4. 窗口 frame 只在需要确认「真的在拖窗口」和「是否到顶」时读取，
--      并做 80ms 节流。
-- ============================================

local M = {}

local cfg = MouseSnapConfig or {}
local EDGE = cfg.edgeSize or 24
local TOP_BAND = cfg.topBand or 160
local TOP_WINDOW_MARGIN = cfg.topWindowMargin or 20
local CORNER_RATIO = cfg.cornerRatio or 0.08
local MIN_DRAG = cfg.minDrag or 20
local MIN_FRAME_CHANGE = cfg.minFrameChange or 8
local TITLE_BAR_MAX = cfg.titleBarMax or 100
local FRAME_CHECK_INTERVAL = 0.08
local APPLY_DELAY = 0.08
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
-- frame 是可见区域（菜单栏下方），用于布局；hitFrame 是全屏区域，用于鼠标命中判断
local function collectScreens(win)
    local screens = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local ok, frame = pcall(function() return screen:frame() end)
        local okFull, full = pcall(function() return screen:fullFrame() end)
        if ok and frame then
            screens[#screens + 1] = {
                screen = screen,
                frame = frame,
                hitFrame = okFull and full or frame,
                area = getUsableArea(frame, win),
            }
        end
    end
    return screens
end

local function entryAtPoint(point, screens)
    for _, entry in ipairs(screens) do
        if pointInFrame(point, entry.hitFrame or entry.frame) then return entry end
    end
    return nil
end

-- ============================================
-- 吸附区域判断（纯 Lua）
-- ============================================

-- 顶部横向分区（按可用区宽度）：
--   最左 1/6      -> 左 1/3
--   左 1/6 ~ 1/3  -> 左 2/3
--   中间 1/3      -> 居中 2/3
--   右 1/3 ~ 5/6  -> 右 2/3
--   最右 1/6      -> 右 1/3
local function topStripZone(point, entry)
    local area = entry.area
    local rel = (point.x - area.x) / area.w
    if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end

    if rel < 1 / 6 then
        return { type = "third", pos = 1, isTop = true }
    elseif rel < 1 / 3 then
        return { type = "left-half", ratio = 2 / 3, isTop = true }
    elseif rel <= 2 / 3 then
        return { type = "center-two-thirds", isTop = true }
    elseif rel <= 5 / 6 then
        return { type = "right-half", ratio = 2 / 3, isTop = true }
    else
        return { type = "third", pos = 3, isTop = true }
    end
end

local function zoneKey(zone)
    if not zone then return nil end
    return zone.type .. "|" .. tostring(zone.pos) .. "|" .. tostring(zone.ratio)
end

local function zoneAt(point, screens)
    for _, entry in ipairs(screens) do
        local frame = entry.frame
        if pointInFrame(point, entry.hitFrame or frame) then
            local area = entry.area
            local nearLeft = point.x <= frame.x + EDGE
            local nearRight = point.x >= frame.x + frame.w - EDGE

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

local function initDrag(point, now)
    local win = windowAtPoint(point)
    if not win then return nil end

    local ok, frame = pcall(function() return win:frame() end)
    if not ok or not frame then return nil end

    local screens = collectScreens(win)

    -- 鼠标按下点距离窗口上沿很近 → 认为抓的是标题栏。
    -- 窗口贴顶拖不动时，用它来区分「拖窗口」和「选文字/拖文件」。
    local grabOffsetY = point.y - frame.y
    local titleBarDrag = grabOffsetY >= 0 and grabOffsetY <= TITLE_BAR_MAX

    return {
        win = win,
        initialized = true,
        baseFrame = frame,
        currentFrame = frame,
        frameTime = now,
        screens = screens,
        titleBarDrag = titleBarDrag,
        armed = false,
        invalid = false,
    }
end

-- 读取窗口 frame，80ms 内复用缓存
local function getFrame(st, now, force)
    if force or not st.frameTime or now - st.frameTime >= FRAME_CHECK_INTERVAL then
        local ok, frame = pcall(function() return st.win:frame() end)
        if not ok or not frame then
            st.invalid = true
            return nil
        end
        st.currentFrame = frame
        st.frameTime = now
    end
    return st.currentFrame
end

-- 确认窗口真的被移动（而不是选文字/拖文件）：位置变化且尺寸基本不变
local function frameChanged(st, frame)
    local base = st.baseFrame
    local moved = math.abs(frame.x - base.x) > MIN_FRAME_CHANGE
               or math.abs(frame.y - base.y) > MIN_FRAME_CHANGE
    local resized = math.abs(frame.w - base.w) > MIN_FRAME_CHANGE
                 or math.abs(frame.h - base.h) > MIN_FRAME_CHANGE
    return moved, resized
end

local function shouldArm(st, now, zone)
    if st.armed or st.invalid then return end

    local frame = getFrame(st, now)
    if not frame then return end

    local moved, resized = frameChanged(st, frame)
    if resized then
        st.invalid = true
        return
    end
    -- 窗口已经贴顶时拖不动；只要抓的是标题栏、并且当前是顶部区域，也算在拖窗口
    if moved or (st.titleBarDrag and zone and zone.isTop) then
        st.armed = true
    end
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
    if not target then return end

    setWinFrame(win, target)

    -- 原生拖动刚结束时，macOS/应用偶尔只接受位置、不接受尺寸。
    -- 稍后回读校验，尺寸不对就补一次（拖动会话可能结束得比较晚，校验两次）。
    local function verify(delay)
        hs.timer.doAfter(delay, function()
            if not isEligible(win) then return end
            local okNow, nowFrame = pcall(function() return win:frame() end)
            if not okNow or not nowFrame then return end

            local atTarget = math.abs(nowFrame.x - target.x) <= 8
                         and math.abs(nowFrame.y - target.y) <= 8
            local sizeOK = math.abs(nowFrame.w - target.w) <= 4
                       and math.abs(nowFrame.h - target.h) <= 4
            if atTarget and not sizeOK then
                setWinFrame(win, target)
            end
        end)
    end
    verify(0.15)
    verify(0.35)
end

-- ============================================
-- 轮询状态机
-- ============================================

-- 计算当前鼠标位置对应的吸附区域。顶部区域需要看窗口上沿，
-- forceFrame=true 时强制读最新 frame（用于松手时的最终判定）。
local function resolveZone(st, point, now, forceFrame)
    local zone, entry = zoneAt(point, st.screens)

    -- 左右边缘/四角优先；顶部只在不靠近左右边缘时生效
    if zone or not entry then return zone, entry end

    -- 和左右边缘一样只看鼠标位置：进入顶部区域、且窗口上沿已经贴近顶部
    if point.y <= entry.area.y + TOP_BAND then
        local frame = getFrame(st, now, forceFrame)
        if frame and frame.y <= entry.area.y + TOP_WINDOW_MARGIN then
            zone = topStripZone(point, entry)
        end
    end
    return zone, entry
end

local function finishDrag(st, point)
    if not st or not st.initialized or st.invalid then return end

    -- 鼠标移动很快时可能还没通过节流检查，这里强制读一次最新 frame
    local now = hs.timer.secondsSinceEpoch()
    local frame = getFrame(st, now, true)
    if not frame then return end

    -- 用松手时的实际位置重算区域，避免最后 80ms 内刚好跨过顶部的判定被漏掉
    local zone, entry = resolveZone(st, point, now, false)
    if not zone or not entry then return end
    st.zone, st.entry = zone, entry

    local moved, resized = frameChanged(st, frame)
    if not st.armed then
        if resized then return end
        -- 窗口已经贴顶时拖不动，抓的是标题栏并且当前在顶部区域也算有效拖动
        if not moved and not (st.titleBarDrag and zone.isTop) then return end
    elseif resized then
        return
    end

    local win = st.win
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
            local point = hs.mouse.absolutePosition()
            resetState()
            finishDrag(st, point)
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

    local now = hs.timer.secondsSinceEpoch()

    if not st.initialized then
        local dx = point.x - st.down.x
        local dy = point.y - st.down.y
        if dx * dx + dy * dy < MIN_DRAG * MIN_DRAG then return end

        local dragState = initDrag(point, now)
        if not dragState then
            st.invalid = true
            return
        end
        dragState.down = st.down
        state = dragState
        st = dragState
    end

    local zone, entry = resolveZone(st, point, now, false)

    local wasArmed = st.armed
    if zone then
        shouldArm(st, now, zone)
    end

    if not zone then
        if st.zone ~= nil then
            st.zone, st.entry, st.zoneKey = nil, entry, nil
            hidePreview()
        end
    elseif st.invalid then
        hidePreview()
    else
        local key = zoneKey(zone)
        if key ~= st.zoneKey or entry ~= st.entry or (st.armed and not wasArmed) then
            st.zone, st.entry, st.zoneKey = zone, entry, key
            updatePreview(st, zone, entry)
        end
    end
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
