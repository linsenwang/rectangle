-- ============================================
-- 自动停靠：应用打开时自动停靠到指定槽位
-- ============================================

-- 使用 config.lua 中的自动停靠配置

-- 微信主窗口只认下面几个标题：
-- 微信 4.x 的聊天/文章窗口标题可能是 "WeChat (Window)"，小程序窗口标题是小程序名，
-- 自动停靠一律不碰，避免把聊天/小程序窗口贴到槽位。
local WECHAT_BUNDLE_ID = "com.tencent.xinWeChat"
local WECHAT_MAIN_TITLES = { ["WeChat"] = true, ["Weixin"] = true, ["微信"] = true }
local WECHAT_REOPEN_TIMEOUT = 10   -- 重新打开主窗口最长等待秒数
local WECHAT_POLL_INTERVAL = 0.5

-- 等待微信主窗口重新打开的轮询计时器（同一时间只允许一个）
local wechatReopenTimer = nil

local function isWeChatName(appName)
    local lower = string.lower(appName or "")
    return lower == "wechat" or lower == "weixin" or lower == "微信"
end

-- 只处理真正的微信主程序（com.tencent.xinWeChat），排除同名的第二实例 WeChat2
local function isMainWeChatApp(appObj)
    if not appObj then return true end
    local ok, bundleID = pcall(function() return appObj:bundleID() end)
    return ok and bundleID == WECHAT_BUNDLE_ID
end

-- 窗口是否真的在槽位里
-- 微信把窗口关掉再打开时，系统可能复用同一个窗口 ID；只比对 ID 会把“重开出来的
-- 窗口”误判成已停靠。因此额外校验窗口位置：未显示时必须位于隐藏点。
local function isWindowInSlot(win, slot)
    if not win or not slot or slot.winId ~= win:id() then return false end
    if slot.isShowing then return true end

    local frame = win:frame()
    if not frame then return false end
    local screen = EdgeDock.getSlotScreenFrame(slot)
    local hideX = screen.x + screen.w - 1
    local hideY = screen.y + screen.h - 1
    return math.abs(frame.x - hideX) <= 5 and math.abs(frame.y - hideY) <= 5
end

-- 窗口是否已经在某个槽位里
local function dockedSlotIndex(win)
    if not win then return nil end
    for i, slot in pairs(EdgeDock.slots) do
        if isWindowInSlot(win, slot) then
            return i
        end
    end
    return nil
end

-- 确认目标槽位可用：
--   · 空槽位 -> 可用
--   · 槽位里是已经贴边的微信主窗口 -> 不可用（已经在里面了）
--   · 槽位里是微信主窗口但记录已过期（窗口被关掉后 ID 被复用/被移出来）-> 清记录，重新贴边
--   · 槽位里是已关闭的微信窗口，或旧逻辑误停靠的微信聊天/小程序窗口 -> 清掉，可用
--   · 槽位里是其它应用 -> 不可用（不抢占别人的槽位）
local function prepareTargetSlot(targetSlot)
    local slot = EdgeDock.slots[targetSlot]
    if not slot then return true end

    local win = slot.winId and hs.window.get(slot.winId)
    local title = win and win:title() or ""
    if win and win:isStandard() and WECHAT_MAIN_TITLES[title] then
        if isWindowInSlot(win, slot) then
            return false
        end
        -- 窗口还在但并没有处于贴边位置，说明槽位记录过期，直接重新贴边
        print("[AutoDock] 槽位 " .. targetSlot .. " 记录已过期，重新贴边")
        if slot.hideTimer then slot.hideTimer:stop() end
        EdgeDock.slots[targetSlot] = nil
        EdgeDock.refreshBars()
        return true
    end

    if not isWeChatName(slot.appName) then
        return false
    end

    print("[AutoDock] 清理槽位 " .. targetSlot .. " 中的非主窗口: "
        .. tostring(slot.appName) .. " / [" .. tostring(title) .. "]")
    EdgeDock.clearSlot(targetSlot)
    EdgeDock.refreshBars()
    EdgeDock.saveState()
    return true
end

-- 窗口若落在屏幕外（例如上次隐藏时被关掉），先摆回可见区域，
-- 避免 dockWindow 把屏幕外坐标记成 originalFrame，之后恢复时窗口"消失"
local function ensureWindowOnScreen(win)
    local frame = win:frame()
    local screen = win:screen()
    if not frame or not screen then return end
    local sf = screen:frame()
    if frame.x >= sf.x + sf.w - 10 or frame.y >= sf.y + sf.h - 10 then
        setWinFrame(win, hs.geometry.rect(
            sf.x + (sf.w - frame.w) / 2,
            sf.y + (sf.h - frame.h) / 2,
            frame.w, frame.h))
    end
