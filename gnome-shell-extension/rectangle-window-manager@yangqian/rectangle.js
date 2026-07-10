/**
 * Rectangle 核心窗口管理逻辑
 * 从 Hammerspoon 的 rectangle.lua 移植
 */

import Meta from 'gi://Meta';
import { getAppMargin, getUsableArea, approx } from './config.js';

export default class RectangleManager {
    constructor() {
        this.windowHistory = {};
        this.cycleState = {};
        this.thirdCycleState = {};
        this.previousFocusedWindow = null;
        this.currentFocusedWindow = null;
    }

    destroy() {
        this.windowHistory = {};
        this.cycleState = {};
        this.thirdCycleState = {};
    }

    // ==========================
    // 通用工具
    // ==========================

    getFocusedWindow() {
        return global.display.focus_window;
    }

    getWorkArea(window) {
        if (!window) return null;
        return window.get_work_area_current_monitor();
    }

    getUsable(window) {
        const workArea = this.getWorkArea(window);
        if (!workArea) return null;
        return getUsableArea(workArea, window);
    }

    /**
     * 设置窗口 frame，自动处理最大化状态
     */
    setFrame(window, x, y, width, height) {
        if (!window) return;

        const wmClass = window.get_wm_class() || 'unknown';
        const maximized = window.get_maximized();
        console.log(`RECTWM setFrame: class=${wmClass} target=${x},${y} ${width}x${height} maximized=${maximized}`);

        // 如果窗口已最大化，先取消最大化
        if (maximized > 0) {
            window.unmaximize(Meta.MaximizeFlags.BOTH);
        }

        try {
            // user_op=true 让 Mutter 把 resize 当作用户操作，部分 Wayland 客户端（Chrome、Settings）只响应用户发起的 resize
            window.move_resize_frame(true, x, y, width, height);
            console.log(`RECTWM setFrame: move_resize_frame ok for ${wmClass}`);
        } catch (e) {
            console.log(`RECTWM setFrame: move_resize_frame FAILED for ${wmClass}: ${e}`);
        }
    }

    saveWindowState(window) {
        if (!window) return;
        const id = window.get_id();
        const rect = window.get_frame_rect();
        this.windowHistory[id] = {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        };
    }

    restoreWindow(window) {
        if (!window) return;
        const id = window.get_id();
        const state = this.windowHistory[id];
        if (!state) return;

        this.setFrame(window, state.x, state.y, state.width, state.height);
        delete this.windowHistory[id];
        delete this.cycleState[id];
    }

    // ==========================
    // 左/右半屏循环
    // ==========================

    leftHalf() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const id = window.get_id();
        const workArea = this.getWorkArea(window);
        const area = this.getUsable(window);
        const frame = window.get_frame_rect();
        const m = getAppMargin(window);

        const usableW = workArea.width - m.left - m.inner - m.right;
        const isLeftSide = approx(frame.x, workArea.x, 5) || approx(frame.x, area.x, 10);
        const isHalfWidth = approx(frame.width, usableW * 0.5, 50) ||
                            approx(frame.width, usableW * 2 / 3, 50) ||
                            approx(frame.width, usableW * 5 / 6, 50);

        let width;
        if (isLeftSide && isHalfWidth) {
            let state = (this.cycleState[id] || 0) + 1;
            if (state > 3) state = 1;
            this.cycleState[id] = state;
            const widths = [0.5, 2 / 3, 5 / 6];
            width = usableW * widths[state - 1];
        } else {
            this.cycleState[id] = 1;
            width = usableW * 0.5;
        }

