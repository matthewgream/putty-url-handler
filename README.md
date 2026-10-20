# PuTTY URL handler

Click an `ssh://` link in a browser, get a PuTTY session — using your saved
session's key, username and port, so key authentication just works.

Windows 11, PuTTY 0.84. Based on the idea in
[John's Software Engineering blog (2009)][post], rebuilt for a world where both
PuTTY and the browsers have moved on.

[post]: https://johnsofteng.wordpress.com/2009/05/12/launch-putty-from-browser/

## Install on a new machine

1. Install PuTTY, and clone this repo anywhere.
2. From an **elevated** PowerShell:

       .\Install.ps1 -Machine

That builds `PuttyUrl.exe` (using the C# compiler already in Windows — nothing
to install) and registers `ssh://` and `putty://`. Restart the browser if links
were clicked before installing.

3. For key authentication, the machine also needs your PuTTY saved sessions.
   On a machine that already has them:

       .\Export-Sessions.ps1

   Copy the resulting `.reg` **and the `.ppk` key files it lists** to the new
   machine, put the keys at the same paths, and `reg import putty-sessions.reg`.

Verify with `test.html`, which covers session matching, overrides, fallback and
hostile input.

## Install where it goes matters — read this if links do nothing

Use `-Machine`. It writes `HKLM\Software\Classes`.

Without it, the handler goes in `HKCU\Software\Classes`, which needs no admin
rights and works from Explorer, Win+R and Firefox — but **Chromium browsers may
only consult HKLM** and ignore per-user protocol handlers entirely. The symptom
is distinctive: clicking the link does *nothing at all*, with no "Open ...?"
confirmation, and no error anywhere.

How to recognise it:

| Clicking a link gives | Means |
| --- | --- |
| a confirmation prompt, then PuTTY | working |
| a confirmation prompt, then nothing | a *different* handler is registered in HKLM and is being used |
| nothing whatsoever, no prompt | the browser cannot see the handler — install with `-Machine` |

Windows' own `telnet://` handler is a good example of the middle row: it points
at a `telnet.exe` that is not installed by default, so it prompts and then does
nothing. `Install.ps1 -Machine -Schemes telnet` takes it over, saving the old
command so `Uninstall.ps1 -Machine` can put it back.

## Why a wrapper is needed at all

PuTTY now strips an `ssh://` prefix and a `user@` part by itself, so 2009's main
reason is gone. But it still ignores a port given in the hostname:

    plink.exe -v ssh://bob@127.0.0.1:2222   ->   Connecting to 127.0.0.1 port 22

The port has to arrive as a separate `-P`. And a bare URL carries no key, so
`ssh://host` alone lands you at a password prompt. `PuttyUrl.exe` handles both.

It is a ~10 KB C# program rather than a batch file: no console window flashing
up, no PowerShell execution policy, and no VBScript, which Windows is removing.

## Saved sessions, and why key auth works

Given a URL, the handler looks for a matching saved session and launches
`-load "<session>"`, which brings the session's key, username and port with it.
Matching order:

1. session **name** equals the host — `putty://iotgate` → session `iotgate`
2. session **HostName** and **port** both match — `ssh://gw.example:8893` picks
   the right one of several sessions sharing a host
3. session **HostName** matches
4. session name equals the host minus a `.local` suffix

Anything explicit in the URL still overrides the session:

| URL | PuTTY command line |
| --- | --- |
| `ssh://iotgate.local` | `-load "iotgate"` |
| `putty://iotgate` | `-load "iotgate"` |
| `ssh://matt@iotgate.local` | `-load "iotgate" -l "matt"` |
| `ssh://iotgate.local:2222` | `-load "iotgate" -P "2222"` |
| `ssh://gw.example:8893` | `-load "gw-iotgate"` (port picks the session) |
| `ssh://unknown.example.com` | `-ssh "unknown.example.com"` (no session: plain) |
| `telnet://router.lan:2323` | `-telnet -P "2323" "router.lan"` |

With no matching session it connects plainly, which means a login prompt — that
is the fallback, not a failure.

## Schemes

`ssh://`, `putty://`, `telnet://`, `rlogin://`. Default install claims `ssh` and
`putty`; add the others with `-Schemes`.

`putty://` exists as an alias that no browser or website claims, which is useful
if a future browser decides to do something of its own with `ssh://`.

## Linking to it from your own pages

Emit plain `ssh://<host>` links. If the host matches a saved session, key auth
follows automatically — no need to put usernames or session names in the markup.

```js
a.href = 'ssh://' + host;
```

## Security

A URL protocol handler is reachable from any page you visit, so its input is
untrusted:

- One explicit regex parses the URL. No shell is involved, and
  `UseShellExecute` is off.
- Host, user and port are re-validated against a character whitelist after
  percent-decoding, and both must start alphanumeric — so a crafted link cannot
  smuggle a leading `-` through and have PuTTY read it as a switch.
  `ssh://-pw%20hunter2` is refused, not run.
- Session names reaching the command line are skipped if they start with `-` or
  contain a quote.
- A password in the URL (`ssh://user:secret@host`) is parsed and then dropped on
  purpose: PuTTY's `-pw` would put it in the machine's process list.
- Only `ssh`, `putty`, `telnet` and `rlogin` are handled.

`test.html` includes the hostile cases so you can confirm this yourself.

## Finding putty.exe

In order: `%PUTTY_PATH%`, next to `PuttyUrl.exe`, `%ProgramFiles%\PuTTY`, the
x86 and `LOCALAPPDATA\Programs` equivalents, then `PATH`. Set `PUTTY_PATH` if
yours lives somewhere unusual.

## Uninstall

    .\Uninstall.ps1 -Machine     # from an elevated shell
    .\Uninstall.ps1              # the per-user keys

Where a previous handler was shadowed, its saved command is restored instead of
the key being deleted.

## Files

| File | |
| --- | --- |
| `PuttyUrl.cs` | the handler |
| `Build.ps1` | compiles with the csc.exe shipped in Windows |
| `Install.ps1` | registers the protocols; builds first if needed |
| `Uninstall.ps1` | removes them, restoring anything shadowed |
| `Export-Sessions.ps1` | exports saved sessions for another machine |
| `test.html` | click-through test, valid and hostile |