end

local function dockWeChatMainWindow(win, targetSlot)
    if not win then return false end

    local existingSlot = dockedSlotIndex(win)
    if existingSlot then
        if existingSlot ~= targetSlot then
            print("[AutoDock] 微信主窗口已在槽位 " .. existingSlot .. "，不重复停靠")
        end
        return false
    end

    if not prepareTargetSlot(targetSlot) then
        print("[AutoDock] 槽位 " .. targetSlot .. " 已被占用，跳过")
        return false
    end

    ensureWindowOnScreen(win)
    print("[AutoDock] 将 WeChat 主窗口停靠到槽位 " .. targetSlot)
    EdgeDock.dockWindow(win, targetSlot, {autoPeek = true})
    return true
end

local function stopWeChatReopenWait()
    if wechatReopenTimer then
        wechatReopenTimer:stop()
        wechatReopenTimer = nil
    end
end

-- 通过 LaunchServices 的 reopen 事件重新打开微信主窗口
-- （等价于点 Dock 图标；应用还在运行但窗口被关掉时，会重新创建主窗口）
local function reopenWeChatMainWindow()
    print("[AutoDock] 微信没有主窗口，尝试重新打开主窗口")
    hs.execute("open -b " .. WECHAT_BUNDLE_ID)
end

-- 鼠标是否还停在目标槽位上（用于重开后直接滑出窗口）
local function isMouseOverSlot(slotIndex)
    local screen = EdgeDock.getCurrentScreen()
    local sx, sy, sw, sh = EdgeDock.getSlotPosition(slotIndex, screen)
    local m = hs.mouse.absolutePosition()
    local r = EdgeDock.config.triggerRange
    return m.x >= sx - (r.leftExtend or 0)
       and m.y >= sy - (r.topExtend or 0)
       and m.y <= sy + sh + (r.bottomExtend or 0)
end

-- 没有主窗口时：先重新打开，再轮询等待主窗口出现后自动贴边
-- showWhenReady=true 时，若鼠标仍停在槽位上，贴边后直接滑出窗口
local function startDockWhenWeChatMainAppears(targetSlot, showWhenReady)
    stopWeChatReopenWait()

    local waited = 0
    wechatReopenTimer = hs.timer.doEvery(WECHAT_POLL_INTERVAL, function()
        waited = waited + WECHAT_POLL_INTERVAL

        local win = findWeChatMainWindow()
        if win then
            stopWeChatReopenWait()
            -- 等窗口完成创建/布局再停靠，避免记录到错误的原始位置
            hs.timer.doAfter(0.5, function()
                local mainWin = findWeChatMainWindow() or win
                local docked = dockWeChatMainWindow(mainWin, targetSlot)
                if docked and showWhenReady and isMouseOverSlot(targetSlot) then
                    EdgeDock.peekWindow(targetSlot)
                end
            end)
        elseif waited >= WECHAT_REOPEN_TIMEOUT then
            stopWeChatReopenWait()
            print("[AutoDock] 等待微信主窗口超时（" .. WECHAT_REOPEN_TIMEOUT .. " 秒）")
        end
    end)
end

-- @param dockExisting 主窗口已经存在时是否直接停靠
--   true  - 启动/窗口新建：直接停靠
--   false - 应用重新激活：只在主窗口不存在（被误关）时重开，不打断正在使用的窗口
local function autoDockWeChat(dockExisting)
    local targetSlot = AutoDockConfig["WeChat"]
    if not targetSlot then return end

    local mainWin = findWeChatMainWindow()
    if mainWin then
        if not dockExisting then
            return
        end
        dockWeChatMainWindow(mainWin, targetSlot)
        return
    end

    -- 已经在等待重开了，避免重复触发
    if wechatReopenTimer then
        return
    end

    if not prepareTargetSlot(targetSlot) then
        print("[AutoDock] 槽位 " .. targetSlot .. " 已被占用，跳过重新打开微信主窗口")
        return
    end

    reopenWeChatMainWindow()
    startDockWhenWeChatMainAppears(targetSlot)
end

