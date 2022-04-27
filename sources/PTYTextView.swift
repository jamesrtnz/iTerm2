//
//  PTYTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation

extension VT100GridAbsCoordRange {
    func relativeRange(overflow: Int64) -> VT100GridCoordRange {
        return VT100GridCoordRangeFromAbsCoordRange(self, overflow)
    }
}

extension VT100GridCoordRange {
    var windowedWithDefaultWindow: VT100GridWindowedRange {
        return VT100GridWindowedRangeMake(self, 0, 0)
    }
}

extension PTYTextView {
    @objc(renderRange:type:filename:)
    func render(range originalRange: VT100GridAbsCoordRange,
                type: String?,
                filename: String?) {
        guard let dataSource = dataSource else {
            return
        }
        var absRange = originalRange
        let overflow = dataSource.totalScrollbackOverflow()
        let width = dataSource.width()
        let relativeRange = absRange.relativeRange(overflow: overflow)
        absRange.start.x = 0
        if absRange.end.x > 0 {
            absRange.end.x = width
        }
        let text = self.text(inRange: absRange.relativeRange(overflow: overflow))
        let pwd = dataSource.workingDirectory(onLine: relativeRange.start.y)
        let baseDirectory = pwd.map { URL(fileURLWithPath: $0) }
        replaceWithPorthole(inRange: absRange,
                            text: text,
                            baseDirectory: baseDirectory,
                            type: type,
                            filename: filename)
    }

    func text(inRange range: VT100GridCoordRange) -> String {
        let extractor = iTermTextExtractor(dataSource: dataSource)
        let windowedRange = range.windowedWithDefaultWindow
        let text = extractor.content(in: windowedRange,
                                     attributeProvider: nil,
                                     nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                                     pad: false,
                                     includeLastNewline: false,
                                     trimTrailingWhitespace: false,
                                     cappedAtSize: -1,
                                     truncateTail: false,
                                     continuationChars: nil,
                                     coords: nil) as! String
        return text
    }

    @objc(replaceWithPortholeInRange:havingText:baseDirectory:type:filename:)
    func replaceWithPorthole(inRange absRange: VT100GridAbsCoordRange,
                             text: String,
                             baseDirectory: URL?,
                             type: String?,
                             filename: String?) {
        guard dataSource != nil else {
            return
        }
        let config = PortholeConfig(text: text,
                                    colorMap: colorMap,
                                    baseDirectory: baseDirectory,
                                    font: font,
                                    type: type,
                                    filename: filename)
        let porthole = makePorthole(for: config)
        replace(range: absRange, withPorthole: porthole)
    }

    private func replace(range absRange: VT100GridAbsCoordRange,
                         withPorthole porthole: Porthole) {
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.desiredHeight(forWidth: bounds.width - hmargin * 2)
        let relativeRange = VT100GridCoordRangeFromAbsCoordRange(absRange, dataSource.totalScrollbackOverflow())
        porthole.savedLines = (relativeRange.start.y ... relativeRange.end.y).map { i in
            dataSource.screenCharArray(forLine: i).copy() as! ScreenCharArray
        }
        dataSource.replace(absRange, with: porthole, ofHeight: Int32(ceil(desiredHeight / lineHeight)))
    }

    private func makePorthole(for config: PortholeConfig) -> Porthole {
        return configuredPorthole(PortholeFactory.highlightrPorthole(config: config))
    }

    private func configuredPorthole(_ porthole: Porthole) -> Porthole {
        if let textPorthole = porthole as? TextViewPorthole {
            textPorthole.changeLanguageCallback = { [weak self] language, porthole in
                guard let self = self else {
                    return
                }
                self.layoutPorthole(porthole)
            }
        }
        return porthole
    }

    private func layoutPorthole(_ porthole: TextViewPorthole) {
        guard let dataSource = dataSource else {
            return
        }
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.desiredHeight(forWidth: bounds.width - hmargin * 2)
        dataSource.changeHeight(of: porthole.mark, to: Int32(ceil(desiredHeight / lineHeight)))
    }

    @objc
    func addPorthole(_ objcPorthole: ObjCPorthole) {
        let porthole = objcPorthole as! Porthole
        portholes.add(porthole)
        addPortholeView(porthole)
    }

