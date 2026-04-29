-- ============================================
-- 高级功能：窗口平铺
-- ============================================

TileManager = {}
TileManager.originalLayouts = {}

-- 使用 config.lua 中的平铺配置
TileManager.config = TilingConfig

-- 循环切换平铺模式
function TileManager.cycleMode()
    local modes = {"single", "multi", "perScreen"}
    local modeNames = {
        single = "单显示器",
        multi = "多显示器均分", 
        perScreen = "各屏独立平铺"
    }
    
    -- 找到当前模式的索引
    local currentIdx = 1
    for i, mode in ipairs(modes) do
        if mode == TileManager.config.mode then
            currentIdx = i
            break
        end
    end
    
    -- 切换到下一个模式
    local nextIdx = currentIdx % #modes + 1
    TileManager.config.mode = modes[nextIdx]
    
    -- 屏幕中央大提示
    hs.alert.show("平铺: " .. modeNames[TileManager.config.mode], 1.5)
end

-- 获取平铺用的屏幕区域
-- 返回：区域列表（每个区域包含 x, y, w, h, screen 对象）
function TileManager.getTilingAreas()
    local allScreens = hs.screen.allScreens()
    local areas = {}
    
    for _, screen in ipairs(allScreens) do
        local frame = screen:frame()
        table.insert(areas, {
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h,
            screen = screen,  -- 保留屏幕对象
            screenFrame = frame
        })
    end
    
    return areas
end

-- 获取窗口当前所在的屏幕
function TileManager.getWindowScreen(win)
    local winScreen = win:screen()
    if not winScreen then return nil end
    
    -- 获取所有屏幕并匹配
    local allScreens = hs.screen.allScreens()
    for _, screen in ipairs(allScreens) do
        if screen:id() == winScreen:id() then
            return screen
        end
    end
    return winScreen
end

-- 按屏幕分组窗口
-- 返回：{ screenId = { windows = {...}, area = {...} }, ... }
function TileManager.groupWindowsByScreen(windows, areas)
    local groups = {}
    
    -- 初始化每个屏幕的组
    for _, area in ipairs(areas) do
        local screenId = area.screen:id()
        groups[screenId] = {
            windows = {},
            area = area,
            screen = area.screen
        }
    end
    
    -- 将窗口分配到对应的屏幕组
    for _, win in ipairs(windows) do
        local winScreen = win:screen()
        if winScreen then
            local screenId = winScreen:id()
            if groups[screenId] then
                table.insert(groups[screenId].windows, win)
            else
                -- 窗口在未知屏幕，分配到主屏幕
                local mainScreen = hs.screen.mainScreen()
                local mainId = mainScreen:id()
                if groups[mainId] then
                    table.insert(groups[mainId].windows, win)
                end
            end
        end
    end
    
    return groups
end

-- 计算多显示器的总宽度和高度
function TileManager.getTotalArea(areas)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    
    for _, area in ipairs(areas) do
        minX = math.min(minX, area.x)
        minY = math.min(minY, area.y)
        maxX = math.max(maxX, area.x + area.w)
        maxY = math.max(maxY, area.y + area.h)
    end
    
    return {
        x = minX,
        y = minY,
        w = maxX - minX,
        h = maxY - minY
    }
end

-- 根据窗口索引和总网格计算窗口应该放置的屏幕和位置
-- 返回：目标屏幕索引, 在该屏幕内的列, 行, 该屏幕的列数, 行数
function TileManager.calcWindowPosition(winIndex, totalWindows, areas)
    local screenCount = #areas
    
    -- 计算总网格
    local totalCols, totalRows = TileManager.calcGrid(totalWindows)
    
    -- 计算每个显示器分配的窗口数
    local windowsPerScreen = math.ceil(totalWindows / screenCount)
    
    -- 确定窗口属于哪个屏幕
    local screenIndex = math.min(math.ceil(winIndex / windowsPerScreen), screenCount)
    
    -- 在该屏幕内的索引
    local indexInScreen = winIndex - (screenIndex - 1) * windowsPerScreen
    local windowsInThisScreen = math.min(windowsPerScreen, totalWindows - (screenIndex - 1) * windowsPerScreen)
    
    -- 计算该屏幕内的网格
    local colsInScreen = math.min(totalCols, windowsInThisScreen)
    local rowsInScreen = math.ceil(windowsInThisScreen / colsInScreen)
    
    -- 在该屏幕内的行列位置
    local col = (indexInScreen - 1) % colsInScreen
    local row = math.floor((indexInScreen - 1) / colsInScreen)
    
    return screenIndex, col, row, colsInScreen, rowsInScreen
end

