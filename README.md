# Vite background process stopped by SIGTTIN

This repository contains a minimal reproduction for a bug in which a Vite server background process is stopped for trying to read STDIN,
but will still take incoming connections to which it will never respond.

I'm not sure exactly what the expected behavior should be here, but the server connecting and silently never responding does not feel right.

## How to reproduce

This reproduction is built on a totally unmodified Vite project created with `npm create vite@latest` and selecting `Vanilla` + `JavaScript` for absolute minimal dependencies. It uses Docker since the exact way this behavior manifests depends on the exact shell implementation / TTY involved, but the same rough behavior will occur in any UNIX environment.

1. Build and run the Docker container: `./build.sh && ./run.sh`
2. Start a Vite server in the background: `npm run preview -- --host &`
3. Issue any command in the foreground: e.g., `echo hello`
4. Observe the `Stopped` message presented by Bash indicating the Vite server process group has been stopped
5. Issue a request to the Vite server: `curl http://localhost:4173/` or via a browser on the host machine
6. Observe that a connection is established, but Vite never responds

This crude pattern of starting a server in the background comes up commonly in CI pipelines with tools like Cypress or Playwright.

## What is going on here?

I've dug very deep on exactly what's going on here, and this is my best understanding of what causes this behavior.

Prior to Vite 4, the server started by `dev` and `preview` was non-interactive.
That is, were no prompts like `press h + enter to show help`.
The server process made no attempt to read from stdin, so there was no issue like this before Vite 4.

In Vite 4 and newer, the server actually is interactive and does have prompts for things like help, quitting without sending a `SIGINT` via `Ctrl+c`, etc...
When the Vite server (dev or preview, both behave the same) gets started in a background process of the shell,
it is still trying to read stdin for those prompts and gets sent a `SIGTTIN` for trying to steal input from the foreground terminal process's stdin.
Receiving this unhandled `SIGTTIN` puts Vite's whole process group into a `T` state according to `ps aux`,
which is "stopped by job control signal" (that is, stopped by `SIGTTIN` for trying to steal input from the terminal).

There are some easy ways to work around this like by redirecting stdin:

```sh
npm run preview < /dev/null &
```

When run in the above manner, the server behaves as it did before Vite 4 since it is not using the forked stdin from the shell process.

I don't necessarily think that Vite is entirely wrong for its current behavior -
it's very consistent with other programs that read from stdin being launched in background processes this way -
but what feels uniquely weird is that the server will happily accept new connections but silently never respond after it has been stopped.
I think it would be great if the Vite server would stop more gracefully and refuse new connections,
or provide some sort of quiet/non-interactive mode for this kind of situation that don't try to consume stdin.
