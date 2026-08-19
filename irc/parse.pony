primitive Parse
  """
  Reads one line of the IRC wire format.

  Public because a bot needs it: the only other source of a `Message` is a live
  socket, and a bot author has to be able to test their own message handling
  without one. It also makes a saved log replayable.

  The line must arrive without its terminator, which is what the framer hands
  over. A trailing CR is tolerated anyway.
  """
  fun max_params(): USize =>
    """RFC 2812 allows fifteen parameters, the last of them trailing."""
    15

  fun apply(line: String val): (Message val | ParseFailure) =>
    try
      _parse(line)?
    else
      _Unreachable()
      ParseFailure._create("could not be read")
    end

  fun _parse(line: String val): (Message val | ParseFailure) ? =>
    var bytes = line.array()
    var size = bytes.size()

    // Be lenient about a terminator the framer did not strip.
    while (size > 0) and ((bytes(size - 1)? == '\r') or (bytes(size - 1)? == '\n'))
    do
      size = size - 1
    end

    var pos = _skip_spaces(bytes, 0, size)?
    if pos >= size then
      return ParseFailure._create("is blank")
    end

    var tags: String val = ""
    if bytes(pos)? == '@' then
      let stop = _find_space(bytes, pos, size)?
      if stop >= size then
        return ParseFailure._create("carries tags but no command")
      end
      tags = _view(bytes, pos + 1, stop)
      pos = _skip_spaces(bytes, stop, size)?
    end

    var source: String val = ""
    if (pos < size) and (bytes(pos)? == ':') then
      let stop = _find_space(bytes, pos, size)?
      if stop >= size then
        return ParseFailure._create("carries a prefix but no command")
      end
      source = _view(bytes, pos + 1, stop)
      pos = _skip_spaces(bytes, stop, size)?
    end

    if pos >= size then
      return ParseFailure._create("carries no command")
    end

    let command_end = _find_space(bytes, pos, size)?
    let command = _view(bytes, pos, command_end)
    if not _is_command(command) then
      return ParseFailure._create(
        "has a command slot that is neither a word nor a three-digit reply")
    end
    pos = _skip_spaces(bytes, command_end, size)?

    let params = recover iso Array[String val] end
    while pos < size do
      if params.size() == max_params() then
        return ParseFailure._create(
          "carries more than " + max_params().string() + " parameters")
      end

      if bytes(pos)? == ':' then
        // The trailing parameter runs to the end of the line and may hold
        // spaces and colons.
        params.push(_view(bytes, pos + 1, size))
        pos = size
      else
        let stop = _find_space(bytes, pos, size)?
        params.push(_view(bytes, pos, stop))
        pos = _skip_spaces(bytes, stop, size)?
      end
    end

    Message._create(line, tags, source, command, consume params)

  fun _is_command(command: String box): Bool =>
    if command.size() == 0 then
      return false
    end

    var letters = true
    var digits = true
    for c in command.values() do
      if not (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))) then
        letters = false
      end
      if (c < '0') or (c > '9') then
        digits = false
      end
    end

    letters or (digits and (command.size() == 3))

  fun _view(bytes: Array[U8] val, from: USize, to: USize): String val =>
    // `trim` on a `val` array shares the allocation and `from_array` reuses
    // the pointer, so a parameter costs no copy of its bytes.
    String.from_array(bytes.trim(from, to))

  fun _find_space(bytes: Array[U8] val, from: USize, size: USize): USize ? =>
    var i = from
    while i < size do
      if bytes(i)? == ' ' then
        return i
      end
      i = i + 1
    end
    size

  fun _skip_spaces(bytes: Array[U8] val, from: USize, size: USize): USize ? =>
    var i = from
    while (i < size) and (bytes(i)? == ' ') do
      i = i + 1
    end
    i
