-- ============================================
-- iLoud Micro-Monitor：首次连接音量过小时的自动修复
-- 现象：音箱上电后主动连 Mac 时，AVRCP 绝对音量握手会偶发失败，
--       CoreAudio 退回软件音量（约 -35 dB），听感特别小；
--       手动断开再连接一次就恢复正常。
-- 原因：绝对音量的能力查询只在建立连接时做一次，失败后 macOS 不会重试，
--       也没有开关能让它改回"音量交给音箱"；老款 iLoud 没有 USB，升级不了固件。
--       所以要真正修好，只能重新建立一次 AVRCP 连接。
-- 做法：iLoud 输出设备出现后，由 Mac 侧 blueutil 断开再连一次
--       （Mac 发起的连接握手正常）。每次连接最多一次，带冷却，不会反复断。
-- 不做"先判断再修"：判断只能翻 bluetoothd 日志，而 log show 对新日志有几十秒
--       延迟，等拿到结论时声音已经小半天了。
-- 依赖：blueutil（brew install blueutil）
-- 快捷键：Ctrl+Option+Cmd+B 手动重连
-- ============================================

IloudFix = IloudFix or {}

local config = {
    namePattern = "iLoud Micro%-Monitor",   -- 输出设备名（Lua 模式匹配）
    address = "eb-06-ef-26-47-19",          -- 蓝牙地址（blueutil 格式）
    blueutil = "/opt/homebrew/bin/blueutil",

    pollInterval = 2,      -- 多久检查一次输出设备是否出现
    actionDelay = 1.5,     -- 设备出现后等多久动手，让 A2DP 先起流，避免抢断失败
    reconnectGap = 4,      -- 断开后等多久再连，太短音箱来不及接受新连接
    connectRetries = 3,    -- 连接失败的重试次数
    retryGap = 3,          -- 重试间隔
    cooldown = 90,         -- 两次重连的最小间隔，也用来忽略自己重连引起的变化
    notifyOnFix = false,   -- 重连成功是否发通知（默认只在日志里记一笔）
}

local function log(msg)
    print("[IloudFix] " .. msg)
end

-- ============================================
-- 异步执行与定时器（引用必须保住，否则会被 GC 回收）
-- ============================================

local tasks = {}
local timers = {}

local function run(launchPath, args, cb)
    local task
    task = hs.task.new(launchPath, function(code, out, err)
        tasks[task] = nil
        cb(code or -1, out or "", err or "")
    end, args)
    tasks[task] = true
    task:start()
end

local function after(seconds, fn)
    local timer
    timer = hs.timer.doAfter(seconds, function()
        timers[timer] = nil
        fn()
    end)
    timers[timer] = true
    return timer
end

local function findDevice()
    local ok, devices = pcall(function() return hs.audiodevice.allOutputDevices() end)
    if not ok or not devices then return nil end
    for _, device in ipairs(devices) do
        local okName, name = pcall(function() return device:name() end)
        if okName and name and name:find(config.namePattern) then
            return device
        end
    end
    return nil
end

-- ============================================
-- 断开重连
-- ============================================

local state = {
    present = false,
    busy = false,
    lastFixAt = 0,
}

local function connect(attemptsLeft)
    run(config.blueutil, {"--connect", config.address}, function(code, out, err)
        if code == 0 then
            state.busy = false
            log("已由 Mac 侧重连")
            if config.notifyOnFix then
                notify("iLoud 已自动重连", "首次连接音量异常，已修复")
            end
            return
        end

        local detail = (err ~= "" and err or out):gsub("%s+$", "")
        if attemptsLeft > 0 then
            log("连接失败（" .. detail .. "），" .. config.retryGap .. " 秒后重试")
            after(config.retryGap, function() connect(attemptsLeft - 1) end)
            return
        end

        state.busy = false
        log("重连失败：" .. detail)
        notify("iLoud 自动重连失败", "音箱没连上，请手动连接一次")
    end)
end

local function reconnect(reason, force)
    if state.busy then
        log("正在重连，忽略本次触发")
        return
    end
    local now = os.time()
    if not force and now - state.lastFixAt < config.cooldown then
        log("距上次重连不足 " .. config.cooldown .. " 秒，本次跳过")
        return
    end

    state.busy = true
    state.lastFixAt = now
    log("开始重连：" .. reason)

    run(config.blueutil, {"--disconnect", config.address}, function()
        after(config.reconnectGap, function()
            connect(config.connectRetries)
        end)
    end)
end

function IloudFix.reconnect()
    reconnect("手动触发", true)
end

-- ============================================
-- 轮询：输出设备一出现就安排一次重连
-- ============================================

if IloudFix.pollTimer then IloudFix.pollTimer:stop() end
if IloudFix.pendingAction then
    IloudFix.pendingAction:stop()
    IloudFix.pendingAction = nil
end

-- 启动时已经在连的不动它，避免每次重载配置都断一次
state.present = findDevice() ~= nil
log("启动时 iLoud " .. (state.present and "已连接（不处理）" or "未连接"))

IloudFix.pollTimer = hs.timer.doEvery(config.pollInterval, function()
    local present = findDevice() ~= nil
    if present == state.present then return end
    state.present = present

    if not present then
        log("iLoud 输出设备已移除")
        return
    end

    log("iLoud 输出设备已出现，准备由 Mac 侧重连")
    if IloudFix.pendingAction then IloudFix.pendingAction:stop() end
    IloudFix.pendingAction = after(config.actionDelay, function()
        IloudFix.pendingAction = nil
        if state.busy or not findDevice() then return end
        reconnect("新连接", false)
    end)
end)

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "b", function()
    IloudFix.reconnect()
end)

log("已启动：iLoud 连上后自动由 Mac 侧重连一次（Ctrl+Option+Cmd+B 手动重连）")
