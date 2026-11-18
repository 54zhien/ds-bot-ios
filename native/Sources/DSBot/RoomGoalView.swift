import UIKit

struct RoomGoalPresentation {
    struct Stage: Equatable {
        let title: String
        let status: String
    }

    let title: String
    let label: String
    let number: String?
    let stages: [Stage]
    let current: Int
    let status: String

    init(goal: JSONValue) {
        title = goal["title"]?.stringValue ?? ""
        status = goal["status"]?.stringValue ?? ""
        current = goal["current"]?.intValue ?? 0
        if case .array(let values)? = goal["stages"] {
            stages = values.map { Stage(title: $0["title"]?.stringValue ?? "", status: $0["status"]?.stringValue ?? "") }
        } else { stages = [] }
        let active = ["active", "paused"].contains(status) && stages.indices.contains(current)
        let currentStage = active ? stages[current] : nil
        let checking: Bool
        if active, case .array(let rawStages)? = goal["stages"],
           case .array(let tasks)? = rawStages[current]["tasks"] {
            checking = tasks.allSatisfy { ["reported", "done"].contains($0["status"]?.stringValue ?? "") }
        } else { checking = active }
        let index: Int?
        if status == "drafting" { index = nil }
        else if status == "stopped" { index = stages.filter { $0.status == "passed" }.count }
        else if active { index = current + 1 }
        else { index = stages.count }
        number = index.map { "\($0)/\(stages.count)" }
        if status == "drafting" { label = NativeLanguage.text("Aligning the goal with you") }
        else if status == "stopped" { label = NativeLanguage.text("Stopped") }
        else if status == "complete" { label = NativeLanguage.text("Goal reached") }
        else if status == "paused" {
            label = currentStage.map { NativeLanguage.text("Paused · {title}", ["title": $0.title]) }
                ?? NativeLanguage.text("Paused")
        } else if goal["idle"] == .bool(true) {
            label = currentStage.map { NativeLanguage.text("Waiting for you · {title}", ["title": $0.title]) }
                ?? NativeLanguage.text("Waiting for you")
        } else if let currentStage {
            label = checking ? NativeLanguage.text("Checking · {title}", ["title": currentStage.title]) : currentStage.title
        } else { label = NativeLanguage.text("Final check") }
    }
}

final class RoomGoalView: UIStackView {
    private var open = false
    private var goal: RoomGoalPresentation?
    var onHeightChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 6
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        isHidden = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggle))
        addGestureRecognizer(tap)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ value: RoomGoalPresentation?) {
        if goal?.title != value?.title { open = false }
        goal = value
        rebuild()
        onHeightChange?()
    }

    @objc private func toggle() {
        open.toggle()
        rebuild()
        onHeightChange?()
    }

    private func rebuild() {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        guard let goal else { isHidden = true; return }
        let heading = UIStackView()
        heading.axis = .horizontal
        heading.spacing = 8
        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .headline)
        title.text = goal.title
        title.lineBreakMode = .byTruncatingTail
        heading.addArrangedSubview(title)
        if let number = goal.number {
            let counter = UILabel()
            counter.font = .preferredFont(forTextStyle: .caption1)
            counter.textColor = .secondaryLabel
            counter.text = number
            heading.addArrangedSubview(counter)
        }
        addArrangedSubview(heading)
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = open ? 0 : 1
        label.text = goal.label
        addArrangedSubview(label)
        if !goal.stages.isEmpty {
            let segments = UIStackView()
            segments.axis = .horizontal
            segments.spacing = 3
            segments.distribution = .fillEqually
            for (index, stage) in goal.stages.enumerated() {
                let segment = UIView()
                segment.backgroundColor = stage.status == "passed" ? .systemGreen
                    : index == goal.current && ["active", "paused"].contains(goal.status) ? tintColor : .separator
                segment.layer.cornerRadius = 2
                segment.heightAnchor.constraint(equalToConstant: 3).isActive = true
                segments.addArrangedSubview(segment)
            }
            addArrangedSubview(segments)
        }
        if open {
            for (index, stage) in goal.stages.enumerated() {
                let row = UILabel()
                row.font = .preferredFont(forTextStyle: .subheadline)
                row.textColor = stage.status == "passed" ? .secondaryLabel : .label
                row.text = "\(index + 1)   \(stage.title)" + (stage.status == "passed" ? "  ✓" : "")
                row.numberOfLines = 0
                addArrangedSubview(row)
            }
        }
        accessibilityLabel = [goal.title, goal.number, goal.label].compactMap { $0 }.joined(separator: ", ")
        accessibilityValue = open ? "Expanded" : "Collapsed"
        isHidden = false
    }
}
