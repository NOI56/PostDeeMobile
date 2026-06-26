import 'package:flutter/foundation.dart';

/// A push notification the app has received (from FCM) and now shows in the
/// in-app notifications list.
@immutable
class PostDeeNotification {
  const PostDeeNotification({
    required this.title,
    required this.body,
    required this.receivedAt,
  });

  final String title;
  final String body;
  final DateTime receivedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostDeeNotification &&
          title == other.title &&
          body == other.body &&
          receivedAt == other.receivedAt;

  @override
  int get hashCode => Object.hash(title, body, receivedAt);
}

/// In-memory store of received notifications, newest first. The notifications
/// screen listens to this; the push messaging gateway feeds it. Kept in memory
/// only for now — there is no notification history endpoint yet.
class PostDeeNotificationCenter extends ChangeNotifier {
  PostDeeNotificationCenter();

  /// Shared instance used by the running app. Tests should inject their own.
  static final PostDeeNotificationCenter instance = PostDeeNotificationCenter();

  final List<PostDeeNotification> _items = <PostDeeNotification>[];

  List<PostDeeNotification> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  void add(PostDeeNotification notification) {
    _items.insert(0, notification);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) {
      return;
    }

    _items.clear();
    notifyListeners();
  }
}
