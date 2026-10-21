# Port Watch

A macOS menu bar app that lists the dev servers running on your machine.

Each project gets one row with its folder, the tool that serves it (vite, astro, next, tsx, …) and a clickable `localhost` link for every port. From the row you can open the project folder in Finder or stop the server.

## Requirements

- macOS 14 or later
- Swift 6, from Xcode or the Command Line Tools (`xcode-select --install`)

## Build and run

```sh
./build.sh
open "build/Port Watch.app"
```

`build.sh` compiles the app with `swiftc` and writes an ad-hoc signed bundle to `build/Port Watch.app`. To keep the app, copy it to `/Applications`.

The bundle is not notarized. If macOS blocks the first launch, right-click the app in Finder and choose **Open**.

## How it finds servers

Every 3 seconds, Port Watch:

1. Lists every process with a listening TCP port (`lsof -iTCP -sTCP:LISTEN`).
2. Looks up the working directory of each process (`lsof -d cwd`).
3. Drops processes that run from `/`, `/System`, `/Applications`, `/Library` or `~/Library`. macOS starts apps from these locations, while you start dev servers from a project folder.
4. Hides ports 49152 and above. Tools such as wrangler open internal helper ports in this range.
5. Groups the remaining processes by working directory and reads the tool name from each command line (`ps -o args=`).

**Stop** sends `SIGTERM` to every listening process in the project, including the hidden helpers.

Port Watch runs only local commands and sends no data anywhere.

## Limitations

- A dev server that runs from `/`, or listens only on a port above 49152, is not shown.
- Port Watch does not start at login. To start it at login, add it in System Settings → General → Login Items.

## License

[MIT](LICENSE)
