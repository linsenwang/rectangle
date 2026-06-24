-- ============================================
-- 全局配置中心
-- 所有用户可配置项都集中在这里
-- ============================================

-- 禁用窗口动画
hs.window.animationDuration = 0

-- 配置文件路径
CONFIG_PATH = os.getenv("HOME") .. "/.hammerspoon/"

-- Edge Dock 状态文件路径
EDGEDOCK_STATE_FILE = CONFIG_PATH .. "edge_dock_state.json"

-- ============================================
-- 修饰键配置
-- ============================================

mash = {"ctrl", "alt"}           -- 主修饰键：Ctrl + Option
mashShift = {"ctrl", "alt", "shift"}  -- Ctrl + Option + Shift

-- ============================================
-- 边距配置
-- ============================================

-- 默认边距（所有应用和显示器的默认值）
margin = {
    left = 120,      -- 左侧边距（距离屏幕左边缘）
    right = 11,      -- 右侧边距（距离屏幕右边缘）
    inner = 40,      -- 中间边距（窗口之间的空隙）
}

-- 应用特定边距配置（可选）
-- 应用名（不区分大小写） -> 边距配置
appMargins = {
    -- 示例：Chrome 有侧栏，左边距更大
    ["Google Chrome"] = { left = 11, right = 11, inner = 40 },
    -- ["Chrome"] = { left = 80, right = 11, inner = 40 },
    -- ["Safari"] = { left = 20, right = 11, inner = 40 },
    ["Code"] = { left = 11, right = 11, inner = 40 },
}

-- 显示器特定边距配置（可选）
-- 支持通过屏幕名称或屏幕ID匹配
displayMargins = {
    -- 示例：内置显示器（Retina 屏幕）
    -- ["Built-in Retina Display"] = { left = 11, right = 11, inner = 40 },
    
    -- 示例：特定外接显示器（通过名称匹配）
    -- ["DELL U2723QE"] = { left = 20, right = 20, inner = 50 },
    -- ["LG ULTRAWIDE"] = { left = 30, right = 30, inner = 60 },
    
    -- 示例：通过屏幕ID匹配（使用 screen_ID 格式）
    -- ["screen_69731840"] = { left = 15, right = 15, inner = 45 },
}

-- 应用+显示器组合配置（优先级最高）
-- 格式：["应用名"] = { ["显示器名"] = {边距配置} }
appDisplayMargins = {
    -- 示例：Chrome 在外接显示器上使用更大的边距
    -- ["Google Chrome"] = {
    --     ["DELL U2723QE"] = { left = 100, right = 20, inner = 50 },
    --     ["screen_69731840"] = { left = 80, right = 11, inner = 40 },
    -- },
}

-- ============================================
-- Edge Dock 配置
-- ============================================

