-- ============================================
-- Rectangle 核心窗口管理功能
-- 左/右/上/下半屏、最大化、居中、还原、四角、六分之一、三分之一等
-- ============================================

-- ============================================
-- 左右半屏循环
-- ============================================

-- 左半屏循环：只有已经在左半屏位置时才循环
hs.hotkey.bind(mash, "left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    -- 只在窗口不处于任何受管布局时才保存快照，避免循环时覆盖原始位置
    if not detectLayoutMode(win) then
        saveWindowState(win)
    end

    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local frame = win:frame()
    local m = getAppMargin(win)
    
    -- 计算左侧半屏的参考区域（用于检测当前位置）
    local leftHalfWidth = max.w * 0.5
    
    -- 检查是否已经在左侧且宽度是半屏系列（0.5, 2/3, 5/6）
    local isLeftSide = approx(frame.x, max.x, 5) or approx(frame.x, area.x, 10)
    local isHalfWidth = approx(frame.w, area.w * 0.5, 50) or 
                        approx(frame.w, area.w * 2/3, 50) or
                        approx(frame.w, area.w * 5/6, 50)
    
    if isLeftSide and isHalfWidth then
        -- 已经在左半屏，启用循环：1/2 -> 2/3 -> 5/6
        local state = cycleState[id] or 0
        state = state + 1
        if state > 3 then state = 1 end
        cycleState[id] = state
        local widths = {0.5, 2/3, 5/6}
        -- 计算可用宽度：屏幕宽 - 左距 - 中间距 - 右距
        local usableW = max.w - m.left - m.inner - m.right
        local width = usableW * widths[state]
        setWinFrame(win, hs.geometry.rect(max.x + m.left, area.y, width, area.h))
    else
        -- 不在左半屏，先设为 1/2，重置循环
        cycleState[id] = 1
        local usableW = max.w - m.left - m.inner - m.right
        local width = usableW * 0.5
        setWinFrame(win, hs.geometry.rect(max.x + m.left, area.y, width, area.h))
    end
end)

-- 右半屏循环：只有已经在右半屏位置时才循环
hs.hotkey.bind(mash, "right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    -- 只在窗口不处于任何受管布局时才保存快照，避免循环时覆盖原始位置
    if not detectLayoutMode(win) then
        saveWindowState(win)
    end

    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local frame = win:frame()
    local m = getAppMargin(win)
    
    -- 计算可用宽度
    local usableW = max.w - m.left - m.inner - m.right
    local rightEdge = max.x + max.w - m.right
    -- 右半屏三个档位的 x 坐标位置
    local rightXPositions = {
        rightEdge - usableW * 0.5,   -- 第一档
        rightEdge - usableW * 2/3,   -- 第二档
        rightEdge - usableW * 5/6,   -- 第三档
    }
    
    -- 检查是否已经在右侧（x 坐标匹配任意一档）且宽度是半屏系列
    local isRightSide = approx(frame.x, rightXPositions[1], 30) or
                        approx(frame.x, rightXPositions[2], 30) or
                        approx(frame.x, rightXPositions[3], 30)
    local isHalfWidth = approx(frame.w, usableW * 0.5, 50) or 
                        approx(frame.w, usableW * 2/3, 50) or
                        approx(frame.w, usableW * 5/6, 50)
    
    if isRightSide and isHalfWidth then
        -- 已经在右半屏，启用循环：1/2 -> 2/3 -> 5/6
        local state = cycleState[id] or 0
        state = state + 1
        if state > 3 then state = 1 end
        cycleState[id] = state
        local widths = {0.5, 2/3, 5/6}
        -- 计算可用宽度：屏幕宽 - 左距 - 中间距 - 右距
        local usableW = max.w - m.left - m.inner - m.right
        local width = usableW * widths[state]
        -- 右边缘对齐：从屏幕右边缘减去 m.right 往左延伸
        local rightEdge = max.x + max.w - m.right
        local x = rightEdge - width
        setWinFrame(win, hs.geometry.rect(x, area.y, width, area.h))
    else
        -- 不在右半屏，先设为右 1/2，与左窗口对称
        cycleState[id] = 1
        local usableW = max.w - m.left - m.inner - m.right
        local width = usableW * 0.5
        local rightEdge = max.x + max.w - m.right
        local x = rightEdge - width
        setWinFrame(win, hs.geometry.rect(x, area.y, width, area.h))
    end
end)

