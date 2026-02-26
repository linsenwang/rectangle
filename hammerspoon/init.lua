-- ============================================
-- Rectangle 风格窗口管理器配置
-- 主修饰键：Ctrl + Option
-- ============================================

-- 禁用窗口动画
hs.window.animationDuration = 0

-- 配置文件路径
local CONFIG_PATH = os.getenv("HOME") .. "/.hammerspoon/"

-- Edge Dock 状态文件路径
local EDGEDOCK_STATE_FILE = CONFIG_PATH .. "edge_dock_state.json"

-- ============================================
-- 修饰键定义
-- ============================================

local mash = {"ctrl", "alt"}           -- 主修饰键：Ctrl + Option
local mashShift = {"ctrl", "alt", "shift"}  -- Ctrl + Option + Shift

-- ============================================
-- 边距配置
-- ============================================

local margin = {
    left = 40,       -- 左侧边距（距离屏幕左边缘）
    right = 11,      -- 右侧边距（距离屏幕右边缘）
    inner = 40,      -- 中间边距（窗口之间的空隙）
}

-- 计算屏幕可用区域（扣除边距后的区域）
function getUsableArea(max)
    return {
        x = max.x + margin.left,
        y = max.y,
        w = max.w - margin.left - margin.right,
        h = max.h
    }
end

-- ============================================
-- 工具函数
-- ============================================

function notify(title, message)
    hs.notify.new({title = title, informativeText = message}):send()
end

-- 快速设置窗口 frame（无动画，解决 AXEnhancedUserInterface 问题）
function setWinFrame(win, rect)
    if not win or not win.isStandard or not win:isStandard() then return end
    
    local axApp = hs.axuielement.applicationElement(win:application())
    local wasEnhanced = axApp.AXEnhancedUserInterface
    if wasEnhanced then
        axApp.AXEnhancedUserInterface = false
    end
    
    win:setFrame(rect, 0)
    
    if wasEnhanced then
        axApp.AXEnhancedUserInterface = true
    end
end

-- 获取当前窗口和屏幕信息
function getWinScreen(win)
    if not win then return nil, nil end
    local screen = win:screen()
    return screen:frame(), screen
end

-- ============================================
-- Rectangle 核心功能
-- ============================================

-- 存储还原信息（每个窗口）
local windowHistory = {}

-- 循环状态记录：每个窗口的左右半屏循环状态
local cycleState = {}

-- 保存窗口原始状态
function saveWindowState(win)
    if not win then return end
    local id = win:id()
    if id then
        windowHistory[id] = win:frame()
    end
end

-- 还原窗口
function restoreWindow(win)
    if not win then return end
    local id = win:id()
    if id and windowHistory[id] then
        setWinFrame(win, windowHistory[id])
        windowHistory[id] = nil
        cycleState[id] = nil  -- 清除循环状态
    end
end

-- 辅助函数：检查值是否在范围内
local function approx(a, b, tolerance)
    tolerance = tolerance or 10
    return math.abs(a - b) < tolerance
end

-- 左半屏循环：只有已经在左半屏位置时才循环
hs.hotkey.bind(mash, "left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max)
    local frame = win:frame()
    
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
        local usableW = max.w - margin.left - margin.inner - margin.right
        local width = usableW * widths[state]
        setWinFrame(win, hs.geometry.rect(max.x + margin.left, area.y, width, area.h))
    else
        -- 不在左半屏，先设为 1/2，重置循环
        cycleState[id] = 1
        local usableW = max.w - margin.left - margin.inner - margin.right
        local width = usableW * 0.5
        setWinFrame(win, hs.geometry.rect(max.x + margin.left, area.y, width, area.h))
    end
end)

-- 右半屏循环：只有已经在右半屏位置时才循环
hs.hotkey.bind(mash, "right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max)
    local frame = win:frame()
    
    -- 计算可用宽度
    local usableW = max.w - margin.left - margin.inner - margin.right
    local rightEdge = max.x + max.w - margin.right
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
        local usableW = max.w - margin.left - margin.inner - margin.right
        local width = usableW * widths[state]
        -- 右边缘对齐：从屏幕右边缘减去 margin.right 往左延伸
        local rightEdge = max.x + max.w - margin.right
        local x = rightEdge - width
        setWinFrame(win, hs.geometry.rect(x, area.y, width, area.h))
    else
        -- 不在右半屏，先设为右 1/2，与左窗口对称
        cycleState[id] = 1
        local usableW = max.w - margin.left - margin.inner - margin.right
        local width = usableW * 0.5
        local rightEdge = max.x + max.w - margin.right
        local x = rightEdge - width
        setWinFrame(win, hs.geometry.rect(x, area.y, width, area.h))
    end
end)

-- 上半屏
hs.hotkey.bind(mash, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max)
    setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, max.h * 0.5))
end)

-- 下半屏
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
    local area = getUsableArea(max)
    setWinFrame(win, hs.geometry.rect(area.x, area.y, area.w, area.h))
end)

