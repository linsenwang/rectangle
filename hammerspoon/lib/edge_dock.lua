-- ============================================
-- 边缘窗口坞（Edge Dock）- 常驻小条 + 拖拽停靠
-- ============================================

EdgeDock = {
    slots = {},             -- 槽位 {win, originalFrame, appName, isShowing, hideTimer}
    bars = {},              -- 小条 UI 元素
    mask = nil,             -- 右侧遮罩条（遮挡可能露出的窗口边缘）
    currentBarScreen = nil,  -- 当前小条所在的屏幕（用于多显示器检测）
    config = {
        maxSlots = 7,       -- 最大槽位数
        barWidth = 3,       -- 小条宽度
        topMargin = 6,      -- 顶部边距（距离屏幕上边缘）
        bottomMargin = 6,   -- 底部边距（距离屏幕下边缘）
        barGap = 10,        -- 小条之间的空隙
        peekWidth = 1,      -- 窗口 peek 出来的宽度
        hideDelay = 0,      -- 鼠标离开后多久收起（秒）
        centeredPause = true,  -- 居中后暂停鼠标移出检测
        -- 鼠标触发范围配置（像素）
        triggerRange = {
            leftExtend = 7,   -- 槽位左侧向左扩展的触发范围
            rightExtend = 5,   -- 屏幕右边缘向右扩展的触发范围
            topExtend = 5,     -- 槽位顶部向上扩展的触发范围
            bottomExtend = 5,  -- 槽位底部向下扩展的触发范围
        },
        -- 深色/浅色模式颜色配置
        colors = {
            dark = {
                emptyBar = {alpha = 0.3, red = 0.3, green = 0.3, blue = 0.3},      -- 空槽位颜色
                emptyText = {alpha = 0, red = 1, green = 1, blue = 1},           -- 空槽位文字颜色
                highlightOccupied = {alpha = 0.9, red = 0.3, green = 0.7, blue = 1.0},  -- 高亮-有窗口
                highlightEmpty = {alpha = 0.6, red = 0.5, green = 0.5, blue = 0.5},     -- 高亮-空槽位
                highlightText = {alpha = 1, red = 1, green = 1, blue = 1},          -- 高亮文字颜色
                normalOccupiedText = {alpha = 1, red = 0, green = 0, blue = 0},     -- 正常-有窗口文字
                mask = {alpha = 1, red = 0, green = 0, blue = 0},                   -- 遮罩条颜色
            },
            light = {
                emptyBar = {alpha = 0.2, red = 0.7, green = 0.7, blue = 0.7},      -- 空槽位颜色（浅灰）
                emptyText = {alpha = 0, red = 0.3, green = 0.3, blue = 0.3},      -- 空槽位文字颜色（深灰）
                highlightOccupied = {alpha = 0.9, red = 0.2, green = 0.5, blue = 0.9},  -- 高亮-有窗口（深蓝）
                highlightEmpty = {alpha = 0.5, red = 0.6, green = 0.6, blue = 0.6},     -- 高亮-空槽位
                highlightText = {alpha = 1, red = 1, green = 1, blue = 1},          -- 高亮文字颜色
                normalOccupiedText = {alpha = 1, red = 1, green = 1, blue = 1},     -- 正常-有窗口文字（浅色模式用白色）
                mask = {alpha = 1, red = 0, green = 0, blue = 0},                   -- 遮罩条颜色
            }
        }
    }
}

-- 缓存应用颜色
EdgeDock.appColorCache = {}

-- 检测当前外观模式（深色/浅色）
function EdgeDock.getAppearanceMode()
    local success, result = pcall(function()
        local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
        if handle then
            local output = handle:read("*a")
            handle:close()
            if output and output:match("Dark") then
                return "dark"
            end
        end
        return "light"
    end)
    return success and result or "light"
end

-- 获取当前模式的颜色配置
function EdgeDock.getCurrentColors()
    local mode = EdgeDock.getAppearanceMode()
    return EdgeDock.config.colors[mode] or EdgeDock.config.colors.dark
end

-- 常用应用颜色表（支持深色/浅色模式）
-- 如果不指定某个模式，则回退到另一个模式
EdgeDock.knownAppColors = {
    ["WeChat"] = {
        dark  = {red = 0.40, green = 0.65, blue = 0.45},
        light = {red = 0.15, green = 0.35, blue = 0.20}, -- 更深
    },
    ["ChatGPT"] = {
        dark  = {red = 0.65, green = 0.65, blue = 0.65},
        light = {red = 0.18, green = 0.18, blue = 0.18}, -- 接近石墨灰
    },
    ["Music"] = {
        dark  = {red = 1.00, green = 0.30, blue = 0.38},
        light = {red = 0.45, green = 0.18, blue = 0.25}, -- 压暗
    },
    ["Kimi"] = {
        dark  = {red = 0.55, green = 0.60, blue = 0.80},
        light = {red = 0.28, green = 0.38, blue = 0.60}, -- 更深蓝
    },
    ["Safari"] = {
        dark  = {red = 0.25, green = 0.65, blue = 1.00},
        light = {red = 0.05, green = 0.38, blue = 0.80}, -- 更沉
    },
    ["Chrome"] = {
        dark  = {red = 1.00, green = 0.40, blue = 0.20},
        light = {red = 0.65, green = 0.18, blue = 0.05}, -- 深红橙
    },
    ["Code"] = {
        dark  = {red = 0.25, green = 0.55, blue = 0.95},
        light = {red = 0.05, green = 0.30, blue = 0.60}, -- 深蓝
    },
    ["Terminal"] = {
        dark  = {red = 0.70, green = 0.70, blue = 0.70},
        light = {red = 0.12, green = 0.12, blue = 0.12}, -- 更深黑灰
    },
}

-- 获取应用在当前模式下的颜色
function EdgeDock.getKnownAppColor(appName)
    local colorEntry = EdgeDock.knownAppColors[appName]
    if not colorEntry then
        return nil
    end
    
    local mode = EdgeDock.getAppearanceMode()
    local color = nil
    
    -- 优先返回当前模式的颜色
    if colorEntry[mode] then
        color = colorEntry[mode]
    elseif mode == "dark" and colorEntry.light then
        -- 深色模式回退到浅色
        color = colorEntry.light
    elseif mode == "light" and colorEntry.dark then
        -- 浅色模式回退到深色
        color = colorEntry.dark
    else
        -- 都没有的话返回第一个可用的
        color = colorEntry.dark or colorEntry.light
    end
    
    return color
end

-- 获取应用图标的颜色
function EdgeDock.getAppIconColor(appName)
    -- 获取当前模式用于缓存键
    local mode = EdgeDock.getAppearanceMode()
    local cacheKey = appName .. "_" .. mode
    
    -- 检查缓存
    if EdgeDock.appColorCache[cacheKey] then
        return EdgeDock.appColorCache[cacheKey]
    end
    
    -- 1. 先检查已知应用颜色表（支持深浅模式）
    local knownColor = EdgeDock.getKnownAppColor(appName)
    if knownColor then
        local color = EdgeDock.brightenColor(knownColor, 1.3)
        color.alpha = 0.85
        EdgeDock.appColorCache[cacheKey] = color
        return color
    end
    
    -- 2. 使用名称生成颜色
    local color = EdgeDock.generateColorFromName(appName)
    color.alpha = 0.3
    EdgeDock.appColorCache[cacheKey] = color
    return color
end

-- 根据应用名生成稳定颜色
function EdgeDock.generateColorFromName(appName)
    local hash = 0
    for i = 1, #appName do
        hash = hash + string.byte(appName, i) * i * 31
    end
    hash = hash % 360
    
    -- HSL to RGB
    local hue = hash / 360
    local s, l = 0.75, 0.6
    
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end
    
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    
    return {
        red = hue2rgb(p, q, hue + 1/3),
        green = hue2rgb(p, q, hue),
        blue = hue2rgb(p, q, hue - 1/3),
        alpha = 0.9
    }
end

-- 亮度增加函数
function EdgeDock.brightenColor(color, factor)
    factor = factor or 1.3
    return {
        red = math.min(1, color.red * factor),
        green = math.min(1, color.green * factor),
        blue = math.min(1, color.blue * factor),
        alpha = color.alpha
    }
end

-- 获取鼠标所在的屏幕
function EdgeDock.getCurrentScreen()
    local screen = hs.mouse.getCurrentScreen()
    if not screen then
        screen = hs.screen.mainScreen()
    end
    return screen:frame()
end

-- 计算小条高度（根据屏幕高度自动分配）
function EdgeDock.getBarHeight(screenFrame)
    local screen = screenFrame or EdgeDock.getCurrentScreen()
    local availableHeight = screen.h - EdgeDock.config.topMargin - EdgeDock.config.bottomMargin
    local totalGap = (EdgeDock.config.maxSlots - 1) * EdgeDock.config.barGap
    return math.floor((availableHeight - totalGap) / EdgeDock.config.maxSlots)
end

-- 获取槽位位置（根据屏幕高度自动分布）
function EdgeDock.getSlotPosition(slotIndex, screenFrame)
    local screen = screenFrame or EdgeDock.getCurrentScreen()
    local barHeight = EdgeDock.getBarHeight(screen)
    local startY = screen.y + EdgeDock.config.topMargin
    local x = screen.x + screen.w - EdgeDock.config.barWidth - 5  -- 减5px给遮罩条留位置
    local y = startY + (slotIndex - 1) * (barHeight + EdgeDock.config.barGap)
    return x, y, EdgeDock.config.barWidth, barHeight
