-- ============================================
-- 自定义窗口管理器配置
-- 功能：保存布局、条件判断、子窗口平铺
-- ============================================

-- 禁用窗口动画（解决卡顿问题）
hs.window.animationDuration = 0

-- 禁用 Apple 动画（系统级）
hs.osascript.applescript([[
    tell application "System Events"
        tell appearance preferences
            set animates to false
        end tell
    end tell
]])

-- 辅助函数：立即执行，无延迟
local function immediate(fn)
    hs.timer.doAfter(0, fn)
end

-- 配置文件路径（用于保存布局数据）
local CONFIG_PATH = os.getenv("HOME") .. "/.hammerspoon/"

-- ============================================
-- 工具函数
-- ============================================

-- 显示通知
function notify(title, message)
    hs.notify.new({title = title, informativeText = message}):send()
end

-- 快速设置窗口 frame（无动画）
-- 解决 AXEnhancedUserInterface 导致的多次按键问题
function setWinFrame(win, rect)
    if not win or not win.isStandard or not win:isStandard() then return end
    
    -- 获取应用的 AXUIElement
    local axApp = hs.axuielement.applicationElement(win:application())
    
    -- 临时禁用 AXEnhancedUserInterface（这是导致卡顿/多次按键的元凶）
    local wasEnhanced = axApp.AXEnhancedUserInterface
    if wasEnhanced then
        axApp.AXEnhancedUserInterface = false
    end
    
    -- 设置窗口位置和大小（duration = 0 表示无动画）
    win:setFrame(rect, 0)
    
    -- 恢复原来的设置
    if wasEnhanced then
        axApp.AXEnhancedUserInterface = true
    end
end

-- 获取屏幕信息
function getScreenInfo()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    return {
        screen = screen,
        frame = frame,
        name = screen:name(),
        id = screen:id()
    }
end

-- ============================================
-- 功能 1：保存/恢复布局
-- ============================================

local LayoutManager = {}
LayoutManager.savedLayouts = {}

