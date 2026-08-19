class val Nick
  """
  A nickname.

  Deliberately has no `eq`, so `==` on two `Nick`s does not compile and a
  `Nick` cannot be a `Map` key or a `Set` member. Whether two nicknames name
  the same person depends on the casemapping the server announces at runtime,
  so the comparison lives on `Registration`: use `Registration.same` to compare
  and `Registration.key` to build a map key.

  Three ways around that do compile, and none of them is correct:

  * `a.display() == b.display()` compares bytes, so `Foo[]` and `foo{}` differ
    even though every `rfc1459` server treats them as one person.
  * `a is b` compares identity, so it is false for two `Nick`s holding the
    same text.
  * `Array[Nick].contains(n)` compiles because its default predicate is
    identity, so it is always false.
  """
  let _text: String val

  new val _create(text: String val) =>
    _text = text

  fun display(): String val =>
    """
    The nickname as the server spelled it, for showing to a human. Never use
    this to compare or to key a collection -- see `Registration.key`.
    """
    _text

primitive Nicks
  """The only source of a `Nick`."""
  fun apply(text: String val): (Nick | InvalidName) =>
    match _Names.representable(text)
    | let e: InvalidName => return e
    end

    try
      if _Names.is_channel_prefix(text(0)?) then
        return InvalidName._create(
          "starts with '" + String.from_array([text(0)?])
            + "', which names a channel and not a person")
      end

      if text(0)? == '$' then
        return InvalidName._create(
          "starts with '$', which IRC reads as a server mask")
      end
    end

    Nick._create(text)
