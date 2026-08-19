interface tag IRCSend
  """
  What a bot may ask a connection to do.

  Every callback receives this rather than the connection itself, so a test
  can implement it and see exactly what a bot asked for, with no socket.
  """
  be privmsg(target: Target, text: String val)
    """
    Send text. Long text is split across several messages, and embedded
    newlines split it too, so text from a stranger cannot become a second
    command.
    """

  be notice(target: Target, text: String val)
    """
    Send a notice. A bot must not answer one: two bots answering each other
    flood the server, which disconnects both.
    """

  be action(target: Target, text: String val)
    """Send a CTCP ACTION -- what a client shows as "/me"."""

  be join(channels: Array[Channel] val, keys: Array[String val] val = [])
    """
    Join channels, coalesced into as few lines as the server's limits allow.

    One line for twelve channels rather than twelve paced lines, which after a
    reconnect is the difference between rejoining at once and rejoining over
    the next quarter of a minute.
    """

  be part(channels: Array[Channel] val, reason: String val = "")
  be nick(n: Nick)

  be send(line: Line val)
    """Send a line built with `Wire`, for anything this package does not wrap."""

  be quit(reason: String val = "")
    """
    Send QUIT and stop. No further connection is attempted.

    Without this a bot vanishing from the network shows as a ping timeout for
    minutes, and everyone in the channel sees it.
    """

  be disconnect()
    """Drop the connection without a QUIT, and stop."""
