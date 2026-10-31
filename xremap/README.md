# xremap trial

Run as the normal user from an active Fedora Sway session:

```sh
./scripts/xremap-apply.sh
```

Installer adds pinned xremap and narrow uaccess rules; autostart stays disabled.
Live-check `xremap --desktop wlroots --list-windows`; test global/foot/footclient
Super+C/V, Shift+Super+C reload, US/RU, and keyd restart reattach. Missing `getfacl`:
`sudo dnf install acl`, then rerun.

Manual start from Sway:

```sh
systemctl --user import-environment WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_CONFIG_HOME
systemctl --user start xremap.service
```

Rollback: `systemctl --user stop xremap.service`; udev/module remains; no full rollback.
