class val Registration
  """
  Who the bot is on this connection, and what the server said about itself.

  Delivered with `irc_registered` and again with every message, so a bot never
  holds a stale copy. Nothing here changes within a connection except the
  nickname and the `005` tokens; the casemapping is fixed when registration
  completes and cannot change until the next connection.

  Construct one directly to test name handling without a connection.
  """
  let _me: Nick
  let _casemap: Casemap
  let _isupport: Array[(String val, String val)] val
  let _caps: Array[String val] val
  let _generation: U32

  new val create(me': Nick, casemap': Casemap = CasemapAscii,
    isupport': Array[(String val, String val)] val = [],
    caps': Array[String val] val = [], generation': U32 = 1)
  =>
    _me = me'
    _casemap = casemap'
    _isupport = isupport'
    _caps = caps'
    _generation = generation'

  fun _with_nick(n: Nick): Registration val =>
    """The same session facts under a new nickname."""
    Registration(n, _casemap, _isupport, _caps, _generation)

  fun me(): Nick =>
    """The bot's current nickname. Follows a `NICK` the server forces on it."""
    _me

  fun casemap(): Casemap =>
    """The rule this server uses to compare names."""
    _casemap

  fun generation(): U32 =>
    """
    Which connection this is, counting from one.

    State keyed by `key` belongs to one generation: a reconnect may reach a
    different server that announces a different casemapping, and keys folded
    under the old rule will not match.
    """
    _generation

  fun caps(): Array[String val] val =>
    """The IRCv3 capabilities the server agreed to."""
    _caps

  fun cap_enabled(name: String box): Bool =>
    for c in _caps.values() do
      if c == name then return true end
    end
    false

  fun isupport(token: String box): (String val | None) =>
    """
    One `005` token's value, undecoded. `None` when the server did not send it.

    `Isupport` decodes the grammars that repay it; the raw value is here for
    the rest.
    """
    for (k, v) in _isupport.values() do
      if k == token then return v end
    end
    None

  fun same(a: Target, b: Target): Bool =>
    """Do these name the same person or channel on this server?"""
    Casefold.same(_casemap, _Names.text_of(a), _Names.text_of(b))

  fun same_text(a: String box, b: String box): Bool =>
    """
    The same comparison against a name that is not a `Nick` or a `Channel` --
    a literal, a configured owner, or a parameter read straight off a line.

    Parameters arrive as plain strings, and `String` has `==`, so comparing
    one with `==` compiles and is wrong here. This is the comparison to use.
    """
    Casefold.same(_casemap, a, b)

  fun key(t: Target): String val =>
    """
    A map key for `t`, folded under this server's rule.

    Freshly allocated, so a keyed collection holds nothing of the message the
    name arrived on. Never show it to a person: use `display`.
    """
    Casefold(_casemap, _Names.text_of(t))

  fun key_text(s: String box): String val =>
    """A map key for a name that is not a `Nick` or a `Channel`."""
    Casefold(_casemap, s)

  fun is_channel_name(s: String box): Bool =>
    """
    Does this name a channel on this server?

    Reads `CHANTYPES`, which the server chooses, so it is right on networks
    whose channel types are not the four that `Channels` recognises.
    """
    let types = Isupport.chars(isupport("CHANTYPES"))
    let prefixes = if types.size() == 0 then _Names.channel_prefixes() else types end

    try
      let first = s(0)?
      for p in prefixes.values() do
        if p == first then return true end
      end
    end
    false

  fun private_to_me(m: Message val): Bool =>
    """
    Was this message addressed privately to the bot rather than to a channel?

    Computed from `me()`, not from the shape of the target, which is why it is
    right where a `match` on `Nick` is wrong: on a network announcing only `#`
    as a channel type, a message to `&local` is not a channel message by that
    test, and treating it as private lets anyone reach a command meant for a
    direct message.
    """
    try
      let target = m.params()(0)?
      (not is_channel_name(target)) and same_text(target, _me.display())
    else
      false
    end

  fun reply_to(m: Message val): (Target | None) =>
    """
    Where a reply to `m` belongs: the channel it was sent to, or its sender
    when it was sent to the bot directly.

    `None` for anything that must not be answered automatically -- a NOTICE,
    a message from the server itself, or one whose target does not resolve.
    Answering a NOTICE is how two bots talk each other into a flood.
    """
    if m.command() != "PRIVMSG" then
      return None
    end

    let target =
      try
        m.params()(0)?
      else
        return None
      end

    // A status-message prefix addresses a subset of a channel's members, and
    // the reply still belongs to the channel.
    let statusmsg = Isupport.chars(isupport("STATUSMSG"))
    var bare = target
    try
      while bare.size() > 0 do
        let first = bare(0)?
        var stripped = false
        for p in statusmsg.values() do
          if p == first then
            bare = bare.substring(1)
            stripped = true
            break
          end
        end
        if not stripped then break end
      end
    end

    if is_channel_name(bare) then
      match Channels(bare)
      | let c: Channel => return c
      | let e: InvalidName => return None
      end
    end

    if same_text(bare, _me.display()) then
      return m.nick()
    end

    None
