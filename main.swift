//
//  main.swift
//  regexToSPML
//
// Created by ChatGPT.
// Output is not very efficient, but at least it provides
// a starting point. Several things that this code believes
// are "unsupported" have easy workarounds. The SPML documentation
// covers those workarounds.
//
// See Example at the end of this file for a sample invocation.


// RegexToSPML.swift
// Translates a classic regex string into SPML code and prints it.
// Assumptions emitted in the generated code:
// - Anchored matching mirrors ^ / $ via bol/eol (or bos/eos for \A/\z)
// - Dot (.) does NOT match newline by default
// - DOTALL (dot includes newline) is only recognized if you set `dotAll = true` manually below
// - For single characters, generator may choose c/ci; for longer literals s/si
//
// Notes:
// - Unsupported constructs produce a stub: /* TODO: ... (unsupported) */
// - Alternation is classic backtracking (tail in each arm)
// - Look-ahead uses _peek helpers; look-behind only supports fixed literals if present
// - Character classes [ ... ] -> ASCII-only predicate blocks (ranges + singles)

public final class RegexToSPML
{
    // Toggle if you want global DOTALL; you can add parsing for (?s) if desired.
    private var dotAll = false
    // Toggle if you want global case-insensitive; simple support, not full inline-scope parsing.
    private var ignoreCase = false

    public init() {}

    // MARK: - Public entrypoint

    public func emitSPML(_ pattern: String)
    {
        var i = pattern.startIndex
        let ast = parseExpression(pattern, &i)
        if i != pattern.endIndex
        {
            print("/* ERROR: Unparsed trailing input near index \(pattern.distance(from: pattern.startIndex, to: i)) */")
        }

        var out: [String] = []
        var indent = 0
        func line(_ s: String) { out.append(String(repeating: "   ", count: indent) + s) }

        // Header
        line("let p = Pattern()")
        line("")
        line("let ok = p.match(haystack)")
        line("{")
        indent += 1
        let body = emitNode(ast, tail: "return true")
        out.append(contentsOf: body.map { String(repeating: "   ", count: indent) + $0 })
        indent -= 1
        line("}")

        // Print to stdout
        print(out.joined(separator: "\n"))
    }

    // MARK: - AST

    private indirect enum Node
    {
        case sequence([Node])
        case alternation([Node])
        case group(Node, capturing: Bool)
        case literal(String)
        case dot
        case anchorBOL, anchorEOL
        case anchorBOS, anchorEOS
        case cls(CharClass)          // character class
        case escapeClass(Esc)        // \d \D \w \W \s \S
        case quantifier(Node, Q)     // atom + quantifier
        case stub(String)            // unsupported
    }

    private enum Esc { case d, D, w, W, s, S }

    private struct CharClass
    {
        var negated: Bool
        var singles: [Character] = []
        var ranges:  [(Character, Character)] = []
    }

    private enum Q
    {
        case zeroOrMore(greedy: Bool)
        case oneOrMore(greedy: Bool)
        case zeroOrOne(greedy: Bool)
        case exact(Int)
        case atLeast(Int, greedy: Bool)
        case between(Int, Int, greedy: Bool)
    }

    // MARK: - Parser (simplified, handles common constructs)

    private func parseExpression(_ s: String, _ i: inout String.Index) -> Node
    {
        var terms: [Node] = [parseTerm(s, &i)]
        var arms: [[Node]] = []

        while i < s.endIndex, s[i] == "|"
        {
            i = s.index(after: i)
            arms.append(terms)
            terms = [parseTerm(s, &i)]
        }
        // Finish last arm/term
        if !arms.isEmpty
        {
            arms.append(terms)
            return .alternation(arms.map { .sequence($0) })
        }
        return .sequence(terms)
    }

    private func parseTerm(_ s: String, _ i: inout String.Index) -> Node
    {
        var nodes: [Node] = []
        while i < s.endIndex
        {
            let c = s[i]
            if c == "|" || c == ")" { break }
            nodes.append(parseFactor(s, &i))
        }
        return .sequence(nodes)
    }

