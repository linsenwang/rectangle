-- ============================================
-- CapsWriter UDP 控制器
-- 用 Hammerspoon 监听鼠标侧键和键盘快捷键，绕过 pynput 的限制
-- 直接使用 hs.socket.udp，避免 fork Python 子进程
-- ============================================

local M = {}

-- 鼠标侧键开关由全局配置 lib/config.lua 的 CapsWriterConfig 控制（没配到就视为开启）
local capsWriterCfg = _G.CapsWriterConfig or {}

-- 用户配置
M.config = {
    host          = "127.0.0.1",   -- CapsWriter 监听地址
    port          = 6018,          -- CapsWriter 监听端口
    triggerButton = 4,             -- 触发录音的鼠标按钮：3=x1(后退), 4=x2(前进)
    suppress      = true,          -- true=拦截侧键，不让系统触发前进/后退
    mouseEnabled  = capsWriterCfg.mouseEnabled ~= false,  -- 是否启用鼠标侧键（改 lib/config.lua 的 CapsWriterConfig）
    alertTimeout  = 0.8,           -- 弹窗显示时长（秒）
    statusPort    = 6019,          -- 监听 CapsWriter 处理状态回传的 UDP 端口
    pingTimeout   = 1.5,           -- 探测客户端 PING 回包的最长等待（秒）

    -- 键盘快捷键配置（按住录音，松开停止）
    keyMods       = {"shift"},     -- 修饰键数组，如 {"shift"}, {"cmd", "alt"}
    keyTrigger    = "right",       -- 触发键名，如 "right", "f5", "space"
    keyEnabled    = true,          -- 是否启用键盘快捷键

    -- 客户端自动拉起（改 lib/config.lua 的 CapsWriterConfig）
    -- macOS 上只有 GUI 应用（Hammerspoon / 终端）拉起的进程才有麦克风权限，
    -- pm2、登录项等 launchd 服务拉起的进程会被系统静音（峰值恒为 0），所以由这里负责启动。
    autoStart     = capsWriterCfg.autoStart ~= false,     -- 未运行时是否自动拉起客户端
    clientPython  = capsWriterCfg.clientPython  or "/Users/yangqian/miniconda3/bin/python",
    clientScript  = capsWriterCfg.clientScript  or "/Users/yangqian/Downloads/local_asr/CapsWriter-Offline/core_client.py",
    clientWorkDir = capsWriterCfg.clientWorkDir or "/Users/yangqian/Downloads/local_asr/CapsWriter-Offline",
    clientLog     = capsWriterCfg.clientLog     or "logs/client_stdout.log",  -- 相对 clientWorkDir
    startTimeout  = capsWriterCfg.startTimeout  or 45,    -- 等待客户端就绪的最长秒数
}

-- 内部状态
local isRecording = false
local pressSeq = 0               -- 按键序号：松开时自增，用于丢弃"按下→检查完成"之间已松开的请求
local udpClient = nil            -- 发送命令的 UDP socket
local statusSocket = nil         -- 接收状态回传的 UDP socket
local statusRetryTimer = nil     -- 状态端口绑定失败后的重试定时器
local clientStarting = false     -- 是否已有启动流程在跑（避免并发拉起两个客户端）
local startPoller = nil          -- 启动后轮询客户端是否就绪的定时器

-- 显示提示（顶部贴边、右对齐；同通道新提示自动顶掉旧的，避免重叠）
local function showAlert(message, timeout)
    Alert.show(message, {
        channel = "capswriter",
        edge    = 1,
        align   = "right",
        timeout = timeout or M.config.alertTimeout,
    })
end

-- 发送 UDP 命令（使用原生 hs.socket.udp，无 shell fork）
-- 坑：hs.socket.udp:send 必须显式给 host/port，只传消息会报
-- "incorrect type 'no value' for argument 3 (expected string)"
local function sendUDP(cmd)
    if not udpClient then
        local ok, sock = pcall(hs.socket.udp.new)
        if ok and sock then
            udpClient = sock
            print(string.format("[CapsWriter] UDP 客户端就绪 %s:%d", M.config.host, M.config.port))
        else
            showAlert("❌ CapsWriter UDP 不可用", 2)
            return false
        end
    end

    local ok, err = pcall(function()
        udpClient:send(cmd, M.config.host, M.config.port)
    end)
    if not ok then
        showAlert("❌ CapsWriter UDP 发送失败\n" .. tostring(err), 2)
        -- 连接可能已失效，下次重建
        pcall(function() udpClient:close() end)
        udpClient = nil
        return false
    end
    return true