-- ============================================
-- 上下半屏、最大化、居中、还原
-- ============================================

-- 上半屏
hs.hotkey.bind(mash, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, area.h * 0.5))
end)

-- 下半屏（已禁用）
-- hs.hotkey.bind(mash, "down", function()
--     local win = hs.window.focusedWindow()
--     if not win then return end
--     saveWindowState(win)
--     local max = getWinScreen(win)
--     local area = getUsableArea(max)
--     setWinFrame(win, hs.geometry.rect(area.x, area.y + area.h * 0.5, area.w, area.h * 0.5))
-- end)

-- 最大化（应用边距）
hs.hotkey.bind(mash, "return", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, area.h))
end)

-- 居中（手动计算，无动画，考虑边距）
hs.hotkey.bind(mash, "c", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local frame = win:frame()
    
    -- 在可用区域内居中
    local newX = area.x + (area.w - frame.w) / 2
    local newY = area.y + (area.h - frame.h) / 2
    
    setWinFrame(win, hs.geometry.rect(newX, newY, frame.w, frame.h))
end)

-- 还原（Backspace/Delete 键）
hs.hotkey.bind(mash, "delete", function()
    restoreWindow(hs.window.focusedWindow())
end)

-- 几乎最大化（Almost Maximize）- Ctrl+Opt+L
hs.hotkey.bind(mash, "l", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local gap = 10  -- 几乎最大化的额外边距
    local m = getAppMargin(win)
    local area = getUsableArea(max, win)
    setWinFrame(win, hs.geometry.rect(
        max.x + m.left + gap, area.y + gap,
        max.w - m.left - m.right - gap * 2, area.h - gap * 2
    ))
end)

-- 最大化高度
hs.hotkey.bind(mashShift, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local frame = win:frame()
    local area = getUsableArea(max, win)
    setWinFrame(win, hs.geometry.rect(frame.x, area.y, frame.w, area.h))
end)

-- ============================================
-- 四角和六分之一
-- ============================================

-- 左上
hs.hotkey.bind(mash, "u", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)
    local w = (area.w - m.inner) / 2
    local h = area.h / 2
    setWinFrame(win, hs.geometry.rect(area.x, area.y, w, h))
end)

-- 右上
hs.hotkey.bind(mash, "i", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)
    local w = (area.w - m.inner) / 2
    local h = area.h / 2
    local x = area.x + (area.w + m.inner) / 2
    setWinFrame(win, hs.geometry.rect(x, area.y, w, h))
end)

-- 左下
hs.hotkey.bind(mash, "0", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)
    local w = (area.w - m.inner) / 2
    local h = area.h / 2
    local y = area.y + area.h / 2
    setWinFrame(win, hs.geometry.rect(area.x, y, w, h))
end)

-- 右下
hs.hotkey.bind(mash, "2", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)
    local w = (area.w - m.inner) / 2
    local h = area.h / 2
    local x = area.x + (area.w + m.inner) / 2
    local y = area.y + area.h / 2
    setWinFrame(win, hs.geometry.rect(x, y, w, h))
end)

-- ============================================
-- 三分之一循环
-- ============================================

-- 三分之一循环状态
thirdCycleState = {}

-- 左 1/3 循环：只有在左侧1/3位置时才循环位置（左→中→右）
hs.hotkey.bind(mash, ",", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local frame = win:frame()
    local m = getAppMargin(win)
    
    -- 计算三分之一屏的宽度（扣除中间边距后）
    local thirdW = (area.w - m.inner * 2) / 3
    
    -- 检查是否在左侧（x ≈ 屏幕左边缘）且宽度 ≈ 1/3
    local isLeftSide = approx(frame.x, area.x, 10)
    local isThirdWidth = approx(frame.w, thirdW, 30)
    
    if isLeftSide and isThirdWidth then
        -- 已经在左侧 1/3，循环位置：左(1) -> 中(2) -> 右(3) -> 左(1)
        local state = thirdCycleState[id] or 0
        state = state + 1
        if state > 3 then state = 1 end
        thirdCycleState[id] = state
        
        -- 计算三个位置的x坐标（含中间边距）
        local xPositions = {
            area.x,
            area.x + thirdW + m.inner,
            area.x + (thirdW + m.inner) * 2
        }
        local x = xPositions[state]
        setWinFrame(win, hs.geometry.rect(x, area.y, thirdW, area.h))
    else
        -- 不在左侧 1/3，设为左 1/3，重置循环
        thirdCycleState[id] = 1
        setWinFrame(win, hs.geometry.rect(area.x, area.y, thirdW, area.h))
    end
end)

