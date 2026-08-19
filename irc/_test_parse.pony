use "pony_test"

class \nodoc\ iso _TestParseBasic is UnitTest
  fun name(): String => "parse/an ordinary channel message"

  fun apply(h: TestHelper) =>
    match Parse(":red!u@example.org PRIVMSG #ponylang :hello there")
    | let m: Message val =>
      h.assert_eq[String]("PRIVMSG", m.command())
      h.assert_eq[String]("red!u@example.org", m.source())
      h.assert_eq[USize](2, m.params().size())
      try h.assert_eq[String]("#ponylang", m.params()(0)?) else h.fail("param 0") end
      h.assert_eq[String]("hello there", m.trailing())

      match m.nick()
      | let n: Nick => h.assert_eq[String]("red", n.display())
      | None => h.fail("no nick parsed from the prefix")
      end

      match m.user()
      | let u: String val => h.assert_eq[String]("u", u)
      | None => h.fail("no user parsed")
      end

      match m.host()
      | let hst: String val => h.assert_eq[String]("example.org", hst)
      | None => h.fail("no host parsed")
      end
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestParseTrailing is UnitTest
  fun name(): String => "parse/the trailing parameter keeps spaces and colons"

  fun apply(h: TestHelper) =>
    match Parse("PRIVMSG #c ::-) hello: world")
    | let m: Message val =>
      h.assert_eq[String](":-) hello: world", m.trailing())
      h.assert_eq[USize](2, m.params().size())
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

    // No trailing marker: parameters split on spaces.
    match Parse("MODE #c +o red")
    | let m: Message val =>
      h.assert_eq[USize](3, m.params().size())
      h.assert_eq[String]("red", m.trailing())
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestParseNumeric is UnitTest
  fun name(): String => "parse/numeric replies are recognised as numbers"

  fun apply(h: TestHelper) =>
    match Parse(":irc.example.org 001 pingbot :Welcome")
    | let m: Message val =>
      h.assert_eq[String]("001", m.command())
      match m.numeric()
      | let n: U16 => h.assert_eq[U16](1, n)
      | None => h.fail("001 should be numeric")
      end
      // A server prefix is not a nickname.
      h.assert_true(m.nick() is None)
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

    match Parse("PRIVMSG #c :hi")
    | let m: Message val => h.assert_true(m.numeric() is None)
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestParseTags is UnitTest
  fun name(): String => "parse/message tags are unescaped on demand"

  fun apply(h: TestHelper) =>
    match Parse("@account=red;+custom=a\\sb\\:c PRIVMSG #c :hi")
    | let m: Message val =>
      match m.tag_value("account")
      | let v: String val => h.assert_eq[String]("red", v)
      | None => h.fail("account tag missing")
      end

      // \s is a space and \: is a semicolon.
      match m.tag_value("+custom")
      | let v: String val => h.assert_eq[String]("a b;c", v)
      | None => h.fail("+custom tag missing")
      end

      h.assert_true(m.tag_value("absent") is None)
      h.assert_eq[USize](2, m.tags().size())
      h.assert_eq[String]("PRIVMSG", m.command())
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

    // A tag with no value is present and empty, not absent.
    match Parse("@bot PRIVMSG #c :hi")
    | let m: Message val =>
      match m.tag_value("bot")
      | let v: String val => h.assert_eq[String]("", v)
      | None => h.fail("valueless tag should be present")
      end
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestParseCtcp is UnitTest
  fun name(): String => "parse/CTCP is unwrapped from the message text"

  fun apply(h: TestHelper) =>
    match Parse(":red!u@h PRIVMSG #c :\x01ACTION waves\x01")
    | let m: Message val =>
      match m.ctcp()
      | let c: Ctcp val =>
        h.assert_eq[String]("ACTION", c.command())
        h.assert_eq[String]("waves", c.argument())
      | None => h.fail("ACTION should be CTCP")
      end
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

    // Real clients omit the closing byte.
    match Parse(":red!u@h PRIVMSG #c :\x01VERSION")
    | let m: Message val =>
      match m.ctcp()
      | let c: Ctcp val =>
        h.assert_eq[String]("VERSION", c.command())
        h.assert_eq[String]("", c.argument())
      | None => h.fail("an unterminated CTCP should still be read")
      end
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

    // Ordinary text is not CTCP.
    match Parse(":red!u@h PRIVMSG #c :hello")
    | let m: Message val => h.assert_true(m.ctcp() is None)
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestParseServerTime is UnitTest
  fun name(): String => "parse/server-time gives a posix instant"

  fun apply(h: TestHelper) =>
    match Parse("@time=2026-08-17T12:00:00.500Z PRIVMSG #c :hi")
    | let m: Message val =>
      match m.at()
      | let t: I64 =>
        // 2026-08-17T12:00:00Z is 1786968000; the tag adds 500ms.
        h.assert_eq[I64](1786968000500, t)
      | None => h.fail("server-time should decode")
      end
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

    match Parse("PRIVMSG #c :hi")
    | let m: Message val => h.assert_true(m.at() is None)
    | let e: ParseFailure => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestParseRejects is UnitTest
  fun name(): String => "parse/malformed lines are rejected, not guessed at"

  fun apply(h: TestHelper) =>
    let bad =
      [ ("", "empty")
        ("   ", "only spaces")
        ("@only=tags", "tags with no command")
        (":prefix", "prefix with no command")
        ("PR!VMSG #c :hi", "command that is not a word") ]

    for (line, why) in bad.values() do
      match Parse(line)
      | let m: Message val => h.fail("accepted " + why)
      | let e: ParseFailure => None
      end
    end

    // Sixteen parameters is one too many.
    let many = recover val String .> append("CMD") end
    var over = recover iso String .> append(many) end
    var i: USize = 0
    while i < 16 do
      over.append(" p")
      i = i + 1
    end
    match Parse(consume over)
    | let m: Message val => h.fail("accepted more than fifteen parameters")
    | let e: ParseFailure => None
    end
