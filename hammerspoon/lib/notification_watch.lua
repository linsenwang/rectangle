-- ============================================
-- 通知监听：通知内容命中关键词时自动执行命令（签到）
-- ============================================
-- 原理：macOS 的通知横幅在「通知中心」(com.apple.notificationcenterui) 进程的
--       AX 树里是 subrole = AXNotificationCenterBanner 的元素，其 AXDescription
--       形如「应用名, 标题, 副标题, 正文」。
--       AXObserver 是系统事件驱动的：有通知 UI 变化才回调，没有通知时零唤醒、
--       零 CPU，所以这里不做轮询。兜底只有两处：
--         · 通知中心进程重启时重建观察者（hs.application.watcher 事件驱动）
--         · 可选的低频健康检查（默认 5 分钟，只查一个本地标志，不遍历 AX 树）
--       已处理的通知 id 会落到 notification_watch_state.json，
--       这样重载配置时不会把通知中心里已有的旧通知再触发一遍。
-- 配置见 config.lua 的 NotificationWatchConfig

local NC_BUNDLE_ID = "com.apple.notificationcenterui"
local NC_APP_NAME = "Notification Center"

-- 通知元素的 subrole（提醒样式的通知可能是 alert，统一按包含匹配）
local BANNER_SUBROLE = "AXNotificationCenterBanner"

-- 注册到应用元素上的通知类型
local WATCH_NOTIFICATIONS = {
    "AXLayoutChanged",
    "AXCreated",
    "AXWindowCreated",
    "AXValueChanged",
    "AXTitleChanged",
}

-- 已处理通知 id 的持久化文件与最大保留条数
local STATE_FILE = (CONFIG_PATH or (os.getenv("HOME") or "") .. "/.hammerspoon/") .. "notification_watch_state.json"
local MAX_PERSISTED = 200

-- 重载配置时先停掉上一次的监听，避免重复触发
if _G.NotificationWatch and _G.NotificationWatch.stop then
    pcall(_G.NotificationWatch.stop)
end

local M = {}
_G.NotificationWatch = M

local observer = nil         -- hs.axuielement.observer
local ncApp = nil            -- 通知中心应用对象
local healthTimer = nil      -- 低频健康检查定时器（可选）
local appWatcher = nil       -- 通知中心进程重启监听
local restartPending = false -- 是否有待执行的重建
local seen = {}              -- 通知标识 -> true（已处理过）
local seenOrder = {}         -- 通知标识，按处理顺序（用于持久化和淘汰）
local stateDirty = false
local saveScheduled = false
local lastTriggerAt = 0
local runningTask = nil      -- 正在执行的 hs.task

local function cfg()
    return NotificationWatchConfig or {}
end

local function log(fmt, ...)
    print("[NotificationWatch] " .. string.format(fmt, ...))
end

-- 读取 AX 属性，元素已销毁时返回 nil
local function attr(el, name)
    if not el then return nil end
    local ok, v = pcall(function() return el:attributeValue(name) end)
    if ok then return v end
    return nil
end

-- 是否为通知元素（subrole 在不同系统版本上略有差异，按包含匹配）
local function isBanner(el)
    local sub = attr(el, "AXSubrole")
    if type(sub) ~= "string" then return false end
    return sub == BANNER_SUBROLE or sub:find("NotificationCenter", 1, true) ~= nil
end

-- 收集当前通知中心里的所有通知元素
local function collectBanners()
    local result = {}
    if not ncApp then
        -- 首次调用（如启动时的 seedSeen）可能还没拿到应用对象
        local apps = hs.application.applicationsForBundleID(NC_BUNDLE_ID)
        ncApp = apps and apps[1] or nil
    end
    if not ncApp or not ncApp:isRunning() then return result end

    local okApp, appEl = pcall(hs.axuielement.applicationElement, ncApp)
    if not okApp or not appEl then return result end

    local function walk(el, depth)
        if not el or depth > 8 then return end
        if isBanner(el) then
            table.insert(result, el)
            return
        end
        for _, child in ipairs(attr(el, "AXChildren") or {}) do
            walk(child, depth + 1)
        end
    end

    for _, win in ipairs(attr(appEl, "AXWindows") or {}) do
        walk(win, 0)
    end
    return result
end

