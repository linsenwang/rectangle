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
    saveWindowState(win)
    
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
    saveWindowState(win)
    
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
    setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, max.h * 0.5))
end)

-- 下半屏（已禁用）
-- hs.hotkey.bind(mash, "down", function()
--     local win = hs.window.focusedWindow()
--     if not win then return end
--     saveWindowState(win)
--     local max = getWinScreen(win)
--     local area = getUsableArea(max)
--     setWinFrame(win, hs.geometry.rect(area.x, area.y + max.h * 0.5, area.w, max.h * 0.5))
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
    setWinFrame(win, hs.geometry.rect(
        max.x + m.left + gap, max.y + gap,
        max.w - m.left - m.right - gap * 2, max.h - gap * 2
    ))
end)

-- 最大化高度
hs.hotkey.bind(mashShift, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x, max.y, frame.w, max.h))
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
    local h = max.h / 2
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
    local h = max.h / 2
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
    local h = max.h / 2
    local y = area.y + max.h / 2
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
    local h = max.h / 2
    local x = area.x + (area.w + m.inner) / 2
    local y = area.y + max.h / 2
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
-- 窗口移动（不改变大小）
-- ============================================

local moveStep = 50  -- 移动步长

-- 窗口移动（微调位置，使用 Cmd + Option + 方向键）
local moveKey = {"cmd", "alt"}

hs.hotkey.bind(moveKey, "left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x - moveStep, frame.y, frame.w, frame.h))
end)

hs.hotkey.bind(moveKey, "right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x + moveStep, frame.y, frame.w, frame.h))
end)

hs.hotkey.bind(moveKey, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x, frame.y - moveStep, frame.w, frame.h))
end)

hs.hotkey.bind(moveKey, "down", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x, frame.y + moveStep, frame.w, frame.h))
end)

-- ============================================
-- 调整窗口大小
-- ============================================

local resizeStep = 50

hs.hotkey.bind(mash, "=", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    local max = getWinScreen(win)
    local newW = math.min(frame.w + resizeStep, max.w)
    local newH = math.min(frame.h + resizeStep, max.h)
    setWinFrame(win, hs.geometry.rect(frame.x, frame.y, newW, newH))
end)

hs.hotkey.bind(mash, "-", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    local newW = math.max(frame.w - resizeStep, 200)
    local newH = math.max(frame.h - resizeStep, 200)
    setWinFrame(win, hs.geometry.rect(frame.x, frame.y, newW, newH))
end)

-- ============================================
-- 显示器切换
-- ============================================

hs.hotkey.bind(mashShift, "right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    win:moveOneScreenEast()
end)