    private func parseFactor(_ s: String, _ i: inout String.Index) -> Node
    {
        let atom = parseAtom(s, &i)

        guard i < s.endIndex else { return atom }
        let c = s[i]
        switch c
        {
            case "*","+", "?", "{":
                var greedy = true
                var q: Q
                if c == "*" {
                    i = s.index(after: i)
                    if i < s.endIndex, s[i] == "?" { greedy = false; i = s.index(after: i) }
                    q = .zeroOrMore(greedy: greedy)
                }
                else if c == "+" {
                    i = s.index(after: i)
                    if i < s.endIndex, s[i] == "?" { greedy = false; i = s.index(after: i) }
                    q = .oneOrMore(greedy: greedy)
                }
                else if c == "?" {
                    i = s.index(after: i)
                    if i < s.endIndex, s[i] == "?" { greedy = false; i = s.index(after: i) }
                    q = .zeroOrOne(greedy: greedy)
                }
                else {
                    // {n}, {n,}, {n,m} with optional lazy '?'
                    i = s.index(after: i)
                    let start = i
                    var digits = ""
                    while i < s.endIndex, s[i].isNumber {
                        digits.append(s[i]); i = s.index(after: i)
                    }
                    guard !digits.isEmpty else { return .stub("/* TODO: malformed quantifier '{}' */") }
                    let n = Int(digits) ?? 0
                    var m: Int? = nil
                    if i < s.endIndex, s[i] == "}" {
                        i = s.index(after: i)
                        greedy = true
                        if i < s.endIndex, s[i] == "?" { greedy = false; i = s.index(after: i) }
                        q = .exact(n)
                    }
                    else if i < s.endIndex, s[i] == "," {
                        i = s.index(after: i)
                        var digits2 = ""
                        while i < s.endIndex, s[i].isNumber {
                            digits2.append(s[i]); i = s.index(after: i)
                        }
                        if i < s.endIndex, s[i] == "}" {
                            i = s.index(after: i)
                            greedy = true
                            if i < s.endIndex, s[i] == "?" { greedy = false; i = s.index(after: i) }
                            if digits2.isEmpty {
                                q = .atLeast(n, greedy: greedy)
                            } else {
                                m = Int(digits2)
                                q = .between(n, m ?? n, greedy: greedy)
                            }
                        } else {
                            return .stub("/* TODO: malformed quantifier '{\(s[start..<i])' */")
                        }
                    } else {
                        return .stub("/* TODO: malformed quantifier '{\(s[start..<i])' */")
                    }
                }
                return .quantifier(atom, q)
            default:
                return atom
        }
    }

    private func parseAtom(_ s: String, _ i: inout String.Index) -> Node
    {
        guard i < s.endIndex else { return .sequence([]) }
        let c = s[i]

        // Anchors
        if c == "^" { i = s.index(after: i); return .anchorBOL }
        if c == "$" { i = s.index(after: i); return .anchorEOL }

        switch c
        {
            case "(":
                i = s.index(after: i)
                // Look-arounds & flags stubs
                if i < s.endIndex, s[i] == "?" {
                    let j = s.index(after: i)
                    if j < s.endIndex {
                        let mark = s[j]
                        // Common look-arounds
                        if mark == "=" { return consumeGroupStub("(?=…)", s, &i) }
                        if mark == "!" { return consumeGroupStub("(?!…)", s, &i) }
                        if mark == "<" {
                            let k = s.index(after: j)
                            guard k < s.endIndex else { return .stub("/* TODO: malformed look-behind */") }
                            let next = s[k]
                            if next == "=" { return consumeGroupStub("(?<=…)", s, &i) }
                            if next == "!" { return consumeGroupStub("(?<!…)", s, &i) }
                            return .stub("/* TODO: malformed look-behind */")
                        }
                        // Non-capturing group (?:...) – treat as normal group
                        if mark == ":" {
                            i = s.index(i, offsetBy: 2) // skip '?:'
                            let node = parseExpression(s, &i)
                            if i < s.endIndex, s[i] == ")" { i = s.index(after: i) }
                            return .group(node, capturing: false)
                        }
                        // Inline flags (?i), (?m), (?s) – simple support: set global and stub scope.
                        if mark == "i" || mark == "m" || mark == "s" {
                            // Consume until ')'
                            while i < s.endIndex, s[i] != ")" { i = s.index(after: i) }
                            if i < s.endIndex { i = s.index(after: i) }
                            // Set global toggles superficially
                            if mark == "i" { ignoreCase = true }
                            if mark == "s" { dotAll = true }
                            // Continue with empty sequence
                            return .sequence([])
                        }
                    }
                }
                // Normal capturing group
                let inner = parseExpression(s, &i)
                if i < s.endIndex, s[i] == ")" { i = s.index(after: i) }
                return .group(inner, capturing: true)

            case ")":
                // Let caller handle the ')'
                return .sequence([])

            case "[":
                return parseCharClass(s, &i)

            case ".":
                i = s.index(after: i)
                return .dot

            case "\\":
                i = s.index(after: i)
                guard i < s.endIndex else { return .stub("/* TODO: dangling escape */") }
                let e = s[i]
                i = s.index(after: i)
                switch e
                {
                    case "d": return .escapeClass(.d)
                    case "D": return .escapeClass(.D)
                    case "w": return .escapeClass(.w)
                    case "W": return .escapeClass(.W)
                    case "s": return .escapeClass(.s)
                    case "S": return .escapeClass(.S)
                    case "A": return .anchorBOS
                    case "z": return .anchorEOS
                    // Backreferences, named groups, unicode props: stub
                    case "1","2","3","4","5","6","7","8","9":
                        return .stub("/* TODO: backreference \\\(e) unsupported */")
                    default:
                        // escaped literal char
                        return .literal(String(e))
                }

            default:
                // Gather a run of plain literal chars (stop at metachars)
                var j = i
                var buf = ""
                while j < s.endIndex
                {
                    let ch = s[j]
                    if "^$.*+?()[]{}\\|".contains(ch) { break }
                    buf.append(ch)
                    j = s.index(after: j)
                }
                i = j
                return .literal(buf)
        }
    }

