# omascope

Inspect and signal Linux processes from the command line, without a display.

## Commands

```sh
omascope ps --json                       # every process, heaviest CPU first
omascope ps --sort mem --limit 10        # the ten largest by resident memory
omascope ps --filter firefox --json      # match name, command, user, or PID
omascope kill 4242 --signal TERM --json  # ask a process to exit
omascope kill 4242 --signal KILL --json  # force it
```

`ps` prints a table by default and one JSON object with `--json`:
`{"type":"processes","time":…,"cores":…,"count":…,"procs":[…]}`. Each process
carries `pid`, `ppid`, `uid`, `user`, `name`, `state`, `cpu` (percent, 100 = one
core), `rss` (bytes), `threads`, `started` (epoch seconds), and `cmd`.

`kill` accepts one or more PIDs. It exits 0 when every signal was sent and 1
otherwise, naming the reason on stderr; with `--json` each result carries `ok`
and `message`. PID 1 and omascope itself are always refused.

The window is `omascope` or `omascope open`; it needs a Wayland session but
none of the commands above do.