end

-- 检查点是否在槽位区域
function EdgeDock.isPointInSlot(x, y, slotIndex)
    local sx, sy, sw, sh = EdgeDock.getSlotPosition(slotIndex)
    local r = EdgeDock.config.triggerRange
    return x >= sx - r.leftExtend and x <= sx + sw + r.rightExtend
           and y >= sy - r.topExtend and y <= sy + sh + r.bottomExtend
end

-- 检查点是否在窗口区域内（用于检测鼠标是否离开窗口）
function EdgeDock.isPointInWindow(mouseX, mouseY, win, slot)
    local frame = nil
    if win then
        frame = win:frame()
    elseif slot and slot.lastWinFrame then
        -- 使用缓存的 frame
        frame = slot.lastWinFrame
    end
    if not frame then return false end
    return mouseX >= frame.x and mouseX <= frame.x + frame.w
           and mouseY >= frame.y and mouseY <= frame.y + frame.h
end

-- 创建/刷新右侧遮罩条（2px宽，遮挡可能被推出的窗口边缘）
function EdgeDock.refreshMask()
    if EdgeDock.mask then
        EdgeDock.mask:delete()
    end
    
    -- 获取当前模式的颜色
    local colors = EdgeDock.getCurrentColors()
    
    local screen = EdgeDock.getCurrentScreen()
    -- 2px宽，全屏高，放在最右侧
    EdgeDock.mask = hs.canvas.new({x = screen.x + screen.w - 2, y = screen.y, w = 2, h = screen.h})
    EdgeDock.mask:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = colors.mask,
    })
    EdgeDock.mask:level(hs.canvas.windowLevels.overlay)
    EdgeDock.mask:show()
end

-- 获取带时间戳的日志前缀
function EdgeDock.logPrefix()
    return os.date("%Y-%m-%d %H:%M:%S") .. " [EdgeDock]"
end

-- 验证槽位窗口是否仍然有效（后台定时器使用）
function EdgeDock.validateSlot(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return nil end
    
    local prefix = EdgeDock.logPrefix()
    local oldWinId = slot.winId
    local appName = slot.appName or "unknown"
    
    -- 检查 winId 是否有效（不为 0 或 -1）
    if not oldWinId or oldWinId == 0 or oldWinId == -1 then
        print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") winId=" .. tostring(oldWinId) .. " 无效，尝试重新连接...")
        -- winId 无效，尝试重新连接
        local reconnectedWin = EdgeDock.tryReconnect(slot)
        if reconnectedWin then
            local newWinId = reconnectedWin:id()
            print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") 重新连接成功，新winId=" .. tostring(newWinId))
            slot.win = reconnectedWin
            slot.winId = newWinId
            return slot
        end
        print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") 重新连接失败")
        return nil
    end
    
    -- 尝试通过 winId 获取窗口对象
    local win = hs.window.get(oldWinId)
    if win then
        -- 窗口仍然存在，检查是否和之前是同一个窗口对象
        local currentWinId = win:id()
        if currentWinId ~= oldWinId then
            print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") winId变化: " .. tostring(oldWinId) .. " -> " .. tostring(currentWinId))
            slot.winId = currentWinId
        end
        
        -- 检查窗口是否是标准窗口
        if win:isStandard() then
            slot.win = win
            return slot
        else
            -- 窗口存在但不是标准窗口（可能是休眠后的临时状态）
            print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") 窗口存在但非标准，可能是临时状态")
            -- 仍然返回 slot，但不更新 win（让定时器后续再试）
            return slot
        end
    else
        print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") winId=" .. tostring(oldWinId) .. " 获取失败，尝试重新连接...")
    end
    
    -- winId 失效，尝试重新连接
    local reconnectedWin = EdgeDock.tryReconnect(slot)
    if reconnectedWin then
        local newWinId = reconnectedWin:id()
        if newWinId and newWinId ~= 0 then
            print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") 重新连接成功，新winId=" .. tostring(newWinId))
            slot.win = reconnectedWin
            slot.winId = newWinId
            return slot
        else
            print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") 重新连接成功但 winId 无效=" .. tostring(newWinId))
            -- 仍然返回 slot，等待下次验证
            slot.win = reconnectedWin
            return slot
        end
    end
    
    -- 窗口已关闭或无法重新连接
    print(prefix .. " [VALIDATE] 槽位 " .. slotIndex .. " (" .. appName .. ") 重新连接失败")
    return nil
end

-- 轻量级验证槽位（用于鼠标交互，非阻塞）
function EdgeDock.quickValidateSlot(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return nil end
    
    local prefix = EdgeDock.logPrefix()
    local oldWinId = slot.winId
    
    -- 尝试通过 winId 获取窗口对象
    if slot.winId then
        local win = hs.window.get(slot.winId)
        if win then
            slot.win = win
            return slot
        end
    end
    
    -- winId 失效，尝试重新连接
    print(prefix .. " [QUICK_VALIDATE] 槽位 " .. slotIndex .. " (" .. (slot.appName or "unknown") .. ") winId=" .. tostring(oldWinId) .. " 失效，尝试重新连接...")
    local reconnectedWin = EdgeDock.tryReconnect(slot)
    if reconnectedWin then
        local newWinId = reconnectedWin:id()
        print(prefix .. " [QUICK_VALIDATE] 槽位 " .. slotIndex .. " 重新连接成功，新winId=" .. tostring(newWinId))
        slot.win = reconnectedWin
        slot.winId = newWinId
        return slot
    end
    
    return nil
end

-- 初始化 bars（一次性创建，后续只更新内容）
function EdgeDock.initBars()
    -- 如果已经初始化过，先清理
    for _, bar in ipairs(EdgeDock.bars) do
        if bar.canvas then bar.canvas:delete() end
    end
    EdgeDock.bars = {}
    
    -- 获取当前模式的颜色
    local colors = EdgeDock.getCurrentColors()
    
    -- 获取当前屏幕
    local screen = EdgeDock.getCurrentScreen()
    -- 记录小条所在的屏幕
    EdgeDock.currentBarScreen = screen.x .. "," .. screen.y .. "," .. screen.w .. "," .. screen.h
    
    -- 创建 bars（初始为空槽位样式）
    for i = 1, EdgeDock.config.maxSlots do
        local x, y, w, h = EdgeDock.getSlotPosition(i, screen)
        local bar = hs.canvas.new({x = x, y = y, w = w, h = h})
        bar:level(hs.canvas.windowLevels.popUpMenu)
        -- 初始添加一个空槽位样式元素
        bar:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = colors.emptyBar,
            roundedRectRadii = {xRadius = 4, yRadius = 4},
        })
        bar:show()
        table.insert(EdgeDock.bars, {
            canvas = bar,
            slotIndex = i,
        })
    end
end

-- 刷新所有小条（只更新内容，不复用 canvas）
function EdgeDock.refreshBars()
    -- 如果 bars 还没初始化，先初始化
    if #EdgeDock.bars == 0 then
        EdgeDock.initBars()
        return
    end
    
    -- 获取当前模式的颜色
    local colors = EdgeDock.getCurrentColors()
    
    -- 获取当前屏幕
    local screen = EdgeDock.getCurrentScreen()
    
    for i = 1, EdgeDock.config.maxSlots do
        local bar = EdgeDock.bars[i]
        if not bar or not bar.canvas then goto continue end
        
        -- 更新小条位置（支持多显示器切换）
        local x, y, w, h = EdgeDock.getSlotPosition(i, screen)
        bar.canvas:frame({x = x, y = y, w = w, h = h})
        
        local slot = EdgeDock.slots[i]
        
        -- 安全地移除旧内容（使用 pcall 避免索引越界错误）
        pcall(function() bar.canvas:removeElement(1) end)
        
        if slot then
            -- 有窗口 - 应用图标颜色
            local iconColor = EdgeDock.getAppIconColor(slot.appName) or {alpha = 0.85, red = 0.5, green = 0.5, blue = 0.5}
            local brightColor = EdgeDock.brightenColor(iconColor, 1.25)
            
            bar.canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = brightColor,
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
        else
            -- 空槽位
            bar.canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = colors.emptyBar,
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
        end
        
        ::continue::
    end
end

