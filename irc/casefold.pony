primitive Casefold
  """
  Casemapped comparison of nicknames and channel names.

  A pure function of the rule and the bytes, so a bot can test its own
  name-handling without a connection. `Registration.same` and
  `Registration.key` delegate here with the rule the server announced.
  """
  fun apply(m: Casemap, s: String box): String val =>
    """
    `s` folded under `m`.

    Always returns a freshly allocated string, never a view of its input, so a
    folded key retains nothing of the message it came from.
    """
    let n = s.size()
    var out = recover iso String(n) end
    for c in s.values() do
      out.push(_fold_byte(m, c))
    end
    consume out

  fun same(m: Casemap, a: String box, b: String box): Bool =>
    """
    Do `a` and `b` name the same thing under `m`? Compares byte by byte and
    allocates nothing.
    """
    if a.size() != b.size() then
      return false
    end

    var i: USize = 0
    try
      while i < a.size() do
        if _fold_byte(m, a(i)?) != _fold_byte(m, b(i)?) then
          return false
        end
        i = i + 1
      end
    else
      return false
    end
    true

  fun of_token(announced: (String box | None)): Casemap =>
    """
    The rule named by a `CASEMAPPING` token from `005`.

    An absent or unrecognised value gives `CasemapAscii`, the finest rule this
    package implements. That is deliberate, and it deviates from RFC 2812,
    which makes `rfc1459` the default when the server sends no value.

    The reason is that the two mistakes are not equally bad. Folding more
    finely than the server splits an equivalence class the server would have
    joined, so a check fails that should have passed. Folding more coarsely
    joins two names the server keeps apart, so whoever takes the second name
    inherits whatever the first name was trusted with. Only the second is a
    way in.
    """
    match announced
    | let s: String box =>
      if s == "ascii" then
        CasemapAscii
      elseif s == "rfc1459" then
        CasemapRfc1459
      elseif s == "rfc1459-strict" then
        CasemapRfc1459Strict
      else
        CasemapUnrecognised._create(s.clone())
      end
    | None =>
      CasemapAscii
    end

  fun _fold_byte(m: Casemap, c: U8): U8 =>
    if (c >= 'A') and (c <= 'Z') then
      return c + 32
    end

    match m
    | CasemapRfc1459 =>
      match c
      | '[' => '{'
      | ']' => '}'
      | '\\' => '|'
      | '^' => '~'
      else c
      end
    | CasemapRfc1459Strict =>
      match c
      | '[' => '{'
      | ']' => '}'
      | '\\' => '|'
      else c
      end
    else
      c
    end