-- 右 1/3 循环：只有在右侧1/3位置时才反向循环（右→中→左）
hs.hotkey.bind(mash, ".", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)
    local frame = win:frame()
    local m = getAppMargin(win)
    
    -- 计算三分之一屏的宽度（扣除中间边距后）
    local thirdW = (area.w - m.inner * 2) / 3
    
    -- 检查是否在右侧（x + w ≈ 屏幕右边缘）且宽度 ≈ 1/3
    local rightEdge = area.x + area.w
    local isRightSide = approx(frame.x + frame.w, rightEdge, 10)
    local isThirdWidth = approx(frame.w, thirdW, 30)
    
    if isRightSide and isThirdWidth then
        -- 已经在右侧 1/3，反向循环：右(3) -> 中(2) -> 左(1) -> 右(3)
        local state = thirdCycleState[id] or 4  -- 4表示未初始化
        state = state - 1
        if state < 1 then state = 3 end
        thirdCycleState[id] = state
        
        -- 计算三个位置的x坐标（含中间边距）
        local xPositions = {
            area.x,
            area.x + thirdW + m.inner,
            area.x + (thirdW + m.inner) * 2
        }
        local x = xPositions[state]
        setWinFrame(win, hs.geometry.rect(x, area.y, thirdW, area.h))
    else
        -- 不在右侧 1/3，设为右 1/3，设置状态为右(3)
        thirdCycleState[id] = 3
        local x = area.x + (thirdW + m.inner) * 2
        setWinFrame(win, hs.geometry.rect(x, area.y, thirdW, area.h))
    end
end)

-- ============================================
-- 调整窗口大小
-- ============================================

local resizeStep = 50

-- 智能调整窗口宽度：
-- - 居中窗口：左右对称伸缩，总步长仍为 resizeStep
-- - 贴右边缘：向左伸缩，保持右边缘对齐
-- - 其他（默认/左边缘）：向右伸缩，保持左边缘对齐
local function resizeWidth(win, delta)
    local frame = win:frame()
    local max = getWinScreen(win)
    local area = getUsableArea(max, win)

    local centerX = area.x + (area.w - frame.w) / 2
    local isCentered = approx(frame.x, centerX, 20)
    local isRightEdge = approx(frame.x + frame.w, area.x + area.w, 20) or
                        approx(frame.x + frame.w, max.x + max.w, 20)

    local newW
    if delta > 0 then
        newW = math.min(frame.w + delta, area.w)
    else
        newW = math.max(frame.w + delta, 200)
    end
    local actualDelta = newW - frame.w

    local newX
    if isCentered then
        newX = frame.x - actualDelta / 2
    elseif isRightEdge then
        newX = frame.x - actualDelta
    else
        newX = frame.x
    end

    -- 确保不超出可用区域
    newX = math.max(area.x, math.min(newX, area.x + area.w - newW))

    setWinFrame(win, hs.geometry.rect(newX, frame.y, newW, frame.h))
end

hs.hotkey.bind(mash, "=", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    resizeWidth(win, resizeStep)
end)

hs.hotkey.bind(mash, "-", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    resizeWidth(win, -resizeStep)
end)

-- ============================================
-- 显示器切换
-- ============================================

-- 跨屏移动后，按布局属性在新屏幕上重排（避免沿用上一个屏幕的比例）
local function moveToAdjacentScreen(win, east)
    local mode = WindowProfile.getMode(win)
    if east then
        win:moveOneScreenEast()
    else
        win:moveOneScreenWest()
    end
    hs.timer.doAfter(0.15, function()
        pcall(function() WindowProfile.apply(win, mode) end)
    end)
end

hs.hotkey.bind(mashShift, "right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    moveToAdjacentScreen(win, true)
end)

hs.hotkey.bind(mashShift, "left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    moveToAdjacentScreen(win, false)
end)

-- ============================================
-- 窗口贴边（保持高度和宽度不变，贴到屏幕边缘）
-- ============================================

-- 靠在最左（左边贴边，无边距）
hs.hotkey.bind(mash, ";", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local max = getWinScreen(win)
    local frame = win:frame()
    
    -- 移到最左边，保持高度和宽度不变
    setWinFrame(win, hs.geometry.rect(max.x, frame.y, frame.w, frame.h))
end)