-- 计算最优行列数（使布局接近正方形）
function TileManager.calcGrid(count)
    if count <= 0 then return 0, 0 end
    if count == 1 then return 1, 1 end
    if count == 2 then return 2, 1 end
    if count == 3 then return 3, 1 end
    if count == 4 then return 2, 2 end
    if count == 5 then return 3, 2 end
    if count == 6 then return 3, 2 end
    
    -- 对于更多窗口，计算接近正方形的布局
    local cols = math.ceil(math.sqrt(count))
    local rows = math.ceil(count / cols)
    return cols, rows
end

-- 在指定区域内平铺一组窗口（内部辅助函数）
-- @param windows 窗口列表
-- @param area 区域 {x, y, w, h}
-- @param spacing 间距
function TileManager._tileInArea(windows, area, spacing)
    local count = #windows
    if count == 0 then return end

    local cols, rows = TileManager.calcGrid(count)
    local cellW = area.w / cols
    local cellH = area.h / rows

    for i, win in ipairs(windows) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)

        local w = cellW - spacing * 2
        local h = cellH - spacing * 2

        local cellCenterX = area.x + col * cellW + cellW / 2
        local cellCenterY = area.y + row * cellH + cellH / 2

        local x = cellCenterX - w / 2
        local y = cellCenterY - h / 2

        if x < area.x then x = area.x end
        if y < area.y then y = area.y end
        if x + w > area.x + area.w then w = area.x + area.w - x end
        if y + h > area.y + area.h then h = area.y + area.h - y end

        w = math.max(w, 100)
        h = math.max(h, 100)

        setWinFrame(win, hs.geometry.rect(x, y, w, h))
    end
end

-- 多显示器均分平铺（内部辅助函数）
-- @param windows 窗口列表
-- @param areas 区域列表
-- @param spacing 间距
function TileManager._tileMulti(windows, areas, spacing)
    local count = #windows
    if count == 0 then return end

    local screenCount = #areas
    local windowsPerScreen = math.ceil(count / screenCount)

    for i, win in ipairs(windows) do
        local screenIdx = math.min(math.ceil(i / windowsPerScreen), screenCount)
        local area = areas[screenIdx]

        local indexInScreen = i - (screenIdx - 1) * windowsPerScreen
        local windowsInThisScreen = math.min(windowsPerScreen, count - (screenIdx - 1) * windowsPerScreen)

        local cols, rows = TileManager.calcGrid(windowsInThisScreen)

        local col = (indexInScreen - 1) % cols
        local row = math.floor((indexInScreen - 1) / cols)

        local cellW = area.w / cols
        local cellH = area.h / rows
        local w = cellW - spacing * 2
        local h = cellH - spacing * 2

        local cellCenterX = area.x + col * cellW + cellW / 2
        local cellCenterY = area.y + row * cellH + cellH / 2

        local x = cellCenterX - w / 2
        local y = cellCenterY - h / 2

        if x < area.x then x = area.x end
        if y < area.y then y = area.y end
        if x + w > area.x + area.w then w = area.x + area.w - x end
        if y + h > area.y + area.h then h = area.y + area.h - y end

        w = math.max(w, 100)
        h = math.max(h, 100)

        setWinFrame(win, hs.geometry.rect(x, y, w, h))
    end
end

-- 平铺指定应用的窗口
-- @param appName 应用名称（可选，不传则平铺当前应用）
-- @param spacing 间距（可选，默认使用 TileManager.config.spacing）
function TileManager.tile(appName, spacing)
    spacing = spacing or TileManager.config.spacing
    
    local app
    if appName then
        app = hs.application.get(appName)
    else
        local win = hs.window.focusedWindow()
        if win then
            app = win:application()
            appName = app:name()
        end
    end
    
    if not app then
        notify("平铺失败", "应用未找到")
        return
    end
    
    local windows = {}
    for _, win in ipairs(app:allWindows()) do
        if win:isStandard() then
            table.insert(windows, win)
        end
    end
    
    local count = #windows
    if count == 0 then
        notify("平铺失败", "没有找到可平铺的窗口")
        return
    end
    if count == 1 then
        notify("平铺提示", "只有1个窗口，无需平铺")
        return
    end
    
    local key = appName .. "_original"
    if not TileManager.originalLayouts[key] then
        local original = {}
        for _, win in ipairs(windows) do
            table.insert(original, {id = win:id(), frame = win:frame()})
        end
        TileManager.originalLayouts[key] = original
    end
    
    -- 获取平铺区域
    local areas = TileManager.getTilingAreas()
    local mode = TileManager.config.mode
    
    if mode == "single" or #areas == 1 then
        TileManager._tileInArea(windows, areas[1], spacing)
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("平铺完成", appName .. " " .. count .. " 个窗口" .. spacingText)

    elseif mode == "multi" then
        TileManager._tileMulti(windows, areas, spacing)
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("平铺完成 [多显示器均分]", appName .. " " .. count .. " 个窗口" .. spacingText)

    elseif mode == "perScreen" then
        local groups = TileManager.groupWindowsByScreen(windows, areas)
        local tiledCount = 0

        for screenId, group in pairs(groups) do
            TileManager._tileInArea(group.windows, group.area, spacing)
            tiledCount = tiledCount + #group.windows
        end

        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("平铺完成 [各屏独立]", appName .. " " .. tiledCount .. " 个窗口" .. spacingText)
    end
