primitive AuthRejected
  """
  The server refused who the bot claims to be: a bad password, a ban, or no
  usable nickname left. Correct the configuration; another attempt will fail
  the same way.
  """
  fun string(): String iso^ => "authentication rejected".clone()

primitive NetworkFailure
  """
  The connection failed or was lost for a reason that commonly clears on its
  own: a name that did not resolve, a refused socket, a timeout, a server that
  went away.
  """
  fun string(): String iso^ => "network failure".clone()

primitive ProtocolFailure
  """
  The exchange broke a rule. Worth reading the detail: it means the server did
  something this package does not expect, or the connection lost the timer it
  needs to notice that the link has died.
  """
  fun string(): String iso^ => "protocol failure".clone()

primitive LocalRequest
  """The bot called `quit`, `disconnect` or `dispose`."""
  fun string(): String iso^ => "asked to stop".clone()

type EndedBecause is
  (AuthRejected | NetworkFailure | ProtocolFailure | LocalRequest)
  """
  The four kinds of ending a bot handles differently: fix the configuration,
  wait, investigate, or nothing.

  Finer reasons exist, and this package uses them to decide whether and when
  to try again. They are not here because a bot does not act on them -- the
  specific reason is in `SessionEnded.detail`, for a person reading a log.
  """

class val SessionEnded is Stringable
  """
  A connection ended.

  Delivered to `irc_session` every time, and to `irc_stopped` when no further
  attempt will be made. `retry_in_millis` is `None` in the second case, so a
  bot that only wants to know "is it coming back" can read that one field.
  """
  let _because: EndedBecause
  let _detail: String val
  let _generation: U32
  let _attempts: U32
  let _retry_in_millis: (U64 | None)

  new val _create(because': EndedBecause, detail': String val,
    generation': U32, attempts': U32, retry_in_millis': (U64 | None))
  =>
    _because = because'
    _detail = detail'
    _generation = generation'
    _attempts = attempts'
    _retry_in_millis = retry_in_millis'

  fun because(): EndedBecause => _because

  fun detail(): String val =>
    """What happened, in words, for a log. Never a credential."""
    _detail

  fun generation(): U32 =>
    """
    Which connection this was. Counts from one and rises on every attempt.

    A bot holding state keyed by `Registration.key` should discard it when the
    generation changes: a reconnect can land on a different server in a
    round-robin, and that server may announce a different casemapping, so keys
    folded under the old one no longer match.
    """
    _generation

  fun attempts(): U32 =>
    """How many consecutive attempts have failed, reset by a stable connection."""
    _attempts

  fun retry_in_millis(): (U64 | None) =>
    """
    How long until the next attempt, or `None` when there will not be one.
    """
    _retry_in_millis

  fun string(): String iso^ =>
    let s = recover iso String end
    s.append(_because.string())
    s.append(": ")
    s.append(_detail)
    match _retry_in_millis
    | let ms: U64 =>
      s.append("; retrying in ")
      s.append(ms.string())
      s.append("ms")
    | None =>
      s.append("; not retrying")
    end
    consume s
