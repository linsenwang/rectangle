-- ============================================
-- 按键绑定帮助面板（按住显示，松手消失）
-- 快捷键：Ctrl+Option + /
-- ============================================

local helpCanvas = nil

-- 按键绑定列表
local bindings = {
    {
        title = "窗口分屏",
        items = {
            { "⌃⌥ ←",      "左半屏循环 (1/2→2/3→5/6)" },
            { "⌃⌥ →",      "右半屏循环 (1/2→2/3→5/6)" },
            { "⌃⌥ ↑",      "最大化" },
            { "⌃⌥ ↵",      "最大化 (应用边距)" },
            { "⌃⌥ C",      "窗口居中" },
            { "⌃⌥ ⇧↑",     "最大化高度" },
            { "⌃⌥ ⌫",      "还原上一位置/大小" },
            { "⌃⌥ L",      "居中并稍大 (80%)" },
        }
    },
    {
        title = "四角与三分屏",
        items = {
            { "⌃⌥ U",      "左上 1/4" },
            { "⌃⌥ I",      "右上 1/4" },
            { "⌃⌥ 0",      "左下 1/4" },
            { "⌃⌥ 2",      "右下 1/4" },
            { "⌃⌥ ,",      "左 1/3 循环" },
            { "⌃⌥ .",      "右 1/3 循环" },
            { "⌃⌥ ;",      "靠最左 (贴边)" },
            { "⌃⌥ '",      "靠最右 (贴边)" },
        }
    },
    {
        title = "窗口调整",
        items = {
            { "⌃⌥ =",      "增大窗口" },
            { "⌃⌥ -",      "缩小窗口" },
            { "⌃⌥ ⇧←",     "移到左边屏幕" },
            { "⌃⌥ ⇧→",     "移到右边屏幕" },
        }
    },
    {
        title = "窗口微调",
        items = {
            { "⌘⌥ ←",      "左移" },
            { "⌘⌥ →",      "右移" },
            { "⌘⌥ ↑",      "上移" },
            { "⌘⌥ ↓",      "下移" },
        }
    },
    {
        title = "Edge Dock",
        items = {
            { "⌃⌥ 1~9",    "停靠到槽位" },
            { "⌃⌥⌘ 1~9",   "恢复槽位" },
        }
    },
    {
        title = "平铺",
        items = {
            { "⌃⌥⌘ T",     "平铺当前应用" },
            { "⌃⌥⌘ A",     "平铺所有应用" },
            { "⌃⌥⌘ V",     "开发工具平铺 (Code+Ghostty)" },
            { "⌃⌥⌘ O",     "恢复平铺" },
            { "⌃⌥⌘ ;",     "设置平铺间距" },
            { "⌃⌥⌘ M",     "切换平铺模式" },
        }
    },
    {
        title = "布局",
        items = {
            { "⌃⌥⌘ S",     "保存布局" },
            { "⌃⌥⌘ R",     "恢复布局" },
            { "⌃⌥⌘ D",     "恢复显示器布局" },
            { "⌃⌥⇧ D",     "保存显示器布局" },
        }
    },
    {
        title = "其他",
        items = {
            { "⌃⌥⌘ I",     "屏幕信息查看" },
            { "⌃⌥ /",      "显示本帮助面板" },
        }
    },
}

