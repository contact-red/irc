use "ssl/net"

primitive NoTLS
  """Connect in the clear."""

primitive NoTLSWithPassword
  """
  Connect in the clear and send the server password anyway.

  Naming it is the point. Without TLS the password crosses the network in
  plain sight, and a failed connection is retried, so it crosses again on
  every attempt. Anyone who wants that has to say so here rather than reach
  it by leaving a parameter out.
  """

type TLS is (SSLContext val | NoTLS | NoTLSWithPassword)
  """
  Whether the connection is encrypted.

  There is no default. Most networks now listen only on TLS ports, and the
  choice decides whether a password is readable in transit, so it is made at
  the call site every time.
  """