    private func parseCharClass(_ s: String, _ i: inout String.Index) -> Node
    {
        var cls = CharClass(negated: false)
        // assume s[i] == "["
        i = s.index(after: i)
        if i < s.endIndex, s[i] == "^" { cls.negated = true; i = s.index(after: i) }

        var lastChar: Character? = nil
        while i < s.endIndex, s[i] != "]"
        {
            let c = s[i]
            if c == "\\" {
                i = s.index(after: i)
                if i < s.endIndex {
                    let esc = s[i]; i = s.index(after: i)
                    lastChar = esc
                    cls.singles.append(esc)
                }
                continue
            }
            if c == "-" {
                // range a-z
                if let lo = lastChar, i < s.endIndex {
                    i = s.index(after: i)
                    if i < s.endIndex, s[i] != "]" {
                        let hi = s[i]
                        cls.ranges.append((lo, hi))
                        lastChar = nil
                        i = s.index(after: i)
                        continue
                    }
                }
                // treat as literal '-'
                cls.singles.append("-")
                lastChar = "-"
                continue
            }
            // literal char
            lastChar = c
            cls.singles.append(c)
            i = s.index(after: i)
        }
        if i < s.endIndex, s[i] == "]" { i = s.index(after: i) }
        return .cls(cls)
    }

    private func consumeGroupStub(_ label: String, _ s: String, _ i: inout String.Index) -> Node
    {
        // advance to matching ')'
        var depth = 1
        i = s.index(i, offsetBy: 2) // after (?X or (?<
        while i < s.endIndex, depth > 0
        {
            if s[i] == "(" { depth += 1 }
            if s[i] == ")" { depth -= 1 }
            i = s.index(after: i)
        }
        return .stub("/* TODO: \(label) not directly supported; rewrite or use peek helpers */")
    }

    // MARK: - Emitter

