-- ============================================
-- 高级功能：保存/恢复布局
-- ============================================

LayoutManager = {}
LayoutManager.savedLayouts = {}

local function layoutFilePath(name)
    return CONFIG_PATH .. "layout_" .. name .. ".json"
end

-- 根据 screenId 查找屏幕对象
local function findScreenById(screenId)
    for _, screen in ipairs(hs.screen.allScreens()) do
        if screen:id() == screenId then
            return screen
        end
    end
    return nil
end

function LayoutManager.save(name)
    local layout = {}
    local windows = hs.window.allWindows()

    for _, win in ipairs(windows) do
        if win:isStandard() then
            local app = win:application()
            local screen = win:screen()
            if app and screen then
                local frame = win:frame()
                local screenFrame = screen:frame()
                table.insert(layout, {
                    app = app:name(),
                    title = win:title(),
                    x = frame.x, y = frame.y,
                    w = frame.w, h = frame.h,
                    screenId = screen:id(),
                    screenX = screenFrame.x,
                    screenY = screenFrame.y,
                    screenW = screenFrame.w,
                    screenH = screenFrame.h,
                })
            end
        end
    end

    LayoutManager.savedLayouts[name] = layout

    -- 原子写入
    local path = layoutFilePath(name)
    local tmpPath = path .. ".tmp"
    local file = io.open(tmpPath, "w")
    if file then
        file:write(hs.json.encode(layout))
        file:close()
        os.rename(tmpPath, path)
    end

    notify("布局保存", name .. " (" .. #layout .. " 个窗口)")
end

function LayoutManager.restore(name)
    if not LayoutManager.savedLayouts[name] then
        local file = io.open(layoutFilePath(name), "r")
        if file then
            local content = file:read("*all")
            file:close()
            local ok, decoded = pcall(function() return hs.json.decode(content) end)
            if ok and type(decoded) == "table" then
                LayoutManager.savedLayouts[name] = decoded
            else
                notify("恢复失败", "布局文件损坏: " .. name)
                return
            end
        end
    end

    local layout = LayoutManager.savedLayouts[name]
    if not layout then
        notify("恢复失败", "布局 '" .. name .. "' 不存在")
        return
    end

    for _, item in ipairs(layout) do
        local app = hs.application.get(item.app)
        if app then
            for _, win in ipairs(app:allWindows()) do
                if win:title() == item.title and win:isStandard() then
                    local targetScreen = findScreenById(item.screenId)
                    if not targetScreen then
                        targetScreen = win:screen() or hs.screen.mainScreen()
                    end

                    local targetFrame = targetScreen:frame()
                    local newFrame

                    -- 如果保存时记录了屏幕 frame，按比例映射到新屏幕（应对屏幕排布变化）
                    if item.screenW and item.screenH and item.screenW > 0 and item.screenH > 0 then
                        local relX = (item.x - item.screenX) / item.screenW
                        local relY = (item.y - item.screenY) / item.screenH
                        local relW = item.w / item.screenW
                        local relH = item.h / item.screenH
                        newFrame = hs.geometry.rect(
                            targetFrame.x + relX * targetFrame.w,
                            targetFrame.y + relY * targetFrame.h,
                            relW * targetFrame.w,
                            relH * targetFrame.h
                        )
                    else
                        -- 兼容旧数据：直接用保存的绝对坐标
                        newFrame = hs.geometry.rect(item.x, item.y, item.w, item.h)
                    end

                    setWinFrame(win, newFrame)
                    break
                end
            end
        end
    end

    notify("布局恢复", name)
end

-- 保存/恢复布局快捷键
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "s", function()
    local button, name = hs.dialog.textPrompt("保存布局", "名称:", "work", "保存", "取消")
    if button == "保存" and name ~= "" then
        LayoutManager.save(name)
    end
end)

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "r", function()
    local button, name = hs.dialog.textPrompt("恢复布局", "名称:", "work", "恢复", "取消")
    if button == "恢复" and name ~= "" then
        LayoutManager.restore(name)
    end
end)
