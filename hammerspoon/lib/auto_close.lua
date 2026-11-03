-- ============================================
-- 应用窗口自动关闭：切到后台满 N 秒后关闭窗口（不退出应用）
-- ============================================
-- 配置见 config.lua 的 AutoCloseConfig：
--   apps = { [应用名或 bundle ID] = 闲置秒数 }
--
-- 完全事件驱动，不做轮询：
--   · hs.application.watcher 的 activated / deactivated / launched / terminated
--   · hs.window.filter 的 windowFocused / windowCreated / windowDestroyed
-- 应用在前台时不存在待关闭定时器；切到后台才挂一个一次性定时器，
-- 重新激活或窗口获得焦点时立刻取消。因此不需要额外的鼠标/键盘 hook：
-- 任何对窗口的交互都会先让应用/窗口获得焦点。
--
-- 关闭用 win:close()，不会结束应用进程；全屏窗口默认跳过，
-- 避免误关正在视频通话 / 屏幕共享 / 全屏播放的窗口。

local DEFAULT_IDLE_SECONDS = 60

-- 重载配置时先停掉上一次的监听与定时器，避免重复触发
if _G.AutoClose and _G.AutoClose.stop then
    pcall(_G.AutoClose.stop)
end
-- 兼容旧版 QQ 专用模块
if _G.QQAutoClose and _G.QQAutoClose.stop then
    pcall(_G.QQAutoClose.stop)
    _G.QQAutoClose = nil
end

local M = {}
_G.AutoClose = M

local rules = {}       -- { key, idleSeconds, closeFullScreen }
local states = {}      -- key -> { timer }
local appWatcher = nil
local windowFilter = nil

local function cfg()
    return AutoCloseConfig or {}
end

local function log(fmt, ...)
    print("[AutoClose] " .. string.format(fmt, ...))
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function buildRules()
    rules = {}
    states = {}

    local apps = cfg().apps or {}
    for key, value in pairs(apps) do
        local rule = {
            key = key,
            idleSeconds = DEFAULT_IDLE_SECONDS,
            closeFullScreen = cfg().closeFullScreen == true,
        }

        if type(value) == "number" then
            rule.idleSeconds = value
        elseif type(value) == "table" then
            rule.idleSeconds = value.idleSeconds or DEFAULT_IDLE_SECONDS
            if value.closeFullScreen ~= nil then
                rule.closeFullScreen = value.closeFullScreen
            end
        else
            log("忽略无效配置: " .. tostring(key))
            rule = nil
        end

        if rule then
            table.insert(rules, rule)
            states[key] = { timer = nil }
        end
    end

    table.sort(rules, function(a, b) return a.key < b.key end)
end

local function matchesApp(rule, app)
    if not app then return false end

    local okBundle, bundleID = pcall(function() return app:bundleID() end)
    if okBundle and bundleID and lower(bundleID) == lower(rule.key) then
        return true
    end

    local okName, name = pcall(function() return app:name() end)
    return okName and name and lower(name) == lower(rule.key)
end

-- 应用名 / bundle ID 都支持；返回匹配到的应用对象
local function findApp(rule)
    local ok, app = pcall(function() return hs.application.get(rule.key) end)
    if ok and app then return app end

    -- 大小写不一致的 bundle ID 等情况下，退回到运行中的应用里逐个匹配
    local okApps, apps = pcall(function() return hs.application.runningApplications() end)
    if not okApps then return nil end
    for _, candidate in ipairs(apps) do
        if matchesApp(rule, candidate) then return candidate end
    end
    return nil
end

local function matchingRules(app)
    local matched = {}
    for _, rule in ipairs(rules) do
        if matchesApp(rule, app) then
            table.insert(matched, rule)
        end
    end
    return matched
end

local function isFrontmost(app)
    local ok, result = pcall(function() return app:isFrontmost() end)
    return ok and result
end

local function windowCount(app)
    local ok, windows = pcall(function() return app:allWindows() end)
    return ok and #windows or 0
end

local function cancelClose(rule)
    local state = states[rule.key]
    if state and state.timer then
        state.timer:stop()
        state.timer = nil
    end
end

local function closeWindows(app, rule)
    local closed, failed, skippedFullScreen = 0, 0, 0

    for _, win in ipairs(app:allWindows()) do
        local standard = false
        pcall(function() standard = win:isStandard() end)

        if standard then
            local fullScreen = false
            if not rule.closeFullScreen then
                pcall(function() fullScreen = win:isFullScreen() end)
            end

            if fullScreen then
                skippedFullScreen = skippedFullScreen + 1
            else
                local ok, result = pcall(function() return win:close() end)
                if ok and result then
                    closed = closed + 1
                else
                    failed = failed + 1
                end
            end
        end
    end

    if closed > 0 or failed > 0 or skippedFullScreen > 0 then
        log(string.format("%s: 关闭窗口 成功 %d，失败 %d，跳过的全屏窗口 %d",
            rule.key, closed, failed, skippedFullScreen))
    end
    return closed
