/**
 * 配置中心
 * 从 Hammerspoon 的 config.lua 移植，适配 GNOME / Linux 应用名
 */

// 默认边距
export const margin = {
    left: 0,
    right: 0,
    inner: 10
};

// 应用特定边距（Linux 桌面名 / WM_CLASS，大小写不敏感）
export const appMargins = {
    // "google-chrome": { left: 11, right: 11, inner: 40 },
    // "chromium": { left: 11, right: 11, inner: 40 },
    // "firefox": { left: 11, right: 11, inner: 40 },
    // "code": { left: 11, right: 11, inner: 40 },
    // "code-oss": { left: 11, right: 11, inner: 40 },
    // "terminal": { left: 11, right: 11, inner: 40 },
    // "org.gnome.terminal": { left: 11, right: 11, inner: 40 }
};

// 显示器特定边距（可用显示器索引 0/1/2... 或连接器名称如 eDP-1/DP-1）
export const displayMargins = {
    // "0": { left: 11, right: 11, inner: 40 },
    // "DP-1": { left: 20, right: 20, inner: 50 },
};

// 应用+显示器组合配置
export const appDisplayMargins = {
    // "google-chrome": {
    //     "0": { left: 100, right: 20, inner: 50 },
    // },
};

/**
 * 获取窗口所属应用的标识名
 */
function getAppName(window) {
    if (!window) return null;
    // gtk_application_id 形如 "org.gnome.Terminal.desktop"
    const appId = window.get_gtk_application_id();
    if (appId) {
        const base = appId.replace(/\.desktop$/, '').toLowerCase();
        return base;
    }
    // wm_class 形如 "code", "Google-chrome"
    const wmClass = window.get_wm_class();
    if (wmClass) return wmClass.toLowerCase();
    return null;
}

/**
 * 获取显示器标识（索引或连接器名）
 */
function getDisplayIdentifier(window) {
    if (!window) return null;
    const monitorIndex = window.get_monitor();
    const display = global.display;

    // 优先使用连接器名（更稳定）
    let connector = null;
    if (display.get_monitor_name) {
        connector = display.get_monitor_name(monitorIndex);
    }

    return connector ? connector.toLowerCase() : String(monitorIndex);
}

/**
 * 大小写不敏感地从对象中取配置
 */
function getInsensitive(table, key) {
    if (!key || !table) return null;
    if (table[key]) return table[key];
    const lower = key.toLowerCase();
    for (const name in table) {
        if (name.toLowerCase() === lower) return table[name];
    }
    return null;
}

/**
 * 获取窗口最终边距配置
 */
export function getAppMargin(window) {
    if (!window) return margin;

    const appName = getAppName(window);
    const displayId = getDisplayIdentifier(window);

    // 1. 应用+显示器组合
    if (appName && displayId) {
        const appConfig = getInsensitive(appDisplayMargins, appName);
        if (appConfig) {
            const displayConfig = getInsensitive(appConfig, displayId);
            if (displayConfig) return displayConfig;
        }
    }

    // 2. 应用特定
    if (appName) {
        const appConfig = getInsensitive(appMargins, appName);
        if (appConfig) return appConfig;
    }

    // 3. 显示器特定
    if (displayId) {
        const displayConfig = getInsensitive(displayMargins, displayId);
        if (displayConfig) return displayConfig;
    }

    // 4. 默认
    return margin;
}

/**
 * 计算可用区域（在 work_area 基础上扣除左右边距）
 */
export function getUsableArea(workArea, window) {
    const m = window ? getAppMargin(window) : margin;
    return {
        x: workArea.x + m.left,
        y: workArea.y,
        width: workArea.width - m.left - m.right,
        height: workArea.height
    };
}

/**
 * 辅助：近似相等
 */
export function approx(a, b, tolerance = 10) {
    return Math.abs(a - b) <= tolerance;
}
