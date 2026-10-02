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

    -- 先取拼接前的几何：宽度比例和左右顺序都按原样来
    local fa = focused:frame()
    local fb = other:frame()

    -- 同一屏幕上按中心位置决定左右（靠左的留在左边）；重合或跨屏时当前窗口在左
    local sameScreen = focused:screen() and other:screen()
        and focused:screen():id() == other:screen():id()
    local aLeft = true
    if sameScreen then
        aLeft = (fa.x + fa.w / 2) <= (fb.x + fb.w / 2)
    end

    local leftWin, rightWin, leftW, rightW
    if aLeft then
        leftWin, rightWin = focused, other
        leftW, rightW = fa.w, fb.w
    else
        leftWin, rightWin = other, focused
        leftW, rightW = fb.w, fa.w
    end

    -- 无视边距铺满整块屏幕：高度占满，宽度按两个窗口原来的宽度比例切分
    local sf = screen:frame()
    local total = leftW + rightW
    local splitW = (total > 0) and math.floor(sf.w * leftW / total + 0.5) or math.floor(sf.w / 2)
    if splitW < 1 then splitW = 1 end
    if splitW > sf.w - 1 then splitW = sf.w - 1 end

    setWinFrame(leftWin, hs.geometry.rect(sf.x, sf.y, splitW, sf.h))
    setWinFrame(rightWin, hs.geometry.rect(sf.x + splitW, sf.y, sf.w - splitW, sf.h))

    notify("拼接全屏", string.format("左右拼接 %d%% / %d%%",
        math.floor(splitW / sf.w * 100 + 0.5),
        math.floor((sf.w - splitW) / sf.w * 100 + 0.5)))
end

-- 快捷键：拼接全屏（Ctrl+Option+Cmd+F）
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "f", function()
    StitchFullscreen.stitch()
end)

print("[StitchFullscreen] 拼接全屏已加载 (Ctrl+Option+Cmd+F)")
