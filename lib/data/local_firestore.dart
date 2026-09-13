import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore din memorie, doar cât îi trebuie lui [MultiplayerService] într-un
/// meci cu boți (data/bot_match.dart): documente, colecții, fluxuri live,
/// tranzacții, loturi. Fără interogări (`where`/`orderBy`) — fluxul cu boți nu
/// le folosește; orice membru neimplementat aruncă [UnimplementedError].
///
/// DE CE NU `fake_cloud_firestore`: pachetul refuză să ruleze în build-uri de
/// release și, mai grav, înlocuiește GLOBAL fabrica de `FieldValue` a
/// Firestore-ului real — după un meci cu boți, scrierile reale cu
/// `serverTimestamp()` din aceeași sesiune s-ar fi stricat.
///
/// `@sealed` din cloud_firestore e doar o adnotare (package:meta), nu o
/// restricție de limbaj — de-aia `ignore`-urile de pe clasele de mai jos.
///
/// Valori speciale: orice [FieldValue] primit e tratat ca `serverTimestamp()`
/// (singurul folosit de modele); `arrayUnion` vine ca [LocalArrayUnion], vezi
/// `MultiplayerService._arrayUnion`.
class LocalFirestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> _docs = {};
  final Map<String, int> _versions = {};
  final Map<String, Set<void Function()>> _listeners = {};
  final Random _rnd = Random();

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _LocalCollection(this, collectionPath);

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) => _LocalDoc(this, documentPath);

  @override
  WriteBatch batch() => _LocalBatch(this);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 1;; attempt++) {
      final tx = _LocalTransaction(this);
      final result = await transactionHandler(tx);
      final stale = tx._readVersions.entries.any((e) => (_versions[e.key] ?? 0) != e.value);
      if (!stale) {
        _apply(tx._writes);
        return result;
      }
      if (attempt >= maxAttempts) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted', message: 'transaction conflict');
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore: ${invocation.memberName}');

  // ─── Stocare ───────────────────────────────────────────────────────────

  String _autoId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  static String _parentOf(String docPath) => docPath.substring(0, docPath.lastIndexOf('/'));

  Map<String, dynamic>? _read(String path) {
    final d = _docs[path];
    return d == null ? null : _copyMap(d);
  }

  void _apply(List<_Write> writes) {
    final touched = <String>{};
    for (final w in writes) {
      switch (w.kind) {
        case _WriteKind.set:
          _docs[w.path] = _resolveMap(w.data!, const {});
        case _WriteKind.update:
          final current = _docs[w.path];
          if (current == null) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found', message: 'No document: ${w.path}');
          }
          w.data!.forEach((key, value) => _setPath(current, key.toString().split('.'), value));
        case _WriteKind.delete:
          _docs.remove(w.path);
      }
      _versions[w.path] = (_versions[w.path] ?? 0) + 1;
      touched
        ..add(w.path)
        ..add(_parentOf(w.path));
    }
    final callbacks = <void Function()>{
      for (final path in touched) ...?_listeners[path],
    };
    scheduleMicrotask(() {
      for (final c in callbacks) {
        c();
      }
    });
  }

  void _setPath(Map<String, dynamic> target, List<String> keys, Object? value) {
    var node = target;
    for (final k in keys.take(keys.length - 1)) {
      final next = node[k];
      if (next is Map<String, dynamic>) {
        node = next;
      } else {
        final created = <String, dynamic>{};
        node[k] = created;
        node = created;
      }
    }
    final last = keys.last;
    node[last] = _resolve(value, node[last]);
  }

  Object? _resolve(Object? value, Object? current) {
    if (value is FieldValue) return Timestamp.now();
    if (value is LocalArrayUnion) {
      final list = current is List ? List<dynamic>.of(current) : <dynamic>[];
      for (final e in value.elements) {
        if (!list.contains(e)) list.add(e);
      }
      return list;
    }
    if (value is Map) return _resolveMap(value, const {});
    if (value is List) return [for (final e in value) _resolve(e, null)];
    return value;
  }

  Map<String, dynamic> _resolveMap(Map<dynamic, dynamic> data, Map<String, dynamic> current) =>
      {for (final e in data.entries) e.key.toString(): _resolve(e.value, current[e.key])};

  static Object? _copy(Object? v) {
    if (v is Map) return _copyMap(v);
    if (v is List) return [for (final e in v) _copy(e)];
    return v;
  }

  static Map<String, dynamic> _copyMap(Map<dynamic, dynamic> m) =>
      {for (final e in m.entries) e.key.toString(): _copy(e.value)};

  /// Multi-abonament, ca `snapshots()` din Firestore: fiecare ascultător
  /// primește starea curentă, apoi fiecare schimbare. Un stream simplu ar fi
  /// rupt codul care ascultă același flux de două ori (ecranul de rezultate).
  Stream<T> _watch<T>(String path, T Function() snapshot) => Stream<T>.multi((controller) {
        void emit() {
          if (!controller.isClosed) controller.add(snapshot());
        }

        (_listeners[path] ??= {}).add(emit);
        scheduleMicrotask(emit);
        controller.onCancel = () => _listeners[path]?.remove(emit);
      });
}

