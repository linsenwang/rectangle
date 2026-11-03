-- ============================================
-- 连接指定 Wi-Fi 时自动打开蓝牙
-- 依赖 blueutil（brew install blueutil）
-- macOS 14+ 读取 SSID 需授予 Hammerspoon 定位权限
-- ============================================

WifiBluetooth = WifiBluetooth or {}

local config = {
    -- 匹配的 SSID（Lua 模式，按小写比较），例如 ResNet / ResNet-5G / ResNet-2.4G
    ssidPatterns = { "^resnet" },
    delay = 3,                       -- 检测到连接后等待几秒，等网络稳定
    checkOnLoad = true,              -- 加载配置时若已连上目标 Wi-Fi 也检查一次
    blueutil = "/opt/homebrew/bin/blueutil",
}

local function log(msg)
    print("[WifiBluetooth] " .. msg)
end

local function ssidMatches(ssid)
    if not ssid then return false end
    local name = string.lower(ssid)
    for _, pattern in ipairs(config.ssidPatterns) do
        if name:find(pattern) then return true end
    end
    return false
end

local settingsOpened = false

local function openBluetoothSettings()
    if settingsOpened then return end
    settingsOpened = true
    hs.execute('open "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"')
end

local function runBlueutil(args)
    return hs.execute(config.blueutil .. " " .. args .. " 2>&1")
end

local function isPermissionError(out)
    out = string.lower(out or "")
    return out:find("bluetooth api", 1, true) ~= nil or out:find("access", 1, true) ~= nil
end

-- 返回 true/false；失败时返回 nil 和错误类型
local function bluetoothPowered()
    local out, ok = runBlueutil("--power")
    if not ok then
        if isPermissionError(out) then
            log("Hammerspoon 没有蓝牙访问权限：" .. string.gsub(out, "%s+$", ""))
            return nil, "permission"
        end
        log("读取蓝牙状态失败：" .. string.gsub(out, "%s+$", ""))
        return nil, "error"
    end
    return out:gsub("%s+", "") == "1"
end

local function enableBluetooth(ssid)
    local powered, err = bluetoothPowered()
    if powered == nil then
        if err == "permission" then
            notify("自动蓝牙未执行", "请在 系统设置 > 隐私与安全性 > 蓝牙 中允许 Hammerspoon")
            openBluetoothSettings()
        else
            notify("自动蓝牙未执行", "读取蓝牙状态失败，请确认已安装 blueutil")
        end
        return
    end
    if powered then
        log("已连接 " .. ssid .. "，蓝牙已开启，无需操作")
        return
    end

    local out, ok = runBlueutil("-p 1")
    if ok then
        log("已连接 " .. ssid .. "，蓝牙已打开")
        notify("已连接 " .. ssid, "蓝牙已自动打开")
    elseif isPermissionError(out) then
        log("打开蓝牙失败：没有蓝牙访问权限")
        notify("自动蓝牙未执行", "请在 系统设置 > 隐私与安全性 > 蓝牙 中允许 Hammerspoon")
        openBluetoothSettings()
    else
        log("打开蓝牙失败：" .. string.gsub(out or "", "%s+$", ""))
        notify("打开蓝牙失败", "请手动检查蓝牙状态")
    end
end

local function currentSSID()
    return hs.wifi.currentNetwork()
end

local function wifiPowered()
    local details = hs.wifi.interfaceDetails()
    return details and details.power == true
end

local ssidPermissionWarned = false

-- macOS 14+ 读取 SSID 需要定位权限；缺权限时 currentNetwork() 恒为 nil
local function checkSSIDAccess()
    if ssidPermissionWarned or not wifiPowered() then return end
    if currentSSID() ~= nil then return end
    ssidPermissionWarned = true
    log("ERROR: 读取不到当前 Wi-Fi 名称，Hammerspoon 缺少定位权限；请在 系统设置 > 隐私与安全性 > 定位服务 中允许 Hammerspoon")
end

-- 延迟执行前再次确认仍连着目标 Wi-Fi，避免刚连上又切走时误开
-- 必须保留 timer 引用，否则配置重载时的 GC 会把它回收，回调不会执行
local pendingTimer

local function checkAndEnable(ssid)
    if pendingTimer then pendingTimer:stop() end
    pendingTimer = hs.timer.doAfter(config.delay, function()
        pendingTimer = nil
        local now = currentSSID()
        if ssidMatches(now) then
            enableBluetooth(now)
        else
            log("等待期间已离开 " .. tostring(ssid) .. "，跳过")
        end
    end)
end

local lastSSID = currentSSID()
log("启动时读取到 Wi-Fi：" .. tostring(lastSSID))

local function handleWifiChange()
    local ssid = currentSSID()
    if ssid == lastSSID then return end

    local previous = lastSSID
    lastSSID = ssid

    if not ssidMatches(ssid) then
        log("Wi-Fi 切换：" .. tostring(previous) .. " -> " .. tostring(ssid))
        return
    end

    log("Wi-Fi 切换：" .. tostring(previous) .. " -> " .. ssid)
    checkAndEnable(ssid)
end

if WifiBluetooth.watcher then
    WifiBluetooth.watcher:stop()
end

WifiBluetooth.watcher = hs.wifi.watcher.new(handleWifiChange)
WifiBluetooth.watcher:start()

if config.checkOnLoad and ssidMatches(lastSSID) then
    checkAndEnable(lastSSID)
end

checkSSIDAccess()

log("已启动：连接 " .. table.concat(config.ssidPatterns, " / ") .. " 时自动打开蓝牙")
