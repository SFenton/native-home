#if os(iOS)
import FentonActivityModel
import HassCore
import HassDesign
import UIKit

// MARK: - Ground

/// The dark ground with its radial glow, the UIKit counterpart of ``SignInGround``. At zero `glow` it is the plain launch colour,
/// which is how the intro starts.
final class UKSignInGroundView: UIView {
    private let glow = CAGradientLayer()

    /// 0 is the plain ground, 1 the full glow.
    var glowAlpha: CGFloat {
        get { CGFloat(glow.opacity) }
        set { glow.opacity = Float(newValue) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(rgb: SignInStyle.base)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        glow.type = .radial
        glow.colors = [UIColor(rgb: SignInStyle.glowCentre).cgColor, UIColor(rgb: SignInStyle.glowMiddle).cgColor,
                       UIColor(rgb: SignInStyle.base).cgColor]
        glow.locations = [0, 0.5, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.2)
        layer.addSublayer(glow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds
        // A radial gradient's end point is the corner of the box whose half-extents are the radius: radius = max side * 0.95.
        let radius = max(bounds.width, bounds.height) * 0.95
        let rx = bounds.width > 0 ? radius / bounds.width : 1
        let ry = bounds.height > 0 ? radius / bounds.height : 1
        glow.endPoint = CGPoint(x: 0.5 + rx, y: 0.2 + ry)
        CATransaction.commit()
    }
}

// MARK: - Marks

/// The bare house and heart, no tile and no container, in the house colour of the saved app icon; the heart's ring is cut out
/// of the house, so the ground shows through it (``SignInMark``).
final class UKSignInMarkView: UIView {
    private let shape = CAShapeLayer()

    init(icon: AppIconChoice, size: CGFloat = 96) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        shape.fillColor = UIColor(rgb: icon.glyph).cgColor
        shape.path = HouseHeartShape().path(in: CGRect(x: 0, y: 0, width: size, height: size)).cgPath
        layer.addSublayer(shape)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The person's monogram on a disc in the icon's colours, for the welcome back sign-in (``SignInMonogram``).
final class UKSignInMonogramView: UIView {
    private let label = UILabel()
    private let icon = UIImageView()
    private var size: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private let initials: String?

    init(name: String?, icon choice: AppIconChoice) {
        initials = ProfileButton.initials(name)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(rgb: choice.glyph)
        size = widthAnchor.constraint(equalToConstant: 88)
        heightConstraint = heightAnchor.constraint(equalToConstant: 88)
        NSLayoutConstraint.activate([size, heightConstraint])
        label.textColor = UIColor(rgb: choice.tint)
        label.textAlignment = .center
        icon.tintColor = UIColor(rgb: choice.tint)
        icon.contentMode = .center
        if let initials {
            label.text = initials
            addSubview(label)
        } else {
            addSubview(icon)
        }
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKSignInMonogramView, _) in view.restyle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The disc grows with the text size, like the initials in it.
    private func restyle() {
        let diameter = UKShellFont.scaled(88, relativeTo: .largeTitle, traits: traitCollection)
        size.constant = diameter
        heightConstraint.constant = diameter
        label.font = UKShellFont.preferred(.title1, weight: .semibold, design: .rounded, traits: traitCollection)
        icon.image = UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.title1, traits: traitCollection)))
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        label.frame = bounds
        icon.frame = bounds
    }
}

// MARK: - Fields

