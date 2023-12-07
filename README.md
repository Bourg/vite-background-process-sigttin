# Vite background process termination bug reproduction

This repository contains a minimal reproduction for a bug in which a Vite server background process is stopped for trying to read STDIN,
but will still take incoming connections to which it will never respond.

I'm not sure exactly what the expected behavior should be here, but the server connecting and silently never responding does not feel right.

## How to reproduce

### Step 1: Build and run the Docker container

The exact nature of the behavior depends on the exact terminal emulator and TTY configuration,
so this repro is provided in a Dockerized format for consistency.

Simply run the scripts to build the Docker image and run an interactive Docker container with bash.

```sh
./build.sh
./run.sh
```

### Step 2: Start a Vite server in the background

At this point, you should be in a bash shell inside the Docker container.
Run the following command to start the Vite server in the background as a child process of the shell:

```sh
npm run preview -- --host &
```

This is a pattern that is common in CI pipelines that run a webserver and test it with tools like Cypress or Playwright,
which is how I stumbled onto this behavior.

### Step 3: Make a request to the server

At this point, if you make a request to the server from the same terminal that started the Vite server in a background process,
it will accept the connection but will never respond.

```
curl http://localhost:4173/ 
```

If you interrupt the `curl` with `Ctrl+c`, you will get a `Stopped` message from `bash`.

If you run any command, even just `echo hello`, the Vite process will stop in the same manner
and any requests to it will still connect, but Vite will never respond.
This behavior holds for `curl` both inside and outside the container, as well as from browsers outside the container.

Running Vite with the `--debug` flag and/or with the `DEBUG=*` environment variable produce no input at all to these hanging requests.

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