-- 靠在最右（右边贴边，无边距）
hs.hotkey.bind(mash, "'", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local max = getWinScreen(win)
    local frame = win:frame()
    
    -- 移到最右边，保持高度和宽度不变
    local newX = max.x + max.w - frame.w
    setWinFrame(win, hs.geometry.rect(newX, frame.y, frame.w, frame.h))
end)
-- ============================================
-- 窗口布局模式检测与应用（跨显示器移动时保持比例）
-- ============================================

-- 判断一组几何形状属于哪种布局模式（窗口可能不在屏幕上，比如 Edge Dock 槽位窗口）
-- @param frame 窗口 frame
-- @param max 屏幕 frame
-- @param win 窗口（用于取应用 / 显示器边距）
function detectLayoutModeForFrame(frame, max, win)
    if not frame or not max then return nil end
    local m = getAppMargin(win)
    local area = getUsableArea(max, win)

    -- 1. 最大化（应用边距）
    if approx(frame.x, area.x, 10) and approx(frame.y, area.y, 10) and
       approx(frame.w, area.w, 10) and approx(frame.h, area.h, 10) then
        return { type = "maximized" }
    end

    -- 2. 居中：水平、垂直都居中，记录相对尺寸
    -- 必须排在半屏/三分之一之前：中间三分之一本身就是居中的，若先判三分之一，
    -- 居中窗口会被记成「中 1/3」，交换位置时对方就被摆到三分之一槽位上（看起来就「歪」了）
    if approx(frame.x + frame.w / 2, area.x + area.w / 2, 20) and
       approx(frame.y + frame.h / 2, area.y + area.h / 2, 20) then
        return { type = "center", relW = frame.w / area.w, relH = frame.h / area.h }
    end

    -- 3. 全高判断
    local isFullHeight = approx(frame.h, area.h, 10) and approx(frame.y, area.y, 10)

    -- 4. 半屏系列（左/右）
    local usableW = max.w - m.left - m.right - m.inner
    local leftEdge = max.x + m.left
    local rightEdge = max.x + max.w - m.right

    if isFullHeight then
        -- 左半屏
        if approx(frame.x, leftEdge, 20) or approx(frame.x, max.x, 10) then
            if approx(frame.w, usableW * 0.5, 50) then return { type = "left-half", ratio = 0.5 } end
            if approx(frame.w, usableW * 2/3, 50) then return { type = "left-half", ratio = 2/3 } end
            if approx(frame.w, usableW * 5/6, 50) then return { type = "left-half", ratio = 5/6 } end
        end

        -- 右半屏
        local isRightEdge = approx(frame.x + frame.w, max.x + max.w, 10) or approx(frame.x + frame.w, rightEdge, 20)
        if isRightEdge then
            if approx(frame.w, usableW * 0.5, 50) then return { type = "right-half", ratio = 0.5 } end
            if approx(frame.w, usableW * 2/3, 50) then return { type = "right-half", ratio = 2/3 } end
            if approx(frame.w, usableW * 5/6, 50) then return { type = "right-half", ratio = 5/6 } end
        end

        -- 三分之一屏
        local thirdW = (area.w - m.inner * 2) / 3
        if approx(frame.w, thirdW, 30) then
            if approx(frame.x, area.x, 15) then return { type = "third", pos = 1 } end
            if approx(frame.x, area.x + thirdW + m.inner, 15) then return { type = "third", pos = 2 } end
            if approx(frame.x, area.x + (thirdW + m.inner) * 2, 15) then return { type = "third", pos = 3 } end
        end
    end

    -- 5. 四角（1/4）
    local halfW = (area.w - m.inner) / 2
    local halfH = area.h / 2
    if approx(frame.w, halfW, 30) and approx(frame.h, halfH, 30) then
        if approx(frame.x, area.x, 10) and approx(frame.y, area.y, 10) then return { type = "corner", pos = "tl" } end
        local rightX = area.x + (area.w + m.inner) / 2
        if approx(frame.x, rightX, 10) and approx(frame.y, area.y, 10) then return { type = "corner", pos = "tr" } end
        if approx(frame.x, area.x, 10) and approx(frame.y, area.y + halfH, 10) then return { type = "corner", pos = "bl" } end
        if approx(frame.x, rightX, 10) and approx(frame.y, area.y + halfH, 10) then return { type = "corner", pos = "br" } end
    end

    -- 6. 上半屏
    if approx(frame.x, area.x, 10) and approx(frame.w, area.w, 10) and
       approx(frame.y, area.y, 10) and approx(frame.h, area.h * 0.5, 10) then
        return { type = "top-half" }
    end

    -- 7. 下半屏
    if approx(frame.x, area.x, 10) and approx(frame.w, area.w, 10) and
       approx(frame.y, area.y + area.h * 0.5, 10) and approx(frame.h, area.h * 0.5, 10) then
        return { type = "bottom-half" }
    end

    -- 8. 仅全高（贴边等），记录相对位置
    if isFullHeight then
        local relX = (frame.x - max.x) / max.w
        local relW = frame.w / max.w
        return { type = "full-height", relX = relX, relW = relW }
    end

    return nil