-- 供 Edge Dock 调用：鼠标停在槽位上时发现窗口已经关闭，
-- 立即重开主窗口并贴边，而不是等 5 秒一次的校验定时器
function EdgeDock.recoverSlotWindow(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot or not isWeChatName(slot.appName) then
        return false
    end

    -- 只处理主微信实例的槽位（手动停靠 WeChat2 的窗口不在这里重开）
    if slot.win then
        local ok, bundleID = pcall(function()
            local app = slot.win:application()
            return app and app:bundleID()
        end)
        if ok and bundleID and bundleID ~= WECHAT_BUNDLE_ID then
            return false
        end
    end

    -- 已经在等待重开了
    if wechatReopenTimer then
        return true
    end

    local mainWin = findWeChatMainWindow()
    if mainWin then
        -- 主窗口其实还在（可能刚被系统恢复），直接重新贴边
        if slot.hideTimer then slot.hideTimer:stop() end
        EdgeDock.slots[slotIndex] = nil
        dockWeChatMainWindow(mainWin, slotIndex)
        return true
    end

    print("[AutoDock] 槽位 " .. slotIndex .. " 的微信窗口已关闭，立即重新打开主窗口")

    -- 旧槽位指向的窗口已经不存在，先清掉记录，避免把死窗口当成占用
    if slot.hideTimer then slot.hideTimer:stop() end
    EdgeDock.slots[slotIndex] = nil
    EdgeDock.refreshBars()
    EdgeDock.saveState()

    reopenWeChatMainWindow()
    startDockWhenWeChatMainAppears(slotIndex, true)
    return true
end

-- 应用启动监听器（自动停靠）
EdgeDock.autoDockWatcher = hs.application.watcher.new(function(appName, eventType, appObj)
    if eventType == hs.application.watcher.launched then
        local targetSlot = AutoDockConfig[appName]
        if not targetSlot then
            return
        end

        -- 微信：只认主窗口，启动后等窗口创建完成再贴边
        if isWeChatName(appName) then
            if not isMainWeChatApp(appObj) then
                print("[AutoDock] 忽略非主微信实例: " .. tostring(appObj and appObj:bundleID()))
                return
            end
            print("[AutoDock] WeChat 启动，等待主窗口创建...")
            hs.timer.doAfter(1.5, function()
                autoDockWeChat(true)
            end)
            return
        end

        -- 其它应用保持原有逻辑：槽位空闲时停靠第一个标准窗口
        if EdgeDock.slots[targetSlot] then
            print("[AutoDock] " .. appName .. " 启动，但槽位 " .. targetSlot .. " 已被占用")
            return
        end

        print("[AutoDock] " .. appName .. " 启动，等待窗口创建...")

        hs.timer.doAfter(1.5, function()
            local app = hs.application.get(appName)
            if not app then
                print("[AutoDock] 无法获取应用: " .. appName)
                return
            end

            local windows = {}
            for _, win in ipairs(app:allWindows()) do
                if win:isStandard() then
                    table.insert(windows, win)
                end
            end

            if #windows == 0 then
                print("[AutoDock] " .. appName .. " 没有可停靠的窗口")
                return
            end

            if EdgeDock.slots[targetSlot] then
                print("[AutoDock] 槽位 " .. targetSlot .. " 已被占用，跳过")
                return
            end

            print("[AutoDock] 将 " .. appName .. " 停靠到槽位 " .. targetSlot)
            EdgeDock.dockWindow(windows[1], targetSlot, {autoPeek = true})
        end)

    elseif eventType == hs.application.watcher.activated then
        -- 微信窗口被误关后重新激活应用时，尝试重开主窗口并贴边。
        -- 主窗口还在（停靠中或正在显示）时不做任何事。
        if not isWeChatName(appName) then return end
        if not AutoDockConfig[appName] then return end
        if not isMainWeChatApp(appObj) then return end
        autoDockWeChat(false)
    end
end)

-- 兜底监听：微信主窗口被重新创建时（启动 / 误关后点 Dock 图标回来）自动贴边
EdgeDock.autoDockWindowFilter = hs.window.filter.new("WeChat")
EdgeDock.autoDockWindowFilter:subscribe(hs.window.filter.windowCreated, function(win)
    local okApp, app = pcall(function() return win:application() end)
    if not okApp or not app then return end
    local okBundle, bundleID = pcall(function() return app:bundleID() end)
    if not okBundle or bundleID ~= WECHAT_BUNDLE_ID then return end

    local title = win:title() or ""
    if not WECHAT_MAIN_TITLES[title] then return end

    local targetSlot = AutoDockConfig["WeChat"]
    if not targetSlot then return end

    -- 等窗口完成布局再贴边
    hs.timer.doAfter(0.8, function()
        -- 重开流程的轮询会负责停靠，这里不重复处理
        if wechatReopenTimer then return end
        local mainWin = findWeChatMainWindow()
        if mainWin then
            dockWeChatMainWindow(mainWin, targetSlot)
        end
    end)
end)

-- 暴露给调试/验证使用
EdgeDock.findWeChatMainWindow = findWeChatMainWindow

-- 启动自动停靠监听器
EdgeDock.autoDockWatcher:start()
print("[AutoDock] 自动停靠功能已启动")