/// A text field with the sign-in rows' insets and no chrome.
final class UKLoginTextField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        borderStyle = .none
        textColor = .white
        tintColor = UIColor(rgb: HassTokens.Palette.tintText)
        adjustsFontForContentSizeCategory = true
        font = UKShellFont.preferred(.body)
        attributedPlaceholder = NSAttributedString(string: "")
        keyboardAppearance = .dark
    }

    /// Space above the text when the label sits above the field (accessibility sizes).
    var topInset: CGFloat = 0 { didSet { setNeedsLayout() } }
    override func textRect(forBounds bounds: CGRect) -> CGRect { super.textRect(forBounds: bounds).inset(by: UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { super.editingRect(forBounds: bounds).inset(by: UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// One row: its label, then its field. At accessibility sizes the label sits above the field instead of beside it, so neither
/// is squeezed (``LoginRow``).
final class UKLoginRowView: UIView {
    let label = UILabel()
    let field: UIView
    private let stack = UIStackView()
    private var labelWidth: NSLayoutConstraint?
    private var labelTop: NSLayoutConstraint?
    private var labelCentre: NSLayoutConstraint?
    /// The label's trailing bound at accessibility sizes, made once and switched on and off (not added again by every restyle).
    private var labelTrailing: NSLayoutConstraint?
    private var minHeight: NSLayoutConstraint!
    private var spansRow: Bool { field is UKLoginTextField }

    init(label text: String, field: UIView) {
        self.field = field
        super.init(frame: .zero)
        label.text = text
        label.textColor = .white
        label.adjustsFontForContentSizeCategory = true
        label.font = UKShellFont.preferred(.body)
        label.isAccessibilityElement = false
        label.numberOfLines = 0
        minHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        minHeight.isActive = true
        if spansRow {
            // The text field is the whole row (a 52 pt target), its text starting after the label column; the label is drawn over it.
            field.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
            addSubview(label)
            let width = label.widthAnchor.constraint(equalToConstant: 96)
            labelWidth = width
            labelTop = label.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.m)
            labelCentre = label.centerYAnchor.constraint(equalTo: centerYAnchor)
            labelTrailing = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -HassTokens.Spacing.l)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: leadingAnchor),
                field.trailingAnchor.constraint(equalTo: trailingAnchor),
                field.topAnchor.constraint(equalTo: topAnchor),
                field.bottomAnchor.constraint(equalTo: bottomAnchor),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.l),
                width, labelCentre!,
            ])
            label.isUserInteractionEnabled = false
        } else {
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.isLayoutMarginsRelativeArrangement = true
            addSubview(stack)
            let width = label.widthAnchor.constraint(equalToConstant: 96)
            labelWidth = width
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKLoginRowView, _) in view.restyle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The label wraps at the row's width (fixed by its parent) less its margins, or in its fixed column: never at its own width.
        let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if large {
            UKWrapWidth.set(label, in: self, reserving: 2 * HassTokens.Spacing.l)
        } else {
            UKWrapWidth.set(label, to: UKShellFont.scaled(96, relativeTo: .body, traits: traitCollection))
        }
    }

    private func restyle() {
        let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let base = UKShellFont.scaled(52, relativeTo: .body, traits: traitCollection)
        let labelColumn = UKShellFont.scaled(96, relativeTo: .body, traits: traitCollection)
        if let text = field as? UKLoginTextField {
            let spacing = HassTokens.Spacing.l
            let left = UIView(frame: CGRect(x: 0, y: 0, width: large ? spacing : spacing + labelColumn + HassTokens.Spacing.m, height: 1))
            text.leftView = left
            text.leftViewMode = .always
            let right = UIView(frame: CGRect(x: 0, y: 0, width: spacing, height: 1))
            text.rightView = right
            text.rightViewMode = .always
            labelCentre?.isActive = !large
            labelTop?.isActive = large
            labelWidth?.isActive = !large
            // At accessibility sizes the label sits above the field instead of beside it, so neither is squeezed.
            labelTrailing?.isActive = large
            text.topInset = large ? base * 0.6 : 0
            minHeight.constant = large ? base * 1.9 : base
            labelWidth?.constant = labelColumn
            return
        }
        stack.axis = large ? .vertical : .horizontal
        stack.alignment = large ? .fill : .center
        stack.spacing = large ? HassTokens.Spacing.xs : HassTokens.Spacing.m
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: large ? HassTokens.Spacing.m : 0, leading: HassTokens.Spacing.l,
                                                                 bottom: large ? HassTokens.Spacing.m : 0, trailing: HassTokens.Spacing.l)
        labelWidth?.isActive = !large
        labelWidth?.constant = labelColumn
        minHeight.constant = base
    }
}

