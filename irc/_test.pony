use "pony_test"
use "pony_check"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    // Names
    test(_TestNickAccepts)
    test(_TestNickRejects)
    test(_TestChannelAccepts)
    test(_TestChannelRejects)

    // Casefolding
    test(_TestFoldAscii)
    test(_TestFoldRfc1459)
    test(_TestFoldStrict)
    test(_TestCasemapOfToken)

    // Parsing
    test(_TestParseBasic)
    test(_TestParseTrailing)
    test(_TestParseNumeric)
    test(_TestParseTags)
    test(_TestParseCtcp)
    test(_TestParseServerTime)
    test(_TestParseRejects)

    // Encoding
    test(_TestWireBasic)
    test(_TestWireTrailingSlot)
    test(_TestWireRejects)
    test(_TestWireTags)
    test(_TestWireCtcp)
    test(_TestWireSplits)
    test(Property1UnitTest[String](_PropNoInjection))
    test(Property1UnitTest[String](_PropSplitRoundTrips))

    // ISUPPORT grammars
    test(_TestIsupportCount)
    test(_TestIsupportChars)
    test(_TestIsupportTargmax)
    test(_TestIsupportChanlimit)
    test(_TestIsupportPrefix)
    test(_TestIsupportChanmodes)

    // Registration
    test(_TestRegistrationCompare)
    test(_TestRegistrationPrivacy)
    test(_TestRegistrationReplyTo)
    test(_TestRegistrationIsupport)

    // Framing
    test(_TestFramerSplits)
    test(_TestFramerIncremental)
    test(_TestFramerTooLong)
    test(_TestFramerBounded)
    test(Property1UnitTest[USize](_PropFramerChunking))

    // Send pacing
    test(_TestOutboxPaces)
    test(_TestOutboxEarnsWhileIdle)
    test(_TestOutboxEarnsNoMoreThanTheBurst)
    test(_TestOutboxKeepsTheRemainder)
    test(_TestOutboxUrgent)
    test(_TestOutboxAtomic)
    test(_TestOutboxOrder)
    test(_TestOutboxClear)

    // Protocol states
    test(_TestStateRegisters)
    test(_TestStateNickFallback)
    test(_TestStateFatalNumerics)
    test(_TestStateSettles)
    test(_TestStateNoIsupport)
    test(_TestStatePingAlways)
    test(_TestStateSendGating)

    // Configuration
    test(_TestConfigAccepts)
    test(_TestConfigRejects)
    test(_TestConfigPlaintextOptIn)

    // A bot, tested the way a bot author would
    test(_TestBotWithoutNetwork)
