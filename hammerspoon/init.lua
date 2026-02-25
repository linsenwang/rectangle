-- ============================================
-- Rectangle 风格窗口管理器配置
-- 主修饰键：Ctrl + Option
-- ============================================

-- 禁用窗口动画
hs.window.animationDuration = 0

-- 配置文件路径
local CONFIG_PATH = os.getenv("HOME") .. "/.hammerspoon/"

-- ============================================
-- 修饰键定义
-- ============================================

local mash = {"ctrl", "alt"}           -- 主修饰键：Ctrl + Option
local mashShift = {"ctrl", "alt", "shift"}  -- Ctrl + Option + Shift

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
    end
end

-- 左半屏
hs.hotkey.bind(mash, "left", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x, max.y, max.w * 0.5, max.h))
end)

-- 右半屏
hs.hotkey.bind(mash, "right", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x + max.w * 0.5, max.y, max.w * 0.5, max.h))
end)

-- 上半屏
hs.hotkey.bind(mash, "up", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x, max.y, max.w, max.h * 0.5))
end)

-- 下半屏
hs.hotkey.bind(mash, "down", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x, max.y + max.h * 0.5, max.w, max.h * 0.5))
end)

-- 最大化
hs.hotkey.bind(mash, "return", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x, max.y, max.w, max.h))
end)

-- 居中
hs.hotkey.bind(mash, "c", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    win:centerOnScreen()
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
    local margin = 10
    setWinFrame(win, hs.geometry.rect(
        max.x + margin, max.y + margin,
        max.w - margin * 2, max.h - margin * 2
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
    setWinFrame(win, hs.geometry.rect(max.x, max.y, max.w * 0.5, max.h * 0.5))
end)

-- 右上
hs.hotkey.bind(mash, "i", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x + max.w * 0.5, max.y, max.w * 0.5, max.h * 0.5))
end)

-- 左下
hs.hotkey.bind(mash, "0", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x, max.y + max.h * 0.5, max.w * 0.5, max.h * 0.5))
end)

-- 右下
hs.hotkey.bind(mash, "2", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x + max.w * 0.5, max.y + max.h * 0.5, max.w * 0.5, max.h * 0.5))
end)

-- 左三分之一
hs.hotkey.bind(mash, "\\", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x, max.y, max.w / 3, max.h))
end)

-- 中三分之一 (使用 . 键，因为 m 被 moveDown 占用)
-- 循环切换 1/2, 1/3, 2/3 大小（类似 Rectangle 的 repeated execution）
local cycleSizes = {0.5, 1/3, 2/3}
local currentSizeIndex = 1

hs.hotkey.bind(mash, "tab", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    local size = cycleSizes[currentSizeIndex]
    currentSizeIndex = currentSizeIndex % #cycleSizes + 1
    setWinFrame(win, hs.geometry.rect(max.x, max.y, max.w * size, max.h))
    notify("窗口大小", math.floor(size * 100) .. "%")
end)

-- 右三分之一
hs.hotkey.bind(mash, "/", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    saveWindowState(win)
    local max = getWinScreen(win)
    setWinFrame(win, hs.geometry.rect(max.x + max.w * 2 / 3, max.y, max.w / 3, max.h))
end)

-- ============================================
-- 窗口移动（不改变大小）
-- ============================================

local moveStep = 50  -- 移动步长

hs.hotkey.bind(mash, ",", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x - moveStep, frame.y, frame.w, frame.h))
end)

hs.hotkey.bind(mash, "'", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x + moveStep, frame.y, frame.w, frame.h))
end)

hs.hotkey.bind(mash, "[", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local frame = win:frame()
    setWinFrame(win, hs.geometry.rect(frame.x, frame.y - moveStep, frame.w, frame.h))
end)

-- moveDown: m 键
hs.hotkey.bind(mash, "m", function()
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
-- 启动提示
-- ============================================

notify("Rectangle 风格管理器已加载", "Ctrl+Option + 方向键/字母")
print("[RectangleHammerspoon] 配置已加载")