end

-- 检测窗口当前的布局模式
function detectLayoutMode(win)
    local screen = win:screen()
    if not screen then return nil end
    return detectLayoutModeForFrame(win:frame(), screen:frame(), win)
end

-- 计算某种布局模式在指定屏幕上的 frame（只计算不移动窗口，Edge Dock 槽位窗口也用它）
-- @param max 屏幕 frame
-- @param win 窗口（用于取应用 / 显示器边距）
function layoutFrameFor(mode, max, win)
    if not mode or not max then return nil end
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)

    if mode.type == "maximized" then
        return hs.geometry.rect(area.x, area.y, area.w, area.h)
    elseif mode.type == "left-half" then
        local usableW = max.w - m.left - m.right - m.inner
        local w = usableW * mode.ratio
        return hs.geometry.rect(max.x + m.left, area.y, w, area.h)
    elseif mode.type == "right-half" then
        local usableW = max.w - m.left - m.right - m.inner
        local w = usableW * mode.ratio
        local x = max.x + max.w - m.right - w
        return hs.geometry.rect(x, area.y, w, area.h)
    elseif mode.type == "third" then
        local thirdW = (area.w - m.inner * 2) / 3
        local xPositions = {
            area.x,
            area.x + thirdW + m.inner,
            area.x + (thirdW + m.inner) * 2
        }
        return hs.geometry.rect(xPositions[mode.pos], area.y, thirdW, area.h)
    elseif mode.type == "corner" then
        local halfW = (area.w - m.inner) / 2
        local halfH = area.h / 2
        local x, y
        if mode.pos == "tl" then x, y = area.x, area.y
        elseif mode.pos == "tr" then x, y = area.x + (area.w + m.inner) / 2, area.y
        elseif mode.pos == "bl" then x, y = area.x, area.y + halfH
        elseif mode.pos == "br" then x, y = area.x + (area.w + m.inner) / 2, area.y + halfH
        end
        return hs.geometry.rect(x, y, halfW, halfH)
    elseif mode.type == "top-half" then
        return hs.geometry.rect(area.x, area.y, area.w, area.h * 0.5)
    elseif mode.type == "bottom-half" then
        return hs.geometry.rect(area.x, area.y + area.h * 0.5, area.w, area.h * 0.5)
    elseif mode.type == "full-height" then
        local newX = max.x + max.w * mode.relX
        local newW = max.w * mode.relW
        newX = math.max(max.x, math.min(newX, max.x + max.w - newW))
        newW = math.min(newW, max.w)
        return hs.geometry.rect(newX, area.y, newW, area.h)
    elseif mode.type == "center" then
        -- 在可用区域内居中，尺寸按记录的比例缩放
        local w = math.min(mode.relW * area.w, area.w)
        local h = math.min(mode.relH * area.h, area.h)
        return hs.geometry.rect(area.x + (area.w - w) / 2, area.y + (area.h - h) / 2, w, h)
    elseif mode.type == "free" then
        -- 自由：按相对整块屏幕的比例平移缩放
        local w = math.min(mode.relW * max.w, max.w)
        local h = math.min(mode.relH * max.h, max.h)
        local x = math.max(max.x, math.min(max.x + mode.relX * max.w, max.x + max.w - w))
        local y = math.max(max.y, math.min(max.y + mode.relY * max.h, max.y + max.h - h))
        return hs.geometry.rect(x, y, w, h)
    end

    return nil
end

-- 在新屏幕上应用布局模式（window_profile 按窗口属性重排时也会调用）
function applyLayoutMode(win, mode, screen)
    local frame = layoutFrameFor(mode, screen:frame(), win)
    if frame then setWinFrame(win, frame) end
