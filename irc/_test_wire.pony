use "pony_test"
use "pony_check"

class \nodoc\ iso _TestWireBasic is UnitTest
  fun name(): String => "wire/builds an ordinary command"

  fun apply(h: TestHelper) =>
    match Wire.command("PRIVMSG", ["#ponylang"], "hello there")
    | let l: Line val =>
      h.assert_eq[String]("PRIVMSG #ponylang :hello there\r\n",
        String.from_array(l.bytes()))
      h.assert_eq[String]("PRIVMSG", l.command())
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestWireTrailingSlot is UnitTest
  fun name(): String => "wire/an empty trailing parameter is not the same as none"

  fun apply(h: TestHelper) =>
    // TOPIC #c :  clears the topic. TOPIC #c  asks what it is. A design with
    // no trailing slot silently turns the first into the second.
    match Wire.command("TOPIC", ["#c"], "")
    | let l: Line val =>
      h.assert_eq[String]("TOPIC #c :\r\n", String.from_array(l.bytes()))
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

    match Wire.command("TOPIC", ["#c"])
    | let l: Line val =>
      h.assert_eq[String]("TOPIC #c\r\n", String.from_array(l.bytes()))
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestWireRejects is UnitTest
  fun name(): String => "wire/refuses a line the server would misread"

  fun apply(h: TestHelper) =>
    // A middle parameter holding a space would silently become two
    // parameters, which the server misreads rather than rejects.
    h.assert_true(Wire.command("KICK", ["#c"; "a b"]) isnt None)
    match Wire.command("KICK", ["#c"; "a b"])
    | let l: Line val => h.fail("accepted a space in a middle parameter")
    end

    match Wire.command("KICK", ["#c"; ":oops"])
    | let l: Line val => h.fail("accepted a leading colon in a middle parameter")
    end

    match Wire.command("KICK", ["#c"; ""])
    | let l: Line val => h.fail("accepted an empty middle parameter")
    end

    match Wire.command("", ["#c"])
    | let l: Line val => h.fail("accepted an empty command")
    end

    match Wire.command("PR!VMSG", ["#c"])
    | let l: Line val => h.fail("accepted a command that is not a word")
    end

    // The whole point: a stranger's text cannot end the line and start another.
    match Wire.command("PRIVMSG", ["#c"], "bye\r\nJOIN #evil")
    | let l: Line val => h.fail("accepted a CRLF in the trailing parameter")
    end

class \nodoc\ iso _TestWireTags is UnitTest
  fun name(): String => "wire/only client-only tags may be sent, and are escaped"

  fun apply(h: TestHelper) =>
    match Wire.command("PRIVMSG", ["#c"], "hi", [("+note", "a b;c")])
    | let l: Line val =>
      h.assert_eq[String]("@+note=a\\sb\\:c PRIVMSG #c :hi\r\n",
        String.from_array(l.bytes()))
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

    // A server-attested tag is the server's to assert, not ours to claim.
    match Wire.command("PRIVMSG", ["#c"], "hi", [("account", "red")])
    | let l: Line val => h.fail("accepted a non-client tag")
    end

    // Escaping is what stops a reflected tag from carrying a real newline.
    match Wire.command("PRIVMSG", ["#c"], "hi", [("+x", "a\r\nJOIN #evil")])
    | let l: Line val =>
      let text = String.from_array(l.bytes())
      h.assert_false(text.contains("\r\nJOIN"))
      h.assert_true(text.contains("\\r\\n"))
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestWireCtcp is UnitTest
  fun name(): String => "wire/CTCP wraps, and a reply is a NOTICE"

  fun apply(h: TestHelper) =>
    let target =
      match Channels("#c") | let c: Channel => c else h.fail("bad channel"); return end

    match Wire.action(target, "waves")
    | let l: Line val =>
      h.assert_eq[String]("PRIVMSG #c :\x01ACTION waves\x01\r\n",
        String.from_array(l.bytes()))
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

    // Answering a CTCP with a PRIVMSG is how two bots flood each other off.
    match Wire.ctcp_reply(target, "VERSION", "ponybot 1.0")
    | let l: Line val =>
      h.assert_eq[String]("NOTICE", l.command())
    | let e: EncodeError => h.fail("rejected: " + e.string())
    end

