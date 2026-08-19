use "pony_test"

primitive \nodoc\ _Lines
  fun one(text: String val): Line val ? =>
    Wire.command("PRIVMSG", ["#c"], text) as Line val

  fun group(count: USize): Array[Line val] val ? =>
    let out = recover iso Array[Line val] end
    var i: USize = 0
    while i < count do
      out.push(one(i.string())?)
      i = i + 1
    end
    consume out

class \nodoc\ iso _TestOutboxPaces is UnitTest
  fun name(): String => "outbox/a burst goes at once, the rest waits"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(3, 2_000, 32), start)
    o.push(_Lines.group(10)?)

    // The burst allowance, and no more.
    h.assert_eq[USize](3, o.ready(start).size())
    h.assert_eq[USize](0, o.ready(start).size())

    // Part of an interval buys nothing.
    h.assert_eq[USize](0, o.ready(start + 1_999).size())

    // One line per interval.
    h.assert_eq[USize](1, o.ready(start + 2_000).size())
    h.assert_eq[USize](2, o.ready(start + 6_000).size())

    h.assert_true(o.pending())

class \nodoc\ iso _TestOutboxEarnsWhileIdle is UnitTest
  """
  The burst comes back when the connection is quiet.

  It used to be spendable once per connection: allowance was granted by a
  timer that only ran while the queue had something in it, so the first
  burst left the bucket empty and nothing ever refilled it. However long a
  bot then sat idle, its next line waited a full interval.
  """
  fun name(): String => "outbox/a quiet connection earns its burst back"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(3, 2_000, 32), start)

    o.push(_Lines.group(3)?)
    h.assert_eq[USize](3, o.ready(start).size())

    // Quiet for a while, with nothing queued to keep any timer alive.
    let later = start + 20_000
    o.push(_Lines.group(5)?)
    h.assert_eq[USize](3, o.ready(later).size())

class \nodoc\ iso _TestOutboxEarnsNoMoreThanTheBurst is UnitTest
  """
  Idle time is not saved up. An hour quiet does not buy an hour of talking,
  which is what the burst allowance exists to bound.
  """
  fun name(): String => "outbox/idle time does not accumulate past the burst"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(3, 2_000, 32), start)
    o.push(_Lines.group(20)?)

    // An hour of quiet, then everything offered at once.
    let later = start + 3_600_000
    h.assert_eq[USize](3, o.ready(later).size())
    h.assert_eq[USize](0, o.ready(later).size())

class \nodoc\ iso _TestOutboxKeepsTheRemainder is UnitTest
  """
  A part-elapsed interval is kept rather than discarded.

  The mark moves by what was earned, not to the time it was asked. Moving
  it to the asking time would throw away however much of the next interval
  had already passed -- and `ready` is called on every line a bot offers,
  so a bot asking often would send strictly slower than the rate allows.

  Catching that needs a question asked between two intervals rather than on
  one: on the boundary the two rules agree, and a test that only ever asks
  on the boundary passes under either.
  """
  fun name(): String => "outbox/a part-elapsed interval is not thrown away"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(1, 1_000, 32), start)
    o.push(_Lines.group(4)?)

    h.assert_eq[USize](1, o.ready(start).size())

    // One and a half intervals: one line is earned, and half an interval
    // is owed and must be kept.
    h.assert_eq[USize](1, o.ready(start + 1_500).size())

    // Half an interval later the second is complete, and the kept half is
    // what completes it.
    h.assert_eq[USize](1, o.ready(start + 2_000).size())

class \nodoc\ iso _TestOutboxUrgent is UnitTest
  fun name(): String => "outbox/an urgent line passes everything and spends no token"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(1, 2_000, 32), start)
    o.push(_Lines.group(4)?)

    // Spend the single token.
    h.assert_eq[USize](1, o.ready(start).size())
    h.assert_eq[USize](0, o.ready(start).size())

    // A PONG must still get out with no tokens left.
    o.urgent(_Lines.one("pong")?)
    h.assert_eq[USize](1, o.ready(start).size())

class \nodoc\ iso _TestOutboxAtomic is UnitTest
  fun name(): String => "outbox/a message is queued whole or refused whole"

  fun apply(h: TestHelper) ? =>
    let o = _Outbox(SendRate(0, 2_000, 4), 10_000)

    // A message longer than the whole queue can never be accepted.
    match o.push(_Lines.group(5)?)
    | let reason: String val => None
    | None => h.fail("a message longer than the queue should be refused")
    end
    h.assert_eq[USize](0, o.size())

    // Two that fit.
    o.push(_Lines.group(2)?)
    o.push(_Lines.group(2)?)
    h.assert_eq[USize](4, o.size())

    // A third pushes the oldest out rather than truncating anything.
    o.push(_Lines.group(2)?)
    h.assert_eq[USize](4, o.size())

class \nodoc\ iso _TestOutboxOrder is UnitTest
  fun name(): String => "outbox/pacing never reorders what survives"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(1, 2_000, 32), start)
    var i: USize = 0
    while i < 5 do
      o.push([_Lines.one(i.string())?])
      i = i + 1
    end

    let seen = Array[String val]
    var guard: USize = 0
    var at: U64 = start
    while (o.size() > 0) and (guard < 50) do
      for l in o.ready(at).values() do
        seen.push(String.from_array(l.bytes()))
      end
      at = at + 2_000
      guard = guard + 1
    end

    h.assert_eq[USize](5, seen.size())
    var n: USize = 0
    while n < 5 do
      h.assert_true(seen(n)?.contains(":" + n.string() + "\r\n"),
        "line " + n.string() + " out of order")
      n = n + 1
    end

class \nodoc\ iso _TestOutboxClear is UnitTest
  fun name(): String => "outbox/nothing survives into the next connection"

  fun apply(h: TestHelper) ? =>
    let start: U64 = 10_000
    let o = _Outbox(SendRate(0, 2_000, 32), start)
    o.push(_Lines.group(3)?)
    o.urgent(_Lines.one("pong")?)

    h.assert_eq[USize](3, o.clear())
    h.assert_eq[USize](0, o.size())
    h.assert_false(o.pending())
    h.assert_eq[USize](0, o.ready(start).size())