-- 通知的可读文本：AXDescription（应用名, 标题, 副标题, 正文），再用标题/正文补齐
local function bannerText(el)
    local parts = {}
    for _, name in ipairs({"AXDescription", "AXTitle", "AXValue"}) do
        local v = attr(el, name)
        if type(v) == "string" and v ~= "" then
            table.insert(parts, v)
        end
    end
    return table.concat(parts, " ")
end

-- 极少见的情况下通知没有 AXIdentifier，用文本的哈希当标识（不落明文）
local function textKey(text)
    local ok, digest = pcall(function() return hs.hash.md5(text) end)
    if ok and digest then return "hash:" .. digest end
    return nil
end

local function bannerKey(el)
    local id = attr(el, "AXIdentifier")
    if type(id) == "string" and id ~= "" then return id end
    local text = bannerText(el)
    if text == "" then return nil end
    return textKey(text)
end

-- 返回命中的关键词，未命中返回 nil
local function hitKeyword(text)
    if not text or text == "" then return nil end
    for _, kw in ipairs(cfg().keywords or {}) do
        if kw ~= "" and text:find(kw, 1, true) then return kw end
    end
    return nil
end

-- ============================================
-- 已处理通知 id 的持久化
-- ============================================

local function saveState()
    local file = io.open(STATE_FILE, "w")
    if not file then return end
    local ok, encoded = pcall(function() return hs.json.encode({ seen = seenOrder }) end)
    if ok and encoded then
        file:write(encoded)
    end
    file:close()
    stateDirty = false
end

-- 写盘去抖：一批通知进来只写一次
local function scheduleSave()
    stateDirty = true
    if saveScheduled then return end
    saveScheduled = true
    hs.timer.doAfter(2, function()
        saveScheduled = false
        if stateDirty then
            pcall(saveState)
        end
    end)
end

local function markSeen(key)
    if not key or seen[key] then return false end
    seen[key] = true
    table.insert(seenOrder, key)
    while #seenOrder > MAX_PERSISTED do
        local oldest = table.remove(seenOrder, 1)
        if oldest then seen[oldest] = nil end
    end
    scheduleSave()
    return true
end

local function loadState()
    local file = io.open(STATE_FILE, "r")
    if not file then return end
    local content = file:read("*a")
    file:close()

    local ok, data = pcall(function() return hs.json.decode(content) end)
    if not ok or type(data) ~= "table" or type(data.seen) ~= "table" then return end

    local restored = 0
    for _, key in ipairs(data.seen) do
        if type(key) == "string" and not seen[key] then
            seen[key] = true
            table.insert(seenOrder, key)
            restored = restored + 1
        end
    end
    if restored > 0 then
        log("已恢复 %d 条已处理通知记录", restored)
    end
end

-- 把当前通知中心里已有的通知标记为已处理（避免重载配置时补触发旧通知）
local function seedSeen()
    for _, el in ipairs(collectBanners()) do
        markSeen(bannerKey(el))
    end
    if stateDirty then
        pcall(saveState)
    end
end

-- 执行配置里的命令（异步，不阻塞 Hammerspoon）
local function runCommand(reason)
    local now = hs.timer.secondsSinceEpoch()
    local cooldown = cfg().cooldown or 60

    if runningTask then
        log("上一次任务仍在运行，跳过：%s", reason)
        return
    end
    if now - lastTriggerAt < cooldown then
        log("冷却中（还剩 %.0f 秒），跳过：%s", cooldown - (now - lastTriggerAt), reason)
        return
    end

    local command = cfg().command
    if not command or command == "" then
        log("未配置 command，跳过")
        return
    end

    lastTriggerAt = now
    log("触发命令：%s（%s）", command, reason)
    if cfg().notifyOnTrigger then
        notify("检测到签到通知", "正在执行 " .. (command:match("[^/]+$") or command))
    end

    -- 继承 Hammerspoon 进程的环境（PATH 为 /usr/bin:/bin:/usr/sbin:/sbin，脚本够用）
    local task = hs.task.new("/bin/bash", function(code, _, err)
        runningTask = nil
        if code == 0 then
            log("命令执行完成")
        else
            log("命令执行失败（exit %s）：%s", tostring(code), tostring(err))
            notify("签到脚本失败", "exit " .. tostring(code))
        end
    end, {command})

    if not task then
        log("创建任务失败：%s", command)
        return
    end

    runningTask = task
    task:start()
