-- ============================================
-- 统一弹窗（hs.alert 封装）
-- ============================================
-- 项目里所有提示弹窗（CapsWriter / OCR / 键盘锁 / 屏幕信息 / 布局 / 平铺 …）
-- 都从这里走，样式、位置、时长、外观自适应只有这一处定义：
--   · 浅色/深色模式自动切换底色与字色，跟随系统外观实时刷新
--   · 同一 channel 的弹窗互斥：新的顶掉旧的，不会叠成一堆
--   · 顶部贴边的弹窗在带刘海的屏幕上自动下移，让开刘海和菜单栏那一条
-- 用法：
--   Alert.show("文字", { timeout = 2 })
--   Alert.show("文字", { channel = "ocr", edge = 1, align = "right", timeout = 3 })
-- 参数（opts，均可省略）：
--   timeout  显示时长（秒），默认 Alert.defaultTimeout
--   channel  互斥通道名，默认 "default"（同一通道的新弹窗会关闭旧的）
--   edge     贴边位置：0=居中 1=顶部 2=底部（对应 hs.alert 的 atScreenEdge；顶部会自动避开刘海）
--   align    文字对齐：left / center / right
--   replace  是否顶掉同通道旧弹窗，默认 true

local Alert = {}

-- 弹窗默认显示时长（秒）
Alert.defaultTimeout = 2

-- 当前系统外观："light" / "dark"（结果缓存，避免被频繁调用时反复 fork shell）
local cachedAppearance = nil

local function detectAppearance()
    local ok, style = pcall(hs.host.interfaceStyle)
    if ok and type(style) == "string" then
        style = string.lower(style)
        if style == "light" or style == "dark" then
            return style
        end
    end
    -- 回退：defaults 读不到 AppleInterfaceStyle 即浅色
    local out = hs.execute("defaults read -g AppleInterfaceStyle 2>/dev/null")
    if type(out) == "string" and string.lower((string.gsub(out, "%s+", ""))) == "dark" then
        return "dark"
    end
    return "light"
end

function Alert.appearance()
    if not cachedAppearance then
        cachedAppearance = detectAppearance()
    end
    return cachedAppearance
end

-- 弹窗配色：浅色模式浅底深字，深色模式保持系统默认深底白字
local alertColors = {
    dark = {
        fillColor   = { white = 0,    alpha = 0.95 },
        textColor   = { white = 1,    alpha = 1 },
        strokeColor = { white = 1,    alpha = 1 },
    },
    light = {
        fillColor   = { white = 0.96, alpha = 0.95 },
        textColor   = { white = 0.1,  alpha = 1 },
        strokeColor = { white = 0.78, alpha = 1 },
    },
}

function Alert.applyAppearance()
    local colors = alertColors[Alert.appearance()] or alertColors.dark
    for key, value in pairs(colors) do
        hs.alert.defaultStyle[key] = value
    end
end

Alert.applyAppearance()

-- 系统外观切换时刷新缓存并同步弹窗配色
Alert.appearanceWatcher = hs.distributednotifications.new(function()
    cachedAppearance = nil
    Alert.applyAppearance()
end, "AppleInterfaceThemeChangedNotification")
Alert.appearanceWatcher:start()

-- 每个通道当前弹窗的 UUID，用于互斥替换
local channels = {}

-- 屏幕顶端预留、放不下弹窗的高度
-- hs.alert 的顶部贴边是按 fullFrame 对齐的，也就是屏幕最上沿；带刘海的机型上这一条
-- 正好是刘海 + 菜单栏（本机 43 点，其中刘海 37 点），居中的弹窗会被刘海挡住中间一块。
-- 普通 Mac 的菜单栏只有 22~25 点，弹窗本来就画在菜单栏之上，不用避让，所以按高度区分。
local function notchInset(screenObj)
    local reserved = screenObj:frame().y - screenObj:fullFrame().y
    if reserved >= 32 then
        return reserved
    end
    return 0
end

-- hs.alert 没有位置参数，顶部贴边的弹窗只能先显示再整体下移
local function shiftBelowNotch(uuid, screenObj)
    local inset = notchInset(screenObj)
    if inset == 0 then
        return
    end
    for _, entry in ipairs(hs.alert._visibleAlerts) do
        if entry.UUID == uuid then
            entry.frame.y = entry.frame.y + inset
            for _, item in ipairs(entry.drawings) do
                local frame = item:frame()
                item:setFrame({ x = frame.x, y = frame.y + inset, w = frame.w, h = frame.h })
            end
            return
        end
    end
end

-- 显示弹窗，返回 UUID（失败返回 nil）
function Alert.show(message, opts)
    opts = opts or {}
    local channel = opts.channel or "default"

    if channels[channel] and opts.replace ~= false then
        pcall(function() hs.alert.closeSpecific(channels[channel]) end)
        channels[channel] = nil
    end

    local style = {}
    if opts.edge then
        style.atScreenEdge = opts.edge
    end
    if opts.align then
        style.textStyle = { alignment = opts.align }
    end

    local screenObj = hs.screen.mainScreen()
    local ok, uuid = pcall(hs.alert.show, message, style, screenObj, opts.timeout or Alert.defaultTimeout)
    if ok then
        channels[channel] = uuid
        if style.atScreenEdge == 1 and screenObj then
            shiftBelowNotch(uuid, screenObj)
        end
        return uuid
    end

    print("[Alert] 弹窗显示失败: " .. tostring(uuid))
    return nil
end

-- 关闭指定通道的弹窗（默认关闭全局 "default" 通道）
function Alert.close(channel)
    channel = channel or "default"
    if channels[channel] then
        pcall(function() hs.alert.closeSpecific(channels[channel]) end)
        channels[channel] = nil
    end
end

_G.Alert = Alert

return Alert
