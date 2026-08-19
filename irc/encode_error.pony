primitive LineTooLongToEncode
  """
  The line would exceed the byte budget.

  Distinct from the rest because a caller can act on it: shorten the text and
  try again, or use `Wire.privmsg`, which splits for you.
  """
  fun string(): String iso^ => "line too long to encode".clone()

class val MalformedLine is Stringable
  """
  The line could not be built from what was given.

  One type rather than eight, because a caller does nothing different for an
  empty command than for a parameter holding a newline: both mean the call is
  wrong and the source must change. The text says which rule it broke.
  """
  let _reason: String val

  new val _create(reason: String val) =>
    _reason = reason

  fun string(): String iso^ =>
    _reason.clone()

type EncodeError is (LineTooLongToEncode | MalformedLine)
  """Why a line could not be built."""
