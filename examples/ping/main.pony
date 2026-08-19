use "collections"
use "signals"
use "time"
use "irc"

actor Main
  new create(env: Env) =>
    let config =
      match IRCConfigs(env.root, "irc.libera.chat", "6667", NoTLS,
        ["ponypingbot"; "ponypingbot_"] where realname = "a pony bot")
      | let c: IRCConfig val => c
      | let e: ConfigError =>
        env.err.print("configuration: " + e.string())
        env.exitcode(2)
        return
      end

    let home =
      match Channels("#ponylang")
      | let c: Channel => c
      | let e: InvalidName =>
        env.err.print("channel: " + e.string())
        env.exitcode(2)
        return
      end

    let irc = IRC(config, PingBot(env, home))

    // Without this the bot vanishes on SIGTERM and everyone in the channel
    // watches it time out for the next few minutes.
    match MakeHandleableSignal(Sig.term())
    | let s: HandleableSignal =>
      SignalHandler(SignalAuth(env.root), recover iso _Stop(irc) end, s)
    end

class _Stop is SignalNotify
  let _irc: IRC

  new iso create(irc: IRC) =>
    _irc = irc

  fun ref apply(count: U32): Bool =>
    _irc.quit("shutting down")
    false

actor PingBot is IRCNotify
  """
  Answers `!ping`, and counts who has spoken.

  The counter is an ordinary field of this actor. That is the point of the bot
  being its own actor: state lives here, and a callback is a method on the
  thing that owns it.
  """
  let _env: Env
  let _home: Channel
  let _heard: Map[String val, U64] = _heard.create()
  var _generation: U32 = 0
  var _since: I64 = 0

  new create(env: Env, home: Channel) =>
    _env = env
    _home = home

  be irc_registered(irc: IRCSend tag, reg: Registration val) =>
    // Joining here rather than in the constructor is what makes the bot come
    // back properly after a reconnect: this fires again on every connection.
    irc.join([_home])

    // Keys are folded under the casemapping this server announced, and a
    // reconnect may reach a server that announces a different one.
    if (_generation != 0) and (_generation != reg.generation()) then
      _heard.clear()
    end
    _generation = reg.generation()

    // Anything the server stamps as older than this connection is history
    // being replayed, not someone talking now.
    _since = Time.millis().i64()

  be irc_message(irc: IRCSend tag, m: Message val,
    reg: (Registration val | None))
  =>
    let r = match reg | let x: Registration val => x else return end
    if m.command() != "PRIVMSG" then return end

    // A bouncer replays its buffer whenever a client attaches, and a
    // reconnecting bot attaches often. Counting replayed lines would count
    // them again on every reconnect.
    if _replayed(m) then return end

    match m.nick()
    | let who: Nick =>
      _heard.upsert(r.key(who), 1, {(had: U64, one: U64): U64 => had + one })
    end

    match m.trailing()
    | "!ping" =>
      match r.reply_to(m)
      | let t: Target => irc.privmsg(t, "pong")
      end
    | "!heard" =>
      match r.reply_to(m)
      | let t: Target =>
        irc.privmsg(t, _heard.size().string() + " people have spoken")
      end
    end

  fun _replayed(m: Message val): Bool =>
    match m.at()
    | let when: I64 => when < _since
    | None => false
    end

  be irc_unparseable(irc: IRCSend tag, raw: String val, why: ParseFailure val) =>
    _env.err.print("unreadable line: " + why.string())

  be irc_dropped(irc: IRCSend tag, what: Dropped) =>
    _env.err.print("did not send: " + what.string())

  be irc_session(irc: IRCSend tag, ended: SessionEnded val) =>
    _env.err.print("session: " + ended.string())

  be irc_stopped(irc: IRCSend tag, ended: SessionEnded val) =>
    _env.err.print("stopped: " + ended.string())
    match ended.because()
    | LocalRequest => None
    else
      _env.exitcode(1)
    end
