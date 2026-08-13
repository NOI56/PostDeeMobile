import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_session.dart';
import 'publish_draft_store.dart';

typedef PublishDraftSupportDirectoryLoader = Future<Directory> Function();

Future<PublishDraftStore?> createPublishDraftStoreForSession({
  PostDeeAuthSessionStore? sessionStore,
  PublishDraftSupportDirectoryLoader? loadSupportDirectory,
}) async {
  final ownerUserId =
      (sessionStore ?? PostDeeAuthSessionStore.instance).session.stableUserId;
  if (ownerUserId == null) return null;

  final supportDirectory = await (loadSupportDirectory ??
      () async => Directory((await getApplicationSupportDirectory()).path))();
  final ownerRootBoundary = Directory(
    _joinAll([supportDirectory.path, 'publish-drafts', 'v1']),
  );
  final ownerDirectory = Directory(
    _joinAll([ownerRootBoundary.path, _encodePathSegment(ownerUserId)]),
  );
  return FilePublishDraftStore(
    rootDirectory: ownerDirectory,
    ownerRootBoundary: ownerRootBoundary,
    ownerUserId: ownerUserId,
  );
}

String _encodePathSegment(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String _joinAll(List<String> parts) => parts.join(Platform.pathSeparator);
