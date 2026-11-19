-- ============================================
-- 图片顺序粘贴
-- 剪贴板里有多张图片时，很多人一次性 ⌘V 进去，AI 软件并行上传会导致顺序乱掉。
-- 这里改成：每按一次把「一张」图片放进剪贴板 → ⌘V → 隔一小段时间再下一张，
-- 顺序就是剪贴板里的原始顺序（Finder 里选中的顺序）。
--
-- 用法：
--   1. 在 Finder 里按顺序选好图片，⌘C
--   2. 切到 AI 软件输入框，按 ⌃⌥⌘P
--   3. 等待图片一张张贴完；中途再按一次 ⌃⌥⌘P 可取消
-- ============================================

local M = {}

M.config = {
    hotkey  = {"ctrl", "alt", "cmd"},   -- 修饰键
    key     = "p",                      -- 触发键
    interval = 0.2,                    -- 每贴完一张，等多久再贴下一张（秒）
    settle   = 0.08,                    -- 写好剪贴板后等多久再按 ⌘V（秒）
    restoreClipboard = true,            -- 贴完后把剪贴板恢复成原来的多张
    showAlert = true,                   -- 顶部提示
}

-- 允许作为「图片」粘贴的文件后缀
local IMAGE_EXTENSIONS = {
    png = true, jpg = true, jpeg = true, jfif = true,
    gif = true, webp = true, heic = true, heif = true,
    tif = true, tiff = true, bmp = true, avif = true, svg = true,
}

local state = {
    running   = false,
    restored  = true,
    timer     = nil,
    items     = nil,
    restore   = nil,
    index     = 1,
    total     = 0,
}

local function showAlert(message, timeout)
    if not M.config.showAlert then
        return
    end
    Alert.show(message, {
        channel = "ordered_paste",
        edge    = 1,
        timeout = timeout or 1.8,
    })
end

-- 绝对路径 → file:// URL（逐字节 percent-encode，中文/空格/特殊符号都能用）
local function fileURL(path)
    local encoded = path:gsub("[^%w%-%._~/]", function(ch)
        return string.format("%%%02X", ch:byte())
    end)
    return "file://" .. encoded
end

local function isImageFile(path)
    local ext = path:match("%.([%w]+)$")
    return ext ~= nil and IMAGE_EXTENSIONS[ext:lower()] == true
end

-- readURL/readImage 传 all=true 时通常返回数组；单个 NSURL 是带 __luaSkinType 的表
local function asArray(value)
    if type(value) ~= "table" then
        return nil
    end
    if value.__luaSkinType then
        return {value}
    end
    return value
end

-- 收集剪贴板里的图片：
--   · Finder 复制的文件 → 按原顺序返回 file URL（保留文件语义，AI 软件怎么收就怎么收）
--   · 浏览器/截图复制的图片数据 → 返回 hs.image 对象
-- 同时给出「还原剪贴板」用的对象列表。
local function collect()
    local urls = asArray(hs.pasteboard.readURL(nil, true))
    local fileItems = {}
    local restoreURLs = {}

    if urls then
        for _, entry in ipairs(urls) do
            if type(entry) == "table" then
                if entry.filePath then
                    local url = fileURL(entry.filePath)
                    restoreURLs[#restoreURLs + 1] = {url = url}
                    if isImageFile(entry.filePath) then
                        fileItems[#fileItems + 1] = {url = url, path = entry.filePath}
                    end
                elseif entry.url then
                    -- 网页链接之类：不参与图片粘贴，但还原剪贴板时保留
                    restoreURLs[#restoreURLs + 1] = {url = entry.url}
                end
            end
        end
    end

    if #fileItems > 0 then
        return fileItems, restoreURLs
    end

    local images = asArray(hs.pasteboard.readImage(nil, true))
    if images and #images > 0 then
        local items = {}
        for _, image in ipairs(images) do
            items[#items + 1] = {image = image}
        end
        return items, images
    end

    return nil, nil
end

local function stopTimer()
    if state.timer then
        state.timer:stop()
        state.timer = nil
    end
end

local function restoreClipboard()
    if state.restored then
        return
    end
    state.restored = true
    if M.config.restoreClipboard and state.restore and #state.restore > 0 then
        pcall(hs.pasteboard.writeObjects, state.restore)
    end
end

local function finish(message)
    stopTimer()
    local pasted = state.index - 1
    state.running = false
    restoreClipboard()
    showAlert(string.format("%s %d 张", message, pasted), 2.2)
    print(string.format("[OrderedPaste] %s %d 张", message, pasted))
end

local step

step = function()
    if not state.running then
        return
    end
    if state.index > state.total then
        finish("✅ 已按顺序粘贴")
        return
    end

    local item = state.items[state.index]
    local object = item.url and {url = item.url} or item.image
    local called, written = pcall(hs.pasteboard.writeObjects, {object})
    if not called or not written then
        finish("❌ 写入剪贴板失败，已粘贴")
        return
    end

    state.timer = hs.timer.doAfter(M.config.settle, function()
        if not state.running then
            return
        end
        hs.eventtap.keyStroke({"cmd"}, "v", 0)
        state.index = state.index + 1
        state.timer = hs.timer.doAfter(M.config.interval, step)
    end)
end

-- 触发一次顺序粘贴；正在粘贴时再触发 = 取消
function M.run()
    if state.running then
        state.running = false
        stopTimer()
        finish("⏹ 已取消，已粘贴")
        return
    end

    local items, restore = collect()
    if not items or #items == 0 then
        showAlert("剪贴板里没有图片\n先在 Finder 选中图片按 ⌘C", 2.5)
        return
    end

    state.running = true
    state.restored = false
    state.items = items
    state.restore = restore
    state.index = 1
    state.total = #items

    print(string.format("[OrderedPaste] 开始 | %d 张 | 间隔 %.2fs", state.total, M.config.interval))
    showAlert(string.format("📋 按顺序粘贴 %d 张…（再按一次取消）", state.total),
        (M.config.settle + M.config.interval) * state.total + 2)
    step()
end

function M.cancel()
    if state.running then
        M.run()
    end
end

M.hotkey = hs.hotkey.bind(M.config.hotkey, M.config.key, M.run)

-- 供 hs 命令行 / 自动化调用：
--   hs -c 'OrderedPasteRun()'
_G.OrderedPasteRun = M.run
_G.OrderedPasteCancel = M.cancel

print(string.format("[OrderedPaste] 已加载 | %s+%s → 按顺序逐张粘贴图片",
    table.concat(M.config.hotkey, "+"), M.config.key))

return M
