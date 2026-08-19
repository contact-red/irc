use "collections"

trait ref _State
  """
  One phase of a connection.

  Each phase is a separate class because the same input means different things
  in different phases: `433` walks the fallback nickname list before
  registration and is an ordinary message after it, `001` completes
  registration once and is a replay from a bouncer if it comes again, and a
  closed socket is a failed connection in one phase and a lost session in
  another.
  """
  fun name(): String

  fun ref on_line(s: _Session ref, m: Message val)
  fun ref on_connected(s: _Session ref) => None
  fun ref on_closed(s: _Session ref)
  fun ref on_deadline(s: _Session ref) => None

  fun ref user_send(s: _Session ref, command: String val,
    group: Array[Line val] val)
  =>
    """Refused unless the phase can send. Overridden by `_Live`."""
    s.emit_dropped(
      SendDropped._create(command, group.size(), "not connected"))

  fun ref on_ping(s: _Session ref, m: Message val) =>
    """
    Answer a PING at once, in every phase, ahead of anything queued.

    The one behaviour that is correct for every phase, which is why it is the
    only default here. A server that does not get its token back closes the
    connection.
    """
    match Wire.command("PONG", [], m.trailing())
    | let l: Line val => s.write_now(l)
    end

class ref _Connecting is _State
  """Waiting for the socket, and for the TLS handshake when there is one."""
  fun name(): String => "connecting"

  fun ref on_connected(s: _Session ref) =>
    s.transition(_Registering(s))

  fun ref on_line(s: _Session ref, m: Message val) => None

  fun ref on_closed(s: _Session ref) =>
    s.finish(NetworkFailure, "the connection closed before it opened",
      _RetryPromptly)

