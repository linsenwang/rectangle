-- ============================================
-- 窗口布局属性（Window Profile）
-- 给每个窗口绑定一个语义化的布局属性（最大化 / 居中 / 左半屏 / 左 1/3 / 四角 / 自由 ...），
-- 显示器变化（插拔外接屏、改分辨率、跨屏移动）后按属性在新屏幕上重新计算，
-- 而不是沿用上一个屏幕的像素尺寸。
--
-- 属性来源：
--   1. 每次通过快捷键摆放窗口（setWinFrame → touch）后自动识别
--   2. 手动拖动/缩放窗口（窗口过滤器事件）后自动识别
--   3. 兜底：每 10 秒全量记录一次
-- 识别不出固定布局的窗口记为「自由」，按屏幕相对比例适配；
-- ⌃⌥⇧F 可以把窗口固定为「自由」，再按一次恢复自动识别。
--
-- Edge Dock 槽位里的窗口被藏在屏幕外，属性按槽位记录的「停靠前 frame」推断；
-- 显示器变化后重算槽位的恢复目标，从 Dock 恢复（⌃⌥⌘ 1~9）时按属性落到新屏幕。
-- ============================================

WindowProfile = {
    tags = {},          -- winId -> 布局属性（detectLayoutMode 的返回值，或 {type = "free"}）
    snapshots = {},     -- winId -> { screen = 屏幕 rect, frame = 窗口 rect }：上次记录的几何
    dirty = {},         -- winId -> { win = 窗口, snapshotOnly = bool }：待记录的窗口
    pending = false,    -- 显示器变化进行中：这段时间内不覆盖记录
    suppressUntil = 0,  -- 按属性重排期间：不把重排结果当成窗口的新属性
    dockStateDirty = false,  -- Edge Dock 槽位恢复目标被修正过，需要落盘
    recordDelay = 0.4,  -- 窗口停止变化后多久记录（等 AX 生效、合并连续事件）
    reapplyDelay = 1.2, -- 显示器变化后多久按属性重新布局
}

-- ============================================
-- 基础工具
-- ============================================

local function now()
    return hs.timer.secondsSinceEpoch()
end

