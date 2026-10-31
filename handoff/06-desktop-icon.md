# 06-desktop-icon

Complete final integrated files. Apply the bundle as a whole; shared imports cross feature boundaries.

See [test steps and limits](README.md).

## `desktop/packaging/windows/make_icon.dart`

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Builds the Windows icon from the same source artwork as the mobile icon.
void main() {
  final source = img.decodePng(File('assets/icon/icon.png').readAsBytesSync());
  if (source == null) throw StateError('Could not read app icon');
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final images = [
    for (final size in sizes)
      Uint8List.fromList(img.encodePng(img.copyResize(source,
          width: size,
          height: size,
          interpolation: img.Interpolation.average))),
  ];
  final headerSize = 6 + sizes.length * 16;
  final total =
      headerSize + images.fold<int>(0, (n, bytes) => n + bytes.length);
  final data = ByteData(total);
  data.setUint16(2, 1, Endian.little);
  data.setUint16(4, sizes.length, Endian.little);
  var offset = headerSize;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + i * 16;
    data.setUint8(entry, sizes[i] == 256 ? 0 : sizes[i]);
    data.setUint8(entry + 1, sizes[i] == 256 ? 0 : sizes[i]);
    data.setUint16(entry + 4, 1, Endian.little);
    data.setUint16(entry + 6, 32, Endian.little);
    data.setUint32(entry + 8, images[i].length, Endian.little);
    data.setUint32(entry + 12, offset, Endian.little);
    data.buffer
        .asUint8List()
        .setRange(offset, offset + images[i].length, images[i]);
    offset += images[i].length;
  }
  final output = File('windows/runner/resources/app_icon.ico');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(data.buffer.asUint8List());
  // The document association uses a dedicated page silhouette with the docu mark.
  final page = img.Image(width: 512, height: 512, numChannels: 4);
  img.fill(page, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(page,
      x1: 92,
      y1: 24,
      x2: 420,
      y2: 488,
      radius: 24,
      color: img.ColorRgb8(220, 229, 239));
  img.fillRect(page,
      x1: 102,
      y1: 34,
      x2: 410,
      y2: 478,
      radius: 18,
      color: img.ColorRgb8(255, 255, 255));
  final mark = img.copyResize(source,
      width: 200, height: 200, interpolation: img.Interpolation.average);
  img.compositeImage(page, mark, dstX: 156, dstY: 124);
  for (final y in [362, 394, 426]) {
    img.fillRect(page,
        x1: 152,
        y1: y,
        x2: y == 426 ? 302 : 360,
        y2: y + 10,
        radius: 5,
        color: img.ColorRgb8(127, 149, 172));
  }
  final documentImages = [
    for (final size in sizes)
      Uint8List.fromList(img.encodePng(img.copyResize(page,
          width: size, height: size, interpolation: img.Interpolation.average)))
  ];
  final documentData = ByteData(
      headerSize + documentImages.fold<int>(0, (n, b) => n + b.length));
  documentData.setUint16(2, 1, Endian.little);
  documentData.setUint16(4, sizes.length, Endian.little);
  var position = headerSize;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + i * 16;
    documentData.setUint8(entry, sizes[i] == 256 ? 0 : sizes[i]);
    documentData.setUint8(entry + 1, sizes[i] == 256 ? 0 : sizes[i]);
    documentData.setUint16(entry + 4, 1, Endian.little);
    documentData.setUint16(entry + 6, 32, Endian.little);
    documentData.setUint32(entry + 8, documentImages[i].length, Endian.little);
    documentData.setUint32(entry + 12, position, Endian.little);
    documentData.buffer.asUint8List().setRange(
        position, position + documentImages[i].length, documentImages[i]);
    position += documentImages[i].length;
  }
  File('windows/runner/resources/document_icon.ico')
      .writeAsBytesSync(documentData.buffer.asUint8List());
}
```

## `desktop/packaging/windows/docu.iss`

```iss
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

