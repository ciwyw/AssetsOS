import Foundation
import SwiftUI
import UIKit

enum Money {
    static let scale = 2
    static let currencySymbol = "¥"

    static func parse(_ input: String) -> Decimal? {
        var cleaned = ""
        var sawDot = false
        for character in input {
            if character.isASCII && character.isNumber {
                cleaned.append(character)
            } else if character == "." || character == "。" || character == "．" {
                guard !sawDot else { continue }
                sawDot = true
                cleaned.append(".")
            } else if character == "-" || character == "−" {
                if cleaned.isEmpty { cleaned.append("-") }
            }
        }
        guard cleaned.contains(where: { $0.isNumber }) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func rounded(
        _ amount: Decimal,
        scale: Int = Money.scale,
        mode: NSDecimalNumber.RoundingMode = .plain
    ) -> Decimal {
        var result = Decimal()
        var source = amount
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    static func string(
        _ amount: Decimal,
        symbol: Bool = true,
        showsPositiveSign: Bool = false,
        fractionDigits: Int = Money.scale,
        minimumFractionDigits: Int? = nil,
        grouping: Bool = true
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.usesGroupingSeparator = grouping
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = minimumFractionDigits ?? fractionDigits
        formatter.roundingMode = .halfUp
        let roundedAmount = rounded(amount, scale: fractionDigits)
        let body = formatter.string(from: roundedAmount as NSDecimalNumber) ?? "0"

        var result = body
        if symbol {
            if body.hasPrefix("-") {
                result = "-" + currencySymbol + body.dropFirst()
            } else {
                result = currencySymbol + body
            }
        }
        if showsPositiveSign && roundedAmount > 0 {
            result = "+" + result
        }
        return result
    }

    static func percent(
        _ rate: Decimal,
        fractionDigits: Int = 2,
        showsPositiveSign: Bool = false
    ) -> String {
        let body = string(
            rate * 100,
            symbol: false,
            showsPositiveSign: showsPositiveSign,
            fractionDigits: fractionDigits,
            minimumFractionDigits: 0,
            grouping: false
        )
        return body + "%"
    }

    static func plainString(_ amount: Decimal, fractionDigits: Int = Money.scale) -> String {
        string(
            amount,
            symbol: false,
            fractionDigits: fractionDigits,
            minimumFractionDigits: 0,
            grouping: false
        )
    }
}

extension Decimal {
    var currencyText: String { Money.string(self) }
    var signedCurrencyText: String { Money.string(self, showsPositiveSign: true) }
    var percentText: String { Money.percent(self) }
    var absolute: Decimal { self < 0 ? -self : self }
    var isZeroAmount: Bool { self == .zero }

    static func money(_ text: String) -> Decimal {
        Money.parse(text) ?? .zero
    }
}

enum DateKit {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func today(_ now: Date = Date()) -> Date {
        startOfDay(now)
    }

    static func dayCount(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func dateOnlyString(_ date: Date) -> String {
        dateOnlyFormatter.string(from: startOfDay(date))
    }

    static func timestampString(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static func parseDateOnly(_ text: String) -> Date? {
        dateOnlyFormatter.date(from: text)
    }

    static func parseTimestamp(_ text: String) -> Date? {
        timestampFormatter.date(from: text)
    }

    static func shortDateText(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func fullDateText(_ date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    static func fullDateTimeText(_ date: Date) -> String {
        displayTimestampFormatter.string(from: date)
    }

    static func relativeDueText(_ maturityDate: Date, now: Date = Date()) -> String {
        let diff = dayCount(today(now), maturityDate)
        switch diff {
        case ..<0:
            return "已到期 \(-diff) 天"
        case 0:
            return "今天到期"
        case 1:
            return "明天到期"
        default:
            return "\(diff) 天后到期"
        }
    }

    static func notificationDate(for businessDate: Date, hour: Int = 9) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: startOfDay(businessDate))
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? businessDate
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private static let displayTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

enum AppTheme {
    static let accent = Color(red: 0.36, green: 0.53, blue: 0.57)
    static let accentLight = Color(red: 0.93, green: 0.96, blue: 0.96)
    static let gain = Color(red: 0.65, green: 0.31, blue: 0.29)
    static let loss = Color(red: 0.31, green: 0.49, blue: 0.38)
    static let warning = Color(red: 0.62, green: 0.50, blue: 0.27)
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    static func amountColor(_ amount: Decimal) -> Color {
        if amount > 0 { return gain }
        if amount < 0 { return loss }
        return .secondary
    }

    static func statusColor(_ status: FundingStatus) -> Color {
        switch status {
        case .direct: return Color(red: 0.29, green: 0.45, blue: 0.49)
        case .redeemable: return Color(red: 0.51, green: 0.65, blue: 0.69)
        case .locked: return Color(uiColor: .systemGray)
        case .receivable: return warning
        }
    }
}

struct SectionHeaderText: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct CardView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.84 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.84 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(foreground.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct RowSeparator: View {
    var inset: CGFloat = 14

    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
}

struct AmountField: View {
    @Binding private var amount: Decimal?
    private let placeholder: String
    private let showsCurrencySymbol: Bool
    private let fractionDigits: Int
    private let allowsNegative: Bool
    private let alignment: TextAlignment
    private let font: Font
    private let selectsAllOnFocus: Bool

    @State private var text: String
    @State private var didSelectAll = false

    init(
        amount: Binding<Decimal?>,
        placeholder: String = "0.00",
        showsCurrencySymbol: Bool = true,
        fractionDigits: Int = Money.scale,
        allowsNegative: Bool = false,
        alignment: TextAlignment = .trailing,
        font: Font = .system(size: 28, weight: .semibold, design: .rounded),
        selectsAllOnFocus: Bool = false
    ) {
        _amount = amount
        self.placeholder = placeholder
        self.showsCurrencySymbol = showsCurrencySymbol
        self.fractionDigits = fractionDigits
        self.allowsNegative = allowsNegative
        self.alignment = alignment
        self.font = font
        self.selectsAllOnFocus = selectsAllOnFocus
        _text = State(initialValue: Self.displayText(for: amount.wrappedValue, fractionDigits: fractionDigits))
    }

    init(
        amount: Binding<Decimal>,
        placeholder: String = "0.00",
        showsCurrencySymbol: Bool = true,
        fractionDigits: Int = Money.scale,
        allowsNegative: Bool = false,
        alignment: TextAlignment = .trailing,
        font: Font = .system(size: 28, weight: .semibold, design: .rounded),
        selectsAllOnFocus: Bool = false
    ) {
        let optionalBinding = Binding<Decimal?>(
            get: { amount.wrappedValue },
            set: { amount.wrappedValue = $0 ?? .zero }
        )
        self.init(
            amount: optionalBinding,
            placeholder: placeholder,
            showsCurrencySymbol: showsCurrencySymbol,
            fractionDigits: fractionDigits,
            allowsNegative: allowsNegative,
            alignment: alignment,
            font: font,
            selectsAllOnFocus: selectsAllOnFocus
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            if showsCurrencySymbol {
                Text(Money.currencySymbol)
                    .font(font)
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $text)
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(alignment)
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    pushToBinding(newValue)
                }
                .onChange(of: amount) { _, newValue in
                    pullFromBinding(newValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
                    selectAllIfNeeded(notification)
                }
        }
    }

    private func selectAllIfNeeded(_ notification: Notification) {
        guard selectsAllOnFocus, !didSelectAll, !text.isEmpty else { return }
        guard let field = notification.object as? UITextField, field.text == text else { return }
        didSelectAll = true
        DispatchQueue.main.async { field.selectAll(nil) }
    }

    private func pushToBinding(_ raw: String) {
        let normalized = normalize(raw)
        if normalized != text { text = normalized }
        let parsed = Money.parse(normalized)
        if parsed != amount { amount = parsed }
    }

    private func pullFromBinding(_ newValue: Decimal?) {
        if text.isEmpty && (newValue == nil || newValue == .zero) { return }
        guard Money.parse(text) != newValue else { return }
        text = Self.displayText(for: newValue, fractionDigits: fractionDigits)
    }

    private static func displayText(for amount: Decimal?, fractionDigits: Int) -> String {
        guard let amount else { return "" }
        return Money.string(
            amount,
            symbol: false,
            fractionDigits: fractionDigits,
            minimumFractionDigits: 0
        )
    }

    private func normalize(_ raw: String) -> String {
        var isNegative = false
        var integerDigits = ""
        var fractionDigits: String?

        for character in raw {
            if character.isASCII && character.isNumber {
                if fractionDigits == nil {
                    integerDigits.append(character)
                } else if fractionDigits!.count < self.fractionDigits {
                    fractionDigits!.append(character)
                }
            } else if character == "." || character == "。" || character == "．" {
                if self.fractionDigits > 0 && fractionDigits == nil {
                    fractionDigits = ""
                }
            } else if character == "-" || character == "−" {
                if allowsNegative && integerDigits.isEmpty && fractionDigits == nil {
                    isNegative = true
                }
            }
        }

        while integerDigits.count > 1 && integerDigits.hasPrefix("0") {
            integerDigits.removeFirst()
        }

        if integerDigits.isEmpty && fractionDigits == nil {
            return isNegative ? "-" : ""
        }

        var result = Self.grouped(integerDigits.isEmpty ? "0" : integerDigits)
        if let fractionDigits { result += "." + fractionDigits }
        return (isNegative ? "-" : "") + result
    }

    private static func grouped(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0 && offset % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return String(result.reversed())
    }
}

struct PercentField: View {
    @Binding private var percent: Decimal?
    var placeholder: String = "3.00"
    var fractionDigits: Int = 3
    var font: Font = .system(size: 28, weight: .semibold, design: .rounded)

    init(percent: Binding<Decimal?>, placeholder: String = "3.00", fractionDigits: Int = 3, font: Font = .system(size: 28, weight: .semibold, design: .rounded)) {
        _percent = percent
        self.placeholder = placeholder
        self.fractionDigits = fractionDigits
        self.font = font
    }

    init(percent: Binding<Decimal>, placeholder: String = "3.00", fractionDigits: Int = 3, font: Font = .system(size: 28, weight: .semibold, design: .rounded)) {
        let optionalBinding = Binding<Decimal?>(
            get: { percent.wrappedValue },
            set: { percent.wrappedValue = $0 ?? .zero }
        )
        _percent = optionalBinding
        self.placeholder = placeholder
        self.fractionDigits = fractionDigits
        self.font = font
    }

    var body: some View {
        HStack(spacing: 2) {
            AmountField(
                amount: $percent,
                placeholder: placeholder,
                showsCurrencySymbol: false,
                fractionDigits: fractionDigits,
                allowsNegative: false,
                alignment: .trailing,
                font: font
            )
            Text("%")
                .font(font)
                .foregroundStyle(.secondary)
        }
    }
}

struct WarningBanner: View {
    let title: String
    let message: String
    var tint: Color = AppTheme.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