EdgeDockConfig = {
    maxSlots = 7,       -- 最大槽位数（1-9）
    barWidth = 4,       -- 小条宽度（像素）
    topMargin = 6,      -- 顶部边距（距离屏幕上边缘）
    bottomMargin = 6,   -- 底部边距（距离屏幕下边缘）
    barGap = 10,        -- 小条之间的空隙（像素）
    barRightOffset = 3, -- 小条距离屏幕右边缘的偏移（像素）
    peekWidth = 1,      -- 窗口 peek 出来的宽度（像素）
    hideDelay = 0,      -- 鼠标离开后多久收起（秒），0表示立即收起
    centeredPause = true,  -- 居中后暂停鼠标移出检测
    showMask = false,      -- 是否显示右侧遮罩条（遮挡窗口边缘露出的一小角）
    
    -- 鼠标触发范围配置（像素）
    triggerRange = {
        leftExtend = 7,   -- 槽位左侧向左扩展的触发范围
        rightExtend = 5,  -- 屏幕右边缘向右扩展的触发范围
        topExtend = 5,    -- 槽位顶部向上扩展的触发范围
        bottomExtend = 5, -- 槽位底部向下扩展的触发范围
    },
    
    -- 深色/浅色模式颜色配置
    colors = {
        dark = {
            emptyBar = {alpha = 0.3, red = 0.3, green = 0.3, blue = 0.3},      -- 空槽位颜色
            emptyText = {alpha = 0, red = 1, green = 1, blue = 1},              -- 空槽位文字颜色
            highlightOccupied = {alpha = 0.9, red = 0.3, green = 0.7, blue = 1.0},  -- 高亮-有窗口
            highlightEmpty = {alpha = 0.6, red = 0.5, green = 0.5, blue = 0.5},     -- 高亮-空槽位
            highlightText = {alpha = 1, red = 1, green = 1, blue = 1},          -- 高亮文字颜色
            normalOccupiedText = {alpha = 1, red = 0, green = 0, blue = 0},     -- 正常-有窗口文字
            mask = {alpha = 1, red = 0, green = 0, blue = 0},                   -- 遮罩条颜色
        },
        light = {
            emptyBar = {alpha = 0.2, red = 0.7, green = 0.7, blue = 0.7},      -- 空槽位颜色（浅灰）
            emptyText = {alpha = 0, red = 0.3, green = 0.3, blue = 0.3},        -- 空槽位文字颜色（深灰）
            highlightOccupied = {alpha = 0.9, red = 0.2, green = 0.5, blue = 0.9},  -- 高亮-有窗口（深蓝）
            highlightEmpty = {alpha = 0.5, red = 0.6, green = 0.6, blue = 0.6},     -- 高亮-空槽位
            highlightText = {alpha = 1, red = 1, green = 1, blue = 1},          -- 高亮文字颜色
            normalOccupiedText = {alpha = 1, red = 1, green = 1, blue = 1},     -- 正常-有窗口文字（浅色模式用白色）
            mask = {alpha = 1, red = 0, green = 0, blue = 0},                   -- 遮罩条颜色
        }
    },
    
    -- 已知应用颜色表（支持深色/浅色模式）
    -- 如果不指定某个模式，则回退到另一个模式
    knownAppColors = {
        ["WeChat"] = {
            dark  = {red = 0.40, green = 0.65, blue = 0.45},
            light = {red = 0.15, green = 0.35, blue = 0.20},
        },
        ["ChatGPT"] = {
            dark  = {red = 0.65, green = 0.65, blue = 0.65},
            light = {red = 0.18, green = 0.18, blue = 0.18},
        },
        ["Music"] = {
            dark  = {red = 1.00, green = 0.30, blue = 0.38},
            light = {red = 0.45, green = 0.18, blue = 0.25},
        },
        ["Kimi"] = {
            dark  = {red = 0.55, green = 0.60, blue = 0.80},
            light = {red = 0.28, green = 0.38, blue = 0.60},
        },
        ["Safari"] = {
            dark  = {red = 0.25, green = 0.65, blue = 1.00},
            light = {red = 0.05, green = 0.38, blue = 0.80},
        },
        ["Chrome"] = {
            dark  = {red = 1.00, green = 0.40, blue = 0.20},
            light = {red = 0.65, green = 0.18, blue = 0.05},
        },
        ["Code"] = {
            dark  = {red = 0.25, green = 0.55, blue = 0.95},
            light = {red = 0.05, green = 0.30, blue = 0.60},
        },
        ["Terminal"] = {
            dark  = {red = 0.70, green = 0.70, blue = 0.70},
            light = {red = 0.12, green = 0.12, blue = 0.12},
        },
    }
}

-- ============================================
-- 窗口平铺配置
-- ============================================

TilingConfig = {
    spacing = 0,        -- 默认间距（可以是负数，表示重叠）
    mode = "single",    -- 默认模式: "single" | "multi" | "perScreen"
                        -- "single" - 只在主显示器平铺所有窗口
                        -- "multi"  - 将窗口均匀分配到所有显示器
                        -- "perScreen" - 每个显示器平铺自己的窗口
}

-- ============================================
-- 自动停靠配置
-- ============================================

AutoDockConfig = {
    -- 应用名 = 槽位编号 (1-9)
    ["Music"] = 5,  -- Apple Music 停靠到槽位 5
    ["ChatGPT"] = 2,
    ["WeChat"] = 1, -- 微信停靠到槽位 1
}

-- ============================================
-- 显示器布局记忆配置
-- ============================================

DisplayLayoutConfig = {
    -- 状态文件路径（相对于 CONFIG_PATH）
    stateFile = "display_layouts.json",
    
    -- 是否启用自动保存（当显示器断开时）
    -- 注意：当前版本默认禁用，使用手动保存 (⌃⌥⇧ D)
    autoSaveOnDisconnect = false,
    
    -- 是否启用自动恢复（当显示器连接时）
    autoRestoreOnConnect = true,
    
    -- 恢复延迟（秒）- 等待显示器完全初始化
    restoreDelay = 1.5,
}

-- ============================================
-- 配置加载完成
-- ============================================

print("[Config] 配置已加载")

-- ============================================
-- 工具函数（配置相关）
-- ============================================

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
-- 通用工具函数
-- ============================================

function notify(title, message)
    hs.notify.new({title = title, informativeText = message}):send()
end

