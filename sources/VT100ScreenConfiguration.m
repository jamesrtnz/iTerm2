//
//  VT100ScreenConfiguration.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100ScreenConfiguration.h"
#import "NSArray+iTerm.h"

@interface VT100ScreenConfiguration()
@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readwrite) NSInteger unicodeVersion;
@property (nonatomic, readwrite) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readwrite) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readwrite) BOOL notifyOfAppend;
@property (nonatomic, readwrite) BOOL isDirty;
@property (nonatomic, readwrite) BOOL isTmuxClient;
@property (nonatomic, readwrite) BOOL printingAllowed;
@property (nonatomic, readwrite) BOOL clipboardAccessAllowed;
@property (nonatomic, readwrite) BOOL miniaturized;
@property (nonatomic, readwrite) NSRect windowFrame;
@property (nonatomic, readwrite) VT100GridSize theoreticalGridSize;
@property (nonatomic, copy, readwrite) NSString *iconTitle;
@property (nonatomic, copy, readwrite) NSString *windowTitle;
@property (nonatomic, readwrite) BOOL clearScrollbackAllowed;
@property (nonatomic, copy, readwrite) NSString *profileName;
@property (nonatomic, readwrite) NSSize cellSize;
@property (nonatomic, readwrite) CGFloat backingScaleFactor;
@property (nonatomic, readwrite) int maximumTheoreticalImageDimension;
@property (nonatomic, readwrite) BOOL dimOnlyText;
@property (nonatomic, readwrite) BOOL darkMode;
@property (nonatomic, readwrite) BOOL useSeparateColorsForLightAndDarkMode;
@property (nonatomic, readwrite) float minimumContrast;
@property (nonatomic, readwrite) double mutingAmount;
@end

@implementation VT100ScreenConfiguration

@synthesize shouldPlacePromptAtFirstColumn = _shouldPlacePromptAtFirstColumn;
@synthesize sessionGuid = _sessionGuid;
@synthesize treatAmbiguousCharsAsDoubleWidth = _treatAmbiguousCharsAsDoubleWidth;
@synthesize unicodeVersion = _unicodeVersion;
@synthesize enableTriggersInInteractiveApps = _enableTriggersInInteractiveApps;
@synthesize triggerParametersUseInterpolatedStrings = _triggerParametersUseInterpolatedStrings;
@synthesize triggerProfileDicts = _triggerProfileDicts;
@synthesize notifyOfAppend = _notifyOfAppend;
@synthesize isTmuxClient = _isTmuxClient;
@synthesize printingAllowed = _printingAllowed;
@synthesize clipboardAccessAllowed = _clipboardAccessAllowed;
@synthesize miniaturized = _miniaturized;
@synthesize windowFrame = _windowFrame;
@synthesize theoreticalGridSize = _theoreticalGridSize;
@synthesize iconTitle = _iconTitle;
@synthesize windowTitle = _windowTitle;
@synthesize clearScrollbackAllowed = _clearScrollbackAllowed;
@synthesize profileName = _profileName;
@synthesize cellSize = _cellSize;
@synthesize backingScaleFactor = _backingScaleFactor;
@synthesize maximumTheoreticalImageDimension = _maximumTheoreticalImageDimension;
@synthesize dimOnlyText = _dimOnlyText;
@synthesize darkMode = _darkMode;
@synthesize useSeparateColorsForLightAndDarkMode = _useSeparateColorsForLightAndDarkMode;
@synthesize minimumContrast = _minimumContrast;
@synthesize mutingAmount = _mutingAmount;

@synthesize isDirty = _isDirty;

