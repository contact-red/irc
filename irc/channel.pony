class val Channel
  """
  A channel name.

  Deliberately has no `eq`, for the same reason as `Nick`: channel names
  compare under the server's casemapping, so `#Ponylang` and `#ponylang` are
  one channel on every network. Use `Registration.same` and
  `Registration.key`.
  """
  let _text: String val

  new val _create(text: String val) =>
    _text = text

  fun display(): String val =>
    """
    The channel name as the server spelled it, for showing to a human. Never
    use this to compare or to key a collection -- see `Registration.key`.
    """
    _text

primitive Channels
  """The only source of a `Channel`."""
  fun apply(text: String val): (Channel | InvalidName) =>
    match _Names.representable(text)
    | let e: InvalidName => return e
    end

    try
      if not _Names.is_channel_prefix(text(0)?) then
        return InvalidName._create(
          "does not start with one of " + _Names.channel_prefixes()
            + ", so it does not name a channel")
      end
    end

    Channel._create(text)
