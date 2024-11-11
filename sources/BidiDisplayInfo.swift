//
//  RangeArray.swift
//  iTerm2
//
//  Created by George Nachman on 10/29/24.
//
import CoreText

@objc(iTermRangeArray)
class RangeArray: NSObject {
    private let ranges: [Range<Int>]
    init(_ ranges: [Range<Int>]) {
        self.ranges = ranges
    }
    
    @objc
    var count: UInt {
        UInt(ranges.count)
    }
    
    @objc
    subscript(_ i: Int) -> NSRange {
        NSRange(ranges[i])
    }
}

extension CTRun {
    var glyphCount: Int {
        CTRunGetGlyphCount(self)
    }
    var wholeRange: CFRange {
        CFRange(location: 0, length: glyphCount)
    }

    var stringIndices: [CFIndex] {
        let count = glyphCount
        var values = Array<CFIndex>(repeating: 0, count: count)
        CTRunGetStringIndices(self, wholeRange, &values)
        return values
    }
    var positions: [CGPoint] {
        let count = glyphCount
        var values = Array<CGPoint>(repeating: .zero, count: count)
        CTRunGetPositions(self, wholeRange, &values)
        return values
    }
    var status: CTRunStatus {
        CTRunGetStatus(self)
    }
    var stringRange: Range<Int> {
        let cfrange = CTRunGetStringRange(self)
        return cfrange.location..<(cfrange.location + cfrange.length)
    }
}

extension ClosedRange where Bound == Int {
    init(_ cfrange: CFRange) {
        self = cfrange.location...(cfrange.location + cfrange.length)
    }
}

extension ClosedRange {
    mutating func formUnion(_ other: Self) {
        self = Swift.min(self.lowerBound, other.lowerBound)...Swift.max(self.upperBound, other.upperBound)
    }
}

struct CellPosition {
    var sourceCell: Int
    enum Position {
        case absolute(CGFloat)
        case leftOfPredecessor
        case rightOfPredecessor
    }
    var position: Position
}

struct ResolvedCellPosition: Comparable {
    var sourceCell: Int
    var base: CGFloat
    var infinitessimals: Int
    init(previous: ResolvedCellPosition?,
         current: CellPosition) {
        self.sourceCell = current.sourceCell
        if let previous {
            switch current.position {
            case .absolute(let value):
                self.base = value
                self.infinitessimals = 0
            case .leftOfPredecessor:
                self.base = previous.base
                self.infinitessimals = previous.infinitessimals - 1
            case .rightOfPredecessor:
                self.base = previous.base
                self.infinitessimals = previous.infinitessimals + 1
            }
        } else {
            switch current.position {
            case .absolute(let value):
                self.base = value
                self.infinitessimals = 0
            case .leftOfPredecessor:
                // The first character, which happens to be in a right-to-left run, was part of a
                // ligature it was not credited for. This must be the rightmost position.
                self.base = CGFloat.infinity
                self.infinitessimals = 0
            case .rightOfPredecessor:
                // The first character, which happens to be in a left-to-right run, was part of a
                // ligature it was not credited for. This must be the leftmost position.
                self.base = -CGFloat.infinity
                self.infinitessimals = 0
            }
        }
    }

    static func < (lhs: ResolvedCellPosition, rhs: ResolvedCellPosition) -> Bool {
        if lhs.base != rhs.base {
            return lhs.base < rhs.base
        } else {
            return lhs.infinitessimals < rhs.infinitessimals
        }
    }
}


