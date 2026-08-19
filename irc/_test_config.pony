use "pony_test"

class \nodoc\ iso _TestConfigAccepts is UnitTest
  fun name(): String => "config/fills in what it can and always asks for server-time"

  fun apply(h: TestHelper) =>
    match IRCConfigs(h.env.root, "irc.example.org", "6667", NoTLS, ["pingbot"])
    | let c: IRCConfig val =>
      // user and realname default to the first nickname.
      h.assert_eq[String]("pingbot", c.user())
      h.assert_eq[String]("pingbot", c.realname())

      // Requested whether or not the bot asked: without it, a bot cannot tell
      // a replayed line from a live one after a reconnect.
      var found = false
      for cap in c.capabilities().values() do
        if cap == "server-time" then found = true end
      end
      h.assert_true(found, "server-time should always be requested")
    | let e: ConfigError => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestConfigRejects is UnitTest
  fun name(): String => "config/refuses what would fail later or fail silently"

  fun apply(h: TestHelper) =>
    let root = h.env.root

    _bad(h, "no nicknames",
      IRCConfigs(root, "h", "6667", NoTLS, []))

    _bad(h, "a nickname that is really a channel",
      IRCConfigs(root, "h", "6667", NoTLS, ["#ponylang"]))

    _bad(h, "an empty host",
      IRCConfigs(root, "", "6667", NoTLS, ["bot"]))

    // A newline here would be refused by the encoder mid-handshake, and the
    // connection would time out and retry for ever on a permanent fault.
    _bad(h, "a newline in realname",
      IRCConfigs(root, "h", "6667", NoTLS, ["bot"] where
        realname = "a\r\nOPER x y"))

    // Sending a password in the clear has to be asked for by name.
    _bad(h, "a password with no TLS",
      IRCConfigs(root, "h", "6667", NoTLS, ["bot"] where password = "hunter2"))

    // Requested and never honoured is worse than refused: the bot would
    // register unauthenticated with nothing reported.
    _bad(h, "a capability this package does not implement",
      IRCConfigs(root, "h", "6667", NoTLS, ["bot"] where
        capabilities = ["sasl"]))

    _bad(h, "a queue that can hold nothing",
      IRCConfigs(root, "h", "6667", NoTLS, ["bot"] where
        rate = SendRate(5, 2_000, 0)))

    _bad(h, "a line bound below the protocol limit",
      IRCConfigs(root, "h", "6667", NoTLS, ["bot"] where max_line_bytes = 100))

  fun _bad(h: TestHelper, what: String,
    result: (IRCConfig val | ConfigError))
  =>
    match result
    | let c: IRCConfig val => h.fail("accepted " + what)
    | let e: ConfigError =>
      h.assert_true(e.field().size() > 0, "an error should name its field")
    end

class \nodoc\ iso _TestConfigPlaintextOptIn is UnitTest
  fun name(): String => "config/a plaintext password is possible, but only on purpose"

  fun apply(h: TestHelper) =>
    match IRCConfigs(h.env.root, "h", "6667", NoTLSWithPassword, ["bot"]
      where password = "hunter2")
    | let c: IRCConfig val => None
    | let e: ConfigError =>
      h.fail("the explicit opt-in should be accepted: " + e.string())
    end