hs.hotkey.bind(mashShift, "left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    win:moveOneScreenWest()
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

-- 检测窗口当前的布局模式
local function detectLayoutMode(win)
    local screen = win:screen()
    if not screen then return nil end
    local max = screen:frame()
    local frame = win:frame()
    local m = getAppMargin(win)
    local area = getUsableArea(max, win)

    -- 1. 最大化（应用边距）
    if approx(frame.x, area.x, 10) and approx(frame.y, area.y, 10) and
       approx(frame.w, area.w, 10) and approx(frame.h, area.h, 10) then
        return { type = "maximized" }
    end

    -- 2. 全高判断
    local isFullHeight = approx(frame.h, max.h, 10) and approx(frame.y, max.y, 10)

    -- 3. 半屏系列（左/右）
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

    -- 4. 四角（1/4）
    local halfW = (area.w - m.inner) / 2
    local halfH = max.h / 2
    if approx(frame.w, halfW, 30) and approx(frame.h, halfH, 30) then
        if approx(frame.x, area.x, 10) and approx(frame.y, area.y, 10) then return { type = "corner", pos = "tl" } end
        local rightX = area.x + (area.w + m.inner) / 2
        if approx(frame.x, rightX, 10) and approx(frame.y, area.y, 10) then return { type = "corner", pos = "tr" } end
        if approx(frame.x, area.x, 10) and approx(frame.y, area.y + halfH, 10) then return { type = "corner", pos = "bl" } end
        if approx(frame.x, rightX, 10) and approx(frame.y, area.y + halfH, 10) then return { type = "corner", pos = "br" } end
    end

    -- 5. 上半屏
    if approx(frame.x, area.x, 10) and approx(frame.w, area.w, 10) and
       approx(frame.y, area.y, 10) and approx(frame.h, max.h * 0.5, 10) then
        return { type = "top-half" }
    end

    -- 6. 下半屏
    if approx(frame.x, area.x, 10) and approx(frame.w, area.w, 10) and
       approx(frame.y, area.y + max.h * 0.5, 10) and approx(frame.h, max.h * 0.5, 10) then
        return { type = "bottom-half" }
    end

    -- 7. 仅全高（贴边等），记录相对位置
    if isFullHeight then
        local relX = (frame.x - max.x) / max.w
        local relW = frame.w / max.w
        return { type = "full-height", relX = relX, relW = relW }
    end

    return nil
end

-- 在新屏幕上应用布局模式
local function applyLayoutMode(win, mode, screen)
    local max = screen:frame()
    local area = getUsableArea(max, win)
    local m = getAppMargin(win)

    if mode.type == "maximized" then
        setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, area.h))
    elseif mode.type == "left-half" then
        local usableW = max.w - m.left - m.right - m.inner
        local w = usableW * mode.ratio
        setWinFrame(win, hs.geometry.rect(max.x + m.left, area.y, w, area.h))
    elseif mode.type == "right-half" then
        local usableW = max.w - m.left - m.right - m.inner
        local w = usableW * mode.ratio
        local x = max.x + max.w - m.right - w
        setWinFrame(win, hs.geometry.rect(x, area.y, w, area.h))
    elseif mode.type == "third" then
        local thirdW = (area.w - m.inner * 2) / 3
        local xPositions = {
            area.x,
            area.x + thirdW + m.inner,
            area.x + (thirdW + m.inner) * 2
        }
        setWinFrame(win, hs.geometry.rect(xPositions[mode.pos], area.y, thirdW, area.h))
    elseif mode.type == "corner" then
        local halfW = (area.w - m.inner) / 2
        local halfH = max.h / 2
        local x, y
        if mode.pos == "tl" then x, y = area.x, area.y
        elseif mode.pos == "tr" then x, y = area.x + (area.w + m.inner) / 2, area.y
        elseif mode.pos == "bl" then x, y = area.x, area.y + halfH
        elseif mode.pos == "br" then x, y = area.x + (area.w + m.inner) / 2, area.y + halfH
        end
        setWinFrame(win, hs.geometry.rect(x, y, halfW, halfH))
    elseif mode.type == "top-half" then
        setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, max.h * 0.5))
    elseif mode.type == "bottom-half" then
        setWinFrame(win, hs.geometry.rect(area.x, area.y + max.h * 0.5, area.w, max.h * 0.5))
    elseif mode.type == "full-height" then
        local newX = max.x + max.w * mode.relX
        local newW = max.w * mode.relW
        newX = math.max(max.x, math.min(newX, max.x + max.w - newW))
        newW = math.min(newW, max.w)
        setWinFrame(win, hs.geometry.rect(newX, max.y, newW, max.h))
    end
end

