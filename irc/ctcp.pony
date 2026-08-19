class val Ctcp
  """
  A CTCP request or reply carried inside a PRIVMSG or NOTICE.

  CTCP is not a separate IRC command: it is ordinary message text wrapped in
  `\x01` bytes. `ACTION` is what a client shows as "/me". A bot that does not
  know this treats `\x01ACTION waves\x01` as the message text.
  """
  let _command: String val
  let _argument: String val

  new val _create(command': String val, argument': String val) =>
    _command = command'
    _argument = argument'

  fun command(): String val =>
    """`"ACTION"`, `"VERSION"`, `"PING"`. Compare case-insensitively."""
    _command

  fun argument(): String val =>
    """Everything after the command, or `""` if it carried none."""
    _argument
