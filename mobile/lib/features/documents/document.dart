enum SortMode { recent, name, size }

extension SortModeLabel on SortMode {
  String get label => switch (this) {
        SortMode.recent => 'Recent',
        SortMode.name => 'Name',
        SortMode.size => 'Size',
      };
}

class DocQuery {
  final String text;
  final bool favoritesOnly;
  final SortMode sort;
  const DocQuery({
    this.text = '',
    this.favoritesOnly = false,
    this.sort = SortMode.recent,
  });

  bool get isFiltered => text.trim().isNotEmpty || favoritesOnly;

  DocQuery copyWith({String? text, bool? favoritesOnly, SortMode? sort}) =>
      DocQuery(
        text: text ?? this.text,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        sort: sort ?? this.sort,
      );
}

class Document {
  final String id;
  final String title;
  final String fileName; // relative to the library folder
  final int pageCount;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorite;
  final bool compressed;
  final String? folderId;

  const Document({
    required this.id,
    required this.title,
    required this.fileName,
    required this.pageCount,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.favorite = false,
    this.compressed = false,
    this.folderId,
  });

  factory Document.fromRow(Map<String, Object?> r) => Document(
        id: r['id'] as String,
        title: r['title'] as String,
        fileName: r['file_name'] as String,
        pageCount: r['page_count'] as int,
        sizeBytes: r['size_bytes'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
        favorite: (r['favorite'] as int) == 1,
        compressed: r['compressed'] == 1,
        folderId: r['folder_id'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'file_name': fileName,
        'page_count': pageCount,
        'size_bytes': sizeBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'favorite': favorite ? 1 : 0,
        'deleted': 0,
        'compressed': compressed ? 1 : 0,
        'folder_id': folderId,
      };
}