/// The glass module with the server, username and password rows (``LoginFieldsModule``): a thin module fill, hairlines, 52 pt
/// rows. The Server row is first (owner, 2026-11-06; `.agents/design/house-config-states.md`, rule 1); welcome back shows the
/// server and the username read-only.
final class UKLoginFieldsModule: UIView {
    let serverField = UKLoginTextField()
    let usernameField = UKLoginTextField()
    let passwordField = UKLoginTextField()
    private let serverRow: UKLoginRowView
    private let serverReadonlyRow: UKLoginRowView
    private let serverReadonlyValue = UILabel()
    private let usernameRow: UKLoginRowView
    private let readonlyRow: UKLoginRowView
    private let readonlyValue = UILabel()
    private let passwordRow: UKLoginRowView
    private let stack = UIStackView()
    private let failureOutline = CAShapeLayer()
    private let serverOutline = CAShapeLayer()
    private let radius = HassTokens.Radius.module
    private let module = UKModuleView(.thin)
    private var showsFailure = false
    private var showsServerFailure = false

    override init(frame: CGRect) {
        serverRow = UKLoginRowView(label: LoginCopy.serverLabel, field: serverField)
        serverReadonlyRow = UKLoginRowView(label: LoginCopy.serverLabel, field: serverReadonlyValue)
        usernameRow = UKLoginRowView(label: "Username", field: usernameField)
        readonlyRow = UKLoginRowView(label: "Username", field: readonlyValue)
        passwordRow = UKLoginRowView(label: "Password", field: passwordField)
        super.init(frame: frame)
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(HassTokens.Palette.separatorDarkOpacity).cgColor
        // The thin module fill (opaque with Reduce Transparency).
        module.isUserInteractionEnabled = false
        module.isAccessibilityElement = false
        addSubview(module)
        module.ukPin(to: self)
        clipsToBounds = false

        serverField.keyboardType = .URL
        serverField.textContentType = .URL
        serverField.autocapitalizationType = .none
        serverField.autocorrectionType = .no
        serverField.spellCheckingType = .no
        serverField.smartDashesType = .no
        serverField.smartQuotesType = .no
        serverField.returnKeyType = .next
        serverField.clearButtonMode = .whileEditing
        serverField.attributedPlaceholder = NSAttributedString(
            string: LoginCopy.serverPlaceholder, attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.4)])
        serverField.accessibilityLabel = LoginCopy.serverAccessibilityLabel
        serverField.accessibilityIdentifier = "login.server"
        serverReadonlyValue.textColor = UIColor.white.withAlphaComponent(0.85)
        serverReadonlyValue.font = UKShellFont.preferred(.body)
        serverReadonlyValue.adjustsFontForContentSizeCategory = true
        serverReadonlyValue.numberOfLines = 1
        serverReadonlyValue.lineBreakMode = .byTruncatingMiddle
        serverReadonlyRow.isAccessibilityElement = true
        serverReadonlyRow.accessibilityIdentifier = "login.server.readonly"
        serverReadonlyRow.isHidden = true
        usernameField.textContentType = .username
        usernameField.autocapitalizationType = .none
        usernameField.autocorrectionType = .no
        usernameField.returnKeyType = .next
        usernameField.accessibilityLabel = "Username"
        usernameField.accessibilityIdentifier = "login.username"
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.accessibilityLabel = "Password"
        passwordField.accessibilityIdentifier = "login.password"
        readonlyValue.textColor = UIColor.white.withAlphaComponent(0.85)
        readonlyValue.font = UKShellFont.preferred(.body)
        readonlyValue.adjustsFontForContentSizeCategory = true
        readonlyRow.isAccessibilityElement = true
        readonlyRow.accessibilityIdentifier = "login.username.readonly"
        readonlyRow.isHidden = true
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        [serverRow, serverReadonlyRow, Self.hairline(), usernameRow, readonlyRow, Self.hairline(), passwordRow].forEach { stack.addArrangedSubview($0) }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for outline in [failureOutline, serverOutline] {
            outline.fillColor = nil
            outline.strokeColor = UIColor(rgb: SignInStyle.error).cgColor
            outline.lineWidth = 1
            outline.isHidden = true
            layer.addSublayer(outline)
        }
        serverRow.addGestureRecognizer(UITapGestureRecognizer(target: serverField, action: #selector(becomeFirstResponder)))
        passwordRow.addGestureRecognizer(UITapGestureRecognizer(target: passwordField, action: #selector(becomeFirstResponder)))
        usernameRow.addGestureRecognizer(UITapGestureRecognizer(target: usernameField, action: #selector(becomeFirstResponder)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the red hairline is drawn round the Server row.
    var showsServerOutline: Bool { !serverOutline.isHidden }

    /// Whether the red hairline is drawn round the Password row.
    var showsPasswordOutline: Bool { !failureOutline.isHidden }

    /// A hairline between two rows, inset from the leading edge like the rows' text.
    private static func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor.white.withAlphaComponent(HassTokens.Palette.separatorDarkOpacity)
        line.isAccessibilityElement = false
        let host = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: HassTokens.Spacing.l),
            line.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            line.topAnchor.constraint(equalTo: host.topAnchor),
            line.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        host.isAccessibilityElement = false
        return host
    }

    /// Shows a fresh sign-in (all three fields) or the welcome back variant (server and account read-only).
    /// - Parameter server: The server as the read-only row shows it (host and port).
    func configure(mode: LoginModel.Mode, username: String, server: String) {
        switch mode {
        case .fresh:
            serverRow.isHidden = false
            serverReadonlyRow.isHidden = true
            usernameRow.isHidden = false
            readonlyRow.isHidden = true
        case .welcomeBack:
            serverRow.isHidden = true
            serverReadonlyRow.isHidden = false
            serverReadonlyValue.text = server
            serverReadonlyRow.accessibilityLabel = "\(LoginCopy.serverLabel), \(server)"
            usernameRow.isHidden = true
            readonlyRow.isHidden = false
            readonlyValue.text = username
            readonlyRow.accessibilityLabel = "Username, \(username)"
        }
    }

    /// An address that is wrong, or does not answer as Home Assistant, gets a red hairline round the Server row (the module's top
    /// corners follow the module).
    func setServerRefused(_ refused: Bool) {
        showsServerFailure = refused
        serverOutline.isHidden = !refused
        setNeedsLayout()
    }

    /// A refused password gets a red hairline round its row (the module's bottom corners follow the module).
    func setPasswordRefused(_ refused: Bool) {
        showsFailure = refused
        failureOutline.isHidden = !refused
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if showsFailure {
            failureOutline.path = outlinePath(around: passwordRow, corners: [.bottomLeft, .bottomRight])
        }
        if showsServerFailure {
            serverOutline.path = outlinePath(around: serverRow.isHidden ? serverReadonlyRow : serverRow, corners: [.topLeft, .topRight])
        }
    }

    private func outlinePath(around row: UIView, corners: UIRectCorner) -> CGPath {
        let frame = row.convert(row.bounds, to: self)
        return UIBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), byRoundingCorners: corners,
                            cornerRadii: CGSize(width: radius, height: radius)).cgPath
    }
}

// MARK: - Failure

/// The red line under the fields for a refused password or an account that needs two-step sign-in (``LoginInlineError``).
final class UKLoginInlineErrorView: UIView {
    private let label = UILabel()
    private let icon = UIImageView()

    init(message: String) {
        super.init(frame: .zero)
        let color = UIColor(rgb: SignInStyle.error)
        icon.tintColor = color
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        label.textColor = color
        label.numberOfLines = 0
        label.text = message
        label.adjustsFontForContentSizeCategory = true
        label.font = UKShellFont.preferred(.subheadline)
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = HassTokens.Spacing.s
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: HassTokens.Spacing.s, bottom: 0, trailing: HassTokens.Spacing.s)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = message
        accessibilityIdentifier = "login.error"
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKLoginInlineErrorView, _) in view.restyle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func restyle() {
        icon.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.subheadline, traits: traitCollection)))
    }
}

