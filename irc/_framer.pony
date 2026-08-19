class _Framer
  """
  Splits a byte stream into lines.

  lori frames by byte count only, so this package owns its own framing. The
  terminator is a line feed, with a carriage return before it removed if
  present: RFC 1459 requires both, and real servers send only the line feed.

  Each completed line is copied out at exactly its own length, so nothing
  handed to a bot points into the connection's read buffer. Without that, a
  bot storing one parameter would hold the whole 16KB buffer alive.

  A line longer than the bound is reported once and then discarded up to the
  next terminator, so a server sending endless bytes with no line feed costs
  one report rather than one per read.
  """
  var _buf: Array[U8] iso = recover iso Array[U8] end
  let _max_line_bytes: USize
  var _scanned: USize = 0
  var _skipping: Bool = false

  new create(max_line_bytes': USize) =>
    _max_line_bytes = max_line_bytes'

  fun ref feed(data: Array[U8] iso) =>
    let incoming: Array[U8] val = consume data
    let at = _buf.size()
    _buf.undefined(at + incoming.size())
    _buf.copy_from(incoming, 0, at, incoming.size())

  fun ref buffered(): USize =>
    """
    How many bytes are held waiting for a terminator. Bounded by
    `max_line_bytes`, which is what stops a server from growing this forever.
    """
    _buf.size()

  fun ref line(): (String val | ParseFailure val | None) =>
    """
    The next complete line, a report that one was too long, or `None` when
    more bytes are needed.

    `None` is the signal to stop calling and wait for more data. A loop that
    treats it as anything else spins forever on an unchanged buffer.
    """
    while true do
      var i = _scanned
      var found: Bool = false

      try
        while i < _buf.size() do
          if _buf(i)? == '\n' then
            found = true
            break
          end
          i = i + 1
        end
      else
        return None
      end

      if not found then
        _scanned = _buf.size()

        if _skipping then
          _buf.clear()
          _scanned = 0
          return None
        end

        if _buf.size() > _max_line_bytes then
          _buf.clear()
          _scanned = 0
          _skipping = true
          return ParseFailure._create(
            "is longer than the " + _max_line_bytes.string() + " byte limit")
        end

        return None
      end

      let consumed = i + 1

      if _skipping then
        _skipping = false
        _discard(consumed)
        continue
      end

      var stop = i
      try
        if (stop > 0) and (_buf(stop - 1)? == '\r') then
          stop = stop - 1
        end
      end

      if stop > _max_line_bytes then
        _discard(consumed)
        return ParseFailure._create(
          "is longer than the " + _max_line_bytes.string() + " byte limit")
      end

      // `chop` carves the line off the front without copying it again; the
      // bytes were already copied once, into this buffer, by `feed`.
      (let head, let rest) = (_buf = recover iso Array[U8] end).chop(consumed)
      _buf = consume rest
      _scanned = 0

      var out = consume head
      out.trim_in_place(0, stop)
      return String.from_iso_array(consume out)
    end
    None

  fun ref _discard(through: USize) =>
    (let head, let rest) = (_buf = recover iso Array[U8] end).chop(through)
    _buf = consume rest
    _scanned = 0
