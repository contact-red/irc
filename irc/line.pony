class val Line
  """
  Bytes ready for the wire.

  A `Line` exists only if `Wire` built it, and `Wire` scans every byte it
  writes. So a `Line` holds no raw CR, LF or NUL anywhere -- not in a
  parameter, not in the tag section -- and is within its byte budget. That is
  what makes it impossible for text from a stranger to end the line early and
  start a second one under the bot's name.
  """
  let _text: String val
  let _command: String val

  new val _create(text: String val, command': String val) =>
    _text = text
    _command = command'

  fun command(): String val =>
    """The command slot, for logging and for recognising a `QUIT`."""
    _command

  fun bytes(): Array[U8] val =>
    """The encoded line, including its terminator."""
    _text.array()

  fun size(): USize =>
    _text.size()

  fun string(): String iso^ =>
    """
    A description, never the contents.

    Until SASL lands, a bot authenticates by sending
    `PRIVMSG NickServ :IDENTIFY <password>`, and nothing here distinguishes that
    line from any other. So a `Line` never renders its payload, and neither
    should a bot: do not log `bytes()` either.
    """
    (_command + " (" + _text.size().string() + " bytes)").clone()
