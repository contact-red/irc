use "files"
use "signals"
use "time"
use "ssl/net"
use "irc"

actor Main
  """
  Connect to a network over TLS, join a channel, and print what arrives.

  The tool for answering "does this configuration reach that network", which
  is a different question from "do the tests pass": the tests drive both ends
  of the protocol, so they can agree with each other and disagree with every
  real server.

      watch <host> <port> <nick> <channel> [seconds] [command] [message]

  With `seconds` it leaves with a QUIT when the time is up, so a run does not
  end with the channel watching the bot time out. With `command` it sends one
  raw line once registered, which is how the sending half gets exercised
  without putting test traffic in a channel. With `message` it says that in
  the channel, through the same paced, split and checked path a bot uses.

  `command` carries a verb and plain parameters only. A parameter holding
  spaces has to be the last one and is written differently on the wire, so a
  line assembled from shell words cannot express it -- use `message` for that.
  """
  new create(env: Env) =>
    let host = try env.args(1)? else "irc.libera.chat" end
    let port = try env.args(2)? else "6697" end
    let nick = try env.args(3)? else "ponywatch" end
    let channel = try env.args(4)? else "" end
    let seconds = try env.args(5)?.u64()? else 0 end
    let command = try env.args(6)? else "" end
    let message = try env.args(7)? else "" end

    let ctx =
      match _context(env)
      | let c: SSLContext val => c
      | None =>
        env.err.print("could not load the certificate authorities")
        env.exitcode(2)
        return
      end

    let home =
      if channel.size() == 0 then
        None
      else
        match Channels(channel)
        | let c: Channel => c
        | let e: InvalidName =>
          env.err.print("channel: " + e.string())
          env.exitcode(2)
          return
        end
      end

    let config =
      match IRCConfigs(env.root, host, port, ctx, [nick; nick + "_"]
        where realname = "pony irc watch")
      | let c: IRCConfig val => c
      | let e: ConfigError =>
        env.err.print("configuration: " + e.string())
        env.exitcode(2)
        return
      end

    env.out.print("connecting to " + host + ":" + port + " as " + nick)
    let irc = IRC(config, Watcher(env, home, command, message))

    match MakeHandleableSignal(Sig.term())
    | let s: HandleableSignal =>
      SignalHandler(SignalAuth(env.root), recover iso _Stop(irc) end, s)
    end

    if seconds > 0 then
      let timers = Timers
      timers(Timer(_Leave(irc), seconds * 1_000_000_000))
    end

  fun _context(env: Env): (SSLContext val | None) =>
    // On Linux a client has to name its certificate authorities; there is no
    // system default to fall back on.
    for candidate in
      [ "/etc/ssl/certs/ca-certificates.crt"
        "/etc/pki/tls/certs/ca-bundle.crt" ].values()
    do
      try
        let path = FilePath(FileAuth(env.root), candidate)
        if path.exists() then
          return recover val
            SSLContext .> set_authority(path)? .> set_client_verify(true)
          end
        end
      end
    end
    None

class _Stop is SignalNotify
  let _irc: IRC
  new iso create(irc: IRC) => _irc = irc
  fun ref apply(count: U32): Bool =>
    _irc.quit("interrupted")
    false

class _Leave is TimerNotify
  let _irc: IRC
  new iso create(irc: IRC) => _irc = irc
  fun ref apply(timer: Timer, count: U64): Bool =>
    _irc.quit("watch finished")
    false

actor Watcher is IRCNotify
  let _env: Env
  let _home: (Channel | None)
  let _command: String val
  let _message: String val

  new create(env: Env, home: (Channel | None), command: String val,
    message: String val)
  =>
    _env = env
    _home = home
    _command = command
    _message = message

  be irc_registered(irc: IRCSend tag, reg: Registration val) =>
    _env.out.print("=== registered as " + reg.me().display()
      + " (connection " + reg.generation().string() + ")")
    _env.out.print("=== casemapping " + reg.casemap().string())

    match reg.isupport("NETWORK")
    | let n: String val => _env.out.print("=== network " + n) end
    match reg.isupport("CHANTYPES")
    | let c: String val => _env.out.print("=== chantypes " + c) end

    match _home
    | let c: Channel =>
      _env.out.print("=== joining " + c.display())
      irc.join([c])
    end

    match _home
    | let c: Channel =>
      if _message.size() > 0 then
        _env.out.print("> PRIVMSG " + c.display() + " :" + _message)
        irc.privmsg(c, _message)
      end
    end

    if _command.size() > 0 then
      let words = _words(_command)
      try
        let verb = words(0)?
        let params = recover iso Array[String val] end
        var i: USize = 1
        while i < words.size() do
          params.push(words(i)?)
          i = i + 1
        end

        match Wire.command(verb, consume params)
        | let l: Line val =>
          _env.out.print("> " + String.from_array(l.bytes()).clone().>strip())
          irc.send(l)
        | let e: EncodeError =>
          _env.out.print("!! could not build " + verb + ": " + e.string())
        end
      end
    end

  fun _words(text: String val): Array[String val] val =>
    let out = recover iso Array[String val] end
    var start: USize = 0
    var i: USize = 0
    try
      while i < text.size() do
        if text(i)? == ' ' then
          if i > start then
            out.push(text.substring(start.isize(), i.isize()))
          end
          start = i + 1
        end
        i = i + 1
      end
      if text.size() > start then
        out.push(text.substring(start.isize()))
      end
    end
    consume out

  be irc_message(irc: IRCSend tag, m: Message val,
    reg: (Registration val | None))
  =>
    _env.out.print("< " + m.raw())

  be irc_unparseable(irc: IRCSend tag, raw: String val, why: ParseFailure val) =>
    _env.out.print("!! unreadable (" + why.string() + "): " + raw)

  be irc_dropped(irc: IRCSend tag, what: Dropped) =>
    _env.out.print("!! not sent: " + what.string())

  be irc_session(irc: IRCSend tag, ended: SessionEnded val) =>
    _env.out.print("=== session ended: " + ended.string())

  be irc_stopped(irc: IRCSend tag, ended: SessionEnded val) =>
    _env.out.print("=== stopped: " + ended.string())
    match ended.because()
    | LocalRequest => None
    else
      _env.exitcode(1)
    end
