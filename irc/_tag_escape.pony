primitive _TagEscape
  """
  IRCv3 message-tag value escaping.

  `escape` and `unescape` are inverse. The escaped form can carry no raw CR,
  LF, semicolon or space, which is what keeps a reflected tag from ending the
  line early and starting a second one.
  """
  fun unescape(s: String box): String val =>
    let out = recover iso String(s.size()) end
    var pending_backslash = false

    for c in s.values() do
      if pending_backslash then
        pending_backslash = false
        match c
        | ':' => out.push(';')
        | 's' => out.push(' ')
        | 'r' => out.push('\r')
        | 'n' => out.push('\n')
        | '\\' => out.push('\\')
        else
          // The spec says a backslash before anything else is dropped.
          out.push(c)
        end
      elseif c == '\\' then
        pending_backslash = true
      else
        out.push(c)
      end
    end

    // A value ending in a lone backslash drops it, per the spec.
    consume out

  fun escape(s: String box): String val =>
    let out = recover iso String(s.size()) end

    for c in s.values() do
      match c
      | ';' => out.append("\\:")
      | ' ' => out.append("\\s")
      | '\r' => out.append("\\r")
      | '\n' => out.append("\\n")
      | '\\' => out.append("\\\\")
      else
        out.push(c)
      end
    end

    consume out