-- 保存当前所有窗口布局
function LayoutManager.save(name)
    local layout = {}
    local windows = hs.window.allWindows()
    local screenInfo = getScreenInfo()
    
    for _, win in ipairs(windows) do
        if win:isStandard() then  -- 只保存标准窗口（排除菜单栏等）
            local app = win:application()
            if app then
                local frame = win:frame()
                table.insert(layout, {
                    app = app:name(),
                    title = win:title(),
                    x = frame.x,
                    y = frame.y,
                    w = frame.w,
                    h = frame.h,
                    screenId = win:screen():id()
                })
            end
        end
    end
    
    LayoutManager.savedLayouts[name] = layout
    
    -- 同时保存到文件（持久化）
    local file = io.open(CONFIG_PATH .. "layout_" .. name .. ".json", "w")
    if file then
        file.write(file, hs.json.encode(layout))
        file:close()
    end
    
    notify("布局保存成功", "已保存 '" .. name .. "' 布局（" .. #layout .. " 个窗口）")
end

-- 从文件加载布局
function LayoutManager.loadFromFile(name)
    local file = io.open(CONFIG_PATH .. "layout_" .. name .. ".json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        local layout = hs.json.decode(content)
        if layout then
            LayoutManager.savedLayouts[name] = layout
            return true
        end
    end
    return false
end

-- 恢复布局
function LayoutManager.restore(name)
    -- 如果内存中没有，尝试从文件加载
    if not LayoutManager.savedLayouts[name] then
        if not LayoutManager.loadFromFile(name) then
            notify("恢复失败", "布局 '" .. name .. "' 不存在")
            return
        end
    end
    
    local layout = LayoutManager.savedLayouts[name]
    local restored = 0
    local failed = 0
    
    for _, item in ipairs(layout) do
        local app = hs.application.get(item.app)
        if app then
            local windows = app:allWindows()
            local found = false
            
            -- 尝试根据标题匹配
            for _, win in ipairs(windows) do
                if win:title() == item.title and win:isStandard() then
                    setWinFrame(win, hs.geometry.rect(item.x, item.y, item.w, item.h))
                    restored = restored + 1
                    found = true
                    break
                end
            end
            
            -- 如果没找到，尝试移动该应用的任意窗口
            if not found and #windows > 0 then
                for _, win in ipairs(windows) do
                    if win:isStandard() then
                        setWinFrame(win, hs.geometry.rect(item.x, item.y, item.w, item.h))
                        restored = restored + 1
                        break
                    end
                end
            end
        else
            failed = failed + 1
        end
    end
    
    notify("布局恢复完成", "成功: " .. restored .. ", 失败: " .. failed)
end

-- 列出所有保存的布局
function LayoutManager.list()
    local list = {}
    for name, _ in pairs(LayoutManager.savedLayouts) do
        table.insert(list, name)
    end
    -- 也检查文件
    local handle = io.popen("ls " .. CONFIG_PATH .. "layout_*.json 2>/dev/null | xargs -n1 basename | sed 's/layout_//g;s/.json//g'")
    if handle then
        for line in handle:lines() do
            if not LayoutManager.savedLayouts[line] then
                table.insert(list, line .. " (文件)")
            end
        end
        handle:close()
    end
    
    if #list == 0 then
        notify("保存的布局", "暂无")
    else
        notify("保存的布局", table.concat(list, ", "))
    end
end

-- ============================================
-- 功能 2：智能窗口调整（带条件判断）
-- ============================================

local SmartResize = {}

-- 配置规则
SmartResize.rules = {
    -- 规则 1：根据应用名
    apps = {
        ["Code"] = { unit = hs.layout.left70 },           -- VSCode 占左边 70%
        ["Cursor"] = { unit = hs.layout.left70 },         -- Cursor 占左边 70%
        ["WebStorm"] = { unit = hs.layout.left70 },
        ["Xcode"] = { unit = hs.layout.maximized },       -- Xcode 全屏
        ["Terminal"] = { pos = {0.7, 0.5}, size = {0.3, 0.5} },  -- 终端右下
        ["iTerm2"] = { pos = {0.7, 0.5}, size = {0.3, 0.5} },
        ["Safari"] = { unit = hs.layout.left50 },
        ["Chrome"] = { unit = hs.layout.left50 },
        ["微信"] = { pos = {0.75, 0}, size = {0.25, 0.6} },      -- 微信右上小窗口
        ["WeChat"] = { pos = {0.75, 0}, size = {0.25, 0.6} },
        ["钉钉"] = { pos = {0.75, 0.6}, size = {0.25, 0.4} },     -- 钉钉右下
        ["DingTalk"] = { pos = {0.75, 0.6}, size = {0.25, 0.4} },
    },
    
    -- 规则 2：根据窗口标题包含的关键词
    titleRules = {
        ["YouTube"] = "maximize",      -- 包含 YouTube 的窗口最大化
        ["Bilibili"] = "maximize",
        ["会议"] = "maximize",          -- 会议窗口最大化
        ["腾讯会议"] = "maximize",
    },
    
    -- 规则 3：根据屏幕名
    screenRules = {
        -- ["外接显示器"] = { unit = hs.layout.maximized },
    }
}

function SmartResize.apply()
    local win = hs.window.focusedWindow()
    if not win then 
        notify("智能调整", "没有聚焦的窗口")
        return 
    end
    
    local app = win:application():name()
    local title = win:title()
    local screen = win:screen()
    local screenName = screen:name()
    local frame = screen:frame()
    
    -- 检查标题规则（优先级最高）
    for keyword, action in pairs(SmartResize.rules.titleRules) do
        if string.find(title, keyword, 1, true) then
            if action == "maximize" then
                win:maximize()
                notify("智能调整", "检测到 '" .. keyword .. "'，已最大化")
                return
            end
        end
    end
    
    -- 检查应用规则
    local rule = SmartResize.rules.apps[app]
    if rule then
        if rule.unit then
            win:moveToUnit(rule.unit)
        elseif rule.pos and rule.size then
            setWinFrame(win, hs.geometry.rect(
                frame.x + frame.w * rule.pos[1],
                frame.y + frame.h * rule.pos[2],
                frame.w * rule.size[1],
                frame.h * rule.size[2]
            ))
        end
        notify("智能调整", app .. " 已调整")
        return
    end
    
    -- 检查屏幕规则
    local screenRule = SmartResize.rules.screenRules[screenName]
    if screenRule then
        if screenRule.unit then
            win:moveToUnit(screenRule.unit)
        end
        notify("智能调整", "根据屏幕 '" .. screenName .. "' 调整")
        return
    end
    
    -- 默认：居中
    win:centerOnScreen()
    notify("智能调整", "默认居中")
end

-- 添加自定义规则
function SmartResize.addRule(appName, config)
    SmartResize.rules.apps[appName] = config
    notify("规则添加", appName .. " 的规则已添加")
end

-- ============================================
-- 功能 3：子窗口平铺
-- ============================================

local TileManager = {}
TileManager.originalLayouts = {}  -- 存储原始布局用于恢复

-- 平铺指定应用的所有窗口
function TileManager.tile(appName)
    local app = hs.application.get(appName)
    if not app then
        notify("平铺失败", appName .. " 未运行")
        return
    end
    
    local windows = {}
    for _, win in ipairs(app:allWindows()) do
        if win:isStandard() then
            table.insert(windows, win)
        end
    end
    
    local count = #windows
    if count == 0 then
        notify("平铺失败", "没有可平铺的窗口")
        return
    end
    
    -- 保存原始布局（如果还没保存）
    local key = appName .. "_original"
    if not TileManager.originalLayouts[key] then
        local original = {}
        for _, win in ipairs(windows) do
            table.insert(original, {
                id = win:id(),
                frame = win:frame()
            })
        end
        TileManager.originalLayouts[key] = original
    end
    
    -- 计算平铺布局
    local screen = hs.screen.mainScreen():frame()
    
    -- 根据窗口数量决定布局方式
    local cols, rows
    if count <= 2 then
        cols = count
        rows = 1
    elseif count <= 4 then
        cols = 2
        rows = 2
    elseif count <= 6 then
        cols = 3
        rows = 2
    elseif count <= 9 then
        cols = 3
        rows = 3
    else
        cols = math.ceil(math.sqrt(count))
        rows = math.ceil(count / cols)
    end
    
    local cellW = screen.w / cols
    local cellH = screen.h / rows
    
    -- 应用平铺
    for i, win in ipairs(windows) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        
        -- 添加一点边距
        local margin = 4
        setWinFrame(win, hs.geometry.rect(
            screen.x + col * cellW + margin,
            screen.y + row * cellH + margin,
            cellW - margin * 2,
            cellH - margin * 2
        ))
    end
    
    notify("平铺完成", appName .. " 的 " .. count .. " 个窗口已平铺")
end

-- 恢复原始布局
function TileManager.restore(appName)
    local key = appName .. "_original"
    local original = TileManager.originalLayouts[key]
    
    if not original then
        notify("恢复失败", "没有保存 " .. appName .. " 的原始布局")
        return
    end
    
    local restored = 0
    for _, item in ipairs(original) do
        local win = hs.window.get(item.id)
        if win and win:isStandard() then
            setWinFrame(win, item.frame)
            restored = restored + 1
        end
    end
    
    TileManager.originalLayouts[key] = nil
    notify("恢复完成", appName .. " 的 " .. restored .. " 个窗口已恢复")
end

-- 平铺当前应用
function TileManager.tileCurrent()
    local win = hs.window.focusedWindow()
    if win then
        local app = win:application():name()
        TileManager.tile(app)
    end
end

-- 恢复当前应用
function TileManager.restoreCurrent()
    local win = hs.window.focusedWindow()
    if win then
        local app = win:application():name()
        TileManager.restore(app)
    end
end

-- ============================================
-- 快捷键绑定
-- ============================================

local hyper = {"cmd", "alt", "ctrl"}
local hyperShift = {"cmd", "alt", "ctrl", "shift"}

-- 布局管理
hs.hotkey.bind(hyper, "S", function() LayoutManager.save("default") end)
hs.hotkey.bind(hyper, "R", function() LayoutManager.restore("default") end)
hs.hotkey.bind(hyperShift, "S", function() 
    -- 交互式保存
    local button, name = hs.dialog.textPrompt("保存布局", "输入布局名称:", "work", "保存", "取消")
    if button == "保存" and name ~= "" then
        LayoutManager.save(name)
    end
end)
hs.hotkey.bind(hyperShift, "R", function()
    -- 交互式恢复
    local button, name = hs.dialog.textPrompt("恢复布局", "输入布局名称:", "work", "恢复", "取消")
    if button == "恢复" and name ~= "" then
        LayoutManager.restore(name)
    end
end)
hs.hotkey.bind(hyper, "L", function() LayoutManager.list() end)

-- 智能调整
hs.hotkey.bind({"cmd", "alt"}, "M", function() SmartResize.apply() end)

-- 子窗口平铺
hs.hotkey.bind(hyper, "T", function() TileManager.tileCurrent() end)
hs.hotkey.bind(hyper, "O", function() TileManager.restoreCurrent() end)

-- ============================================
-- 窗口基本操作（类似 Rectangle）
-- ============================================

-- 半屏 - 无动画
hs.hotkey.bind({"cmd", "alt"}, "Left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen():frame()
    setWinFrame(win, hs.geometry.rect(screen.x, screen.y, screen.w * 0.5, screen.h))
end)

hs.hotkey.bind({"cmd", "alt"}, "Right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen():frame()
    setWinFrame(win, hs.geometry.rect(screen.x + screen.w * 0.5, screen.y, screen.w * 0.5, screen.h))
end)

hs.hotkey.bind({"cmd", "alt"}, "Up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen():frame()
    setWinFrame(win, hs.geometry.rect(screen.x, screen.y, screen.w, screen.h))
end)

hs.hotkey.bind({"cmd", "alt"}, "Down", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen():frame()
    local w = screen.w * 0.6
    local h = screen.h * 0.6
    setWinFrame(win, hs.geometry.rect(
        screen.x + (screen.w - w) / 2,
        screen.y + (screen.h - h) / 2,
        w, h
    ))
end)

-- 自定义比例分屏（30%/70%）- 使用直接计算避免动画问题
hs.hotkey.bind(hyper, "Left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen():frame()
    setWinFrame(win, hs.geometry.rect(screen.x, screen.y, screen.w * 0.3, screen.h))
end)

hs.hotkey.bind(hyper, "Right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen():frame()
    setWinFrame(win, hs.geometry.rect(screen.x + screen.w * 0.3, screen.y, screen.w * 0.7, screen.h))
end)

-- ============================================
-- 启动提示
-- ============================================

notify("窗口管理器已加载", "Cmd+Alt+M 智能调整 | Cmd+Alt+Ctrl+T 平铺")
print("[WindowManager] 配置已加载")
