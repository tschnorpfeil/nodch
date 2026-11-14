// Adapted from Pippa: app/Sources/Pippa/App/IslandPresenter.swift
import AppKit
import NodchCore
import QuartzCore
import SwiftUI

/// Clear, borderless, non-activating window at menu bar level on every Space, also beside full-screen apps. It may
/// become key only while the card is open (`allowsKey`), and only when the person clicks into it or presses the
/// shortcut: an approval that opens the card by itself never takes the keyboard from the app in front.
final class IslandPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        title = "nodch"
        setAccessibilityLabel("nodch")
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    /// ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z in the prompt: no menu bar would deliver them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, EditShortcuts.perform(event, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// SwiftUI on the island: the first click counts, also while another app is active.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Draws the black silhouette and reveals the two contents inside it: the compact wing, and the open card. Files
/// dropped anywhere on the shape, closed or open, go to the quick prompt.
final class IslandView: NSView {
    let compact: IslandHostingView<IslandCompactView>
    let panel: IslandHostingView<IslandPanelView>
    let model: IslandModel
    private let clip = NSView()
    private var silhouette: IslandSilhouette?
    private var fillAlpha: CGFloat = 1
    /// Window origin in global coordinates; the geometry is global.
    private var origin = CGPoint.zero
    var onPanelShown: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    /// A file drag is over the shape (true) or left it.
    var onDragOver: ((Bool) -> Void)?
    var onDrop: (([DroppedFile]) -> Void)?

