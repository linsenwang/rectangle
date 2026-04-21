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