end



-- 平铺所有应用的窗口
-- @param spacing 间距（可选，默认使用 TileManager.config.spacing）
function TileManager.tileAll(spacing)
    spacing = spacing or TileManager.config.spacing
    
    local allWindows = {}
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isStandard() and win:application() then
            -- 排除 Edge Dock 中停靠的窗口
            if not TileManager.isWindowInEdgeDock(win) then
                table.insert(allWindows, win)
            end
        end
    end
    
    local count = #allWindows
    if count == 0 then
        notify("平铺失败", "没有找到可平铺的窗口")
        return
    end
    if count == 1 then
        notify("平铺提示", "只有1个窗口，无需平铺")
        return
    end
    
    -- 保存所有窗口的原始布局
    local key = "_all_windows_"
    if not TileManager.originalLayouts[key] then
        local original = {}
        for _, win in ipairs(allWindows) do
            table.insert(original, {id = win:id(), frame = win:frame()})
        end
        TileManager.originalLayouts[key] = original
    end
    
    -- 获取平铺区域
    local areas = TileManager.getTilingAreas()
    local mode = TileManager.config.mode
    
    if mode == "single" or #areas == 1 then
        TileManager._tileInArea(allWindows, areas[1], spacing)
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("全局平铺完成", "共 " .. count .. " 个窗口" .. spacingText)

    elseif mode == "multi" then
        TileManager._tileMulti(allWindows, areas, spacing)
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("全局平铺完成 [多显示器均分]", "共 " .. count .. " 个窗口" .. spacingText)

    elseif mode == "perScreen" then
        local groups = TileManager.groupWindowsByScreen(allWindows, areas)
        local tiledCount = 0
        local screenInfo = {}

        for screenId, group in pairs(groups) do
            local screenCount = #group.windows
            if screenCount > 0 then
                table.insert(screenInfo, screenCount)
                TileManager._tileInArea(group.windows, group.area, spacing)
                tiledCount = tiledCount + screenCount
            end
        end

        table.sort(screenInfo)
        local distribution = table.concat(screenInfo, "+")
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("全局平铺完成 [各屏独立]", "共 " .. tiledCount .. " 个窗口 [" .. distribution .. "]" .. spacingText)
    end
end

-- 恢复平铺前的布局
-- @param appName 应用名称（可选，不传则恢复当前应用）
function TileManager.restore(appName)
    local key
    if appName then
        key = appName .. "_original"
    else
        key = "_all_windows_"
    end
    
    local original = TileManager.originalLayouts[key]
    if not original then
        notify("恢复失败", "没有找到保存的布局")
        return
    end
    
    for _, item in ipairs(original) do
        local win = hs.window.get(item.id)
        if win and win:isStandard() then
            setWinFrame(win, item.frame)
        end
    end
    
    TileManager.originalLayouts[key] = nil
    notify("已恢复", appName or "所有窗口")
end

-- 恢复当前应用的布局
function TileManager.restoreCurrent()
    local win = hs.window.focusedWindow()
    if win then
        TileManager.restore(win:application():name())
    else
        -- 如果没有聚焦窗口，尝试恢复全局布局
        TileManager.restore(nil)
    end
end

-- 设置间距
function TileManager.setSpacing(spacing)
    TileManager.config.spacing = spacing or 0
    notify("平铺间距已设置", "当前间距: " .. TileManager.config.spacing .. "px")
end

-- 平铺当前应用的所有窗口
function TileManager.tileCurrent(spacing)
    spacing = spacing or TileManager.config.spacing
    TileManager.tile(nil, spacing)
end

-- 平铺快捷键：当前应用（Ctrl+Opt+Cmd+T）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "t", function()
    TileManager.tileCurrent()
end)

-- 平铺快捷键：所有应用（Ctrl+Opt+Cmd+A）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "a", function()
    TileManager.tileAll()
end)

-- 恢复平铺快捷键（Ctrl+Opt+Cmd+O）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "o", TileManager.restoreCurrent)

