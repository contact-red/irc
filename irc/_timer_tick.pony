use "time"

primitive _DeadlineTick
primitive _PacerTick
primitive _BackoffTick
type _TickPurpose is (_DeadlineTick | _PacerTick | _BackoffTick)

class _Tick is TimerNotify
  """
  Wakes the connection for one scheduled thing.

  Carries the generation it was armed in. A timer that fires after the
  connection it belonged to has gone is ignored on arrival rather than
  cancelled in advance, which avoids racing a cancellation against a firing
  that is already on its way.
  """
  let _irc: IRC
  let _purpose: _TickPurpose
  let _armed_in: U64

  new iso create(irc: IRC, purpose: _TickPurpose, armed_in: U64) =>
    _irc = irc
    _purpose = purpose
    _armed_in = armed_in

  fun ref apply(timer: Timer, count: U64): Bool =>
    _irc._tick(_purpose, _armed_in)
    false
