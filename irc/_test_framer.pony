use "pony_test"
use "pony_check"

primitive \nodoc\ _Bytes
  fun of(s: String val): Array[U8] iso^ =>
    let out = recover iso Array[U8] end
    out.undefined(s.size())
    out.copy_from(s.array(), 0, 0, s.size())
    consume out

class \nodoc\ iso _TestFramerSplits is UnitTest
  fun name(): String => "framer/splits on CRLF and on a bare LF"

  fun apply(h: TestHelper) =>
    let f = _Framer(8703)
    f.feed(_Bytes.of("PING :one\r\nPING :two\nPING :three\r\n"))

    h.assert_eq[String]("PING :one", _drain(f, h))
    h.assert_eq[String]("PING :two", _drain(f, h))
    h.assert_eq[String]("PING :three", _drain(f, h))

    // Nothing left: the signal to stop reading and wait.
    h.assert_true(f.line() is None)
    h.assert_eq[USize](0, f.buffered())

  fun _drain(f: _Framer, h: TestHelper): String val =>
    match f.line()
    | let s: String val => s
    | let e: ParseFailure val => h.fail("unexpected: " + e.string()); ""
    | None => h.fail("expected a line"); ""
    end

class \nodoc\ iso _TestFramerIncremental is UnitTest
  fun name(): String => "framer/a line arriving one byte at a time still forms"

  fun apply(h: TestHelper) =>
    let f = _Framer(8703)
    let text = "PRIVMSG #ponylang :hello there\r\n"

    var i: USize = 0
    while i < (text.size() - 1) do
      f.feed(_Bytes.of(text.substring(i.isize(), (i + 1).isize())))
      // Incomplete: must report None rather than a partial line.
      h.assert_true(f.line() is None)
      i = i + 1
    end

    f.feed(_Bytes.of(text.substring((text.size() - 1).isize())))
    match f.line()
    | let s: String val =>
      h.assert_eq[String]("PRIVMSG #ponylang :hello there", s)
    else
      h.fail("the last byte should complete the line")
    end

class \nodoc\ iso _TestFramerTooLong is UnitTest
  fun name(): String => "framer/an over-long line is reported once, then skipped"

  fun apply(h: TestHelper) =>
    let f = _Framer(32)

    // No terminator in sight and past the bound.
    f.feed(_Bytes.of("x" * 64))
    match f.line()
    | let e: ParseFailure val => None
    else h.fail("should report the line as too long")
    end

    // Reported once, not once per read.
    f.feed(_Bytes.of("y" * 64))
    h.assert_true(f.line() is None)

    // The rest of the bad line is discarded and the next one is clean.
    f.feed(_Bytes.of("zzz\r\nPING :ok\r\n"))
    match f.line()
    | let s: String val => h.assert_eq[String]("PING :ok", s)
    else h.fail("the next line should be delivered")
    end

class \nodoc\ iso _TestFramerBounded is UnitTest
  fun name(): String => "framer/a server with no terminator cannot grow the buffer"

  fun apply(h: TestHelper) =>
    let f = _Framer(64)
    var i: USize = 0
    while i < 100 do
      f.feed(_Bytes.of("x" * 64))
      f.line()
      i = i + 1
    end
    h.assert_true(f.buffered() <= 64,
      "buffered " + f.buffered().string() + " bytes past the bound")

class \nodoc\ iso _PropFramerChunking is Property1[USize]
  """
  Where the reads happen to split does not change the lines that come out.
  """
  fun name(): String => "framer/property: chunk boundaries do not matter"

  fun gen(): Generator[USize] => Generators.usize(1, 40)

  fun property(chunk: USize, h: PropertyHelper) =>
    let text = "PING :a\r\nPRIVMSG #c :hello there\r\n:s 001 bot :Welcome\r\n"
    let f = _Framer(8703)
    let got = Array[String val]

    var i: USize = 0
    while i < text.size() do
      let stop = (i + chunk).min(text.size())
      f.feed(_Bytes.of(text.substring(i.isize(), stop.isize())))
      i = stop

      var more = true
      while more do
        match f.line()
        | let s: String val => got.push(s)
        | let e: ParseFailure val => h.fail("unexpected failure")
        | None => more = false
        end
      end
    end

    h.assert_eq[USize](3, got.size())
    try
      h.assert_eq[String]("PING :a", got(0)?)
      h.assert_eq[String]("PRIVMSG #c :hello there", got(1)?)
      h.assert_eq[String](":s 001 bot :Welcome", got(2)?)
    else
      h.fail("wrong number of lines")
    end