-- ============================================
-- 微信窗口选择辅助
-- 微信的搜索/隐藏窗口常被误识别为前台窗口，这里提供主窗口选择逻辑
-- ============================================

function pickWeChatMainWindow(app, candidateWin)
    if not app then return candidateWin end

    local appName = app:name() or ""
    local lowerName = string.lower(appName)
    if lowerName ~= "wechat" and lowerName ~= "weixin" and lowerName ~= "微信" then
        return candidateWin
    end

    local mainTitles = { ["WeChat"] = true, ["Weixin"] = true, ["微信"] = true }
    -- 只排除实际观察到的搜索/辅助窗口标题，后续观察到新的再加
    local searchTitles = {
        ["WeChat (Window)"] = true,   -- 当前实际观察到的搜索窗口标题
    }

    -- 判断窗口是否已经在 Edge Dock 槽位里（避免重复钉同一个已隐藏的窗口）
    local function isDockedWindow(win)
        if not win or not win.id then return false end
        local wid = win:id()
        if not wid then return false end
        if EdgeDock and EdgeDock.slots then
            for _, slot in pairs(EdgeDock.slots) do
                if slot and slot.winId and slot.winId == wid then
                    return true
                end
            end
        end
        return false
    end

    -- 判断窗口是否可用：标准窗口、非搜索窗口、且未被 EdgeDock 占用
    local function isUsableWindow(win)
        if not win or not win.isStandard or not win:isStandard() then return false end
        local title = win:title() or ""
        if searchTitles[title] then return false end
        if isDockedWindow(win) then return false end
        return true
    end

    -- 候选窗口本身可用就直接用（保留用户主动聚焦的聊天窗口/公众号窗口等）
    if isUsableWindow(candidateWin) then
        return candidateWin
    end

    local ok, allWindows = pcall(function() return app:allWindows() end)
    if not ok or not allWindows then return candidateWin end

    local bestMain = nil
    local bestOther = nil

    for _, win in ipairs(allWindows) do
        if win:isStandard() then
            local title = win:title() or ""
            local area = win:frame().w * win:frame().h

            if not searchTitles[title] and not isDockedWindow(win) then
                if mainTitles[title] then
                    if not bestMain or area > bestMain.area then
                        bestMain = { win = win, area = area, title = title }
                    end
                else
                    if not bestOther or area > bestOther.area then
                        bestOther = { win = win, area = area, title = title }
                    end
                end
            end
        end
    end

    if bestMain then
        print("[WeChatHelper] 选择主窗口: title=[" .. bestMain.title .. "]")
        return bestMain.win
    end
    if bestOther then
        print("[WeChatHelper] 未找到主标题，选择最大可用窗口: title=[" .. bestOther.title .. "]")
        return bestOther.win
    end

    return candidateWin
end

-- ============================================
-- 修复：hs.window.focusedWindow() 在切换到 Chrome App/PWA 后返回旧窗口的问题
-- ============================================

local originalFocusedWindow = hs.window.focusedWindow

function hs.window.focusedWindow()
    local win = originalFocusedWindow()
    local frontApp = hs.application.frontmostApplication()

    if not frontApp then
        return win
    end

    local okFront, frontBundleID = pcall(function() return frontApp:bundleID() end)
    local isWeChat = okFront and frontBundleID == "com.tencent.xinWeChat"

    -- 如果原函数返回的窗口已经属于最前台应用，直接返回
    if win then
        local app = win:application()
        if app then
            local ok, bundleID = pcall(function() return app:bundleID() end)
            if ok and bundleID and frontBundleID and bundleID == frontBundleID then
                if isWeChat then
                    local fixed = pickWeChatMainWindow(frontApp, win)
                    if fixed then return fixed end
                end
                return win
            end
        end
    end

    -- 否则直接询问最前台应用的聚焦窗口（对 Chrome App / PWA 更可靠）
    local ok, appWin = pcall(function() return frontApp:focusedWindow() end)
    if ok and appWin then
        if isWeChat then
            local fixed = pickWeChatMainWindow(frontApp, appWin)
            if fixed then return fixed end
        end
        return appWin
    end

    -- 备选：最前台应用的主窗口
    local ok2, mainWin = pcall(function() return frontApp:mainWindow() end)
    if ok2 and mainWin then
        if isWeChat then
            local fixed = pickWeChatMainWindow(frontApp, mainWin)
            if fixed then return fixed end
        end
        return mainWin
    end

    return win
end

print("[Config] hs.window.focusedWindow 已补丁：优先使用前台应用的 focusedWindow，并修复微信搜索窗口误识别")

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

-- 三分之一循环状态
thirdCycleState = {}

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