local function sameRect(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- 参与布局属性管理的窗口：跳过非标准窗口和最小化窗口
-- （Edge Dock 槽位里的窗口单独走 applyDocked：它被藏在屏幕外，不能按自身 frame 推断属性）
local function isManaged(win)
    if not win then return false end
    local ok, standard = pcall(function() return win:isStandard() end)
    if not ok or not standard then return false end
    local okMin, minimized = pcall(function() return win:isMinimized() end)
    if okMin and minimized then return false end
    return true
end

-- 窗口所在的 Edge Dock 槽位（不在槽位里返回 nil）
local function dockSlotOf(win)
    if not EdgeDock or not EdgeDock.slots then return nil end
    local id = win:id()
    if not id then return nil end
    local maxSlots = (EdgeDock.config and EdgeDock.config.maxSlots) or 9
    for i = 1, maxSlots do
        local slot = EdgeDock.slots[i]
        if slot and slot.winId == id then
            return slot, i
        end
    end
    return nil
end

-- 取槽位对应的窗口对象
local function slotWindow(slot)
    if not slot then return nil end
    if slot.win then return slot.win end
    if slot.winId and slot.winId ~= 0 and slot.winId ~= -1 then
        return hs.window.get(slot.winId)
    end
    return nil
end

-- 取槽位编号（按槽位表反查）
local function slotIndexOf(slot)
    if not slot or not EdgeDock or not EdgeDock.slots then return nil end
    local maxSlots = (EdgeDock.config and EdgeDock.config.maxSlots) or 9
    for i = 1, maxSlots do
        if EdgeDock.slots[i] == slot then return i end
    end
    return nil
end

-- 找出 rect 所在的屏幕（中心点落在屏幕内，且尺寸不离谱）
local function screenForRect(rect)
    if not rect then return nil end
    local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
    for _, s in ipairs(hs.screen.allScreens()) do
        local f = s:frame()
        if cx >= f.x and cx <= f.x + f.w and cy >= f.y and cy <= f.y + f.h
            and rect.w <= f.w * 2 and rect.h <= f.h * 2 then
            return s
        end
    end
    return nil
end

-- 在屏幕列表中找出 frame 完全一致的屏幕
local function screenWithFrame(frame)
    if not frame then return nil end
    for _, s in ipairs(hs.screen.allScreens()) do
        local f = s:frame()
        if f.x == frame.x and f.y == frame.y and f.w == frame.w and f.h == frame.h then
            return s
        end
    end
    return nil
end

-- 「自由」属性：窗口相对整块屏幕的比例（用屏幕 frame，不是扣掉边距后的可用区域）
local function freeMode(frame, screen)
    return {
        type = "free",
        relX = (frame.x - screen.x) / screen.w,
        relY = (frame.y - screen.y) / screen.h,
        relW = frame.w / screen.w,
        relH = frame.h / screen.h,
    }
end

-- 记录窗口当前的屏幕与几何，作为「自由」重排和「屏幕是否变化」判断的依据
local function snapshot(win)
    local id = win:id()
    local screen = win:screen()
    if not id or not screen then return end
    local frame = win:frame()
    local max = screen:frame()
    if not frame or not max then return end
    WindowProfile.snapshots[id] = {
        screen = { x = max.x, y = max.y, w = max.w, h = max.h },
        frame  = { x = frame.x, y = frame.y, w = frame.w, h = frame.h },
    }
end

-- 槽位窗口的布局属性：用槽位记录的「停靠前 frame」推断（窗口自身已经被藏到屏幕外）
local function recordDocked(slot, slotIndex)
    local win = slotWindow(slot)
    local id = win and win:id()
    local frame = slot and slot.originalFrame
    if not id or not frame then return end
    local screen = screenForRect(frame)
    if not screen then
        -- 坐标不在任何屏幕上（历史状态里存过屏幕外的隐藏位置）→ 先按当前屏幕修好再推断
        slotIndex = slotIndex or slotIndexOf(slot)
        if slotIndex and WindowProfile.applyDocked then
            WindowProfile.applyDocked(slot, slotIndex)
            frame = slot.originalFrame
            screen = screenForRect(frame)
        end
        if not screen then return end
    end
    local max = screen:frame()

    -- 记住「停靠前几何 + 它所在的屏幕」：显示器变化时用它换算比例，
    -- 即使那块屏幕已经拔掉也能按比例落到新屏幕上
    WindowProfile.snapshots[id] = {
        screen = { x = max.x, y = max.y, w = max.w, h = max.h },
        frame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h },
    }

    local existing = WindowProfile.tags[id]
    if existing and existing.pinned then
        local mode = freeMode(frame, max)
        mode.pinned = true
        WindowProfile.tags[id] = mode
        return
    end

    WindowProfile.tags[id] = detectLayoutModeForFrame(frame, max, win)
        or freeMode(frame, max)
end

-- 记录窗口当前的布局属性（几何形状 → 属性）
local function record(win)
    local slot, slotIndex = dockSlotOf(win)
    if slot then
        recordDocked(slot, slotIndex)
        return
    end

    local id = win:id()
    local screen = win:screen()
    if not id or not screen then return end
    local frame = win:frame()
    local max = screen:frame()
    if not frame or not max then return end

    local existing = WindowProfile.tags[id]
    if existing and existing.pinned then
        -- 被固定为「自由」的窗口：只刷新相对几何，不改属性类型
        local mode = freeMode(frame, max)
        mode.pinned = true
        WindowProfile.tags[id] = mode
        return
    end

    WindowProfile.tags[id] = detectLayoutMode(win) or freeMode(frame, max)
end

-- 处理待记录队列：窗口停止变化 0.4s 后统一记录
local function flush()
    if WindowProfile.pending then
        -- 显示器变化期间几何是过渡状态，等重排结束再记录
        WindowProfile.flushTimer:start()
        return
    end

    local queue = WindowProfile.dirty
    WindowProfile.dirty = {}
    for id, item in pairs(queue) do
        local win = item.win
        local ok, wid = pcall(function() return win:id() end)
        if ok and wid == id and isManaged(win) then
            local slot = dockSlotOf(win)
            if slot then
                -- 槽位窗口：当前位置是「藏在屏幕右下角」，不能当成布局记录
                if not item.snapshotOnly then
                    recordDocked(slot)
                end
            else
                snapshot(win)
                if not item.snapshotOnly then
                    record(win)
                end
            end
        end
    end
