-- 测试：完全无动画的窗口设置
-- 把这个文件放到 hammerspoon 目录，然后在控制台运行: dofile("test_no_anim.lua")

local win = hs.window.focusedWindow()
if not win then
    print("没有聚焦窗口")
    return
end

local screen = win:screen():frame()
local targetFrame = hs.geometry.rect(screen.x, screen.y, screen.w * 0.3, screen.h)

print("测试窗口:", win:title())
print("目标位置:", targetFrame)

-- 方法3：使用 AppleScript 强制设置（终极方案）
local appName = win:application():name()
local cmd = string.format([[
    tell application "System Events"
        tell process %q
            set position of window 1 to {%d, %d}
            set size of window 1 to {%d, %d}
        end tell
    end tell
]], appName, targetFrame.x, targetFrame.y, targetFrame.w, targetFrame.h)

hs.osascript.applescript(cmd)
print("已设置（AppleScript 方式）")