end

-- ============================================
-- 跨显示器移动窗口（保持布局模式）
-- ============================================

-- 获取当前屏幕的下一个屏幕（按 x 坐标排序，支持 3 屏以上循环切换）
local function getNextScreen(currentScreen)
    local allScreens = hs.screen.allScreens()
    if #allScreens < 2 then return nil end
    table.sort(allScreens, function(a, b)
        local af = a:frame()
        local bf = b:frame()
        return af.x < bf.x
    end)

    local currentId = currentScreen:id()
    local found = false
    for _, screen in ipairs(allScreens) do
        if found then
            return screen
        end
        if screen:id() == currentId then
            found = true
        end
    end
    -- 当前屏幕是最右时，回到最左
    return allScreens[1]
end

-- 跨显示器移动窗口（保持布局模式）
local function moveToOtherScreen()
    local win = hs.window.focusedWindow()
    if not win then return end

    local currentScreen = win:screen()
    if not currentScreen then
        print("[MoveScreen] 未获取到当前屏幕")
        return
    end

    local targetScreen = getNextScreen(currentScreen)
    if not targetScreen then
        hs.alert.show("只有一个显示器", 1)
        return
    end

    -- 检测当前布局模式
    local mode = detectLayoutMode(win)
    local oldFrame = win:frame()

    -- 直接用 setFrame 移动窗口到目标屏幕（moveToScreen 在某些应用上不可靠）
    if mode then
        applyLayoutMode(win, mode, targetScreen)
    else
        -- 没有标准布局，保持原大小，将窗口中心对准目标屏幕中心
        local targetMax = targetScreen:frame()
        local newX = targetMax.x + (targetMax.w - oldFrame.w) / 2
        local newY = targetMax.y + (targetMax.h - oldFrame.h) / 2
        setWinFrame(win, hs.geometry.rect(newX, newY, oldFrame.w, oldFrame.h))
    end

    print(string.format("[MoveScreen] 已移动到 %s", targetScreen:name() or "?"))
end

-- Ctrl+Alt+Cmd + ↓：跨显示器移动（保持布局模式）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "down", moveToOtherScreen)

-- ============================================
-- 屏幕变化后的窗口重排
-- ============================================
-- 以前这里只把「看起来是全高」的窗口高度补满新屏幕，宽度仍沿用旧屏幕的像素值。
-- 现在统一交给 lib/window_profile.lua：每个窗口记录布局属性（半屏 / 居中 / 1/3 ...），
-- 显示器变化后按属性在新屏幕上重新计算，自由窗口则按屏幕相对比例适配。

-- ============================================
-- 与上一个焦点窗口交换位置与前后层次（大小不变）
-- ============================================

local previousFocusedWindow = nil
local currentFocusedWindow = nil

-- 监听焦点变化，记录上一个焦点窗口，并让 focusedWindow 缓存失效
local swapFilter = hs.window.filter.new(true)
swapFilter:subscribe(hs.window.filter.windowFocused, function(win)
    -- 焦点变化时使 hs.window.focusedWindow 缓存失效（定义于 config.lua）
    if _G.invalidateFocusedWindowCache then
        _G.invalidateFocusedWindowCache()
    end
    if win and win ~= currentFocusedWindow then
        previousFocusedWindow = currentFocusedWindow
        currentFocusedWindow = win
    end
end)

-- 取窗口的布局属性：优先按当前几何识别（识别不出时才用 lib/window_profile.lua 里
-- 切换屏幕时保存的属性），仍识别不出就按屏幕相对比例当作「自由」
-- 注意顺序：WindowProfile 的记录有 0.4s 防抖，刚交换完马上再按一次时记录还是旧的，
-- 若优先用记录，第二次计算出的位置和第一次一样，看起来就像「第二次没反应」
local function layoutModeOf(win)
    local mode = detectLayoutMode(win)
    if mode then return mode end

    if WindowProfile and WindowProfile.getMode then
        mode = WindowProfile.getMode(win)
        if mode then return mode end
    end

    local screen = win:screen()
    local frame = win:frame()
    if not screen or not frame then return nil end
    local max = screen:frame()
    return {
        type = "free",
        relX = (frame.x - max.x) / max.w,
        relY = (frame.y - max.y) / max.h,
        relW = frame.w / max.w,
        relH = frame.h / max.h,
    }