end

WindowProfile.flushTimer = hs.timer.delayed.new(WindowProfile.recordDelay, flush)

-- ============================================
-- 对外接口
-- ============================================

-- 窗口发生变化（快捷键摆放 / 拖动 / 缩放 / 新建）时标记待记录
-- @param snapshotOnly 只更新几何记录，不改布局属性（重排自身触发的变化用）
function WindowProfile.touch(win, snapshotOnly)
    if WindowProfile.pending or not win then return end
    local id = win:id()
    if not id then return end

    -- 重排刚结束的一小段时间内，几何变化来自我们自己的重排，不代表新属性
    local suppressed = now() < WindowProfile.suppressUntil
    local item = WindowProfile.dirty[id]
    if item then
        item.win = win
        item.snapshotOnly = item.snapshotOnly and (snapshotOnly or suppressed)
    else
        WindowProfile.dirty[id] = { win = win, snapshotOnly = snapshotOnly or suppressed }
    end
    WindowProfile.flushTimer:start()
end

-- 获取窗口的布局属性
function WindowProfile.getMode(win)
    local id = win and win:id()
    if not id then return nil end
    return WindowProfile.tags[id]
end

-- 在窗口当前所在的屏幕上按属性重排
-- @param mode 指定属性（可选，缺省用记录的属性；都没有则按上次记录的屏幕比例重排）
-- @return 是否调整过该窗口
function WindowProfile.apply(win, mode)
    if not isManaged(win) then return false end
    local id = win:id()
    if not id then return false end

    -- 槽位窗口不能直接按属性摆放（会把它从屏幕外拉回来），改走槽位修正
    local slot, slotIndex = dockSlotOf(win)
    if slot then
        return WindowProfile.applyDocked(slot, slotIndex)
    end

    local screen = win:screen()
    if not screen then return false end
    local max = screen:frame()
    local snap = WindowProfile.snapshots[id]

    if not mode then
        -- 屏幕尺寸没变就不动它，避免无谓的 setFrame 抖动
        if sameRect(snap and snap.screen, max) then return false end
        mode = WindowProfile.tags[id]
        if not mode then
            if not snap then return false end
            mode = freeMode(snap.frame, snap.screen)
        end
    end

    WindowProfile.suppressUntil = now() + 0.8
    applyLayoutMode(win, mode, screen)
    return true
end

-- Edge Dock 槽位窗口的显示器变化处理：
-- 1. 按布局属性重算「从 Dock 恢复时用的 frame」（槽位的 originalFrame）
-- 2. 把藏在屏幕外的位置重新落到当前屏幕的右下角（否则屏幕排布变化后可能露在屏幕里）
-- @return 是否更新过槽位
function WindowProfile.applyDocked(slot, slotIndex)
    local win = slotWindow(slot)
    if not win or not slot.originalFrame then return false end
    local id = win:id()
    if not id then return false end

    -- 目标屏幕与 Edge Dock 保持一致：槽位绑定的屏幕，屏幕没了则退回鼠标所在屏幕
    local targetScreen = screenWithFrame(EdgeDock.getSlotScreenFrame(slot))
    if not targetScreen then return false end

    -- 参考屏幕：停靠前几何所在的屏幕（可能已经被拔掉），用来换算比例
    local snap = WindowProfile.snapshots[id]
    local refMax = snap and snap.screen
    if not refMax then
        local refScreen = screenForRect(slot.originalFrame)
        refMax = refScreen and refScreen:frame()
    end

    -- 有属性就按属性算；没有属性就按参考屏幕的比例换算；
    -- 参考屏幕也没有（历史状态里存过屏幕外的隐藏坐标）时按目标屏幕钳回屏幕内
    local mode = WindowProfile.tags[id] or freeMode(slot.originalFrame, refMax or targetScreen:frame())

    local target = layoutFrameFor(mode, targetScreen:frame(), win)
    if not target then return false end
    local changed = not sameRect(slot.originalFrame, target)

    -- 窗口正在预览显示时先收回屏幕外，避免下次隐藏仍用旧屏幕坐标
    if slot.isShowing and not slot.centeredPaused then
        EdgeDock.hideWindow(slotIndex)
    end

    if changed then
        -- 恢复目标与尺寸都按属性走，恢复时不再沿用上一个屏幕的大小
        slot.originalFrame = target
        slot.currentSize = { w = target.w, h = target.h }
        WindowProfile.dockStateDirty = true
    end

    if not slot.isShowing then
        EdgeDock.hideWindow(slotIndex)
    end

    return changed
