-- ============================================
-- AutoPolicy：检测 → 调整 类模块的公共骨架
-- 把这类工具里重复的三件事收在一起：
--   1. 环境快照：屏幕构成（内置/外接）、是否合盖
--   2. 触发调度：屏幕变化、系统唤醒去抖后调用 apply(reason)
--   3. 异步工具：保留引用的 hs.task / 定时器，避免被 Lua GC 回收
-- 各工具只需要声明「检测什么、检测到后怎么调整」。
-- ============================================

AutoPolicy = AutoPolicy or {}

local M = AutoPolicy

-- ============================================
-- 异步执行（引用必须保住，否则回调可能被 GC 回收）
-- ============================================

local tasks = {}
local timers = {}

local async = {}
M.async = async

function async.run(path, args, cb)
    local task
    task = hs.task.new(path, function(code, out, err)
        tasks[task] = nil
        cb(code or -1, out or "", err or "")
    end, args)
    tasks[task] = true
    task:start()
    return task
end

function async.after(seconds, fn)
    local timer
    timer = hs.timer.doAfter(seconds, function()
        timers[timer] = nil
        fn()
    end)
    timers[timer] = true
    return timer
end

function async.every(seconds, fn)
    local timer = hs.timer.doEvery(seconds, fn)
    timers[timer] = true
    return timer
end

function async.cancel(timer)
    if not timer then return end
    timer:stop()
    timers[timer] = nil
end

-- ============================================
-- 环境快照：屏幕构成 + 合盖状态
-- ============================================

-- 内置屏名称随机型/系统语言不同
local builtinPatterns = { "built%-in", "color lcd", "retina display", "内建", "内置" }

function M.isBuiltinScreen(screen)
    if not screen then return false end
    local name = string.lower(screen:name() or "")
    for _, pattern in ipairs(builtinPatterns) do
        if name:find(pattern) then return true end
    end
    return false
end

-- 有外接屏即视为外接模式；合盖时内置屏不在列表里，只剩外接屏
function M.hasExternalScreen()
    local screens = hs.screen.allScreens()
    if #screens > 1 then return true end
    return #screens == 1 and not M.isBuiltinScreen(screens[1])
end

local LID_CACHE_SECONDS = 1
local lidClosedCache, lidCheckedAt

-- 合盖状态：读 ioreg 的 AppleClamshellState（无需 sudo）
function M.lidClosed()
    local now = hs.timer.secondsSinceEpoch()
    if lidClosedCache ~= nil and now - lidCheckedAt < LID_CACHE_SECONDS then
        return lidClosedCache
    end

    local out = hs.execute("ioreg -r -k AppleClamshellState -d 4 2>/dev/null") or ""
    lidClosedCache = out:match('"AppleClamshellState"%s*=%s*(%a+)') == "Yes"
    lidCheckedAt = now
    return lidClosedCache
end

function M.snapshot()
    local screens = hs.screen.allScreens()
    local builtinPresent = false
    for _, screen in ipairs(screens) do
        if M.isBuiltinScreen(screen) then
            builtinPresent = true
            break
        end
    end

    return {
        external = #screens > 1 or (#screens == 1 and not builtinPresent),
        lidClosed = M.lidClosed(),
    }
end

-- ============================================
-- 策略对象：事件去抖后调用 apply
-- spec:
--   name        日志前缀
--   apply       function(policy, reason)，检测到变化后要做的调整
--   debounce    屏幕变化去抖秒数，默认 1.5
--   wakeDelay   系统唤醒后等待秒数，默认 3
--   poll        可选，额外兜底轮询间隔（秒）
--   watch       可选，function(policy)，注册其它事件源
--   watchScreens / watchWake  设为 false 可关闭对应事件源
--   onLoad      设为 false 可跳过启动时执行
-- ============================================

local Policy = {}
Policy.__index = Policy

function M.new(spec)
    local self = setmetatable({}, Policy)
    for key, value in pairs(spec or {}) do
        self[key] = value
    end
    self.name = self.name or "AutoPolicy"
    self.debounceSeconds = self.debounce or 1.5
    self.wakeSeconds = self.wakeDelay or 3
    return self
end

function Policy:refresh(reason)
    if not self.started or not self.apply then return end
    self:apply(reason or "手动刷新")
end

function Policy:debounced(reason)
    if not self.started or not self.changeTimer then return end
    self.pendingReason = reason
    self.changeTimer:start()
end

function Policy:start()
    if self.started then return self end
    self.started = true

    self.changeTimer = hs.timer.delayed.new(self.debounceSeconds, function()
        if self.started then
            local reason = self.pendingReason or "屏幕变化"
            self.pendingReason = nil
            self:refresh(reason)
        end
    end)

    if self.watchScreens ~= false then
        self.screenWatcher = hs.screen.watcher.new(function()
            self:debounced("屏幕变化")
        end)
        self.screenWatcher:start()
    end

    if self.watchWake ~= false then
        self.wakeWatcher = hs.caffeinate.watcher.new(function(eventType)
            if eventType == hs.caffeinate.watcher.systemDidWake then
                async.cancel(self.wakeTimer)
                self.wakeTimer = async.after(self.wakeSeconds, function()
                    self.wakeTimer = nil
                    self:refresh("系统唤醒")
                end)
            end
        end)
        self.wakeWatcher:start()
    end

    if self.poll then
        self.pollTimer = async.every(self.poll, function()
            self:refresh("轮询")
        end)
    end

    if self.watch then
        self:watch()
    end

    if self.onLoad ~= false then
        self:refresh("启动")
    end

    return self
end

function Policy:stop()
    self.started = false
    if self.changeTimer then self.changeTimer:stop() end
    if self.screenWatcher then self.screenWatcher:stop() end
    if self.wakeWatcher then self.wakeWatcher:stop() end
    async.cancel(self.wakeTimer)
    async.cancel(self.pollTimer)
    self.wakeTimer = nil
    self.pollTimer = nil
end
