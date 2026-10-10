-- ============================================
-- 键盘锁：临时锁定键盘，避免误触（擦键盘、宠物/小孩踩键盘等）
-- 快捷键：Ctrl+L 启停（锁定状态下再按一次解锁）
-- 实现：一个常驻的 hs.eventtap 监听键盘事件
--       未锁定：全部放行，只顺手识别 Ctrl+L（不影响其他快捷键）
--       已锁定：吞掉所有按键，仅 Ctrl+L 例外（否则无法解锁自己）
-- 应急解锁（键盘失效时用鼠标）：
--       1. Hammerspoon 菜单栏图标 → Reload Config（或退出重开）
--          锁定状态只存在内存里，重载即恢复；shutdown 回调还会先把事件监听停掉
--       2. 终端执行 hs -c "KeyboardLock.unlock('cli')"
-- ============================================

local M = {}

-- 用户配置来自全局配置 lib/config.lua 的 KeyboardLockConfig（没配就用默认值）
local cfg = _G.KeyboardLockConfig or {}

M.config = {
    mods            = cfg.toggleMods or {"ctrl"},   -- 启停锁定的修饰键
    key             = cfg.toggleKey or "l",         -- 启停锁定的按键（hs.keycodes.map 里的名字）
    blockMediaKeys  = cfg.blockMediaKeys ~= false,  -- 是否连音量/亮度等媒体键一起拦
    autoUnlockAfter = cfg.autoUnlockAfter or 0,     -- 锁定多久后自动解锁（秒），0 = 不自动解锁
    flashTimeout    = 2.5,                          -- 锁定/解锁提示的显示时长（秒）
    keyFlash        = cfg.keyFlash or "🔒",         -- 锁定期间按到按键闪出的提示（只放这个 emoji）
    keyFlashTimeout = cfg.keyFlashTimeout or 0.5,   -- 上面这个 emoji 的显示时长（秒）
}

-- 事件类型 / 属性常量
local KEY_DOWN       = hs.eventtap.event.types.keyDown
local KEY_UP         = hs.eventtap.event.types.keyUp
local SYSTEM_DEFINED = hs.eventtap.event.types.systemDefined
local AUTO_REPEAT    = hs.eventtap.event.properties.keyboardEventAutorepeat

-- 参与「恰好按下」判断的修饰键：mods 里没写的修饰键被按下时不算触发
local MOD_FLAGS   = {"ctrl", "cmd", "alt", "shift"}
local MOD_SYMBOLS = {ctrl = "⌃", cmd = "⌘", alt = "⌥", shift = "⇧"}

local toggleKeyCode = hs.keycodes.map[M.config.key]
local enabled       = toggleKeyCode ~= nil

local requiredMods = {}
for _, m in ipairs(M.config.mods) do
    requiredMods[m] = true
end

-- 内部状态
local isLocked = false
local keyFlashShown = false      -- 按键提示（🔒）是否正在显示
local keyFlashTimer = nil        -- 按键提示的复位计时器
local autoUnlockTimer = nil

-- ============================================
-- 工具函数
-- ============================================

-- 组合键显示文本，如 ⌃L
local function comboText()
    local parts = {}
    for _, m in ipairs(M.config.mods) do
        table.insert(parts, MOD_SYMBOLS[m] or m)
    end
    table.insert(parts, string.upper(M.config.key))
    return table.concat(parts)
end

-- 秒数转中文描述（用于提示条）
local function durationText(seconds)
    if seconds % 60 == 0 then
        return string.format("%d 分钟", math.floor(seconds / 60))
    end
    return string.format("%d 秒", math.floor(seconds))
end

-- 短暂提示（顶部贴边；同通道新提示自动顶掉旧的，避免叠在一起）
local function flash(message, timeout)
    Alert.show(message, {
        channel = "keyboard_lock",
        edge    = 1,
        timeout = timeout or M.config.flashTimeout,
    })
end

-- 锁定期间按到按键时闪出的提示（默认只有一个 🔒）
-- 连续敲键时，上一条还在显示就不重建，避免「关掉再打开」造成的闪烁
local function flashLockedKey()
    if keyFlashShown then return end
    keyFlashShown = true
    flash(M.config.keyFlash, M.config.keyFlashTimeout)
    keyFlashTimer = hs.timer.doAfter(M.config.keyFlashTimeout, function()
        keyFlashShown = false
        keyFlashTimer = nil
    end)
end

-- 复位按键提示状态（锁定/解锁时调用，避免残留计时器）
local function resetKeyFlash()
    if keyFlashTimer then
        keyFlashTimer:stop()
        keyFlashTimer = nil
    end
    keyFlashShown = false
end

local function cancelAutoUnlock()
    if autoUnlockTimer then
        autoUnlockTimer:stop()
        autoUnlockTimer = nil
    end
end

