-- ============================================
-- 菜单栏自动隐藏策略
-- 连接外置显示器时：Automatically hide and show the menu bar = In Full Screen Only
-- 仅使用内置屏幕时：Automatically hide and show the menu bar = Always
-- 依赖 System Events 自动化权限（首次设置会弹窗请求）
-- ============================================

MenuBarAutoHide = MenuBarAutoHide or {}

local function log(msg)
    print("[MenuBarAutoHide] " .. msg)
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

local function apply(_, reason)
    local external = AutoPolicy.hasExternalScreen()
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

local policy = AutoPolicy.new({
    name = "MenuBarAutoHide",
    debounce = 1.5,   -- 屏幕变化去抖（秒）
    wakeDelay = 3,    -- 唤醒后等显示器重新识别
    apply = apply,
})

MenuBarAutoHide.policy = policy

function MenuBarAutoHide.init()
    policy:start()
end

MenuBarAutoHide.init()