end

-- 应用进入后台：挂一个一次性定时器，到点再确认一次状态后关闭
local function scheduleClose(rule)
    cancelClose(rule)

    local state = states[rule.key]
    state.timer = hs.timer.doAfter(rule.idleSeconds, function()
        state.timer = nil

        local app = findApp(rule)
        if not app then return end          -- 已退出
        if isFrontmost(app) then return end -- 期间又回到前台了
        if windowCount(app) == 0 then return end

        closeWindows(app, rule)
    end)
end

-- 应用进入后台，或没有窗口：按当前状态挂定时器 / 取消
local function scheduleRule(rule, app)
    if not app or windowCount(app) == 0 then
        cancelClose(rule)
    else
        scheduleClose(rule)
    end
end

-- 应用在前台，或已经没有窗口：不需要关闭
local function settleRule(rule, app)
    if not app or isFrontmost(app) or windowCount(app) == 0 then
        cancelClose(rule)
    else
        scheduleClose(rule)
    end
end

local function handleAppEvent(eventType, appObj)
    if not appObj then return end

    local matched = matchingRules(appObj)
    if #matched == 0 then return end

    if eventType == hs.application.watcher.activated
        or eventType == hs.application.watcher.unhidden then
        for _, rule in ipairs(matched) do
            settleRule(rule, appObj)
        end

    elseif eventType == hs.application.watcher.deactivated
        or eventType == hs.application.watcher.hidden
        or eventType == hs.application.watcher.launched then
        -- deactivated 回调里 isFrontmost 可能还没翻转，这里不判断前台，
        -- 直接挂定时器；到点时再确认一次，期间激活会被 activated 取消。
        for _, rule in ipairs(matched) do
            scheduleRule(rule, appObj)
        end

    elseif eventType == hs.application.watcher.terminated then
        for _, rule in ipairs(matched) do
            cancelClose(rule)
        end
    end
end

local function handleWindowTouched(win)
    local ok, app = pcall(function() return win:application() end)
    if not ok or not app then return end

    for _, rule in ipairs(matchingRules(app)) do
        settleRule(rule, app)
    end
end

local function handleWindowDestroyed()
    -- 窗口数量变化后，没有窗口的应用不需要继续等待关闭
    for _, rule in ipairs(rules) do
        local app = findApp(rule)
        if not app or windowCount(app) == 0 then
            cancelClose(rule)
        end
    end
end

local function standardWindows(app)
    local windows = {}
    for _, win in ipairs(app:allWindows()) do
        local standard = false
        pcall(function() standard = win:isStandard() end)
        if standard then
            table.insert(windows, { id = win:id(), title = win:title() })
        end
    end
    return windows
end

-- 供调试 / 手动触发
function M.status()
    local result = {}
    for _, rule in ipairs(rules) do
        local app = findApp(rule)
        local state = states[rule.key]
        table.insert(result, {
            app = rule.key,
            running = app ~= nil,
            frontmost = app ~= nil and isFrontmost(app) or false,
            idleLimit = rule.idleSeconds,
            closeInSeconds = state.timer and state.timer:nextTrigger() or nil,
            windows = app and standardWindows(app) or {},
        })
    end
    return result
end

function M.closeNow(key)
    for _, rule in ipairs(rules) do
        if not key or lower(rule.key) == lower(key) then
            local app = findApp(rule)
            if app then
                cancelClose(rule)
                return closeWindows(app, rule)
            end
        end
    end
    return 0
end

function M.stop()
    for _, rule in ipairs(rules) do
        cancelClose(rule)
    end
    if appWatcher then
        appWatcher:stop()
        appWatcher = nil
    end
    if windowFilter then
        pcall(function() windowFilter:unsubscribeAll() end)
        windowFilter = nil
    end
end

buildRules()

if cfg().enabled == false then
    log("已在配置中禁用")
    return M
end

if #rules == 0 then
    log("未配置任何应用（AutoCloseConfig.apps 为空）")
    return M
end

appWatcher = hs.application.watcher.new(function(_, eventType, appObj)
    handleAppEvent(eventType, appObj)
end)
appWatcher:start()

windowFilter = hs.window.filter.new(function(win)
    local ok, app = pcall(function() return win:application() end)
    return ok and #matchingRules(app) > 0
end)
windowFilter:subscribe(hs.window.filter.windowFocused, handleWindowTouched)
windowFilter:subscribe(hs.window.filter.windowCreated, handleWindowTouched)
windowFilter:subscribe(hs.window.filter.windowDestroyed, handleWindowDestroyed)

-- 配置加载时已经在后台运行的应用：补挂一次定时器（仅初始化时检查一次，不是轮询）
for _, rule in ipairs(rules) do
    settleRule(rule, findApp(rule))
end

local names = {}
for _, rule in ipairs(rules) do
    table.insert(names, string.format("%s=%ds", rule.key, rule.idleSeconds))
end
log("已启动：" .. table.concat(names, ", ") .. "（后台闲置后关闭窗口，不退出应用）")
