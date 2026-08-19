class val ReconnectPolicy
  """
  When to try again after a connection ends.

  The delay doubles from `initial_millis` up to `max_millis`, with jitter, and
  resets only after a connection has stayed registered for longer than the
  current delay. Resetting on connect instead would turn a server that accepts
  and immediately closes into a permanent once-a-second reconnect, which is
  what earns a ban.

  Some endings are never retried whatever this says: a rejected password, a
  ban, a casemapping conflict, and a shutdown the bot asked for.
  """
  let _initial_millis: U64
  let _max_millis: U64
  let _jitter_percent: U64
  let _max_attempts: U32

  new val create(initial_millis': U64 = 1_000, max_millis': U64 = 300_000,
    jitter_percent': U64 = 25, max_attempts': U32 = 100)
  =>
    _initial_millis = initial_millis'
    _max_millis = max_millis'
    _jitter_percent = jitter_percent'
    _max_attempts = max_attempts'

  new val none() =>
    """Never reconnect."""
    _initial_millis = 1_000
    _max_millis = 300_000
    _jitter_percent = 25
    _max_attempts = 0

  fun initial_millis(): U64 => _initial_millis
  fun max_millis(): U64 => _max_millis
  fun jitter_percent(): U64 => _jitter_percent
  fun max_attempts(): U32 => _max_attempts