        this.setFrame(window, workArea.x + m.left, area.y, Math.round(width), area.height);
    }

    rightHalf() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const id = window.get_id();
        const workArea = this.getWorkArea(window);
        const area = this.getUsable(window);
        const frame = window.get_frame_rect();
        const m = getAppMargin(window);

        const usableW = workArea.width - m.left - m.inner - m.right;
        const rightEdge = workArea.x + workArea.width - m.right;
        const rightXPositions = [
            rightEdge - usableW * 0.5,
            rightEdge - usableW * 2 / 3,
            rightEdge - usableW * 5 / 6
        ];

        const isRightSide = approx(frame.x, rightXPositions[0], 30) ||
                            approx(frame.x, rightXPositions[1], 30) ||
                            approx(frame.x, rightXPositions[2], 30);
        const isHalfWidth = approx(frame.width, usableW * 0.5, 50) ||
                            approx(frame.width, usableW * 2 / 3, 50) ||
                            approx(frame.width, usableW * 5 / 6, 50);

        let width;
        if (isRightSide && isHalfWidth) {
            let state = (this.cycleState[id] || 0) + 1;
            if (state > 3) state = 1;
            this.cycleState[id] = state;
            const widths = [0.5, 2 / 3, 5 / 6];
            width = usableW * widths[state - 1];
        } else {
            this.cycleState[id] = 1;
            width = usableW * 0.5;
        }

        const x = Math.round(rightEdge - width);
        this.setFrame(window, x, area.y, Math.round(width), area.height);
    }

    // ==========================
    // 上/下/最大化/居中/还原
    // ==========================

    topHalf() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const workArea = this.getWorkArea(window);
        const area = this.getUsable(window);
        this.setFrame(window, area.x, area.y, area.width, Math.floor(workArea.height * 0.5));
    }

    maximize() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const area = this.getUsable(window);
        this.setFrame(window, area.x, area.y, area.width, area.height);
    }

    center() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const area = this.getUsable(window);
        const frame = window.get_frame_rect();
        const newX = area.x + Math.floor((area.width - frame.width) / 2);
        const newY = area.y + Math.floor((area.height - frame.height) / 2);
        this.setFrame(window, newX, newY, frame.width, frame.height);
    }

    almostMaximize() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const workArea = this.getWorkArea(window);
        const m = getAppMargin(window);
        const gap = 10;
        this.setFrame(
            window,
            workArea.x + m.left + gap,
            workArea.y + gap,
            workArea.width - m.left - m.right - gap * 2,
            workArea.height - gap * 2
        );
    }

    maximizeHeight() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const workArea = this.getWorkArea(window);
        const frame = window.get_frame_rect();
        this.setFrame(window, frame.x, workArea.y, frame.width, workArea.height);
    }

    restore() {
        const window = this.getFocusedWindow();
        this.restoreWindow(window);
    }

    // ==========================
    // 四角 1/4
    // ==========================

    topLeft() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const area = this.getUsable(window);
        const m = getAppMargin(window);
        const workArea = this.getWorkArea(window);
        const w = Math.floor((area.width - m.inner) / 2);
        const h = Math.floor(workArea.height / 2);
        this.setFrame(window, area.x, area.y, w, h);
    }

    topRight() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const area = this.getUsable(window);
        const m = getAppMargin(window);
        const workArea = this.getWorkArea(window);
        const w = Math.floor((area.width - m.inner) / 2);
        const h = Math.floor(workArea.height / 2);
        const x = area.x + Math.floor((area.width + m.inner) / 2);
        this.setFrame(window, x, area.y, w, h);
    }

    bottomLeft() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const area = this.getUsable(window);
        const m = getAppMargin(window);
        const workArea = this.getWorkArea(window);
        const w = Math.floor((area.width - m.inner) / 2);
        const h = Math.floor(workArea.height / 2);
        const y = area.y + Math.floor(workArea.height / 2);
        this.setFrame(window, area.x, y, w, h);
    }

    bottomRight() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const area = this.getUsable(window);
        const m = getAppMargin(window);
        const workArea = this.getWorkArea(window);
        const w = Math.floor((area.width - m.inner) / 2);
        const h = Math.floor(workArea.height / 2);
        const x = area.x + Math.floor((area.width + m.inner) / 2);
        const y = area.y + Math.floor(workArea.height / 2);
        this.setFrame(window, x, y, w, h);
    }

    // ==========================
    // 三分之一循环
    // ==========================

    leftThird() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const id = window.get_id();
        const area = this.getUsable(window);
        const frame = window.get_frame_rect();
        const m = getAppMargin(window);
        const thirdW = Math.floor((area.width - m.inner * 2) / 3);

        const isLeftSide = approx(frame.x, area.x, 10);
        const isThirdWidth = approx(frame.width, thirdW, 30);

        let x, state;
        if (isLeftSide && isThirdWidth) {
            state = (this.thirdCycleState[id] || 0) + 1;
            if (state > 3) state = 1;
            this.thirdCycleState[id] = state;
        } else {
            state = 1;
            this.thirdCycleState[id] = 1;
        }

        x = area.x + (thirdW + m.inner) * (state - 1);
        this.setFrame(window, x, area.y, thirdW, area.height);
    }

    rightThird() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const id = window.get_id();
        const area = this.getUsable(window);
        const frame = window.get_frame_rect();
        const m = getAppMargin(window);
        const thirdW = Math.floor((area.width - m.inner * 2) / 3);
        const rightEdge = area.x + area.width;

        const isRightSide = approx(frame.x + frame.width, rightEdge, 10);
        const isThirdWidth = approx(frame.width, thirdW, 30);

        let state;
        if (isRightSide && isThirdWidth) {
            state = (this.thirdCycleState[id] || 4) - 1;
            if (state < 1) state = 3;
            this.thirdCycleState[id] = state;
        } else {
            state = 3;
            this.thirdCycleState[id] = 3;
        }

        const x = area.x + (thirdW + m.inner) * (state - 1);
        this.setFrame(window, x, area.y, thirdW, area.height);
    }

    // ==========================
    // 窗口微调移动
    // ==========================

    moveLeft() {
        const window = this.getFocusedWindow();
        if (!window) return;
        const frame = window.get_frame_rect();
        this.setFrame(window, frame.x - 50, frame.y, frame.width, frame.height);
    }

    moveRight() {
        const window = this.getFocusedWindow();
        if (!window) return;
        const frame = window.get_frame_rect();
        this.setFrame(window, frame.x + 50, frame.y, frame.width, frame.height);
    }

    moveUp() {
        const window = this.getFocusedWindow();
        if (!window) return;
        const frame = window.get_frame_rect();
        this.setFrame(window, frame.x, frame.y - 50, frame.width, frame.height);
    }

    moveDown() {
        const window = this.getFocusedWindow();
        if (!window) return;
        const frame = window.get_frame_rect();
        this.setFrame(window, frame.x, frame.y + 50, frame.width, frame.height);
    }

    // ==========================
    // 调整窗口大小
    // ==========================

    resizeWidth(delta) {
        const window = this.getFocusedWindow();
        if (!window) return;

        const frame = window.get_frame_rect();
        const workArea = this.getWorkArea(window);
        const area = this.getUsable(window);

        const centerX = area.x + Math.floor((area.width - frame.width) / 2);
        const isCentered = approx(frame.x, centerX, 20);
        const isRightEdge = approx(frame.x + frame.width, area.x + area.width, 20) ||
                            approx(frame.x + frame.width, workArea.x + workArea.width, 20);

        let newW;
        if (delta > 0) {
            newW = Math.min(frame.width + delta, area.width);
        } else {
            newW = Math.max(frame.width + delta, 200);
        }
        const actualDelta = newW - frame.width;

        let newX;
        if (isCentered) {
            newX = frame.x - Math.floor(actualDelta / 2);
        } else if (isRightEdge) {
            newX = frame.x - actualDelta;
        } else {
            newX = frame.x;
        }

        newX = Math.max(area.x, Math.min(newX, area.x + area.width - newW));
        this.setFrame(window, newX, frame.y, newW, frame.height);
    }

    growWidth() {
        this.resizeWidth(50);
    }

    shrinkWidth() {
        this.resizeWidth(-50);
    }

    // ==========================
    // 显示器切换
    // ==========================

    moveToScreenEast() {
        const window = this.getFocusedWindow();
        if (!window) return;

        const current = window.get_monitor();
        const target = global.display.get_monitor_neighbor_index(current, Meta.DisplayDirection.RIGHT);
        if (target >= 0) {
            window.move_to_monitor(target);
        }
    }

    moveToScreenWest() {
        const window = this.getFocusedWindow();
        if (!window) return;

        const current = window.get_monitor();
        const target = global.display.get_monitor_neighbor_index(current, Meta.DisplayDirection.LEFT);
        if (target >= 0) {
            window.move_to_monitor(target);
        }
    }

    // ==========================
    // 贴边
    // ==========================

    snapLeft() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const workArea = this.getWorkArea(window);
        const frame = window.get_frame_rect();
        this.setFrame(window, workArea.x, frame.y, frame.width, frame.height);
    }

    snapRight() {
        const window = this.getFocusedWindow();
        if (!window) return;
        this.saveWindowState(window);

        const workArea = this.getWorkArea(window);
        const frame = window.get_frame_rect();
        const newX = workArea.x + workArea.width - frame.width;
        this.setFrame(window, newX, frame.y, frame.width, frame.height);
    }

    // ==========================
    // 焦点历史与交换
    // ==========================

    onFocusChanged(window) {
        if (window && window !== this.currentFocusedWindow) {
            this.previousFocusedWindow = this.currentFocusedWindow;
            this.currentFocusedWindow = window;
        }
    }

    swapWithPrevious() {
        const window = this.getFocusedWindow();
        if (!window) return;

        const prev = this.previousFocusedWindow;
        if (!prev || !prev.get_id || prev.get_id() === window.get_id()) return;

        this.saveWindowState(window);
        this.saveWindowState(prev);

        const frame1 = window.get_frame_rect();
        const frame2 = prev.get_frame_rect();

        if (window.get_monitor() !== prev.get_monitor()) return;

        const workArea = this.getWorkArea(window);
        const area = this.getUsable(window);

        const getAnchor = (win, frame) => {
            const centerLine = area.x + Math.floor(area.width / 2);
            if (approx(frame.x, area.x, 20) || approx(frame.x, workArea.x, 20)) {
                return { type: 'left', ref: frame.x };
            } else if (approx(frame.x + frame.width, area.x + area.width, 20) ||
                       approx(frame.x + frame.width, workArea.x + workArea.width, 20)) {
                return { type: 'right', ref: frame.x + frame.width };
            } else if (approx(frame.x + Math.floor(frame.width / 2), centerLine, 20)) {
                return { type: 'center', ref: centerLine };
            } else {
                return { type: 'float', ref: frame.x };
            }
        };

        const applyAnchor = (frame, anchor) => {
            if (anchor.type === 'left') return anchor.ref;
            if (anchor.type === 'right') return anchor.ref - frame.width;
            if (anchor.type === 'center') return anchor.ref - Math.floor(frame.width / 2);
            return anchor.ref;
        };

        const anchor1 = getAnchor(window, frame1);
        const anchor2 = getAnchor(prev, frame2);

        let newX1 = applyAnchor({ width: frame1.width, height: frame1.height }, anchor2);
        let newX2 = applyAnchor({ width: frame2.width, height: frame2.height }, anchor1);

        newX1 = Math.max(area.x, Math.min(newX1, area.x + area.width - frame1.width));
        newX2 = Math.max(area.x, Math.min(newX2, area.x + area.width - frame2.width));

        this.setFrame(window, newX1, frame2.y, frame1.width, frame1.height);
        this.setFrame(prev, newX2, frame1.y, frame2.width, frame2.height);

        const centerLine = area.x + Math.floor(area.width / 2);
        const isWinCentered = approx(newX1 + Math.floor(frame1.width / 2), centerLine, 20);
        if (isWinCentered) window.focus(global.get_current_time());
    }
}
