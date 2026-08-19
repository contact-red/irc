class val ParseFailure is Stringable
  """
  Why a line from the server could not be read.

  Every reason means the same thing to a bot: this line is not usable, and the
  session carries on. The raw bytes arrive alongside it, so the text here is
  for a human reading a log.
  """
  let _reason: String val

  new val _create(reason: String val) =>
    _reason = reason

  fun string(): String iso^ =>
    _reason.clone()
