# Toshy 与 Rectangle Window Manager 共存配置

## 问题现象

安装 Toshy 后，Rectangle Window Manager 扩展出现以下情况：

- Ghostty 等终端里 `Ctrl+Alt+←/→/c` 正常贴边/居中
- Chrome、GNOME Settings 等原生 Wayland 应用里完全没反应，或者过一会儿/休眠后失效
- 关掉 Toshy 后有时能用，有时仍然不行
- 日志反复出现 `Window manager warning: Trying to re-add keybinding "..."`

## 根因

### 1. Toshy 的 Mac 风格键位映射

Toshy 在 Windows 键盘上会把物理按键做 Mac 风格映射：

- 物理 `Ctrl` → `Super`（Command）
- 物理 `Win` → `Alt`（Option）

于是你按的 `Ctrl+Alt+→` 在 GNOME Shell 看来变成了 `Super+Alt+→`，扩展绑定的是 `Ctrl+Alt+→`，所以 Chrome/Settings 收不到快捷键。

### 2. Keybinding 名字冲突（更重要）

扩展内部注册快捷键时用的名字和系统/其它扩展冲突：

- `maximize` 和系统 `org.gnome.desktop.wm.keybindings maximize` 冲突
- `restore-window`、`center-window` 和已安装的 **Tiling Assistant** 扩展同名 keybinding 冲突

这导致每次扩展 reload（休眠唤醒、锁屏、扩展重启）时，Mutter 都报 `Trying to re-add keybinding`，快捷键可能绑定到旧的/失效的 handler 上，表现为“时灵时不灵”。

## 解决方案

### 1. 扩展侧：给冲突的 keybinding 名字加前缀

`extension.js` 里的 `SHORTCUTS` 和 schema 中，把冲突名字改为唯一前缀：

- `maximize` → `rect-maximize`
- `restore-window` → `rect-restore-window`
- `center-window` → `rect-center-window`

其它如 `left-half`、`right-half` 本身不会冲突，保持原样。

同时，注册快捷键时先 `removeKeybinding` 再 `addKeybinding`，避免 reload 时残留旧绑定：

```javascript
for (const shortcut of SHORTCUTS) {
    Main.wm.removeKeybinding(shortcut.name);
    Main.wm.addKeybinding(
        shortcut.name,
        this._settings,
        Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
        Shell.ActionMode.ALL,
        () => { /* ... */ }
    );
}
```

### 2. 扩展侧：Wayland 客户端需要 `user_op=true`

为了让 Chrome、Settings 等原生 Wayland 客户端接受程序化 resize，`rectangle.js` 里使用：

```javascript
window.move_resize_frame(true, x, y, width, height);
```

第一个参数 `user_op=true` 让 Mutter 把这次 resize 视为用户操作，否则部分 Wayland surface 会直接拒绝调整。

### 3. Toshy 侧：把 Super+Alt+X 还原为 Ctrl+Alt+X

编辑 `~/.config/toshy/toshy_config.py`，在 `User hardware keys` 切片里加入透传映射：

```python
keymap("User hardware keys", {
    # 把 Toshy 映射后的 Super+Alt+... 还原为 Ctrl+Alt+...
    C("Super-Alt-Left"):        C("C-Alt-Left"),
    C("Super-Alt-Right"):       C("C-Alt-Right"),
    C("Super-Alt-Up"):          C("C-Alt-Up"),
    C("Super-Alt-Down"):        C("C-Alt-Down"),
    C("Super-Alt-C"):           C("C-Alt-C"),
    C("Super-Alt-Enter"):       C("C-Alt-Enter"),
    C("Super-Alt-Backspace"):   C("C-Alt-Backspace"),
    C("Super-Alt-Comma"):       C("C-Alt-Comma"),
    C("Super-Alt-Dot"):         C("C-Alt-Dot"),
    C("Super-Alt-Semicolon"):   C("C-Alt-Semicolon"),
    C("Super-Alt-Apostrophe"):  C("C-Alt-Apostrophe"),

}, when = lambda ctx:
    cnfg.screen_has_focus and
    not ctx_app_is_remote
)
```

> **注意 Toshy 的 key name**：Enter 键叫 `Enter`，Backspace 键叫 `Backspace`（小写 s）。GNOME keybinding 字符串里用 `Return` / `BackSpace`，但 Toshy 的 `C()` 解析器不用这两个名字。

### 4. Toshy 侧：避免 `OptSpecialChars` 抢 `C` 键

Toshy 的 `OptSpecialChars - ABC` 和 `OptSpecialChars - US` 键位表会把 `Alt-C` 转成 `ç` / cedilla 等字符。如果 `Super+Alt-C` 被识别成 `Alt-C`，居中就会失效。

在这两个 keymap 里加上覆盖：

```python
C("Alt-C"):                 UC(0x00E7),                     # ç Small Letter c with Cedilla
C("Super-Alt-C"):           C("C-Alt-C"),                   # Override for Rectangle Window Manager center shortcut
C("Super-Alt-Comma"):       C("C-Alt-Comma"),               # Override for Rectangle left 1/3 shortcut
C("Super-Alt-Dot"):         C("C-Alt-Dot"),                 # Override for Rectangle right 1/3 shortcut
C("Super-Alt-Semicolon"):   C("C-Alt-Semicolon"),           # Override for Rectangle snap-left shortcut
C("Super-Alt-Apostrophe"):  C("C-Alt-Apostrophe"),          # Override for Rectangle snap-right shortcut
```

## 重启与验证

### 重启 Toshy

```bash
toshy-services-restart
```

### 让扩展干净加载

修改 schema / keybinding 名字后，必须**注销/登录一次**清除 GJS 缓存和 Mutter 的旧绑定。

### 验证

打开 Chrome 或 Settings，按：

- `Ctrl+Alt+←`：左半屏
- `Ctrl+Alt+→`：右半屏
- `Ctrl+Alt+c`：居中
- `Ctrl+Alt+Enter`：最大化
- `Ctrl+Alt+Backspace`：还原
- `Ctrl+Alt+,`：左 1/3
- `Ctrl+Alt+.`：右 1/3
- `Ctrl+Alt+;`：靠最左
- `Ctrl+Alt+'`：靠最右

如果还有问题，打开 Toshy 调试：

```bash
toshy-debug
```

或在另一个终端看扩展日志：

```bash
journalctl -b 0 -g 'RECTWM' --no-pager -n 50
```

## 如何给其它快捷键加透传

如果以后发现某个 `Ctrl+Alt+X` 在 Chrome 里不工作，本质都是同一个原因：Toshy 把它变成了 `Super+Alt+X`，扩展没绑定这个组合。

在 `User hardware keys` 里加一行即可：

```python
C("Super-Alt-X"): C("C-Alt-X"),
```

注意把 `X` 换成 Toshy 能识别的 key name（如 `Enter`、`Backspace`、`Semicolon`、`Apostrophe` 等）。
