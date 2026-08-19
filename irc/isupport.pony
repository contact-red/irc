primitive Unlimited
  """
  An ISUPPORT limit the server declared as having no bound, by sending the key
  with an empty value -- `TARGMAX=JOIN:` means join as many as you like.
  """
  fun string(): String iso^ => "unlimited".clone()

class val ChanModes
  """
  The four groups of `CHANMODES`, which differ in whether a mode carries a
  parameter. Pairing a mode with its parameter on a `MODE` line requires knowing which
  group the mode is in, and the groups vary by network.
  """
  let _with_list: String val
  let _always_parameter: String val
  let _parameter_when_set: String val
  let _no_parameter: String val

  new val _create(with_list': String val, always_parameter': String val,
    parameter_when_set': String val, no_parameter': String val)
  =>
    _with_list = with_list'
    _always_parameter = always_parameter'
    _parameter_when_set = parameter_when_set'
    _no_parameter = no_parameter'

  fun with_list(): String val =>
    """Modes holding a list, always with a parameter -- bans and invites."""
    _with_list

  fun always_parameter(): String val =>
    """Modes that take a parameter both when set and when unset -- a key."""
    _always_parameter

  fun parameter_when_set(): String val =>
    """Modes that take a parameter only when set -- a user limit."""
    _parameter_when_set

  fun no_parameter(): String val =>
    """Modes that never take a parameter."""
    _no_parameter

primitive Isupport
  """
  Decoders for the `005` token grammars.

  `Registration.isupport` hands back a token's raw value; these read it. They
  are pure functions of the raw value, so they need no session and a bot can
  test against them directly.

  Each takes the value exactly as `Registration.isupport` returns it, `None`
  included, so a call site needs no match.
  """
  fun count(raw: (String box | None), default: U64): U64 =>
    """
    A plain number, such as `NICKLEN=30` or `MODES=4`. Falls back to `default`
    when the server sent no value, or one that will not parse.
    """
    match raw
    | let s: String box =>
      try _digits(s, 0, s.size())? else default end
    | None => default
    end

  fun chars(raw: (String box | None)): String val =>
    """
    A set of bytes, such as `CHANTYPES=#&` or `STATUSMSG=@+`. Empty when the
    server sent none.
    """
    match raw
    | let s: String box => s.clone()
    | None => ""
    end

  fun targmax(raw: (String box | None), command: String box)
    : (U64 | Unlimited | None)
  =>
    """
    How many targets one command may address, from
    `TARGMAX=PRIVMSG:4,NOTICE:4,JOIN:`.

    `None` when the command is not listed, which means the server states no
    limit for it.
    """
    _keyed(raw, command, false)

  fun chanlimit(raw: (String box | None), prefix: U8)
    : (U64 | Unlimited | None)
  =>
    """
    How many channels of a given type may be joined, from
    `CHANLIMIT=#:25,&:10`.

    The key is a set of channel prefixes, so `#&:10` covers both. `None`
    when this prefix is not listed.
    """
    _keyed(raw, String.from_array([prefix]), true)

  fun prefixes(raw: (String box | None)): Array[(U8, U8)] val =>
    """
    Channel membership prefixes, from `PREFIX=(ov)@+`, as `(mode, prefix)`
    pairs in the order the server gave -- most privileged first.

    Which byte marks which mode is the server's choice, not a constant, so an
    operator check has to read it from here.
    """
    let out = recover iso Array[(U8, U8)] end

    match raw
    | let s: String box =>
      try
        if s(0)? != '(' then
          return consume out
        end
        let close = s.find(")")?.usize()
        let modes = s.substring(1, close.isize())
        let marks = s.substring((close + 1).isize())

        var i: USize = 0
        while (i < modes.size()) and (i < marks.size()) do
          out.push((modes(i)?, marks(i)?))
          i = i + 1
        end
      end
    end

    consume out

  fun chanmodes(raw: (String box | None)): ChanModes val =>
    """The four `CHANMODES` groups, empty where the server said nothing."""
    var groups = ["" ; "" ; "" ; ""]

    match raw
    | let s: String box =>
      var i: USize = 0
      for part in s.split(",").values() do
        if i < 4 then
          try groups(i)? = consume part end
        end
        i = i + 1
      end
    end

    try
      ChanModes._create(groups(0)?, groups(1)?, groups(2)?, groups(3)?)
    else
      ChanModes._create("", "", "", "")
    end

  fun _keyed(raw: (String box | None), key: String box, by_member: Bool)
    : (U64 | Unlimited | None)
  =>
    let s =
      match raw
      | let v: String box => v
      | None => return None
      end

    for group in s.split(",").values() do
      let g: String val = consume group
      try
        let colon = g.find(":")?
        let name: String val = g.substring(0, colon)
        let value: String val = g.substring(colon + 1)

        let hit: Bool =
          if by_member then
            (key.size() == 1) and name.contains(key)
          else
            name == key
          end

        if hit then
          if value.size() == 0 then
            return Unlimited
          end
          return _digits(value, 0, value.size())?
        end
      end
    end

    None

  fun _digits(s: String box, from: USize, count': USize): U64 ? =>
    if count' == 0 then error end
    var n: U64 = 0
    var i = from
    while i < (from + count') do
      let c = s(i)?
      if (c < '0') or (c > '9') then error end
      n = (n * 10) + (c - '0').u64()
      i = i + 1
    end
    n
