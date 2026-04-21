-- ============================================
-- 全局配置与工具函数
-- ============================================

-- 禁用窗口动画
hs.window.animationDuration = 0

-- 配置文件路径
CONFIG_PATH = os.getenv("HOME") .. "/.hammerspoon/"

-- Edge Dock 状态文件路径
EDGEDOCK_STATE_FILE = CONFIG_PATH .. "edge_dock_state.json"

-- 修饰键定义
mash = {"ctrl", "alt"}           -- 主修饰键：Ctrl + Option
mashShift = {"ctrl", "alt", "shift"}  -- Ctrl + Option + Shift

-- ============================================
-- 边距配置
-- ============================================

-- 默认边距
margin = {
    left = 220,       -- 左侧边距（距离屏幕左边缘）
    right = 11,      -- 右侧边距（距离屏幕右边缘）
    inner = 40,      -- 中间边距（窗口之间的空隙）
}

-- 应用特定边距配置（可选）
-- 应用名（不区分大小写） -> 边距配置
appMargins = {
    -- 示例：Chrome 有侧栏，左边距更大
    ["Google Chrome"] = { left = 11, right = 11, inner = 40 },
    ["Chrome"] = { left = 11, right = 11, inner = 40 },
    -- 你可以在这里添加更多应用特定配置
    -- ["Safari"] = { left = 20, right = 11, inner = 40 },
    -- ["Code"] = { left = 60, right = 11, inner = 40 },
}

-- 显示器特定边距配置（可选）
-- 支持通过屏幕名称或屏幕ID匹配
displayMargins = {
    -- 示例：内置显示器（Retina 屏幕）
    ["Built-in Retina Display"] = { left = 80, right = 11, inner = 40 },
    
    -- 示例：特定外接显示器（通过名称匹配）
    -- ["DELL U2723QE"] = { left = 20, right = 20, inner = 50 },
    -- ["LG ULTRAWIDE"] = { left = 30, right = 30, inner = 60 },
    
    -- 示例：通过屏幕ID匹配（使用 hs.screen:id() 获取）
    -- ["screen_69731840"] = { left = 15, right = 15, inner = 45 },
}

-- 应用+显示器组合配置（优先级最高）
-- 格式：["应用名"] = { ["显示器名"] = {边距配置} }
appDisplayMargins = {
    -- 示例：Chrome 在外接显示器上使用更大的边距
    -- ["Google Chrome"] = {
    --     ["DELL U2723QE"] = { left = 100, right = 20, inner = 50 },
    -- },
}

-- 获取屏幕标识（名称或ID）
function getScreenIdentifier(screen)
    if not screen then return nil end
    return screen:name() or ("screen_" .. screen:id())
end

-- 获取边距配置（综合考虑应用和显示器）
function getAppMargin(win)
    if not win then return margin end
    
    local app = win:application()
    local appName = app and app:name() or nil
    local screen = win:screen()
    local screenId = getScreenIdentifier(screen)
    
    -- 1. 优先检查应用+显示器组合配置
    if appName and screenId and appDisplayMargins[appName] then
        local displayConfig = appDisplayMargins[appName]
        -- 尝试精确匹配屏幕名称
        if displayConfig[screenId] then
            return displayConfig[screenId]
        end
        -- 尝试通过屏幕ID匹配
        if screen then
            local idKey = "screen_" .. screen:id()
            if displayConfig[idKey] then
                return displayConfig[idKey]
            end
        end
        -- 尝试大小写不敏感匹配
        for name, config in pairs(displayConfig) do
            if string.lower(name) == string.lower(screenId) then
                return config
            end
        end
    end
    
    -- 2. 检查应用特定配置
    if appName then
        if appMargins[appName] then
            return appMargins[appName]
        end
        -- 尝试大小写不敏感匹配
        for name, config in pairs(appMargins) do
            if string.lower(name) == string.lower(appName) then
                return config
            end
        end
    end
    
    -- 3. 检查显示器特定配置
    if screenId then
        if displayMargins[screenId] then
            return displayMargins[screenId]
        end
        -- 尝试通过屏幕ID匹配
        if screen then
            local idKey = "screen_" .. screen:id()
            if displayMargins[idKey] then
                return displayMargins[idKey]
            end
        end
        -- 尝试大小写不敏感匹配
        for name, config in pairs(displayMargins) do
            if string.lower(name) == string.lower(screenId) then
                return config
            end
        end
    end
    
    -- 4. 返回默认配置
    return margin
end

-- 计算屏幕可用区域（扣除边距后的区域）
-- @param max 屏幕 frame
-- @param win 可选，窗口对象，用于获取应用特定边距
function getUsableArea(max, win)
    local m = win and getAppMargin(win) or margin
    return {
        x = max.x + m.left,
        y = max.y,
        w = max.w - m.left - m.right,
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
-- 窗口状态管理
-- ============================================

-- 存储还原信息（每个窗口）
windowHistory = {}

-- 循环状态记录：每个窗口的左右半屏循环状态
cycleState = {}

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
function approx(a, b, tolerance)
    tolerance = tolerance or 10
    return math.abs(a - b) < tolerance
end
