primitive CasemapAscii
  """`A`-`Z` fold to `a`-`z`, and nothing else."""
  fun string(): String iso^ => "ascii".clone()

primitive CasemapRfc1459
  """
  ASCII, and additionally `[`, `]`, `\\` and `^` fold to `{`, `}`, `|` and `~`.

  This is the default IRC casemapping, and the reason `Foo[]` and `foo{}` are
  one person on most networks.
  """
  fun string(): String iso^ => "rfc1459".clone()

primitive CasemapRfc1459Strict
  """`rfc1459` without the `^` to `~` fold."""
  fun string(): String iso^ => "rfc1459-strict".clone()

class val CasemapUnrecognised is Stringable
  """
  The server announced a casemapping this package does not implement, such as
  `utf8` or `rfc7613`.

  It folds as ASCII, the finest rule available. A bot that would rather refuse
  to run than compare names by a rule it does not share can match on this and
  read `announced()`.
  """
  let _announced: String val

  new val _create(announced': String val) =>
    _announced = announced'

  fun announced(): String val =>
    _announced

  fun string(): String iso^ =>
    ("unrecognised (" + _announced + ")").clone()

type Casemap is
  ( CasemapAscii
  | CasemapRfc1459
  | CasemapRfc1459Strict
  | CasemapUnrecognised )
  """
  The rule this server applies when comparing two nicknames or channel
  names.

  The server chooses, and announces it in `005`. Until it does, this package
  assumes `CasemapAscii`.
  """
