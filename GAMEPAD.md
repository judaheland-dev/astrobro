# Gamepad Notes

## Input Architecture

`InputManager.gd` routes input per player index:

- **Player 0** — keyboard/mouse primary; gamepad device 0 (first gamepad) for movement/aim fallback
- **Player 1** — IJKL keyboard primary; gamepad device 1 (second gamepad) for movement/aim/fire — first gamepad does NOT control P2

### P1 Aim Priority (InputManager.get_aim_dir)
Right stick is checked **before** mouse for Player 0. Do not revert this — it is intentional so a solo gamepad player can aim without a mouse.

## SDL2 Button Remapping

Godot uses SDL2's gamepad database, which remaps all controllers to a virtual Xbox layout. The `button_index` values in `project.godot` refer to **SDL2 logical buttons**, not raw HID button numbers.

**Consequence:** A controller that reports raw button 0 as "X" may end up as SDL2 button 2 (`JOY_BUTTON_X`). Always verify mappings with a browser gamepad tester (e.g. hardwaretester.com/gamepad) rather than assuming physical labels match button indices.

## Known Controller Mapping — Logitech Dual Action (Vendor: 046d, Product: c216)

On macOS, SDL2 remaps this controller as follows:

| Physical label | SDL2 logical | Godot JOY_BUTTON constant | button_index |
|---|---|---|---|
| Face 2 (bottom) | a | JOY_BUTTON_A | 0 |
| Face 3 (right) | b | JOY_BUTTON_B | 1 |
| Face 1 (left) | x | JOY_BUTTON_X | 2 |
| Face 4 (top) | y | JOY_BUTTON_Y | 3 |
| Select | back | JOY_BUTTON_BACK | 4 |
| Start | start | JOY_BUTTON_START | 6 |
| L3 (left stick click) | leftstick | JOY_BUTTON_LEFT_STICK | 7 |
| R3 (right stick click) | rightstick | JOY_BUTTON_RIGHT_STICK | 8 |
| L1 | leftshoulder | JOY_BUTTON_LEFT_SHOULDER | 9 |
| R1 | rightshoulder | JOY_BUTTON_RIGHT_SHOULDER | 10 |
| D-pad up | dpup | (hat, not button) | — |

**Note:** D-pad directions on this controller are reported as hat (h0.x) values, not discrete buttons. If a d-pad direction appears to trigger a button action, check whether a hat-encoded d-pad is being misread as button 11.

## Current project.godot Bindings

| Action | Keyboard/Mouse | Gamepad |
|---|---|---|
| `move_up/down/left/right` | WASD | Left stick (axis) |
| `fire` | Mouse button 1 | R1 (button_index 10) |
| `boost` | Mouse button 2 (right-click) | L1 (button_index 9) |
| `interact` | E | Face 2 / A (button_index 0) |
| `pause` | Escape | Start (button_index 6) |
| `ui_accept` | Enter / Space | A (button_index 0, any device) |
| `ui_up/down/left/right` | Arrow keys | D-pad (buttons 11-14) + left stick |