-- 设置间距快捷键（Ctrl+Opt+Cmd+;）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, ";", function()
    local button, text = hs.dialog.textPrompt("设置平铺间距", 
        "输入间距（像素，可以是负数）：", 
        tostring(TileManager.config.spacing), 
        "确定", "取消")
    if button == "确定" and text ~= "" then
        local spacing = tonumber(text)
        if spacing ~= nil then
            TileManager.setSpacing(spacing)
        else
            notify("设置失败", "请输入有效的数字")
        end
    end
end)

-- 切换平铺模式（Ctrl+Opt+Cmd+M）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "m", function()
    TileManager.cycleMode()
end)

-- ============================================
-- Edge Dock 辅助函数（必须在 EdgeDock 定义后加载）
-- ============================================

-- 检查窗口是否在 Edge Dock 中
function TileManager.isWindowInEdgeDock(win)
    if not win then return false end
    local winId = win:id()
    for i = 1, EdgeDock.config.maxSlots do
        local slot = EdgeDock.slots[i]
        if slot and slot.winId == winId then
            return true
        end
    end
    return false
end

-- ============================================
-- 开发工具平铺：将 VS Code 和 Terminal 移到主显示器并平铺
-- ============================================

-- 配置：开发工具应用列表（可按需修改）
TileManager.devToolApps = {"Code", "Ghostty"}

function TileManager.tileDevTools(spacing)
    spacing = spacing or TileManager.config.spacing
    local key = "_dev_tools_original_"

    -- 如果已保存布局，则恢复（toggle 行为）
    if TileManager.originalLayouts[key] then
        TileManager.restoreDevTools()
        return
    end

    -- 收集所有目标应用的窗口
    local allWindows = {}
    local foundApps = {}

    for _, appName in ipairs(TileManager.devToolApps) do
        local app = hs.application.get(appName)
        if app then
            table.insert(foundApps, appName)
            for _, win in ipairs(app:allWindows()) do
                if win:isStandard() and not TileManager.isWindowInEdgeDock(win) then
                    table.insert(allWindows, win)
                end
            end
        end
    end

    local count = #allWindows
    if count == 0 then
        notify("平铺失败", "没有找到 Code 或 Ghostty 的窗口")
        return
    end
    if count == 1 then
        notify("平铺提示", "只有1个窗口，无需平铺")
        return
    end

    -- 保存原始布局
    local original = {}
    for _, win in ipairs(allWindows) do
        table.insert(original, {id = win:id(), frame = win:frame()})
    end
    TileManager.originalLayouts[key] = original

    local mode = TileManager.config.mode
    local areas = TileManager.getTilingAreas()

    if mode == "single" or #areas == 1 then
        -- 单屏幕模式：鼠标所在屏幕
        local targetScreen = hs.mouse.getCurrentScreen()
        if not targetScreen then
            notify("平铺失败", "无法获取鼠标所在显示器")
            return
        end

        local frame = targetScreen:frame()
        local area = {
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h
        }

        TileManager._tileInArea(allWindows, area, spacing)
        local appsText = table.concat(foundApps, ", ")
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("开发工具平铺完成", appsText .. " 共 " .. count .. " 个窗口" .. spacingText)

    elseif mode == "multi" then
        -- 多显示器均分
        TileManager._tileMulti(allWindows, areas, spacing)
        local appsText = table.concat(foundApps, ", ")
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("开发工具平铺完成 [多显示器均分]", appsText .. " 共 " .. count .. " 个窗口" .. spacingText)

    elseif mode == "perScreen" then
        -- 各屏独立平铺
        local groups = TileManager.groupWindowsByScreen(allWindows, areas)
        local tiledCount = 0

        for screenId, group in pairs(groups) do
            TileManager._tileInArea(group.windows, group.area, spacing)
            tiledCount = tiledCount + #group.windows
        end

        local appsText = table.concat(foundApps, ", ")
        local spacingText = spacing == 0 and "" or " (间距: " .. spacing .. "px)"
        notify("开发工具平铺完成 [各屏独立]", appsText .. " 共 " .. tiledCount .. " 个窗口" .. spacingText)
    end
end

-- 恢复开发工具布局
function TileManager.restoreDevTools()
    local key = "_dev_tools_original_"
    local original = TileManager.originalLayouts[key]
    if not original then
        notify("恢复失败", "没有找到保存的开发工具布局")
        return
    end

    for _, item in ipairs(original) do
        local win = hs.window.get(item.id)
        if win and win:isStandard() then
            setWinFrame(win, item.frame)
        end
    end

    TileManager.originalLayouts[key] = nil
    notify("已恢复", "开发工具窗口")
end

-- 快捷键：开发工具平铺/恢复 (Ctrl+Opt+Cmd+V)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "v", function()
    TileManager.tileDevTools()
end)