-- 保存 Edge Dock 状态到文件
function EdgeDock.saveState()
    local prefix = EdgeDock.logPrefix()
    local state = {}
    print(prefix .. " [SAVE_STATE] 开始保存状态，当前有 " .. #EdgeDock.slots .. " 个槽位")
    
    -- 检查是否有窗口处于异常状态（winId=0 或无效）
    local hasInvalidWindow = false
    for i = 1, EdgeDock.config.maxSlots do
        local slot = EdgeDock.slots[i]
        if slot and slot.winId then
            local win = hs.window.get(slot.winId)
            -- 检测异常状态：winId=0 或窗口获取失败
            if slot.winId == 0 or not win then
                hasInvalidWindow = true
                print(prefix .. " [SAVE_STATE] 警告: 槽位 " .. i .. " (" .. slot.appName .. ") winId=" .. tostring(slot.winId) .. " 可能处于异常状态")
            end
        end
    end
    
    -- 如果有异常窗口且不是休眠前的保存，尝试读取之前的状态来保留正确的 winId
    local previousState = {}
    if hasInvalidWindow then
        local file = io.open(EDGEDOCK_STATE_FILE, "r")
        if file then
            local content = file:read("*all")
            file:close()
            local ok, decoded = pcall(function() return hs.json.decode(content) end)
            if ok and decoded then
                for _, item in ipairs(decoded) do
                    previousState[item.slotIndex] = item
                end
                print(prefix .. " [SAVE_STATE] 已读取之前保存的状态用于恢复异常槽位")
            end
        end
    end
    
    for i = 1, EdgeDock.config.maxSlots do
        local slot = EdgeDock.slots[i]
        if not slot then goto continue end
        
        -- 尝试获取窗口以更新标题和 ID
        local win = nil
        local winTitle = slot.winTitle  -- 默认使用已保存的标题
        local winId = slot.winId        -- 默认使用已保存的 ID
        
        if slot.winId and slot.winId ~= 0 then
            win = hs.window.get(slot.winId)
        end
        
        -- 如果 winId 获取失败，尝试通过应用名和标题重新查找
        if (not win or not win:isStandard()) and slot.appName then
            local app = hs.application.get(slot.appName)
            if app then
                for _, w in ipairs(app:allWindows()) do
                    if w:isStandard() then
                        -- 优先匹配保存的标题
                        if slot.winTitle and w:title() == slot.winTitle then
                            win = w
                            break
                        end
                        -- 备选：第一个标准窗口
                        if not win then
                            win = w
                        end
                    end
                end
            end
        end
        
        if win and win:isStandard() then
            local newWinId = win:id()
            local newWinTitle = win:title()
            -- 只有当新获取的 winId 有效时才更新（避免休眠时的异常状态覆盖正确状态）
            if newWinId and newWinId ~= 0 then
                winTitle = newWinTitle
                winId = newWinId
                print(prefix .. " [SAVE_STATE] 槽位 " .. i .. ": 更新 winId=" .. tostring(winId) .. ", title=[" .. tostring(winTitle) .. "]")
            else
                print(prefix .. " [SAVE_STATE] 槽位 " .. i .. ": 检测到无效 winId=" .. tostring(newWinId) .. "，保留原值 winId=" .. tostring(slot.winId))
                -- 尝试从之前保存的状态恢复（如果当前也是无效值）
                if (not winId or winId == 0) and previousState[i] and previousState[i].winId and previousState[i].winId ~= 0 then
                    winId = previousState[i].winId
                    winTitle = previousState[i].winTitle or slot.winTitle
                    print(prefix .. " [SAVE_STATE] 槽位 " .. i .. ": 从之前状态恢复 winId=" .. tostring(winId))
                end
            end
        else
            -- 窗口暂时不可访问，保留之前保存的 winId 和标题
            print(prefix .. " [SAVE_STATE] 槽位 " .. i .. ": 窗口暂时不可访问，保留原 winId=" .. tostring(winId) .. ", title=[" .. tostring(winTitle) .. "]")
            -- 如果当前 winId 无效，尝试从之前保存的状态恢复
            if (not winId or winId == 0) and previousState[i] and previousState[i].winId and previousState[i].winId ~= 0 then
                winId = previousState[i].winId
                winTitle = previousState[i].winTitle or slot.winTitle
                print(prefix .. " [SAVE_STATE] 槽位 " .. i .. ": 从之前状态恢复 winId=" .. tostring(winId))
            end
        end
        
        -- 最后检查：确保不会保存 winId=0 或 nil
        if not winId or winId == 0 then
            print(prefix .. " [SAVE_STATE] 警告: 槽位 " .. i .. " winId 仍然无效，使用占位符保存")
            -- 使用一个占位符，表示需要下次重新查找
            winId = -1  -- 使用 -1 表示需要重新连接
        end
        
        -- 只要槽位数据存在就保存（即使窗口暂时不可访问）
        -- 这在休眠前保存时特别重要
        table.insert(state, {
            slotIndex = i,
            appName = slot.appName,
            winTitle = winTitle,
            winId = winId,  -- 保存窗口 ID（虽然重启后会失效，但休眠/唤醒有用）
            screenId = slot.screenId,  -- 保存窗口原本所在的屏幕
            originalFrame = {
                x = slot.originalFrame.x,
                y = slot.originalFrame.y,
                w = slot.originalFrame.w,
                h = slot.originalFrame.h
            }
        })
        
        ::continue::
    end
    
    local file = io.open(EDGEDOCK_STATE_FILE, "w")
    if file then
        file:write(hs.json.encode(state))
        file:close()
        print(prefix .. " [SAVE_STATE] 完成: " .. #state .. " 个窗口已保存到 " .. EDGEDOCK_STATE_FILE)
        -- 打印详细保存信息
        for _, item in ipairs(state) do
            print(prefix .. " [SAVE_STATE]   槽位 " .. item.slotIndex .. ": app=" .. item.appName .. ", winId=" .. tostring(item.winId) .. ", title=[" .. tostring(item.winTitle) .. "]")
        end
    else
        print(prefix .. " [SAVE_STATE] 错误: 无法写入文件 " .. EDGEDOCK_STATE_FILE)
    end
end

-- 从文件恢复 Edge Dock 状态
function EdgeDock.restoreState()
    local prefix = EdgeDock.logPrefix()
    local file = io.open(EDGEDOCK_STATE_FILE, "r")
    if not file then
        print(prefix .. " [RESTORE_STATE] 没有找到状态文件: " .. EDGEDOCK_STATE_FILE)
        -- 标记启动完成
        EdgeDock._startupComplete = true
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local state = hs.json.decode(content)
    if not state or #state == 0 then
        print(prefix .. " [RESTORE_STATE] 状态文件为空")
        -- 标记启动完成
        EdgeDock._startupComplete = true
        return
    end
    
    print(prefix .. " [RESTORE_STATE] 开始恢复，文件中有 " .. #state .. " 个槽位记录")
    
    -- 延迟恢复，等待应用启动
    hs.timer.doAfter(1, function()
        -- 标记启动完成，此后 refreshBars 可以保存状态
        EdgeDock._startupComplete = true
        
        local restoredCount = 0
        
        for _, item in ipairs(state) do
            -- 查找应用
            print(prefix .. " [RESTORE_STATE] 处理槽位 " .. item.slotIndex .. ": app=" .. item.appName .. ", savedWinId=" .. tostring(item.winId) .. ", savedTitle=[" .. tostring(item.winTitle) .. "]")
            local app = hs.application.get(item.appName)
            if not app then
                -- 尝试启动应用
                print(prefix .. " [RESTORE_STATE]   尝试启动应用: " .. item.appName)
                hs.application.launchOrFocus(item.appName)
                -- 等待应用启动
                hs.timer.usleep(500000) -- 500ms
                app = hs.application.get(item.appName)
                if app then
                    print(prefix .. " [RESTORE_STATE]   应用启动成功: " .. item.appName)
                else
                    print(prefix .. " [RESTORE_STATE]   应用启动失败: " .. item.appName)
                end
            end
            
            -- 安全检查：确保 app 是有效的应用对象且有 allWindows 方法
            if app and type(app.allWindows) == "function" then
                -- 查找匹配的窗口
                local targetWin = nil
                local windows = app:allWindows()
                local candidates = {}
                
                -- 收集所有标准窗口
                for _, win in ipairs(windows) do
                    if win:isStandard() then
                        table.insert(candidates, {
                            win = win,
                            title = win:title() or "",
                            id = win:id()
                        })
                    end
                end
                
                -- 匹配策略1: 优先通过 winId 匹配（如果窗口仍然存在）
                if item.winId then
                    print(prefix .. " [RESTORE_STATE]   尝试winId匹配: " .. tostring(item.winId))
                    for _, cand in ipairs(candidates) do
                        print(prefix .. " [RESTORE_STATE]     检查候选: id=" .. tostring(cand.id) .. ", title=[" .. cand.title .. "]")
                        if cand.id == item.winId then
                            targetWin = cand.win
                            print(prefix .. " [RESTORE_STATE]   winId匹配成功: " .. item.appName .. ", id=" .. tostring(item.winId))
                            break
                        end
                    end
                    if not targetWin then
                        print(prefix .. " [RESTORE_STATE]   winId匹配失败: 没有候选窗口匹配 " .. tostring(item.winId))
                    end
                end
                
                -- 匹配策略2: 通过窗口标题匹配
                -- 只在标题唯一时匹配，避免连错窗口
                if not targetWin and item.winTitle and item.winTitle ~= "" then
                    local titleMatches = {}
                    for _, cand in ipairs(candidates) do
                        if cand.title == item.winTitle then
                            table.insert(titleMatches, cand)
                        end
                    end
                    
                    if #titleMatches == 1 then
                        targetWin = titleMatches[1].win
                        print("[EdgeDock] 恢复时标题唯一匹配: " .. item.appName .. ", title=" .. item.winTitle)
                    elseif #titleMatches > 1 then
                        -- 多个窗口有相同标题，无法确定哪个是原来的
                        -- 从文件恢复时也保持严格，避免连错窗口
                        print("[EdgeDock] 恢复失败: 有 " .. #titleMatches .. " 个窗口标题相同，无法确定原窗口: " .. item.winTitle)
                        -- 不设置 targetWin，跳过此槽位
                    end
                end
                
                -- 匹配策略3: 如果应用只有一个窗口且原窗口没有标题
                if not targetWin and (not item.winTitle or item.winTitle == "") then
                    if #candidates == 1 then
                        targetWin = candidates[1].win
                        print("[EdgeDock] 恢复时单窗口无标题匹配: " .. item.appName)
                    else
                        print("[EdgeDock] 恢复失败: 应用有 " .. #candidates .. " 个窗口且原窗口无标题，无法确定: " .. item.appName)
                        -- 不设置 targetWin，跳过此槽位
                    end
                end
                
                if targetWin then
                    print(prefix .. " [RESTORE_STATE]   槽位 " .. item.slotIndex .. " 恢复成功: " .. item.appName .. ", newWinId=" .. tostring(targetWin:id()))
                    -- 恢复 originalFrame
                    local frame = hs.geometry.rect(
                        item.originalFrame.x,
                        item.originalFrame.y,
                        item.originalFrame.w,
                        item.originalFrame.h
                    )
                    
                    -- 使用主屏幕（启动时小条在主屏幕）
                    local screen = hs.screen.mainScreen():frame()
                    
                    -- 获取槽位位置
                    local sx, sy, sw, sh = EdgeDock.getSlotPosition(item.slotIndex, screen)
                    
                    -- 计算窗口在槽位区域内的垂直居中位置
                    local winY = sy + (sh - frame.h) / 2
                    if winY < screen.y then
                        winY = screen.y
                    end
                    if winY + frame.h > screen.y + screen.h then
                        winY = screen.y + screen.h - frame.h
                    end
                    
                    -- 保存到槽位
                    EdgeDock.slots[item.slotIndex] = {
                        win = targetWin,
                        winId = targetWin:id(),
                        originalFrame = frame,
                        appName = item.appName,
                        isShowing = false,
                        hideTimer = nil,
                        slotY = sy,
                        slotHeight = sh,
                        winY = winY,
                        screenId = item.screenId,  -- 保留原屏幕信息
                    }
                    
                    -- 隐藏窗口到屏幕右下角
                    local hideX = screen.x + screen.w - 1
                    local hideY = screen.y + screen.h - 1
                    setWinFrame(targetWin, hs.geometry.rect(hideX, hideY, frame.w, frame.h))
                    
                    restoredCount = restoredCount + 1
                else
                    print(prefix .. " [RESTORE_STATE]   槽位 " .. item.slotIndex .. " 恢复失败: 未找到匹配窗口 (" .. item.appName .. ")")
                end
            elseif app then
                -- app 对象存在但不是有效的应用对象（例如可能是错误保存的 timer 对象）
                print(prefix .. " [RESTORE_STATE]   槽位 " .. item.slotIndex .. " 恢复失败: 应用对象无效 (" .. item.appName .. ")，清理槽位")
            else
                print(prefix .. " [RESTORE_STATE]   槽位 " .. item.slotIndex .. " 恢复失败: 应用未运行 (" .. item.appName .. ")")
            end
        end
        
        print(prefix .. " [RESTORE_STATE] 恢复完成: " .. restoredCount .. "/" .. #state .. " 个窗口已恢复")
        
        -- 刷新小条显示
        EdgeDock.refreshBars()
        
        if restoredCount > 0 then
            notify("Edge Dock", "已恢复 " .. restoredCount .. " 个窗口")
        end
    end)
end

-- 高亮小条（拖拽提示）
function EdgeDock.highlightBar(slotIndex, highlight)
    local bar = EdgeDock.bars[slotIndex]
    if not bar or not bar.canvas then return end
    
    local slot = EdgeDock.slots[slotIndex]
    -- 获取当前屏幕和槽位高度
    local screen = EdgeDock.getCurrentScreen()
    local barHeight = EdgeDock.getBarHeight(screen)
    local w, h = EdgeDock.config.barWidth, barHeight
    
    -- 更新小条位置
    local x, y = EdgeDock.getSlotPosition(slotIndex, screen)
    bar.canvas:frame({x = x, y = y, w = w, h = h})
    
    -- 获取当前模式的颜色
    local colors = EdgeDock.getCurrentColors()
    
    -- 清除并重绘
    bar.canvas:removeElement(1)
    bar.canvas:removeElement(1)
    
    if highlight then
        -- 高亮状态 - 使用当前模式的颜色
        bar.canvas:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = slot and colors.highlightOccupied or colors.highlightEmpty,
            roundedRectRadii = {xRadius = 4, yRadius = 4},
        })
    else
        -- 正常状态
        if slot then
            bar.canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {alpha = 0.5, red = 1, green = 1, blue = 1},
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
        else
            bar.canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = colors.emptyBar,
                roundedRectRadii = {xRadius = 4, yRadius = 4},
            })
        end
    end
    
    -- 文字
    bar.canvas:appendElements({
        type = "text",
        text = slot and string.upper(string.sub(slot.appName, 1, 1)) or tostring(slotIndex),
        textSize = 14,
        textColor = highlight and colors.highlightText
                            or (slot and colors.normalOccupiedText or colors.emptyText),
        frame = {x = 0, y = h/2 - 10, w = w, h = 20},
        textAlignment = "center",
    })
end

-- 清除所有高亮
function EdgeDock.clearAllHighlights()
    for i = 1, EdgeDock.config.maxSlots do
        EdgeDock.highlightBar(i, false)
    end
end

-- 将窗口停靠到槽位
-- @param win 窗口对象
-- @param slotIndex 槽位索引
-- @param options 可选参数表 {autoPeek = boolean}，autoPeek=true 表示如果鼠标在窗口上则自动显示
function EdgeDock.dockWindow(win, slotIndex, options)
    if not win or not win:isStandard() then return false end
    
    options = options or {}
    
    -- 如果窗口已经在其他槽位，先移除
    for i, slot in pairs(EdgeDock.slots) do
        if slot and slot.win:id() == win:id() then
            EdgeDock.undockWindow(i, false)
            break
        end
    end
    
    -- 如果槽位被占用，恢复那个窗口
    if EdgeDock.slots[slotIndex] then
        EdgeDock.undockWindow(slotIndex, false)
    end
    
    local app = win:application()
    local frame = win:frame()
    
    -- 使用当前鼠标所在的屏幕（支持多显示器）
    local screen = EdgeDock.getCurrentScreen()
    
    -- 获取槽位位置（基于当前屏幕）
    local sx, sy, sw, sh = EdgeDock.getSlotPosition(slotIndex, screen)
    
    -- 计算窗口在槽位区域内的垂直居中位置
    local winY = sy + (sh - frame.h) / 2
    
    -- 确保窗口不会超出屏幕顶部和底部
    if winY < screen.y then
        winY = screen.y
    end
    if winY + frame.h > screen.y + screen.h then
        winY = screen.y + screen.h - frame.h
    end
    
    print(string.format("[EdgeDock] 槽位%d: y=%.0f, h=%.0f, 窗口高=%.0f, winY=%.0f", slotIndex, sy, sh, frame.h, winY))
    
    -- 计算窗口显示位置（靠右）
    local showX = screen.x + screen.w - frame.w
    
    -- 检查鼠标是否当前在窗口区域内（用于 autoPeek 模式）
    local mousePos = hs.mouse.absolutePosition()
    local isMouseInWindow = mousePos.x >= frame.x and mousePos.x <= frame.x + frame.w
                            and mousePos.y >= frame.y and mousePos.y <= frame.y + frame.h
    
    -- 如果启用了 autoPeek 且鼠标在窗口上，则先显示窗口
    local shouldShow = options.autoPeek and isMouseInWindow
    
    EdgeDock.slots[slotIndex] = {
        win = win,
        winId = win:id(),
        winTitle = win:title() or "",  -- 保存窗口标题用于恢复时匹配
        originalFrame = frame,
        appName = app and app:name() or "?",
        isShowing = shouldShow,
        hideTimer = nil,
        slotY = sy,         -- 槽位顶部 Y
        slotHeight = sh,    -- 槽位高度
        winY = winY,        -- 窗口实际显示的 Y（垂直居中）
        screenId = win:screen():id(),  -- 记录窗口原本所在的屏幕
    }
    
    if shouldShow then
        -- 鼠标在窗口上，显示窗口到右侧
        setWinFrame(win, hs.geometry.rect(showX, winY, frame.w, frame.h))
        -- 缓存窗口 frame 供鼠标检测使用
        EdgeDock.slots[slotIndex].lastWinFrame = {x = showX, y = winY, w = frame.w, h = frame.h}
        -- 将窗口置顶
        win:raise()
        print(string.format("[EdgeDock] 槽位%d: 鼠标在窗口内，自动显示窗口", slotIndex))
    else
        -- 隐藏到当前屏幕右下角（只露出1x1像素，保持尺寸）
        local hideX = screen.x + screen.w - 1
        local hideY = screen.y + screen.h - 1
        setWinFrame(win, hs.geometry.rect(hideX, hideY, frame.w, frame.h))
    end
    
    EdgeDock.refreshBars()
    EdgeDock.saveState()  -- 保存状态
    notify("Edge Dock", "已停靠到槽位 " .. slotIndex)
    return true
end

-- 辅助函数：尝试重新连接窗口
-- 注意：此函数只在确认能找到原窗口时才返回窗口，否则返回 nil
function EdgeDock.tryReconnect(slot)
    local prefix = EdgeDock.logPrefix()
    
    if not slot or not slot.appName then 
        print(prefix .. " [RECONNECT] 失败: 槽位数据不完整")
        return nil 
    end
    
    print(prefix .. " [RECONNECT] 开始: app=" .. slot.appName .. ", savedWinId=" .. tostring(slot.winId) .. ", savedTitle=" .. tostring(slot.winTitle))
    
    -- 方法1: 通过 hs.application.get 查找
    local app = hs.application.get(slot.appName)
    if not app then
        -- 方法2: 遍历所有运行中的应用（通过 name()）
        for _, a in ipairs(hs.application.runningApplications()) do
            local name = a:name()
            if name and name == slot.appName then
                app = a
                break
            end
        end
    end
    
    -- 方法3: 尝试通过 bundle ID 查找
    if not app then
        local bundleMap = {
            ["WeChat"] = "com.tencent.xinWeChat",
            ["Music"] = "com.apple.Music",
            ["ChatGPT"] = "com.openai.chat",
            ["Safari"] = "com.apple.Safari",
            ["Chrome"] = "com.google.Chrome",
        }
        local bundleID = bundleMap[slot.appName]
        if bundleID then
            app = hs.application.get(bundleID)
        end
    end
    
    if not app then
        print(prefix .. " [RECONNECT] 失败: 找不到应用 " .. slot.appName)
        return nil
    end
    
    -- 获取应用的所有窗口
    local windows = app:allWindows()
    print(prefix .. " [RECONNECT] 应用 " .. slot.appName .. " 找到 " .. #windows .. " 个窗口")
    
    if #windows == 0 then
        print(prefix .. " [RECONNECT] 失败: 应用 " .. slot.appName .. " 没有窗口")
        return nil
    end
    
    local candidates = {}
    local nonStandardCandidates = {}
    
    -- 收集所有窗口（包括非标准窗口作为备选）
    for _, win in ipairs(windows) do
        local title = win:title() or ""
        local id = win:id()
        if win:isStandard() then
            table.insert(candidates, {win = win, title = title, id = id, standard = true})
            print(prefix .. " [RECONNECT]   标准窗口: id=" .. tostring(id) .. ", title=[" .. title .. "], matchWinId=" .. tostring(id == slot.winId))
        else
            table.insert(nonStandardCandidates, {win = win, title = title, id = id, standard = false})
            print(prefix .. " [RECONNECT]   非标准窗口: id=" .. tostring(id) .. ", title=[" .. title .. "], matchWinId=" .. tostring(id == slot.winId))
        end
    end
    
    -- 休眠后特殊处理：某些应用（如微信）的窗口可能变成非标准窗口且 id=0
    -- 但之后会自动恢复，此时应该优先尝试通过标题匹配
    if #candidates == 0 and #nonStandardCandidates > 0 then
        print(prefix .. " [RECONNECT] 警告: 应用 " .. slot.appName .. " 没有标准窗口，可能是休眠后的临时状态")
        -- 休眠后，如果保存了标题，优先尝试通过标题在非标准窗口中匹配
        -- 这适用于窗口暂时变成非标准但之后会恢复的情况
        if slot.winTitle and slot.winTitle ~= "" then
            for _, cand in ipairs(nonStandardCandidates) do
                -- 微信等特殊处理：标题可能从 "Weixin" 变成 "WeChat"
                if cand.title == slot.winTitle then
                    print(prefix .. " [RECONNECT] 在非标准窗口中找到标题匹配: [" .. cand.title .. "]")
                    -- 不立即返回，记录这个候选，等待窗口恢复为标准窗口
                end
            end
        end
    end
    
    -- 如果没有标准窗口，尝试使用非标准窗口（休眠后某些窗口可能暂时变成非标准）
    if #candidates == 0 then
        print(prefix .. " [RECONNECT] 警告: 应用 " .. slot.appName .. " 没有标准窗口，尝试使用非标准窗口")
        if #nonStandardCandidates > 0 then
            -- 优先使用有标题且 id ~= 0 的非标准窗口（更可能是有效窗口）
            for _, cand in ipairs(nonStandardCandidates) do
                if cand.title ~= "" and cand.id and cand.id ~= 0 then
                    table.insert(candidates, cand)
                end
            end
            -- 其次使用有标题的（无论 id 是什么）
            if #candidates == 0 then
                for _, cand in ipairs(nonStandardCandidates) do
                    if cand.title ~= "" then
                        table.insert(candidates, cand)
                    end
                end
            end
            -- 如果没有有标题的，全部加入
            if #candidates == 0 then
                candidates = nonStandardCandidates
            end
        end
    end
    
    if #candidates == 0 then
        print(prefix .. " [RECONNECT] 失败: 应用 " .. slot.appName .. " 没有任何可用窗口")
        return nil
    end
    
    local targetWin = nil
    
    -- 匹配策略1: 优先通过 winId 匹配（窗口仍然存在且 ID 未变）
    -- 这是休眠/唤醒后最常见的情况
    -- 注意：winId=-1 是占位符，表示需要重新查找
    if slot.winId and slot.winId ~= 0 and slot.winId ~= -1 then
        for _, cand in ipairs(candidates) do
            if cand.id == slot.winId then
                targetWin = cand.win
                print(prefix .. " [RECONNECT] 成功(winId匹配): " .. slot.appName .. ", id=" .. tostring(slot.winId))
                break
            end
        end
        if not targetWin then
            print(prefix .. " [RECONNECT] winId=" .. tostring(slot.winId) .. " 没有匹配到任何候选窗口")
        end
    else
        print(prefix .. " [RECONNECT] 没有有效的 savedWinId (" .. tostring(slot.winId) .. ")，跳过 winId 匹配")
    end
    
    -- 匹配策略2: 通过窗口标题匹配（ID 变化但标题相同）
    -- 只在 winId 匹配失败且标题不为空时尝试
    if not targetWin and slot.winTitle and slot.winTitle ~= "" then
        local titleMatches = {}
        for _, cand in ipairs(candidates) do
            -- 完全匹配
            if cand.title == slot.winTitle then
                table.insert(titleMatches, cand)
            end
        end
        
        if #titleMatches == 1 then
            -- 只有一个匹配，认为是同一个窗口（标题唯一）
            targetWin = titleMatches[1].win
            print(prefix .. " [RECONNECT] 成功(标题唯一匹配): " .. slot.appName .. ", title=[" .. slot.winTitle .. "]")
        elseif #titleMatches > 1 then
            -- 多个窗口有相同标题，无法确定哪个是原来的
            -- 宁可不连接，也不要连错窗口
            print(prefix .. " [RECONNECT] 失败: 有 " .. #titleMatches .. " 个窗口标题相同，无法确定原窗口: [" .. slot.winTitle .. "]")
            return nil
        else
            -- 没有完全匹配，尝试部分匹配（休眠后标题可能变化，如 Weixin -> WeChat）
            print(prefix .. " [RECONNECT] 完全匹配失败，尝试部分匹配 savedTitle=[" .. slot.winTitle .. "]")
            local partialMatches = {}
            for _, cand in ipairs(candidates) do
                -- 部分匹配：保存的标题包含在候选标题中，或候选标题包含在保存的标题中
                -- 或者两者有共同的前缀/子串（至少3个字符）
                local savedLower = string.lower(slot.winTitle)
                local candLower = string.lower(cand.title)
                local isMatch = false
                
                -- 互相包含
                if string.find(candLower, savedLower, 1, true) or 
                   string.find(savedLower, candLower, 1, true) then
                    isMatch = true
                end
                
                -- 或者应用名匹配（微信的特殊情况：Weixin/WeChat 都包含 Wei）
                if not isMatch and slot.appName then
                    local appLower = string.lower(slot.appName)
                    if string.find(candLower, appLower, 1, true) or 
                       string.find(appLower, candLower, 1, true) then
                        isMatch = true
                    end
                end
                
                if isMatch then
                    table.insert(partialMatches, cand)
                end
            end
            
            if #partialMatches == 1 then
                targetWin = partialMatches[1].win
                print(prefix .. " [RECONNECT] 成功(标题部分匹配): " .. slot.appName .. ", saved=[" .. slot.winTitle .. "], found=[" .. partialMatches[1].title .. "]")
            elseif #partialMatches > 1 then
                print(prefix .. " [RECONNECT] 部分匹配也有多个结果，放弃匹配")
            else
                print(prefix .. " [RECONNECT] 标题匹配失败: 没有窗口标题匹配 [" .. slot.winTitle .. "]")
            end
        end
    elseif not targetWin then
        print(prefix .. " [RECONNECT] 跳过标题匹配: savedTitle=" .. tostring(slot.winTitle))
    end
    
    -- 匹配策略3: 如果应用只有一个窗口且原窗口没有标题
    -- 这种情况比较少见，需要谨慎处理
    if not targetWin and (not slot.winTitle or slot.winTitle == "") then
        if #candidates == 1 then
            targetWin = candidates[1].win
            print(prefix .. " [RECONNECT] 成功(单窗口无标题): " .. slot.appName)
        else
            print(prefix .. " [RECONNECT] 失败: 应用有 " .. #candidates .. " 个窗口且原窗口无标题，无法确定")
            return nil
        end
    end
    
    if targetWin then
        local newId = targetWin:id()
        slot.win = targetWin
        slot.winId = newId
        print(prefix .. " [RECONNECT] 最终成功: app=" .. slot.appName .. ", newWinId=" .. tostring(newId))
        return targetWin
    else
        print(prefix .. " [RECONNECT] 最终失败: app=" .. slot.appName .. ", savedTitle=" .. tostring(slot.winTitle))
    end
    
    return nil
end

-- 检查窗口是否处于居中状态
function EdgeDock.isWindowCentered(win, screen)
    if not win then return false end
    local frame = win:frame()
    if not frame then return false end
    
    -- 计算可用区域（考虑边距）
    local area = getUsableArea(screen, win)
    
    -- 计算可用区域中心位置（允许一定误差）
    local centerX = area.x + (area.w - frame.w) / 2
    local centerY = area.y + (area.h - frame.h) / 2
    local tolerance = 20  -- 误差容忍度（像素）
    
    -- 检查窗口是否在可用区域中心附近
    local isCenteredX = math.abs(frame.x - centerX) < tolerance
    local isCenteredY = math.abs(frame.y - centerY) < tolerance
    
    return isCenteredX and isCenteredY
end

-- 显示窗口（滑出到右边，保持大小，在槽位内垂直居中）
function EdgeDock.peekWindow(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return end
    
    -- 如果窗口已经显示且处于居中暂停状态，不再重新定位（避免鼠标跨屏幕时打断居中状态）
    if slot.isShowing and slot.centeredPaused then
        return
    end
    
    -- 快速获取窗口对象（不做耗时的验证）
    local win = slot.win
    if not win and slot.winId then
        win = hs.window.get(slot.winId)
    end
    
    if not win then
        -- 窗口暂时不可用，不处理
        return
    end
    
    -- 更新引用
    slot.win = win
    
    print(string.format("[EdgeDock] 显示槽位%d, winY=%.0f", slotIndex, slot.winY))
    
    -- 先隐藏其他所有正在显示的窗口（单选模式）
    for i = 1, EdgeDock.config.maxSlots do
        if i ~= slotIndex then
            local otherSlot = EdgeDock.slots[i]
            if otherSlot and otherSlot.isShowing then
                EdgeDock.hideWindow(i)
            end
            -- 取消其他窗口的隐藏计时器
            if otherSlot and otherSlot.hideTimer then
                otherSlot.hideTimer:stop()
                otherSlot.hideTimer = nil
            end
        end
    end
    
    -- 取消当前槽位的隐藏计时器
    if slot.hideTimer then
        slot.hideTimer:stop()
        slot.hideTimer = nil
    end
    
    if not slot.isShowing then
        -- 使用当前鼠标所在的屏幕（支持多显示器）
        local screen = EdgeDock.getCurrentScreen()
        
        -- 更新槽位位置（可能在不同的显示器上）
        local sx, sy, sw, sh = EdgeDock.getSlotPosition(slotIndex, screen)
        slot.slotY = sy
        slot.slotHeight = sh
        
        -- 重新计算窗口在槽位区域内的垂直居中位置
        local winY = sy + (sh - slot.originalFrame.h) / 2
        if winY < screen.y then
            winY = screen.y
        end
        if winY + slot.originalFrame.h > screen.y + screen.h then
            winY = screen.y + screen.h - slot.originalFrame.h
        end
        slot.winY = winY
        
        -- 使用 originalFrame 的尺寸（窗口在屏幕外时 win:frame() 可能返回错误值）
        local winW = slot.originalFrame.w
        local winH = slot.originalFrame.h
        -- 靠右显示，保持大小不变，y 坐标垂直居中于槽位
        local showX = screen.x + screen.w - winW
        
        setWinFrame(win, hs.geometry.rect(showX, slot.winY, winW, winH))
        slot.isShowing = true
        
        -- 缓存窗口 frame 供鼠标移动检测使用
        slot.lastWinFrame = {x = showX, y = slot.winY, w = winW, h = winH}
        
        -- 重置居中暂停状态
        slot.centeredPaused = false
        slot.wasMouseInWindow = false
        
        -- 将窗口置顶并激活（最前面）
        win:raise()
        win:focus()
        -- 稍微延迟再次确保置顶
        hs.timer.doAfter(0.05, function()
            if win and win:isStandard() then
                win:raise()
                win:focus()
            end
        end)
    end
end

-- 隐藏窗口（移到右下角，只露出1x1像素）
function EdgeDock.hideWindow(slotIndex)
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return end
    
    -- 尝试获取窗口对象
    local win = slot.win
    if not win then
        if slot.winId then
            win = hs.window.get(slot.winId)
        end
    end
    
    -- 如果找到窗口，移动它
    if win then
        -- 使用当前鼠标所在的屏幕（支持多显示器）
        local screen = EdgeDock.getCurrentScreen()
        -- 移到屏幕右下角（只露出1x1像素，保持原尺寸）
        local hideX = screen.x + screen.w - 1
        local hideY = screen.y + screen.h - 1
        setWinFrame(win, hs.geometry.rect(hideX, hideY, slot.originalFrame.w, slot.originalFrame.h))
        slot.win = win
    end
    
    slot.isShowing = false
    slot.centeredPaused = false
    slot.wasMouseInWindow = false
end

-- 完全恢复窗口
function EdgeDock.undockWindow(slotIndex, focus)
    focus = focus ~= false  -- 默认 true
    local slot = EdgeDock.slots[slotIndex]
    if not slot then return end
    
    if slot.hideTimer then
        slot.hideTimer:stop()
    end
    
    -- 尝试获取窗口
    local win = slot.win
    if not win and slot.winId then
        win = hs.window.get(slot.winId)
    end
    
    if win then
        setWinFrame(win, slot.originalFrame)
        if focus then win:focus() end
    else
        print("[EdgeDock] 恢复时窗口已失效: " .. (slot.appName or "unknown"))
    end
    
    EdgeDock.slots[slotIndex] = nil
    EdgeDock.refreshBars()
    EdgeDock.saveState()
    
    if focus then
        notify("Edge Dock", "窗口已恢复")
    end
end

-- 鼠标移动监听（仅用于悬停检测，不拦截事件）
EdgeDock.mouseWatcher = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local mousePos = e:location()
    -- 使用当前鼠标所在的屏幕（支持多显示器）
    local screen = EdgeDock.getCurrentScreen()
    
    -- 检测屏幕变化，如果鼠标移动到了不同屏幕，重新定位小条
    if EdgeDock.currentBarScreen then
        local screenId = screen.x .. "," .. screen.y .. "," .. screen.w .. "," .. screen.h
        if EdgeDock.currentBarScreen ~= screenId then
            -- 屏幕变化，重新定位小条和遮罩
            EdgeDock.currentBarScreen = screenId
            EdgeDock.refreshBars()
            EdgeDock.refreshMask()
            -- 如果有正在显示的窗口，先隐藏它（避免窗口留在旧屏幕）
            -- 但处于居中暂停状态的窗口保持显示
            for i = 1, EdgeDock.config.maxSlots do
                local slot = EdgeDock.slots[i]
                if slot and slot.isShowing and not slot.centeredPaused then
                    EdgeDock.hideWindow(i)
                end
            end
        end
    else
        -- 初始化当前屏幕
        EdgeDock.currentBarScreen = screen.x .. "," .. screen.y .. "," .. screen.w .. "," .. screen.h
    end
    
    local rightEdge = screen.x + screen.w
    
    -- 悬停检测
    for i = 1, EdgeDock.config.maxSlots do
        local slot = EdgeDock.slots[i]
        if not slot then goto continue end
        
        local sx, sy, sw, sh = EdgeDock.getSlotPosition(i, screen)
        -- 扩大检测区域：屏幕右边缘附近都能触发
        local r = EdgeDock.config.triggerRange
        local inSlotArea = mousePos.x >= sx - r.leftExtend and mousePos.x <= rightEdge + r.rightExtend
                          and mousePos.y >= sy - r.topExtend and mousePos.y <= sy + sh + r.bottomExtend
        
        -- 检测是否在槽位区域 - 显示窗口
        if inSlotArea and not slot.isShowing then
            EdgeDock.peekWindow(i)
        end
        
        -- 检测是否离开窗口区域 - 启动隐藏计时器
        if slot.isShowing then
            local inWindow = EdgeDock.isPointInWindow(mousePos.x, mousePos.y, slot.win, slot)
            -- 扩大槽位检测区域（使用配置参数）
            local r = EdgeDock.config.triggerRange
            local inSlot = mousePos.x >= sx - r.leftExtend - 10 and mousePos.x <= rightEdge + r.rightExtend + 5
                          and mousePos.y >= sy - r.topExtend - 5 and mousePos.y <= sy + sh + r.bottomExtend + 5
            
            -- 检测窗口是否被居中（用户手动居中后需要暂停移出检测）
            if not slot.centeredPaused then
                local win = slot.win
                if win then
                    local currentFrame = win:frame()
                    -- 如果窗口不在贴边位置（靠右），可能被居中了
                    local showX = screen.x + screen.w - slot.originalFrame.w
                    if math.abs(currentFrame.x - showX) > 100 then
                        -- 窗口位置偏离贴边位置超过100像素，可能是被居中了
                        -- 检查是否确实在屏幕中央附近
                        if EdgeDock.isWindowCentered(win, screen) then
                            slot.centeredPaused = true
                            slot.wasMouseInWindow = false  -- 重置鼠标状态
                            print(string.format("[EdgeDock] 槽位%d: 检测到窗口被居中，暂停移出检测", i))
                        end
                    end
                end
            end
            
            -- 检测鼠标是否进入窗口（从外部移到内部）
            local wasInWindow = slot.wasMouseInWindow or false
            if inWindow and not wasInWindow then
                -- 鼠标进入窗口：如果之前是居中暂停状态，且窗口是贴边显示（非居中），才恢复正常检测
                -- 窗口被居中后，不应该因为鼠标进入而恢复检测，否则跨屏幕回来时又会缩回去
                if slot.centeredPaused then
                    local win = slot.win
                    if win then
                        local currentFrame = win:frame()
                        -- 检查窗口是否在贴边位置（靠右）
                        local showX = screen.x + screen.w - slot.originalFrame.w
                        -- 如果窗口在贴边位置（非居中），才恢复检测
                        if math.abs(currentFrame.x - showX) <= 100 then
                            slot.centeredPaused = false
                            print(string.format("[EdgeDock] 槽位%d: 鼠标进入贴边窗口，恢复移出检测", i))
                        end
                    end
                end
            end
            slot.wasMouseInWindow = inWindow
            
            -- 既不在窗口内，也不在槽位上
            if not inWindow and not inSlot then
                -- 如果处于居中暂停状态，不隐藏窗口
                if slot.centeredPaused then
                    -- 居中暂停中，忽略移出检测
                    if slot.hideTimer then
                        slot.hideTimer:stop()
                        slot.hideTimer = nil
                    end
                else
                    -- 正常检测：启动隐藏计时器
                    if not slot.hideTimer then
                        slot.hideTimer = hs.timer.doAfter(EdgeDock.config.hideDelay, function()
                            EdgeDock.hideWindow(i)
                            slot.hideTimer = nil
                        end)
                    end
                end
            else
                -- 还在窗口或槽位上，取消隐藏计时器
                if slot.hideTimer then
                    slot.hideTimer:stop()
                    slot.hideTimer = nil
                end
            end
        end
        
        ::continue::
    end
    
    return false  -- 不拦截事件
end)

-- 应用关闭检测
EdgeDock.appWatcher = hs.application.watcher.new(function(appName, eventType, appObj)
    local prefix = EdgeDock.logPrefix()
    if eventType == hs.application.watcher.terminated then
        print(prefix .. " [APP_WATCHER] 收到应用关闭事件: " .. (appName or "unknown") .. ", 延迟5秒后检查...")
        -- 增加延迟到 5 秒，给系统更多恢复时间，避免误判休眠唤醒为应用关闭
        hs.timer.doAfter(5, function()
            -- 检查所有槽位
            local changed = false
            print(prefix .. " [APP_WATCHER] 开始检查槽位 (触发应用: " .. (appName or "unknown") .. ")")
            for i = 1, EdgeDock.config.maxSlots do
                local slot = EdgeDock.slots[i]
                if slot then
                    if slot.appName == appName then
                        print(prefix .. " [APP_WATCHER] 检查槽位 " .. i .. " (应用: " .. slot.appName .. ", winId=" .. tostring(slot.winId) .. ")")
                        -- 使用 validateSlot 来验证和重新连接
                        local validSlot = EdgeDock.validateSlot(i)
                        if not validSlot then
                            print(prefix .. " [APP_WATCHER] 槽位 " .. i .. " 确认关闭，清理槽位")
                            EdgeDock.slots[i] = nil
                            changed = true
                        else
                            print(prefix .. " [APP_WATCHER] 槽位 " .. i .. " 验证通过（可能是误报）")
                        end
                    end
                end
            end
            if changed then
                print(prefix .. " [APP_WATCHER] 有槽位被清理，刷新界面并保存状态")
                EdgeDock.refreshBars()
                EdgeDock.saveState()
            else
                print(prefix .. " [APP_WATCHER] 没有槽位需要清理")
            end
        end)
    end
end)

-- 屏幕变化时重新定位
EdgeDock.screenWatcher = hs.screen.watcher.new(function()
    hs.timer.doAfter(0.3, function()
        EdgeDock.refreshBars()
        EdgeDock.refreshMask()
    end)
end)

-- 系统休眠/唤醒监听
EdgeDock.caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
    local prefix = EdgeDock.logPrefix()
    if eventType == hs.caffeinate.watcher.systemDidWake then
        print(prefix .. " [CAFFEINATE] ====== 系统唤醒 ======")
        print(prefix .. " [CAFFEINATE] 当前槽位状态:")
        for i = 1, EdgeDock.config.maxSlots do
            local slot = EdgeDock.slots[i]
            if slot then
                print(prefix .. " [CAFFEINATE]   槽位 " .. i .. ": app=" .. slot.appName .. ", winId=" .. tostring(slot.winId) .. ", isShowing=" .. tostring(slot.isShowing))
            else
                print(prefix .. " [CAFFEINATE]   槽位 " .. i .. ": 空")
            end
        end
        -- 唤醒后先暂停验证定时器，避免在窗口恢复过程中误判
        if EdgeDock.validationTimer then
            print(prefix .. " [CAFFEINATE] 暂停验证定时器，等待窗口恢复...")
            EdgeDock.validationTimer:stop()
        end
        -- 延迟 5 秒后恢复验证定时器并验证槽位
        print(prefix .. " [CAFFEINATE] 5秒后开始验证槽位...")
        hs.timer.doAfter(5, function()
            print(prefix .. " [CAFFEINATE] 开始验证槽位...")
            -- 唤醒后强制验证所有槽位，优先尝试重新连接
            local reconnectedCount = 0
            local failedSlots = {}
            for i = 1, EdgeDock.config.maxSlots do
                local slot = EdgeDock.slots[i]
                if slot then
                    print(prefix .. " [CAFFEINATE] 验证槽位 " .. i .. " (" .. slot.appName .. ")...")
                    local validSlot = EdgeDock.validateSlot(i)
                    if validSlot then
                        reconnectedCount = reconnectedCount + 1
                        print(prefix .. " [CAFFEINATE] 槽位 " .. i .. " 验证成功，新winId=" .. tostring(validSlot.winId))
                        -- 确保窗口还在隐藏位置
                        if slot.isShowing then
                            print(prefix .. " [CAFFEINATE] 槽位 " .. i .. " 之前在显示状态，重新隐藏")
                            EdgeDock.hideWindow(i)
                        end
                    else
                        print(prefix .. " [CAFFEINATE] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 无法重新连接，将被清理")
                        table.insert(failedSlots, i .. "(" .. (slot.appName or "?") .. ")")
                        EdgeDock.slots[i] = nil
                    end
                else
                    print(prefix .. " [CAFFEINATE] 槽位 " .. i .. " 为空，跳过")
                end
            end
            EdgeDock.refreshBars()
            EdgeDock.refreshMask()
            EdgeDock.saveState()
            -- 恢复验证定时器
            if EdgeDock.validationTimer then
                print(prefix .. " [CAFFEINATE] 恢复验证定时器")
                EdgeDock.validationTimer:start()
            end
            print(prefix .. " [CAFFEINATE] ====== 唤醒恢复完成 ======")
            print(prefix .. " [CAFFEINATE] 结果: " .. reconnectedCount .. " 个成功, 失败: " .. table.concat(failedSlots, ", "))
        end)
    elseif eventType == hs.caffeinate.watcher.systemWillSleep then
        print(prefix .. " [CAFFEINATE] ====== 系统即将休眠 ======")
        print(prefix .. " [CAFFEINATE] 当前槽位状态:")
        for i = 1, EdgeDock.config.maxSlots do
            local slot = EdgeDock.slots[i]
            if slot then
                print(prefix .. " [CAFFEINATE]   槽位 " .. i .. ": app=" .. slot.appName .. ", winId=" .. tostring(slot.winId) .. ", title=[" .. tostring(slot.winTitle) .. "]")
            else
                print(prefix .. " [CAFFEINATE]   槽位 " .. i .. ": 空")
            end
        end
        -- 休眠前暂停验证定时器，避免休眠期间误判
        if EdgeDock.validationTimer then
            print(prefix .. " [CAFFEINATE] 暂停验证定时器")
            EdgeDock.validationTimer:stop()
        end
        EdgeDock.saveState()
        print(prefix .. " [CAFFEINATE] ====== 休眠准备完成 ======")
    elseif eventType == hs.caffeinate.watcher.screensDidWake then
        -- 屏幕唤醒时恢复验证定时器（如果还没启动）
        if EdgeDock.validationTimer and not EdgeDock.validationTimer:running() then
            print(prefix .. " [CAFFEINATE] 屏幕唤醒，恢复验证定时器")
            EdgeDock.validationTimer:start()
        end
    end
end)

-- 外观模式变化监听
EdgeDock.appearanceWatcher = hs.distributednotifications.new(function()
    print("[EdgeDock] 外观模式变化，刷新颜色")
    -- 清除颜色缓存，让应用颜色根据新模式重新计算
    EdgeDock.appColorCache = {}
    hs.timer.doAfter(0.5, function()
        EdgeDock.refreshBars()
        EdgeDock.refreshMask()
    end)
end, "AppleInterfaceThemeChangedNotification")


-- 恢复所有可能被之前脚本实例藏起来的窗口
function EdgeDock.recoverHiddenWindows()
    -- 获取所有屏幕
    local allScreens = hs.screen.allScreens()
    
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isStandard() then
            local frame = win:frame()
            local winScreen = win:screen()
            local winScreenFrame = winScreen and winScreen:frame()
            
            if winScreenFrame then
                local rightEdge = winScreenFrame.x + winScreenFrame.w
                -- 如果窗口在屏幕右侧外（被藏起来了），把它拉回来
                -- 扩大检测范围：从 rightEdge-50 到 rightEdge+100，支持 peekWidth=0 的情况
                if frame.x >= rightEdge - 50 and frame.x <= rightEdge + 100 then
                    -- 窗口被藏在右边，恢复到屏幕内（居中），保持原始尺寸
                    local newX = winScreenFrame.x + (winScreenFrame.w - frame.w) / 2
                    local newY = winScreenFrame.y + (winScreenFrame.h - frame.h) / 2
                    setWinFrame(win, hs.geometry.rect(newX, newY, frame.w, frame.h))
                    print("[EdgeDock] 恢复窗口: " .. (win:application():name() or "Unknown"))
                end
            end
        end
    end
end

-- 启动
function EdgeDock.start()
    -- 先恢复可能被之前实例藏起来的窗口（这些不在状态文件中）
    EdgeDock.recoverHiddenWindows()
    
    -- 启动监听器（在恢复状态前启动，以便恢复后的窗口能被正确处理）
    EdgeDock.mouseWatcher:start()
    EdgeDock.appWatcher:start()
    EdgeDock.screenWatcher:start()
    EdgeDock.caffeinateWatcher:start()
    EdgeDock.appearanceWatcher:start()
    
    -- 启动定期验证定时器（每 5 秒验证一次槽位，清理已关闭的窗口）
    -- 使用失败计数器：连续 3 次验证失败才清理，避免窗口暂时不可用时被误清理
    EdgeDock.validationTimer = hs.timer.doEvery(5, function()
        local prefix = EdgeDock.logPrefix()
        local changed = false
        
        -- 检查系统是否正在休眠或锁屏（通过检查电源状态和屏幕状态）
        -- 如果正在休眠/唤醒/锁屏过程中，跳过本次验证
        local isSystemAwake = true
        
        -- 方法1: 检查电源状态
        local powerHandle = io.popen("pmset -g systemstate 2>/dev/null | grep -i 'sleep' | head -1")
        if powerHandle then
            local powerState = powerHandle:read("*l") or ""
            powerHandle:close()
            if powerState ~= "" and string.find(string.lower(powerState), "sleep") then
                print(prefix .. " [VALIDATION_TIMER] 系统正在休眠（systemstate），跳过验证")
                isSystemAwake = false
            end
        end
        
        -- 方法2: 检查屏幕是否锁定（通过会话状态）
        if isSystemAwake then
            local sessionHandle = io.popen("ls -la /tmp/com.apple.ScreenSharing* 2>/dev/null | wc -l")
            if sessionHandle then
                local count = tonumber(sessionHandle:read("*l")) or 0
                sessionHandle:close()
                -- 这个方法不太可靠，仅作为参考
            end
        end
        
        -- 方法3: 检查系统是否刚唤醒（通过检查 CGSession 状态）
        if isSystemAwake then
            local cgHandle = io.popen("ps aux | grep -i 'coregraphics' | grep -v grep | wc -l")
            if cgHandle then
                cgHandle:close()  -- 这个方法也不太准确
            end
        end
        
        -- 如果验证定时器被显式暂停（如休眠期间），也跳过
        if not isSystemAwake then
            return
        end
        
        -- 额外检查：如果所有窗口都是非标准且 id=0，可能是系统正在恢复中
        local allAbnormal = true
        local hasAnyWindow = false
        for i = 1, EdgeDock.config.maxSlots do
            local slot = EdgeDock.slots[i]
            if slot and slot.winId and slot.winId ~= 0 then
                local win = hs.window.get(slot.winId)
                if win then
                    hasAnyWindow = true
                    if win:isStandard() then
                        allAbnormal = false
                        break
                    end
                end
            end
        end
        if hasAnyWindow and allAbnormal then
            print(prefix .. " [VALIDATION_TIMER] 检测到所有窗口都是非标准状态，系统可能正在恢复，跳过验证")
            return
        end
        
        for i = 1, EdgeDock.config.maxSlots do
            local slot = EdgeDock.slots[i]
            if slot then
                -- 先检查应用是否还在运行
                local app = hs.application.get(slot.appName)
                if not app then
                    -- 应用已关闭，尝试通过 bundle ID 查找
                    local bundleMap = {
                        ["WeChat"] = "com.tencent.xinWeChat",
                        ["Music"] = "com.apple.Music",
                        ["ChatGPT"] = "com.openai.chat",
                        ["Safari"] = "com.apple.Safari",
                        ["Chrome"] = "com.google.Chrome",
                    }
                    local bundleID = bundleMap[slot.appName]
                    if bundleID then
                        app = hs.application.get(bundleID)
                    end
                end
                
                if not app then
                    -- 应用确实已关闭，直接清理槽位
                    print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 应用已关闭，清理槽位")
                    EdgeDock.slots[i] = nil
                    changed = true
                    goto continue_slot
                end
                
                -- 应用还在运行，使用 validateSlot 进行验证
                local validSlot = EdgeDock.validateSlot(i)
                if not validSlot then
                    -- 验证失败，检查是否是窗口异常状态（如 winId=0 或窗口非标准）
                    -- 如果是异常状态，不增加失败计数，等待窗口恢复
                    local isAbnormalState = false
                    
                    -- 检查1: winId 为 0 或 -1（无效值）
                    if not slot.winId or slot.winId == 0 or slot.winId == -1 then
                        isAbnormalState = true
                        print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") winId=" .. tostring(slot.winId) .. " 无效，可能是休眠后的临时状态，跳过")
                    else
                        -- 检查2: 窗口存在但变成非标准窗口（休眠后常见）
                        local win = hs.window.get(slot.winId)
                        if win and not win:isStandard() then
                            isAbnormalState = true
                            print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 窗口暂时为非标准状态，跳过")
                        elseif not win then
                            -- 检查3: 窗口获取失败但应用还在运行（可能是暂时的）
                            -- 检查应用是否还在运行
                            local app = hs.application.get(slot.appName)
                            if app then
                                -- 应用还在，但窗口获取不到，可能是暂时的
                                isAbnormalState = true
                                print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 应用还在但窗口获取失败，可能是临时状态，跳过")
                            end
                        end
                    end
                    
                    if not isAbnormalState then
                        -- 真正的验证失败，增加失败计数
                        slot.failCount = (slot.failCount or 0) + 1
                        print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 验证失败，失败次数=" .. slot.failCount)
                        
                        -- 连续 3 次失败才清理（给窗口恢复留出时间）
                        if slot.failCount >= 3 then
                            print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 连续3次验证失败，清理槽位")
                            EdgeDock.slots[i] = nil
                            changed = true
                        end
                    end
                else
                    -- 验证成功，重置失败计数
                    if slot.failCount and slot.failCount > 0 then
                        print(prefix .. " [VALIDATION_TIMER] 槽位 " .. i .. " (" .. (slot.appName or "unknown") .. ") 验证恢复，重置失败计数")
                        slot.failCount = 0
                    end
                end
                
                ::continue_slot::
            end
        end
        if changed then
            print(prefix .. " [VALIDATION_TIMER] 有槽位被清理，刷新界面并保存状态")
            EdgeDock.refreshBars()
            EdgeDock.saveState()
        end
    end)
    
    -- 从文件恢复状态（必须在 refreshBars 之前，否则空状态会覆盖文件）
    EdgeDock.restoreState()
    
    -- 初始化小条和遮罩（在恢复状态后，这样小条能正确显示停靠的窗口）
    EdgeDock.refreshBars()
    EdgeDock.refreshMask()
end

-- 停止
function EdgeDock.stop()
    for i = 1, EdgeDock.config.maxSlots do
        if EdgeDock.slots[i] then
            EdgeDock.undockWindow(i)
        end
    end
    if EdgeDock.mask then
        EdgeDock.mask:delete()
        EdgeDock.mask = nil
    end
    EdgeDock.mouseWatcher:stop()
    EdgeDock.appWatcher:stop()
    EdgeDock.screenWatcher:stop()
    EdgeDock.caffeinateWatcher:stop()
    EdgeDock.appearanceWatcher:stop()
    if EdgeDock.validationTimer then
        EdgeDock.validationTimer:stop()
        EdgeDock.validationTimer = nil
    end
    -- 停止自动停靠监听器
    if EdgeDock.autoDockWatcher then
        EdgeDock.autoDockWatcher:stop()
        EdgeDock.autoDockWatcher = nil
    end
end

-- 快捷键：停靠到槽位 1-9 (Ctrl+Opt+数字)
-- 根据 maxSlots 配置动态绑定，支持 1-9 槽位
for i = 1, math.min(EdgeDock.config.maxSlots, 9) do
    hs.hotkey.bind(mash, tostring(i), function()
        local win = hs.window.focusedWindow()
        EdgeDock.dockWindow(win, i)
    end)
end

-- 快捷键：恢复槽位 1-9 (Ctrl+Opt+Cmd+数字)
-- 根据 maxSlots 配置动态绑定，支持 1-9 槽位
for i = 1, math.min(EdgeDock.config.maxSlots, 9) do
    hs.hotkey.bind({"ctrl", "alt", "cmd"}, tostring(i), function()
        EdgeDock.undockWindow(i)
    end)
end

-- 启动
EdgeDock.start()