// Make a lookup table that maps source cell to display cell.
fileprivate func makeLookupTable(_ attributedString: NSAttributedString,
                                     deltas: UnsafePointer<Int32>,
                                     count: Int) -> ([Int32], IndexSet) {
    var rtlIndexes = IndexSet()

    // Create a CTLine from the attributed string
    let line = CTLineCreateWithAttributedString(attributedString)
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]

    // Source cell to range of positions
    var sourceCellToPositionRange = Array<ClosedRange<CGFloat>?>(repeating: nil, count: count)
    for run in runs {
        let isRTL = (run.status.contains(.rightToLeft))
        let stringIndices = run.stringIndices

        // Update rtlIndexes
        if isRTL {
            for stringIndex in run.stringRange {
                let sourceCell = Int(CellOffsetFromUTF16Offset(Int32(stringIndex), deltas))
                rtlIndexes.insert(sourceCell)
            }
        }

        // Update sourceCellToPositionRange
        let positions = run.positions
        for i in 0..<run.glyphCount {
            let stringIndex = stringIndices[i]
            let sourceCell = Int(CellOffsetFromUTF16Offset(Int32(stringIndex), deltas))
            if var existing = sourceCellToPositionRange[sourceCell] {
                existing.formUnion(positions[i].x...positions[i].x)
                sourceCellToPositionRange[sourceCell] = existing
            } else {
                sourceCellToPositionRange[sourceCell] = positions[i].x...positions[i].x
            }
        }
    }

    let cellPositionsBySourceCell = sourceCellToPositionRange.enumerated().map { (sourceCell: Int, positionRange: ClosedRange<CGFloat>?) -> CellPosition in
        if let positionRange {
            return CellPosition(sourceCell: sourceCell, position: .absolute(positionRange.lowerBound))
        } else {
            if rtlIndexes.contains(sourceCell) {
                // This is a right-to-left character that contributed to a ligature. It should be placed left of the preceding character.
                return CellPosition(sourceCell: sourceCell, position: .leftOfPredecessor)
            } else {
                // This is a left-to-right character that contributed to a ligature. It should be placed right of the preceding character.
                return CellPosition(sourceCell: sourceCell, position: .rightOfPredecessor)
            }
        }
    }

    var resolvedCellPositions = [ResolvedCellPosition]()
    for cellPosition in cellPositionsBySourceCell {
        resolvedCellPositions.append(ResolvedCellPosition(previous: resolvedCellPositions.last,
                                                          current: cellPosition))
    }
    let sortedResolvedCellPositions = resolvedCellPositions.sorted()

    var lut = Array(Int32(0)..<Int32(count))
    for (visualIndex, resolvedCellPosition) in sortedResolvedCellPositions.enumerated() {
        lut[Int(resolvedCellPosition.sourceCell)] = Int32(visualIndex)
    }
    return (lut, rtlIndexes)
}

extension IndexSet {
    func mapRanges(_ transform: (Range<Int>) throws -> Range<Int>) rethrows -> IndexSet {
        var temp = IndexSet()
        for range in rangeView {
            let mapped = try transform(range)
            if !mapped.isEmpty {
                temp.insert(integersIn: mapped)
            }
        }
        return temp
    }

    func compactMapRanges(_ transform: (Range<Int>) throws -> Range<Int>?) rethrows -> IndexSet {
        var temp = IndexSet()
        for range in rangeView {
            if let mapped = try transform(range), !mapped.isEmpty {
                temp.insert(integersIn: mapped)
            }
        }
        return temp
    }
}
#warning("TODO: Deal with embedded nulls")
@objc(iTermBidiDisplayInfo)
class BidiDisplayInfoObjc: NSObject {
    private let guts: BidiDisplayInfo

