import AppKit

/// Menyu ichidagi slayder qatori: [belgi va nom] [━━━●━━] [qiymat].
/// Surilgan zahoti sozlama o‘zgaradi va ekrandagi qor, odamlar, mashinalar darhol moslashadi —
/// menyu ochiq turganda ham (animatsiya taymerlari .common rejimda ishlaydi).
final class MenuSliderView: NSView {
    private let titleField: NSTextField
    private let valueField: NSTextField
    private let slider: NSSlider
    private let format: (Double) -> String
    private let onChange: (Double) -> Void

    init(title: String, value: Double, range: ClosedRange<Double>, step: Double? = nil,
         format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) {
        self.format = format
        self.onChange = onChange
        titleField = NSTextField(labelWithString: title)
        valueField = NSTextField(labelWithString: format(value))
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 30))

        titleField.font = NSFont.menuFont(ofSize: 0)
        titleField.frame = NSRect(x: 18, y: 6, width: 128, height: 18)
        titleField.lineBreakMode = .byTruncatingTail

        slider.frame = NSRect(x: 148, y: 5, width: 128, height: 20)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        if let step {
            let marks = Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1
            slider.numberOfTickMarks = marks
            slider.allowsTickMarkValuesOnly = true
        }

        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueField.textColor = .secondaryLabelColor
        valueField.alignment = .right
        valueField.frame = NSRect(x: 278, y: 6, width: 52, height: 18)

        addSubview(titleField)
        addSubview(slider)
        addSubview(valueField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let value = sender.doubleValue
        valueField.stringValue = format(value)
        onChange(value)
    }
}

/// Menyu ichidagi kichik kulrang izoh/sarlavha qatori.
final class MenuCaptionView: NSView {
    init(_ text: String, width: CGFloat = 340) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = width - 36
        let height = ceil(label.sizeThatFits(NSSize(width: width - 36, height: 200)).height) + 6
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        label.frame = NSRect(x: 18, y: 3, width: width - 36, height: height - 6)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }
}