/// The red card above the fields for a sign-in that did not reach Home Assistant or failed in a way the person cannot fix by
/// retyping: a plain-words title and body, and a Details disclosure with the raw reason (``LoginFailureCard``).
final class UKLoginFailureCardView: UIView {
    private let detailText: String?
    private let detailLabel = UILabel()
    private let chevron = UIImageView()
    private let detailsButton = UIControl()
    private var showsDetail = false
    var onToggle: () -> Void = {}

    init(title: String, message: String, detail: String?) {
        detailText = detail
        super.init(frame: .zero)
        let red = UIColor(rgb: SignInStyle.error)
        backgroundColor = red.withAlphaComponent(SignInStyle.errorWash)
        layer.cornerRadius = SignInStyle.cardRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = red.withAlphaComponent(SignInStyle.errorOutline).cgColor

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UKShellFont.preferred(.headline)
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.headline)))?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.append(NSAttributedString(string: "  " + title))
        attributed.addAttributes([.font: UKShellFont.preferred(.headline), .foregroundColor: UIColor.white], range: NSRange(location: 0, length: attributed.length))
        titleLabel.attributedText = attributed
        titleLabel.accessibilityLabel = title
        titleLabel.accessibilityTraits = .header
        let body = UILabel()
        body.numberOfLines = 0
        body.text = message
        body.textColor = UIColor.white.withAlphaComponent(0.85)
        body.adjustsFontForContentSizeCategory = true
        body.font = UKShellFont.preferred(.subheadline)

        let stack = UIStackView(arrangedSubviews: [titleLabel, body])
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.s
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.l, leading: HassTokens.Spacing.l,
                                                                 bottom: HassTokens.Spacing.l, trailing: HassTokens.Spacing.l)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if detail != nil {
            // A button, not a disclosure group: the whole row is the 44 pt target and says whether it is open.
            let row = UIStackView()
            row.axis = .horizontal
            row.isUserInteractionEnabled = false
            let name = UILabel()
            name.text = LoginCopy.detailsTitle
            name.textColor = .white
            name.adjustsFontForContentSizeCategory = true
            name.font = UKShellFont.preferred(.subheadline, weight: .semibold)
            chevron.image = UIImage(systemName: "chevron.right")
            chevron.tintColor = .white
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(name)
            row.addArrangedSubview(UIView())
            row.addArrangedSubview(chevron)
            row.translatesAutoresizingMaskIntoConstraints = false
            detailsButton.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: detailsButton.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: detailsButton.trailingAnchor),
                row.topAnchor.constraint(equalTo: detailsButton.topAnchor),
                row.bottomAnchor.constraint(equalTo: detailsButton.bottomAnchor),
                detailsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            ])
            detailsButton.isAccessibilityElement = true
            detailsButton.accessibilityLabel = LoginCopy.detailsTitle
            detailsButton.accessibilityTraits = .button
            detailsButton.accessibilityValue = "Collapsed"
            detailsButton.accessibilityIdentifier = "login.error.details"
            detailsButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
            stack.addArrangedSubview(detailsButton)
            detailLabel.numberOfLines = 0
            detailLabel.text = detail
            detailLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            detailLabel.adjustsFontForContentSizeCategory = true
            detailLabel.font = UKShellFont.preferred(.footnote, design: .monospaced)
            detailLabel.isHidden = true
            detailLabel.isUserInteractionEnabled = true
            detailLabel.accessibilityIdentifier = "login.error.detail"
            stack.addArrangedSubview(detailLabel)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        accessibilityIdentifier = "login.error.card"
        isAccessibilityElement = false
        accessibilityElements = [titleLabel, body] + (detail != nil ? [detailsButton] : [])
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func toggle() {
        showsDetail.toggle()
        detailsButton.accessibilityValue = showsDetail ? "Expanded" : "Collapsed"
        accessibilityElements = showsDetail ? [detailsButton, detailLabel] : [detailsButton]
        UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: .curveEaseOut) {
            self.detailLabel.isHidden = !self.showsDetail
            self.chevron.transform = CGAffineTransform(rotationAngle: self.showsDetail ? .pi / 2 : 0)
            self.superview?.layoutIfNeeded()
        }
        onToggle()
    }
}
#endif
