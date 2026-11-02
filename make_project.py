#!/usr/bin/env python3
"""Generate a standalone Xcode app, using the local reusable Swift package."""
import hashlib
import json
import os
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
BUILD = Path(os.environ.get("REUSE_BUILD_DIR", TOOLS / ".build/app"))
if not BUILD.is_absolute():
    BUILD = TOOLS / BUILD
BUILD = BUILD.resolve()

def main():
    project = BUILD / "ReuseLab.xcodeproj"
    project.mkdir(parents=True, exist_ok=True)
    entries = []
    def uid(name):
        return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
    def quote(value):
        return json.dumps(str(value))
    def ref(name):
        return uid(name)
    def add(name, isa, fields):
        entries.append(f"{uid(name)} = {{ isa = {isa}; {fields} }};")
        return uid(name)
    def array(items):
        return "(" + ",".join(items) + ")"
    sources = []
    app_files = []
    for path in sorted((TOOLS / "App").glob("*.swift")):
        file = add(str(path.relative_to(TOOLS)), "PBXFileReference", f"lastKnownFileType = sourcecode.swift; path = {quote(os.path.relpath(path, BUILD))}; sourceTree = SOURCE_ROOT;")
        app_files.append(file)
        sources.append(add("compile:" + str(path.relative_to(TOOLS)), "PBXBuildFile", f"fileRef = {file};"))
    resources = []
    resource_files = []
    model_resources = [TOOLS / "App/ModelCatalog.json", TOOLS / "App/ModelSource.json"]
    for path in model_resources + [TOOLS / "App/Samples", TOOLS / "App/Notices.txt", TOOLS / "App/Assets.xcassets"]:
        if not path.exists():
            raise FileNotFoundError(path.name)
        kind = "folder.assetcatalog" if path.suffix == ".xcassets" else "folder" if path.is_dir() else "text"
        file = add(str(path.relative_to(TOOLS)), "PBXFileReference", f"lastKnownFileType = {kind}; path = {quote(os.path.relpath(path, BUILD))}; sourceTree = SOURCE_ROOT;")
        resource_files.append(file)
        resources.append(add("resource:" + str(path.relative_to(TOOLS)), "PBXBuildFile", f"fileRef = {file};"))
    add("app", "PBXFileReference", 'explicitFileType = wrapper.application; path = ReuseLab.app; sourceTree = BUILT_PRODUCTS_DIR;')
    add("products", "PBXGroup", f'children = ({ref("app")}); name = Products; sourceTree = "<group>";')
    add("group", "PBXGroup", f'children = {array(app_files + resource_files + [ref("products")])}; sourceTree = "<group>";')
    add("package", "XCLocalSwiftPackageReference", f"relativePath = {quote(os.path.relpath(TOOLS, BUILD))};")
    add("sdk", "XCSwiftPackageProductDependency", f"package = {ref('package')}; productName = ReuseKit;")
    add("link-sdk", "PBXBuildFile", f"productRef = {ref('sdk')};")
    add("playback-sdk", "XCSwiftPackageProductDependency", f"package = {ref('package')}; productName = ReusePlayback;")
    add("link-playback-sdk", "PBXBuildFile", f"productRef = {ref('playback-sdk')};")
    add("assets-sdk", "XCSwiftPackageProductDependency", f"package = {ref('package')}; productName = ReuseModelAssets;")
    add("link-assets-sdk", "PBXBuildFile", f"productRef = {ref('assets-sdk')};")
    add("sources", "PBXSourcesBuildPhase", f"buildActionMask = 2147483647; files = {array(sources)}; runOnlyForDeploymentPostprocessing = 0;")
    add("resources", "PBXResourcesBuildPhase", f"buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;")
    add("frameworks", "PBXFrameworksBuildPhase", f"buildActionMask = 2147483647; files = ({ref('link-sdk')},{ref('link-playback-sdk')},{ref('link-assets-sdk')}); runOnlyForDeploymentPostprocessing = 0;")
    add("target", "PBXNativeTarget", f"buildConfigurationList = {ref('target-configs')}; buildPhases = ({ref('sources')},{ref('frameworks')},{ref('resources')}); buildRules = (); dependencies = (); name = ReuseLab; packageProductDependencies = ({ref('sdk')},{ref('playback-sdk')},{ref('assets-sdk')}); productName = ReuseLab; productReference = {ref('app')}; productType = \"com.apple.product-type.application\";")
    for level in ("project", "target"):
        configs = []
        for configuration in ("Debug", "Release"):
            settings = {
                "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "6.0",
                "CLANG_ENABLE_MODULES": "YES", "SWIFT_OPTIMIZATION_LEVEL": "-O" if configuration == "Release" else "-Onone",
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym" if configuration == "Release" else "dwarf",
                "SWIFT_COMPILATION_MODE": "wholemodule" if configuration == "Release" else "incremental",
            }
            if level == "target":
                settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "app.stackchan.reuse.lab", "PRODUCT_NAME": "$(TARGET_NAME)",
                                 "INFOPLIST_FILE": os.path.relpath(TOOLS / "App/Info.plist", BUILD), "GENERATE_INFOPLIST_FILE": "NO",
                                 "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGN_STYLE": "Automatic",
                                 "DEVELOPMENT_TEAM": os.environ.get("REUSE_DEVELOPMENT_TEAM", ""), "ENABLE_PREVIEWS": "NO",
                                 "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                                 "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
            body = " ".join(f"{key} = {quote(value)};" for key, value in settings.items())
            configs.append(add(level + configuration, "XCBuildConfiguration", f"buildSettings = {{ {body} }}; name = {configuration};"))
        add(level + "-configs", "XCConfigurationList", f"buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    add("project", "PBXProject", f"attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {ref('project-configs')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {ref('group')}; packageReferences = ({ref('package')}); productRefGroup = {ref('products')}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({ref('target')});")
    (project / "project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(entries) + f"\n}}; rootObject = {ref('project')}; }}\n")
    scheme = project / "xcshareddata/xcschemes/ReuseLab.xcscheme"
    scheme.parent.mkdir(parents=True, exist_ok=True)
    buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target")}" BuildableName="ReuseLab.app" BlueprintName="ReuseLab" ReferencedContainer="container:ReuseLab.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
    print(project)

if __name__ == "__main__":
    main()
