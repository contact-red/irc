use "irc"

actor Main
  """
  The shortest working bot: connect, register, and print everything.

  `IRCLogger` implements every callback, so this is also the place to copy
  method names from when writing a real one.
  """
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