end

-- 处理 CapsWriter 状态报文
local function handleStatus(data)
    if not data then return end
    data = data:gsub("^%s*(.-)%s*$", "%1")
    if data:match("^STATUS:") then
        local statusLine = data:match("^STATUS:(.+)$")
        if statusLine then
            local statusType, message = statusLine:match("^([^|]+)|(.+)$")
            if message then
                showAlert(message)
                print(string.format("[CapsWriter] 状态更新: %s", message))
            end
        end
    end
end

-- 绑定状态端口
-- hs.socket 绑定失败不会报错，只会返回一个未绑定（localPort = 0）的 socket，
-- 所以必须自己检查，否则会误以为监听已启动，之后再也不重试
local function bindStatusSocket()
    local ok, sock = pcall(function()
        return hs.socket.udp.server(M.config.statusPort, function(data, addr)
            handleStatus(data)
        end):receive()
    end)

    if not (ok and sock) then
        return nil, tostring(sock)
    end

    local bound = false
    pcall(function()
        local info = sock:info()
        bound = info ~= nil and info.localPort == M.config.statusPort
    end)

    if not bound then
        pcall(function() sock:close() end)
        return nil, "端口被占用或绑定失败"
    end

    return sock
end

-- 启动 UDP 状态监听（接收 CapsWriter 处理状态）；端口被占时每 5 秒重试
local function startStatusListener()
    if statusSocket and not statusSocket:closed() then
        return
    end

    local sock, err = bindStatusSocket()
    if sock then
        statusSocket = sock
        print(string.format("[CapsWriter] UDP 状态监听已启动 | port=%d", M.config.statusPort))
        return
    end

    print(string.format("[CapsWriter] UDP 状态监听启动失败: %s | port=%d | 每 5 秒重试",
        tostring(err), M.config.statusPort))

    if statusRetryTimer then return end
    statusRetryTimer = hs.timer.doEvery(5, function()
        local retried = bindStatusSocket()
        if retried then
            statusSocket = retried
            statusRetryTimer:stop()
            statusRetryTimer = nil
            print(string.format("[CapsWriter] UDP 状态监听已启动（重试成功）| port=%d", M.config.statusPort))
        end
    end)
end

-- 停止 UDP 状态监听
local function stopStatusListener()
    if statusRetryTimer then
        statusRetryTimer:stop()
        statusRetryTimer = nil
    end
    if statusSocket then
        pcall(function() statusSocket:close() end)
        statusSocket = nil
        print("[CapsWriter] 状态监听已停止")
    end
end

-- ========== 客户端自动拉起 ==========
-- 判断客户端是否真的能用：发 PING 等 PONG
-- 不能只看端口是否被占用——进程卡死时端口还在监听，但不会回包，那才是最常见的故障
local function checkClientReady(callback)
    local done = false
    local probe = nil

    local function finish(ready)
        if done then return end
        done = true
        if probe then
            pcall(function() probe:close() end)
        end
        callback(ready)
    end

    local ok = pcall(function()
        probe = hs.socket.udp.new(function(data)
            if data and tostring(data):gsub("%s+$", "") == "PONG" then
                finish(true)
            end
        end)
        -- 必须先 send 再 receive：先 receive 时 socket 还没绑上本地端口，收不到回包
        probe:send("PING", M.config.host, M.config.port)
        probe:receive()
    end)

    if not ok or not probe then
        finish(false)
        return
    end

    hs.timer.doAfter(M.config.pingTimeout, function()
        finish(false)
    end)
end

