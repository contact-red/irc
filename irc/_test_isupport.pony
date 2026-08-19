use "pony_test"

class \nodoc\ iso _TestIsupportCount is UnitTest
  fun name(): String => "isupport/a plain count falls back when unsaid"

  fun apply(h: TestHelper) =>
    h.assert_eq[U64](30, Isupport.count("30", 9))
    h.assert_eq[U64](9, Isupport.count(None, 9))
    h.assert_eq[U64](9, Isupport.count("not a number", 9))

class \nodoc\ iso _TestIsupportChars is UnitTest
  fun name(): String => "isupport/a byte set comes back verbatim or empty"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("#&", Isupport.chars("#&"))
    h.assert_eq[String]("@+", Isupport.chars("@+"))
    h.assert_eq[String]("", Isupport.chars(None))

class \nodoc\ iso _TestIsupportTargmax is UnitTest
  fun name(): String => "isupport/targmax tells listed from unlimited from absent"

  fun apply(h: TestHelper) =>
    let raw = "PRIVMSG:4,NOTICE:4,JOIN:"

    match Isupport.targmax(raw, "PRIVMSG")
    | let n: U64 => h.assert_eq[U64](4, n)
    else h.fail("PRIVMSG should be limited to 4")
    end

    // An empty value means no limit, which is not the same as not listed.
    h.assert_true(Isupport.targmax(raw, "JOIN") is Unlimited)
    h.assert_true(Isupport.targmax(raw, "KICK") is None)
    h.assert_true(Isupport.targmax(None, "PRIVMSG") is None)

class \nodoc\ iso _TestIsupportChanlimit is UnitTest
  fun name(): String => "isupport/chanlimit matches a prefix inside a key set"

  fun apply(h: TestHelper) =>
    match Isupport.chanlimit("#:25,&:10", '#')
    | let n: U64 => h.assert_eq[U64](25, n)
    else h.fail("# should be limited to 25")
    end

    // The key is a set of prefixes, so #&:10 answers for both.
    match Isupport.chanlimit("#&:10", '&')
    | let n: U64 => h.assert_eq[U64](10, n)
    else h.fail("& should be covered by the #& key")
    end

    h.assert_true(Isupport.chanlimit("#:25", '+') is None)

class \nodoc\ iso _TestIsupportPrefix is UnitTest
  fun name(): String => "isupport/prefix pairs modes with their marks"

  fun apply(h: TestHelper) =>
    let pairs = Isupport.prefixes("(ohv)@%+")
    h.assert_eq[USize](3, pairs.size())
    try
      h.assert_eq[U8]('o', pairs(0)?._1)
      h.assert_eq[U8]('@', pairs(0)?._2)
      h.assert_eq[U8]('v', pairs(2)?._1)
      h.assert_eq[U8]('+', pairs(2)?._2)
    else
      h.fail("prefix pairs did not decode")
    end

    h.assert_eq[USize](0, Isupport.prefixes(None).size())
    h.assert_eq[USize](0, Isupport.prefixes("nonsense").size())

class \nodoc\ iso _TestIsupportChanmodes is UnitTest
  fun name(): String => "isupport/chanmodes splits into its four groups"

  fun apply(h: TestHelper) =>
    let m = Isupport.chanmodes("beI,k,l,imnpst")
    h.assert_eq[String]("beI", m.with_list())
    h.assert_eq[String]("k", m.always_parameter())
    h.assert_eq[String]("l", m.parameter_when_set())
    h.assert_eq[String]("imnpst", m.no_parameter())

    let empty = Isupport.chanmodes(None)
    h.assert_eq[String]("", empty.with_list())
    h.assert_eq[String]("", empty.no_parameter())