class \nodoc\ iso _TestWireSplits is UnitTest
  fun name(): String => "wire/long text splits, newlines split, control bytes go"

  fun apply(h: TestHelper) =>
    let target =
      match Channels("#c") | let c: Channel => c else h.fail("bad channel"); return end

    // Embedded newlines become separate messages, not a second command.
    let lines = Wire.privmsg(target, "one\ntwo\r\nthree")
    h.assert_eq[USize](3, lines.size())

    // A stranger's text cannot forge an action in the bot's name.
    let forged = Wire.privmsg(target, "\x01ACTION resigns\x01")
    h.assert_eq[USize](1, forged.size())
    try
      h.assert_false(String.from_array(forged(0)?.bytes()).contains("\x01"))
    else h.fail("no line produced") end

    // Over-long text splits rather than being truncated by the server.
    let long_text = recover val String(600) .> append("x" * 600) end
    let split = Wire.privmsg(target, long_text, 100)
    h.assert_true(split.size() >= 6)
    for l in split.values() do
      h.assert_true(l.size() <= (100 + 32))
    end

    // A trailing newline must not cost a line and a pacing slot to say nothing.
    h.assert_eq[USize](1, Wire.privmsg(target, "hi\n").size())

    // Empty text is still one message, because the bot asked for one.
    h.assert_eq[USize](1, Wire.privmsg(target, "").size())

class \nodoc\ iso _PropNoInjection is Property1[String]
  """
  The headline safety claim, over arbitrary bytes: nothing a stranger can say
  reaches the wire as a second line.
  """
  fun name(): String => "wire/property: no text can inject a second line"

  fun gen(): Generator[String] =>
    Generators.byte_string(Generators.u8(), 0, 300)

  fun property(sample: String, h: PropertyHelper) =>
    let text: String val = sample.clone()
    let target =
      match Channels("#c") | let c: Channel => c else return end

    for l in Wire.privmsg(target, text).values() do
      let bytes = l.bytes()
      h.assert_true(bytes.size() >= 2, "a line must at least terminate")

      try
        h.assert_eq[U8]('\r', bytes(bytes.size() - 2)?)
        h.assert_eq[U8]('\n', bytes(bytes.size() - 1)?)

        var i: USize = 0
        while i < (bytes.size() - 2) do
          let c = bytes(i)?
          h.assert_false((c == '\r') or (c == '\n') or (c == 0x00),
            "a raw CR, LF or NUL reached the wire")
          i = i + 1
        end
      else
        h.fail("could not read the encoded line")
      end
    end

class \nodoc\ iso _PropSplitRoundTrips is Property1[String]
  """Every line a split produces is a well-formed PRIVMSG to the right place."""
  fun name(): String => "wire/property: split output parses back"

  fun gen(): Generator[String] =>
    Generators.byte_string(Generators.u8(), 0, 300)

  fun property(sample: String, h: PropertyHelper) =>
    let text: String val = sample.clone()
    let target =
      match Channels("#c") | let c: Channel => c else return end

    for l in Wire.privmsg(target, text, 80).values() do
      let on_wire = String.from_array(l.bytes())
      // Parse wants the line without its terminator, as the framer hands it.
      match Parse(on_wire.substring(0, on_wire.size().isize() - 2))
      | let m: Message val =>
        h.assert_eq[String]("PRIVMSG", m.command())
        try
          h.assert_eq[String]("#c", m.params()(0)?)
        else
          h.fail("no target parameter survived the round trip")
        end
      | let e: ParseFailure =>
        h.fail("a line we built did not parse: " + e.string())
      end
    end