    private func addPortholeView(_ porthole: Porthole) {
        porthole.delegate = self
        // I'd rather add it to TextViewWrapper but doing so somehow causes TVW to be overreleased
        // and I can't figure out why.
        addSubview(porthole.view)
        updatePortholeFrame(porthole, force: true)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        setNeedsDisplay(true)
        porthole.view.needsDisplay = true
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    // Continue owning the porthole but remove it from view.
    @objc
    func hidePorthole(_ objcPorthole: ObjCPorthole) {
        let porthole = objcPorthole as! Porthole
        willRemoveSubview(porthole.view)
        if porthole.delegate === self {
            porthole.delegate = nil
        }
        porthole.view.removeFromSuperview()
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    @objc
    func unhidePorthole(_ objcPorthole: ObjCPorthole) {
        let porthole = objcPorthole as! Porthole
        precondition(portholes.contains(porthole))
        precondition(porthole.view.superview != self)
        addPortholeView(porthole)
    }

    @objc
    func removePorthole(_ objcPorthole: ObjCPorthole) {
        let porthole = objcPorthole as! Porthole
        willRemoveSubview(porthole.view)
        if porthole.delegate === self {
            porthole.delegate = nil
        }
        portholes.remove(porthole)
        porthole.view.removeFromSuperview()
        if let mark = porthole.mark {
            dataSource.replace(mark, withLines: porthole.savedLines)
        }
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    @objc
    func updatePortholeFrames() {
        DLog("Begin updatePortholeFrames")
        for porthole in portholes {
            updatePortholeFrame(porthole as! Porthole, force: false)
        }
        DLog("End updatePortholeFrames")
    }

    private func range(porthole: Porthole) -> VT100GridCoordRange? {
        guard porthole.mark != nil else {
            return nil
        }
        guard let dataSource = dataSource else {
            return nil
        }
        let gridCoordRange = dataSource.coordRange(of: porthole)
        guard gridCoordRange != VT100GridCoordRangeInvalid else {
            return nil
        }
        guard gridCoordRange.start.y <= gridCoordRange.end.y else {
            return nil
        }
        return gridCoordRange
    }

    // If force is true, recalculate the height even if the textview's width hasn't changed since
    // the last time this method was called.
    private func updatePortholeFrame(_ objcPorthole: ObjCPorthole, force: Bool) {
        let porthole = objcPorthole as! Porthole
        guard let dataSource = dataSource else {
            return
        }
        guard let gridCoordRange = range(porthole: porthole) else {
            return
        }
        let lineRange = gridCoordRange.start.y...gridCoordRange.end.y
        DLog("Update porthole with line range \(lineRange)")
        let hmargin = CGFloat(iTermPreferences.integer(forKey: kPreferenceKeySideMargins))
        let vmargin = CGFloat(iTermPreferences.integer(forKey: kPreferenceKeyTopBottomMargins))
        let cellWidth = dataSource.width()
        let innerMargin = porthole.outerMargin
        if lastPortholeWidth == cellWidth && !force {
            // Calculating porthole size is very slow because NSView is a catastrophe so avoid doing
            // it if the width is unchanged.
            let y = CGFloat(lineRange.lowerBound) * lineHeight + vmargin + innerMargin
            DLog("y=\(y) range=\(String(describing: VT100GridCoordRangeDescription(gridCoordRange ))) overflow=\(dataSource.scrollbackOverflow())")
            porthole.view.frame = NSRect(x: hmargin,
                                         y: y,
                                         width: bounds.width - hmargin * 2,
                                         height: CGFloat(lineRange.count) * lineHeight - innerMargin * 2)
        } else {
            lastPortholeWidth = cellWidth
            porthole.view.frame = NSRect(x: hmargin,
                                         y: CGFloat(lineRange.lowerBound) * lineHeight + vmargin + innerMargin,
                                         width: bounds.width - hmargin * 2,
                                         height: CGFloat(lineRange.count) * lineHeight - innerMargin * 2)
        }
        updateAlphaValue()
    }

    @objc
    var hasPortholes: Bool {
        return portholes.count > 0
    }

    // Because Swift can't cope with forward declarations and I don't want a dependency cycle.
    private var typedPortholes: [Porthole] {
        return portholes as! [Porthole]
    }

    @objc
    func removePortholeSelections() {
        for porthole in typedPortholes {
            porthole.removeSelection()
        }
    }

    @objc
    func updatePortholeColors() {
        for porthole in typedPortholes {
            porthole.updateColors()
        }
    }

    @objc
    func absRangeIntersectsPortholes(_ absRange: VT100GridAbsCoordRange) -> Bool {
        guard let dataSource = dataSource else {
            return false
        }
        let range = VT100GridCoordRangeFromAbsCoordRange(absRange, dataSource.totalScrollbackOverflow())
        for porthole in typedPortholes {
            let portholeRange = dataSource.coordRange(of: porthole)
            guard portholeRange != VT100GridCoordRangeInvalid else {
                continue
            }
            let lhs = portholeRange.start.y...portholeRange.end.y
            let rhs = range.start.y...range.end.y
            if lhs.overlaps(rhs) {
                return true
            }
        }
        return false
    }

    @objc(setNeedsPrunePortholes:)
    func setNeedsPrunePortholes(_ needs: Bool) {
        if self.portholesNeedUpdatesJoiner == nil {
            self.portholesNeedUpdatesJoiner = IdempotentOperationJoiner.asyncJoiner(.main)
        }
        self.portholesNeedUpdatesJoiner.setNeedsUpdate { [weak self] in
            self?.prunePortholes()
        }
    }
    @objc
    func prunePortholes() {
        let indexes = typedPortholes.indexes { porthole in
            porthole.mark == nil
        }
        for i in indexes {
            typedPortholes[i].view.removeFromSuperview()
        }
        portholes.removeObjects(at: indexes)
    }
}

extension Array {
    func indexes(where closure: (Element) throws -> Bool) rethrows -> IndexSet {
        var indexSet = IndexSet()
        for (i, element) in enumerated() {
            if try closure(element) {
                indexSet.insert(i)
            }
        }
        return indexSet
    }
}
extension PTYTextView: PortholeDelegate {
    func portholeDidAcquireSelection(_ porthole: Porthole) {
        selection.clear()
    }

    func portholeRemove(_ porthole: Porthole) {
        removePorthole(porthole)
    }
}

extension VT100GridCoordRange: Equatable {
    public static func == (lhs: VT100GridCoordRange, rhs: VT100GridCoordRange) -> Bool {
        return VT100GridCoordRangeEqualsCoordRange(lhs, rhs)
    }
}