    override var description: String {
        "<iTermBidiDisplayInfo: \(self.it_addressString) \(guts.debugDescription)>"
    }
    @objc var lut: UnsafePointer<Int32> {
        guts.lut.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!
        }
    }
    private lazy var _inverseLUT: [Int32] = {
        let lut = guts.lut
        guard let max = lut.max() else {
            return []
        }
        var result = Array(0..<Int32(max))
        for i in 0..<Int(numberOfCells) {
            result[Int(lut[i])] = Int32(i)
        }
        return result
    }()

    @objc var inverseLUT: UnsafePointer<Int32> {
        _inverseLUT.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!
        }
    }

    @objc var inverseLUTCount: Int32 {
        Int32(_inverseLUT.count)
    }

    @objc var rtlIndexes: IndexSet { guts.rtlIndexes }
    // Length of the `lut`. Also equals the number of non-empty sequential cells counting from the first. Does not include trailing spaces.
    @objc var numberOfCells: Int32 { Int32(guts.lut.count) }

    private enum Keys: String {
        case lut = "lut"
        case rtlIndexes = "rtlIndexes"
    }

    @objc
    var dictionaryValue: [String: Any] {
        return [Keys.lut.rawValue: guts.lut.map { NSNumber(value: $0) },
                Keys.rtlIndexes.rawValue: rtlIndexes.rangeView.map { NSValue(range: NSRange($0)) } ]
    }

    @objc(initWithDictionary:)
    init?(_ dictionary: NSDictionary) {
        guard let lutObj = dictionary[Keys.lut.rawValue], let lutArray = lutObj as? Array<NSNumber> else {
            return nil
        }
        guard let indexesObj = dictionary[Keys.rtlIndexes.rawValue], let indexesArray = indexesObj as? Array<NSValue> else {
            return nil
        }
        let lut = lutArray.map { Int32($0.intValue) }
        let indexes = IndexSet(ranges: indexesArray.compactMap { Range($0.rangeValue) })
        guts = BidiDisplayInfo(lut: lut,
                               rtlIndexes: indexes)
    }

    @objc(initWithScreenCharArray:)
    init?(_ sca: ScreenCharArray) {
        if let guts = BidiDisplayInfo(sca) {
            self.guts = guts
        } else {
            return nil
        }
    }

    private init(_ guts: BidiDisplayInfo) {
        self.guts = guts
    }

    // If bidiInfo is nil, annotate all cells as LTR
    // Returns whether any changes were made
    @objc
    @discardableResult
    static func annotate(bidiInfo: BidiDisplayInfoObjc?, msca: MutableScreenCharArray) -> Bool {
        let line = msca.mutableLine;
        var changed = false
        for i in 0..<Int(msca.length) {
            let before = line[i].rtlStatus
            line[i].rtlStatus = (bidiInfo?.guts.rtlIndexes.contains(i) ?? false) ? RTLStatus.RTL : RTLStatus.LTR
            if line[i].rtlStatus != before {
                changed = true
            }
        }
        return changed
    }

    @objc(subInfoInRange:)
    func subInfo(range nsrange: NSRange) -> BidiDisplayInfoObjc? {
        if let guts = guts.subInfo(range: nsrange) {
            return BidiDisplayInfoObjc(guts)
        } else {
            return nil
        }
    }

    @objc(isEqual:)
    override func isEqual(_ other: Any?) -> Bool {
        guard let other, let obj = other as? BidiDisplayInfoObjc else {
            return false
        }
        return guts == obj.guts
    }

    @objc
    func enumerateLogicalRanges(in visualNSRange: NSRange,
                                closure: (NSRange, Int32, UnsafeMutablePointer<ObjCBool>) -> ()) {
        enumerateLogicalRanges(in: visualNSRange, reversed: false, closure:closure)
    }

    // Like enumerateLogicalRanges(in:, closure:) but with the order of calls to `closure` reversed.
    @objc
    func enumerateLogicalRangesReverse(in visualNSRange: NSRange,
                                       closure: (NSRange, Int32, UnsafeMutablePointer<ObjCBool>) -> ()) {
        enumerateLogicalRanges(in: visualNSRange, reversed: true, closure:closure)
    }

    // Invokes `closure` with logical ranges within a visual range, but still in logical order.
    //
    // For example:
    //               012345678
    // Logical       abcDEFghi
    // Visual        ghiFEDabc
    // visualNSRange  ^^^^     1...4
    //
    // Then closure will be invoked with:
    //
    // Logical Range    Visual Start Index
    // 4...5 (EF)       3
    // 7...8 (hi)       1
    //
    // Or, if the reversed flag is true, the same calls are made in the reverse order (i.e., from
    // largest logical range to smallest). The visual order is not necessarily monotonic,
    // regardless of the `reversed` flag.
    private func enumerateLogicalRanges(in visualNSRange: NSRange,
                                        reversed: Bool,
                                        closure: (NSRange, Int32, UnsafeMutablePointer<ObjCBool>) -> ()) {
        guard let visualRange = Range<Int>(visualNSRange) else {
            return
        }

        let visualToLogical = guts.invertedLUT
        let sortedLogicalIndexes = visualRange.map { visualIndex in
            if visualIndex < visualToLogical.count {
                return Int(visualToLogical[visualIndex])
            }
            return visualIndex
        }.sorted()
        let logicalIndexes = reversed ? sortedLogicalIndexes.reversed() : sortedLogicalIndexes
        let logicalToVisual = guts.lut
        var stop = ObjCBool(false)
        for logicalRange in logicalIndexes.rangeIterator() {
            let visualStart = if logicalRange.lowerBound < logicalToVisual.count {
                logicalToVisual[logicalRange.lowerBound]
            } else {
                Int32(logicalRange.lowerBound)
            }
            closure(NSRange(logicalRange), visualStart, &stop)
            if stop.boolValue {
                return
            }
        }
    }
}

struct CollectionRangeIterator<C: Collection>: IteratorProtocol, Sequence where C.Element: BinaryInteger {
    private let collection: C
    private var currentIndex: C.Index

    init(collection: C) {
        self.collection = collection
        self.currentIndex = collection.startIndex
    }

    mutating func next() -> ClosedRange<C.Element>? {
        guard currentIndex < collection.endIndex else { return nil }

        let start = collection[currentIndex]
        var end = start
        collection.formIndex(after: &currentIndex)

        while currentIndex < collection.endIndex, collection[currentIndex] == end + 1 {
            end = collection[currentIndex]
            collection.formIndex(after: &currentIndex)
        }

        return start...end
    }
}

extension Collection where Element: BinaryInteger {
    func rangeIterator() -> CollectionRangeIterator<Self> {
        return CollectionRangeIterator(collection: self)
    }
}

struct BidiDisplayInfo: CustomDebugStringConvertible, Equatable {
    // Maps a source column to a display column
    fileprivate let lut: [Int32]

