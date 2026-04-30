-- ============================================
-- Window Context 模块
-- 每 5 秒捕获当前窗口 OCR 并推送到本地上下文引擎
-- ============================================

local INTERVAL = 5
local BIN = os.getenv("HOME") .. "/.local/bin/window-ocr"
local API = "http://127.0.0.1:16789"
local LOG = os.getenv("HOME") .. "/.hammerspoon/wc.log"

local function log(msg)
    local f = io.open(LOG, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
    print(msg)
end

-- 简单 shell quote
local function q(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
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
        x = math.max(0, math.floor(frame.x)),
        y = math.max(0, math.floor(frame.y)),
        w = math.max(1, math.floor(frame.w)),
        h = math.max(1, math.floor(frame.h)),
    }
end

local function captureAndPushSync()
    local info = frontmostWindowInfo()
    if not info then
        log("[SKIP] No frontmost window")
        return
    end
    if info.w < 50 or info.h < 50 then
        log("[SKIP] Window too small: " .. info.app)
        return
    end

    local cmd = string.format(
        "%s %d %d %d %d %s %s",
        q(BIN), info.x, info.y, info.w, info.h,
        q(info.app), q(info.title)
    )

    log("[OCR] " .. info.app .. " | " .. info.title)
    local output, status, typ, rc = hs.execute(cmd, true)
    if not output or output == "" then
        log("[FAIL] OCR empty output, rc=" .. tostring(rc))
        return
    end

    local jsonOk, data = pcall(hs.json.decode, output)
    if not jsonOk or not data then
        log("[FAIL] Bad JSON: " .. output:sub(1, 100))
        return
    end

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
    captureAndPushSync()
    hs.timer.doEvery(INTERVAL, captureAndPushSync)
    log("[START] Window Context interval=" .. INTERVAL .. "s")
else
    log("[START] Window Context failed: binary not found")
end
