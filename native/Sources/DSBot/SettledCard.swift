import Foundation

/// The settled card items.tsx draws full width: a closed ask, a handoff's
/// answer, a view card's replies, or a question card's picks. The branch order
/// is the RN file's own, so an answer with none of these is no card — RN
/// renders that as the plain reply bubble, and so does the native list.
struct SettledPick {
    let letter: String
    let label: String
}

struct SettledQuestion {
    let question: String
    let picks: [SettledPick]
}

struct SettledReply {
    let title: String
    let detail: String
}

enum SettledCard {
    case closed(prompt: String, answered: Bool)
    /// A handoff's answer; a nil badge draws the check instead.
    case handoff(title: String, badge: String?)
    case views([SettledReply])
    case questions([SettledQuestion])
    case viewTitle(String)

    init?(item: JSONValue) {
        switch item["kind"]?.stringValue {
        case "closed":
            let prompt = item["question"]?["question"]?.stringValue
                ?? item["title"]?.stringValue ?? ""
            self = .closed(prompt: prompt, answered: item["closed"]?.stringValue == "replied")
        case "view":
            // A view with data is the live card the chat already opens, not this one.
            guard item["view"] == nil || item["view"] == .null else { return nil }
            self = .viewTitle(item["title"]?.stringValue ?? NativeLanguage.text("View"))
        case "answer":
            if let handoff = SettledCard.handoff(of: item) {
                let outcome = handoff["outcome"]?.stringValue
                self = .handoff(
                    title: SettledCard.handoffTitle(handoff["reason"]?.stringValue),
                    badge: outcome == "skipped" ? NativeLanguage.text("Skipped")
                        : outcome == "returned" ? NativeLanguage.text("Returned") : nil)
                return
            }
            let answers = SettledCard.array(item["answers"])
            let views = SettledCard.array(item["views"])
            if !views.isEmpty {
                self = .views(views.enumerated().map { index, entry in
                    let answer = SettledCard.answer(at: index, matching: entry["id"]?.stringValue, in: answers)
                    let detail = answer != nil && entry["view"] != nil && entry["view"] != .null
                        ? SettledCard.viewAnswerText(view: entry["view"] ?? .null, answer: answer ?? .null) : ""
                    return SettledReply(title: entry["title"]?.stringValue ?? "", detail: detail)
                })
                return
            }
            let questions = SettledCard.array(item["questions"])
            if !questions.isEmpty {
                self = .questions(questions.enumerated().map { index, question in
                    SettledQuestion(
                        question: question["question"]?.stringValue ?? "",
                        picks: SettledCard.picks(
                            question: question,
                            answer: SettledCard.answer(at: index, matching: question["id"]?.stringValue, in: answers)))
                })
                return
            }
            return nil
        default:
            return nil
        }
    }

    /// items.tsx:155-163: the handoff rides the item, or hides inside its text
    /// as JSON when no questions or views came along.
    private static func handoff(of item: JSONValue) -> JSONValue? {
        if let direct = item["handoff"], direct != .null { return direct }
        guard SettledCard.array(item["questions"]).isEmpty,
              SettledCard.array(item["views"]).isEmpty,
              let text = item["text"]?.stringValue,
              let data = text.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(JSONValue.self, from: data),
              parsed["kind"]?.stringValue == "answer_to_pending_handoff",
              parsed["reason"]?.stringValue != nil else { return nil }
        return parsed
    }

    /// settled.ts handoffTitleOf.
    static func handoffTitle(_ reason: String?) -> String {
        switch reason {
        case "sign-in": return NativeLanguage.text("Sign-in needed")
        case "verification": return NativeLanguage.text("Verification needed")
        case "confirmation": return NativeLanguage.text("Confirmation needed")
        default: return NativeLanguage.text("Your turn in the browser")
        }
    }

    /// settled.ts settledQuestionPicks: a pick's letter is its option's index,
    /// and a custom answer takes the first letter past the options.
    static func picks(question: JSONValue?, answer: JSONValue?) -> [SettledPick] {
        let options = SettledCard.array(question?["options"]).map { option in
            option["label"]?.stringValue ?? option.stringValue ?? ""
        }
        let selected = answer?["selected"]?.stringArrayValue ?? []
        var result = selected.enumerated().map { index, label -> SettledPick in
            SettledPick(letter: SettledCard.letter(options.firstIndex(of: label) ?? index), label: label)
        }
        if let custom = answer?["custom"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            result.append(SettledPick(letter: SettledCard.letter(options.count), label: custom))
        }
        return result
    }