-- ============================================
-- 跨显示器移动窗口（保持布局模式）
-- ============================================

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end

    local currentScreen = win:screen()
    if not currentScreen then
        print("[MoveScreen] 未获取到当前屏幕")
        return
    end

    local allScreens = hs.screen.allScreens()
    print(string.format("[MoveScreen] 当前屏幕: %s (id=%d), 总屏幕数: %d", currentScreen:name() or "?", currentScreen:id(), #allScreens))

    if #allScreens < 2 then
        hs.alert.show("只有一个显示器", 1)
        print("[MoveScreen] 只有一个显示器，无法移动")
        return
    end

    -- 找到目标显示器（不是当前显示器的那个）
    local targetScreen = nil
    for _, screen in ipairs(allScreens) do
        local sf = screen:frame()
        print(string.format("[MoveScreen] 候选屏幕: %s (id=%d) frame=%s", screen:name() or "?", screen:id(), hs.inspect(sf)))
        if screen:id() ~= currentScreen:id() then
            targetScreen = screen
            break
        end
    end

    if not targetScreen then
        hs.alert.show("未找到目标显示器", 1)
        print("[MoveScreen] 未找到目标显示器")
        return
    end

    print(string.format("[MoveScreen] 目标屏幕: %s (id=%d)", targetScreen:name() or "?", targetScreen:id()))

    -- 检测当前布局模式
    local mode = detectLayoutMode(win)
    if mode then
        print(string.format("[MoveScreen] 检测到布局模式: %s", hs.inspect(mode)))
    else
        print("[MoveScreen] 未检测到标准布局模式")
    end

    -- 获取当前窗口 frame 用于日志
    local oldFrame = win:frame()
    print(string.format("[MoveScreen] 当前窗口 frame: x=%.0f y=%.0f w=%.0f h=%.0f", oldFrame.x, oldFrame.y, oldFrame.w, oldFrame.h))

    -- 直接用 setFrame 移动窗口到目标屏幕（moveToScreen 在某些应用上不可靠）
    if mode then
        print("[MoveScreen] 有布局模式，直接应用目标屏幕布局")
        applyLayoutMode(win, mode, targetScreen)
    else
        -- 没有标准布局，保持原大小，将窗口中心对准目标屏幕中心
        local targetMax = targetScreen:frame()
        local newX = targetMax.x + (targetMax.w - oldFrame.w) / 2
        local newY = targetMax.y + (targetMax.h - oldFrame.h) / 2
        print(string.format("[MoveScreen] 无布局模式，目标屏幕居中: x=%.0f y=%.0f w=%.0f h=%.0f", newX, newY, oldFrame.w, oldFrame.h))
        setWinFrame(win, hs.geometry.rect(newX, newY, oldFrame.w, oldFrame.h))
    end

    -- 验证最终位置
    local finalFrame = win:frame()
    local finalScreen = win:screen()
    print(string.format("[MoveScreen] 最终窗口 frame: x=%.0f y=%.0f w=%.0f h=%.0f", finalFrame.x, finalFrame.y, finalFrame.w, finalFrame.h))
    if finalScreen then
        print(string.format("[MoveScreen] 最终窗口所在屏幕: %s (id=%d)", finalScreen:name() or "?", finalScreen:id()))
    end
end)

-- ============================================
-- 屏幕切换后自动调整半屏窗口高度
-- ============================================

-- 检测窗口是否是"全高"类型（需要在新屏幕上保持全高）
local function isFullHeightWindow(win)
    local max = win:screen():frame()
    local frame = win:frame()
    local m = getAppMargin(win)

    -- 检测是否是左/右半屏（宽度约为 0.5、2/3、5/6，位置在左/右边缘）
    local isLeftSide = approx(frame.x, max.x, 10) or approx(frame.x, max.x + m.left, 15)
    local isRightSide = approx(frame.x + frame.w, max.x + max.w, 10) or
                        approx(frame.x + frame.w, max.x + max.w - m.right, 15)
    local isHalfWidth = approx(frame.w, max.w * 0.5, 40) or
                        approx(frame.w, max.w * 2/3, 40) or
                        approx(frame.w, max.w * 5/6, 40)

    -- 检测是否是 1/3 分屏
    local thirdW = (max.w - m.left - m.right - m.inner * 2) / 3
    local isThirdWidth = approx(frame.w, thirdW, 30)
    local isThirdLayout = isThirdWidth and (
        approx(frame.x, max.x + m.left, 15) or
        approx(frame.x, max.x + m.left + thirdW + m.inner, 15) or
        approx(frame.x, max.x + m.left + (thirdW + m.inner) * 2, 15)
    )

    -- 如果高度已经约等于屏幕高度，也算（已经是全高了）
    local isAlreadyFullHeight = approx(frame.h, max.h, 10)

    return (isHalfWidth and (isLeftSide or isRightSide)) or isThirdLayout or isAlreadyFullHeight
end

-- 屏幕变化监听器：自动调整窗口高度
local screenChangeWatcher = hs.screen.watcher.new(function()
    hs.timer.doAfter(0.5, function()
        for _, win in ipairs(hs.window.allWindows()) do
            if win:isStandard() then
                local screen = win:screen()
                if screen then
                    local max = screen:frame()
                    local frame = win:frame()

                    -- 只处理那些看起来是"半屏/三分之一屏布局"的窗口
                    if isFullHeightWindow(win) then
                        -- 保持 x、w 不变，调整 y 和 h 使其填满新屏幕
                        if not approx(frame.h, max.h, 10) or not approx(frame.y, max.y, 10) then
                            setWinFrame(win, hs.geometry.rect(frame.x, max.y, frame.w, max.h))
                        end
                    end
                end
            end
        end
    end)
end)
screenChangeWatcher:start()