-- 居中（手动计算，无动画）
hs.hotkey.bind(mash, "c", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local max = getWinScreen(win)
    local frame = win:frame()
    
    -- 计算居中位置
    local newX = max.x + (max.w - frame.w) / 2
    local newY = max.y + (max.h - frame.h) / 2
    
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
    setWinFrame(win, hs.geometry.rect(
        max.x + margin.left + gap, max.y + gap,
        max.w - margin.left - margin.right - gap * 2, max.h - gap * 2
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
    local area = getUsableArea(max)
    local w = (area.w - margin.inner) / 2
    local h = max.h / 2
    setWinFrame(win, hs.geometry.rect(area.x, area.y, w, h))
end)

-- 右上
hs.hotkey.bind(mash, "i", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max)
    local w = (area.w - margin.inner) / 2
    local h = max.h / 2
    local x = area.x + (area.w + margin.inner) / 2
    setWinFrame(win, hs.geometry.rect(x, area.y, w, h))
end)

-- 左下
hs.hotkey.bind(mash, "0", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local area = getUsableArea(max)
    local w = (area.w - margin.inner) / 2
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
    local area = getUsableArea(max)
    local w = (area.w - margin.inner) / 2
    local h = max.h / 2
    local x = area.x + (area.w + margin.inner) / 2
    local y = area.y + max.h / 2
    setWinFrame(win, hs.geometry.rect(x, y, w, h))
end)

-- 三分之一循环状态
local thirdCycleState = {}

-- 左 1/3 循环：只有在左侧1/3位置时才循环位置（左→中→右）
hs.hotkey.bind(mash, ",", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    
    local id = win:id()
    local max = getWinScreen(win)
    local area = getUsableArea(max)
    local frame = win:frame()
    
    -- 计算三分之一屏的宽度（扣除中间边距后）
    local thirdW = (area.w - margin.inner * 2) / 3
    
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
            area.x + thirdW + margin.inner,
            area.x + (thirdW + margin.inner) * 2
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
    local area = getUsableArea(max)
    local frame = win:frame()
    
    -- 计算三分之一屏的宽度（扣除中间边距后）
    local thirdW = (area.w - margin.inner * 2) / 3
    
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
            area.x + thirdW + margin.inner,
            area.x + (thirdW + margin.inner) * 2
        }
        local x = xPositions[state]
        setWinFrame(win, hs.geometry.rect(x, area.y, thirdW, area.h))
    else
        -- 不在右侧 1/3，设为右 1/3，设置状态为右(3)
        thirdCycleState[id] = 3
        local x = area.x + (thirdW + margin.inner) * 2
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
-- 高级功能：保存/恢复布局
-- ============================================

local LayoutManager = {}
LayoutManager.savedLayouts = {}

function LayoutManager.save(name)
    local layout = {}
    local windows = hs.window.allWindows()
    
    for _, win in ipairs(windows) do
        if win:isStandard() then
            local app = win:application()
            if app then
                local frame = win:frame()
                table.insert(layout, {
                    app = app:name(),
                    title = win:title(),
                    x = frame.x, y = frame.y,
                    w = frame.w, h = frame.h,
                    screenId = win:screen():id()
                })
            end
        end
    end
    
    LayoutManager.savedLayouts[name] = layout
    
    local file = io.open(CONFIG_PATH .. "layout_" .. name .. ".json", "w")
    if file then
        file:write(hs.json.encode(layout))
        file:close()
    end
    
    notify("布局保存", name .. " (" .. #layout .. " 个窗口)")
end

function LayoutManager.restore(name)
    if not LayoutManager.savedLayouts[name] then
        local file = io.open(CONFIG_PATH .. "layout_" .. name .. ".json", "r")
        if file then
            local content = file:read("*all")
            file:close()
            LayoutManager.savedLayouts[name] = hs.json.decode(content)
        end
    end
    
    local layout = LayoutManager.savedLayouts[name]
    if not layout then
        notify("恢复失败", "布局 '" .. name .. "' 不存在")
        return
    end
    
    for _, item in ipairs(layout) do
        local app = hs.application.get(item.app)
        if app then
            for _, win in ipairs(app:allWindows()) do
                if win:title() == item.title and win:isStandard() then
                    setWinFrame(win, hs.geometry.rect(item.x, item.y, item.w, item.h))
                    break
                end
            end
        end
    end
    
    notify("布局恢复", name)
end

-- 保存/恢复布局快捷键
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "s", function()
    local button, name = hs.dialog.textPrompt("保存布局", "名称:", "work", "保存", "取消")
    if button == "保存" and name ~= "" then
        LayoutManager.save(name)
    end
end)

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "r", function()
    local button, name = hs.dialog.textPrompt("恢复布局", "名称:", "work", "恢复", "取消")
    if button == "恢复" and name ~= "" then
        LayoutManager.restore(name)
    end
end)

-- ============================================
-- 高级功能：子窗口平铺
-- ============================================

local TileManager = {}
TileManager.originalLayouts = {}

function TileManager.tile(appName)
    local app = hs.application.get(appName)
    if not app then return end
    
    local windows = {}
    for _, win in ipairs(app:allWindows()) do
        if win:isStandard() then
            table.insert(windows, win)
        end
    end
    
    local count = #windows
    if count == 0 then return end
    
    local key = appName .. "_original"
    if not TileManager.originalLayouts[key] then
        local original = {}
        for _, win in ipairs(windows) do
            table.insert(original, {id = win:id(), frame = win:frame()})
        end
        TileManager.originalLayouts[key] = original
    end
    
    local max = hs.screen.mainScreen():frame()
    local cols = math.ceil(math.sqrt(count))
    local rows = math.ceil(count / cols)
    local cellW = max.w / cols
    local cellH = max.h / rows
    
    for i, win in ipairs(windows) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local margin = 4
        setWinFrame(win, hs.geometry.rect(
            max.x + col * cellW + margin,
            max.y + row * cellH + margin,
            cellW - margin * 2,
            cellH - margin * 2
        ))
    end
    
    notify("平铺完成", appName .. " " .. count .. " 个窗口")
