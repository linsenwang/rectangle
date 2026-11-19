-- ============================================
-- 手柄连接 hook：蓝牙连上 Pro Controller / Xbox 等手柄时自动启动 xbox
-- 依赖 blueutil（brew install blueutil）与 pm2
-- 与 Raycast 里的 "Toggle Xbox" 等价，只是改为按手柄连接状态自动触发：
--   · 手柄连上 → pm2 start/restart xbox（已在运行则跳过）
--   · 手柄断开 → 等 stopDelay 秒后 pm2 stop xbox
-- 检测方式：轮询 blueutil --paired 的 connected 字段（Hammerspoon 没有
--           蓝牙连接事件可订阅，只能轮询；已配对设备数量少，开销可忽略）
-- ============================================

GamepadHook = GamepadHook or {}

local config = {
    -- 手柄名称匹配（Lua 模式，按小写比较）
    namePatterns = {
        "pro controller",
        "xbox",
        "dualsense",
        "dualshock",
        "8bitdo",
        "gamepad",
        "controller",
    },

    pm2 = "/opt/homebrew/bin/pm2",
    -- Hammerspoon 的 PATH 只有 /usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin，
    -- 而 pm2 的 shebang 是 #!/usr/bin/env node；直接 exec 会 127，
    -- 所以经 /usr/bin/env 临时补上 Homebrew 的 PATH 再调用
    pm2Path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    pm2Name = "xbox",
    ecosystem = "/Users/yangqian/Downloads/concom/ecosystem.config.js",
    blueutil = "/opt/homebrew/bin/blueutil",

    pollInterval = 3,        -- 蓝牙状态轮询间隔（秒）
    startDelay = 2,          -- 检测到连接后等几秒再启动，避开刚连上时的抖动
    stopOnDisconnect = true, -- 手柄断开后是否停止 xbox
    stopDelay = 20,          -- 断开后等这么久再停，避免瞬断导致反复启停
    checkOnLoad = true,      -- 加载配置时检查一次当前已连接的手柄
    alertOnStart = true,     -- 启动/停止时用 Alert 弹窗提示
    alertOnStop = true,
}

local M = GamepadHook

local function log(fmt, ...)
    print("[GamepadHook] " .. string.format(fmt, ...))
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 统一弹窗，同一通道互斥，新的顶掉旧的
local function popup(message)
    Alert.show(message, { channel = "gamepad", timeout = 2 })
end

-- ============================================
-- 异步执行与定时器：统一走 AutoPolicy.async（内部保留引用，避免被 GC 回收）
-- ============================================

local run, after, cancel = AutoPolicy.async.run, AutoPolicy.async.after, AutoPolicy.async.cancel

