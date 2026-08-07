# Firmware

The board runs [libhmk](https://github.com/peppapighs/libhmk), an open-source
Hall-effect keyboard firmware, configured live through
[hmkconf](https://hmkconf.com/). On top of libhmk this board adds a small module
(`gd_keypad.c` / `.h`) for the six mechanical keys and the rotary encoder, which
libhmk does not model natively.

Files here:

| File | Role |
|---|---|
| `keyboard.json` | The board definition (libhmk compiles it into firmware, hmkconf reads it to draw the board) |
| `gd_keypad.c` / `gd_keypad.h` | Mechanical matrix scanning + rotary encoder decoding |
| `main.c` | The updates version of libhmk's `main.c` with a three-line change that calls the module |

---

## Building

libhmk is the build environment. Keep this repo separate from your libhmk clone
and copy these files in.

**One-time setup:**

1. Install [Python](https://www.python.org/downloads/) (tick "Add to PATH"),
   [Git](https://git-scm.com/), and [VS Code](https://code.visualstudio.com/)
2. In VS Code, install the **PlatformIO IDE** extension
3. Clone libhmk and install its dependency:
   ```
   git clone https://github.com/peppapighs/libhmk.git
   cd libhmk
   python -m pip install -r requirements.txt
   ```

**Add this board:**

1. Copy the files into the libhmk clone:
   - `keyboard.json` → `keyboards/gd-keypad/keyboard.json`
   - `gd_keypad.h` → `include/gd_keypad.h`
   - `gd_keypad.c` → `src/gd_keypad.c`
   - replace `src/main.c` with new `main.c` file (three lines patch - see below)
2. Open the `libhmk` folder in VS Code as the workspace root
3. In the terminal:
   ```
   python setup.py -k gd-keypad
   ```
   (no output means success - it writes `platformio.ini`)
4. Build with the checkmark in the status bar, or PlatformIO sidebar →
   Project Tasks → gd-keypad → Build
5. Output: `.pio/build/gd-keypad/firmware.bin`

The three-line `main.c` change - the module must run **after** `matrix_scan()`
(which would otherwise overwrite our keys with empty ADC data) and **before**
`layout_task()` (which turns key states into USB reports):

```diff
 #include "xinput.h"
+#include "gd_keypad.h"
```
```diff
   matrix_init();
+  gd_keypad_init();
```
```diff
     matrix_scan();
+    gd_keypad_task();
     layout_task();
```

Re-apply this patch whenever you pull libhmk updates.

## Flashing (WebUSB DFU)

1. Hold the **BOOT0** button, plug in USB, release BOOT0
2. **First time on Windows:** the device shows up as "DFU in FS Mode" under
   *Other devices* in Device Manager with no driver. Install one with
   [Zadig](https://zadig.akeo.ie/): Options → List All Devices, select
   "DFU in FS Mode", target **WinUSB**, Install Driver.
3. Open the [WebUSB DFU tool](https://devanlai.github.io/webdfu/dfu-util/) in
   Chrome or Edge → Connect → select the **internal flash** interface → choose
   `firmware.bin` → flash.
4. Unplug and replug **without** BOOT0 to boot the firmware. It enumerates as
   "GD Keypad".

## Configuring in hmkconf

[hmkconf](https://hmkconf.com/) talks to the running board over WebUSB (plugged
in normally, not in DFU) and edits the config in flash — no reflashing. All
twelve keys, including the encoder, appear there and can be remapped. Settings
persist in flash and survive reflashing.

---

## How it works

### The board definition (`keyboard.json`)

libhmk builds a board from one JSON file; the driver and chip support are shared
code selected by `"driver": "at32f405xx"`.

Key fields for this board:

- `usb.port: "hs"` — high-speed USB, which is what enables 8 kHz polling
- `hardware.hse_value: 12000000` — the 12 MHz crystal the USB PHY requires
- `keyboard.num_keys: 12` — sizes every per-key array at compile time
  (see below for why it's 12, not 3)
- `analog.raw` — maps the three sensors directly to ADC pins A0/A1/A2, no
  multiplexer:
  ```json
  "raw": { "input": ["A0", "A1", "A2"], "vector": [3, 2, 1] }
  ```
  The reversed vector puts the physically-leftmost key first, matching the board.
- `calibration` — global starting values for the noise floor and bottom-out
  threshold; libhmk auto-calibrates each key at runtime relative to these

### Adding the mechanical keys and encoder

libhmk's key pipeline has a natural seam: everything upstream decides whether a
key is down and writes `key_matrix[i].is_pressed`; everything downstream
(`layout_task()`) turns that boolean into keycodes, layers, and USB reports. And
`layout_task()` is **edge-triggered** — it only acts on changes to those
booleans.

That made the integration clean. Rather than hand-build keypresses, `num_keys` is
set to **12** and the module writes directly into the extra indices:

| Index | Input |
|---|---|
| 0–2 | Hall jump keys (libhmk, from the ADC) |
| 3–8 | Mechanical matrix |
| 9 | Encoder push switch |
| 10 / 11 | Encoder rotate CW / CCW (virtual) |

The mechanical keys and encoder become first-class keys — same code path as the
analog ones, fully remappable in hmkconf. Keys 3–11 have no ADC input, so their
sensor values stay 0 and they never self-actuate; the module's write is what
gives them state.

### The mechanical matrix

The diodes point toward the rows, so the scan **drives a row low and reads the
columns** (each with an internal pull-up). A pressed key pulls its column low
through the forward-biased diode. One row is active at a time; the diodes prevent
ghosting. Each switch is debounced with a "wait for the reading to hold steady
for 5 ms" filter.

### The encoder

A quadrature encoder's two contacts produce a repeating pattern as it turns;
direction comes from *which* transition occurs. The module reads both pins,
combines previous and current state into a lookup that yields −1 / 0 / +1, and
accumulates to a detent. Because a rotation is an event but `layout_task()` only
understands press and release, each detent briefly presses and then releases a
virtual key — serialized so a fast spin produces a clean sequence of discrete
keypresses rather than one smeared hold.

---

## Per-application volume control (AutoHotkey)

The encoder drives *Geometry Dash's* volume specifically — not system volume —
because Windows has no per-app volume shortcut. The board sends F13/F14 (rotation)
and F15 (press); a script translates those into per-app audio commands.

1. Install [SoundVolumeView from NirSoft](https://www.nirsoft.net/utils/sound_volume_view.html)
   and unzip to somewhere permanent (e.g. `C:\Program Files\SoundVolumeView`)
2. Open Geometry Dash
3. Run `SoundVolumeView.exe` and confirm that `GeometryDash.exe` is an entry
4. Install [AutoHotkey](https://www.autohotkey.com/)
5. Make a text file named `gd-knob.ahk` anywhere convenient
6. Open `gd-knob.ahk` in Notepad and paste the following (replace `1` / `-1` with
   your preferred step size):

   ```autohotkey
   #Requires AutoHotkey v2.0

   svv := "C:\Program Files\SoundVolumeView\SoundVolumeView.exe"
   app := "GeometryDash.exe"

   F14::Run(svv ' /ChangeVolume "' app '" 1', , "Hide")   ; knob CW  = louder
   F13::Run(svv ' /ChangeVolume "' app '" -1', , "Hide")  ; knob CCW = quieter
   F15::Run(svv ' /Switch "' app '"', , "Hide")           ; knob press = mute toggle
   ```

7. Run it by double-clicking `gd-knob.ahk` and test the knob
8. To launch it with Windows: Win+R, type `shell:startup`, press Enter (opens the
   Startup folder), then put a shortcut to `gd-knob.ahk` there (right-click the
   `.ahk`, Create shortcut, move the shortcut into that folder)

F13–F15 were chosen because effectively no keyboard has them, so they don't
collide with anything else while the script captures them.

---

## Calibration

The Hall keys need calibrating once the switches are seated in the case (their
resting magnet-to-sensor distance, which the calibration depends on, is only
fixed once the case holds them at the proper height). hmkconf has a calibration
section where the sensors can be tuned.

---

## Notes
- `gd_keypad.c` / `.h` are written against libhmk (GPL-3.0-or-later) and inherit
  that license.
