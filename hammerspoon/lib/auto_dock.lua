-- ============================================
-- 自动停靠：应用打开时自动停靠到指定槽位
-- ============================================

-- 使用 config.lua 中的自动停靠配置

-- 应用启动监听器（自动停靠）
EdgeDock.autoDockWatcher = hs.application.watcher.new(function(appName, eventType, appObj)
    -- 只处理应用启动事件
    if eventType ~= hs.application.watcher.launched then
        return
    end
    
    -- 检查是否有该应用的自动停靠配置
    local targetSlot = AutoDockConfig[appName]
    if not targetSlot then
        return
    end
    
    -- 检查目标槽位是否已被占用
    if EdgeDock.slots[targetSlot] then
        print("[AutoDock] " .. appName .. " 启动，但槽位 " .. targetSlot .. " 已被占用")
        return
    end
    
    print("[AutoDock] " .. appName .. " 启动，等待窗口创建...")
    
    -- 延迟执行，等待应用窗口完全加载
    hs.timer.doAfter(1.5, function()
        -- 重新获取应用对象（可能已变化）
        local app = hs.application.get(appName)
        if not app then
            print("[AutoDock] 无法获取应用: " .. appName)
            return
        end
        
        -- 获取应用的所有标准窗口
        local windows = {}
        for _, win in ipairs(app:allWindows()) do
            if win:isStandard() then
                table.insert(windows, win)
            end
        end
        
        if #windows == 0 then
            print("[AutoDock] " .. appName .. " 没有可停靠的窗口")
            return
        end
        
        -- 使用第一个窗口进行停靠
        local win = windows[1]
        
        -- 再次检查槽位是否仍为空（可能被其他操作占用）
        if EdgeDock.slots[targetSlot] then
            print("[AutoDock] 槽位 " .. targetSlot .. " 已被占用，跳过")
            return
        end
        
        -- 执行停靠（使用 autoPeek 模式：如果鼠标在窗口上则自动显示）
        print("[AutoDock] 将 " .. appName .. " 停靠到槽位 " .. targetSlot)
        EdgeDock.dockWindow(win, targetSlot, {autoPeek = true})
    end)
end)

-- 启动自动停靠监听器
EdgeDock.autoDockWatcher:start()
print("[AutoDock] 自动停靠功能已启动")
