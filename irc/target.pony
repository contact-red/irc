type Target is (Nick | Channel)
  """
  Somewhere a message can be sent: one person or one channel.

  Which of the two a given name is depends on the server's `CHANTYPES`, so a
  bot that needs to know should ask `Registration.is_channel`. A bot deciding
  whether a message arrived privately should ask
  `Registration.private_to_me` -- matching on `Nick` here is not the same
  question, and gets it wrong on any network that has channel types beyond
  the ones `Channels` recognises.
  """
