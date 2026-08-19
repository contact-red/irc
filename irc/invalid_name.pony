class val InvalidName is Stringable
  """
  Why a nickname or channel name cannot be used.

  Every reason means the same thing to a caller: the name in your source or
  your configuration cannot be sent as one IRC parameter, so correct it. The
  text says which rule it broke.

  This is a startup check, not an authority. A name that passes can still be
  refused by the server: `NICKLEN`, `CHANNELLEN` and the real `CHANTYPES`
  arrive in `005`, after the connection is already open. See
  `Registration.acceptable`.
  """
  let _reason: String val

  new val _create(reason: String val) =>
    _reason = reason

  fun string(): String iso^ =>
    _reason.clone()
