use "pony_test"

actor \nodoc\ _ExampleBot is IRCNotify
  """
  A bot, written the way a bot author writes one.

  Here to prove the shape works: everything it touches is public API, so a
  bot's own package can do exactly this.
  """
  let _home: Channel
  let _owner: String val
  var _greeted: USize = 0

  new create(home: Channel, owner: String val) =>
    _home = home
    _owner = owner

  be irc_registered(irc: IRCSend tag, reg: Registration val) =>
    irc.join([_home])
    _greeted = _greeted + 1

  be irc_message(irc: IRCSend tag, m: Message val,
    reg: (Registration val | None))
  =>
    let r = match reg | let x: Registration val => x else return end
    if m.command() != "PRIVMSG" then return end

    match m.trailing()
    | "!ping" =>
      match r.reply_to(m)
      | let t: Target => irc.privmsg(t, "pong")
      end
    | "!shutdown" =>
      // Only the owner, compared by the server's rule rather than by bytes.
      match m.nick()
      | let who: Nick =>
        if r.same_text(who.display(), _owner) then
          irc.quit("owner asked")
        end
      end
    end

  be irc_unparseable(irc: IRCSend tag, raw: String val, why: ParseFailure val) =>
    None

  be irc_dropped(irc: IRCSend tag, what: Dropped) => None
  be irc_session(irc: IRCSend tag, ended: SessionEnded val) => None
  be irc_stopped(irc: IRCSend tag, ended: SessionEnded val) => None

actor \nodoc\ _RecordingSend is IRCSend
  """
  Stands in for a connection so a test can see what a bot asked for.

  `IRCSend` is what every callback receives, and `IRC` satisfies it
  structurally, so nothing here needs the real thing.
  """
  let _h: TestHelper
  let _expected: Array[String val] val
  var _seen: USize = 0

  new create(h: TestHelper, expected: Array[String val] val) =>
    _h = h
    _expected = expected

  be _record(what: String val) =>
    try
      _h.assert_eq[String](_expected(_seen)?, what)
    else
      _h.fail("unexpected: " + what)
    end
    _seen = _seen + 1
    if _seen == _expected.size() then
      _h.complete(true)
    end

  be privmsg(target: Target, text: String val) =>
    _record("privmsg " + _name(target) + " " + text)

  be notice(target: Target, text: String val) =>
    _record("notice " + _name(target) + " " + text)

  be action(target: Target, text: String val) =>
    _record("action " + _name(target) + " " + text)

  be join(channels: Array[Channel] val, keys: Array[String val] val = []) =>
    let names = recover iso Array[String val] end
    for c in channels.values() do names.push(c.display()) end
    _record("join " + ",".join((consume names).values()))

  be part(channels: Array[Channel] val, reason: String val = "") => None
  be nick(n: Nick) => None
  be send(line: Line val) => None
  be quit(reason: String val = "") => _record("quit " + reason)
  be disconnect() => None

  fun _name(t: Target): String val =>
    match t
    | let n: Nick => n.display()
    | let c: Channel => c.display()
    end

class \nodoc\ iso _TestBotWithoutNetwork is UnitTest
  """
  A bot author's own test: no socket, no server, no waiting.

  Before the codec and `IRCSend` were public this was impossible -- the only
  source of a `Message` was a live connection, so the casemapping logic that
  this package exists to get right could not be checked by the person writing
  it.
  """
  fun name(): String => "bot/a bot can be tested with no network"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    let home = Channels("#ponylang") as Channel
    let bot = _ExampleBot(home, "Red[]")

    let session = _RecordingSend(h,
      [ "join #ponylang"
        "privmsg #ponylang pong"
        "privmsg alice pong"
        "quit owner asked" ])

    let reg = Registration(
      Nicks("pingbot") as Nick,
      CasemapRfc1459,
      [("CHANTYPES", "#&"); ("STATUSMSG", "@+")])

    bot.irc_registered(session, reg)

    // A channel message is answered in the channel.
    bot.irc_message(session,
      Parse(":alice!u@h PRIVMSG #ponylang :!ping") as Message val, reg)

    // A direct message is answered to whoever sent it.
    bot.irc_message(session,
      Parse(":alice!u@h PRIVMSG pingbot :!ping") as Message val, reg)

    // The owner is `Red[]`; on this server `red{}` is the same person. A
    // comparison written with `==` would refuse this and the shutdown would
    // silently never happen.
    bot.irc_message(session,
      Parse(":red{}!u@h PRIVMSG pingbot :!shutdown") as Message val, reg)