    private func emitNode(_ node: Node, tail: String) -> [String]
    {
        switch node
        {
            case .sequence(let arr):
                return emitSequence(arr, tail: tail)

            case .alternation(let arms):
                // classic alternation: tail inside each arm
                var lines: [String] = []
                lines.append("return")
                for (idx, arm) in arms.enumerated()
                {
                    lines.append(idx == 0 ? "   (" : "|| (")
                    lines.append("      { () -> Bool in")
                    lines.append(contentsOf: emitNode(arm, tail: "return true").map { "         " + $0 })
                    lines.append("      }()")
                    lines.append("   )")
                }
                // add final tail? Classic alternation already ends with its own returns.
                // If you need a shared tail outside (atomic style), change strategy.
                return lines

            case .group(let inner, _):
                return emitNode(inner, tail: tail)

            case .literal(let lit):
                guard !lit.isEmpty else { return [tail] }
                if lit.count == 1
                {
                    let c = lit
                    let fn = ignoreCase ? "ci" : "c"
                    return ["return p.\(fn)(\"\(escapeString(c))\")",
                            "{",
                            "   \(tail)",
                            "}"]
                }
                else
                {
                    let fn = ignoreCase ? "si" : "s"
                    return ["return p.\(fn)(\"\(escapeString(lit))\")",
                            "{",
                            "   \(tail)",
                            "}"]
                }

            case .dot:
                if dotAll
                {
                    return ["return p.skip(1)",
                            "{",
                            "   \(tail)",
                            "}"]
                }
                else
                {
                    return ["return p.any",
                            "{",
                            "   \(tail)",
                            "}"]
                }

            case .escapeClass(let e):
                switch e
                {
                    case .d:
                        return ["return p.aDigit",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .D:
                        return emitNegatedDigit(tail)
                    case .w:
                        return ["return p.oneWordChar",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .W:
                        return emitNegatedWord(tail)
                    case .s:
                        return emitWhitespace(tail, negated: false)
                    case .S:
                        return emitWhitespace(tail, negated: true)
                }

            case .cls(let cc):
                return emitClass(cc, tail)

            case .anchorBOL:
                return ["return p.bol",
                        "{",
                        "   \(tail)",
                        "}"]
            case .anchorEOL:
                return ["return p.eol",
                        "{",
                        "   \(tail)",
                        "}"]
            case .anchorBOS:
                return ["return p.bos",
                        "{",
                        "   \(tail)",
                        "}"]
            case .anchorEOS:
                return ["return p.eos",
                        "{",
                        "   \(tail)",
                        "}"]

            case .quantifier(let atom, let q):
                let block = emitAsBlock(atom)
                switch q
                {
                    case .zeroOrMore(let g):
                        let fn = g ? "zeroOrMorePat" : "zeroOrMorePat_lazy"
                        return ["return p.\(fn)(block: \(block))",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .oneOrMore(let g):
                        let fn = g ? "oneOrMorePat" : "oneOrMorePat_lazy"
                        return ["return p.\(fn)(block: \(block))",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .zeroOrOne(let g):
                        let fn = g ? "zeroOrOnePat" : "zeroOrOnePat_lazy"
                        return ["return p.\(fn)(block: \(block))",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .exact(let n):
                        return ["return p.nPat(n: \(n), block: \(block))",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .atLeast(let n, let g):
                        let fn = g ? "nTomPat" : "nTomPat_lazy"
                        return ["return p.\(fn)(n: \(n), m: .max, block: \(block))",
                                "{",
                                "   \(tail)",
                                "}"]
                    case .between(let n, let m, let g):
                        let fn = g ? "nTomPat" : "nTomPat_lazy"
                        return ["return p.\(fn)(n: \(n), m: \(m), block: \(block))",
                                "{",
                                "   \(tail)",
                                "}"]
                }

            case .stub(let msg):
                return ["/* \(msg) */", tail]
        }
    }

    private func emitSequence(_ parts: [Node], tail: String) -> [String]
    {
        guard let first = parts.first else { return [tail] }
        if parts.count == 1 { return emitNode(first, tail: tail) }
        // Recurse: first + (rest)
        let rest = Array(parts.dropFirst())
        let inner = emitSequence(rest, tail: tail)
        var lines = emitNode(first, tail: "return true")
        // Replace the 'return true' at the end with the nested body
        // Easiest: emitNode(first, tail: "return true") produces a block; append the rest as a nested block.
        // Instead, just wrap: after first's tail, insert the remaining code at the same indent.
        // Here we just replace the last "return true" with the rest lines.
        if let idx = lines.lastIndex(of: "return true")
        {
            lines.remove(at: idx)
            lines.append(contentsOf: inner)
        }
        else
        {
            lines.append(contentsOf: inner)
        }
        return lines
    }

    private func emitAsBlock(_ node: Node) -> String
    {
        // Produce a (PatClosure)->Bool block text for "one unit" of `node`.
        // We wrap the node’s emission with a tail that just propagates.
        let unit = emitNode(node, tail: "return tail()")
        let body = unit.map { "      " + $0 }.joined(separator: "\n")
        return "{ tail in\n\(body)\n   }"
    }

    private func emitNegatedDigit(_ tail: String) -> [String]
    {
        return [
            "return { () -> Bool in",
            "   if p.cursor >= p.endStr { return false }",
            "   if let b = p.haystack[p.cursor].asciiValue, (b >= 48 && b <= 57) { return false }",
            "   p.incCursor()",
            "   return true",
            "}()",
            "{",
            "   \(tail)",
            "}"
        ]
    }

    private func emitNegatedWord(_ tail: String) -> [String]
    {
        return [
            "return { () -> Bool in",
            "   if p.cursor >= p.endStr { return false }",
            "   let ch = p.haystack[p.cursor]",
            "   let isWord = ch.isLetter || ch.isNumber || ch == \"_\"",
            "   if isWord { return false }",
            "   p.incCursor()",
            "   return true",
            "}()",
            "{",
            "   \(tail)",
            "}"
        ]
    }

    private func emitWhitespace(_ tail: String, negated: Bool) -> [String]
    {
        return [
            "return { () -> Bool in",
            "   if p.cursor >= p.endStr { return false }",
            "   let ch = p.haystack[p.cursor]",
            "   let ws = ch.isWhitespace",
            "   if \(negated ? "ws" : "!ws") { return false }",
            "   p.incCursor()",
            "   return true",
            "}()",
            "{",
            "   \(tail)",
            "}"
        ]
    }

// Build code for a bracket class [ ... ] with optional negation.
// ASCII chars are tested via `asciiValue` (byte `b`), non-ASCII via `Character` comparisons (`ch`).

private func emitClass(_ cc: CharClass, _ tail: String) -> [String]
{
    // Collect ASCII vs non-ASCII tests separately
    var asciiConds: [String] = []
    var uniConds:  [String] = []

    for (lo, hi) in cc.ranges
    {
        if let loB = lo.asciiValue, let hiB = hi.asciiValue
        {
            asciiConds.append("(b >= \(loB) && b <= \(hiB))")
        }
        else
        {
            let loS = escapeString(String(lo))
            let hiS = escapeString(String(hi))
            uniConds.append("(ch >= \"\(loS)\" && ch <= \"\(hiS)\")")
        }
    }

    for ch in cc.singles
    {
        if let b = ch.asciiValue
        {
            asciiConds.append("(b == \(b))")
        }
        else
        {
            let s = escapeString(String(ch))
            uniConds.append("(ch == \"\(s)\")")
        }
    }

    // Join expressions (use "false" when empty so negation works correctly)
    let asciiExpr = asciiConds.isEmpty ? "false" : asciiConds.joined(separator: " || ")
    let uniExpr   = uniConds.isEmpty  ? "false" : uniConds.joined(separator: " || ")

    // Final pass conditions per branch (apply negation once)
    let passASCII = cc.negated ? "!(\(asciiExpr))" : "(\(asciiExpr))"
    let passUNI   = cc.negated ? "!(\(uniExpr))"   : "(\(uniExpr))"

    return [
        "return { () -> Bool in",
        "   if p.cursor >= p.endStr { return false }",
        "   let ch = p.haystack[p.cursor]",
        "   if let b = ch.asciiValue",
        "   {",
        "      if \(passASCII) { p.incCursor(); return true }",
        "      return false",
        "   }",
        "   if \(passUNI) { p.incCursor(); return true }",
        "   return false",
        "}()",
        "{",
        "   \(tail)",
        "}"
    ]
}


    private func escapeString(_ s: String) -> String
    {
        var out = ""
        for c in s
        {
            switch c {
                case "\\": out.append("\\\\")
                case "\"": out.append("\\\"")
                case "\n": out.append("\\n")
                case "\r": out.append("\\r")
                case "\t": out.append("\\t")
                default:   out.append(c)
            }
        }
        return out
    }
}

// MARK: Example call

// ExampleRegexToSPML.swift
// Simple driver that feeds several regex strings to the generator
// and prints the SPML it generates.


struct Example
{
    static func main()
    {
        let gen = RegexToSPML()

        // A few representative patterns:
        let patterns: [String] =
        [
            #"^[0-9]+ABC.+$"#,                 // Anchored, +, literal, dot (no NL)
            #"(?s)^[0-9]+ABC.+$"#,             // Same but DOTALL via (?s)
            #"^(\w+)-(\d{2,4})$"#,             // Groups, \w, bounded {m,n}
            #"ab|cd|ef"#,                      // Alternation
            #"foo[0-9A-Fa-f]{2,8}bar"#,        // Class + range + bounded quantifier
            #"^\s*\#\w+[^\n]*$"#,              // Escapes, \s, negated class
            #"(?=ABC)XYZ"#,                    // Look-ahead (will emit a TODO stub)
            #"(?<=ab+)X"#,                     // Variable-length look-behind (stub)
            #"^([A-Z]+)\1$"#                   // Backreference (stub)
        ]

        for pat in patterns
        {
            print("/* ---------------- REGEX ---------------- */")
            print(pat)
            print("/* --------------- GENERATED ------------- */")
            gen.emitSPML(pat)
            print("\n")
        }
    }
}

Example.main()

