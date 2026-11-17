-- ============================================
-- 配置预检：加载模块前，先用 luac -p 扫一遍 init.lua 和 lib/*.lua
--
-- 背景：init.lua 里任一模块语法错，require 会抛错并中断它后面的所有加载。
-- 而控制台被 EdgeDock 的日志刷屏，报错瞬间就被冲掉，表现出来就是
-- 「某个快捷键莫名其妙没了」（如 ⇧⌘3 的截图 OCR）。
-- 这里在加载前把 文件:行号 直接摆到弹窗里。
-- ============================================

local M = {}

-- Hammerspoon 的 PATH 不含 Homebrew，必须用绝对路径找 luac
local function luacPath()
    for _, path in ipairs({
        "/opt/homebrew/bin/luac",
        "/usr/local/bin/luac",
        "/usr/bin/luac",
    }) do
        local fh = io.open(path, "r")
        if fh then
            fh:close()
            return path
        end
    end
    return "luac"
end

-- 返回语法错误列表，如：
--   { "lib/gamepad_hook.lua:233: unexpected symbol near ')'" }
function M.check()
    local command = string.format(
        'cd %q && for f in init.lua lib/*.lua; do [ -f "$f" ] && %s -p "$f" 2>&1; done',
        hs.configdir, luacPath())

    local output = hs.execute(command) or ""
    local errors = {}

    for line in output:gmatch("[^\r\n]+") do
        if not line:match("^%s*$") then
            -- luac 的报错形如 "/opt/homebrew/bin/luac: lib/x.lua:233: unexpected symbol near ')'"
            -- 去掉命令前缀，只留 "lib/x.lua:233: ..."
            local location = line:gsub("^.-luac: ", "", 1)
            table.insert(errors, location)
        end
    end

    return errors
end

-- 弹出错误详情（非空才弹），完整内容同时写进控制台
function M.report(problems, title)
    if not problems or #problems == 0 then
        return
    end

    local shown = problems
    local extra = ""
    if #problems > 8 then
        shown = {}
        for i = 1, 8 do
            shown[i] = problems[i]
        end
        extra = string.format("\n…还有 %d 项，详见控制台", #problems - 8)
    end

    local detail = table.concat(shown, "\n") .. extra
    print("[Preflight] 配置有问题：\n" .. table.concat(problems, "\n"))

    if hs.dialog and hs.dialog.blockAlert then
        hs.dialog.blockAlert(title or "Hammerspoon 配置有问题", detail, "知道了")
    else
        hs.alert.show("配置有问题：" .. problems[1], 10)
    end
end

return M