end

-- 按布局属性求该属性对应的「位置」（左上角坐标）
-- 尺寸由调用方传入窗口自己的 w/h：只取位置，大小不动；
-- 坐标基于可用区域，并保证窗口不会越出可用区域
local function positionForMode(mode, max, win, w, h)
    if not mode or not max then return nil end
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)
    local t = mode.type
    local x, y = area.x, area.y

    if t == "right-half" then
        x = area.x + area.w - w
    elseif t == "third" then
        local thirdW = (area.w - m.inner * 2) / 3
        x = area.x + (thirdW + m.inner) * ((mode.pos or 1) - 1)
    elseif t == "corner" then
        if mode.pos == "tr" or mode.pos == "br" then
            x = area.x + (area.w + m.inner) / 2
        end
        if mode.pos == "bl" or mode.pos == "br" then
            y = area.y + area.h - h
        end
    elseif t == "full-height" or t == "free" then
        x = max.x + max.w * (mode.relX or 0)
        if t == "free" then
            y = max.y + max.h * (mode.relY or 0)
        end
    elseif t == "center" then
        x = area.x + (area.w - w) / 2
        y = area.y + (area.h - h) / 2
    elseif t == "bottom-half" then
        y = area.y + area.h - h
    end

    x = math.max(area.x, math.min(x, area.x + area.w - w))
    y = math.max(area.y, math.min(y, area.y + area.h - h))
    return x, y
end

-- 窗口在当前屏幕上的前后顺序（1 = 最前）；不在层叠列表里返回 nil
local function zOrderIndex(win)
    local ok, list = pcall(hs.window.orderedWindows)
    if not ok or not list then return nil end
    local id = win:id()
    if not id then return nil end
    for i, w in ipairs(list) do
        if w:id() == id then return i end
    end
    return nil
end

local function swapWithPreviousWindow()
    local win = hs.window.focusedWindow()
    if not win then
        hs.alert.show("没有当前窗口", 1)
        return
    end

    local prev = previousFocusedWindow
    local ok, isPrevValid = pcall(function()
        return prev and prev:isStandard()
    end)
    if not ok or not isPrevValid then
        hs.alert.show("没有上一个焦点窗口", 1)
        return
    end

    if prev:id() == win:id() then
        hs.alert.show("没有可交换的窗口", 1)
        return
    end

    -- 只在同一屏幕内交换，避免跨屏幕坐标混乱
    local screen1 = win:screen()
    local screen2 = prev:screen()
    if not screen1 or not screen2 or screen1:id() ~= screen2:id() then
        hs.alert.show("窗口不在同一屏幕，无法交换", 1)
        return
    end

    local frame1 = win:frame()
    local frame2 = prev:frame()
    local max = screen1:frame()

    -- 前后关系（谁在前面）也要交换：先记下当前层叠顺序，原来看不到的窗口换到前面
    local z1, z2 = zOrderIndex(win), zOrderIndex(prev)
    local toFront = nil
    if z1 and z2 and z1 ~= z2 then
        toFront = (z1 > z2) and win or prev
    end

    -- 只交换位置：位置取对方「切换屏幕时保存的布局属性」对应的槽位（左半屏 / 居中 ...），
    -- 大小保持各自原来的 w/h 不变；属性识别不出时退回直接交换左上角坐标
    local x1, y1 = positionForMode(layoutModeOf(prev), max, win, frame1.w, frame1.h)
    local x2, y2 = positionForMode(layoutModeOf(win), max, prev, frame2.w, frame2.h)
    if not x1 then x1, y1 = frame2.x, frame2.y end
    if not x2 then x2, y2 = frame1.x, frame1.y end

    -- 保存状态以便还原
    saveWindowState(win)
    saveWindowState(prev)

    local newFrame1 = hs.geometry.rect(x1, y1, frame1.w, frame1.h)
    local newFrame2 = hs.geometry.rect(x2, y2, frame2.w, frame2.h)
    setWinFrame(win, newFrame1)
    setWinFrame(prev, newFrame2)

    if toFront then
        -- 换成前面，并让它持有焦点，避免看得见的是前面那个、按键却落到后面那个
        pcall(function() toFront:raise() end)
        pcall(function() toFront:focus() end)
    end
end

-- Ctrl+Option + X：与上一个焦点窗口交换位置与前后层次（大小不变）
hs.hotkey.bind(mash, "x", swapWithPreviousWindow)
