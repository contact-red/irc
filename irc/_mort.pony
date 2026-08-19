use @pony_os_stderr[Pointer[U8]]()
use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @exit[None](status: I32)

primitive _Unreachable
  """
  A branch the compiler demands but that cannot execute.

  Used where a partial call has already been proved safe by a bounds check.
  Reporting such a branch as ordinary bad input would blame the server for a
  bug in this package, so it stops the process instead.
  """
  fun apply(loc: SourceLoc = __loc) =>
    @fprintf(
      @pony_os_stderr(),
      "%s:%d: unreachable code executed. This is a bug in the irc package.\n".cstring(),
      loc.file().cstring(),
      loc.line().u32())
    @exit(I32(1))