end

-- Edge Dock 槽位恢复目标被修正过就落盘（避免下次重载又读回旧坐标）
function WindowProfile.saveDockState()
    if not WindowProfile.dockStateDirty then return end
    WindowProfile.dockStateDirty = false
    if EdgeDock and EdgeDock.saveState then
        EdgeDock.saveState()
    end
end

-- 按布局属性重排所有窗口
function WindowProfile.reapplyAll()
    local count = 0
    for _, win in ipairs(hs.window.allWindows()) do
        local ok, applied = pcall(WindowProfile.apply, win)
        if ok and applied then count = count + 1 end
    end

    -- Edge Dock 槽位里的窗口可能不在 allWindows 里（被藏到屏幕外），单独再扫一遍
    if EdgeDock and EdgeDock.slots then
        local maxSlots = (EdgeDock.config and EdgeDock.config.maxSlots) or 9
        for i = 1, maxSlots do
            local slot = EdgeDock.slots[i]
            if slot then
                local ok, applied = pcall(WindowProfile.applyDocked, slot, i)
                if ok and applied then count = count + 1 end
            end
        end
    end

    WindowProfile.pending = false
    WindowProfile.saveDockState()
    if count > 0 then
        print(string.format("[WindowProfile] 按布局属性重排 %d 个窗口", count))
    end
    return count
end

-- 安排一次按属性重排（显示器变化后调用，去抖）
function WindowProfile.scheduleReapply(delay)
    WindowProfile.pending = true
    WindowProfile.reapplyTimer:start(delay or WindowProfile.reapplyDelay)
end

-- 全量记录一遍（启动时和兜底轮询用）
function WindowProfile.recordAll()
    local count = 0
    for _, win in ipairs(hs.window.allWindows()) do
        if isManaged(win) then
            local slot = dockSlotOf(win)
            if slot then
                recordDocked(slot)
            else
                snapshot(win)
                record(win)
            end
            count = count + 1
        end
    end
    -- 槽位里的窗口可能不在 allWindows 里，补一遍
    if EdgeDock and EdgeDock.slots then
        local maxSlots = (EdgeDock.config and EdgeDock.config.maxSlots) or 9
        for i = 1, maxSlots do
            local slot = EdgeDock.slots[i]
            if slot and slotWindow(slot) then
                recordDocked(slot, i)
            end
        end
    end
    WindowProfile.saveDockState()
    return count
end

-- ============================================
-- 属性名称（用于提示）
-- ============================================

local RATIO_NAMES = { [0.5] = "1/2", [2/3] = "2/3", [5/6] = "5/6" }
local CORNER_NAMES = { tl = "左上 1/4", tr = "右上 1/4", bl = "左下 1/4", br = "右下 1/4" }
local THIRD_NAMES = { [1] = "左 1/3", [2] = "中 1/3", [3] = "右 1/3" }

function WindowProfile.describe(mode)
    if not mode then return "未记录" end
    local t = mode.type
    if t == "maximized" then return "最大化"
    elseif t == "left-half" then return "左半屏 " .. (RATIO_NAMES[mode.ratio] or "")
    elseif t == "right-half" then return "右半屏 " .. (RATIO_NAMES[mode.ratio] or "")
    elseif t == "top-half" then return "上半屏"
    elseif t == "bottom-half" then return "下半屏"
    elseif t == "center" then return "居中"
    elseif t == "third" then return THIRD_NAMES[mode.pos] or "1/3"
    elseif t == "corner" then return CORNER_NAMES[mode.pos] or "1/4"
    elseif t == "full-height" then return "全高"
    elseif t == "free" then return mode.pinned and "自由（已固定）" or "自由"
    end
    return t