- (instancetype)initFrom:(VT100ScreenConfiguration *)other {
    self = [super init];
    if (self) {
        _shouldPlacePromptAtFirstColumn = other.shouldPlacePromptAtFirstColumn;
        _sessionGuid = other.sessionGuid;
        _treatAmbiguousCharsAsDoubleWidth = other.treatAmbiguousCharsAsDoubleWidth;
        _unicodeVersion = other.unicodeVersion;
        _enableTriggersInInteractiveApps = other.enableTriggersInInteractiveApps;
        _triggerParametersUseInterpolatedStrings = other.triggerParametersUseInterpolatedStrings;
        _triggerProfileDicts = [other.triggerProfileDicts copy];
        _notifyOfAppend = other.notifyOfAppend;
        _isTmuxClient = other.isTmuxClient;
        _printingAllowed = other.printingAllowed;
        _clipboardAccessAllowed = other.clipboardAccessAllowed;
        _miniaturized = other.miniaturized;
        _windowFrame = other.windowFrame;
        _theoreticalGridSize = other.theoreticalGridSize;
        _iconTitle = other.iconTitle;
        _windowTitle = other.windowTitle;
        _clearScrollbackAllowed = other.clearScrollbackAllowed;
        _profileName = other.profileName;
        _cellSize = other.cellSize;
        _backingScaleFactor = other.backingScaleFactor;
        _maximumTheoreticalImageDimension = other.maximumTheoreticalImageDimension;
        _dimOnlyText = other.dimOnlyText;
        _darkMode = other.darkMode;
        _useSeparateColorsForLightAndDarkMode = other.useSeparateColorsForLightAndDarkMode;
        _minimumContrast = other.minimumContrast;
        _mutingAmount = other.mutingAmount;

        _isDirty = other.isDirty;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    NSDictionary *dict = @{ @"shouldPlacePromptAtFirstColumn": @(_shouldPlacePromptAtFirstColumn),
                            @"sessionGuid": _sessionGuid ?: @"(nil)",
                            @"treatAmbiguousCharsAsDoubleWidth": @(_treatAmbiguousCharsAsDoubleWidth),
                            @"unicodeVersion": @(_unicodeVersion),
                            @"enableTriggersInInteractiveApps": @(_enableTriggersInInteractiveApps),
                            @"triggerParametersUseInterpolatedStrings": @(_triggerParametersUseInterpolatedStrings),
                            @"triggerProfileDicts (count)": @(_triggerProfileDicts.count),
                            @"notifyOfAppend": @(_notifyOfAppend),
                            @"isTmuxClient": @(_isTmuxClient),
                            @"printingAllowed": @(_printingAllowed),
                            @"clipboardAccessAllowed": @(_clipboardAccessAllowed),
                            @"miniaturized": @(_miniaturized),
                            @"windowFrame": @(_windowFrame),
                            @"theoreticalGridSize": VT100GridSizeDescription(_theoreticalGridSize),
                            @"iconTitle": _iconTitle ?: @"",
                            @"windowTitle": _windowTitle ?: @"",
                            @"clearScrollbackAllowed": @(_clearScrollbackAllowed),
                            @"profileName": _profileName ?: @"",
                            @"cellSize": NSStringFromSize(_cellSize),
                            @"backingScaleFactor": @(_backingScaleFactor),
                            @"maximumTheoreticalImageDimension": @(_maximumTheoreticalImageDimension),
                            @"dimOnlyText": @(_dimOnlyText),
                            @"darkMode": @(_darkMode),
                            @"useSeparateColorsForLightAndDarkMode": @(_useSeparateColorsForLightAndDarkMode),
                            @"minimumContrast": @(_minimumContrast),
                            @"mutingAmount": @(_mutingAmount),

                            @"isDirty": @(_isDirty),
    };
    NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *kvps = [keys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"    %@=%@", key, dict[key]];
    }];
    NSString *values = [kvps componentsJoinedByString:@"\n"];
    return [NSString stringWithFormat:@"<%@: %p\n%@>", NSStringFromClass([self class]), self, values];
}
@end

@implementation VT100MutableScreenConfiguration

@dynamic shouldPlacePromptAtFirstColumn;
@dynamic sessionGuid;
@dynamic treatAmbiguousCharsAsDoubleWidth;
@dynamic unicodeVersion;
@dynamic enableTriggersInInteractiveApps;
@dynamic triggerParametersUseInterpolatedStrings;
@dynamic triggerProfileDicts;
@dynamic notifyOfAppend;
@dynamic isTmuxClient;
@dynamic printingAllowed;
@dynamic clipboardAccessAllowed;
@dynamic miniaturized;
@dynamic windowFrame;
@dynamic theoreticalGridSize;
@dynamic iconTitle;
@dynamic windowTitle;
@dynamic clearScrollbackAllowed;
@dynamic profileName;
@dynamic cellSize;
@dynamic backingScaleFactor;
@dynamic maximumTheoreticalImageDimension;
@dynamic dimOnlyText;
@dynamic darkMode;
@dynamic useSeparateColorsForLightAndDarkMode;
@dynamic minimumContrast;
@dynamic mutingAmount;

@dynamic isDirty;

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenConfiguration alloc] initFrom:self];
}

@end

