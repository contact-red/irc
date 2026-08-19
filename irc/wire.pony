primitive Wire
  """
  Builds IRC lines.

  Every byte written is scanned, whatever its source: a validated `Nick`, a
  literal in the bot's own code, or text a stranger just sent to a channel.
  Nothing is exempt because of its type, so a caller cannot build a line that
  carries a raw CR, LF or NUL.

  `Line` has no public constructor, so this is the only way to produce one.
  """
  fun default_budget(): USize =>
    """
    The classic 512-byte line limit, terminator included. IRCv3 gives message
    tags a separate 8191-byte budget, which `command` adds on top.
    """
    512

  fun max_tag_bytes(): USize =>
    8191

  fun command(name: String val, params: Array[String val] val,
    trailing: (String val | None) = None,
    tags: Array[(String val, String val)] val = [],
    budget: USize = 512): (Line val | EncodeError)
  =>
    """
    Build one line.

    `trailing` is the final parameter, and it is the only one that may hold
    spaces or start with a colon. Passing `""` encodes a bare `:`, which is
    not the same as passing `None`: `TOPIC #c :` clears a topic and
    `TOPIC #c` queries it.

    Tag names must be client-only -- prefixed with `+`. A server-attested tag
    is the server's to assert, not ours to claim.

    A `\x01` is refused anywhere in the line. CTCP framing is only reachable
    through `ctcp`, `ctcp_reply` and `action`, so a bot cannot forge an action
    or a file-transfer offer by routing text through here.
    """
    _build(name, params, trailing, tags, budget, false)

  fun _build(name: String val, params: Array[String val] val,
    trailing: (String val | None), tags: Array[(String val, String val)] val,
    budget: USize, allow_ctcp: Bool): (Line val | EncodeError)
  =>
    if not _is_command(name) then
      return MalformedLine._create(
        "a command must be a word or a three-digit reply, not '" + name + "'")
    end

    let out = recover iso String(budget) end

    if tags.size() > 0 then
      out.push('@')
      var first = true
      for (k, v) in tags.values() do
        match _tag_name_fault(k)
        | let reason: String val => return MalformedLine._create(reason)
        end

        if not first then out.push(';') end
        first = false
        out.append(k)
        if v.size() > 0 then
          out.push('=')
          out.append(_TagEscape.escape(v))
        end
      end

      if out.size() > max_tag_bytes() then
        return LineTooLongToEncode
      end
      out.push(' ')
    end

    out.append(name)

    for p in params.values() do
      match _middle_fault(p)
      | let reason: String val => return MalformedLine._create(reason)
      end
      out.push(' ')
      out.append(p)
    end

    match trailing
    | let t: String val =>
      match _text_fault(t, allow_ctcp)
      | let reason: String val => return MalformedLine._create(reason)
      end
      out.append(" :")
      out.append(t)
    end

    let tag_bytes = if tags.size() > 0 then out.size() else 0 end
    out.append("\r\n")

    if (out.size() - tag_bytes) > budget then
      return LineTooLongToEncode
    end

    Line._create(consume out, name)

  fun privmsg(target: Target, text: String val, max_text: USize = 400)
    : Array[Line val] val
  =>
    """
    One or more PRIVMSGs carrying `text`.

    Splits on embedded newlines, and splits over-long text at a UTF-8
    character boundary. NUL and `\x01` are removed, so text a stranger supplied
    cannot forge an action or a file-transfer offer in the bot's name, and
    cannot inject a second command.

    Never fails and never returns an empty array: the target has already been
    validated, and everything else is either sent or trimmed.
    """
    _say("PRIVMSG", target, text, max_text)

  fun notice(target: Target, text: String val, max_text: USize = 400)
    : Array[Line val] val
  =>
    """
    One or more NOTICEs carrying `text`.

    A bot must not answer a NOTICE. Two bots answering each other's notices
    flood the server, which then disconnects both. See `Registration.reply_to`, which returns
    `None` for one.
    """
    _say("NOTICE", target, text, max_text)

  fun ctcp(target: Target, command': String val, argument: String val = "")
    : (Line val | EncodeError)
  =>
    """A CTCP request, as a PRIVMSG wrapped in `\x01`."""
    _ctcp("PRIVMSG", target, command', argument)

  fun ctcp_reply(target: Target, command': String val,
    argument: String val = ""): (Line val | EncodeError)
  =>
    """
    A CTCP reply, as a NOTICE wrapped in `\x01`.

    A reply must be a NOTICE. Answering a CTCP request with a PRIVMSG invites
    the other end to answer back, and two bots doing that flood each other off
    the server.
    """
    _ctcp("NOTICE", target, command', argument)

  fun action(target: Target, text: String val): (Line val | EncodeError) =>
    """A CTCP ACTION -- what a client shows as "/me"."""
    _ctcp("PRIVMSG", target, "ACTION", text)

  fun _ctcp(verb: String val, target: Target, command': String val,
    argument: String val): (Line val | EncodeError)
  =>
    if command'.size() == 0 then
      return MalformedLine._create("a CTCP command cannot be empty")
    end

    match _text_fault(command', true)
    | let reason: String val => return MalformedLine._create(reason)
    end
    match _text_fault(argument, true)
    | let reason: String val => return MalformedLine._create(reason)
    end

    let body = recover iso String(command'.size() + argument.size() + 3) end
    body.push(0x01)
    body.append(_strip_ctcp(command'))
    if argument.size() > 0 then
      body.push(' ')
      body.append(_strip_ctcp(argument))
    end
    body.push(0x01)

    _build(verb, [_Names.text_of(target)], consume body, [], default_budget(),
      true)

  fun _say(verb: String val, target: Target, text: String val,
    max_text: USize): Array[Line val] val
  =>
    let clean = _strip_ctcp(text)
    let out = recover iso Array[Line val] end
    let name = _Names.text_of(target)

    for segment in _split_lines(clean).values() do
      for chunk in _split_bytes(segment, max_text).values() do
        match command(verb, [name], chunk)
        | let l: Line val => out.push(l)
        end
      end
    end

    if out.size() == 0 then
      match command(verb, [name], "")
      | let l: Line val => out.push(l)
      end
    end

    consume out

  fun _split_lines(text: String val): Array[String val] val =>
    """
    Split on embedded CR or LF and drop the empty pieces.

    A newline in text a bot echoes would otherwise be a second command. Empty
    pieces are dropped because a trailing newline would otherwise cost a line
    and a pacing slot to say nothing.
    """
    let out = recover iso Array[String val] end
    var start: USize = 0
    var i: USize = 0

    try
      while i < text.size() do
        let c = text(i)?
        if (c == '\r') or (c == '\n') then
          if i > start then
            out.push(text.substring(start.isize(), i.isize()))
          end
          start = i + 1
        end
        i = i + 1
      end

      if text.size() > start then
        out.push(text.substring(start.isize()))
      end
    end

    consume out

  fun _split_bytes(text: String val, max_text: USize): Array[String val] val =>
    """Split at a UTF-8 character boundary so no line exceeds `max_text`."""
    let out = recover iso Array[String val] end

    if text.size() <= max_text then
      out.push(text)
      return consume out
    end

    var start: USize = 0
    while start < text.size() do
      var stop = (start + max_text).min(text.size())

      if stop < text.size() then
        // Back off a continuation byte so a character is not cut in half.
        // Bounded, because the text may not be valid UTF-8 at all.
        var backed: USize = 0
        try
          while (stop > start) and (backed < 3)
            and ((text(stop)? and 0xC0) == 0x80)
          do
            stop = stop - 1
            backed = backed + 1
          end
        end
      end

      out.push(text.substring(start.isize(), stop.isize()))
      start = stop
    end

    consume out

  fun _strip_ctcp(s: String val): String val =>
    var needs = false
    for c in s.values() do
      if (c == 0x00) or (c == 0x01) then
        needs = true
        break
      end
    end

    if not needs then
      return s
    end

    let out = recover iso String(s.size()) end
    for c in s.values() do
      if (c != 0x00) and (c != 0x01) then
        out.push(c)
      end
    end
    consume out

  fun _middle_fault(p: String box): (None | String val) =>
    if p.size() == 0 then
      return "a parameter before the last one cannot be empty"
    end

    try
      if p(0)? == ':' then
        return "a parameter before the last one cannot start with ':'"
      end
    end

    for c in p.values() do
      if c == ' ' then
        return "a parameter before the last one cannot contain a space"
      end
    end

    _text_fault(p, false)

  fun _text_fault(s: String box, allow_ctcp: Bool): (None | String val) =>
    for c in s.values() do
      match c
      | '\r' => return "contains a carriage return"
      | '\n' => return "contains a line feed"
      | 0x00 => return "contains a null byte"
      | 0x01 =>
        if not allow_ctcp then
          return "contains a CTCP delimiter"
        end
      end
    end
    None

  fun _tag_name_fault(k: String box): (None | String val) =>
    if k.size() == 0 then
      return "a tag name cannot be empty"
    end

    try
      if k(0)? != '+' then
        return "tag name '" + k.clone()
          + "' is not client-only; only '+' tags may be sent"
      end
    end

    for c in k.values() do
      if (c <= ' ') or (c == ';') or (c == '=') or (c == 0x7F) then
        return "tag name '" + k.clone() + "' has a byte that cannot be sent"
      end
    end
    None

  fun _is_command(name: String box): Bool =>
    if name.size() == 0 then
      return false
    end

    var letters = true
    var digits = true
    for c in name.values() do
      if not (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))) then
        letters = false
      end
      if (c < '0') or (c > '9') then
        digits = false
      end
    end
    letters or (digits and (name.size() == 3))
