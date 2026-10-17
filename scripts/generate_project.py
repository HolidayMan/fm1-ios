#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; sources use synchronized groups."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / "FM1.xcodeproj"
(project / "xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)

def ident(n): return f"{n:024X}"

objects = []
def obj(n, content):
    objects.append(f"{ident(n)} = {{ {content} }};")

app, tests, ui = ident(10), ident(11), ident(12)
obj(1, f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {tests} = {{ TestTargetID = {app}; }}; {ui} = {{ TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {ident(50)}; compatibilityVersion = "Xcode 16.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ru, Base); mainGroup = {ident(2)}; productRefGroup = {ident(3)}; projectDirPath = ""; projectRoot = ""; targets = ({app}, {tests}, {ui});')
obj(2, f'isa = PBXGroup; children = ({ident(4)}, {ident(5)}, {ident(6)}, {ident(3)}); sourceTree = "<group>";')
obj(3, f'isa = PBXGroup; children = ({ident(7)}, {ident(8)}, {ident(9)}); name = Products; sourceTree = "<group>";')
obj(4, f'isa = PBXFileSystemSynchronizedRootGroup; exceptions = ({ident(70)}); path = App; sourceTree = "<group>";')
obj(5, 'isa = PBXFileSystemSynchronizedRootGroup; path = FM1Tests; sourceTree = "<group>";')
obj(6, 'isa = PBXFileSystemSynchronizedRootGroup; path = FM1UITests; sourceTree = "<group>";')
obj(70, f'isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Info.plist, FM1Bridge.h); target = {app};')
for n, typ, name in [(7, 'wrapper.application', 'FM1.app'),(8, 'wrapper.cfbundle', 'FM1Tests.xctest'),(9,'wrapper.cfbundle','FM1UITests.xctest')]:
    obj(n, f'isa = PBXFileReference; explicitFileType = {typ}; includeInIndex = 0; path = {name}; sourceTree = BUILT_PRODUCTS_DIR;')
for i, name, product_type in [(0,'FM1','com.apple.product-type.application'),(1,'FM1Tests','com.apple.product-type.bundle.unit-test'),(2,'FM1UITests','com.apple.product-type.bundle.ui-testing')]:
    obj(10+i, f'isa = PBXNativeTarget; buildConfigurationList = {ident(51+i)}; buildPhases = ({ident(20+i*3)}, {ident(21+i*3)}, {ident(22+i*3)}); buildRules = (); dependencies = ({ident(61+i) if i else ""}); fileSystemSynchronizedGroups = ({ident(4+i)}); name = {name}; productName = {name}; productReference = {ident(7+i)}; productType = "{product_type}";')
    for offset, typ in enumerate(['PBXSourcesBuildPhase','PBXFrameworksBuildPhase','PBXResourcesBuildPhase']):
        obj(20+i*3+offset, f'isa = {typ}; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for i in [1,2]:
    obj(80+i, f'isa = PBXContainerItemProxy; containerPortal = {ident(1)}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = FM1;')
    obj(90+i, f'isa = PBXTargetDependency; target = {app}; targetProxy = {ident(80+i)};')
objects = [s.replace(f'dependencies = ({ident(62)});', f'dependencies = ({ident(91)});').replace(f'dependencies = ({ident(63)});',f'dependencies = ({ident(92)});') for s in objects]
common = 'ARCHS = arm64; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = minimal;'
app_settings = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; SWIFT_OBJC_BRIDGING_HEADER = App/FM1Bridge.h; OTHER_LDFLAGS = ("-lfm1_ios_core", "-liconv"); "LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]" = "$(SRCROOT)/target/aarch64-apple-ios-sim/release"; "LIBRARY_SEARCH_PATHS[sdk=iphoneos*]" = "$(SRCROOT)/target/aarch64-apple-ios/release"; PRODUCT_BUNDLE_IDENTIFIER = com.local.fm1.instrument; PRODUCT_NAME = "$(TARGET_NAME)"; INFOPLIST_FILE = App/Info.plist; GENERATE_INFOPLIST_FILE = NO; TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTS_MACCATALYST = NO; SWIFT_EMIT_LOC_STRINGS = YES;  CODE_SIGN_STYLE = Automatic;'
test_settings = 'GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic;'
for group in range(4):
    numbers = []
    for mode in ['Debug','Release']:
        n = 100+group*2+(mode=='Release')
        numbers.append(ident(n))
        settings = common + (' DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode=='Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O";')
        if group==1: settings+=app_settings
        if group==2: settings+=test_settings+' PRODUCT_BUNDLE_IDENTIFIER = com.local.fm1.instrument.tests; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/FM1.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FM1"; BUNDLE_LOADER = "$(TEST_HOST)";'
        if group==3: settings+=test_settings+' PRODUCT_BUNDLE_IDENTIFIER = com.local.fm1.instrument.uitests; TEST_TARGET_NAME = FM1;'
        obj(n, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
    obj(50+group, f'isa = XCConfigurationList; buildConfigurations = ({", ".join(numbers)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 77; objects = {\n'+ '\n'.join(objects)+'\n}; rootObject = '+ident(1)+';}\n')
entries=''
for n,name in [(10,'FM1'),(11,'FM1Tests'),(12,'FM1UITests')]:
    entries+=f'<BuildActionEntry buildForTesting="YES" buildForRunning="{"YES" if n==10 else "NO"}" buildForProfiling="{"YES" if n==10 else "NO"}" buildForArchiving="{"YES" if n==10 else "NO"}" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(n)}" BuildableName="{name+ (".app" if n==10 else ".xctest")}" BlueprintName="{name}" ReferencedContainer="container:FM1.xcodeproj"/></BuildActionEntry>'
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="FM1.app" BlueprintName="FM1" ReferencedContainer="container:FM1.xcodeproj"/>'
testables=''.join(f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(n)}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:FM1.xcodeproj"/></TestableReference>' for n,name in [(11,'FM1Tests'),(12,'FM1UITests')])
(project/'xcshareddata/xcschemes/FM1.xcscheme').write_text(f'<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>{entries}</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testables}</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>')
print(project)