-- pm2 是 node 脚本，必须带上 Homebrew PATH 才能找到 node；
-- 同时 pm2 在 stdin 是未关闭的管道时会一直等 EOF，不退出，
-- 所以用 sh 把 stdin 重定向到 /dev/null 再 exec
local function runPm2(args, cb)
    local full = {"-c", 'exec "$@" < /dev/null', "sh",
                  "/usr/bin/env", "PATH=" .. config.pm2Path, config.pm2}
    for _, arg in ipairs(args) do
        full[#full + 1] = arg
    end
    run("/bin/sh", full, cb)
end

-- ============================================
-- 蓝牙设备识别
-- ============================================

local state = {
    pad = nil,          -- 当前连接的手柄 { name, address }
    polling = false,    -- blueutil 查询进行中
    pm2Busy = false,    -- pm2 操作进行中
    startTimer = nil,   -- 待执行的启动
    stopTimer = nil,    -- 待执行的停止
}

local lastError = nil

local function logError(kind, msg)
    if lastError == kind then return end
    lastError = kind
    if msg then log(msg) end
end

local function isGamepadName(name)
    local lowerName = string.lower(tostring(name or ""))
    for _, pattern in ipairs(config.namePatterns) do
        if lowerName:find(pattern) then return true end
    end
    return false
end

local function firstPad(devices)
    local found = {}
    for _, device in ipairs(devices) do
        if device.connected and isGamepadName(device.name) then
            table.insert(found, { name = device.name, address = device.address })
        end
    end
    -- 多只手柄同时连接时固定选一只，避免来回切换
    table.sort(found, function(a, b) return a.name < b.name end)
    return found[1]
end

-- 查询当前已连接的手柄；cb(pad or nil, failed)
-- failed=true 表示查询本身失败，此时不能把 nil 当成"手柄已断开"
local function query(cb)
    run(config.blueutil, {"--paired", "--format", "json"}, function(code, out, err)
        if code ~= 0 then
            logError("blueutil", "读取蓝牙设备失败：" .. trim(err ~= "" and err or out))
            cb(nil, true)
            return
        end

        local ok, devices = pcall(hs.json.decode, out)
        if not ok or type(devices) ~= "table" then
            logError("json", "解析 blueutil 输出失败")
            cb(nil, true)
            return
        end

        lastError = nil
        cb(firstPad(devices), false)
    end)
end

-- ============================================
-- pm2 启停
-- ============================================

-- cb(status)：status 为 "online" / "stopped" / ...；未注册时为 false；失败为 nil
-- pm2 jlist 全量输出约 80KB，会把 hs.task 的输出管道塞满导致进程不退出，
-- 所以在 shell 里先用 jq 过滤出目标进程的状态再交给 hs.task
local function pm2Status(cb)
    run("/bin/sh", {
        "-c",
        'set -o pipefail; n="$0"; f="$1"; shift; ' ..
            'exec "$@" < /dev/null | /usr/bin/jq -r --arg n "$n" "$f"',
        config.pm2Name,
        '.[] | select(.name == $n) | .pm2_env.status',
        "/usr/bin/env", "PATH=" .. config.pm2Path, config.pm2, "jlist",
    }, function(code, out, err)
        local status = trim(out)
        if code ~= 0 or (status == "" and trim(err) ~= "") then
            cb(nil)
            return
        end
        cb(status ~= "" and status or false)
    end)
end

local function stopXbox(reason)
    if state.pm2Busy then return end
    state.pm2Busy = true
    runPm2({"stop", config.pm2Name}, function(code, out, err)
        state.pm2Busy = false
        if code == 0 then
            log(reason .. "，xbox 已停止")
            if config.alertOnStop then popup("xbox 已停止（手柄已断开）") end
        else
            log("停止 xbox 失败：" .. trim(err ~= "" and err or out))
        end
    end)
end

local function startXbox(padName)
    if state.pm2Busy then return end
    state.pm2Busy = true

    pm2Status(function(status)
        if status == nil then
            state.pm2Busy = false
            log("读取 pm2 状态失败，跳过启动")
            return
        end

        if status == "online" then
            state.pm2Busy = false
            log("手柄 " .. padName .. " 已连接，xbox 已在运行")
            return
        end

        -- 已注册但停止/报错时用 restart；从未注册时用 ecosystem 启动
        local args
        if status == false then
            args = {"start", config.ecosystem, "--only", config.pm2Name}
        else
            args = {"restart", config.pm2Name}
        end

        runPm2(args, function(code, out, err)
            state.pm2Busy = false
            if code == 0 then
                log("手柄 " .. padName .. " 已连接，xbox 已启动")
                if config.alertOnStart then popup("✅ xbox 已启动 " .. padName) end
            else
                log("启动 xbox 失败：" .. trim(err ~= "" and err or out))
            end
        end)
    end)
end

-- ============================================
-- 状态切换
-- ============================================

local function scheduleStart(pad)
    cancel(state.startTimer)
    state.startTimer = after(config.startDelay, function()
        state.startTimer = nil
        M._startTimer = nil
        -- 等待期间可能又断开了，动手前再确认一次
        query(function(current, failed)
            if failed then
                log("确认手柄状态失败，跳过本次启动")
                return
            end
            if not current then
                log("等待启动期间手柄已断开，跳过")
                return
            end
            startXbox(current.name)
        end)
    end)
    M._startTimer = state.startTimer
end

local function scheduleStop()
    cancel(state.stopTimer)
    state.stopTimer = after(config.stopDelay, function()
        state.stopTimer = nil
        M._stopTimer = nil
        query(function(current, failed)
            if failed then
                log("确认手柄状态失败，跳过本次停止")
                return
            end
            if current then
                log("等待停止期间手柄重新连上，跳过")
                return
            end
            stopXbox("手柄已断开")
        end)
    end)
    M._stopTimer = state.stopTimer
end

local function handleState(pad)
    local previous = state.pad

    if pad then
        state.pad = pad
        cancel(state.stopTimer)
        state.stopTimer = nil
        M._stopTimer = nil

        if not previous then
            log("检测到手柄已连接：" .. pad.name)
            scheduleStart(pad)
        elseif previous.address ~= pad.address then
            log("手柄切换：" .. previous.name .. " -> " .. pad.name)
            scheduleStart(pad)
        end
        return
    end

    if not previous then return end

    state.pad = nil
    cancel(state.startTimer)
    state.startTimer = nil
    M._startTimer = nil
    log("手柄已断开：" .. previous.name)

    if config.stopOnDisconnect then
        scheduleStop()
    end
end

local function poll()
    if state.polling then return end
    state.polling = true
    query(function(pad, failed)
        state.polling = false
        if failed then return end -- 查询失败不动状态，避免误判断开
        handleState(pad)
    end)
end

-- ============================================
-- 启动 / 重载
-- ============================================

if M.pollTimer then
    M.pollTimer:stop()
    M.pollTimer = nil
end
-- 重载时取消上一轮还没触发的定时器，避免旧闭包继续启停
cancel(M._startTimer)
cancel(M._stopTimer)
cancel(M._loadTimer)
M._startTimer = nil
M._stopTimer = nil
M._loadTimer = nil
state.startTimer = nil
state.stopTimer = nil

M.refresh = poll

M.status = function()
    return {
        pad = state.pad and state.pad.name or nil,
        padAddress = state.pad and state.pad.address or nil,
        startPending = state.startTimer ~= nil,
        stopPending = state.stopTimer ~= nil,
    }
end

M.pollTimer = hs.timer.doEvery(config.pollInterval, poll)

if config.checkOnLoad then
    -- 加载时补一次检测：手柄已连着但 xbox 没跑时也能拉起来
    M._loadTimer = hs.timer.doAfter(1, function()
        M._loadTimer = nil
        poll()
    end)
end

log("已启动：连接手柄时自动启动 " .. config.pm2Name ..
    (config.stopOnDisconnect and ("，断开 " .. config.stopDelay .. " 秒后停止") or ""))
