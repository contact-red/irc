# irc

The IRC client protocol for Pony, for writing bots. Reads and writes the wire
format, and answers the questions about names that a bot cannot answer on its
own.

## Status

irc is alpha-level software. Expect breaking changes. It has not yet been run
against a live network.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/irc.git --version 0.0.0`
* `corral fetch` to fetch your dependencies
* `use "irc"` to include this package
* `corral run -- ponyc` to compile your application

## Usage

A bot is an actor implementing `IRCNotify`. Being its own actor is what gives
it somewhere to keep state, and keeps its code off the connection's turn so it
cannot hold up a reply to a PING.

```pony
use "irc"

actor Main
  new create(env: Env) =>
    let config =
      match IRCConfigs(env.root, "irc.libera.chat", "6667", NoTLS,
        ["ponyloggerbot"; "ponyloggerbot_"])
      | let c: IRCConfig val => c
      | let e: ConfigError =>
        env.err.print("configuration: " + e.string())
        env.exitcode(2)
        return
      end

    IRC(config, IRCLogger(env))
```

`IRCLogger` prints everything and does nothing. No member of `IRCNotify` has a
default, so a misspelled callback is a compile error rather than a bot that
connects and stays silent.

Two nicknames can be one person even when their bytes differ, under a rule the
server announces at runtime. `Registration` carries that rule and arrives with
every message, so a bot cannot hold a stale copy:

```pony
Casefold.same(CasemapRfc1459, "Foo[]", "foo{}")  // true
Casefold.same(CasemapAscii, "Foo[]", "foo{}")    // false
```

`Nick` and `Channel` have no `eq`, so `==` on either does not compile and
neither can be a `Map` key. Use `Registration.same` and `Registration.key`.

`Wire` scans every byte of every line it builds, so text from a stranger
cannot end the line early and start a second one:

```pony
Wire.command("PRIVMSG", ["#ponylang"], "bye\r\nJOIN #elsewhere")
```

returns a `MalformedLine` rather than two commands. Long text is split rather
than truncated, and a split message is queued whole or dropped whole.

Everything a bot sends is paced, because servers disconnect a client that
sends too fast. PING replies and QUIT are not paced.

See the `examples/` directory for a bot that answers commands, keeps state and
survives a reconnect.

## API Documentation

[https://ponylang.github.io/irc](https://ponylang.github.io/irc)
