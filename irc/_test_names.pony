use "pony_test"

class \nodoc\ iso _TestNickAccepts is UnitTest
  fun name(): String => "names/nick accepts ordinary nicknames"

  fun apply(h: TestHelper) =>
    for good in
      ["red"; "Red"; "red_"; "r"; "red[]"; "red{}"; "|red|"; "red-1"].values()
    do
      match Nicks(good)
      | let n: Nick => h.assert_eq[String](good, n.display())
      | let e: InvalidName => h.fail(good + " rejected: " + e.string())
      end
    end

class \nodoc\ iso _TestNickRejects is UnitTest
  fun name(): String => "names/nick rejects unsendable and mistyped names"

  fun apply(h: TestHelper) =>
    let bad =
      [ ("", "empty")
        ("a b", "space")
        ("a,b", "comma")
        (":a", "leading colon")
        ("a*", "wildcard")
        ("$red", "server mask")
        ("#ponylang", "channel, not a person")
        ("&local", "channel, not a person") ]

    for (text, why) in bad.values() do
      match Nicks(text)
      | let n: Nick => h.fail("accepted " + why + ": " + n.display())
      | let e: InvalidName => None
      end
    end

    // A control byte must not survive validation: it would end the line early.
    match Nicks("a\rb")
    | let n: Nick => h.fail("accepted an embedded CR")
    | let e: InvalidName => None
    end

class \nodoc\ iso _TestChannelAccepts is UnitTest
  fun name(): String => "names/channel accepts every RFC 2811 prefix"

  fun apply(h: TestHelper) =>
    for good in ["#ponylang"; "&local"; "+modeless"; "!12345chan"].values() do
      match Channels(good)
      | let c: Channel => h.assert_eq[String](good, c.display())
      | let e: InvalidName => h.fail(good + " rejected: " + e.string())
      end
    end

class \nodoc\ iso _TestChannelRejects is UnitTest
  fun name(): String => "names/channel rejects a nickname"

  fun apply(h: TestHelper) =>
    // The whole value of having two types is that this fails. If it ever
    // passes, Nick and Channel are distinct in name only.
    match Channels("red")
    | let c: Channel => h.fail("accepted a nickname as a channel")
    | let e: InvalidName => None
    end

    match Channels("#a,#b")
    | let c: Channel => h.fail("accepted a comma-separated target list")
    | let e: InvalidName => None
    end