-- 创建帮助面板
local function createHelpPanel()
    if helpCanvas then
        helpCanvas:delete()
        helpCanvas = nil
    end

    -- 计算每列放多少个分类（大致均分）
    local col1Groups = {}
    local col2Groups = {}
    local mid = math.ceil(#bindings / 2)
    for i = 1, mid do
        table.insert(col1Groups, bindings[i])
    end
    for i = mid + 1, #bindings do
        table.insert(col2Groups, bindings[i])
    end

    -- 样式参数
    local fontSize = 13
    local lineHeight = 18
    local titleColor = { hex = "#FFD866" }      -- 黄色标题
    local keyColor = { hex = "#78DCE8" }        -- 青色按键
    local descColor = { hex = "#F8F8F2" }       -- 白色描述
    local dimColor = { hex = "#75715E" }        -- 灰色分隔
    local bgColor = { hex = "#1E1E1E", alpha = 0.93 }

    -- 计算列高度
    local function colHeight(groups)
        local h = 0
        for _, g in ipairs(groups) do
            h = h + lineHeight + 4                    -- 标题行
            h = h + (#g.items * lineHeight)           -- 项目行
            h = h + 10                                -- 组间距
        end
        return h
    end

    local h1 = colHeight(col1Groups)
    local h2 = colHeight(col2Groups)
    local contentH = math.max(h1, h2)

    -- 面板尺寸
    local paddingX = 24
    local paddingY = 20
    local colWidth = 280
    local gap = 30
    local panelW = paddingX * 2 + colWidth * 2 + gap
    local panelH = paddingY * 2 + contentH + 28     -- +28 标题栏

    -- 居中于主屏幕
    local screen = hs.screen.primaryScreen()
    local frame = screen:frame()
    local x = frame.x + (frame.w - panelW) / 2
    local y = frame.y + (frame.h - panelH) / 2

    helpCanvas = hs.canvas.new({ x = x, y = y, w = panelW, h = panelH })

    -- 阴影效果（先添加，在最底层）
    helpCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { hex = "#000000", alpha = 0.4 },
        roundedRectRadii = { xRadius = 14, yRadius = 14 },
        frame = { x = 4, y = 6, w = panelW, h = panelH },
    })

    -- 背景
    helpCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = bgColor,
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
    })

    local currentY = paddingY

    -- 顶部大标题
    local headerStyle = {
        font = { name = ".AppleSystemUIFont", size = 16 },
        color = { hex = "#FF79C6" },
        paragraphStyle = { alignment = "center" },
    }
    helpCanvas:appendElements({
        type = "text",
        text = hs.styledtext.new("Rectangle 快捷键帮助", headerStyle),
        frame = { x = 0, y = currentY, w = panelW, h = 24 },
    })
    currentY = currentY + 32

    -- 绘制单列内容的辅助函数
    local function drawColumn(groups, startX, colW)
        local cy = currentY
        for gi, g in ipairs(groups) do
            -- 分类标题
            local titleStyle = {
                font = { name = ".AppleSystemUIFont", size = fontSize },
                color = titleColor,
            }
            helpCanvas:appendElements({
                type = "text",
                text = hs.styledtext.new("▎" .. g.title, titleStyle),
                frame = { x = startX, y = cy, w = colW, h = lineHeight },
            })
            cy = cy + lineHeight + 4

            -- 每个项目
            for _, item in ipairs(g.items) do
                local keyStyle = {
                    font = { name = ".AppleSystemUIFontMono", size = fontSize },
                    color = keyColor,
                }
                local descStyle = {
                    font = { name = ".AppleSystemUIFont", size = fontSize },
                    color = descColor,
                }
                helpCanvas:appendElements({
                    type = "text",
                    text = hs.styledtext.new(item[1], keyStyle),
                    frame = { x = startX + 8, y = cy, w = 90, h = lineHeight },
                })
                helpCanvas:appendElements({
                    type = "text",
                    text = hs.styledtext.new(item[2], descStyle),
                    frame = { x = startX + 100, y = cy, w = colW - 100, h = lineHeight },
                })
                cy = cy + lineHeight
            end
            cy = cy + 10
        end
    end

    drawColumn(col1Groups, paddingX, colWidth)
    drawColumn(col2Groups, paddingX + colWidth + gap, colWidth)

    -- 底部提示
    local footStyle = {
        font = { name = ".AppleSystemUIFont", size = 11 },
        color = dimColor,
        paragraphStyle = { alignment = "center" },
    }
    helpCanvas:appendElements({
        type = "text",
        text = hs.styledtext.new("松开按键即可关闭", footStyle),
        frame = { x = 0, y = panelH - 22, w = panelW, h = 16 },
    })

    helpCanvas:show()
    helpCanvas:clickActivating(false)
end

-- 销毁帮助面板
local function destroyHelpPanel()
    if helpCanvas then
        helpCanvas:delete()
        helpCanvas = nil
    end
end

-- 绑定：按下显示，松手消失
hs.hotkey.bind(mash, "/", createHelpPanel, destroyHelpPanel)

print("[KeyBindings] 帮助快捷键已加载 (Ctrl+Option+/ 按住显示)")