end

-- ============================================
-- 快捷键：切换「自由」属性
-- ============================================

-- 窗口「有意义的几何」：槽位窗口用停靠前的 frame，其他窗口用实时 frame
local function meaningfulGeometry(win)
    local slot = dockSlotOf(win)
    if slot and slot.originalFrame then
        local screen = screenForRect(slot.originalFrame)
        if screen then return slot.originalFrame, screen:frame() end
    end
    local screen = win:screen()
    local frame = win:frame()
    if not screen or not frame then return nil end
    return frame, screen:frame()
end

-- ⌃⌥⇧F：固定为「自由」（只按屏幕比例适配，不吸附固定布局），再按一次恢复自动识别
hs.hotkey.bind(mashShift, "f", function()
    local win = hs.window.focusedWindow()
    if not isManaged(win) then return end
    local id = win:id()
    if not id then return end

    local current = WindowProfile.tags[id]
    if current and current.pinned then
        WindowProfile.tags[id] = nil
        if dockSlotOf(win) then
            record(win)   -- 槽位窗口：record 内部按停靠前的 frame 识别
        else
            snapshot(win)
            record(win)
        end
        hs.alert.show("布局属性：自动识别（" .. WindowProfile.describe(WindowProfile.tags[id]) .. "）", 1.5)
    else
        local frame, max = meaningfulGeometry(win)
        if not frame then return end
        local mode = freeMode(frame, max)
        mode.pinned = true
        WindowProfile.tags[id] = mode
        hs.alert.show("布局属性：自由（按屏幕比例适配）", 1.5)
    end
end)

-- ============================================
-- 初始化
-- ============================================

function WindowProfile.init()
    WindowProfile.reapplyTimer = hs.timer.delayed.new(WindowProfile.reapplyDelay, function()
        WindowProfile.reapplyAll()
    end)

    -- 显示器配置变化（插拔、改分辨率）→ 等系统搬完窗口，再按属性重排
    WindowProfile.screenWatcher = hs.screen.watcher.new(function()
        print("[WindowProfile] 显示器配置变化，稍后按布局属性重排")
        WindowProfile.scheduleReapply()
    end)
    WindowProfile.screenWatcher:start()

    -- 锁屏 / 睡眠期间 AX 不可用（窗口读不到），显示器变化时没法重排；
    -- 解锁或唤醒后补一次，此时快照仍是变化前的，才能正确换算比例
    WindowProfile.caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.screensDidUnlock
            or event == hs.caffeinate.watcher.screensDidWake
            or event == hs.caffeinate.watcher.sessionDidBecomeActive then
            print("[WindowProfile] 解锁/唤醒，稍后按布局属性重排")
            WindowProfile.scheduleReapply(1.0)
        end
    end)
    WindowProfile.caffeinateWatcher:start()

    -- 窗口被拖动 / 缩放（都走 windowMoved）/ 新建 → 更新记录
    WindowProfile.windowFilter = hs.window.filter.new(true)
    WindowProfile.windowFilter:subscribe({
        hs.window.filter.windowMoved,
        hs.window.filter.windowCreated,
    }, function(win)
        WindowProfile.touch(win)
    end)

    -- 兜底：每 10 秒全量记录一次，防止漏掉 AX 事件
    hs.timer.doEvery(10, function()
        if not WindowProfile.pending then
            WindowProfile.recordAll()
        end
    end)

    -- 启动时等窗口稳定后记录一遍
    hs.timer.doAfter(2, function()
        local count = WindowProfile.recordAll()
        print(string.format("[WindowProfile] 已记录 %d 个窗口的布局属性", count))
    end)

    print("[WindowProfile] 布局属性管理已启动")
end

WindowProfile.init()
