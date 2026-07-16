-- ============================================
-- CapsWriter UDP 控制器
-- 用 Hammerspoon 监听鼠标侧键和键盘快捷键，绕过 pynput 的限制
-- 直接使用 hs.socket.udp，避免 fork Python 子进程
-- ============================================

local M = {}

-- 用户配置
M.config = {
    host          = "127.0.0.1",   -- CapsWriter 监听地址
    port          = 6018,          -- CapsWriter 监听端口
    triggerButton = 4,             -- 触发录音的鼠标按钮：3=x1(后退), 4=x2(前进)
    suppress      = true,          -- true=拦截侧键，不让系统触发前进/后退
    alertTimeout  = 0.8,           -- 提示显示时长（秒）
    statusPort    = 6019,          -- 监听 CapsWriter 处理状态回传的 UDP 端口
    -- 弹窗位置：atScreenEdge 0=居中 1=顶部 2=底部；alignment 可设 left/center/right
    alertStyle    = { atScreenEdge = 1, textStyle = { alignment = "right" } },

    -- 键盘快捷键配置（按住录音，松开停止）
    keyMods       = {"shift"},     -- 修饰键数组，如 {"shift"}, {"cmd", "alt"}
    keyTrigger    = "right",       -- 触发键名，如 "right", "f5", "space"
    keyEnabled    = true,          -- 是否启用键盘快捷键
}

-- 内部状态
local isRecording = false
local lastAlertUUID = nil        -- 上一个悬浮窗的 UUID，用于关闭避免重叠
local udpClient = nil            -- 发送命令的 UDP socket
local statusSocket = nil         -- 接收状态回传的 UDP socket

-- 显示提示（自动关闭上一个，避免重叠）
local function showAlert(message, timeout)
    if lastAlertUUID then
        pcall(function() hs.alert.closeSpecific(lastAlertUUID) end)
    end
    lastAlertUUID = hs.alert.show(message, M.config.alertStyle, nil, timeout or M.config.alertTimeout)
end

-- 发送 UDP 命令（使用原生 hs.socket.udp，无 shell fork）
local function sendUDP(cmd)
    if not udpClient then
        local ok, sock = pcall(hs.socket.udp.new)
        if ok and sock then
            local connOk = pcall(function() sock:connect(M.config.host, M.config.port) end)
            if connOk then
                udpClient = sock
                print(string.format("[CapsWriter] UDP 客户端已连接 %s:%d", M.config.host, M.config.port))
            else
                showAlert("❌ CapsWriter UDP 连接失败", 2)
                return
            end
        else
            showAlert("❌ CapsWriter UDP 不可用", 2)
            return
        end
    end

    local ok, err = pcall(function() udpClient:send(cmd) end)
    if not ok then
        showAlert("❌ CapsWriter UDP 发送失败\n" .. tostring(err), 2)
        -- 连接可能已失效，下次重建
        pcall(function() udpClient:close() end)
        udpClient = nil
    end
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

-- 启动 UDP 状态监听（接收 CapsWriter 处理状态）
local function startStatusListener()
    if statusSocket and not statusSocket:closed() then
        return
    end

    local ok, sock = pcall(function()
        return hs.socket.udp.server(M.config.statusPort, function(data, addr)
            handleStatus(data)
        end):receive()
    end)

    if ok and sock then
        statusSocket = sock
        print(string.format("[CapsWriter] UDP 状态监听已启动 | port=%d", M.config.statusPort))
    else
        print(string.format("[CapsWriter] UDP 状态监听启动失败: %s", tostring(sock)))
    end
end

-- 停止 UDP 状态监听
local function stopStatusListener()
    if statusSocket then
        pcall(function() statusSocket:close() end)
        statusSocket = nil
        print("[CapsWriter] 状态监听已停止")
    end
end

-- 开始录音（带来源标记防止重复触发）
local function startRecording(source)
    if not isRecording then
        sendUDP("START")
        isRecording = true
        showAlert("🎙️ 录音开始")
        print(string.format("[CapsWriter] 录音开始 | source=%s", source))
    end
end

-- 停止录音（带来源标记）
local function stopRecording(source)
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

    if M.mouseTap and not M.mouseTap:isEnabled() then
        M.mouseTap:start()
        table.insert(started, "鼠标 Button " .. M.config.triggerButton)
    end

    if M.keyBinding and M.config.keyEnabled then
        M.keyBinding:enable()
        table.insert(started, "键盘 " .. table.concat(M.config.keyMods, "+") .. "+" .. M.config.keyTrigger)
    end

    -- 启动 UDP 状态监听
    startStatusListener()

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

print(string.format("[CapsWriter] 已加载 | host=%s:%d | button=%d | key=%s+%s | suppress=%s",
    M.config.host, M.config.port, M.config.triggerButton,
    table.concat(M.config.keyMods, "+"), M.config.keyTrigger,
    tostring(M.config.suppress)))

return M
