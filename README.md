# OmaTask

A task manager for [Omarchy](https://omarchy.org), in the spirit of the Windows
Task Manager: see what uses the CPU, memory, GPUs, disks, network and battery,
end what misbehaves, and decide what starts with your session. It follows the
Omarchy theme and language live.

![OmaTask showing the CPU graph](docs/screenshot.png)

## Pages

| Page | What it shows |
| --- | --- |
| **Processes** | Every process grouped by app (Apps, background, system), with CPU, memory, disk and GPU use, tinted by load. End, force-end, suspend, or change priority; other users' processes ask for permission through polkit. |
| **Performance** | One tile per CPU, memory, GPU, disk and network interface, with a minute of history and the details of the selected one. The CPU can show each logical processor. |
| **Sensors & battery** | Charge, power draw, time left, battery health and cycles; every temperature and fan from `/sys/class/hwmon`. |
| **Startup** | What Hyprland starts (Lua `autostart` files and classic `exec-once`), XDG autostart entries, and user services, which can be switched on and off. |
| **Services** | systemd services, the user's or the system's, with start, stop, restart and autostart. |

The window shrinks gracefully when tiled: the sidebar turns into icons and the
less important columns step aside.

### Hybrid graphics

A sleeping NVIDIA GPU stays asleep. Per-process GPU use comes from the kernel's
DRM `fdinfo`, which never wakes the card, and `nvidia-smi` is only asked while
an app other than the compositor actually uses it.

## Keyboard

| Key | Action |
| --- | --- |
| `1` – `5` | Processes, Performance, Sensors, Startup, Services |
| `Ctrl+Tab` | Next page |
| `/` | Search |
| `↑` `↓` | Move through the list |
| `→` `←` / `Enter` | Expand or collapse an app |
| `Del` | End the selected task |
| `Shift+Del` | Force the selected task to end |
| `G` | Group processes by app, or list them all |
| `C` | Overall CPU or every logical processor |
| `S` / `R` | Start or stop, restart the selected service |
| `Space` | Pause or resume updates |
| `F5` | Update now |
| `?` / `F1` | Show every shortcut |
| `Q` | Quit |

## Build and install

```sh
bin/build      # build/omatask
bin/test       # parser and model tests, offscreen
bin/install    # makepkg -fsi: installs the binary, icon and launcher entry
```

Needs `qt6-base`, `qt6-declarative` and `qt6-wayland`; `nvidia-utils` adds
NVIDIA utilization, memory and temperature.

## License

MIT
