class val Timeouts
  """
  How long to wait before giving up on each stage.

  `liveness_millis` is the one that keeps a bot alive: with no traffic for that
  long the library sends a PING, and if the next period is also silent it ends
  the connection. Two periods must fit inside the server's own timeout, which
  is commonly 240 seconds.
  """
  let _connect_millis: U64
  let _registration_millis: U64
  let _isupport_millis: U64
  let _liveness_millis: U64
  let _quit_millis: U64

  new val create(connect_millis': U64 = 30_000,
    registration_millis': U64 = 30_000, isupport_millis': U64 = 1_000,
    liveness_millis': U64 = 60_000, quit_millis': U64 = 10_000)
  =>
    _connect_millis = connect_millis'
    _registration_millis = registration_millis'
    _isupport_millis = isupport_millis'
    _liveness_millis = liveness_millis'
    _quit_millis = quit_millis'

  fun connect_millis(): U64 => _connect_millis
  fun registration_millis(): U64 => _registration_millis
  fun isupport_millis(): U64 => _isupport_millis
  fun liveness_millis(): U64 => _liveness_millis
  fun quit_millis(): U64 => _quit_millis
