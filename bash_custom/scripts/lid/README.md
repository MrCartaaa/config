# Lid-awake (close lid, keep running)

Terminal toggle so a **plugged-in** laptop can close the lid without suspending.
On battery, lid-close still suspends. There is no keyboard shortcut; the
Hyprland lid *switch* is wrapped only to DPMS-off the panel.

## Why this exists

Omarchy's Hyprland lid bind locks and does clamshell. **Sleep** is systemd-logind:

| Setting | Default | Meaning |
|---|---|---|
| `HandleLidSwitch` | `suspend` | Lid-close on battery |
| `HandleLidSwitchExternalPower` | same as `HandleLidSwitch` | Lid-close on AC |
| `HandleLidSwitchDocked` | `ignore` | Docked clamshell already keeps running |
| `LidSwitchIgnoreInhibited` | `yes` | `systemd-inhibit` cannot block lid-close sleep |

So the toggle cannot be a user inhibitor. It writes a logind drop-in.

## Behaviour

```
lid-awake           # toggle
lid-awake on        # enable — errors if not on AC
lid-awake off
lid-awake status
```

**Enable is refused on battery** (stderr + desktop notification). Plug in, then
`lid-awake on`.

While enabled, the drop-in is:

```ini
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
```

Unplugging does not need a watchdog: logind uses `HandleLidSwitch` on battery,
so lid-close suspends again until AC is back.

Omarchy still **locks** on lid-close when there is no external display.
Idle lock (`omarchy toggle idle`) is independent.

`omarchy toggle suspend` only hides Suspend from the system menu. Unrelated.

## Files

| File | Role |
|---|---|
| `lid-keep-running.sh` | User-facing CLI (`lid-awake` alias) |
| `lid-keep-running-apply.sh` | Root-only: write/remove `/etc/systemd/logind.conf.d/30-lid-keep-running.conf`, `systemctl reload systemd-logind` |
| `lid-event.sh` | Hyprland `switch:on/off:Lid Switch` wrapper |
| `lib.sh` | AC check, flag path, logind dbus helper |

Alias: `~/.config/bash_custom/aliases.conf` → `lid-awake`.

Lid binds: `~/.config/hypr/custom/bindings.lua` unbinds the stock Omarchy lid
handlers and points them at `lid-event.sh`. That wrapper still calls
`omarchy-system-lid-close` / `omarchy-hyprland-monitor-clamshell`. When the
toggle is on, we are on AC, and there is no external monitor, close also
`hyprctl dispatch dpms off` so the backlight is not left on under the lid.

Do not edit `/usr/share/omarchy/` or `/etc/systemd/logind.conf`.

## State

- Source of truth for sleep: logind (`HandleLidSwitchExternalPower=ignore`).
- Mirror flag: `~/.local/state/omarchy/toggles/lid-keep-running` (for `lid-event.sh`).
- Persists until `lid-awake off` (drop-in survives reboot).

## Developer notes

- `lid-keep-running-apply.sh` must not source `lib.sh` or use `$HOME`; sudo may
  reset the environment. It only touches that one drop-in path.
- Reload logind (`systemctl reload systemd-logind`), never restart it, so the
  session stays up.
- Override sysfs for tests: `LIDAWAKE_POWER_SUPPLY_DIR=/tmp/fake-psu`.
- After Hyprland Lua changes: `hyprctl reload` then `hyprctl configerrors`.
- Confirm lid binds: `hyprctl binds` should show `switch:on:Lid Switch` and
  `switch:off:Lid Switch`.

## Safety

A closed laptop in a bag still runs on AC and can overheat. Turn it off with
`lid-awake off` when finished. The panel is DPMS-off, not S3.
