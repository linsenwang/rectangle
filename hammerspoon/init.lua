-- ============================================
-- Rectangle 风格窗口管理器配置
-- 主修饰键：Ctrl + Option
-- ============================================

-- 添加 lib 目录到模块搜索路径
package.path = hs.configdir .. "/lib/?.lua;" .. package.path

-- 按依赖顺序加载模块
require("config")          -- 配置、边距、工具函数
require("rectangle")       -- 窗口管理核心（半屏/全屏/居中/四角等）
require("layout")          -- 布局保存/恢复
require("edge_dock")       -- Edge Dock（必须在 tiling 之前加载）
require("tiling")          -- 窗口平铺（依赖 EdgeDock）
require("auto_dock")       -- 自动停靠（依赖 EdgeDock）
require("display_layout")  -- 显示器布局记忆
require("capswriter")      -- CapsWriter 鼠标侧键触发录音（UDP 控制）
require("keybindings")     -- 快捷键帮助面板 (Ctrl+Option+/)

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
        table.insert(info, string.format("当前边距: left=%d, right=%d, inner=%d", m.left, m.right, m.inner))
    end
    
    local msg = table.concat(info, "\n\n")
    hs.alert.show(msg, 4)
    print("[ScreenInfo]\n" .. msg)
end)