/// Echivalentul local al `FieldValue.arrayUnion` — vezi [LocalFirestore].
class LocalArrayUnion {
  final List<Object?> elements;
  const LocalArrayUnion(this.elements);
}

// ignore: subtype_of_sealed_class
class _LocalDoc implements DocumentReference<Map<String, dynamic>> {
  _LocalDoc(this._db, this.path);
  final LocalFirestore _db;
  @override
  final String path;

  @override
  FirebaseFirestore get firestore => _db;

  @override
  String get id => path.substring(path.lastIndexOf('/') + 1);

  @override
  CollectionReference<Map<String, dynamic>> get parent => _LocalCollection(_db, LocalFirestore._parentOf(path));

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _LocalCollection(_db, '$path/$collectionPath');

  @override
  Future<void> delete() async => _db._apply([_Write(_WriteKind.delete, path)]);

  @override
  Future<void> update(Map<Object, Object?> data) async => _db._apply([_Write(_WriteKind.update, path, data)]);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async =>
      _db._apply([_Write(_WriteKind.set, path, data)]);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async => _snapshot();

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      _db._watch(path, _snapshot);

  _LocalSnapshot _snapshot() => _LocalSnapshot(this, _db._read(path));

  @override
  bool operator ==(Object other) => other is _LocalDoc && other.path == path && identical(other._db, _db);

  @override
  int get hashCode => path.hashCode;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore document: ${invocation.memberName}');
}

// ignore: subtype_of_sealed_class
class _LocalCollection implements CollectionReference<Map<String, dynamic>> {
  _LocalCollection(this._db, this.path);
  final LocalFirestore _db;
  @override
  final String path;

  @override
  String get id => path.substring(path.lastIndexOf('/') + 1);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _LocalDoc(_db, '${this.path}/${path ?? _db._autoId()}');

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(Map<String, dynamic> data) async {
    final ref = doc();
    await ref.set(data);
    return ref;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async => _snapshot();

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      _db._watch(path, _snapshot);

  _LocalQuerySnapshot _snapshot() {
    final prefix = '$path/';
    final ids = _db._docs.keys
        .where((k) => k.startsWith(prefix) && !k.substring(prefix.length).contains('/'))
        .toList()
      ..sort();
    return _LocalQuerySnapshot([
      for (final k in ids) _LocalQueryDocSnapshot(_LocalDoc(_db, k), _db._read(k)!),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore collection: ${invocation.memberName}');
}

// ignore: subtype_of_sealed_class
class _LocalSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _LocalSnapshot(this.reference, this._data);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? _data;

  @override
  String get id => reference.id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data?[field];

  @override
  dynamic operator [](Object field) => get(field);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore snapshot: ${invocation.memberName}');
}

// ignore: subtype_of_sealed_class
class _LocalQueryDocSnapshot extends _LocalSnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _LocalQueryDocSnapshot(super.reference, Map<String, dynamic> super._data);

  @override
  Map<String, dynamic> data() => _data!;
}

class _LocalQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _LocalQuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore query snapshot: ${invocation.memberName}');
}

enum _WriteKind { set, update, delete }

class _Write {
  _Write(this.kind, this.path, [this.data]);
  final _WriteKind kind;
  final String path;
  final Map<Object?, Object?>? data;
}

class _LocalBatch implements WriteBatch {
  _LocalBatch(this._db);
  final LocalFirestore _db;
  final List<_Write> _writes = [];

  @override
  Future<void> commit() async => _db._apply(_writes);

  @override
  void delete(DocumentReference<Object?> document) => _writes.add(_Write(_WriteKind.delete, document.path));

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _writes.add(_Write(_WriteKind.set, document.path, data as Map<Object?, Object?>));

  @override
  void update<T>(DocumentReference<T> document, T data) =>
      _writes.add(_Write(_WriteKind.update, document.path, data as Map<Object?, Object?>));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore batch: ${invocation.memberName}');
}

class _LocalTransaction implements Transaction {
  _LocalTransaction(this._db);
  final LocalFirestore _db;
  final List<_Write> _writes = [];
  final Map<String, int> _readVersions = {};

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> documentReference) async {
    final path = documentReference.path;
    _readVersions.putIfAbsent(path, () => _db._versions[path] ?? 0);
    return _LocalSnapshot(_LocalDoc(_db, path), _db._read(path)) as DocumentSnapshot<T>;
  }

  @override
  Transaction delete(DocumentReference<Object?> documentReference) {
    _writes.add(_Write(_WriteKind.delete, documentReference.path));
    return this;
  }

  @override
  Transaction update(DocumentReference<Object?> documentReference, Map<Object, Object?> data) {
    _writes.add(_Write(_WriteKind.update, documentReference.path, data));
    return this;
  }

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    _writes.add(_Write(_WriteKind.set, documentReference.path, data as Map<Object?, Object?>));
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('LocalFirestore transaction: ${invocation.memberName}');
}
