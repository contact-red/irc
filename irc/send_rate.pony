class val SendRate
  """
  How fast a bot's own messages are allowed to leave.

  IRC servers disconnect a client that sends too fast, on a schedule that is
  in no RFC and varies between networks. The defaults follow the common one:
  a burst of five, then one message every two seconds. Nothing the library
  sends on its own behalf is paced -- a queued PONG is how a bot dies.

  `queue_limit` bounds how far behind the queue may fall. It is a limit on
  delay as much as on memory: at the default rate, thirty-two waiting
  messages is about a minute of output.
  """
  let _burst: USize
  let _interval_millis: U64
  let _queue_limit: USize

  new val create(burst': USize = 5, interval_millis': U64 = 2_000,
    queue_limit': USize = 32)
  =>
    _burst = burst'
    _interval_millis = interval_millis'
    _queue_limit = queue_limit'

  fun burst(): USize => _burst
  fun interval_millis(): U64 => _interval_millis
  fun queue_limit(): USize => _queue_limit
