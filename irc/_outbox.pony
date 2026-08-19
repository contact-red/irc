use "collections"

class _Outbox
  """
  Paces the lines a bot asks to send.

  Servers disconnect a client that sends too fast, and the schedule is not in
  any RFC. A bot replying to forty people at once would be killed without
  this, and the failure does not show up against a test server on the same
  machine.

  The library's own PING replies and its QUIT do not queue here. A PONG behind
  forty paced messages arrives after the server has already given up.

  Lines are accepted or refused a whole message at a time, so a channel never
  sees the first half of a split sentence and then nothing.

  Allowance is earned by the clock rather than granted by whoever is asking.
  A bucket that filled only while it was being emptied would spend its
  burst once and never see it again -- every later line waiting a full
  interval however long the connection had been quiet.
  """
  let _rate: SendRate val
  embed _queue: List[Array[Line val] val] = List[Array[Line val] val]
  var _priority: (Line val | None) = None
  var _tokens: USize
  var _lines: USize = 0
  var _head_sent: USize = 0
  // When the allowance was last brought up to date. Every token since is
  // owed and has not been counted yet.
  var _granted_at: U64

  new create(rate: SendRate val, now: U64) =>
    _rate = rate
    _tokens = rate.burst()
    _granted_at = now

  fun ref urgent(l: Line val) =>
    """
    Send this ahead of everything queued, without spending a pacing token.

    Only for lines the library originates and cannot delay: a PONG, and the
    QUIT that ends a session.
    """
    _priority = l

  fun ref push(group: Array[Line val] val): (None | String val) =>
    """
    Queue one message. Either all of its lines are accepted or none are, and
    the reason is returned when they are not.
    """
    if group.size() == 0 then
      return None
    end

    if group.size() > _rate.queue_limit() then
      return "it is longer than the whole send queue"
    end

    while (_lines + group.size()) > _rate.queue_limit() do
      if not _drop_oldest() then
        return "the send queue is full"
      end
    end

    _queue.push(group)
    _lines = _lines + group.size()
    None

  fun ref ready(now: U64): Array[Line val] val =>
    """
    The lines that may go out now: any urgent one first, then as many queued
    lines as the elapsed time has paid for.

    `now` is monotonic milliseconds. It is passed in rather than read here
    so a test can hold the clock still and step it.
    """
    _earn(now)

    let out = recover iso Array[Line val] end

    match _priority = None
    | let l: Line val => out.push(l)
    end

    while (_tokens > 0) and (_lines > 0) do
      try
        let group = _queue(0)?
        out.push(group(_head_sent)?)
        _tokens = _tokens - 1
        _lines = _lines - 1
        _head_sent = _head_sent + 1

        if _head_sent == group.size() then
          _queue.shift()?
          _head_sent = 0
        end
      else
        break
      end
    end

    consume out

  fun ref _earn(now: U64) =>
    """
    Count the tokens the clock has paid for since it was last counted.

    The mark moves by exactly what was earned rather than to `now`, so the
    part of an interval that has passed but not completed is kept. Moving
    it to `now` would throw that remainder away on every call and send
    slower than the rate asks for -- and `ready` is called on every line a
    bot offers, so it would be thrown away often.

    Time beyond a full bucket is discarded with the same move. A connection
    quiet for an hour has not earned an hour of talking, which is the
    burst's whole purpose.
    """
    let interval = _rate.interval_millis()
    if (interval == 0) or (now <= _granted_at) then
      return
    end

    let earned = (now - _granted_at) / interval
    if earned == 0 then
      return
    end

    _granted_at = _granted_at + (earned * interval)
    let allowance = _rate.burst().u64()
    let held = _tokens.u64() + earned
    _tokens = (if held > allowance then allowance else held end).usize()

  fun ref requeue(l: Line val) =>
    """
    Put a line back after the connection refused to write it.

    It goes into the urgent slot so it keeps its place ahead of the queue, and
    so a refused PONG is not lost -- the one line that must not be dropped is
    otherwise the only one with no way back.
    """
    _priority = l

  fun ref pending(): Bool =>
    """Whether anything is waiting, which is when the pacing timer is needed."""
    (_lines > 0) or (_priority isnt None)

  fun ref size(): USize =>
    _lines

  fun ref clear(): USize =>
    """
    Discard everything and report how many lines were lost.

    Called when a connection ends: a line built for one connection must not be
    sent on the next, where the bot may hold a different nickname and may not
    have rejoined the channel it was addressed to.
    """
    let lost = _lines
    _queue.clear()
    _lines = 0
    _head_sent = 0
    _priority = None
    lost

  fun ref _drop_oldest(): Bool =>
    """
    Drop the oldest whole message that has not started sending. Returns false
    when there is nothing droppable, which leaves the caller to refuse.
    """
    try
      if (_head_sent > 0) and (_queue.size() > 1) then
        // The head is part-sent; dropping it now would truncate a sentence
        // that has already begun. Take the next one instead.
        let node = _queue.index(1)?
        let group = node()?
        node.remove()
        _lines = _lines - group.size()
        return true
      end

      if _head_sent > 0 then
        return false
      end

      let group = _queue.shift()?
      _lines = _lines - group.size()
      true
    else
      false
    end
