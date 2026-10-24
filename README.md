# AETHERWAKE

Source for the AETHERWAKE Roblox experience (place `74121571667495`), synced with [Rojo](https://rojo.space).

Only **scripts** live in this repo. Models, maps, UI templates, remotes and other
instances stay in the Studio place. Every service in `default.project.json` sets
`$ignoreUnknownInstances`, so syncing never deletes them.

## Layout

| Folder in `src/`        | Where it lives in the place                  |
| ----------------------- | -------------------------------------------- |
| `ReplicatedFirst`       | `ReplicatedFirst`                            |
| `StarterPlayerScripts`  | `StarterPlayer.StarterPlayerScripts`         |
| `Shared`                | `ReplicatedStorage.Shared`                   |
| `ServerScriptService`   | `ServerScriptService`                        |
| `DevTools`              | `ServerStorage.DevTools`                     |

File names follow Rojo's rules: `*.server.luau` is a `Script`, `*.client.luau` is a
`LocalScript`, and plain `*.luau` is a `ModuleScript`. Folders become `Folder`s.

## Working on the game

1. Install the tools: `rokit install` (pins Rojo 7.4.4, see `rokit.toml`).
2. Install the Rojo plugin in Studio (`rojo plugin install`).
3. Run `rojo serve`, open the place in Studio and press **Connect** in the Rojo plugin.
4. Edit the `.luau` files here. Rojo pushes every save into Studio.

Edits made to scripts directly in Studio are **not** copied back to these files, so
make script changes in the repo and land them as pull requests.

## Checking the project builds

```sh
rojo build -o aetherwake.rbxlx
```

The output contains only the scripts, so it is a sanity check, not a playable place.