    init(model: IslandModel, onHeight: @escaping (CGFloat) -> Void) {
        self.model = model
        compact = IslandHostingView(rootView: IslandCompactView(model: model))
        panel = IslandHostingView(rootView: IslandPanelView(model: model, onHeight: onHeight))
        super.init(frame: .zero)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.autoresizesSubviews = false
        // Only `show` sizes the contents; their own sizing would fight the animation.
        compact.sizingOptions = []
        panel.sizingOptions = []
        clip.addSubview(compact)
        clip.addSubview(panel)
        addSubview(clip)
        registerForDraggedTypes(DropReader.types)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Drops
    // Adapted from Pippa: app/Sources/Pippa/App/DropHostingView.swift

    private func dragTarget(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let inside = DropReader.carriesFiles(sender.draggingPasteboard) && shapeContains(convert(sender.draggingLocation, from: nil))
        onDragOver?(inside)
        return inside ? .copy : []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { dragTarget(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { dragTarget(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { onDragOver?(false) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { !dragTarget(sender).isEmpty }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender) else { return false }
        DropReader.read(sender.draggingPasteboard) { [weak self] files in self?.onDrop?(files) }
        return true
    }

    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    /// Lays out one moment: the compact shape `compactShape` (rest or wing, maybe mid-change) grown toward the open
    /// card `openRect` by `open`. `compactTarget` is where the compact content sits; `compactAlpha` how much of it
    /// shows. `contentRect` holds the card's content laid out at its own height (by default the open card).
    func show(_ placement: IslandPlacement, compactShape: CGRect, compactTarget: CGRect, compactAlpha: CGFloat,
              open: CGFloat, openRect: CGRect, contentRect: CGRect? = nil, origin: CGPoint) {
        self.origin = origin
        let shape = IslandGeometry.silhouette(placement, from: compactShape, to: openRect, progress: open)
        silhouette = shape
        var layout = model.layout
        switch placement {
        case .notch(let housing, _):
            fillAlpha = 1
            clip.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layout.notch = true
            layout.rowLeft = max(0, housing.minX - openRect.minX)
            layout.rowRight = max(0, openRect.maxX - housing.maxX)
            layout.rowHeight = housing.height
        case .menuBar:
            fillAlpha = max(min(1, compactShape.height / IslandGeometry.capsuleHeight), IslandChoreography.backgroundAlpha(open))
            clip.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            layout.notch = false
        }
        layout.maxContent = IslandGeometry.maxContentHeight(placement)
        if layout != model.layout { model.layout = layout }
        needsDisplay = true
        let body = shape.rect.offsetBy(dx: -origin.x, dy: -origin.y)
        clip.frame = body
        clip.layer?.cornerRadius = min(shape.radius, body.width / 2, body.height / 2)
        clip.isHidden = body.width < 1 || body.height < 1
        compact.frame = compactTarget.offsetBy(dx: -shape.rect.minX, dy: -shape.rect.minY)
        compact.alphaValue = compactAlpha * IslandChoreography.compactAlpha(open)
        compact.isHidden = compact.alphaValue < 0.01
        let content = contentRect ?? openRect
        panel.frame = NSRect(x: content.minX - shape.rect.minX, y: content.minY - shape.rect.minY + IslandChoreography.contentDrop(open),
                             width: content.width, height: content.height)
        panel.alphaValue = IslandChoreography.contentAlpha(open)
        let hidden = open < 0.01
        let shown = panel.isHidden && !hidden
        panel.isHidden = hidden
        if shown { onPanelShown?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let silhouette, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(silhouette.path(offset: origin))
        context.setFillColor(NSColor.black.withAlphaComponent(fillAlpha).cgColor)
        context.fillPath()
    }

    func shapeContains(_ point: NSPoint) -> Bool {
        silhouette?.contains(CGPoint(x: point.x + origin.x, y: point.y + origin.y)) ?? false
    }
}

/// Moves the island between rest, compact and open: critically damped springs on the display link, one for the
/// compact shape (rest ↔ wing, a longer or shorter line), one for opening and one for the card's height. Reversals
/// keep value and velocity. Under Reduce Motion the springs jump and the window only fades.
@MainActor
final class IslandPresenter: NSObject {
    let panel = IslandPanel()
    private(set) var view: IslandView!
    private(set) var placement: IslandPlacement?
    private(set) var isPresented = false
    private var compactFrom = CGRect.zero, compactTo = CGRect.zero
    private var alphaFrom: CGFloat = 0, alphaTo: CGFloat = 0
    private var wing = IslandSpring(value: 1)
    private var opening = IslandSpring()
    private var height = IslandSpring(value: 180, bounds: 0...10_000, tolerance: 0.25)
    /// The tallest the card has been since its height last settled: the window and the content keep that size until
    /// then, so neither is resized on every frame.
    private var heightReach: CGFloat = 180
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var tickCount = 0
    private var watchdog: Timer?
    private var watchedTicks = 0
    private var fadeToken = 0
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var pressWatch: Timer?
    var onClosed: (() -> Void)?
    /// The close has finished: the island may move to another display now.
    var onIdle: (() -> Void)?
    var isIdle: Bool { !isPresented && opening.isSettled && opening.value == 0 && height.isSettled }
    var onEscape: (() -> Void)?
    var onQuestionKey: ((UInt16) -> Bool)?
    /// A key with ⌘ or ⌥ while the card has the keyboard; true when the card acted on it.
    var onCardKey: ((IslandPresentation.CardKey, IslandPresentation.KeyModifier) -> Bool)?
    /// Whether a click outside the card closes it (not for a card that opened by itself for an approval).
    var closesOnOutsideClick: () -> Bool = { true }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(model: IslandModel) {
        super.init()
        view = IslandView(model: model) { [weak self] height in self?.contentHeightChanged(height) }
        panel.contentView = view
    }

    /// A new display: everything jumps to its resting place there.
    func place(_ placement: IslandPlacement?, compact: (leading: CGFloat, trailing: CGFloat)?) {
        guard placement != self.placement else { return }
        self.placement = placement
        guard let placement else {
            close(animated: false)
            panel.orderOut(nil)
            return
        }
        compactTo = target(placement, compact)
        compactFrom = compactTo
        alphaTo = compact == nil ? 0 : 1
        alphaFrom = alphaTo
        wing.snap(to: 1)
        if !isPresented { opening.snap(to: 0) }
        render()
    }

    private func target(_ placement: IslandPlacement, _ compact: (leading: CGFloat, trailing: CGFloat)?) -> CGRect {
        compact.map { IslandGeometry.compact(placement, leading: $0.leading, trailing: $0.trailing) } ?? IslandGeometry.rest(placement)
    }

    /// The wing appears, changes width or goes back to rest; nil is rest.
    func setCompact(_ compact: (leading: CGFloat, trailing: CGFloat)?) {
        guard let placement else { return }
        let target = target(placement, compact)
        let alpha: CGFloat = compact == nil ? 0 : 1
        guard target != compactTo || alpha != alphaTo else { return }
        compactFrom = currentCompact
        alphaFrom = currentCompactAlpha
        compactTo = target
        alphaTo = alpha
        wing.snap(to: 0)
        wing.move(to: 1, IslandSpring.opening, reduceMotion: reduceMotion())
        if wing.isSettled { render() } else { startLink() }
    }

    var compactTarget: CGRect { compactTo }

    private var currentCompact: CGRect {
        guard let placement else { return compactTo }
        return IslandGeometry.silhouette(placement, from: compactFrom, to: compactTo, progress: wing.value).rect
    }

    private var currentCompactAlpha: CGFloat {
        let w = CGFloat(wing.value)
        let t = alphaTo > alphaFrom ? IslandChoreography.smoothstep(0.5, 1, w) : IslandChoreography.smoothstep(0, 0.4, w)
        return alphaFrom + (alphaTo - alphaFrom) * t
    }

    /// Opens the card; `key` makes it key for typing (the person asked for it).
    func open(key: Bool) {
        guard placement != nil else { return }
        panel.allowsKey = true
        if key { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        guard !isPresented else { return }
        isPresented = true
        installMonitors()
        if reduceMotion() {
            opening.snap(to: 1)
            render()
            fade(from: 0)
        } else {
            cancelFade()
            opening.retarget(1, IslandSpring.opening)
            startLink()
        }
    }

    func close(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false
        removeMonitors()
        panel.allowsKey = false
        // Hand the keyboard back: a window that stays on screen keeps key focus until it is ordered out once.
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        onClosed?()
        if !animated {
            opening.snap(to: 0)
            height.snap(to: height.target)
            render()
            onIdle?()
        } else if reduceMotion() {
            fade(from: 1, to: 0) { [weak self] in
                guard let self else { return }
                opening.snap(to: 0)
                height.snap(to: height.target)
                render()
                panel.alphaValue = 1
                onIdle?()
            }
        } else {
            cancelFade()
            opening.retarget(0, IslandSpring.closing)
            startLink()
        }
    }

    private func contentHeightChanged(_ newHeight: CGFloat) {
        let target = Double(newHeight)
        guard newHeight > 0, abs(target - height.target) > 0.5 else { return }
        heightReach = max(heightReach, CGFloat(height.value), newHeight)
        let shown = isPresented || opening.value > 0
        if !shown || reduceMotion() {
            height.snap(to: target)
        } else {
            height.retarget(target, target > height.value ? IslandSpring.opening : IslandSpring.closing)
        }
        if height.isSettled { render() } else { startLink() }
    }

    // MARK: Drawing

    private func render() {
        guard let placement else { return }
        if wing.isSettled { compactFrom = compactTo; alphaFrom = alphaTo }
        if height.isSettled { heightReach = CGFloat(height.target) }
        let openRect = IslandGeometry.open(placement, contentHeight: CGFloat(height.value))
        let reach = IslandGeometry.open(placement, contentHeight: ceil(heightReach))
        let showsOpen = opening.value > 0 || opening.target > 0
        let frame = IslandGeometry.windowFrame(placement, covering: [compactFrom, compactTo] + (showsOpen ? [reach] : []))
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
            view.frame = NSRect(origin: .zero, size: frame.size)
        }
        view.show(placement, compactShape: currentCompact, compactTarget: compactTo, compactAlpha: currentCompactAlpha,
                  open: CGFloat(opening.value), openRect: openRect, contentRect: reach, origin: frame.origin)
        // At the notch the resting island hides in the housing and still finds the pointer; below the menu bar it leaves.
        let visible = placement.isNotch || alphaTo > 0 || alphaFrom > 0 || showsOpen
        if visible, !panel.isVisible { panel.orderFrontRegardless() }
        if !visible, panel.isVisible { panel.orderOut(nil) }
    }

    private func startLink() {
        if link == nil {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        defer { watchLink() }
        guard let link, link.isPaused else { return }
        lastTick = CACurrentMediaTime()
        link.isPaused = false
    }

    /// A display link stops, or ticks only now and then, while its display sleeps or the screen is locked: the shapes
    /// would stay where they were until it wakes. If it hardly ticks for a moment, everything jumps to where it is heading.
    private func watchLink() {
        guard watchdog == nil else { return }
        watchedTicks = tickCount
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let link = self.link, !link.isPaused else {
                    self.watchdog?.invalidate()
                    self.watchdog = nil
                    return
                }
                // Ticking at a usable rate (4 frames in 0.3 s, about 13 fps): check again later.
                guard self.tickCount &- self.watchedTicks < 4 else { self.watchedTicks = self.tickCount; return }
                self.watchdog?.invalidate()
                self.watchdog = nil
                self.wing.snap(to: self.wing.target)
                self.opening.snap(to: self.opening.target)
                self.height.snap(to: self.height.target)
                link.isPaused = true
                self.render()
                if self.isIdle { self.onIdle?() }
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Step by presented frame time; callback time jitters from frame to frame.
        let now = link.targetTimestamp
        tickCount &+= 1
        wing.advance(by: now - lastTick)
        opening.advance(by: now - lastTick)
        height.advance(by: now - lastTick)
        if !isPresented, opening.isSettled, opening.value == 0 { height.snap(to: height.target) }
        lastTick = now
        render()
        guard wing.isSettled && opening.isSettled && height.isSettled else { return }
        link.isPaused = true
        if isIdle { onIdle?() }
    }

    private func cancelFade() {
        fadeToken += 1
        panel.alphaValue = 1
    }

    /// Reduce Motion: the window fades instead of the shape moving.
    private func fade(from start: CGFloat, to end: CGFloat = 1, completion: (@MainActor @Sendable () -> Void)? = nil) {
        fadeToken += 1
        let token = fadeToken
        panel.alphaValue = start
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = end
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeToken == token else { return }
                completion?()
            }
        }
    }

    // MARK: Events while open

    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            // Only while the island is the key window: a card that opened by itself never sees these keys.
            // A held key does not repeat a decision: one press, one approve, decline, send or stop. In a text field the
            // repeats stay with the field (⌥⌫ keeps deleting words).
            if event.type == .keyDown, event.isARepeat, let self, event.window === self.panel, Self.cardKey(event) != nil,
               !(self.panel.firstResponder is NSTextView) {
                return nil
            }
            if event.type == .keyDown, !event.isARepeat, let self, event.window === self.panel, self.panel.isKeyWindow,
               let (key, modifier) = Self.cardKey(event),
               !((self.panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false),
               MainActor.assumeIsolated({ self.onCardKey?(key, modifier) ?? false }) {
                return nil
            }
            if event.type == .keyDown, let self, event.window === self.panel,
               self.view.model.showsPrompt, self.panel.isKeyWindow,
               let editor = self.panel.firstResponder as? NSTextView, editor.isFieldEditor, !editor.hasMarkedText(),
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
               MainActor.assumeIsolated({
                   if event.isARepeat, (event.keyCode == 36 || event.keyCode == 76),
                      self.view.model.asking != nil, self.view.model.highlightedChoice != nil { return true }
                   return self.onQuestionKey?(event.keyCode) ?? false
               }) {
                return nil
            }
            let escape = event.type == .keyDown && event.keyCode == 53 && event.window === self?.panel
            if event.type == .keyDown && !escape { return event }
            let inPanel = event.window === self?.panel
            let location = event.locationInWindow
            MainActor.assumeIsolated {
                guard let self else { return }
                if escape {
                    self.onEscape?()
                } else if inPanel, !self.view.shapeContains(location), self.closesOnOutsideClick() {
                    self.close()
                }
            }
            return escape ? nil : event
        }
        // Clicks in other apps are outside.
        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                guard let self, self.closesOnOutsideClick() else { return }
                if type == .leftMouseDown { self.pressedOutside() } else { self.close() }
            }
        }
        monitors = [local, global].compactMap { $0 }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.closesOnOutsideClick() else { return }
                self.close()
            }
        })
    }

    /// Return, Delete or "." with ⌘ or ⌥ alone; nil for anything else.
    nonisolated private static func cardKey(_ event: NSEvent) -> (IslandPresentation.CardKey, IslandPresentation.KeyModifier)? {
        let modifier: IslandPresentation.KeyModifier
        switch event.modifierFlags.intersection([.command, .control, .option, .shift]) {
        case [.command]: modifier = .command
        case [.option]: modifier = .option
        default: return nil
        }
        switch event.keyCode {
        case 36, 76: return (.returnKey, modifier)
        case 51: return (.delete, modifier)
        // "." by the character, wherever the layout puts it.
        default: return event.charactersIgnoringModifiers == "." ? (.period, modifier) : nil
        }
    }

    // Adapted from Pippa: app/Sources/Pippa/App/IslandPresenter.swift (pressedOutside)
    /// A press in another app may start a drag onto the card ("drop a file here"), so the card waits for the button
    /// to come up: a plain click closes it then, and so does a drag that ends anywhere else. A drag that ends on the
    /// card leaves it open with the files.
    private func pressedOutside() {
        let drags = NSPasteboard(name: .drag).changeCount
        pressWatch?.invalidate()
        pressWatch = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.pressWatch?.invalidate()
                self.pressWatch = nil
                let dragged = NSPasteboard(name: .drag).changeCount != drags
                let onIsland = self.view.shapeContains(self.panel.convertPoint(fromScreen: NSEvent.mouseLocation))
                if !(dragged && onIsland) { self.close() }
            }
        }
    }

    private func removeMonitors() {
        pressWatch?.invalidate()
        pressWatch = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }
}