local function startAutoUnlock()
    cancelAutoUnlock()
    local seconds = M.config.autoUnlockAfter
    if seconds and seconds > 0 then
        autoUnlockTimer = hs.timer.doAfter(seconds, function()
            autoUnlockTimer = nil
            M.unlock("timeout")
        end)
    end
end

-- ============================================
-- 事件识别
-- ============================================

local function modsMatch(flags)
    for _, m in ipairs(MOD_FLAGS) do
        if (flags[m] == true) ~= (requiredMods[m] == true) then
            return false
        end
    end
    return true
end

-- 是否是启停键（长按连发要忽略，否则会反复开关）
local function isToggleEvent(event)
    if event:getType() ~= KEY_DOWN then return false end
    if event:getKeyCode() ~= toggleKeyCode then return false end
    if event:getProperty(AUTO_REPEAT) == 1 then return false end
    return modsMatch(event:getFlags())
end

-- ============================================
-- 公共接口
-- ============================================

function M.lock(source)
    if isLocked then return end
    isLocked = true

    resetKeyFlash()
    startAutoUnlock()

    -- local hint = "🔒 键盘已锁定 · " .. comboText() .. " 解锁"
    local hint = "🔒 键盘已锁定"
    local seconds = M.config.autoUnlockAfter
    if seconds and seconds > 0 then
        hint = hint .. "（" .. durationText(seconds) .. "后自动解锁）"
    end
    flash(hint)

    print("[KeyboardLock] 已锁定 | source=" .. tostring(source))
end

function M.unlock(source)
    if not isLocked then return end
    isLocked = false

    cancelAutoUnlock()
    resetKeyFlash()
    -- 重载/退出时不弹提示（马上就没了，弹出来只会晃一下）
    if source ~= "shutdown" then
        flash(source == "timeout" and "🔓 已自动解锁（超时保护）" or "🔓 解锁")
    end

    print("[KeyboardLock] 已解锁 | source=" .. tostring(source))
end

function M.toggle(source)
    if isLocked then
        M.unlock(source)
    else
        M.lock(source)
    end
end

function M.isLocked()
    return isLocked
end

-- ============================================
-- 事件监听：锁定状态下吞掉全部按键
-- ============================================

local eventTypes = {KEY_DOWN, KEY_UP}
if M.config.blockMediaKeys then
    table.insert(eventTypes, SYSTEM_DEFINED)
end

local function handleEvent(event)
    if isLocked then
        if isToggleEvent(event) then
            M.unlock("hotkey")
            return true
        end

        -- 按到按键时闪一个 🔒，明确「键盘确实锁上了」：
        -- 长按连发的重复事件不重复闪；音量/亮度等媒体键也闪
        local etype = event:getType()
        if (etype == KEY_DOWN and event:getProperty(AUTO_REPEAT) ~= 1) or etype == SYSTEM_DEFINED then
            flashLockedKey()
        end

        -- 锁定期间一律吞掉，不让前台应用收到任何输入
        return true
    end

    if isToggleEvent(event) then
        M.lock("hotkey")
        return true   -- 吞掉触发的这一下，避免同时漏给前台应用
    end

    return false      -- 未锁定时放行，不影响其他快捷键和正常输入
end

M.tap = hs.eventtap.new(eventTypes, function(event)
    local ok, swallow = pcall(handleEvent, event)
    if not ok then
        -- 出错就放行，绝不把键盘卡死；同时避免事件监听到超时被系统禁用
        print("[KeyboardLock] 事件处理异常，已放行: " .. tostring(swallow))
        return false
    end
    return swallow
end)

function M.start()
    if not enabled then
        print(string.format("[KeyboardLock] 按键配置无效（hs.keycodes.map 里没有 %q），键盘锁未启用",
            tostring(M.config.key)))
        return false
    end

    if M.tap:isEnabled() then
        return true
    end

    local ok, started = pcall(function() return M.tap:start() end)
    if ok and started then
        print(string.format("[KeyboardLock] 监听已启动 | %s 启停 | 媒体键=%s | 自动解锁=%s",
            comboText(),
            tostring(M.config.blockMediaKeys),
            M.config.autoUnlockAfter > 0 and durationText(M.config.autoUnlockAfter) or "关闭"))
        return true
    end

    print("[KeyboardLock] 监听启动失败: " .. tostring(started))
    return false
end

-- 重载配置 / 退出 Hammerspoon 之前主动收尾：
-- 锁定状态只存在内存里，重载后本来就会重置；这里再把事件监听显式停掉，
-- 让「用鼠标 Reload Config = 键盘立刻恢复」这条路万无一失
local previousShutdownCallback = hs.shutdownCallback
hs.shutdownCallback = function()
    if isLocked then
        M.unlock("shutdown")
    end
    if M.tap and M.tap:isEnabled() then
        pcall(function() M.tap:stop() end)
    end
    if type(previousShutdownCallback) == "function" then
        previousShutdownCallback()
    end
end

-- 便于 IPC / AppleScript 调用：hs -c "KeyboardLock.unlock('cli')"
_G.KeyboardLock = M

M.start()

return M
