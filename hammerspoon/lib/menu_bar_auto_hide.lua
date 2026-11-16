-- ============================================
-- 菜单栏自动隐藏策略
-- 连接外置显示器时：Automatically hide and show the menu bar = In Full Screen Only
-- 仅使用内置屏幕时：Automatically hide and show the menu bar = Always
-- 依赖 System Events 自动化权限（首次设置会弹窗请求）
-- ============================================

MenuBarAutoHide = MenuBarAutoHide or {}

local config = {
    debounce = 1.5,   -- 屏幕变化去抖（秒）
    wakeDelay = 3,    -- 唤醒后等显示器重新识别
}

local function log(msg)
    print("[MenuBarAutoHide] " .. msg)
end

-- 内置屏名称随机型/系统语言不同
local builtinPatterns = { "built%-in", "color lcd", "retina display", "内建", "内置" }

local function isBuiltinScreen(screen)
    local name = string.lower(screen:name() or "")
    for _, pattern in ipairs(builtinPatterns) do
        if name:find(pattern) then return true end
    end
    return false
end

-- 有外置屏（含合盖只用外接屏的情况）即视为外接模式
local function hasExternalScreen()
    local screens = hs.screen.allScreens()
    if #screens > 1 then return true end
    if #screens == 1 then return not isBuiltinScreen(screens[1]) end
    return false
end

-- In Full Screen Only 对应 _HIHideMenuBar=0 + AppleMenuBarVisibleInFullscreen=0
-- Never 对应 AppleMenuBarVisibleInFullscreen=1，先归零避免落到 Never
local function ensureFullscreenBarVisible()
    local out = hs.execute("defaults read .GlobalPreferences AppleMenuBarVisibleInFullscreen 2>/dev/null")
    if out:gsub("%s+", "") ~= "0" then
        hs.execute("defaults write .GlobalPreferences AppleMenuBarVisibleInFullscreen -bool false")
    end
end

local function currentAutoHide()
    local ok, res = hs.osascript.applescript(
        'tell application "System Events" to get autohide menu bar of dock preferences')
    if ok and type(res) == "boolean" then
        return res
    end
    -- AppleScript 不可用时退回读偏好
    local out = hs.execute("defaults read .GlobalPreferences _HIHideMenuBar 2>/dev/null")
    return out:gsub("%s+", "") == "1"
end

local permissionWarned = false

-- AppleScript 设置会立即生效；defaults 写入需要重新登录
local function setAutoHide(hide)
    local ok, _, err = hs.osascript.applescript(string.format(
        'tell application "System Events" to set autohide menu bar of dock preferences to %s',
        hide and "true" or "false"))
    if ok then return true end

    log("AppleScript 设置失败：" .. hs.inspect(err))
    hs.execute(string.format(
        "defaults write .GlobalPreferences _HIHideMenuBar -bool %s", hide and "true" or "false"))
    if not permissionWarned then
        permissionWarned = true
        notify("菜单栏自动隐藏未立即生效",
            "请在 系统设置 > 隐私与安全性 > 自动化 中允许 Hammerspoon 控制 System Events")
    end
    return false
end

local function applyMode(reason)
    if not MenuBarAutoHide.started then return end

    local external = hasExternalScreen()
    local hide = not external
    ensureFullscreenBarVisible()

    if currentAutoHide() == hide then
        log(string.format("%s：%s，菜单栏设置无需变更", reason, external and "外接屏" or "内置屏"))
        return
    end

    if setAutoHide(hide) then
        log(string.format("%s：%s，菜单栏改为 %s", reason,
            external and "外接屏" or "内置屏",
            hide and "Always" or "In Full Screen Only"))
    end
end

local function scheduleApply(reason)
    if not MenuBarAutoHide.changeTimer then return end
    MenuBarAutoHide.pendingReason = reason
    MenuBarAutoHide.changeTimer:start()
end

local function onWake()
    if MenuBarAutoHide.wakeTimer then MenuBarAutoHide.wakeTimer:stop() end
    MenuBarAutoHide.wakeTimer = hs.timer.doAfter(config.wakeDelay, function()
        applyMode("系统唤醒")
    end)
end

function MenuBarAutoHide.init()
    if MenuBarAutoHide.screenWatcher then MenuBarAutoHide.screenWatcher:stop() end
    if MenuBarAutoHide.caffeinateWatcher then MenuBarAutoHide.caffeinateWatcher:stop() end

    MenuBarAutoHide.changeTimer = hs.timer.delayed.new(config.debounce, function()
        applyMode(MenuBarAutoHide.pendingReason or "屏幕变化")
    end)

    MenuBarAutoHide.started = true

    MenuBarAutoHide.screenWatcher = hs.screen.watcher.new(function()
        scheduleApply("屏幕变化")
    end)
    MenuBarAutoHide.screenWatcher:start()

    MenuBarAutoHide.caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
        if eventType == hs.caffeinate.watcher.systemDidWake then
            onWake()
        end
    end)
    MenuBarAutoHide.caffeinateWatcher:start()

    applyMode("启动")
end

MenuBarAutoHide.init()