end

function TileManager.restore(appName)
    local key = appName .. "_original"
    local original = TileManager.originalLayouts[key]
    if not original then return end
    
    for _, item in ipairs(original) do
        local win = hs.window.get(item.id)
        if win and win:isStandard() then
            setWinFrame(win, item.frame)
        end
    end
    
    TileManager.originalLayouts[key] = nil
    notify("已恢复", appName)
end

function TileManager.tileCurrent()
    local win = hs.window.focusedWindow()
    if win then TileManager.tile(win:application():name()) end
end

function TileManager.restoreCurrent()
    local win = hs.window.focusedWindow()
    if win then TileManager.restore(win:application():name()) end
end

-- 平铺快捷键
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "t", TileManager.tileCurrent)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "o", TileManager.restoreCurrent)

-- ============================================
-- 窗口靠在最左/最右（保持高度和宽度不变，贴到屏幕边缘）
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
-- 边缘窗口坞（Edge Dock）- 常驻小条 + 拖拽停靠
-- ============================================

local EdgeDock = {
    slots = {},             -- 槽位 {win, originalFrame, appName, isShowing, hideTimer}
    bars = {},              -- 小条 UI 元素
    mask = nil,             -- 右侧遮罩条（遮挡可能露出的窗口边缘）
    dragState = {           -- 拖拽状态
        isDragging = false,
        dragWin = nil,
        dragStartPos = nil,
        dragStartFrame = nil,
        highlightedSlot = nil,  -- 当前高亮的槽位
    },
    config = {
        maxSlots = 5,       -- 最大槽位数
        barWidth = 4,       -- 小条宽度
        topMargin = 6,    -- 顶部边距（距离屏幕上边缘）
        bottomMargin = 6, -- 底部边距（距离屏幕下边缘）
        barGap = 10,        -- 小条之间的空隙
        peekWidth = 1,      -- 窗口 peek 出来的宽度
        hideDelay = 0,      -- 鼠标离开后多久收起（秒）
        dragThreshold = 10, -- 拖拽检测阈值（像素）
    }
}

-- 缓存应用颜色
EdgeDock.appColorCache = {}

-- 常用应用颜色表（基于实际图标）
EdgeDock.knownAppColors = {
    ["WeChat"]  = {red = 0.35, green = 0.55, blue = 0.40}, -- 去饱和微信绿
    ["ChatGPT"] = {red = 0.5, green = 0.5, blue = 0.5}, -- 浅灰
    ["Music"]   = {red = 0.55, green = 0.32, blue = 0.38}, -- 灰玫红
    ["Kimi"]    = {red = 0.45, green = 0.50, blue = 0.65}, -- 灰蓝
    ["Safari"] = {red = 0.15, green = 0.55, blue = 0.95},      -- Safari 蓝
    ["Chrome"] = {red = 0.95, green = 0.35, blue = 0.15},      -- Chrome 红/黄/绿/蓝 - 主要用红色
    ["Code"] = {red = 0.15, green = 0.45, blue = 0.75},        -- VS Code 蓝
    ["Terminal"] = {red = 0.25, green = 0.25, blue = 0.25},    -- 终端黑
}

-- 获取应用图标的平均颜色
function EdgeDock.getAppIconColor(appName)
    -- 检查缓存
    if EdgeDock.appColorCache[appName] then
        return EdgeDock.appColorCache[appName]
    end
    
    -- 1. 先检查已知应用颜色表
    if EdgeDock.knownAppColors[appName] then
        local color = EdgeDock.brightenColor(EdgeDock.knownAppColors[appName], 1.3)
        color.alpha = 0.6
        EdgeDock.appColorCache[appName] = color
        return color
    end
    
    -- 2. 尝试获取应用的实际图标
    local app = hs.application.get(appName)
    if not app then 
        return EdgeDock.generateColorFromName(appName)
    end
    
    -- 安全获取图标
    local success, icon = pcall(function() return app:icon() end)
    if not success or not icon then 
        return EdgeDock.generateColorFromName(appName)
    end
    
    -- 3. 尝试通过 bundle 路径获取图标文件
    local bundlePath = app:path()
    if bundlePath then
        local color = EdgeDock.extractColorFromIconBundle(bundlePath)
        if color then
            EdgeDock.appColorCache[appName] = color
            return color
        end
    end
    
    -- 4. 备选：使用名称生成颜色
    local color = EdgeDock.generateColorFromName(appName)
    color.alpha = 0.3
    EdgeDock.appColorCache[appName] = color
    return color
end

