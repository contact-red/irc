use lori = "lori"

class val IRCConfig
  """
  A checked configuration for one connection.

  Every value that reaches the wire has already been checked by `IRCConfigs`,
  so the connection actor cannot fail to start. An actor constructor cannot
  report an error, and a bad realname discovered part-way through registration
  would otherwise show up as a handshake that times out and retries for ever.
  """
  let _auth: lori.TCPConnectAuth
  let _host: String val
  let _service: String val
  let _tls: TLS
  let _nicks: Array[String val] val
  let _user: String val
  let _realname: String val
  let _password: (String val | None)
  let _capabilities: Array[String val] val
  let _rate: SendRate val
  let _reconnect: ReconnectPolicy val
  let _timeouts: Timeouts val
  let _max_line_bytes: USize

  new val _create(auth': lori.TCPConnectAuth, host': String val,
    service': String val, tls': TLS, nicks': Array[String val] val,
    user': String val, realname': String val, password': (String val | None),
    capabilities': Array[String val] val, rate': SendRate val,
    reconnect': ReconnectPolicy val, timeouts': Timeouts val,
    max_line_bytes': USize)
  =>
    _auth = auth'
    _host = host'
    _service = service'
    _tls = tls'
    _nicks = nicks'
    _user = user'
    _realname = realname'
    _password = password'
    _capabilities = capabilities'
    _rate = rate'
    _reconnect = reconnect'
    _timeouts = timeouts'
    _max_line_bytes = max_line_bytes'

  fun auth(): lori.TCPConnectAuth => _auth
  fun host(): String val => _host
  fun service(): String val => _service
  fun tls(): TLS => _tls
  fun nicks(): Array[String val] val => _nicks
  fun user(): String val => _user
  fun realname(): String val => _realname
  fun password(): (String val | None) => _password
  fun capabilities(): Array[String val] val => _capabilities
  fun rate(): SendRate val => _rate
  fun reconnect(): ReconnectPolicy val => _reconnect
  fun timeouts(): Timeouts val => _timeouts
  fun max_line_bytes(): USize => _max_line_bytes

primitive IRCConfigs
  """
  Checks a configuration and builds an `IRCConfig`.

  Takes an `AmbientAuth` rather than a connection authority, so a bot needs no
  `use` for the transport package: nothing from it appears in any signature
  here or anywhere else in this package.
  """
  fun unsupported(): Array[String val] val =>
    """
    Capabilities this package cannot honour yet.

    Requesting one and then not implementing it is worse than refusing it.
    Asking for `sasl` and never sending `AUTHENTICATE` registers the bot
    unauthenticated with nothing reported, and `echo-message` turns a bot that
    relays what it hears into one that relays its own output for ever.
    """
    ["sasl"; "echo-message"; "batch"; "labeled-response"]

  fun apply(root: AmbientAuth, host: String val, service: String val,
    tls: TLS, nicks: Array[String val] val, user: String val = "",
    realname: String val = "", password: (String val | None) = None,
    capabilities: Array[String val] val = [],
    rate: SendRate val = SendRate,
    reconnect: ReconnectPolicy val = ReconnectPolicy,
    timeouts: Timeouts val = Timeouts,
    max_line_bytes: USize = 8703): (IRCConfig val | ConfigError)
  =>
    if host.size() == 0 then
      return ConfigError._create("host", "cannot be empty")
    end
    if service.size() == 0 then
      return ConfigError._create("service", "cannot be empty")
    end

    if nicks.size() == 0 then
      return ConfigError._create("nicks", "must hold at least one nickname")
    end
    for n in nicks.values() do
      match Nicks(n)
      | let e: InvalidName =>
        return ConfigError._create("nicks", e.string())
      end
    end

    let user' = if user.size() == 0 then try nicks(0)? else "" end else user end
    let realname' =
      if realname.size() == 0 then try nicks(0)? else "" end else realname end

    match _wire_safe(user')
    | let why: String val => return ConfigError._create("user", why)
    end
    match _wire_safe(realname')
    | let why: String val => return ConfigError._create("realname", why)
    end

    match password
    | let p: String val =>
      match _wire_safe(p)
      | let why: String val => return ConfigError._create("password", why)
      end

      // Without TLS the password crosses the network readable, and a retried
      // connection sends it again each time.
      if tls is NoTLS then
        return ConfigError._create("password",
          "would be sent in the clear; pass NoTLSWithPassword to accept that")
      end
    end

    for c in capabilities.values() do
      if c.size() == 0 then
        return ConfigError._create("capabilities", "holds an empty name")
      end
      for u in unsupported().values() do
        if c == u then
          return ConfigError._create("capabilities",
            "asks for '" + c + "', which this package does not implement")
        end
      end
    end

    if rate.burst() == 0 then
      return ConfigError._create("rate", "must allow a burst of at least one")
    end
    if rate.queue_limit() == 0 then
      return ConfigError._create("rate",
        "must allow a queue of at least one message")
    end
    if reconnect.initial_millis() == 0 then
      return ConfigError._create("reconnect",
        "must wait at least a millisecond before trying again")
    end
    if timeouts.liveness_millis() == 0 then
      return ConfigError._create("timeouts", "must allow a liveness check")
    end
    if max_line_bytes < 512 then
      return ConfigError._create("max_line_bytes",
        "must be at least the 512 byte protocol limit")
    end

    IRCConfig._create(lori.TCPConnectAuth(root), host, service, tls,
      nicks, user', realname', password, _with_server_time(capabilities),
      rate, reconnect, timeouts, max_line_bytes)

  fun _with_server_time(caps: Array[String val] val): Array[String val] val =>
    """
    `server-time` is always requested. A bouncer replays its buffer whenever a
    client attaches, and a reconnecting bot attaches often, so without it a
    bot cannot tell a command typed a minute ago from one typed while it was
    away.
    """
    for c in caps.values() do
      if c == "server-time" then return caps end
    end

    let out = recover iso Array[String val] end
    for c in caps.values() do
      out.push(c)
    end
    out.push("server-time")
    consume out

  fun _wire_safe(s: String box): (None | String val) =>
    if s.size() == 0 then
      return "cannot be empty"
    end
    for c in s.values() do
      match c
      | '\r' => return "cannot contain a carriage return"
      | '\n' => return "cannot contain a line feed"
      | 0x00 => return "cannot contain a null byte"
      end
    end
    None