[Setup]
AppId=docu.desktop
AppName=docu
AppVersion={#MyAppVersion}
ChangesAssociations=yes
DefaultDirName={localappdata}\Programs\docu
DefaultGroupName=docu
OutputDir=..\..\release
OutputBaseFilename=docu-windows-x64-setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "docu.PDF"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\docu.PDF"; ValueType: string; ValueData: "docu PDF document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\docu.PDF\DefaultIcon"; ValueType: string; ValueData: """{app}\document_icon.ico"",0"
Root: HKA; Subkey: "Software\Classes\docu.PDF\shell\open\command"; ValueType: string; ValueData: """{app}\docapp.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\docapp.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "docu"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\docapp.exe\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\docapp.exe\shell\open\command"; ValueType: string; ValueData: """{app}\docapp.exe"" ""%1"""

[Icons]
Name: "{group}\docu"; Filename: "{app}\docapp.exe"
Name: "{userdesktop}\docu"; Filename: "{app}\docapp.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional options:"

[Run]
Filename: "{app}\docapp.exe"; Description: "Launch docu"; Flags: nowait postinstall skipifsilent
```

## `desktop/windows/CMakeLists.txt`

```txt
# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(docapp LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "docapp")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/runner/resources/document_icon.ico"
  DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
```

## `desktop/lib/features/desktop/desktop_home.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/format.dart';
import '../compress/compress_flow.dart';
import '../documents/actions.dart';
import '../documents/document.dart';
import '../documents/document_repository.dart';
import '../documents/document_screen.dart';
import '../documents/providers.dart';
import '../editor_launch.dart';
import '../pickers.dart';
import '../scan_flow.dart';
import 'external_pdf_screen.dart';

/// Desktop library. Folders are local library categories; PDFs remain in the
/// app's document store so renaming a folder cannot break file references.
class DesktopHome extends ConsumerStatefulWidget {
  const DesktopHome({super.key, this.initialPdfPath});

  final String? initialPdfPath;

  @override
  ConsumerState<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends ConsumerState<DesktopHome> {
  String? _folderId;
  bool _unfiled = false;
  bool _recent = false;
  String _search = '';
  SortMode _sort = SortMode.recent;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final path = widget.initialPdfPath;
    if (path != null) {
      _recent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExternalPdfScreen(path: path),
        ));
      });
    }
  }

  Future<void> _newFolder() async {
    final name =
        await askText(context, title: 'New folder', label: 'Folder name');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final folder = await ref.read(repositoryProvider).createFolder(name);
      setState(() {
        _folderId = folder.id;
        _unfiled = false;
        _recent = false;
      });
    } catch (_) {
      _message('A folder with that name already exists.');
    }
  }

  Future<void> _renameFolder(DocumentFolder folder) async {
    final name = await askText(context,
        title: 'Rename folder', initial: folder.name, label: 'Folder name');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await ref.read(repositoryProvider).renameFolder(folder.id, name);
    } catch (_) {
      _message('A folder with that name already exists.');
    }
  }

  Future<void> _deleteFolder(DocumentFolder folder) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${folder.name}?'),
        content: const Text('PDFs in this folder will move to Unfiled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await ref.read(repositoryProvider).deleteFolder(folder.id);
    setState(() {
      if (_folderId == folder.id) {
        _folderId = null;
        _unfiled = true;
      }
    });
  }

  Future<void> _move(List<String> ids, List<DocumentFolder> folders) async {
    if (ids.isEmpty) return;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const ListTile(
                leading: Icon(Icons.folder_off_outlined),
                title: Text('Unfiled')),
          ),
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.id),
              child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name)),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await ref
        .read(repositoryProvider)
        .moveToFolder(ids, target.isEmpty ? null : target);
    setState(_selected.clear);
  }

  Future<void> _export(Document doc) async {
    await exportDocument(context, doc);
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _docAction(
      String action, Document doc, List<DocumentFolder> folders) async {
    switch (action) {
      case 'move':
        await _move([doc.id], folders);
        return;
      case 'export':
        await _export(doc);
        return;
      case 'rename':
        if (mounted) await renameDocument(context, doc);
        return;
      case 'edit':
        if (mounted) await editDocument(context, doc);
        return;
      case 'compress':
        if (mounted) await compressDocument(context, doc);
        return;
    }
  }

  Future<void> _mergeSelected(List<Document> documents) async {
    final byId = {for (final doc in documents) doc.id: doc};
    final chosen = [
      for (final id in _selected)
        if (byId.containsKey(id)) byId[id]!,
    ];
    if (chosen.length < 2) return;
    final compress = await askMergeMode(context);
    if (compress == null || !mounted) return;
    final repo = ref.read(repositoryProvider);
    setState(_selected.clear);
    await mergeIntoEditor(context, [for (final doc in chosen) repo.pathOf(doc)],
        compress: compress, folderId: _folderId, openAfterSave: true);
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    setState(_selected.clear);
    await deleteWithUndo(context, ids);
  }

  void _navigate(String? folderId, {bool unfiled = false}) {
    setState(() {
      _folderId = folderId;
      _unfiled = unfiled;
      _recent = false;
      _selected.clear();
    });
  }

  Future<void> _openRecent(RecentPdf file) async {
    if (!mounted) return;
    await ref.read(repositoryProvider).recordRecentFile(file.path);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExternalPdfScreen(path: file.path),
    ));
  }

  List<Document> _visible(List<Document> docs) {
    final needle = _search.trim().toLowerCase();
    final result = docs.where((d) {
      if (_folderId != null && d.folderId != _folderId) return false;
      if (_unfiled && d.folderId != null) return false;
      return needle.isEmpty || d.title.toLowerCase().contains(needle);
    }).toList();
    result.sort((a, b) => switch (_sort) {
          SortMode.recent => b.updatedAt.compareTo(a.updatedAt),
          SortMode.name =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          SortMode.size => b.sizeBytes.compareTo(a.sizeBytes),
        });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final foldersAsync = ref.watch(_foldersProvider);
    final recentAsync = ref.watch(recentFilesProvider);
    final all = docsAsync.value ?? const <Document>[];
    final folders = foldersAsync.value ?? const <DocumentFolder>[];
    final docs = _visible(all);
    final title = _recent
        ? 'Recently opened'
        : _folderId == null
            ? (_unfiled ? 'Unfiled' : 'All documents')
            : folders
                    .where((f) => f.id == _folderId)
                    .map((f) => f.name)
                    .firstOrNull ??
                'Folder';

    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              importPdfs(context, folderId: _folderId),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newFolder,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_selected.isNotEmpty) setState(_selected.clear);
          },
        },
        child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 250,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 26, 16, 24),
                            child: Text('docu',
                                style: TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          _sideItem(
                              Icons.description_outlined,
                              'All documents',
                              _folderId == null && !_unfiled && !_recent,
                              () => _navigate(null)),
                          _sideItem(Icons.history, 'Recently opened', _recent,
                              () {
                            setState(() {
                              _recent = true;
                              _selected.clear();
                            });
                          }),
                          _sideItem(
                              Icons.folder_off_outlined,
                              'Unfiled',
                              _unfiled && !_recent,
                              () => _navigate(null, unfiled: true)),
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                            child: Row(children: [
                              const Expanded(
                                  child: Text('FOLDERS',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              IconButton(
                                  tooltip: 'New folder',
                                  onPressed: _newFolder,
                                  icon: const Icon(
                                      Icons.create_new_folder_outlined)),
                            ]),
                          ),
                          Expanded(
                            child: ListView(children: [
                              for (final folder in folders)
                                ListTile(
                                  dense: true,
                                  selected: !_recent && _folderId == folder.id,
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(folder.name,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () => _navigate(folder.id),
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Folder options',
                                    onSelected: (value) => value == 'rename'
                                        ? _renameFolder(folder)
                                        : _deleteFolder(folder),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename')),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete')),
                                    ],
                                  ),
                                ),
                            ]),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Stored locally on this computer',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                                width: 220,
                                child: Text(title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall)),
                            SizedBox(
                              width: 280,
                              child: SearchBar(
                                hintText: 'Search PDFs',
                                leading: const Icon(Icons.search),
                                onChanged: (value) =>
                                    setState(() => _search = value),
                              ),
                            ),
                            if (!_recent)
                              DropdownButton<SortMode>(
                                value: _sort,
                                onChanged: (value) =>
                                    setState(() => _sort = value ?? _sort),
                                items: [
                                  for (final mode in SortMode.values)
                                    DropdownMenuItem(
                                        value: mode,
                                        child: Text('Sort: ${mode.label}'))
                                ],
                              ),
                            FilledButton.icon(
                              onPressed: () =>
                                  importPdfs(context, folderId: _folderId),
                              icon: const Icon(Icons.file_open_outlined),
                              label: const Text('Import PDFs'),
                            ),
                            OutlinedButton.icon(
                                onPressed: _newFolder,
                                icon: const Icon(
                                    Icons.create_new_folder_outlined),
                                label: const Text('New folder')),
                          ],
                        ),
                      ),
                      if (!_recent)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await pickPdf(context);
                                if (picked == null || !mounted) return;
                                if (picked.doc != null) {
                                  await editDocument(this.context, picked.doc!);
                                } else {
                                  await editExternalPdf(
                                      this.context, picked.path);
                                }
                              },
                              icon: const Icon(Icons.edit_note),
                              label: const Text('Edit pages'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final paths = await pickPdfsForMerge(context);
                                if (paths == null || !mounted) return;
                                final compress =
                                    await askMergeMode(this.context);
                                if (compress == null || !mounted) return;
                                await mergeIntoEditor(this.context, paths,
                                    compress: compress,
                                    folderId: _folderId,
                                    openAfterSave: true);
                              },
                              icon: const Icon(Icons.merge_type),
                              label: const Text('Merge'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await pickPdf(context);
                                if (picked == null || !mounted) return;
                                await compressPdfFile(this.context,
                                    path: picked.path,
                                    title: picked.doc?.title ??
                                        p.basenameWithoutExtension(
                                            picked.path));
                              },
                              icon: const Icon(Icons.compress),
                              label: const Text('Compress'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final images = await pickImages();
                                if (images.isNotEmpty && mounted) {
                                  await imagesIntoEditor(this.context, images,
                                      defaultName: 'Photos ${stamp()}');
                                }
                              },
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Images to PDF'),
                            ),
                            OutlinedButton.icon(
                                onPressed: () => startScan(context),
                                icon:
                                    const Icon(Icons.document_scanner_outlined),
                                label: const Text('Scan photos / ID')),
                          ]),
                        ),
                      if (!_recent && _selected.isNotEmpty)
                        Material(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 8),
                            child: Row(children: [
                              Text('${_selected.length} selected'),
                              const SizedBox(width: 12),
                              TextButton.icon(
                                  onPressed: () =>
                                      _move(_selected.toList(), folders),
                                  icon:
                                      const Icon(Icons.drive_file_move_outline),
                                  label: const Text('Move')),
                              if (_selected.length > 1)
                                TextButton.icon(
                                    onPressed: () => _mergeSelected(all),
                                    icon: const Icon(Icons.merge_type),
                                    label: const Text('Merge')),
                              if (_selected.length == 1)
                                TextButton.icon(
                                    onPressed: () {
                                      final selected = all.firstWhere(
                                          (doc) => doc.id == _selected.single);
                                      compressDocument(context, selected);
                                    },
                                    icon: const Icon(Icons.compress),
                                    label: const Text('Compress')),
                              TextButton.icon(
                                  onPressed: _deleteSelected,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete')),
                              TextButton(
                                  onPressed: () => setState(_selected.clear),
                                  child: const Text('Clear')),
                            ]),
                          ),
                        ),
                      Expanded(
                        child: _recent
                            ? recentAsync.when(
                                loading: () => const Center(
                                    child: CircularProgressIndicator()),
                                error: (error, _) =>
                                    Center(child: Text('$error')),
                                data: (files) {
                                  final needle = _search.trim().toLowerCase();
                                  final visible = files
                                      .where((file) =>
                                          needle.isEmpty ||
                                          p
                                              .basename(file.path)
                                              .toLowerCase()
                                              .contains(needle))
                                      .toList();
                                  if (visible.isEmpty) {
                                    return Center(
                                        child: Text(needle.isEmpty
                                            ? 'No recently opened PDFs yet. Open a PDF with docu from File Explorer.'
                                            : 'No matching PDFs'));
                                  }
                                  return ListView.builder(
                                    itemCount: visible.length,
                                    itemBuilder: (context, index) {
                                      final file = visible[index];
                                      return ListTile(
                                        leading: const Icon(
                                            Icons.picture_as_pdf_outlined),
                                        title: Text(p.basename(file.path),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        subtitle: Text(file.path,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        onTap: () => _openRecent(file),
                                        trailing: IconButton(
                                          tooltip:
                                              'Remove from recently opened',
                                          icon: const Icon(Icons.close),
                                          onPressed: () => ref
                                              .read(repositoryProvider)
                                              .removeRecentFile(file.path),
                                        ),
                                      );
                                    },
                                  );
                                },
                              )
                            : docsAsync.isLoading || foldersAsync.isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : docsAsync.hasError || foldersAsync.hasError
                                    ? Center(
                                        child: Text(
                                            '${docsAsync.error ?? foldersAsync.error}'))
                                    : docs.isEmpty
                                        ? Center(
                                            child: Text(_search.isNotEmpty
                                                ? 'No matching PDFs'
                                                : 'No PDFs here. Import files or move them into this folder.'))
                                        : ListView.builder(
                                            itemCount: docs.length,
                                            itemBuilder: (context, index) {
                                              final doc = docs[index];
                                              return ListTile(
                                                selected:
                                                    _selected.contains(doc.id),
                                                leading: Checkbox(
                                                  value: _selected
                                                      .contains(doc.id),
                                                  onChanged: (_) =>
                                                      setState(() {
                                                    if (!_selected
                                                        .add(doc.id)) {
                                                      _selected.remove(doc.id);
                                                    }
                                                  }),
                                                ),
                                                title: Text(doc.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                                subtitle: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                                                  if(doc.snippet!=null)Text(doc.snippet!,maxLines:2,overflow:TextOverflow.ellipsis),
                                                  Text('${doc.pageCount} pages · ${fmtSize(doc.sizeBytes)}${doc.ocrStatus=='reading'?' · Reading text…':doc.ocrStatus=='ready'?' · Text ready':''}')]),
                                                onTap: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            DocumentScreen(
                                                                id: doc.id))),
                                                trailing:
                                                    PopupMenuButton<String>(
                                                  tooltip: 'Document options',
                                                  onSelected: (action) =>
                                                      _docAction(
                                                          action, doc, folders),
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                        value: 'edit',
                                                        child:
                                                            Text('Edit pages')),
                                                    PopupMenuItem(
                                                        value: 'compress',
                                                        child:
                                                            Text('Compress')),
                                                    PopupMenuItem(
                                                        value: 'move',
                                                        child: Text(
                                                            'Move to folder')),
                                                    PopupMenuItem(
                                                        value: 'rename',
                                                        child: Text('Rename')),
                                                    PopupMenuItem(
                                                        value: 'export',
                                                        child:
                                                            Text('Export PDF')),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                      ),
                    ]),
                  ),
                ],
              ),
            )));
  }

  Widget _sideItem(
          IconData icon, String title, bool selected, VoidCallback onTap) =>
      ListTile(
          leading: Icon(icon),
          title: Text(title),
          selected: selected,
          onTap: onTap);
}

final _foldersProvider = StreamProvider<List<DocumentFolder>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  yield await repo.folders();
  await for (final _ in repo.changes) {
    yield await repo.folders();
  }
});
```
