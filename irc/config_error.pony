class val ConfigError is Stringable
  """
  A configuration value that cannot be used.

  Reported before the connection actor exists, so a bot fails at startup
  rather than part-way through a handshake. `field` names the parameter; the
  text says what is wrong with it. Neither ever contains the value, so a
  rejected password is not written to a log by whoever prints this.
  """
  let _field: String val
  let _reason: String val

  new val _create(field': String val, reason: String val) =>
    _field = field'
    _reason = reason

  fun field(): String val =>
    """The parameter at fault, never its value."""
    _field

  fun string(): String iso^ =>
    (_field + " " + _reason).clone()
