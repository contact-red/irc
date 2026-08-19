use "pony_test"

class \nodoc\ iso _TestFoldAscii is UnitTest
  fun name(): String => "casefold/ascii folds only A-Z"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("red", Casefold(CasemapAscii, "RED"))
    h.assert_eq[String]("red[]", Casefold(CasemapAscii, "Red[]"))
    h.assert_false(Casefold.same(CasemapAscii, "Foo[]", "foo{}"))
    h.assert_true(Casefold.same(CasemapAscii, "Foo", "fOO"))

class \nodoc\ iso _TestFoldRfc1459 is UnitTest
  fun name(): String => "casefold/rfc1459 folds the bracket bytes too"

  fun apply(h: TestHelper) =>
    // The bug the library exists to prevent: on an rfc1459 server these two
    // strings are one person, and comparing them as bytes says they are not.
    h.assert_true(Casefold.same(CasemapRfc1459, "Foo[]", "foo{}"))
    h.assert_true(Casefold.same(CasemapRfc1459, "a\\b", "a|b"))
    h.assert_true(Casefold.same(CasemapRfc1459, "A^B", "a~b"))
    h.assert_eq[String]("foo{}", Casefold(CasemapRfc1459, "Foo[]"))

class \nodoc\ iso _TestFoldStrict is UnitTest
  fun name(): String => "casefold/rfc1459-strict leaves ^ alone"

  fun apply(h: TestHelper) =>
    h.assert_true(Casefold.same(CasemapRfc1459Strict, "Foo[]", "foo{}"))
    h.assert_false(Casefold.same(CasemapRfc1459Strict, "A^B", "a~b"))

class \nodoc\ iso _TestCasemapOfToken is UnitTest
  fun name(): String => "casefold/an unknown casemapping folds finely"

  fun apply(h: TestHelper) =>
    h.assert_is[Casemap](CasemapRfc1459, Casefold.of_token("rfc1459"))
    h.assert_is[Casemap](CasemapAscii, Casefold.of_token("ascii"))

    // Absent and unrecognised both fold as ASCII, the finest rule we have.
    // Folding coarsely is what lets one name inherit another's trust.
    h.assert_is[Casemap](CasemapAscii, Casefold.of_token(None))

    match Casefold.of_token("utf8")
    | let u: CasemapUnrecognised =>
      h.assert_eq[String]("utf8", u.announced())
      h.assert_false(Casefold.same(u, "Foo[]", "foo{}"))
    else
      h.fail("utf8 should be reported as unrecognised")
    end
