# Examples

## hello

The shortest working bot. Builds a configuration and hands it to `IRCLogger`,
which implements every `IRCNotify` callback and prints what arrives.
Demonstrates `IRCConfigs`, `IRCConfig`, `ConfigError`, `IRC` and `IRCLogger`.
Start here.

```console
corral run -- ponyc examples/hello -o build --bin-name hello --path .
./build/hello
```

## ping

A bot that answers `!ping`, counts who has spoken, rejoins after a reconnect,
skips history replayed by a bouncer, and shuts down cleanly on SIGTERM.
Demonstrates `IRCNotify`, `IRCSend`, `Registration`, `Message`, `Channels`
and `SessionEnded`, and shows where a bot keeps its own state.

```console
corral run -- ponyc examples/ping -o build --bin-name ping --path .
./build/ping
```

## watch

Connects over TLS, joins a channel, prints everything that arrives, and can
send one raw line. The tool for answering "does this configuration reach that
network", which is a different question from "do the tests pass" — the tests
drive both ends of the protocol, so they can agree with each other and
disagree with every real server.

Demonstrates TLS setup with `SSLContext`, `Registration.isupport`, `Wire` and
`IRCSend.send`.

```console
corral run -- ponyc examples/watch -o build --bin-name watch --path .
./build/watch <host> <port> <nick> <channel> [seconds] [command] [message]
./build/watch irc.libera.chat 6697 ponywatch '#ponylang' 30 'WHOIS ponywatch'
./build/watch irc.libera.chat 6697 ponywatch '#ponylang' 30 '' 'hello there'
```

`command` carries a verb and plain parameters only. A parameter holding
spaces has to be the last one and is written differently on the wire, so a
line assembled from shell words cannot express it — `message` goes through
`IRCSend.privmsg`, which is the path a bot uses.

On Linux a TLS client has to name its certificate authorities; there is no
system default to fall back on. This example looks for the usual bundle
locations.
