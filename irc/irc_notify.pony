interface tag IRCNotify
  """
  What a bot implements to hear from a connection.

  No member has a default. That is the whole reason a misspelled callback is
  caught: with defaults, `be irc_mesage(...)` compiles, satisfies this
  interface through the default, and never runs -- a bot that connects and
  does nothing, in every build. Without them the compiler names the missing
  method.

  It also means a bot is told about every kind of failure. A silent default
  for "your message did not go out" is how a bot ends up dropping replies with
  nothing on the terminal to say so.

  Adding a member here is a breaking change, which is deliberate: the
  alternative is a surface that grows to forty methods because each addition
  on its own looked harmless.
  """
  be irc_registered(irc: IRCSend tag, reg: Registration val)
    """
    Registration completed and the server's settings are known.

    The first moment a send will reach the network, and where a bot joins its
    channels. Fires again after every reconnect, so joining here is what makes
    a bot come back properly; `reg.generation()` says which connection this is.
    """

  be irc_message(irc: IRCSend tag, m: Message val,
    reg: (Registration val | None))
    """
    A line arrived.

    Every line the server sends reaches here exactly once, in order, including
    the ones the library acted on itself. Nothing is filtered out and nothing
    is dropped quietly, so a bot can handle anything this package does not
    model.

    `reg` is `None` only before registration completes, when servers send
    notices and the bot has no settled nickname to compare against. It travels
    with the message rather than being stored by the bot, so it cannot go
    stale: a nickname the services force on the bot changes it, and code that
    cached a copy would keep answering with the old one.
    """

  be irc_unparseable(irc: IRCSend tag, raw: String val, why: ParseFailure val)
    """
    A line arrived that could not be read. The session carries on.

    `raw` is empty when the line was refused for being over-long, because
    keeping those bytes is what a server sending an endless line without a
    terminator would rely on.
    """

  be irc_dropped(irc: IRCSend tag, what: Dropped)
    """Something the bot asked to send did not go out."""

  be irc_session(irc: IRCSend tag, ended: SessionEnded val)
    """
    A connection ended. `ended.retry_in_millis()` says when the next attempt
    will be, or `None` when there will not be one.
    """

  be irc_stopped(irc: IRCSend tag, ended: SessionEnded val)
    """
    No further connection will be attempted, and nothing else will be
    delivered.

    Where a bot sets a non-zero exit code. Without one the process leaves with
    a success status even when it stopped because its password was refused,
    and a supervisor set to restart on failure will not restart it.
    """
