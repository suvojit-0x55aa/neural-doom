#!/usr/bin/env python3
"""Generate the small native Xcode project from its explicit source lists."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
core = sorted(p.relative_to(root).as_posix() for p in (root/'Sources/DoomCore').glob('*.c'))
bridge = ['Sources/Bridge/CircuitModuleABI.c', 'Sources/Bridge/EngineBridge.c', 'Sources/Bridge/MovementReference.c', 'Sources/Bridge/TicRemainderReference.c']
app_swift = sorted(p.relative_to(root).as_posix() for p in (root/'Sources/App').glob('**/*.swift'))
app_sources = core + bridge + app_swift + []
test_sources = core + ['Sources/Bridge/CircuitModuleABI.c', 'Sources/Bridge/MovementReference.c', 'Sources/Bridge/TicRemainderReference.c', 'Sources/App/Circuit.swift', 'Sources/App/TicRemainder.swift', 'Sources/App/IWAD.swift', 'Sources/App/DataDirectory.swift', 'Sources/App/WAD/MapTables.swift', 'Tests/WAD/MapTablesTests.swift', 'Tests/WAD/EngineParityHooks.c', 'Tests/Contracts/LayoutTests.c', 'Tests/Contracts/CircuitContractTests.swift', 'Tests/Parity/ParityFixture.swift', 'Tests/Parity/ParityHarness.swift', 'Tests/Parity/SyntheticModule.swift', 'Tests/TestEngineHooks.c', 'Tests/main.swift']
resources = ['Sources/App/Locomotion.msl', 'Sources/App/TicRemainder.msl', 'Sources/Bridge/CircuitExactV1.msl', 'Sources/App/Present.msl', 'Assets/freedoom1.wad', 'Assets/FREEDOOM-COPYING.txt', 'Assets/FREEDOOM-CREDITS.txt']
files = sorted(set(app_sources + test_sources + resources + ['Sources/App/BridgingHeader.h']))
objects = {}
next_id = 0x100

def ident():
    global next_id
    next_id += 1
    return f'{next_id:024X}'
def obj(fields):
    key = ident(); objects[key] = fields; return key
def quote(value):
    if isinstance(value, list): return '( ' + ', '.join(quote(v) for v in value) + (', ' if value else '') + ')'
    if isinstance(value, dict): return '{ ' + ' '.join(f'{k} = {quote(v)};' for k,v in value.items()) + ' }'
    s = str(value)
    if s.startswith('RAW:'): return s[4:]
    if s and all(c.isalnum() or c in '_./$' for c in s): return s
    return '"' + s.replace('\\','\\\\').replace('"','\\"') + '"'

refs = {}
for path in files:
    ext = Path(path).suffix
    typ = {'.c':'sourcecode.c.c','.h':'sourcecode.c.h','.swift':'sourcecode.swift','.msl':'text','.wad':'file','.txt':'text'}[ext]
    refs[path] = obj(dict(isa='PBXFileReference', lastKnownFileType=typ, path=path, sourceTree='RAW:"<group>"'))
app_product = obj(dict(isa='PBXFileReference', explicitFileType='wrapper.application', includeInIndex='0', path='NeuralDoom.app', sourceTree='BUILT_PRODUCTS_DIR'))
test_product = obj(dict(isa='PBXFileReference', explicitFileType='compiled.mach-o.executable', includeInIndex='0', path='CircuitTests', sourceTree='BUILT_PRODUCTS_DIR'))
products = obj(dict(isa='PBXGroup', children=[app_product,test_product], name='Products', sourceTree='RAW:"<group>"'))
main_group = obj(dict(isa='PBXGroup', children=list(refs.values())+[products], sourceTree='RAW:"<group>"'))
def phase(name, paths):
    builds = [obj(dict(isa='PBXBuildFile', fileRef=refs[p])) for p in paths]
    return obj(dict(isa=name, buildActionMask='2147483647', files=builds, runOnlyForDeploymentPostprocessing='0'))
app_phase = phase('PBXSourcesBuildPhase', app_sources)
app_resource = phase('PBXResourcesBuildPhase', resources)
test_phase = phase('PBXSourcesBuildPhase', test_sources)
test_resource = phase('PBXResourcesBuildPhase', resources[:3])

def config(name, settings): return obj(dict(isa='XCBuildConfiguration', buildSettings=settings, name=name))
def configs(debug, release): return obj(dict(isa='XCConfigurationList', buildConfigurations=[debug,release], defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
common = dict(ARCHS='arm64', SDKROOT='macosx', MACOSX_DEPLOYMENT_TARGET='14.0',
              SWIFT_VERSION='5.0', SWIFT_STRICT_CONCURRENCY='minimal', CLANG_ENABLE_MODULES='YES',
              GCC_C_LANGUAGE_STANDARD='gnu11', HEADER_SEARCH_PATHS=['$(SRCROOT)/Sources/Bridge','$(SRCROOT)/Sources/DoomCore'],
              GCC_PREPROCESSOR_DEFINITIONS=['NORMALUNIX=1','$(inherited)'], CODE_SIGNING_ALLOWED='NO',
              ONLY_ACTIVE_ARCH='YES', MTL_FAST_MATH='NO')
project_cfg = configs(config('Debug',dict(common, DEBUG_INFORMATION_FORMAT='dwarf', GCC_OPTIMIZATION_LEVEL='0', SWIFT_OPTIMIZATION_LEVEL='-Onone')),
                      config('Release',dict(common, DEBUG_INFORMATION_FORMAT='dwarf-with-dsym', GCC_OPTIMIZATION_LEVEL='2', SWIFT_OPTIMIZATION_LEVEL='-O')))
app_settings = dict(PRODUCT_NAME='NeuralDoom', PRODUCT_BUNDLE_IDENTIFIER='local.neural.doom',
                    GENERATE_INFOPLIST_FILE='YES', INFOPLIST_KEY_CFBundleDisplayName='Neural Doom',
                    INFOPLIST_KEY_LSApplicationCategoryType='public.app-category.games',
                    SWIFT_OBJC_BRIDGING_HEADER='Sources/App/BridgingHeader.h',
                    PRODUCT_TYPE='com.apple.product-type.application',
                    LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks'])
app_cfg = configs(config('Debug',app_settings),config('Release',app_settings))
test_settings = dict(GCC_PREPROCESSOR_DEFINITIONS=['NORMALUNIX=1','HM_TEST=1','$(inherited)'], PRODUCT_NAME='CircuitTests', PRODUCT_BUNDLE_IDENTIFIER='local.neural.doom.tests',
                     SWIFT_OBJC_BRIDGING_HEADER='Sources/App/BridgingHeader.h',
                     LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path'])
test_cfg = configs(config('Debug',test_settings),config('Release',test_settings))
app_target = obj(dict(isa='PBXNativeTarget', buildConfigurationList=app_cfg, buildPhases=[app_phase,app_resource],
                      buildRules=[], dependencies=[], name='NeuralDoom', productName='NeuralDoom',
                      productReference=app_product, productType='com.apple.product-type.application'))
test_target = obj(dict(isa='PBXNativeTarget', buildConfigurationList=test_cfg, buildPhases=[test_phase,test_resource],
                       buildRules=[], dependencies=[], name='CircuitTests', productName='CircuitTests',
                       productReference=test_product, productType='com.apple.product-type.tool'))
project = obj(dict(isa='PBXProject', attributes=dict(BuildIndependentTargetsInParallel='YES', LastUpgradeCheck='2650',
                    TargetAttributes={app_target:dict(CreatedOnToolsVersion='26.5'),test_target:dict(CreatedOnToolsVersion='26.5')}),
                   buildConfigurationList=project_cfg, compatibilityVersion='Xcode 16.0',
                   developmentRegion='en', hasScannedForEncodings='0', knownRegions=['en','Base'],
                   mainGroup=main_group, productRefGroup=products, projectDirPath='', projectRoot='',
                   targets=[app_target,test_target]))
lines = ['// !$*UTF8*$!', '{', '\tarchiveVersion = 1;', '\tclasses = {};', '\tobjectVersion = 77;', '\tobjects = {']
for key,fields in objects.items(): lines.append(f'\t\t{key} = {quote(fields)};')
lines += ['\t};', f'\trootObject = {project};', '}']
(root/'NeuralDoom.xcodeproj/project.pbxproj').write_text('\n'.join(lines)+'\n')
print(f'{len(core)} DoomGeneric C sources, {len(app_swift)} Swift sources')
