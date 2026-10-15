import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

OAuthCredential? _credential;

// Firebase is only used for shared budgets and the rating popup. On the web
// its SDK download held the first frame for about 1.5s, so main() starts it
// in the background there and Firebase users wait for it here.
Future<void> firebaseInitialization = Future.value();

Future<FirebaseFirestore?> firebaseGetDBInstanceAnonymous() async {
  await firebaseInitialization;
  try {
    await FirebaseAuth.instance.signInAnonymously();
    return FirebaseFirestore.instance;
  } catch (e) {
    print("There was an error with firebase login");
    print(e.toString());
    return null;
  }
}

// returns null if authentication unsuccessful
Future<FirebaseFirestore?> firebaseGetDBInstance() async {
  await firebaseInitialization;
  if (_credential != null) {
    try {
      await FirebaseAuth.instance.signInWithCredential(_credential!);
      updateSettings(
        "currentUserEmail",
        FirebaseAuth.instance.currentUser!.email,
        pagesNeedingRefresh: [],
        updateGlobalState: false,
      );
      return FirebaseFirestore.instance;
    } catch (e) {
      print("There was an error with firebase login");
      print(e.toString());
      print("will retry with a new credential");
      _credential = null;
      googleUser = null;
      return await firebaseGetDBInstance();
    }
  } else {
    try {
      if (googleUser == null) {
        await signInGoogle(silentSignIn: true);
      }
      // GoogleSignInAccount? googleUser = googleUser;

      GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

      _credential = GoogleAuthProvider.credential(
        accessToken: googleAuth?.accessToken,
        idToken: googleAuth?.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(_credential!);
      updateSettings(
          "currentUserEmail", FirebaseAuth.instance.currentUser!.email,
          updateGlobalState: true);
      return FirebaseFirestore.instance;
    } catch (e) {
      print("There was an error with firebase login and possibly google");
      print(e.toString());
      return null;
    }
  }
}
