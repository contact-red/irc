class val SendRejected is Stringable
  """
  A line could not be built from what the bot asked to send.

  Carries the command and why, never the text: until SASL lands a bot
  authenticates by sending its password in a PRIVMSG, and nothing here can
  tell that line from any other.
  """
  let _command: String val
  let _why: EncodeError

  new val _create(command': String val, why': EncodeError) =>
    _command = command'
    _why = why'

  fun command(): String val => _command
  fun why(): EncodeError => _why

  fun string(): String iso^ =>
    (_command + " was not sent: " + _why.string()).clone()

class val SendDropped is Stringable
  """
  A line was built but not sent, because the queue was full or the connection
  had gone.

  `lines` is how many were dropped together: a long message is split into
  several, and they are queued or dropped as one so a channel never sees half
  a sentence.
  """
  let _command: String val
  let _lines: USize
  let _reason: String val

  new val _create(command': String val, lines': USize, reason: String val) =>
    _command = command'
    _lines = lines'
    _reason = reason

  fun command(): String val => _command
  fun lines(): USize => _lines

  fun string(): String iso^ =>
    (_command + " dropped (" + _lines.string() + " lines): " + _reason).clone()

type Dropped is (SendRejected | SendDropped)
  """
  Something the bot asked to send did not go out. Both members concern the
  outbound direction: nothing received is ever dropped.
  """
