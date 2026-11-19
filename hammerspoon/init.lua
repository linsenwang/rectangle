-- ============================================
-- Rectangle 风格窗口管理器配置
-- 主修饰键：Ctrl + Option
-- ============================================

-- 添加 lib 目录到模块搜索路径
package.path = hs.configdir .. "/lib/?.lua;" .. package.path

-- 启用 Hammerspoon IPC，便于 hs 命令行调试
pcall(function() require("hs.ipc") end)

-- 控制台回滚历史上限（字符数，默认 100000）
hs.console.maxOutputHistory(10000)

-- ============================================
-- 语法预检：加载前用 luac -p 扫一遍，有错就弹窗给出 文件:行号
-- ============================================
local Preflight = require("preflight")
local problems = Preflight.check()

-- 逐个 require：单个模块出错只影响它自己，不会中断后面的模块
local loadFailures = {}

local function loadModule(name)
    local ok, err = pcall(require, name)
    if ok then
        return
    end
    local message = tostring(err)
        :gsub("^error loading module '.-' from file '.-':\n?", "")
        :gsub("^\t", "")
    loadFailures[#loadFailures + 1] = name .. ": " .. message
    print("[Config] 模块加载失败 | " .. name .. " | " .. message)
end

-- 按依赖顺序加载模块
loadModule("config")          -- 配置、边距、工具函数
loadModule("alert")           -- 统一弹窗（需早于其它模块加载）
loadModule("auto_policy")     -- 检测→调整类工具的公共骨架（屏幕/合盖快照、去抖调度）
loadModule("rectangle")       -- 窗口管理核心（半屏/全屏/居中/四角等）
loadModule("mouse_snap")      -- 鼠标贴边吸附（拖动窗口到边缘）
loadModule("layout")          -- 布局保存/恢复
loadModule("edge_dock")       -- Edge Dock（必须在 tiling 之前加载）
loadModule("tiling")          -- 窗口平铺（依赖 EdgeDock）
loadModule("stitch_fullscreen") -- 拼接全屏：按比例铺满屏幕（依赖 TileManager）
loadModule("auto_dock")       -- 自动停靠（依赖 EdgeDock）
loadModule("auto_close")      -- 应用窗口闲置自动关闭（不退出应用）
loadModule("display_layout")  -- 显示器布局记忆
loadModule("menu_bar_auto_hide")  -- 菜单栏自动隐藏：外接屏 In Full Screen Only / 内置屏 Always
loadModule("night_shift")     -- Night Shift：外接屏 + 合盖时打开，用内置屏时关闭
loadModule("window_profile")  -- 窗口布局属性：屏幕变化后按属性重排
loadModule("capswriter")      -- CapsWriter 鼠标侧键触发录音（UDP 控制）
loadModule("notification_watch")  -- 通知监听：签到通知自动执行脚本 / 信息验证码自动复制并粘贴
loadModule("wifi_bluetooth")  -- 连接 ResNet Wi-Fi 或指定有线网络时自动打开蓝牙
loadModule("iloud_fix")       -- iLoud 首次连接音量过小时自动断开重连
loadModule("gamepad_hook")    -- 蓝牙连上手柄时自动 pm2 启动 xbox
loadModule("keybindings")     -- 快捷键帮助面板 (Ctrl+Option+/)
loadModule("ocr_shot")        -- 截图 OCR 成 Markdown(LaTeX) (⇧⌘3)
loadModule("ordered_paste")   -- 剪贴板多图按顺序逐张粘贴 (⌃⌥⌘P)
loadModule("keyboard_lock")   -- 键盘锁：Ctrl+L 启停锁定

for _, failure in ipairs(loadFailures) do
    problems[#problems + 1] = failure
end
Preflight.report(problems)

-- 控制台里用 ReloadChecked() 重载：语法有问题就弹窗，不重载
_G.ReloadChecked = function()
    local errors = Preflight.check()
    if #errors > 0 then
        Preflight.report(errors)
        return
    end
    hs.reload()
end

-- ============================================
-- 启动提示
-- ============================================

notify("Rectangle 风格管理器已加载", "Ctrl+Option + 方向键/字母")
print("[RectangleHammerspoon] 配置已加载")

-- ============================================
-- Shottr 截图快捷键接管 (解决快捷键冲突)
-- ============================================
-- 使用 ⌃⌘C 触发 Shottr 区域截图
-- hs.hotkey.bind({"ctrl", "cmd"}, "c", function()
--     -- 方法1：直接启动 Shottr（如果它已经监听快捷键，这会自动触发）
--     local shottr = hs.application.get("Shottr")
--     if shottr then
--         -- Shottr 已在运行，尝试通过菜单栏触发
--         shottr:selectMenuItem({"Capture", "Area"})
--     else
--         -- 启动 Shottr
--         hs.application.launchOrFocus("Shottr")
--     end
-- end)

-- 备用方法：如果 Shottr 支持 URL Scheme 或 CLI
-- 可以通过 osascript 或 shell 命令触发

-- ============================================
-- 屏幕信息查看（用于配置显示器边距）
-- ============================================

-- 显示当前所有屏幕的信息（Ctrl+Opt+Cmd+I）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "i", function()
    local screens = hs.screen.allScreens()
    local info = {}
    
    for i, screen in ipairs(screens) do
        local frame = screen:frame()
        local name = screen:name() or "Unknown"
        local id = screen:id()
        local idKey = "screen_" .. id
        
        table.insert(info, string.format("屏幕 %d: %s\nID: %d (%s)\n分辨率: %.0f x %.0f", 
            i, name, id, idKey, frame.w, frame.h))
    end
    
    local win = hs.window.focusedWindow()
    if win then
        local screen = win:screen()
        local app = win:application()
        local appName = app and app:name() or "Unknown"
        local m = getAppMargin(win)
        
        table.insert(info, "\n--- 当前窗口 ---")
        table.insert(info, string.format("应用: %s", appName))
        table.insert(info, string.format("屏幕: %s (ID: %d)", screen:name() or "Unknown", screen:id()))
        table.insert(info, string.format("当前边距: left=%d, right=%d, top=%d, bottom=%d, inner=%d", m.left, m.right, m.top or 0, m.bottom or 0, m.inner))
    end
    
    local msg = table.concat(info, "\n\n")
    Alert.show(msg, { timeout = 4 })
    print("[ScreenInfo]\n" .. msg)
end)

-- Window Context: 自动截屏 OCR 并维护窗口上下文记忆
-- require("window_context")
