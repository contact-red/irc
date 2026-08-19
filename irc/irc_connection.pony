use "collections"
use "time"
use "random"
use lori = "lori"
use "ssl/net"

actor IRC is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver
  & _Session & IRCSend)
  """
  A connection to one IRC network.

  Owns the wire format, the registration handshake, PING replies, send pacing
  and reconnection. It owns nothing about what the bot does: there is no
  command routing and no plugin registry here.

  The bot is a separate actor implementing `IRCNotify`, so its code never runs
  on this one's turn and cannot hold up a PING reply.

  Construction cannot fail. Everything that could be wrong about the
  configuration was reported by `IRCConfigs` before this existed.
  """
  let _config: IRCConfig val
  let _notify: IRCNotify tag
  var _conn: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _State = _Waiting
  var _framer: _Framer
  var _outbox: _Outbox
  var _reg: (Registration val | None) = None

  var _generation: U32 = 0
  var _attempts: U32 = 0
  var _backoff_millis: U64
  var _live_since: U64 = 0
  var _epoch: U64 = 0
  var _pacer_armed: Bool = false
  var _ping_outstanding: Bool = false
  var _stopped: Bool = false

  let _timers: Timers = Timers
  let _rand: Rand = Rand(Time.nanos(), Time.millis())

  new create(config': IRCConfig val, notify': IRCNotify tag) =>
    _config = config'
    _notify = notify'
    _framer = _Framer(config'.max_line_bytes())
    _outbox = _Outbox(config'.rate(), Time.millis())
    _backoff_millis = config'.reconnect().initial_millis()
    _open()

  //
  // lori
  //

  fun ref _connection(): lori.TCPConnection => _conn

  fun ref _on_connected() =>
    _configure_connection()
    _state.on_connected(this)

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    let detail =
      match reason
      | lori.ConnectionFailedDNS => "the host name did not resolve"
      | lori.ConnectionFailedTCP => "the connection was refused"
      | lori.ConnectionFailedSSL => "the TLS handshake failed"
      | lori.ConnectionFailedTimeout => "the connection timed out"
      | lori.ConnectionFailedTimerError => "a connection timer failed"
      end

    // A TLS failure is retried on a floor rather than abandoned: expired
    // certificates and part-rolled chains are among the failures that most
    // reliably clear on their own, and a bot that stops for good on one stays
    // down long after the network is fixed.
    let plan =
      if reason is lori.ConnectionFailedSSL then
        _RetryAfterFloor
      else
        _RetryPromptly
      end

    finish(NetworkFailure, detail, plan)

  fun ref _on_closed() =>
    _state.on_closed(this)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _ping_outstanding = false
    _framer.feed(consume data)

    var reading = true
    while reading do
      match _framer.line()
      | let text: String val => _deliver(text)
      | let why: ParseFailure val => _notify.irc_unparseable(this, "", why)
      | None =>
        // The only signal to stop. Treating it as anything else spins on an
        // unchanged buffer.
        reading = false
      end
    end

    lori.KeepReading

  fun ref _on_idle_timeout() =>
    if _ping_outstanding then
      finish(NetworkFailure, "the server stopped answering", _RetryPromptly)
      return
    end

    _ping_outstanding = true
    match Wire.command("PING", [], _config.host())
    | let l: Line val => write_now(l)
    end

  fun ref _on_idle_timer_failure() =>
    // Without this timer nothing notices a half-open socket, so the connection
    // is ended rather than left running blind.
    finish(ProtocolFailure, "the liveness timer failed", _RetryPromptly)

  fun ref _on_timer_failure() =>
    finish(ProtocolFailure, "a connection timer failed", _RetryPromptly)

  fun ref _on_throttled() => None

  fun ref _on_unthrottled() =>
    _resume()

  be _resume() =>
    _flush()

  //
  // IRCSend
  //

  be privmsg(target: Target, text: String val) =>
    _say("PRIVMSG", Wire.privmsg(target, text))

  be notice(target: Target, text: String val) =>
    _say("NOTICE", Wire.notice(target, text))

  be action(target: Target, text: String val) =>
    _one("PRIVMSG", Wire.action(target, text))

  be join(channels: Array[Channel] val, keys: Array[String val] val = []) =>
    for line in _grouped("JOIN", channels, keys).values() do
      _one("JOIN", line)
    end

  be part(channels: Array[Channel] val, reason: String val = "") =>
    for line in _grouped("PART", channels, []).values() do
      _one("PART", line)
    end

  be nick(n: Nick) =>
    _one("NICK", Wire.command("NICK", [n.display()]))

  be send(line: Line val) =>
    if line.command() == "QUIT" then
      // The escape hatch must not be a way round `quit`: a QUIT sent this way
      // still means the bot is stopping.
      _quit_with(line)
      return
    end
    _state.user_send(this, line.command(), [line])

  be quit(reason: String val = "") =>
    match Wire.command("QUIT", [], reason)
    | let l: Line val => _quit_with(l)
    | let e: EncodeError =>
      match Wire.command("QUIT", [], "")
      | let l: Line val => _quit_with(l)
      | let e': EncodeError => disconnect()
      end
    end

  be disconnect() =>
    _stopped = true
    _finish_now(LocalRequest, "the bot asked to stop", _NeverRetry)
    _conn.hard_close()

  be dispose() =>
    """
    Stop. An alias for `disconnect`.

    lori's own `dispose` hard-closes the socket, which here would look like the
    server dropping the connection and start a reconnect. Overriding it means
    the name every Pony program uses to stop something does stop it.
    """
    disconnect()

  //
  // _Session
  //

  fun config(): IRCConfig val => _config
  fun generation(): U32 => _generation

  fun ref write_now(l: Line val) =>
    _outbox.urgent(l)
    _flush()

  fun ref enqueue(command: String val, group: Array[Line val] val) =>
    match _outbox.push(group)
    | let why: String val =>
      _notify.irc_dropped(this,
        SendDropped._create(command, group.size(), why))
    | None =>
      _flush()
    end

  fun ref transition(next: _State) =>
    _state = next

  fun ref arm_deadline(millis: U64) =>
    _arm(_DeadlineTick, millis)

  fun ref cancel_deadline() =>
    // Nothing is cancelled: the epoch moves on and a late firing is ignored
    // when it arrives.
    _epoch = _epoch + 1

  fun ref registration(): (Registration val | None) => _reg

  fun ref set_registration(reg: Registration val) =>
    _reg = reg

  fun ref emit_registered(reg: Registration val) =>
    _live_since = Time.millis()
    _notify.irc_registered(this, reg)

  fun ref emit_dropped(what: Dropped) =>
    _notify.irc_dropped(this, what)

  fun ref finish(because: EndedBecause, detail: String val,
    plan: _RetryPlan)
  =>
    _finish_now(because, detail, plan)
    _conn.hard_close()

  //
  // internals
  //

  be _tick(purpose: _TickPurpose, armed_in: U64) =>
    if armed_in != _epoch then
      return
    end

    match purpose
    | _DeadlineTick => _state.on_deadline(this)
    | _PacerTick =>
      _pacer_armed = false
      _flush()
    | _BackoffTick => _open()
    end

  fun ref _deliver(text: String val) =>
    match Parse(text)
    | let m: Message val =>
      if m.command() == "PING" then
        _state.on_ping(this, m)
      end

      _state.on_line(this, m)

      // Every line reaches the bot, including the ones handled above. A bot
      // can then deal with anything this package does not model, and nothing
      // disappears into a log that release builds compile out.
      _notify.irc_message(this, m, _reg)
    | let why: ParseFailure val =>
      _notify.irc_unparseable(this, text, why)
    end

  fun ref _say(command: String val, group: Array[Line val] val) =>
    _state.user_send(this, command, group)

  fun ref _one(command: String val, built: (Line val | EncodeError)) =>
    match built
    | let l: Line val => _state.user_send(this, command, [l])
    | let e: EncodeError =>
      _notify.irc_dropped(this, SendRejected._create(command, e))
    end

  fun ref _grouped(command: String val, channels: Array[Channel] val,
    keys: Array[String val] val): Array[(Line val | EncodeError)] val
  =>
    let out = recover iso Array[(Line val | EncodeError)] end
    if channels.size() == 0 then
      return consume out
    end

    let per_line = _targmax(command)
    var i: USize = 0

    while i < channels.size() do
      let stop = (i + per_line).min(channels.size())
      let names = recover iso Array[String val] end
      let batch_keys = recover iso Array[String val] end

      var j = i
      while j < stop do
        try names.push(channels(j)?.display()) end
        try
          let k = keys(j)?
          if k.size() > 0 then batch_keys.push(k) end
        end
        j = j + 1
      end

      let names': Array[String val] val = consume names
      let keys': Array[String val] val = consume batch_keys

      let params = recover iso Array[String val] end
      params.push(",".join(names'.values()))
      if keys'.size() > 0 then
        params.push(",".join(keys'.values()))
      end

      out.push(Wire.command(command, consume params))
      i = stop
    end

    consume out

  fun ref _targmax(command: String val): USize =>
    match _reg
    | let r: Registration val =>
      match Isupport.targmax(r.isupport("TARGMAX"), command)
      | let n: U64 => return n.usize().max(1)
      | Unlimited => return 12
      end

      match Isupport.chanlimit(r.isupport("CHANLIMIT"), '#')
      | let n: U64 => return n.usize().max(1)
      end
    end
    4

  fun ref _flush() =>
    for l in _outbox.ready(Time.millis()).values() do
      match _conn.send(l.bytes())
      | let e: lori.SendError =>
        // lori does not queue for us, so the line goes back and waits for the
        // socket to become writeable again.
        _outbox.requeue(l)
        return
      end
    end

    if _outbox.pending() and (not _pacer_armed) then
      _pacer_armed = true
      _arm(_PacerTick, _config.rate().interval_millis())
    end

  fun ref _arm(purpose: _TickPurpose, millis: U64) =>
    _epoch = _epoch + 1
    let t = Timer(_Tick(this, purpose, _epoch), millis * 1_000_000)
    _timers(consume t)

  fun ref _quit_with(l: Line val) =>
    _stopped = true
    _outbox.clear()
    write_now(l)
    _state = _Quitting(this)

  fun ref _finish_now(because: EndedBecause, detail: String val,
    plan: _RetryPlan)
  =>
    match _state
    | let terminal: _Stopped => return
    | let waiting: _Waiting => return
    end

    _epoch = _epoch + 1
    _pacer_armed = false
    _ping_outstanding = false

    let lost = _outbox.clear()
    if lost > 0 then
      _notify.irc_dropped(this,
        SendDropped._create("queued", lost, "the connection ended"))
    end

    _reg = None

    // The delay resets only after a connection has held for longer than the
    // delay itself. Resetting on connect would turn a server that accepts and
    // immediately closes into a once-a-second reconnect, which earns a ban.
    let held = if _live_since > 0 then Time.millis() - _live_since else 0 end
    if held > _backoff_millis then
      _attempts = 0
      _backoff_millis = _config.reconnect().initial_millis()
    end
    _live_since = 0

    let policy = _config.reconnect()
    _attempts = _attempts + 1

    let retry =
      if _stopped or (plan is _NeverRetry) then
        false
      else
        _attempts <= policy.max_attempts()
      end

    let delay =
      if retry then
        let base =
          match plan
          | _RetryAfterFloor => _backoff_millis.max(policy.max_millis() / 4)
          else
            _backoff_millis
          end
        _jittered(base)
      else
        U64(0)
      end

    let retry_in: (U64 | None) = if retry then delay else None end
    let ended =
      SessionEnded._create(because, detail, _generation, _attempts, retry_in)

    _notify.irc_session(this, ended)

    if retry then
      _state = _Waiting
      _backoff_millis = (_backoff_millis * 2).min(policy.max_millis())
      _arm(_BackoffTick, delay)
    else
      _state = _Stopped
      _notify.irc_stopped(this, ended)
    end

  fun ref _jittered(base: U64): U64 =>
    let spread = (base * _config.reconnect().jitter_percent()) / 100
    if spread == 0 then
      return base
    end
    (base - (spread / 2)) + _rand.int(spread)

  fun ref _open() =>
    if _stopped then
      return
    end

    _generation = _generation + 1
    _reg = None
    _framer = _Framer(_config.max_line_bytes())
    _outbox = _Outbox(_config.rate(), Time.millis())
    _state = _Connecting

    _conn =
      match _config.tls()
      | let ctx: SSLContext val =>
        lori.TCPConnection.ssl_client(_config.auth(), ctx, _config.host(),
          _config.service(), "", this, this)
      else
        lori.TCPConnection.client(_config.auth(), _config.host(),
          _config.service(), "", this, this)
      end

  fun ref _configure_connection() =>
    """
    Everything about the connection that is set per connection rather than
    once.

    lori keeps these on the connection object, and a reconnect builds a new
    one, so anything set only in the constructor is silently lost from the
    second connection onward. The liveness timeout is the one that matters:
    without it a half-open socket is never noticed, never closed and never
    retried.
    """
    match lori.MakeIdleTimeout(_config.timeouts().liveness_millis())
    | let t: lori.IdleTimeout => _conn.idle_timeout(t)
    end
