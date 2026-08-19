"""
# IRC

The IRC client protocol, for writing bots.

This package owns the wire format and the connection: framing, the
registration handshake, PING replies, send pacing and reconnection. It owns
nothing about what a bot does. There is no command routing and no plugin
registry here, because the shape of a bot is the bot author's.

## A bot

A bot is an actor implementing `IRCNotify`. Being its own actor is what gives
it somewhere to keep state, and means its code never runs on the connection's
turn and cannot hold up a reply to a PING.

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

`IRCLogger` prints everything and does nothing, which makes it a working bot
and a place to copy callback names from. `examples/ping` is a real one.

No member of `IRCNotify` has a default. A misspelled callback is therefore a
compile error rather than a bot that connects, does nothing, and says nothing
about it in any build.

## Joining, and coming back

`irc_registered` is the first moment a send reaches the network, and it fires
again after every reconnect, so a bot that joins there rejoins by itself.
Reconnection is on unless it is switched off, with a delay that doubles and
resets only after a connection has held.

Some endings are never retried: a rejected password, a ban, and a shutdown the
bot asked for. `irc_stopped` fires once when there will be no further attempt,
and is where a bot sets a non-zero exit code -- without one the process reports
success even when it stopped because its password was refused.

## Comparing names

Two nicknames can be one person even when their bytes differ, under a rule the
server picks and announces. `Registration` carries that rule and travels with
every message, so a bot cannot hold a stale copy:

```pony
be irc_message(irc: IRCSend tag, m: Message val,
  reg: (Registration val | None))
=>
  let r = match reg | let x: Registration val => x else return end
  if r.same_text(m.source(), _owner) then ... end
```

`Nick` and `Channel` have no `eq`, so `==` on either does not compile and
neither can be a `Map` key. Use `Registration.same` to compare and
`Registration.key` to build a key. Three ways round that do compile and none
is correct: comparing `display()` strings compares bytes, `is` compares
identity, and `Array[Nick].contains` uses an identity predicate and is always
false.

Ask `Registration.private_to_me` whether a message arrived privately. Matching
`reply_to` on `Nick` is a different question, and on a network with channel
types beyond the usual ones it lets anyone reach a command meant for a direct
message.

## Sending

Everything a bot sends is paced, because servers disconnect a client that
sends too fast and the schedule is in no RFC. PING replies and QUIT are not
paced: a PONG behind forty queued messages arrives after the server has given
up.

`Wire` scans every byte of every line, so text from a stranger cannot end the
line early and start a second one, and cannot forge an action under the bot's
name. Long text is split across several messages rather than truncated, and a
split message is queued whole or dropped whole, so a channel never sees half a
sentence.

Nothing received is ever dropped. Every line reaches `irc_message` exactly
once, in order, including the ones this package acted on itself, so a bot can
handle anything not modelled here.

## What is not here

Channel membership and mode state are not tracked. SASL is not implemented,
and asking for it in `capabilities` is refused rather than accepted and
ignored -- until it lands, authenticating means sending a password to NickServ
in an ordinary message. Nothing in this package can tell that message from any
other, so a `Line` never renders its contents and a bot should not log one.
"""
