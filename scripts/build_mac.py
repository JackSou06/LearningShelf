#!/usr/bin/env python3
import json,plistlib,shutil,subprocess
from pathlib import Path
from build_icon import build_icon
ROOT=Path(__file__).resolve().parents[1]
APP=ROOT/'dist'/'LearningShelf.app';MAC=APP/'Contents/MacOS';RES=APP/'Contents/Resources'
MAC.mkdir(parents=True,exist_ok=True);RES.mkdir(parents=True,exist_ok=True)
for folder,target in [('web','Web'),('courses','Courses'),('protocol','Protocol')]:
 shutil.copytree(ROOT/folder,RES/target,dirs_exist_ok=True)
# Native loading uses the library files directly; no need to parse built-in browser snapshots.
(RES/'Web/library.js').write_text('window.BUNDLED_COURSES=[];\n')
build_icon(ROOT/'resources/learningShelf_icon_macos.png',RES/'LearningShelf.icns')
binaries=[]
for arch in ['arm64','x86_64']:
 binary=ROOT/'dist'/('LearningShelf-'+arch)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-O','-target',f'{arch}-apple-macos13.0','-module-cache-path',str(ROOT/'.swift-cache'),*map(str,sorted((ROOT/'native').glob('*.swift'))),'-framework','SwiftUI','-framework','WebKit','-framework','JavaScriptCore','-framework','Security','-framework','Network','-framework','PDFKit','-lsqlite3','-o',str(binary)],check=True)
 binaries.append(str(binary))
subprocess.run(['lipo','-create',*binaries,'-output',str(MAC/'LearningShelf')],check=True)
info={'CFBundleName':'學習工具','CFBundleDisplayName':'學習工具','CFBundleIdentifier':'com.jacksou.LearningShelf','CFBundleExecutable':'LearningShelf','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.7','CFBundleVersion':'10','CFBundleIconFile':'LearningShelf','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSLocalNetworkUsageDescription':'分享選定課程，讓同一網路的裝置閱讀。'}
(APP/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-','--deep',str(APP)],check=True)
print(APP)
