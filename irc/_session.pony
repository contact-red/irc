trait ref _Session
  """
  What a protocol state may do to the session it runs in.

  A trait rather than the actor itself, so every state can be driven in a test
  with no socket, no scheduler and no connection. An actor held from outside is
  `tag`, and a `tag` cannot be handed to a `fun ref`, so a state that took the
  actor directly could only ever be exercised end to end.
  """
  fun config(): IRCConfig val
  fun generation(): U32

  fun ref write_now(l: Line val)
    """Send ahead of the queue, unpaced. For the library's own lines only."""

  fun ref enqueue(command: String val, group: Array[Line val] val)
    """Queue a message the bot asked to send, whole or not at all."""

  fun ref transition(next: _State)
  fun ref arm_deadline(millis: U64)
  fun ref cancel_deadline()

  fun ref registration(): (Registration val | None)
  fun ref set_registration(reg: Registration val)

  fun ref emit_registered(reg: Registration val)
  fun ref emit_dropped(what: Dropped)

  fun ref finish(because: EndedBecause, detail: String val, plan: _RetryPlan)
    """End this connection and decide whether another will be attempted."""

primitive _RetryPromptly
primitive _RetryAfterFloor
primitive _NeverRetry
type _RetryPlan is (_RetryPromptly | _RetryAfterFloor | _NeverRetry)