class ref _Registering is _State
  """
  From the first byte sent to `001`.

  Nothing the bot asks to send goes out here. Queuing it instead would let the
  bot's first message leave at an unpredictable moment, possibly under a
  different nickname than the one it believed it had.
  """
  var _nick_index: USize = 0
  var _requested: Array[String val] val = []
  var _acked: Array[String val] val = []
  var _cap_pending: Bool = false
  embed _offered: Array[String val] = Array[String val]

  new ref create(s: _Session ref) =>
    let c = s.config()
    s.arm_deadline(c.timeouts().registration_millis())

    match c.password()
    | let p: String val =>
      _send(s, Wire.command("PASS", [], p))
    end

    _cap_pending = true
    _send(s, Wire.command("CAP", ["LS"; "302"]))
    _send_nick(s, c)
    _send(s, Wire.command("USER", [c.user(); "0"; "*"], c.realname()))

  fun name(): String => "registering"

  fun ref on_closed(s: _Session ref) =>
    s.finish(NetworkFailure, "the connection closed during registration",
      _RetryPromptly)

  fun ref on_deadline(s: _Session ref) =>
    s.finish(ProtocolFailure, "registration did not complete in time",
      _RetryAfterFloor)

  fun ref on_line(s: _Session ref, m: Message val) =>
    match m.command()
    | "CAP" => _on_cap(s, m)
    | "ERROR" =>
      // Before registration this commonly means "you are reconnecting too
      // fast", which is a reason to wait rather than to stop for good.
      s.finish(NetworkFailure, "the server refused the connection: "
        + m.trailing(), _RetryAfterFloor)
    | "001" => _on_welcome(s, m)
    | "432" | "433" | "437" => _on_nick_unusable(s, m)
    | "464" =>
      s.finish(AuthRejected, "the server password was rejected", _NeverRetry)
    | "465" =>
      s.finish(AuthRejected, "this client is banned: " + m.trailing(),
        _NeverRetry)
    | "451" =>
      s.finish(ProtocolFailure, "the server said we had not registered",
        _RetryAfterFloor)
    end

  fun ref _on_welcome(s: _Session ref, m: Message val) =>
    s.cancel_deadline()
    let me =
      try
        match Nicks(m.params()(0)?)
        | let n: Nick => n
        | let e: InvalidName => return _bad_welcome(s)
        end
      else
        return _bad_welcome(s)
      end

    s.transition(_Settling(s, me, _acked))

  fun ref _bad_welcome(s: _Session ref) =>
    s.finish(ProtocolFailure, "the welcome carried no usable nickname",
      _RetryAfterFloor)

  fun ref _on_nick_unusable(s: _Session ref, m: Message val) =>
    let c = s.config()
    _nick_index = _nick_index + 1

    if _nick_index >= c.nicks().size() then
      s.finish(AuthRejected,
        "every configured nickname was refused", _NeverRetry)
      return
    end

    _send_nick(s, c)

  fun ref _send_nick(s: _Session ref, c: IRCConfig val) =>
    try
      _send(s, Wire.command("NICK", [c.nicks()(_nick_index)?]))
    end

  fun ref _on_cap(s: _Session ref, m: Message val) =>
    // CAP <target> <subcommand> [*] :<caps>
    let sub = try m.params()(1)? else return end

    match sub
    | "LS" =>
      for c in m.trailing().split(" ").values() do
        let token: String val = consume c
        if token.size() > 0 then
          // A capability may arrive as name=value; only the name matters here.
          _offered.push(try token.substring(0, token.find("=")?) else token end)
        end
      end

      // A `*` before the list means more lines follow.
      let more = try m.params()(2)? == "*" else false end
      if not more then
        _request(s)
      end
    | "ACK" =>
      _acked = _words(m.trailing())
      _end_cap(s)
    | "NAK" =>
      _end_cap(s)
    end

  fun ref _request(s: _Session ref) =>
    let wanted = s.config().capabilities()
    let ask = recover iso Array[String val] end

    for w in wanted.values() do
      for o in _offered.values() do
        if o == w then
          ask.push(w)
          break
        end
      end
    end

    let ask': Array[String val] val = consume ask
    if ask'.size() == 0 then
      _end_cap(s)
      return
    end

    _requested = ask'
    _send(s, Wire.command("CAP", ["REQ"], " ".join(ask'.values())))

  fun ref _end_cap(s: _Session ref) =>
    if _cap_pending then
      _cap_pending = false
      _send(s, Wire.command("CAP", ["END"]))
    end

  fun _words(text: String val): Array[String val] val =>
    let out = recover iso Array[String val] end
    for w in text.split(" ").values() do
      let word: String val = consume w
      if word.size() > 0 then
        out.push(word)
      end
    end
    consume out

  fun ref _send(s: _Session ref, built: (Line val | EncodeError)) =>
    match built
    | let l: Line val => s.write_now(l)
    | let e: EncodeError =>
      s.finish(ProtocolFailure,
        "a registration line could not be built: " + e.string(), _NeverRetry)
    end

class ref _Settling is _State
  """
  From `001` until the server's `005` tokens have arrived.

  The casemapping is fixed when this phase ends and does not change again for
  the connection, so no bot ever compares two names under a rule that is about
  to be replaced. The phase ends on the first line after a `005` that is not
  another `005`, or on a deadline, so a server that sends no `005` at all
  still registers.

  Sends are accepted here: the server considers the connection registered from
  `001`, and refusing them would be a lie.
  """
  let _me: Nick
  let _caps: Array[String val] val
  embed _tokens: Array[(String val, String val)] = Array[(String val, String val)]
  var _saw_isupport: Bool = false

  new ref create(s: _Session ref, me: Nick, caps: Array[String val] val) =>
    _me = me
    _caps = caps
    s.arm_deadline(s.config().timeouts().isupport_millis())

  fun name(): String => "settling"

  fun ref on_closed(s: _Session ref) =>
    s.finish(NetworkFailure, "the connection closed during registration",
      _RetryPromptly)

  fun ref on_deadline(s: _Session ref) =>
    _complete(s)

  fun ref user_send(s: _Session ref, command: String val,
    group: Array[Line val] val)
  =>
    s.enqueue(command, group)

  fun ref on_line(s: _Session ref, m: Message val) =>
    if m.command() == "005" then
      _saw_isupport = true
      _collect(m)
      return
    end

    if _saw_isupport or (m.command() == "376") or (m.command() == "422") then
      _complete(s)
    end

  fun ref _collect(m: Message val) =>
    let params = m.params()
    var i: USize = 1
    // The first parameter is our nickname and the last is a human-readable
    // trailer; everything between is a token.
    while (i + 1) < params.size() do
      try
        let token = params(i)?
        match token.find("=")?
        | let eq: ISize =>
          _tokens.push((token.substring(0, eq), token.substring(eq + 1)))
        end
      else
        try _tokens.push((params(i)?, "")) end
      end
      i = i + 1
    end

  fun ref _complete(s: _Session ref) =>
    s.cancel_deadline()

    let collected = recover iso Array[(String val, String val)] end
    for pair in _tokens.values() do
      collected.push(pair)
    end
    let collected': Array[(String val, String val)] val = consume collected

    var casemap: Casemap = CasemapAscii
    for (k, v) in collected'.values() do
      if k == "CASEMAPPING" then
        casemap = Casefold.of_token(v)
      end
    end

    let reg = Registration(_me, casemap, collected', _caps, s.generation())
    s.set_registration(reg)
    s.transition(_Live)
    s.emit_registered(reg)

class ref _Live is _State
  """A registered connection. Everything the bot sends is paced from here."""
  fun name(): String => "live"

  fun ref user_send(s: _Session ref, command: String val,
    group: Array[Line val] val)
  =>
    s.enqueue(command, group)

  fun ref on_closed(s: _Session ref) =>
    s.finish(NetworkFailure, "the server closed the connection",
      _RetryPromptly)

  fun ref on_line(s: _Session ref, m: Message val) =>
    match m.command()
    | "ERROR" =>
      s.finish(NetworkFailure, "the server sent ERROR: " + m.trailing(),
        _RetryAfterFloor)
    | "NICK" => _on_nick(s, m)
    | "005" => _on_isupport(s, m)
    end

  fun ref _on_nick(s: _Session ref, m: Message val) =>
    // Only our own nickname change matters here.
    let reg = match s.registration() | let r: Registration val => r else return end
    let was = match m.nick() | let n: Nick => n else return end
    if not reg.same(was, reg.me()) then
      return
    end

    match Nicks(m.trailing())
    | let now: Nick => s.set_registration(reg._with_nick(now))
    end

  fun ref _on_isupport(s: _Session ref, m: Message val) =>
    let reg = match s.registration() | let r: Registration val => r else return end

    // A later CASEMAPPING is refused rather than applied: folding names by a
    // new rule mid-connection can merge two people the server keeps apart,
    // and whoever holds the second name inherits the first one's standing.
    let params = m.params()
    var i: USize = 1
    while (i + 1) < params.size() do
      try
        let token = params(i)?
        if token.size() >= 12 then
          if token.substring(0, 12) == "CASEMAPPING=" then
            let announced = Casefold.of_token(token.substring(12))
            if not _same_casemap(announced, reg.casemap()) then
              s.finish(ProtocolFailure,
                "the server changed its casemapping mid-connection",
                _RetryAfterFloor)
              return
            end
          end
        end
      end
      i = i + 1
    end

  fun _same_casemap(a: Casemap, b: Casemap): Bool =>
    match (a, b)
    | (CasemapAscii, CasemapAscii) => true
    | (CasemapRfc1459, CasemapRfc1459) => true
    | (CasemapRfc1459Strict, CasemapRfc1459Strict) => true
    | (let x: CasemapUnrecognised, let y: CasemapUnrecognised) =>
      x.announced() == y.announced()
    else
      false
    end

class ref _Quitting is _State
  """QUIT has been written. No further attempt will be made."""
  fun name(): String => "quitting"

  new ref create(s: _Session ref) =>
    s.arm_deadline(s.config().timeouts().quit_millis())

  fun ref on_line(s: _Session ref, m: Message val) => None

  fun ref on_closed(s: _Session ref) =>
    s.finish(LocalRequest, "the bot asked to stop", _NeverRetry)

  fun ref on_deadline(s: _Session ref) =>
    s.finish(LocalRequest, "the bot asked to stop", _NeverRetry)

class ref _Waiting is _State
  """Between connections, waiting out the backoff."""
  fun name(): String => "waiting"
  fun ref on_line(s: _Session ref, m: Message val) => None
  fun ref on_closed(s: _Session ref) => None

class ref _Stopped is _State
  """Terminal. Nothing is delivered after this."""
  fun name(): String => "stopped"
  fun ref on_line(s: _Session ref, m: Message val) => None
  fun ref on_closed(s: _Session ref) => None
