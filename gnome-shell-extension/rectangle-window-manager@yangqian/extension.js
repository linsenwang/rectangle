/**
 * Rectangle Window Manager - GNOME Shell 扩展入口
 */

import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import RectangleManager from './rectangle.js';

const SHORTCUTS = [
    { name: 'left-half', handler: 'leftHalf' },
    { name: 'right-half', handler: 'rightHalf' },
    { name: 'top-half', handler: 'topHalf' },
    { name: 'rect-maximize', handler: 'maximize' },
    { name: 'rect-restore-window', handler: 'restore' },
    { name: 'rect-center-window', handler: 'center' },
    { name: 'almost-maximize', handler: 'almostMaximize' },
    { name: 'snap-left', handler: 'snapLeft' },
    { name: 'snap-right', handler: 'snapRight' },
    { name: 'top-left', handler: 'topLeft' },
    { name: 'top-right', handler: 'topRight' },
    { name: 'bottom-left', handler: 'bottomLeft' },
    { name: 'bottom-right', handler: 'bottomRight' },
    { name: 'left-third', handler: 'leftThird' },
    { name: 'right-third', handler: 'rightThird' },
    { name: 'grow-width', handler: 'growWidth' },
    { name: 'shrink-width', handler: 'shrinkWidth' },
    { name: 'move-screen-west', handler: 'moveToScreenWest' },
    { name: 'move-screen-east', handler: 'moveToScreenEast' },
    { name: 'maximize-height', handler: 'maximizeHeight' },
    { name: 'move-left', handler: 'moveLeft' },
    { name: 'move-right', handler: 'moveRight' },
    { name: 'move-up', handler: 'moveUp' },
    { name: 'move-down', handler: 'moveDown' },
    { name: 'swap-windows', handler: 'swapWithPrevious' }
];

export default class RectangleExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._manager = new RectangleManager();

        // 禁用与本扩展冲突的系统工作区切换快捷键
        this._disableConflictingKeybindings();

        // 注册快捷键：先强制移除可能残留的同名绑定，避免 reload 时绑定到旧 handler
        for (const shortcut of SHORTCUTS) {
            Main.wm.removeKeybinding(shortcut.name);
            try {
                Main.wm.addKeybinding(
                    shortcut.name,
                    this._settings,
                    Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
                    Shell.ActionMode.ALL,
                    () => {
                        const win = global.display.focus_window;
                        const wmClass = win ? win.get_wm_class() : 'null';
                        console.log(`RECTWM: ${shortcut.name} triggered, focus=${wmClass}`);
                        try {
                            this._manager[shortcut.handler]();
                        } catch (e) {
                            logError(e, `RectangleWM: ${shortcut.name}`);
                        }
                    }
                );
                console.log(`RECTWM: registered ${shortcut.name}`);
            } catch (e) {
                console.log(`RECTWM: FAILED to register ${shortcut.name}: ${e}`);
            }
        }

        // 监听焦点变化，用于窗口交换
        this._focusId = global.display.connect('notify::focus-window', () => {
            const window = global.display.focus_window;
            if (window) this._manager.onFocusChanged(window);
        });

        log('Rectangle Window Manager 已加载');
    }

    disable() {
        if (this._focusId) {
            global.display.disconnect(this._focusId);
            this._focusId = null;
        }

        for (const shortcut of SHORTCUTS) {
            Main.wm.removeKeybinding(shortcut.name);
        }

        this._restoreConflictingKeybindings();

        this._manager.destroy();
        this._manager = null;
        this._settings = null;

        log('Rectangle Window Manager 已卸载');
    }

    _disableConflictingKeybindings() {
        this._conflictingSettings = [];
        const schemaId = 'org.gnome.desktop.wm.keybindings';
        const settings = new Gio.Settings({ schema_id: schemaId });
        const keys = [
            'switch-to-workspace-left',
            'switch-to-workspace-right',
            'switch-to-workspace-up',
            'switch-to-workspace-down'
        ];
        const conflicts = [
            '<Control><Alt>Left',
            '<Control><Alt>Right',
            '<Control><Alt>Up',
            '<Control><Alt>Down'
        ];

        for (const key of keys) {
            const original = settings.get_strv(key);
            const filtered = original.filter(a => !conflicts.includes(a));
            if (filtered.length !== original.length) {
                this._conflictingSettings.push({ settings, key, original });
                settings.set_strv(key, filtered);
            }
        }
    }

    _restoreConflictingKeybindings() {
        if (!this._conflictingSettings) return;
        for (const item of this._conflictingSettings) {
            item.settings.set_strv(item.key, item.original);
        }
        this._conflictingSettings = null;
    }
}
