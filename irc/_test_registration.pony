use "pony_test"

primitive \nodoc\ _Fixture
  """The session facts a bot's name handling depends on, in one place."""
  fun libera(): Registration val ? =>
    Registration(
      Nicks("pingbot") as Nick,
      CasemapRfc1459,
      [ ("CHANTYPES", "#&")
        ("STATUSMSG", "@+")
        ("NICKLEN", "30") ],
      ["server-time"])

  fun line(text: String val): Message val ? =>
    Parse(text) as Message val

class \nodoc\ iso _TestRegistrationCompare is UnitTest
  fun name(): String => "registration/names compare by the server's rule"

  fun apply(h: TestHelper) ? =>
    let reg = _Fixture.libera()?

    let a = Nicks("Foo[]") as Nick
    let b = Nicks("foo{}") as Nick

    // The bug the package exists to prevent. Comparing the displayed bytes
    // says these differ; on this server they are one person.
    h.assert_true(reg.same(a, b))
    h.assert_false(a.display() == b.display())

    // A folded key is what a map should hold.
    h.assert_eq[String](reg.key(a), reg.key(b))
    h.assert_eq[String]("foo{}", reg.key(a))

    // Parameters arrive as plain strings, where `==` compiles and is wrong.
    h.assert_true(reg.same_text("Foo[]", "foo{}"))
    h.assert_eq[String]("foo{}", reg.key_text("FOO[]"))

class \nodoc\ iso _TestRegistrationPrivacy is UnitTest
  fun name(): String => "registration/a local channel is not a private message"

  fun apply(h: TestHelper) ? =>
    let reg = _Fixture.libera()?

    h.assert_true(
      reg.private_to_me(_Fixture.line(":a!u@h PRIVMSG pingbot :!deploy")?))

    // Case-insensitively, by the server's rule.
    h.assert_true(
      reg.private_to_me(_Fixture.line(":a!u@h PRIVMSG PingBot :!deploy")?))

    h.assert_false(
      reg.private_to_me(_Fixture.line(":a!u@h PRIVMSG #ponylang :!deploy")?))

    // The bypass this method exists to close. `&local` is a channel here, and
    // a privacy check written as a match on `Nick` would call it private.
    h.assert_false(
      reg.private_to_me(_Fixture.line(":a!u@h PRIVMSG &local :!deploy")?))

class \nodoc\ iso _TestRegistrationReplyTo is UnitTest
  fun name(): String => "registration/a reply goes where the message came from"

  fun apply(h: TestHelper) ? =>
    let reg = _Fixture.libera()?

    // A channel message is answered in the channel.
    match reg.reply_to(_Fixture.line(":a!u@h PRIVMSG #ponylang :hi")?)
    | let c: Channel => h.assert_eq[String]("#ponylang", c.display())
    else h.fail("a channel message should be answered in the channel")
    end

    // A direct message is answered to the sender, not to the bot itself.
    match reg.reply_to(_Fixture.line(":alice!u@h PRIVMSG pingbot :hi")?)
    | let n: Nick => h.assert_eq[String]("alice", n.display())
    else h.fail("a direct message should be answered to its sender")
    end

    // A status-message prefix still names the channel.
    match reg.reply_to(_Fixture.line(":a!u@h PRIVMSG @#ponylang :hi")?)
    | let c: Channel => h.assert_eq[String]("#ponylang", c.display())
    else h.fail("@#chan should resolve to the channel")
    end

    // Never answer a NOTICE: that is how two bots flood each other.
    h.assert_true(
      reg.reply_to(_Fixture.line(":a!u@h NOTICE #ponylang :hi")?) is None)

    // Nothing to answer when the server itself spoke.
    h.assert_true(
      reg.reply_to(_Fixture.line(":irc.example.org PRIVMSG pingbot :hi")?)
        is None)

    // Not addressed to us and not a channel.
    h.assert_true(
      reg.reply_to(_Fixture.line(":a!u@h PRIVMSG someoneelse :hi")?) is None)

class \nodoc\ iso _TestRegistrationIsupport is UnitTest
  fun name(): String => "registration/channel types come from the server"

  fun apply(h: TestHelper) ? =>
    let reg = _Fixture.libera()?

    h.assert_true(reg.is_channel_name("#ponylang"))
    h.assert_true(reg.is_channel_name("&local"))
    h.assert_false(reg.is_channel_name("+notachannel"))
    h.assert_false(reg.is_channel_name("red"))

    match reg.isupport("NICKLEN")
    | let v: String val => h.assert_eq[U64](30, Isupport.count(v, 9))
    | None => h.fail("NICKLEN should be present")
    end

    h.assert_true(reg.isupport("ABSENT") is None)
    h.assert_true(reg.cap_enabled("server-time"))
    h.assert_false(reg.cap_enabled("sasl"))
    h.assert_eq[U32](1, reg.generation())
