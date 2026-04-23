-- ============================================
-- 显示器布局记忆功能
-- 当外接显示器断开/重新连接时自动保存和恢复窗口布局
-- ============================================

local DisplayLayoutManager = {
    savedLayouts = {},          -- 按屏幕配置保存的布局
    lastScreenCount = 0,        -- 上次屏幕数量
    isRestoring = false,        -- 是否正在恢复中（避免递归）
    stateFile = CONFIG_PATH .. DisplayLayoutConfig.stateFile,
}

-- 获取当前屏幕配置的唯一标识
function DisplayLayoutManager.getScreenConfig()
    local screens = hs.screen.allScreens()
    local screenIds = {}
    for _, screen in ipairs(screens) do
        table.insert(screenIds, tostring(screen:id()))
    end
    table.sort(screenIds)
    return table.concat(screenIds, "_")
end

-- 获取屏幕数量
function DisplayLayoutManager.getScreenCount()
    return #hs.screen.allScreens()
end

-- 保存当前所有窗口的布局
function DisplayLayoutManager.saveLayout(showNotify)
    if DisplayLayoutManager.isRestoring then return end
    
    local config = DisplayLayoutManager.getScreenConfig()
    local layout = {}
    local windows = hs.window.allWindows()
    
    for _, win in ipairs(windows) do
        if win:isStandard() then
            -- 忽略 Edge Dock 中的窗口
            if not TileManager.isWindowInEdgeDock(win) then
                local app = win:application()
                local screen = win:screen()
                if app and screen then
                    local frame = win:frame()
                    table.insert(layout, {
                        app = app:name(),
                        title = win:title(),
                        winId = win:id(),
                        screenId = screen:id(),
                        screenName = screen:name(),
                        x = frame.x,
                        y = frame.y,
                        w = frame.w,
                        h = frame.h,
                    })
                end
            end
        end
    end
    
    DisplayLayoutManager.savedLayouts[config] = layout
    
    -- 保存到文件
    local file = io.open(DisplayLayoutManager.stateFile, "w")
    if file then
        file:write(hs.json.encode(DisplayLayoutManager.savedLayouts))
        file:close()
    end
    
    print("[DisplayLayout] 布局已保存 (" .. #layout .. " 个窗口, 配置: " .. config .. ")")
    
    if showNotify then
        notify("显示器布局", "已保存当前布局 (" .. #layout .. " 个窗口)")
        hs.alert.show("显示器布局已保存\n" .. #layout .. " 个窗口", 1.5)
    end
end

-- 从文件加载保存的布局
function DisplayLayoutManager.loadLayouts()
    local file = io.open(DisplayLayoutManager.stateFile, "r")
    if file then
        local content = file:read("*all")
        file:close()
        local ok, layouts = pcall(function() return hs.json.decode(content) end)
        if ok and layouts then
            DisplayLayoutManager.savedLayouts = layouts
            print("[DisplayLayout] 已从文件加载布局")
        end
    end
end

-- 恢复指定配置的布局
function DisplayLayoutManager.restoreLayout(targetConfig)
    targetConfig = targetConfig or DisplayLayoutManager.getScreenConfig()
    local layout = DisplayLayoutManager.savedLayouts[targetConfig]
    
    if not layout then
        print("[DisplayLayout] 没有找到配置 " .. targetConfig .. " 的布局")
        return false
    end
    
    DisplayLayoutManager.isRestoring = true
    
    -- 获取当前所有屏幕
    local screens = hs.screen.allScreens()
    local screenMap = {}
    for _, screen in ipairs(screens) do
        screenMap[screen:id()] = screen
    end
    
    local restoredCount = 0
    local failedWindows = {}
    
    for _, item in ipairs(layout) do
        -- 尝试通过 winId 查找窗口
        local win = nil
        if item.winId then
            win = hs.window.get(item.winId)
        end
        
        -- 如果 winId 找不到，尝试通过应用名和标题查找
        if not win then
            local app = hs.application.get(item.app)
            if app then
                for _, w in ipairs(app:allWindows()) do
                    if w:isStandard() and w:title() == item.title then
                        win = w
                        break
                    end
                end
                -- 如果没找到标题匹配的，使用第一个窗口
                if not win then
                    for _, w in ipairs(app:allWindows()) do
                        if w:isStandard() then
                            win = w
                            break
                        end
                    end
                end
            end
        end
        
        if win then
            -- 计算目标屏幕
            local targetScreen = screenMap[item.screenId]
            
            -- 如果原屏幕不存在（比如外接显示器还没识别），尝试找到最匹配的屏幕
            if not targetScreen and #screens > 0 then
                -- 优先尝试通过名称匹配
                for _, screen in ipairs(screens) do
                    if screen:name() == item.screenName then
                        targetScreen = screen
                        break
                    end
                end
                -- 如果还是找不到，使用主屏幕
                if not targetScreen then
                    targetScreen = hs.screen.mainScreen()
                end
            end
            
            if targetScreen then
                local screenFrame = targetScreen:frame()
                
                -- 计算相对位置（相对于原屏幕）
                -- 先找到原屏幕的信息（从保存的布局中推断）
                local originalScreenX, originalScreenY = item.x, item.y
                
                -- 如果窗口原本在这个屏幕上，使用保存的绝对坐标
                -- 否则需要计算相对位置（这里简化处理，直接使用绝对坐标）
                
                -- 确保窗口不会超出目标屏幕太多
                local newX = math.max(screenFrame.x, math.min(item.x, screenFrame.x + screenFrame.w - item.w))
                local newY = math.max(screenFrame.y, math.min(item.y, screenFrame.y + screenFrame.h - item.h))
                
                -- 如果窗口原本是占满屏幕高度的，保持全高
                local frame = win:frame()
                local currentScreen = win:screen()
                if currentScreen then
                    local currentFrame = currentScreen:frame()
                    -- 检测是否是全高窗口
                    if math.abs(item.h - currentFrame.h) < 20 then
                        newY = screenFrame.y
                        item.h = screenFrame.h
                    end
                end
                
                setWinFrame(win, hs.geometry.rect(newX, newY, item.w, item.h))
                restoredCount = restoredCount + 1
                print(string.format("[DisplayLayout] 恢复窗口: %s - %s 到屏幕 %s", 
                    item.app, item.title or "", targetScreen:name()))
            else
                table.insert(failedWindows, item.app .. ":" .. (item.title or ""))
            end
        else
            table.insert(failedWindows, item.app .. ":" .. (item.title or ""))
        end
    end
    
    DisplayLayoutManager.isRestoring = false
    
    if restoredCount > 0 then
        notify("显示器布局", string.format("已恢复 %d 个窗口", restoredCount))
        hs.alert.show(string.format("显示器布局已恢复\n%d 个窗口", restoredCount), 1.5)
        print("[DisplayLayout] 恢复完成: " .. restoredCount .. "/" .. #layout .. " 个窗口")
    end
    
    if #failedWindows > 0 then
        print("[DisplayLayout] 失败的窗口: " .. table.concat(failedWindows, ", "))
    end
    
    return restoredCount > 0
end

-- 屏幕变化处理
function DisplayLayoutManager.onScreenChange()
    local currentCount = DisplayLayoutManager.getScreenCount()
    local lastCount = DisplayLayoutManager.lastScreenCount
    
    print(string.format("[DisplayLayout] 屏幕变化: %d -> %d 个屏幕", lastCount, currentCount))
    
    -- 如果是从多屏变成单屏，保存布局（已禁用自动保存，使用手动 ⌃⌥D 保存）
    -- if lastCount > 1 and currentCount == 1 then
    --     print("[DisplayLayout] 外接显示器断开，保存布局...")
    --     DisplayLayoutManager.saveLayout()
    -- end
    
    -- 如果是从单屏变成多屏，尝试恢复布局
    if lastCount == 1 and currentCount > 1 then
        print("[DisplayLayout] 外接显示器连接，尝试恢复布局...")
        -- 延迟一点等待显示器完全识别
        hs.timer.doAfter(1.5, function()
            -- 尝试找到之前多屏配置的布局
            -- 遍历所有保存的布局，找到屏幕数量匹配的
            local targetConfig = nil
            for config, _ in pairs(DisplayLayoutManager.savedLayouts) do
                -- 配置格式是 "id1_id2_id3"，通过下划线数量判断屏幕数
                local _, count = string.gsub(config, "_", "")
                local screenCount = count + 1
                if screenCount == currentCount then
                    targetConfig = config
                    break
                end
            end
            
            if targetConfig then
                DisplayLayoutManager.restoreLayout(targetConfig)
            else
                -- 如果没有找到匹配的，尝试保存当前单屏布局后恢复
                -- 或者使用最近的保存的布局
                print("[DisplayLayout] 没有找到匹配的 " .. currentCount .. " 屏配置")
            end
        end)
    end
    
    -- 如果是多屏之间的变化（比如换了不同的外接显示器），也保存一下（已禁用自动保存）
    -- if lastCount > 1 and currentCount > 1 and lastCount == currentCount then
    --     hs.timer.doAfter(2, function()
    --         DisplayLayoutManager.saveLayout()
    --     end)
    -- end
    
    DisplayLayoutManager.lastScreenCount = currentCount
end

-- 初始化
function DisplayLayoutManager.init()
    -- 加载保存的布局
    DisplayLayoutManager.loadLayouts()
    
    -- 记录初始屏幕数量
    DisplayLayoutManager.lastScreenCount = DisplayLayoutManager.getScreenCount()
    
    -- 创建屏幕监听器
    DisplayLayoutManager.screenWatcher = hs.screen.watcher.new(function()
        -- 延迟处理，等待屏幕完全初始化
        hs.timer.doAfter(1, DisplayLayoutManager.onScreenChange)
    end)
    DisplayLayoutManager.screenWatcher:start()
    
    -- 系统休眠/唤醒监听（休眠时通常会断开外接显示器）
    DisplayLayoutManager.caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
        if eventType == hs.caffeinate.watcher.systemWillSleep then
            print("[DisplayLayout] 系统即将休眠（自动保存已禁用，使用手动 ⌃⌥D 保存）")
            -- DisplayLayoutManager.saveLayout()
        elseif eventType == hs.caffeinate.watcher.systemDidWake then
            print("[DisplayLayout] 系统唤醒，屏幕数量: " .. DisplayLayoutManager.getScreenCount())
            -- 唤醒后更新屏幕数量，避免误判
            hs.timer.doAfter(3, function()
                DisplayLayoutManager.lastScreenCount = DisplayLayoutManager.getScreenCount()
                print("[DisplayLayout] 唤醒后屏幕数量更新为: " .. DisplayLayoutManager.lastScreenCount)
            end)
        end
    end)
    DisplayLayoutManager.caffeinateWatcher:start()
    
    print("[DisplayLayout] 显示器布局管理器已初始化，当前 " .. DisplayLayoutManager.lastScreenCount .. " 个屏幕")
end

-- 手动保存布局快捷键 (⌃⌥⇧ D)
hs.hotkey.bind(mashShift, "d", function()
    DisplayLayoutManager.saveLayout(true)
end)

-- 手动恢复布局快捷键 (⌃⌥ D)
hs.hotkey.bind(mash, "d", function()
    DisplayLayoutManager.restoreLayout()
end)

-- 启动显示器布局管理器
DisplayLayoutManager.init()
