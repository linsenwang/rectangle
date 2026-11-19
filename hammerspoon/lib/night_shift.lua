-- ============================================
-- Night Shift 自动策略
--   外接显示器 + 合盖（合盖模式）→ 打开 Night Shift
--   使用内置显示器（无论是否外接屏）→ 关闭 Night Shift
-- 依赖 bin/nightshift：通过 CoreBrightness 私有接口开关 Night Shift，
-- 二进制缺失或源码更新时会在加载阶段自动用 clang 编译一次。
-- ============================================

NightShift = NightShift or {}

local config = {
    tool = hs.configdir .. "/bin/nightshift",
    source = hs.configdir .. "/bin/nightshift.m",
    -- 兜底轮询：Night Shift 自己的定时计划可能在两次屏幕事件之间改动状态
    poll = 60,
}

local function log(msg)
    print("[NightShift] " .. msg)
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ============================================
-- 小工具编译与调用
-- ============================================

local toolReady = false

local function mtime(path)
    local attributes = hs.fs.attributes(path)
    return attributes and attributes.modification or 0
end

local function ensureTool()
    local binaryTime = mtime(config.tool)
    local sourceTime = mtime(config.source)

    if binaryTime > 0 and binaryTime >= sourceTime then
        toolReady = true
        return true
    end

    if sourceTime == 0 then
        log("找不到 " .. config.source)
        return false
    end

    local clang = io.open("/usr/bin/clang", "r")
    if not clang then
        log("缺少 clang，无法编译 nightshift 工具")
        return false
    end
    clang:close()

    log("正在编译 nightshift 工具…")
    local out, ok = hs.execute(string.format(
        "/usr/bin/clang -O2 -fobjc-arc -framework Foundation -o '%s' '%s' 2>&1",
        config.tool, config.source))
    if not ok then
        log("编译失败：" .. trim(out))
        return false
    end

    toolReady = true
    return true
end

local function readStatus()
    local out, ok = hs.execute(string.format("'%s' status 2>&1", config.tool))
    local state = trim(out)
    if ok and (state == "on" or state == "off") then
        return state == "on"
    end
    return nil, state
end

local function writeStatus(on)
    local expect = on and "on" or "off"
    local out, ok = hs.execute(string.format("'%s' %s 2>&1", config.tool, expect))
    local state = trim(out)
    if ok and state == expect then
        return true
    end
    return false, state
end

-- ============================================
-- 策略：外接屏 + 合盖才需要 Night Shift
-- ============================================

local function describe(snapshot)
    if snapshot.external and snapshot.lidClosed then return "外接屏 + 合盖" end
    if snapshot.external then return "内置屏 + 外接屏" end
    return snapshot.lidClosed and "合盖（无外接屏）" or "内置屏"
end

local function apply(_, reason)
    if not toolReady then return end

    local snapshot = AutoPolicy.snapshot()
    local want = snapshot.external and snapshot.lidClosed

    local actual, err = readStatus()
    if actual == nil then
        log("读取 Night Shift 状态失败：" .. (err ~= "" and err or "unknown"))
        return
    end
    if actual == want then return end

    local ok, writeErr = writeStatus(want)
    if ok then
        log(string.format("%s：%s，Night Shift 已%s", reason, describe(snapshot), want and "打开" or "关闭"))
    else
        log("设置 Night Shift 失败：" .. (writeErr ~= "" and writeErr or "unknown"))
    end
end

local policy = AutoPolicy.new({
    name = "NightShift",
    debounce = 1.5,
    wakeDelay = 3,
    poll = config.poll,
    apply = apply,
})

NightShift.policy = policy

-- 手动重新评估一次（控制台调试用）
function NightShift.apply(reason)
    policy:refresh(reason or "手动")
end

if ensureTool() then
    policy:start()
else
    notify("Night Shift 自动切换未启用", "无法准备 bin/nightshift，详见控制台")
end