-- 从应用 bundle 提取图标颜色
function EdgeDock.extractColorFromIconBundle(bundlePath)
    -- 查找 .icns 文件
    local iconPath = nil
    
    -- 先尝试读取 Info.plist 中的 CFBundleIconFile
    local plistCmd = "defaults read '" .. bundlePath .. "/Contents/Info' CFBundleIconFile 2>/dev/null"
    local handle = io.popen(plistCmd)
    local iconFile = handle and handle:read("*l")
    if handle then handle:close() end
    
    if iconFile then
        iconFile = iconFile:gsub("^%s*", ""):gsub("%s*$", ""):gsub("^\"", ""):gsub("\"$", "")
        iconFile = iconFile:gsub("%.icns$", "")
        
        -- 尝试多个可能的路径
        local paths = {
            bundlePath .. "/Contents/Resources/" .. iconFile .. ".icns",
            bundlePath .. "/Contents/Resources/" .. iconFile,
        }
        for _, p in ipairs(paths) do
            local f = io.open(p, "r")
            if f then f:close() iconPath = p break end
        end
    end
    
    -- 如果没找到，查找 Resources 目录下的任意 .icns
    if not iconPath then
        local findCmd = "find '" .. bundlePath .. "/Contents/Resources' -name '*.icns' -type f 2>/dev/null | head -1"
        local findHandle = io.popen(findCmd)
        iconPath = findHandle and findHandle:read("*l")
        if findHandle then findHandle:close() end
    end
    
    if not iconPath then return nil end
    
    -- 使用 sips 提取颜色直方图的主要颜色
    -- 方法：转换为小的位图然后采样几个像素
    local tmpFile = os.tmpname()
    
    -- 提取第一个图标并缩放到 1x1 来获取平均颜色（但这样太模糊了）
    -- 更好的方法：提取到 4x4 然后分析
    local cmd = "sips -s format png '" .. iconPath .. "' -o '" .. tmpFile .. "' --resampleWidth 4 2>/dev/null"
    os.execute(cmd)
    
    -- 读取 PNG 文件并解析（简化：直接读取文件找颜色特征）
    local f = io.open(tmpFile, "rb")
    local color = nil
    
    if f then
        local data = f:read("*all")
        f:close()
        
        -- 简单启发式：在 PNG 数据中寻找最常见的非透明颜色
        -- PNG 的 IDAT 块包含压缩后的像素数据
        -- 我们采样几个固定位置的字节
        if data and #data > 100 then
            -- 跳过 PNG 头部，采样数据区的一些字节
            local samples = {}
            for i = 100, math.min(#data - 3, 500), 10 do
                local r = string.byte(data, i)
                local g = string.byte(data, i + 1)
                local b = string.byte(data, i + 2)
                -- 过滤掉极端值
                if r and g and b and (r+g+b) > 50 and (r+g+b) < 720 then
                    table.insert(samples, {r=r, g=g, b=b})
                end
            end
            
            if #samples > 0 then
                local tr, tg, tb = 0, 0, 0
                for _, s in ipairs(samples) do
                    tr = tr + s.r
                    tg = tg + s.g
                    tb = tb + s.b
                end
                color = {
                    red = math.min(1, (tr / #samples / 255) * 1.4),
                    green = math.min(1, (tg / #samples / 255) * 1.4),
                    blue = math.min(1, (tb / #samples / 255) * 1.4),
                    alpha = 0.9
                }
            end
        end
    end
    
    os.remove(tmpFile)
    return color
end

-- 根据应用名生成稳定颜色（备选方案）
function EdgeDock.generateColorFromName(appName)
    local hash = 0
    for i = 1, #appName do
        hash = hash + string.byte(appName, i) * i * 31
    end
    hash = hash % 360
    
    -- HSL to RGB
    local hue = hash / 360
    local s, l = 0.75, 0.6
    
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end
    
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    
    return {
        red = hue2rgb(p, q, hue + 1/3),
        green = hue2rgb(p, q, hue),
        blue = hue2rgb(p, q, hue - 1/3),
        alpha = 0.9
    }
end

-- 亮度增加函数
function EdgeDock.brightenColor(color, factor)
    factor = factor or 1.3
    return {
        red = math.min(1, color.red * factor),
        green = math.min(1, color.green * factor),
        blue = math.min(1, color.blue * factor),
        alpha = color.alpha
    }
end

-- 计算小条高度（根据屏幕高度自动分配）
function EdgeDock.getBarHeight()
    local screen = hs.screen.mainScreen():frame()
    local availableHeight = screen.h - EdgeDock.config.topMargin - EdgeDock.config.bottomMargin
    local totalGap = (EdgeDock.config.maxSlots - 1) * EdgeDock.config.barGap
    return math.floor((availableHeight - totalGap) / EdgeDock.config.maxSlots)
end

-- 获取槽位位置（根据屏幕高度自动分布）
function EdgeDock.getSlotPosition(slotIndex)
    local screen = hs.screen.mainScreen():frame()
    local barHeight = EdgeDock.getBarHeight()
    local startY = screen.y + EdgeDock.config.topMargin
    local x = screen.x + screen.w - EdgeDock.config.barWidth - 5  -- 减5px给遮罩条留位置
    local y = startY + (slotIndex - 1) * (barHeight + EdgeDock.config.barGap)
    return x, y, EdgeDock.config.barWidth, barHeight
end

-- 检查点是否在槽位区域
function EdgeDock.isPointInSlot(x, y, slotIndex)
    local sx, sy, sw, sh = EdgeDock.getSlotPosition(slotIndex)
    -- 扩大检测区域方便拖拽（上下左右都扩展）
    return x >= sx - 80 and x <= sx + sw + 80
           and y >= sy - 10 and y <= sy + sh + 10
end

-- 检查点是否在窗口区域内（用于检测鼠标是否离开窗口）
function EdgeDock.isPointInWindow(mouseX, mouseY, win)
    if not win then return false end
    local frame = win:frame()
    return mouseX >= frame.x and mouseX <= frame.x + frame.w
           and mouseY >= frame.y and mouseY <= frame.y + frame.h
end

-- 创建/刷新右侧遮罩条（2px宽黑色，遮挡可能被推出的窗口边缘）
function EdgeDock.refreshMask()
    if EdgeDock.mask then
        EdgeDock.mask:delete()
    end
    local screen = hs.screen.mainScreen():frame()
    -- 2px宽，全屏高，纯黑，放在最右侧
    EdgeDock.mask = hs.canvas.new({x = screen.x + screen.w - 2, y = screen.y, w = 2, h = screen.h})
    EdgeDock.mask:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = {alpha = 1, red = 0, green = 0, blue = 0},
    })
    EdgeDock.mask:level(hs.canvas.windowLevels.overlay)
    EdgeDock.mask:show()
end

-- 创建/刷新所有小条
function EdgeDock.refreshBars()
    -- 清理旧的
    for _, bar in ipairs(EdgeDock.bars) do
        if bar.canvas then bar.canvas:delete() end
    end
    EdgeDock.bars = {}
    
    for i = 1, EdgeDock.config.maxSlots do
        local x, y, w, h = EdgeDock.getSlotPosition(i)
        local slot = EdgeDock.slots[i]
        
        local bar = hs.canvas.new({x = x, y = y, w = w, h = h})
        
        if slot then
            -- 有窗口 - 应用图标颜色（增量后的鲜艳颜色）
            local iconColor = EdgeDock.getAppIconColor(slot.appName) or {alpha = 0.85, red = 0.5, green = 0.5, blue = 0.5}
            local brightColor = EdgeDock.brightenColor(iconColor, 1.25)
            
            bar:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = brightColor,
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
            -- 不显示文字，只用颜色标识应用
        else
            -- 空槽位 - 暗色条 + 编号
            bar:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {alpha = 0.3, red = 0.3, green = 0.3, blue = 0.3},
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
            -- bar:appendElements({
            --     type = "text",
            --     text = tostring(i),
            --     textSize = 11,
            --     textColor = {alpha = 0.4, red = 1, green = 1, blue = 1},
            --     frame = {x = 0, y = h/2 - 8, w = w, h = 16},
            --     textAlignment = "center",
            -- })
        end
        
        bar:show()
        bar:level(hs.canvas.windowLevels.popUpMenu)  -- 置顶显示
        
        table.insert(EdgeDock.bars, {
            canvas = bar,
            slotIndex = i,
        })
    end
end

-- 保存 Edge Dock 状态到文件
function EdgeDock.saveState()
    local state = {}
    for i = 1, EdgeDock.config.maxSlots do
        local slot = EdgeDock.slots[i]
        if slot and slot.win and slot.win:isStandard() then
            -- 保存应用名、窗口标题、原始位置和槽位号
            table.insert(state, {
                slotIndex = i,
                appName = slot.appName,
                winTitle = slot.win:title(),
                originalFrame = {
                    x = slot.originalFrame.x,
                    y = slot.originalFrame.y,
                    w = slot.originalFrame.w,
                    h = slot.originalFrame.h
                }
            })
        end
    end
    
    local file = io.open(EDGEDOCK_STATE_FILE, "w")
    if file then
        file:write(hs.json.encode(state))
        file:close()
        print("[EdgeDock] 状态已保存: " .. #state .. " 个窗口")
    end
end

-- 从文件恢复 Edge Dock 状态
function EdgeDock.restoreState()
    local file = io.open(EDGEDOCK_STATE_FILE, "r")
    if not file then
        print("[EdgeDock] 没有找到状态文件")
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local state = hs.json.decode(content)
    if not state or #state == 0 then
        print("[EdgeDock] 状态文件为空")
        return
    end
    
    -- 延迟恢复，等待应用启动
    hs.timer.doAfter(2, function()
        local restoredCount = 0
        
        for _, item in ipairs(state) do
            -- 查找应用
            local app = hs.application.get(item.appName)
            if not app then
                -- 尝试启动应用
                print("[EdgeDock] 尝试启动应用: " .. item.appName)
                hs.application.launchOrFocus(item.appName)
                -- 等待应用启动
                hs.timer.usleep(500000) -- 500ms
                app = hs.application.get(item.appName)
            end
            
            if app then
                -- 查找匹配的窗口
                local targetWin = nil
                local windows = app:allWindows()
                
                for _, win in ipairs(windows) do
                    if win:isStandard() then
                        -- 优先匹配标题
                        if win:title() == item.winTitle then
                            targetWin = win
                            break
                        end
                        -- 备选：如果没有标题匹配，取第一个标准窗口
                        if not targetWin then
                            targetWin = win
                        end
                    end
                end
                
                if targetWin then
                    -- 恢复 originalFrame
                    local frame = hs.geometry.rect(
                        item.originalFrame.x,
                        item.originalFrame.y,
                        item.originalFrame.w,
                        item.originalFrame.h
                    )
                    
                    -- 使用主屏幕（和小条一致）
                    local screen = hs.screen.mainScreen():frame()
                    
                    -- 获取槽位位置
                    local sx, sy, sw, sh = EdgeDock.getSlotPosition(item.slotIndex)
                    
                    -- 计算窗口在槽位区域内的垂直居中位置
                    local winY = sy + (sh - frame.h) / 2
                    if winY < screen.y then
                        winY = screen.y
                    end
                    if winY + frame.h > screen.y + screen.h then
                        winY = screen.y + screen.h - frame.h
                    end
                    
                    -- 保存到槽位
                    EdgeDock.slots[item.slotIndex] = {
                        win = targetWin,
                        winId = targetWin:id(),
                        originalFrame = frame,
                        appName = item.appName,
                        isShowing = false,
                        hideTimer = nil,
                        slotY = sy,
                        slotHeight = sh,
                        winY = winY,
                    }
                    
                    -- 隐藏窗口到屏幕右下角
                    local hideX = screen.x + screen.w - 1
                    local hideY = screen.y + screen.h - 1
                    setWinFrame(targetWin, hs.geometry.rect(hideX, hideY, frame.w, frame.h))
                    
                    restoredCount = restoredCount + 1
                    print("[EdgeDock] 恢复槽位 " .. item.slotIndex .. ": " .. item.appName)
                else
                    print("[EdgeDock] 未找到窗口: " .. item.appName)
                end
            else
                print("[EdgeDock] 应用未运行: " .. item.appName)
            end
        end
        
        -- 刷新小条显示
        EdgeDock.refreshBars()
        
        if restoredCount > 0 then
            notify("Edge Dock", "已恢复 " .. restoredCount .. " 个窗口")
        end
    end)
end

-- 高亮小条（拖拽提示）
function EdgeDock.highlightBar(slotIndex, highlight)
    local bar = EdgeDock.bars[slotIndex]
    if not bar or not bar.canvas then return end
    
    local slot = EdgeDock.slots[slotIndex]
    local barHeight = EdgeDock.getBarHeight()
    local w, h = EdgeDock.config.barWidth, barHeight
    
    -- 清除并重绘
    bar.canvas:removeElement(1)
    bar.canvas:removeElement(1)
    
    if highlight then
        -- 高亮状态 - 亮色边框
        bar.canvas:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = slot and {alpha = 0.9, red = 0.3, green = 0.7, blue = 1.0} 
                        or {alpha = 0.6, red = 0.5, green = 0.5, blue = 0.5},
            roundedRectRadii = {xRadius = 4, yRadius = 4},
        })
    else
        -- 正常状态
        if slot then
            bar.canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {alpha = 0.5, red = 1, green = 1, blue = 1},
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
        else
            bar.canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {alpha = 0.2, red = 0.3, green = 0.3, blue = 0.3},
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
        end
    end
    
    -- 文字
    bar.canvas:appendElements({
        type = "text",
        text = slot and string.upper(string.sub(slot.appName, 1, 1)) or tostring(slotIndex),
        textSize = 14,
        textColor = highlight and {alpha = 1, red = 1, green = 1, blue = 1}
                            or (slot and {alpha = 1, red = 0, green = 0, blue = 0} 
                                or {alpha = 0.4, red = 1, green = 1, blue = 1}),
        frame = {x = 0, y = h/2 - 10, w = w, h = 20},
        textAlignment = "center",
    })
end

-- 清除所有高亮
function EdgeDock.clearAllHighlights()
    for i = 1, EdgeDock.config.maxSlots do
        EdgeDock.highlightBar(i, false)
    end
end

-- 将窗口停靠到槽位
function EdgeDock.dockWindow(win, slotIndex)
    if not win or not win:isStandard() then return false end
    
    -- 如果窗口已经在其他槽位，先移除
    for i, slot in pairs(EdgeDock.slots) do
        if slot and slot.win:id() == win:id() then
            EdgeDock.undockWindow(i, false)
            break
        end
    end
    
    -- 如果槽位被占用，恢复那个窗口
    if EdgeDock.slots[slotIndex] then
        EdgeDock.undockWindow(slotIndex, false)
    end
    
    local app = win:application()
    local frame = win:frame()
    
    -- 使用主屏幕（和小条一致），而不是窗口所在屏幕
    local screen = hs.screen.mainScreen():frame()
    
    -- 获取槽位位置（基于主屏幕）
    local sx, sy, sw, sh = EdgeDock.getSlotPosition(slotIndex)
    
    -- 计算窗口在槽位区域内的垂直居中位置
    local winY = sy + (sh - frame.h) / 2
    
    -- 确保窗口不会超出屏幕顶部和底部
    if winY < screen.y then
        winY = screen.y
    end
    if winY + frame.h > screen.y + screen.h then
        winY = screen.y + screen.h - frame.h
    end
    
    print(string.format("[EdgeDock] 槽位%d: y=%.0f, h=%.0f, 窗口高=%.0f, winY=%.0f", slotIndex, sy, sh, frame.h, winY))
    
    EdgeDock.slots[slotIndex] = {
        win = win,
        winId = win:id(),
        originalFrame = frame,
        appName = app and app:name() or "?",
        isShowing = false,
        hideTimer = nil,
        slotY = sy,         -- 槽位顶部 Y
        slotHeight = sh,    -- 槽位高度
        winY = winY,        -- 窗口实际显示的 Y（垂直居中）
    }
    
    -- 隐藏到屏幕右下角（只露出1x1像素，保持尺寸）
    local hideX = screen.x + screen.w - 1
    local hideY = screen.y + screen.h - 1
    setWinFrame(win, hs.geometry.rect(hideX, hideY, frame.w, frame.h))
    
    EdgeDock.refreshBars()
    EdgeDock.saveState()  -- 保存状态
    notify("Edge Dock", "已停靠到槽位 " .. slotIndex)
    return true
end

-- 显示窗口（滑出到右边，保持大小，在槽位内垂直居中）
function EdgeDock.peekWindow(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return end
    
    local win = slot.win
    if not win or not win:isStandard() then
        EdgeDock.slots[slotIndex] = nil
        EdgeDock.refreshBars()
        return
    end
    
    print(string.format("[EdgeDock] 显示槽位%d, winY=%.0f", slotIndex, slot.winY))
    
    -- 先隐藏其他所有正在显示的窗口（单选模式）
    for i = 1, EdgeDock.config.maxSlots do
        if i ~= slotIndex then
            local otherSlot = EdgeDock.slots[i]
            if otherSlot and otherSlot.isShowing then
                EdgeDock.hideWindow(i)
            end
            -- 取消其他窗口的隐藏计时器
            if otherSlot and otherSlot.hideTimer then
                otherSlot.hideTimer:stop()
                otherSlot.hideTimer = nil
            end
        end
    end
    
    -- 取消当前槽位的隐藏计时器
    if slot.hideTimer then
        slot.hideTimer:stop()
        slot.hideTimer = nil
    end
    
    if not slot.isShowing then
        -- 使用主屏幕（和小条一致）
        local screen = hs.screen.mainScreen():frame()
        -- 使用 originalFrame 的尺寸（窗口在屏幕外时 win:frame() 可能返回错误值）
        local winW = slot.originalFrame.w
        local winH = slot.originalFrame.h
        -- 靠右显示，保持大小不变，y 坐标垂直居中于槽位
        local showX = screen.x + screen.w - winW
        
        setWinFrame(win, hs.geometry.rect(showX, slot.winY, winW, winH))
        slot.isShowing = true
        
        -- 将窗口置顶并激活（最前面）
        win:raise()
        win:focus()
        -- 稍微延迟再次确保置顶
        hs.timer.doAfter(0.05, function()
            if win and win:isStandard() then
                win:raise()
                win:focus()
            end
        end)
    end
end

-- 隐藏窗口（移到右下角，只露出1x1像素）
function EdgeDock.hideWindow(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return end
    
    local win = slot.win
    if not win or not win:isStandard() then
        EdgeDock.slots[slotIndex] = nil
        EdgeDock.refreshBars()
        return
    end
    
    -- 移到屏幕右下角（只露出1x1像素，保持原尺寸）
    local screen = hs.screen.mainScreen():frame()
    local hideX = screen.x + screen.w - 1
    local hideY = screen.y + screen.h - 1
    
    setWinFrame(win, hs.geometry.rect(hideX, hideY, slot.originalFrame.w, slot.originalFrame.h))
    slot.isShowing = false
end

-- 完全恢复窗口
function EdgeDock.undockWindow(slotIndex, focus)
    focus = focus ~= false  -- 默认 true
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return end
    
    if slot.hideTimer then
        slot.hideTimer:stop()
    end
    
    local win = slot.win
    if win and win:isStandard() then
        setWinFrame(win, slot.originalFrame)
        if focus then win:focus() end
    end
    
    EdgeDock.slots[slotIndex] = nil
    EdgeDock.refreshBars()
    EdgeDock.saveState()  -- 保存状态
    
    if focus then
        notify("Edge Dock", "窗口已恢复")
    end
end

-- 鼠标移动监听（仅用于悬停检测，不拦截事件）
EdgeDock.mouseWatcher = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local mousePos = e:location()
    local screen = hs.screen.mainScreen():frame()
    local rightEdge = screen.x + screen.w
    
    -- 悬停检测
    for i = 1, EdgeDock.config.maxSlots do
        local slot = EdgeDock.slots[i]
        if not slot then goto continue end
        
        local sx, sy, sw, sh = EdgeDock.getSlotPosition(i)
        -- 扩大检测区域：屏幕右边缘附近都能触发（支持 peekWidth=0 的情况）
        local inSlotArea = mousePos.x >= sx - 20 and mousePos.x <= rightEdge + 5
                          and mousePos.y >= sy - 5 and mousePos.y <= sy + sh + 5
        
        -- 检测是否在槽位区域 - 显示窗口
        if inSlotArea and not slot.isShowing then
            EdgeDock.peekWindow(i)
        end
        
        -- 检测是否离开窗口区域 - 启动隐藏计时器
        if slot.isShowing then
            local inWindow = EdgeDock.isPointInWindow(mousePos.x, mousePos.y, slot.win)
            -- 扩大槽位检测区域，确保鼠标在小条附近时不会误判为离开
            local inSlot = mousePos.x >= sx - 30 and mousePos.x <= rightEdge + 10
                          and mousePos.y >= sy - 10 and mousePos.y <= sy + sh + 10
            
            -- 既不在窗口内，也不在槽位上
            if not inWindow and not inSlot then
                if not slot.hideTimer then
                    slot.hideTimer = hs.timer.doAfter(EdgeDock.config.hideDelay, function()
                        EdgeDock.hideWindow(i)
                        slot.hideTimer = nil
                    end)
                end
            else
                -- 还在窗口或槽位上，取消隐藏计时器
                if slot.hideTimer then
                    slot.hideTimer:stop()
                    slot.hideTimer = nil
                end
            end
        end
        
        ::continue::
    end
    
    return false  -- 不拦截事件
end)

-- 应用关闭检测
EdgeDock.appWatcher = hs.application.watcher.new(function(appName, eventType, appObj)
    if eventType == hs.application.watcher.terminated then
        hs.timer.doAfter(0.5, function()
            for i = 1, EdgeDock.config.maxSlots do
                local slot = EdgeDock.slots[i]
                if slot and (not slot.win or not slot.win:isStandard()) then
                    EdgeDock.slots[i] = nil
                end
            end
            EdgeDock.refreshBars()
        end)
    end
end)

-- 屏幕变化时重新定位
EdgeDock.screenWatcher = hs.screen.watcher.new(function()
    hs.timer.doAfter(0.3, function()
        EdgeDock.refreshBars()
        EdgeDock.refreshMask()
    end)
end)

-- ============================================
-- 屏幕切换后自动调整半屏窗口高度
-- ============================================

-- 检测窗口是否是"全高"类型（需要在新屏幕上保持全高）
local function isFullHeightWindow(win)
    local max = win:screen():frame()
    local frame = win:frame()
    
    -- 检测是否是左/右半屏（宽度约为 0.5、2/3、5/6，位置在左/右边缘）
    local isLeftSide = approx(frame.x, max.x, 10) or approx(frame.x, max.x + margin.left, 15)
    local isRightSide = approx(frame.x + frame.w, max.x + max.w, 10) or 
                        approx(frame.x + frame.w, max.x + max.w - margin.right, 15)
    local isHalfWidth = approx(frame.w, max.w * 0.5, 40) or 
                        approx(frame.w, max.w * 2/3, 40) or
                        approx(frame.w, max.w * 5/6, 40)
    
    -- 检测是否是 1/3 分屏
    local thirdW = (max.w - margin.left - margin.right - margin.inner * 2) / 3
    local isThirdWidth = approx(frame.w, thirdW, 30)
    local isThirdLayout = isThirdWidth and (
        approx(frame.x, max.x + margin.left, 15) or
        approx(frame.x, max.x + margin.left + thirdW + margin.inner, 15) or
        approx(frame.x, max.x + margin.left + (thirdW + margin.inner) * 2, 15)
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

-- 恢复所有可能被之前脚本实例藏起来的窗口
function EdgeDock.recoverHiddenWindows()
    local screen = hs.screen.mainScreen():frame()
    local rightEdge = screen.x + screen.w
    
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isStandard() then
            local frame = win:frame()
            -- 如果窗口在屏幕右侧外（被藏起来了），把它拉回来
            -- 扩大检测范围：从 rightEdge-50 到 rightEdge+100，支持 peekWidth=0 的情况
            if frame.x >= rightEdge - 50 and frame.x <= rightEdge + 100 then
                -- 窗口被藏在右边，恢复到屏幕内（居中），保持原始尺寸
                local newX = screen.x + (screen.w - frame.w) / 2
                local newY = screen.y + (screen.h - frame.h) / 2
                setWinFrame(win, hs.geometry.rect(newX, newY, frame.w, frame.h))
                print("[EdgeDock] 恢复窗口: " .. (win:application():name() or "Unknown"))
            end
        end
    end
end

-- 启动
function EdgeDock.start()
    -- 先恢复可能被之前实例藏起来的窗口
    EdgeDock.recoverHiddenWindows()
    
    -- 初始化小条和遮罩
    EdgeDock.refreshBars()
    EdgeDock.refreshMask()
    
    -- 启动监听器
    EdgeDock.mouseWatcher:start()
    EdgeDock.appWatcher:start()
    EdgeDock.screenWatcher:start()
    
    -- 从文件恢复状态
    EdgeDock.restoreState()
end

-- 停止
function EdgeDock.stop()
    for i = 1, EdgeDock.config.maxSlots do
        if EdgeDock.slots[i] then
            EdgeDock.undockWindow(i)
        end
    end
    if EdgeDock.mask then
        EdgeDock.mask:delete()
        EdgeDock.mask = nil
    end
    EdgeDock.mouseWatcher:stop()
    EdgeDock.appWatcher:stop()
    EdgeDock.screenWatcher:stop()
end

-- 快捷键：停靠到槽位 1-5 (Ctrl+Opt+数字)
for i = 1, 5 do
    hs.hotkey.bind(mash, tostring(i), function()
        local win = hs.window.focusedWindow()
        EdgeDock.dockWindow(win, i)
    end)
end

-- 快捷键：恢复槽位 1-5 (Ctrl+Opt+Cmd+数字)
for i = 1, 5 do
    hs.hotkey.bind({"ctrl", "alt", "cmd"}, tostring(i), function()
        EdgeDock.undockWindow(i)
    end)
end

-- 启动
EdgeDock.start()

-- ============================================
-- 启动提示
-- ============================================

notify("Rectangle 风格管理器已加载", "Ctrl+Option + 方向键/字母")
print("[RectangleHammerspoon] 配置已加载")
