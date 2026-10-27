-- ============================================
-- 截图 OCR 模块
-- ⇧⌘3 拉框选区 → 远端 Ollama 视觉模型识别 → Markdown(LaTeX) 进剪贴板
-- 真正干活的是 ~/Downloads/local_ocr 下的 ocrmd.py（可单独当 CLI 用）
--
-- 等待期间 ocrmd.py 会把进度写进 progressFile（JSONL），这里定时读，
-- 把模型正在吐的字实时显示在顶部提示里，不用干等。
-- ============================================

local M = {}

-- 用户配置
M.config = {
    hotkey       = {"cmd", "shift"},                                  -- 修饰键
    key          = "3",                                               -- 触发键
    script       = os.getenv("HOME") .. "/Downloads/local_ocr/ocr",   -- 拉框截图 + 识别
    extraArgs    = "--no-notify",                                     -- 提示交给统一弹窗，不再叠系统通知
    autoPaste    = false,                                              -- 识别成功后自动按 ⌘V 粘到当前焦点
    alertTimeout = 3.0,                                               -- 结果提示时长（秒）
    previewLen   = 160,                                               -- 提示里预览多少字符
    progressFile = "/tmp/ocr_shot_progress.jsonl",                    -- 识别进度文件
    livePreview  = true,                                              -- 等待时逐字显示识别结果
    progressTick = 0.15,                                              -- 读进度文件的间隔（秒）
    previewTick  = 1.0,                                               -- 进度提示重画的最小间隔（秒），太密会闪
}

-- 内部状态
local running = false            -- 同一时间只允许跑一次

-- 显示提示（顶部贴边；同通道新提示自动顶掉旧的，避免重叠）
local function showAlert(message, timeout)
    Alert.show(message, {
        channel = "ocr",
        edge    = 1,
        timeout = timeout or M.config.alertTimeout,
    })
end

-- 把多行输出压成一行短预览
local function preview(text, limit)
    local flat = text:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    if #flat > limit then
        flat = flat:sub(1, limit) .. "…"
    end
    return flat
end

-- 读进度文件的最后一条记录（ocrmd.py 每行写一个 JSON）
local function readProgress(path)
    local fh = io.open(path, "r")
    if not fh then
        return nil
    end
    local last
    for line in fh:lines() do
        if line ~= "" then
            last = line
        end
    end
    fh:close()
    if not last then
        return nil
    end
    local ok, record = pcall(hs.json.decode, last)
    if ok and type(record) == "table" then
        return record
    end
    return nil
end

-- 等待期间盯着进度文件，把「识别中」以及模型正在吐的字显示出来
local function startProgress(startedAt)
    local lastPhase, lastChars, shownAt = nil, -1, 0

    local timer = hs.timer.new(M.config.progressTick, function()
        local record = readProgress(M.config.progressFile)
        if not record then
            return
        end
        local now = hs.timer.secondsSinceEpoch()

        if record.p == "stream" then
            -- 重画提示 = 关掉旧窗口再开一个，所以最多每秒一次；只在真的多出字时才重画
            local chars = math.floor(record.n or 0)
            if M.config.livePreview and chars ~= lastChars
                and now - shownAt >= M.config.previewTick then
                shownAt = now
                lastChars = chars
                showAlert(string.format("⏳ 识别中… %.1fs · %d 字\n%s",
                    now - startedAt, chars, preview(record.tail or "", 70)), 30)
            end
        elseif record.p == "scanning" and lastPhase ~= "scanning" and lastPhase ~= "stream" then
            shownAt = now
            showAlert("⏳ 识别中…", 30)
        end
        lastPhase = record.p
    end)
    timer:start()
    return timer
end

-- 拉框截图 → OCR → 剪贴板（可选自动粘贴）
local function captureAndOcr()
    if running then
        showAlert("⏳ 上一次识别还没结束", 1.2)
        return
    end
    running = true

    local progressPath = M.config.progressFile
    os.remove(progressPath)
    local poller = startProgress(hs.timer.secondsSinceEpoch())

    local command = string.format("%s %s --progress-file '%s'",
        M.config.script, M.config.extraArgs, progressPath)

    local task = hs.task.new("/bin/bash", function(exitCode, stdout, stderr)
        running = false
        if poller then
            poller:stop()
            poller = nil
        end
        os.remove(progressPath)

        local out = stdout and stdout:gsub("%s+$", "") or ""
        local err = stderr and stderr:gsub("%s+$", "") or false

        if exitCode ~= 0 then
            local reason = (err ~= false and err ~= "") and preview(err, 200)
                or ("脚本退出码 " .. tostring(exitCode))
            showAlert("❌ OCR 失败\n" .. reason, 4)
            print(string.format("[OcrShot] 失败 | exit=%s | %s", tostring(exitCode), reason))
            return
        end

        if out == "" then
            -- 用户按 Esc 取消了选区，静默收场
            print("[OcrShot] 已取消（未选中区域）")
            return
        end

        local function announce(prefix)
            showAlert(prefix .. "\n" .. preview(out, M.config.previewLen))
        end

        if M.config.autoPaste then
            -- 先发 ⌘V 再报结果；剪贴板此时已经被 ocrmd 写好，焦点也稳了
            hs.timer.doAfter(0.15, function()
                hs.eventtap.keyStroke({"cmd"}, "v")
                announce("✅ 已粘贴")
            end)
            print(string.format("[OcrShot] 完成 | %d 字符 | 已自动 ⌘V", #out))
        else
            announce("✅ 已复制到剪贴板")
            print(string.format("[OcrShot] 完成 | %d 字符", #out))
        end
    end, {"-c", command})

    if task then
        task:start()
    else
        running = false
        if poller then
            poller:stop()
            poller = nil
        end
        showAlert("❌ 无法启动 " .. M.config.script, 4)
    end
end

-- ========== 快捷键 ==========
M.hotkey = hs.hotkey.bind(M.config.hotkey, M.config.key, captureAndOcr)

-- ========== 公共接口 ==========
-- 供 hs 命令行 / AppleScript 手动触发：
--   hs -c 'OcrShotRun()'
_G.OcrShotRun = captureAndOcr

function M.trigger()
    captureAndOcr()
end

print(string.format("[OcrShot] 已加载 | %s+%s → %s",
    table.concat(M.config.hotkey, "+"), M.config.key, M.config.script))

return M
