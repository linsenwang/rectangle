-- ============================================
-- CapsWriter UDP 控制器
-- 用 Hammerspoon 监听鼠标侧键和键盘快捷键，绕过 pynput 的限制
-- ============================================

local M = {}

-- 用户配置
M.config = {
    host          = "127.0.0.1",   -- CapsWriter 监听地址
    port          = 6018,          -- CapsWriter 监听端口
    triggerButton = 4,             -- 触发录音的鼠标按钮：3=x1(后退), 4=x2(前进)
    suppress      = true,          -- true=拦截侧键，不让系统触发前进/后退
    alertTimeout  = 0.8,           -- 提示显示时长（秒）

    -- 键盘快捷键配置（按住录音，松开停止）
    keyMods       = {"shift"},     -- 修饰键数组，如 {"shift"}, {"cmd", "alt"}
    keyTrigger    = "right",       -- 触发键名，如 "right", "f5", "space"
    keyEnabled    = true,          -- 是否启用键盘快捷键
}

-- 内部状态
local isRecording = false

-- 发送 UDP 命令（异步，不阻塞 Hammerspoon）
local function sendUDP(cmd)
    local pyScript = string.format(
        "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b'%s',('%s',%d))",
        cmd, M.config.host, M.config.port
    )
    hs.task.new("/usr/bin/python3", function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
            hs.alert.show("❌ CapsWriter UDP 发送失败\n" .. tostring(stdErr), 2)
        end
    end, {"-c", pyScript}):start()
end

-- 开始录音（带来源标记防止重复触发）
local function startRecording(source)
    if not isRecording then
        sendUDP("START")
        isRecording = true
        hs.alert.show("🎤 录音开始", M.config.alertTimeout)
        print(string.format("[CapsWriter] 录音开始 | source=%s", source))
    end
end

-- 停止录音（带来源标记）
local function stopRecording(source)
    if isRecording then
        sendUDP("STOP")
        isRecording = false
        hs.alert.show("⏹ 录音结束", M.config.alertTimeout)
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

    if #started > 0 then
        hs.alert.show("🎙️ CapsWriter 监听已启动 | " .. table.concat(started, ", "), 2)
    end
end

function M.stop()
    if M.mouseTap and M.mouseTap:isEnabled() then
        M.mouseTap:stop()
    end
    if M.keyBinding then
        M.keyBinding:disable()
    end
    hs.alert.show("🎙️ CapsWriter 监听已停止", 2)
end

function M.isRunning()
    local mouseRunning = M.mouseTap and M.mouseTap:isEnabled()
    local keyRunning = M.keyBinding and M.keyBinding.enabled
    return mouseRunning or keyRunning
end

-- 自动启动
M.start()

print(string.format("[CapsWriter] 已加载 | host=%s:%d | button=%d | key=%s+%s | suppress=%s",
    M.config.host, M.config.port, M.config.triggerButton,
    table.concat(M.config.keyMods, "+"), M.config.keyTrigger,
    tostring(M.config.suppress)))

return M
