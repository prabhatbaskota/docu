"""Export complete final files, resolved licenses, and a copyable source bundle."""
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse
import zipfile

root=Path(__file__).resolve().parent.parent
out=root/'handoff'
out.mkdir(exist_ok=True)
groups={
 '01-live-edges': ['mobile/lib/core/document_edges.dart','mobile/lib/core/document_geometry.dart','mobile/lib/features/camera_scan_screen.dart','desktop/lib/core/document_edges.dart','desktop/lib/core/document_geometry.dart'],
 '02-sequential-correction': [f'{app}/{name}' for app in ['mobile','desktop'] for name in ['lib/features/scan/scan_draft.dart','lib/features/scan/edge_correction_screen.dart','lib/features/scan/scan_review_screen.dart','lib/features/scan_flow.dart','test/scan_regression_test.dart']]+['desktop/lib/features/scan/import_scan.dart'],
 '03-id-card': [f'{app}/lib/features/scan/card_scan_screen.dart' for app in ['mobile','desktop']],
 '04-compression': [f'{app}/{name}' for app in ['mobile','desktop'] for name in ['lib/core/pdf_engine.dart','lib/core/progress.dart','lib/features/compress/compress_flow.dart','lib/features/page_editor.dart']],
 '05-ocr': [f'{app}/{name}' for app in ['mobile','desktop'] for name in ['lib/core/database.dart','lib/core/ocr_service.dart','lib/core/searchable_pdf.dart','lib/features/documents/document.dart','lib/features/documents/document_card.dart','lib/features/documents/document_repository.dart','lib/features/documents/document_screen.dart','lib/features/documents/ocr_actions.dart','lib/features/settings/settings_page.dart','lib/main.dart','test/ocr_repository_test.dart']],
 '06-desktop-icon': ['desktop/packaging/windows/make_icon.dart','desktop/packaging/windows/docu.iss','desktop/windows/CMakeLists.txt','desktop/lib/features/desktop/desktop_home.dart'],
 '07-configuration': ['mobile/pubspec.yaml','mobile/pubspec.lock','mobile/android/app/build.gradle.kts','mobile/android/gradle.properties','mobile/android/app/src/main/AndroidManifest.xml','desktop/pubspec.yaml','desktop/pubspec.lock','desktop/analysis_options.yaml'],
}
all_files=set()
groups['07-configuration'] += ['mobile/ios/Podfile', 'mobile/ios/Flutter/Debug.xcconfig', 'mobile/ios/Flutter/Release.xcconfig', 'mobile/ios/Flutter/AppFrameworkInfo.plist', 'mobile/ios/Runner.xcodeproj/project.pbxproj', 'mobile/README.md', 'desktop/README.md', 'scripts/build-android-apk.ps1', 'scripts/ANDROID-BUILD.md']
all_files.add('verification/.gitignore')
groups['02-sequential-correction'] += [f'{app}/lib/core/scan_cleanup.dart' for app in ['mobile', 'desktop']]
for group,files in groups.items():
    sections=[f'# {group}\n\nComplete final integrated files. Apply the bundle as a whole; shared imports cross feature boundaries.\n\nSee [test steps and limits](README.md).\n']
    for name in files:
        path=root/name
        if not path.exists():continue
        all_files.add(name)
        language=path.suffix.lstrip('.')
        sections.append(f'\n## `{name}`\n\n```{language}\n{path.read_text(encoding="utf-8").rstrip()}\n```\n')
    (out/f'{group}.md').write_text(''.join(sections),encoding='utf-8')

licenses=out/'licenses'
licenses.mkdir(exist_ok=True)
packages={}
for app in ['mobile','desktop']:
    config=json.loads((root/app/'.dart_tool/package_config.json').read_text(encoding='utf-8'))
    for package in config['packages']:
        if package['name']=='docapp':continue
        uri=package['rootUri']
        if not uri.startswith('file:'):continue
        path=Path(unquote(urlparse(uri).path).lstrip('/'))
        pubspec=path/'pubspec.yaml'
        if not pubspec.exists():continue
        match=re.search(r'^version:\s*[\'"]?([^\s\'"]+)',pubspec.read_text(encoding='utf-8'),re.M)
        version=match.group(1) if match else 'Flutter SDK'
        candidates=[path/'LICENSE',path/'LICENSE.md',path/'LICENSE.txt']
        if 'flutter' in str(path).lower():candidates.append(Path('C:/src/flutter/LICENSE'))
        license_file=next((p for p in candidates if p.exists()),None)
        notice=license_file.read_text(encoding='utf-8',errors='replace') if license_file else ''
        lower=notice.lower()
        if 'apache license' in lower:kind='Apache-2.0'
        elif 'permission is hereby granted, free of charge' in lower:kind='MIT'
        elif 'redistribution and use in source and binary forms' in lower:
            kind='BSD-3-Clause' if 'endorse' in lower else 'BSD-2-Clause'
        elif 'mozilla public license' in lower:kind='MPL-2.0'
        elif 'public domain' in lower:kind='Public domain'
        elif 'isc license' in lower:kind='ISC'
        else:kind='See full upstream notice'
        name=package['name'];filename=f'{name}-{version}.txt'
        (licenses/filename).write_text(notice or 'License not included in installed package; review upstream before distribution.',encoding='utf-8')
        entry=packages.setdefault((name,version),[kind,filename,set()])
        entry[2].add(app)
lines=['# Resolved package versions and licenses\n\n',
 'Generated from each app\'s resolved package configuration and installed LICENSE files. Includes direct, transitive, development and SDK packages. Full notices are linked below.\n\n',
 'New direct dependencies: **opencv_dart 2.2.2 (Apache-2.0)** and **google_mlkit_text_recognition 0.17.1 (MIT wrapper)**. Removed the unused cunning_document_scanner dependency.\n\n',
 'Native components: OpenCV/dartcv4 Apache-2.0; PDFium BSD-style notices distributed by pdfrx; Tesseract Apache-2.0 with Leptonica BSD-2-Clause (desktop, separately installed). Bundled Noto Sans and Noto Sans Devanagari use SIL OFL-1.1; see each app\'s assets/fonts/OFL.txt. ML Kit Android text-recognition and text-recognition-devanagari are pinned to 16.0.1. ML Kit is a free proprietary SDK under Google\'s terms, explicitly approved for this task; its MIT wrapper does not change that.\n\n',
 '| Package | Resolved version | License | Apps |\n| --- | --- | --- | --- |\n']
for (name,version),(kind,filename,apps) in sorted(packages.items()):
    lines.append(f'| {name} | {version} | [{kind}](licenses/{filename}) | {", ".join(sorted(apps))} |\n')
(out/'DEPENDENCIES.md').write_text(''.join(lines),encoding='utf-8')
for app in ['mobile','desktop']:
    for path in (root/app/'assets/fonts').glob('*'):all_files.add(path.relative_to(root).as_posix())
for path in (root/'verification').rglob('*'):
    if path.is_file() and not any(part.startswith('.') or part=='build' for part in path.relative_to(root/'verification').parts):
        all_files.add(path.relative_to(root).as_posix())
all_files.update(['desktop/windows/runner/resources/app_icon.ico','desktop/windows/runner/resources/document_icon.ico'])
with zipfile.ZipFile(out/'docu-feature-updates.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(all_files):archive.write(root/name,name)
(out/'FILES.txt').write_text('\n'.join(sorted(all_files))+'\n',encoding='utf-8')
print(f'Exported {len(all_files)} files; {len(packages)} resolved package versions.')