end

-- 处理一条通知（按标识去重）
local function processBanner(el)
    local key = bannerKey(el)
    if not key or not markSeen(key) then return end

    local text = bannerText(el)
    log("新通知：%s", text)

    local kw = hitKeyword(text)
    if kw then
        runCommand(string.format("命中「%s」：%s", kw, text))
    end
end

local function scan()
    for _, el in ipairs(collectBanners()) do
        processBanner(el)
    end
end

local function stopObserver()
    if observer then
        pcall(function() observer:stop() end)
        observer = nil
    end
end

-- 前向声明：scheduleRestart 与观察者回调都要用到
local startObserver

local function scheduleRestart(delay)
    if restartPending then return end
    restartPending = true
    hs.timer.doAfter(delay or 5, function()
        restartPending = false
        startObserver()
    end)
end

startObserver = function()
    if observer then return end

    local apps = hs.application.applicationsForBundleID(NC_BUNDLE_ID)
    ncApp = apps and apps[1] or nil
    if not ncApp or not ncApp:isRunning() then
        ncApp = nil
        log("未找到通知中心进程，5 秒后重试")
        scheduleRestart(5)
        return
    end

    local okNew, obs = pcall(hs.axuielement.observer.new, ncApp:pid())
    if not okNew or not obs then
        log("创建观察者失败：%s", tostring(obs))
        scheduleRestart(5)
        return
    end
    observer = obs

    observer:callback(function(_, element, notification)
        if isBanner(element) then
            processBanner(element)
        elseif notification == "AXCreated" or notification == "AXWindowCreated" then
            -- 通知中心窗口刚出现，补齐一次全量扫描
            scan()
        end
    end)

    local okApp, appEl = pcall(hs.axuielement.applicationElement, ncApp)
    if not okApp or not appEl then
        log("获取通知中心 AX 元素失败，5 秒后重试")
        stopObserver()
        scheduleRestart(5)
        return
    end

    for _, name in ipairs(WATCH_NOTIFICATIONS) do
        local okAdd, err = pcall(function() return observer:addWatcher(appEl, name) end)
        if not okAdd then
            log("注册 %s 失败：%s", name, tostring(err))
        end
    end

    observer:start()
    log("已开始监听通知，关键词：%s", table.concat(cfg().keywords or {}, "、"))
end

-- 通知中心进程退出时观察者会失效，重新启动时重建
local function startAppWatcher()
    appWatcher = hs.application.watcher.new(function(appName, event, app)
        local bid = app and app:bundleID()
        local isNC = bid == NC_BUNDLE_ID or (bid == nil and appName == NC_APP_NAME)
        if not isNC then return end

        if event == hs.application.watcher.terminated then
            log("通知中心进程已退出，等待其重启")
            stopObserver()
            ncApp = nil
        elseif event == hs.application.watcher.launched then
            log("通知中心进程已启动，重建监听")
            scheduleRestart(2)
        end
    end)
    appWatcher:start()
end

-- 低频健康检查：只判断观察者是否还在运行，不遍历 AX 树（开销可忽略）
-- healthCheckInterval = 0 可完全关闭
local function startHealthCheck()
    local interval = cfg().healthCheckInterval
    if interval == nil then interval = 300 end
    if interval <= 0 then return end

    healthTimer = hs.timer.doEvery(interval, function()
        if observer and observer:isRunning() then return end
        log("观察者未在运行，重建监听")
        stopObserver()
        startObserver()
        scan()  -- 把期间漏掉的通知补上
    end)
end

-- 停止监听（供重载或手动关闭使用）
function M.stop()
    stopObserver()
    if healthTimer then
        healthTimer:stop()
        healthTimer = nil
    end
    if appWatcher then
        appWatcher:stop()
        appWatcher = nil
    end
    if stateDirty then
        pcall(saveState)
    end
end

function M.start()
    M.stop()
    if cfg().enabled == false then
        log("已禁用（NotificationWatchConfig.enabled = false）")
        return
    end
    loadState()
    seedSeen()
    startObserver()
    startAppWatcher()
    startHealthCheck()
end

M.start()
