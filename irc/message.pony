use "time"

class val Message
  """
  One line received from the server, parsed into its wire structure.

  The parameters are byte views into the line, so reading them copies nothing.
  IRC is bytes, not text: a parameter may not be valid UTF-8, because a real
  user can send anything. Comparing, slicing and storing all work regardless;
  only `runes()` is affected.

  Storing a parameter beyond the callback keeps the whole line alive. Lines are
  bounded, but a bot retaining thousands of them should `clone()` first.
  `Registration.key` already returns a fresh string, so a casemapped map key
  retains nothing.
  """
  let _raw: String val
  let _tags: String val
  let _source: String val
  let _command: String val
  let _params: Array[String val] val

  new val _create(raw': String val, tags': String val, source': String val,
    command': String val, params': Array[String val] val)
  =>
    _raw = raw'
    _tags = tags'
    _source = source'
    _command = command'
    _params = params'

  fun raw(): String val =>
    """The line as received, without the terminator. A field read, so free."""
    _raw

  fun command(): String val =>
    """
    The command slot exactly as it arrived: `"PRIVMSG"`, or `"433"`.

    A `String` and not a closed set of types, because the set is not closed:
    IRC has hundreds of numeric replies and networks invent their own.
    """
    _command

  fun numeric(): (U16 | None) =>
    """The command as a number, when it is a three-digit numeric reply."""
    if _command.size() != 3 then
      return None
    end

    var n: U16 = 0
    for c in _command.values() do
      if (c < '0') or (c > '9') then
        return None
      end
      n = (n * 10) + (c - '0').u16()
    end
    n

  fun params(): Array[String val] val =>
    """Every parameter, including the trailing one."""
    _params

  fun trailing(): String val =>
    """
    The last parameter, or `""` when there are none.

    A line with an empty final parameter and a line with no parameters both
    read as `""` here. The two are distinguishable through `params()`, and
    nothing in IRC treats them differently on the receiving side.
    """
    try _params(_params.size() - 1)? else "" end

  fun source(): String val =>
    """
    The prefix as it arrived -- `nick!user@host`, a server name, or `""` when
    the line carried none.
    """
    _source

  fun nick(): (Nick | None) =>
    """
    The nickname that sent this, when there is one.

    `None` when the line came from the server itself, or carried no prefix, or
    named something that cannot be a nickname.
    """
    let text =
      try
        _source.substring(0, _source.find("!")?)
      else
        // No `!`, so this is either a bare nickname or a server name. A dot
        // means a server: no network permits one in a nickname.
        if _source.contains(".") then
          return None
        end
        _source.clone()
      end

    match Nicks(consume text)
    | let n: Nick => n
    else
      None
    end

  fun user(): (String val | None) =>
    """The user part of the prefix, when it carried one."""
    try
      let bang = _source.find("!")? + 1
      let host_at = _source.find("@", bang)?
      _source.substring(bang, host_at)
    else
      None
    end

  fun host(): (String val | None) =>
    """The host part of the prefix, when it carried one."""
    try
      _source.substring(_source.find("@")? + 1)
    else
      None
    end

  fun tag_value(name: String box): (String val | None) =>
    """
    One IRCv3 message tag by name, unescaped.

    `None` when the tag is absent; `""` when it is present with no value. Tags
    are decoded only when asked for, so a line without any costs nothing.
    """
    for (k, v) in _decode_tags().values() do
      if k == name then
        return v
      end
    end
    None

  fun tags(): Array[(String val, String val)] val =>
    """Every message tag, unescaped, in the order the server sent them."""
    _decode_tags()

  fun ctcp(): (Ctcp val | None) =>
    """
    The CTCP request or reply this line carries, when the final parameter is
    wrapped in `\x01`.

    A missing closing `\x01` is tolerated, because real clients omit it.
    """
    if (_command != "PRIVMSG") and (_command != "NOTICE") then
      return None
    end

    let text = trailing()
    if (text.size() < 2) or (try text(0)? != 0x01 else true end) then
      return None
    end

    let body =
      try
        if text(text.size() - 1)? == 0x01 then
          text.substring(1, text.size().isize() - 1)
        else
          text.substring(1)
        end
      else
        return None
      end

    let body': String val = consume body
    try
      let sp = body'.find(" ")?
      Ctcp._create(body'.substring(0, sp), body'.substring(sp + 1))
    else
      Ctcp._create(body', "")
    end

  fun at(): (I64 | None) =>
    """
    When the server says this line happened, in POSIX milliseconds, from the
    `server-time` tag.

    Only present when the `server-time` capability is enabled, which this
    package always requests. It matters because a bouncer replays its buffer
    every time a client attaches, and reconnection is on by default -- so a bot
    with side effects will see the same commands again after every reconnect.
    Record the `at()` of the last line you acted on and ignore anything at or
    before it.
    """
    let stamp =
      match tag_value("time")
      | let s: String val => s
      | None => return None
      end

    // The format is fixed width: YYYY-MM-DDThh:mm:ss.sssZ
    if stamp.size() < 20 then
      return None
    end

    try
      let d = PosixDate
      d.year = _digits(stamp, 0, 4)?.i32()
      d.month = _digits(stamp, 5, 2)?.i32()
      d.day_of_month = _digits(stamp, 8, 2)?.i32()
      d.hour = _digits(stamp, 11, 2)?.i32()
      d.min = _digits(stamp, 14, 2)?.i32()
      d.sec = _digits(stamp, 17, 2)?.i32()

      let millis: I64 =
        if (stamp.size() >= 23) and (stamp(19)? == '.') then
          _digits(stamp, 20, 3)?.i64()
        else
          0
        end

      (d.time() * 1000) + millis
    else
      None
    end

  fun _digits(s: String box, from: USize, count: USize): U32 ? =>
    var n: U32 = 0
    var i = from
    while i < (from + count) do
      let c = s(i)?
      if (c < '0') or (c > '9') then
        error
      end
      n = (n * 10) + (c - '0').u32()
      i = i + 1
    end
    n

  fun _decode_tags(): Array[(String val, String val)] val =>
    let out = recover iso Array[(String val, String val)] end

    if _tags.size() == 0 then
      return consume out
    end

    for pair in _tags.split(";").values() do
      if pair.size() == 0 then
        continue
      end

      let p: String val = consume pair
      try
        let eq = p.find("=")?
        out.push((p.substring(0, eq), _TagEscape.unescape(p.substring(eq + 1))))
      else
        out.push((p, ""))
      end
    end

    consume out
