primitive _Names
  """
  The representability rules shared by `Nicks`, `Channels` and the parser.

  Representable means "can be sent as a single IRC parameter and read back as
  the same bytes". It is a property of the string alone, so it can be checked
  before a connection exists.
  """
  fun max_bytes(): USize =>
    """
    The longest name we will build. RFC 2812 caps a nickname at 9 bytes and
    every modern network raises it via `NICKLEN`, so this is a sanity bound
    rather than a protocol limit -- it exists to keep one name from consuming
    the whole 512-byte line budget.
    """
    64

  fun channel_prefixes(): String val =>
    """
    The channel-type bytes we recognise before the server announces
    `CHANTYPES`. Deliberately conservative: RFC 2811 defines these four, and a
    network using anything else is not served.
    """
    "#&+!"

  fun representable(text: String box): (None | InvalidName) =>
    if text.size() == 0 then
      return InvalidName._create("is empty")
    end

    if text.size() > max_bytes() then
      return InvalidName._create(
        "is longer than " + max_bytes().string() + " bytes")
    end

    try
      if text(0)? == ':' then
        return InvalidName._create(
          "starts with ':', which IRC reads as the start of a trailing parameter")
      end
    end

    for c in text.values() do
      if (c <= ' ') or (c == 0x7F) then
        return InvalidName._create("contains a space or a control byte")
      end

      match c
      | ',' =>
        return InvalidName._create(
          "contains a comma, which IRC reads as a target separator")
      | '*' | '?' =>
        return InvalidName._create("contains a wildcard")
      end
    end

    None

  fun text_of(t: Target): String val =>
    match t
    | let n: Nick => n.display()
    | let c: Channel => c.display()
    end

  fun is_channel_prefix(c: U8): Bool =>
    for p in channel_prefixes().values() do
      if p == c then return true end
    end
    false