    // Indexes into the screen char array that created this object which have right-to-left
    // direction. Adjacent RTL indexes will be drawn right-to-left.
    fileprivate let rtlIndexes: IndexSet

    var debugDescription: String {
        struct RLE: CustomDebugStringConvertible {
            var debugDescription: String {
                switch stride {
                case .unknown:
                    "\(start)"
                case .ltr:
                    ">\(start)...\(end)>"
                case .rtl:
                    "<\(end)...\(start)<"
                }
            }
            var start: Int32
            enum Stride {
                case unknown
                case ltr
                case rtl
            }
            var stride: Stride
            var end: Int32
        }
        let rles = lut.reduce(into: Array<RLE>()) { partialResult, value in
            if let last = partialResult.last {
                var replacement = last
                switch last.stride {
                case .unknown:
                    if value == last.start + 1 {
                        replacement.stride = .ltr
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else if value == last.start - 1 {
                        replacement.stride = .rtl
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else {
                        partialResult.append(RLE(start: value, stride: .unknown, end: value))
                    }
                case .ltr:
                    if value == last.end + 1 {
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else {
                        partialResult.append(RLE(start: value, stride: .unknown, end: value))
                    }
                case .rtl:
                    if value == last.end - 1 {
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else {
                        partialResult.append(RLE(start: value, stride: .unknown, end: value))
                    }
                }
            } else {
                partialResult.append(RLE(start: value, stride: .unknown, end: value))
            }
        }
        let lutString = rles.map { $0.debugDescription }.joined(separator: " ")
        let indexesString = rtlIndexes.rangeView.map { range in
            if range.lowerBound == range.upperBound - 1 {
                return "\(range.lowerBound)"
            }
            return "\(range.lowerBound)…\(range.upperBound - 1)"
        }.joined(separator: ", ")

        return "lut=[\(lutString)] rleIndexes=[\(indexesString)] length=\(lut.count)"
    }

    fileprivate init(lut: [Int32],
                     rtlIndexes: IndexSet) {
        self.lut = lut
        self.rtlIndexes = rtlIndexes
    }

    // Fails if no RTL was found
    init?(_ sca: ScreenCharArray) {
        let length = Int32(sca.length)
        let emptyCount = Int32(sca.numberOfTrailingEmptyCells(spaceIsEmpty: false))
        let nonEmptyCount = length - emptyCount

        var buffer: UnsafeMutablePointer<unichar>?
        var deltas: UnsafeMutablePointer<Int32>?
        let string = ScreenCharArrayToString(sca.line, 0, nonEmptyCount, &buffer, &deltas)!

        let attributedString = NSAttributedString(string: string)
        (lut, rtlIndexes) = makeLookupTable(attributedString,
                                            deltas: deltas!,
                                            count: Int(nonEmptyCount))
        free(deltas)
        free(buffer)
        if rtlIndexes.isEmpty {
            return nil
        }
    }

    func subInfo(range nsrange: NSRange) -> BidiDisplayInfo? {
        let range = Range(nsrange)!.clamped(to: 0..<lut.count)
        if range == 0..<lut.count {
            return self
        }

        var subIndexes = IndexSet()
        for rtlRange in rtlIndexes.rangeView(of: range) {
            let shifted = rtlRange.shifted(by: -nsrange.location)
            subIndexes.insert(integersIn: shifted)
        }
        if subIndexes.isEmpty {
            return nil
        }

        let sublut = lut[range]
        let sorted = sublut.sorted()

        // Create a compression map to remap `lut` values
        let compression = Dictionary(uniqueKeysWithValues: sorted.enumerated().map {
            ($1, Int32($0))
        })
        let fixed = sublut.map {
            compression[$0]!
        }
        return BidiDisplayInfo(lut: fixed, rtlIndexes: subIndexes)
    }

    var invertedLUT: [Int32] {
        var result = Array<Int32>(repeating: 0, count: lut.count)
        for (index, value) in lut.enumerated() {
            result[Int(value)] = Int32(index)
        }
        return result
    }
}

extension ScreenCharArray {
    func numberOfTrailingEmptyCells(spaceIsEmpty: Bool) -> Int {
        var count = 0
        let length = Int(self.length)
        let line = self.line
        let emptyCodes = spaceIsEmpty ? Set([unichar(0), unichar(32)]) : Set([unichar(0)])
        while count < length && emptyCodes.contains(line[Int(length - count - 1)].code) {
            count += 1
        }
        return count
    }
}

extension Range where Bound: Comparable {
    func intersection(_ other: Range<Bound>) -> Range<Bound>? {
        let lowerBound = Swift.max(self.lowerBound, other.lowerBound)
        let upperBound = Swift.min(self.upperBound, other.upperBound)

        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }
}
