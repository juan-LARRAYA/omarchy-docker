# Docker widget for Omarchy

A native-looking Omarchy bar widget for monitoring and controlling Docker
containers.

## Features

- Docker logo and daemon status in the bar.
- Running and stopped container counts.
- List of all containers, with image and status.
- Start, stop, and restart controls.
- Configurable Docker context.
- On-demand refresh: Docker is queried only when the panel opens, after an
  action, or when refresh is explicitly requested.
- Configurable link to Portainer, Dockge, a custom UI, or no UI.
- Mouse and keyboard navigation.

## Requirements

- The Docker CLI must be on `PATH`.
- The desktop user must have permission to access the selected Docker context.
  The widget never elevates privileges or stores credentials.
- When the system daemon denies access, the panel can open Omarchy's official
  Sudoless Docker security wizard. The wizard clearly warns that membership in
  the `docker` group is equivalent to passwordless root and requires a reboot.

## Keyboard shortcuts

- `j` / `k` or arrows: move between containers.
- `enter` / `space` / `s`: start or stop the selected container.
- `r`: refresh.
- `o`: open the configured container UI.
- `esc`: close.

## Install

Place this directory under `~/.config/omarchy/plugins/` and enable it:

```bash
omarchy plugin enable juan.docker --section right
```