-- 杀掉占着控制端口、但已经不再响应 PING 的旧客户端
-- 只针对 core_client.py，避免误伤（Hammerspoon 自己也连着这个端口，lsof 会列出它）
local function killStaleClient()
    local cmd = string.format(
        'for pid in $(/usr/sbin/lsof -nP -t -iUDP:%d 2>/dev/null); do '
        .. 'if /bin/ps -o command= -p "$pid" | /usr/bin/grep -q core_client; then '
        .. '/bin/kill -9 "$pid" && echo "killed $pid"; fi; done',
        M.config.port)
    local output = hs.execute(cmd)
    if output and output:find("killed") then
        print("[CapsWriter] 已清理失去响应的旧客户端: " .. output:gsub("%s+$", ""))
    end
end

-- 拉起客户端（逐出到 launchd 名下，配置重载或 Hammerspoon 退出后仍然存活）
-- 三个坑：
--   1) hs.execute 会同步等待子进程的 stdout 管道关闭，所以必须用 (...) >> 日志 2>&1 < /dev/null &
--      把后台子进程的标准流全部接管，否则子 shell 一直攥着管道，Hammerspoon 主线程会永久卡死
--   2) 对 (...) 的重定向是在外层 shell 的工作目录下解析的，不受里面 cd 影响，所以日志必须用绝对路径
--   3) 子进程会继承 Hammerspoon 的所有 FD，包括 6019 的状态监听 socket。Hammerspoon 重载时
--      自己关了它，子进程却还攥着，新监听再也绑不上（hs.socket 绑定失败不报错），状态弹窗就没了。
--      所以 exec 之前先把 3~63 号 FD 全部关掉
local function spawnClient()
    local logPath = M.config.clientLog
    if logPath:sub(1, 1) ~= "/" then
        logPath = M.config.clientWorkDir .. "/" .. logPath
    end

    local closeFDs = {}
    for fd = 3, 63 do
        closeFDs[#closeFDs + 1] = fd .. ">&-"
    end

    local cmd = string.format(
        '(cd "%s" && exec %s && exec "%s" "%s") >> "%s" 2>&1 < /dev/null &',
        M.config.clientWorkDir, table.concat(closeFDs, " "),
        M.config.clientPython, M.config.clientScript, logPath)
    hs.execute(cmd)
    print("[CapsWriter] 已拉起客户端: " .. M.config.clientScript .. " >> " .. logPath)
end

-- 确保客户端在运行；未运行时自动拉起并轮询等待就绪
-- onResult(ready, starting)：ready=现在就能收 START，starting=正在启动中
local function ensureClientRunning(onResult)
    local function report(ready, starting)
        if onResult then onResult(ready, starting) end
    end

    -- 已有启动流程在跑时不要再拉一遍（否则会并发起两个客户端，抢同一个端口）
    if clientStarting then
        report(false, true)
        return
    end

    checkClientReady(function(ready)
        if ready then
            report(true, false)
            return
        end
        if not M.config.autoStart then
            report(false, false)
            return
        end
        if clientStarting then          -- 探测的这段时间里可能已有别的调用开始了启动
            report(false, true)
            return
        end

        clientStarting = true

        -- 先清掉占着端口但不回 PING 的僵尸进程，否则新客户端绑不上 6018
        showAlert("⏳ CapsWriter 未运行或未响应，正在后台启动…", 2)
        killStaleClient()
        spawnClient()

        local deadline = os.time() + M.config.startTimeout
        startPoller = hs.timer.doEvery(2, function()
            checkClientReady(function(ok)
                if ok then
                    startPoller:stop()
                    startPoller = nil
                    clientStarting = false
                    showAlert("✅ CapsWriter 已就绪，可以说话了", 2)
                    print("[CapsWriter] 客户端已就绪")
                elseif os.time() > deadline then
                    startPoller:stop()
                    startPoller = nil
                    clientStarting = false
                    showAlert("❌ CapsWriter 启动失败，请查看客户端日志", 3)
                    print("[CapsWriter] 客户端启动超时")
                end
            end)
        end)

        report(false, true)
    end)
end

-- 开始录音（带来源标记防止重复触发）
-- 先确认客户端在运行，未运行则自动拉起，本次按键不录音
local function startRecording(source)
    if isRecording then return end

    pressSeq = pressSeq + 1
    local mySeq = pressSeq

    ensureClientRunning(function(ready, starting)
        if mySeq ~= pressSeq then return end      -- 检查期间已松手，丢弃这次
        if not ready then
            if not starting then
                showAlert("❌ CapsWriter 未运行（自动启动已关闭）", 2)
            end
            return
        end
        -- 发送失败就不要置 isRecording，否则后续按键会被前面的 if isRecording 吞掉
        if not sendUDP("START") then return end
        isRecording = true
        showAlert("🎙️ 录音开始")
        print(string.format("[CapsWriter] 录音开始 | source=%s", source))
    end)
end

-- 停止录音（带来源标记）
local function stopRecording(source)
    pressSeq = pressSeq + 1                       -- 作废尚未完成的 START
    if isRecording then
        sendUDP("STOP")
        isRecording = false
        showAlert("🛑 录音结束")
        print(string.format("[CapsWriter] 录音结束 | source=%s", source))
    end
end

-- ========== 鼠标监听器 ==========

M.mouseTap = hs.eventtap.new({
    hs.eventtap.event.types.otherMouseDown,
    hs.eventtap.event.types.otherMouseUp,
}, function(event)
    local btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
    if btn ~= M.config.triggerButton then
        return false
    end

    local etype = event:getType()

    if etype == hs.eventtap.event.types.otherMouseDown then
        startRecording("mouse")
        return M.config.suppress
    elseif etype == hs.eventtap.event.types.otherMouseUp then
        stopRecording("mouse")
        return M.config.suppress
    end

    return false
end)

-- ========== 键盘监听器 ==========

M.keyBinding = hs.hotkey.new(M.config.keyMods, M.config.keyTrigger, function()
    startRecording("keyboard")
end, function()
    stopRecording("keyboard")
end)

-- ========== 公共接口 ==========

function M.start()
    local started = {}

    if M.config.mouseEnabled and M.mouseTap and not M.mouseTap:isEnabled() then
        M.mouseTap:start()
        table.insert(started, "鼠标 Button " .. M.config.triggerButton)
    end

    if M.keyBinding and M.config.keyEnabled then
        M.keyBinding:enable()
        table.insert(started, "键盘 " .. table.concat(M.config.keyMods, "+") .. "+" .. M.config.keyTrigger)
    end

    -- 启动 UDP 状态监听
    startStatusListener()

    -- 客户端没在跑就拉起来（Hammerspoon 启动/重载时各执行一次，用于开机后自动就绪）
    ensureClientRunning(nil)

    if #started > 0 then
        showAlert("🎙️ CapsWriter 监听已启动 | " .. table.concat(started, ", "), 2)
    end
end

function M.stop()
    if M.mouseTap and M.mouseTap:isEnabled() then
        M.mouseTap:stop()
    end
    if M.keyBinding then
        M.keyBinding:disable()
    end
    if startPoller then
        startPoller:stop()
        startPoller = nil
        clientStarting = false
    end
    stopStatusListener()
    if udpClient then
        pcall(function() udpClient:close() end)
        udpClient = nil
    end
    showAlert("🎙️ CapsWriter 监听已停止", 2)
end

function M.isRunning()
    local mouseRunning = M.mouseTap and M.mouseTap:isEnabled()
    local keyRunning = M.keyBinding and M.keyBinding.enabled
    return mouseRunning or keyRunning
end

-- ========== 手柄外部调用接口 ==========
-- 供手柄映射工具通过 AppleScript 调用：
-- osascript -e 'tell application "Hammerspoon" to execute lua code "CapsWriterGamepadStart()"'
_G.CapsWriterGamepadStart = function()
    startRecording("gamepad")
end
_G.CapsWriterGamepadStop = function()
    stopRecording("gamepad")
end

-- 启用 AppleScript 支持，允许外部程序（如手柄映射工具）调用 Hammerspoon
local appleScriptResult = hs.allowAppleScript(true)
print("[CapsWriter] hs.allowAppleScript(true) result: " .. tostring(appleScriptResult))

-- 自动启动
M.start()

print(string.format("[CapsWriter] 已加载 | host=%s:%d | button=%d | mouse=%s | key=%s+%s | suppress=%s",
    M.config.host, M.config.port, M.config.triggerButton,
    tostring(M.config.mouseEnabled),
    table.concat(M.config.keyMods, "+"), M.config.keyTrigger,
    tostring(M.config.suppress)))

return M
