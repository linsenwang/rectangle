-- ============================================
-- Window Context 模块
-- 每 5 秒捕获当前窗口 OCR 并推送到本地上下文引擎
-- 改为异步 hs.task，避免阻塞主线程
-- ============================================

local INTERVAL = 5
local BIN = os.getenv("HOME") .. "/.local/bin/window-ocr"
local API = "http://127.0.0.1:16789"
local LOG = os.getenv("HOME") .. "/.hammerspoon/wc.log"
local LOG_MAX_BYTES = 1024 * 1024  -- 日志上限 1MB，超过则清空

local screenLocked = false
local lastInfo = nil
local lastOCRText = nil
local ocrTask = nil

-- 日志滚动：超过上限时清空（避免无界增长）
local function rotateLogIfNeeded()
    local attr = hs.fs.attributes(LOG)
    if attr and attr.size > LOG_MAX_BYTES then
        local f = io.open(LOG, "w")
        if f then f:close() end
    end
end

local function log(msg)
    rotateLogIfNeeded()
    local f = io.open(LOG, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
    print(msg)
end

local function ensureBinary()
    if hs.fs.attributes(BIN) then
        return true
    end
    hs.alert.show("WindowOCR 未找到，请先运行 window-context/start.sh", 5)
    return false
end

local function frontmostWindowInfo()
    local app = hs.application.frontmostApplication()
    if not app then return nil end
    local win = app:focusedWindow()
    if not win then return nil end
    local frame = win:frame()
    return {
        app = app:name() or "Unknown",
        title = win:title() or "",
        x = math.floor(frame.x),
        y = math.floor(frame.y),
        w = math.max(1, math.floor(frame.w)),
        h = math.max(1, math.floor(frame.h)),
    }
end

local function infoEqual(a, b)
    return a.app == b.app
       and a.title == b.title
       and a.x == b.x
       and a.y == b.y
       and a.w == b.w
       and a.h == b.h
end

-- 监听锁屏/休眠事件，锁屏时跳过 OCR（隐私+性能）
local lockWatcher = hs.caffeinate.watcher.new(function(eventType)
    if eventType == hs.caffeinate.watcher.screensDidLock
       or eventType == hs.caffeinate.watcher.systemWillSleep then
        screenLocked = true
    elseif eventType == hs.caffeinate.watcher.screensDidUnlock
       or eventType == hs.caffeinate.watcher.systemDidWake then
        screenLocked = false
    end
end)
lockWatcher:start()

local function captureAndPush()
    -- 锁屏/休眠时直接跳过
    if screenLocked then
        return
    end

    local info = frontmostWindowInfo()
    if not info then
        log("[SKIP] No frontmost window")
        return
    end
    if info.w < 50 or info.h < 50 then
        log("[SKIP] Window too small: " .. info.app)
        return
    end

    -- 窗口位置/标题未变化且已有 OCR 结果时跳过，减少无意义截图
    if lastInfo and infoEqual(lastInfo, info) and lastOCRText then
        return
    end
    lastInfo = info

    log("[OCR] " .. info.app .. " | " .. info.title)

    -- 终止上一次未完成的 OCR 任务，避免队列堆积
    if ocrTask and ocrTask:isRunning() then
        ocrTask:terminate()
    end

    ocrTask = hs.task.new(BIN, function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
            log("[FAIL] OCR exit=" .. tostring(exitCode) .. " err=" .. tostring(stdErr))
            return
        end
        if not stdOut or stdOut == "" then
            log("[FAIL] OCR empty output")
            return
        end

        local jsonOk, data = pcall(hs.json.decode, stdOut)
        if not jsonOk or not data then
            log("[FAIL] Bad JSON: " .. stdOut:sub(1, 100))
            return
        end

        -- 变化检测：OCR 结果未变则不再 POST
        local text = stdOut
        if text == lastOCRText then
            return
        end
        lastOCRText = text

        local payload = hs.json.encode(data)
        hs.http.doAsyncRequest(API .. "/ocr", "POST", payload, {
            ["Content-Type"] = "application/json"
        }, function(code, body, headers)
            if code == 200 then
                log("[OK] " .. info.app .. " -> engine")
            else
                log("[FAIL] POST code=" .. tostring(code))
            end
        end)
    end, {
        tostring(info.x),
        tostring(info.y),
        tostring(info.w),
        tostring(info.h),
        info.app,
        info.title,
    })

    if ocrTask then
        ocrTask:start()
    end
end

-- 对外接口：获取当前窗口的上下文摘要
function getWindowContext(callback)
    local info = frontmostWindowInfo()
    if not info then
        callback(nil)
        return
    end
    local url = API .. "/context?app=" .. hs.http.encodeForQuery(info.app)
                  .. "&title=" .. hs.http.encodeForQuery(info.title)
    hs.http.doAsyncRequest(url, "GET", nil, nil, function(code, body, headers)
        if code == 200 then
            local ok, data = pcall(hs.json.decode, body)
            if ok then callback(data) else callback(nil) end
        else
            callback(nil)
        end
    end)
end

-- 菜单栏小图标
local menu = hs.menubar.new()
if menu then
    menu:setTitle("WC")
    menu:setClickCallback(function()
        getWindowContext(function(data)
            if data and data.summary and data.summary ~= "" then
                hs.alert.show(data.summary, 4)
            else
                hs.alert.show("暂无窗口上下文", 2)
            end
        end)
    end)
end

-- 启动
if ensureBinary() then
    captureAndPush()
    hs.timer.doEvery(INTERVAL, captureAndPush)
    log("[START] Window Context interval=" .. INTERVAL .. "s")
else
    log("[START] Window Context failed: binary not found")
end