    /// deep-view reply.js viewAnswerText: the answer as one short line, built
    /// from the labels the user saw.
    static func viewAnswerText(view: JSONValue, answer: JSONValue) -> String {
        guard let values = answer["values"], case .object = values else { return "" }
        var parts: [String] = []
        if case .array(let selected)? = values["selected"] {
            let labels = SettledCard.optionLabels(of: view)
            parts.append(contentsOf: selected.map { value in
                let text = SettledCard.scalarText(value)
                return labels[text] ?? text
            })
        } else if case .bool(let confirmed)? = values["confirmed"] {
            let labels = SettledCard.actionLabels(of: view, action: answer["action"]?.stringValue)
            parts.append(confirmed ? (labels.confirm ?? "Confirmed") : (labels.cancel ?? "Cancelled"))
        } else if case .object(let fields)? = values["fields"] {
            let labels = SettledCard.fieldLabels(of: view)
            parts.append(contentsOf: fields.keys.sorted().map { key in
                "\(labels[key] ?? key): \(SettledCard.scalarText(fields[key]))"
            })
        }
        if case .object(let inputs)? = values["inputs"] {
            let labels = SettledCard.inputLabels(of: view)
            parts.append(contentsOf: inputs.keys.sorted().map { key in
                "\(labels[key] ?? key)=\(SettledCard.scalarText(inputs[key]))"
            })
        }
        let text = parts.joined(separator: "; ")
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    private static func array(_ value: JSONValue?) -> [JSONValue] {
        if case .array(let items)? = value { return items }
        return []
    }

    private static func answer(at index: Int, matching id: String?, in answers: [JSONValue]) -> JSONValue? {
        if let id, let match = answers.first(where: { $0["id"]?.stringValue == id }) { return match }
        return index < answers.count ? answers[index] : nil
    }

    private static func letter(_ index: Int) -> String {
        guard let scalar = UnicodeScalar(UInt32(max(0, index) + 65)) else { return "A" }
        return String(scalar)
    }

    private static func eachNode(_ view: JSONValue, visit: (JSONValue) -> Void) {
        visit(view)
        for child in SettledCard.array(view["children"]) {
            SettledCard.eachNode(child, visit: visit)
        }
    }

    /// reply.js keys one label map by the option's own label and by its value,
    /// so either resolves to the label the user saw.
    private static func optionLabels(of view: JSONValue) -> [String: String] {
        var labels: [String: String] = [:]
        SettledCard.eachNode(view) { node in
            for option in SettledCard.array(node["options"]) {
                guard let label = option["label"]?.stringValue else { continue }
                labels[label] = label
                if let value = option["value"]?.stringValue { labels[value] = label }
            }
        }
        return labels
    }

    private static func actionLabels(of view: JSONValue, action: String?) -> (confirm: String?, cancel: String?) {
        var confirm: String?
        var cancel: String?
        SettledCard.eachNode(view) { node in
            if confirm == nil, node["id"]?.stringValue == action {
                confirm = node["confirmLabel"]?.stringValue
                cancel = node["cancelLabel"]?.stringValue
            }
        }
        return (confirm, cancel)
    }

    private static func fieldLabels(of view: JSONValue) -> [String: String] {
        var labels: [String: String] = [:]
        SettledCard.eachNode(view) { node in
            for field in SettledCard.array(node["fields"]) {
                let id = field["id"]?.stringValue ?? ""
                labels[id] = field["label"]?.stringValue ?? id
            }
        }
        return labels
    }

    private static func inputLabels(of view: JSONValue) -> [String: String] {
        var labels: [String: String] = [:]
        SettledCard.eachNode(view) { node in
            if let id = node["id"]?.stringValue {
                labels[id] = node["label"]?.stringValue ?? id
            }
        }
        return labels
    }

    private static func scalarText(_ value: JSONValue?) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number):
            return number == number.rounded() ? String(format: "%.0f", number) : String(number)
        case .bool(let flag): return flag ? "true" : "false"
        default: return ""
        }
    }
}
