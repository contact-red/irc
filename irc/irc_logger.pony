actor IRCLogger is IRCNotify
  """
  A bot that prints everything and does nothing.

  `IRC(config, IRCLogger(env))` is a working program, which makes it the
  shortest way to check that a configuration connects and registers.

  It is also worth copying from. Callback names here are the ones the
  compiler expects, and because every line the server sends reaches
  `irc_message`, a notify built only from this package's public API is a
  complete record of what arrived.
  """
  let _env: Env

  new create(env: Env) =>
    _env = env

  be irc_registered(irc: IRCSend tag, reg: Registration val) =>
    _env.out.print("[registered] " + reg.me().display()
      + " (connection " + reg.generation().string() + ")")

  be irc_message(irc: IRCSend tag, m: Message val,
    reg: (Registration val | None))
  =>
    _env.out.print("< " + m.raw())

  be irc_unparseable(irc: IRCSend tag, raw: String val, why: ParseFailure val) =>
    _env.err.print("[unreadable] " + why.string() + ": " + raw)

  be irc_dropped(irc: IRCSend tag, what: Dropped) =>
    _env.err.print("[dropped] " + what.string())

  be irc_session(irc: IRCSend tag, ended: SessionEnded val) =>
    _env.err.print("[session] " + ended.string())

  be irc_stopped(irc: IRCSend tag, ended: SessionEnded val) =>
    _env.err.print("[stopped] " + ended.string())
    _env.exitcode(
      match ended.because()
      | LocalRequest => 0
      else
        1
      end)
