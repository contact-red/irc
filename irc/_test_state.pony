use "pony_test"

class \nodoc\ _FakeSession is _Session
  """
  Drives a protocol state with no actor, no socket and no scheduler.

  This is what the `_Session` seam exists for: an actor held from outside is
  `tag`, so a state that took the connection directly could only be exercised
  end to end against a real server.
  """
  let _config: IRCConfig val
  embed written: Array[String val] = Array[String val]
  embed queued: Array[String val] = Array[String val]
  embed dropped: Array[String val] = Array[String val]
  var state_name: String val = "connecting"
  var deadline_armed: Bool = false
  var reg: (Registration val | None) = None
  var registered_with: (Registration val | None) = None
  var ended_because: (EndedBecause | None) = None
  var ended_detail: String val = ""
  var ended_plan: (_RetryPlan | None) = None

  new ref create(config': IRCConfig val) =>
    _config = config'

  fun config(): IRCConfig val => _config
  fun generation(): U32 => 1

  fun ref write_now(l: Line val) =>
    written.push(String.from_array(l.bytes()))

  fun ref enqueue(command: String val, group: Array[Line val] val) =>
    for l in group.values() do
      queued.push(String.from_array(l.bytes()))
    end

  fun ref transition(next: _State) =>
    state_name = next.name()

  fun ref arm_deadline(millis: U64) => deadline_armed = true
  fun ref cancel_deadline() => deadline_armed = false

  fun ref registration(): (Registration val | None) => reg
  fun ref set_registration(r: Registration val) => reg = r

  fun ref emit_registered(r: Registration val) => registered_with = r
  fun ref emit_dropped(what: Dropped) => dropped.push(what.string())

  fun ref finish(because: EndedBecause, detail: String val,
    plan: _RetryPlan)
  =>
    ended_because = because
    ended_detail = detail
    ended_plan = plan

  fun ref wrote(fragment: String val): Bool =>
    for w in written.values() do
      if w.contains(fragment) then return true end
    end
    false

primitive \nodoc\ _Config
  fun apply(h: TestHelper, nicks: Array[String val] val =
    ["pingbot"; "pingbot_"]): IRCConfig val ?
  =>
    IRCConfigs(h.env.root, "irc.example.org", "6667", NoTLS, nicks)
      as IRCConfig val

  fun line(text: String val): Message val ? =>
    Parse(text) as Message val

class \nodoc\ iso _TestStateRegisters is UnitTest
  fun name(): String => "state/registration sends the handshake and settles"

  fun apply(h: TestHelper) ? =>
    let s = _FakeSession(_Config(h)?)
    let r = _Registering(s)

    h.assert_true(s.wrote("CAP LS 302"), "should negotiate capabilities")
    h.assert_true(s.wrote("NICK pingbot"), "should send the first nickname")
    h.assert_true(s.wrote("USER pingbot"), "should send USER")
    h.assert_true(s.deadline_armed, "registration should be time limited")

    // No capabilities offered that we want: negotiation ends.
    r.on_line(s, _Config.line(":s CAP * LS :sasl multi-prefix")?)
    h.assert_true(s.wrote("CAP END"), "should end negotiation")

    r.on_line(s, _Config.line(":s 001 pingbot :Welcome")?)
    h.assert_eq[String]("settling", s.state_name)

class \nodoc\ iso _TestStateNickFallback is UnitTest
  fun name(): String => "state/a taken nickname walks the configured list"

  fun apply(h: TestHelper) ? =>
    let s = _FakeSession(_Config(h)?)
    let r = _Registering(s)

    r.on_line(s, _Config.line(":s 433 * pingbot :Nickname is already in use")?)
    h.assert_true(s.wrote("NICK pingbot_"), "should try the next nickname")

    // Exhausted: stopping is honest, and retrying would change nothing.
    r.on_line(s, _Config.line(":s 433 * pingbot_ :Nickname is already in use")?)
    h.assert_true(s.ended_because is AuthRejected)
    h.assert_true(s.ended_plan is _NeverRetry)

class \nodoc\ iso _TestStateFatalNumerics is UnitTest
  fun name(): String => "state/a refused password stops, a throttle waits"

  fun apply(h: TestHelper) ? =>
    let bad_password = _FakeSession(_Config(h)?)
    _Registering(bad_password).on_line(bad_password,
      _Config.line(":s 464 * :Password incorrect")?)
    h.assert_true(bad_password.ended_because is AuthRejected)
    h.assert_true(bad_password.ended_plan is _NeverRetry,
      "retrying a rejected password earns a ban")

    let banned = _FakeSession(_Config(h)?)
    _Registering(banned).on_line(banned,
      _Config.line(":s 465 * :You are banned")?)
    h.assert_true(banned.ended_plan is _NeverRetry)

    // "Trying to reconnect too fast" is a request to wait, not to stop. A bot
    // that treats it as fatal dies because it was asked to slow down.
    let throttled = _FakeSession(_Config(h)?)
    _Registering(throttled).on_line(throttled,
      _Config.line("ERROR :Closing Link: Trying to reconnect too fast.")?)
    h.assert_true(throttled.ended_because is NetworkFailure)
    h.assert_true(throttled.ended_plan is _RetryAfterFloor)

class \nodoc\ iso _TestStateSettles is UnitTest
  fun name(): String => "state/isupport fixes the casemapping, then registers"

  fun apply(h: TestHelper) ? =>
    let s = _FakeSession(_Config(h)?)
    let me = Nicks("pingbot") as Nick
    let settling = _Settling(s, me, [])

    settling.on_line(s,
      _Config.line(":s 005 pingbot CHANTYPES=#& CASEMAPPING=rfc1459 :are supported")?)

    // Still settling: more 005 lines may follow.
    h.assert_true(s.registered_with is None)

    // The first line that is not a 005 ends the burst.
    settling.on_line(s, _Config.line(":s 375 pingbot :- Message of the day")?)

    match s.registered_with
    | let reg: Registration val =>
      h.assert_eq[String]("pingbot", reg.me().display())
      h.assert_true(reg.same(Nicks("Foo[]") as Nick, Nicks("foo{}") as Nick),
        "the announced casemapping should be in force")
      h.assert_eq[String]("#&",
        match reg.isupport("CHANTYPES") | let v: String val => v else "" end)
    | None => h.fail("should have registered")
    end
    h.assert_eq[String]("live", s.state_name)

class \nodoc\ iso _TestStateNoIsupport is UnitTest
  fun name(): String => "state/a server sending no isupport still registers"

  fun apply(h: TestHelper) ? =>
    let s = _FakeSession(_Config(h)?)
    let settling = _Settling(s, Nicks("pingbot") as Nick, [])

    // The deadline is the other way out. Without it a bot would sit connected
    // and never registered, with nothing timing out, looking healthy.
    settling.on_deadline(s)

    h.assert_true(s.registered_with isnt None, "the deadline should register")
    h.assert_eq[String]("live", s.state_name)

class \nodoc\ iso _TestStatePingAlways is UnitTest
  fun name(): String => "state/every phase answers a PING at once"

  fun apply(h: TestHelper) ? =>
    let ping = _Config.line("PING :token123")?

    let phases = [as _State: _Connecting; _Live; _Waiting; _Stopped]

    for st in phases.values() do
      let s = _FakeSession(_Config(h)?)
      st.on_ping(s, ping)
      h.assert_true(s.wrote("PONG :token123"),
        "a PING went unanswered in one phase")
      h.assert_eq[USize](0, s.queued.size(),
        "a PONG must not wait behind paced messages")
    end

class \nodoc\ iso _TestStateSendGating is UnitTest
  fun name(): String => "state/sends are refused before registration, queued after"

  fun apply(h: TestHelper) ? =>
    let group: Array[Line val] val =
      [Wire.command("PRIVMSG", ["#c"], "hi") as Line val]

    let early = _FakeSession(_Config(h)?)
    _Connecting.user_send(early, "PRIVMSG", group)
    h.assert_eq[USize](0, early.queued.size())
    h.assert_eq[USize](1, early.dropped.size(),
      "a refused send must be reported, not silently discarded")

    let live = _FakeSession(_Config(h)?)
    _Live.user_send(live, "PRIVMSG", group)
    h.assert_eq[USize](1, live.queued.size())
    h.assert_eq[USize](0, live.dropped.size())
