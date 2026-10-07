-- ============================================
-- 拼接全屏（Stitch Fullscreen）
-- 类似 macOS 左右分屏：把「当前窗口」和「上一个焦点窗口」左右并排铺满整块屏幕，
-- 宽度按两个窗口原本的宽度比例分配，高度占满。
-- 完全忽略应用边距 / 显示器边距 / 窗口间距（无视所有边界设定）。
-- 两个窗口可以是同一个应用的两个窗口。
-- 快捷键：Ctrl+Option+Cmd+F
-- ============================================

StitchFullscreen = {}

-- 参与拼接的窗口：标准窗口、非最小化、不在 Edge Dock 槽位、尺寸合理
local function isUsableWindow(win)
    if not win then return false end

    -- 排除拿不到有效窗口 id 的影子窗口（id 为 0），它们写不进去也容易和真窗口重名
    local id = win:id()
    if not id or id <= 0 then return false end

    local okStd, standard = pcall(function() return win:isStandard() end)
    if not okStd or not standard then return false end

    local okMin, minimized = pcall(function() return win:isMinimized() end)
    if okMin and minimized then return false end

    -- Edge Dock 槽位里的窗口被藏在屏幕外，不参与拼接
    if TileManager and TileManager.isWindowInEdgeDock and TileManager.isWindowInEdgeDock(win) then
        return false
    end

    local okFrame, frame = pcall(function() return win:frame() end)
    if not okFrame or not frame or frame.w < 50 or frame.h < 50 then return false end

    return true
end

-- 按「最近焦点」排序的窗口列表（最前面的是当前窗口，其次是上一个焦点窗口）
-- 用 Hammerspoon 的窗口过滤器排序，不需要自己维护焦点历史
local focusOrderFilter = hs.window.filter.new(true)
focusOrderFilter:setSortOrder(hs.window.filter.sortByFocusedLast)

local function windowsByFocus()
    local list = {}
    for _, win in ipairs(focusOrderFilter:getWindows()) do
        if isUsableWindow(win) then
            list[#list + 1] = win
        end
    end
    return list
end

-- 取出要拼接的两个窗口：当前窗口 + 下一个最近焦点的窗口
-- 优先同一块屏幕上的窗口；都没有时退回任意屏幕上最近焦点的窗口
local function pickTwoWindows()
    local focused = hs.window.focusedWindow()
    if not isUsableWindow(focused) then return nil end

    local screen = focused:screen()
    if not screen then return nil end

    local other, fallback
    for _, win in ipairs(windowsByFocus()) do
        if win:id() ~= focused:id() then
            local winScreen = win:screen()
            if winScreen and winScreen:id() == screen:id() then
                other = win
                break
            end
            fallback = fallback or win
        end
    end

    return focused, (other or fallback), screen
end

-- 上一次拼接的结果：记住窗口对、各自宽度和左右顺序，供「再按一次」对调用
-- widths 按窗口 id 保存每个窗口自己的宽度，对调后宽度保持不变
local lastStitch = nil

-- 两个窗口当前是否正好左右并排铺满整块屏幕（判断还能不能继续对调）
local function isSideBySideFullscreen(winA, winB, sf)
    local okA, fa = pcall(function() return winA:frame() end)
    local okB, fb = pcall(function() return winB:frame() end)
    if not okA or not okB or not fa or not fb then return false end

    local function near(a, b)
        return math.abs(a - b) < 2
    end

    local left, right
    if fa.x <= fb.x then
        left, right = fa, fb
    else
        left, right = fb, fa
    end

    return near(left.x, sf.x) and near(left.y, sf.y) and near(left.h, sf.h)
        and near(right.x, sf.x + left.w) and near(right.y, sf.y) and near(right.h, sf.h)
        and near(left.w + right.w, sf.w)
end

-- 拼接全屏
function StitchFullscreen.stitch()
    local focused, other, screen = pickTwoWindows()

    if not focused then
        notify("拼接全屏", "当前没有可用窗口")
        return
    end
    if not other then
        notify("拼接全屏", "只有一个窗口，无法拼接")
        return
    end

    local sf = screen:frame()
    local idA, idB = focused:id(), other:id()

    -- 同一对窗口、同一屏幕，且当前正是上次拼出来的左右并排 → 这次改成左右对调
    local ids = lastStitch and lastStitch.ids
    local toggle = lastStitch ~= nil
        and lastStitch.screenId == screen:id()
        and lastStitch.widths[idA] and lastStitch.widths[idB]
        and ((ids[1] == idA and ids[2] == idB) or (ids[1] == idB and ids[2] == idA))
        and isSideBySideFullscreen(focused, other, sf)

    local leftWin, rightWin, leftW, rightW
    if toggle then
        -- 对调：上次在左边的这次去右边，宽度各自不变
        if idA == ids[1] then
            leftWin, rightWin = other, focused
        else
            leftWin, rightWin = focused, other
        end
        leftW = lastStitch.widths[leftWin:id()]
        rightW = lastStitch.widths[rightWin:id()]
    else
        -- 第一次拼接：宽度比例和左右顺序都按窗口当前位置来
        local fa = focused:frame()
        local fb = other:frame()

        -- 同一屏幕上按中心位置决定左右（靠左的留在左边）；重合或跨屏时当前窗口在左
        local sameScreen = focused:screen() and other:screen()
            and focused:screen():id() == other:screen():id()
        local aLeft = true
        if sameScreen then
            aLeft = (fa.x + fa.w / 2) <= (fb.x + fb.w / 2)
        end

        if aLeft then
            leftWin, rightWin = focused, other
            leftW, rightW = fa.w, fb.w
        else
            leftWin, rightWin = other, focused
            leftW, rightW = fb.w, fa.w
        end
    end

    -- 无视边距铺满整块屏幕：高度占满，宽度按两个窗口的宽度比例切分
    local total = leftW + rightW
    local splitW = (total > 0) and math.floor(sf.w * leftW / total + 0.5) or math.floor(sf.w / 2)
    if splitW < 1 then splitW = 1 end
    if splitW > sf.w - 1 then splitW = sf.w - 1 end

    setWinFrame(leftWin, hs.geometry.rect(sf.x, sf.y, splitW, sf.h))
    setWinFrame(rightWin, hs.geometry.rect(sf.x + splitW, sf.y, sf.w - splitW, sf.h))

    -- 记住这次的窗口对、各自宽度和左右顺序，下次按 F 就对调
    lastStitch = {
        ids = { leftWin:id(), rightWin:id() },
        widths = {
            [leftWin:id()] = leftW,
            [rightWin:id()] = rightW,
        },
        screenId = screen:id(),
    }

    notify("拼接全屏", string.format("左右拼接 %d%% / %d%%",
        math.floor(splitW / sf.w * 100 + 0.5),
        math.floor((sf.w - splitW) / sf.w * 100 + 0.5)))
end

-- 快捷键：拼接全屏（Ctrl+Option+Cmd+F）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "f", function()
    StitchFullscreen.stitch()
end)

print("[StitchFullscreen] 拼接全屏已加载 (Ctrl+Option+Cmd+F)")
