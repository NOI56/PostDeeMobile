import 'package:firebase_core/firebase_core.dart';

/// Firebase project settings for the PostDee browser app.
///
/// Firebase web configuration values identify the public app; they are not
/// service-account credentials or server secrets.
class PostDeeFirebaseWebOptions {
  const PostDeeFirebaseWebOptions._();

  static const currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyD4Tavx7UVoQpz8Cqk4e_SIGxYkY4V2AGg',
    appId: '1:121898224944:web:010758af2b5bfeeaa6ccf5',
    messagingSenderId: '121898224944',
    projectId: 'postdee-3c163',
    authDomain: 'postdee-3c163.firebaseapp.com',
    storageBucket: 'postdee-3c163.firebasestorage.app',
  );
}
