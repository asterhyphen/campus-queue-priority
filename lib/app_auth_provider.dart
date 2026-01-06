import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

class AppAuthProvider extends ChangeNotifier {
  User? get user => FirebaseAuth.instance.currentUser;
  String? get email => user?.email;
  String? get uid => user?.uid;

  // -----------------------------
  // LOGIN (Email + Password)
  // -----------------------------
  bool _isAllowedEmail(String? email) {
    if (email == null) return false;
    return email.endsWith('@mite.ac.in') || email.endsWith('@asterhyphen.xyz');
  }

  Future<bool> _isBlocked(String email) async {
    final snap = await FirebaseFirestore.instance
        .collection('blockedUsers')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> login(String email, String password) async {
    // Domain restriction
    if (!_isAllowedEmail(email)) {
      throw Exception('Only college emails are allowed to log in.');
    }

    // Block check
    if (await _isBlocked(email)) {
      throw Exception('This account has been blocked. Contact admin.');
    }

    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = cred.user;
    if (user == null) throw Exception('Failed to sign in');

    // Require email verification
    await user.reload();
    if (!user.emailVerified) {
      await FirebaseAuth.instance.signOut();
      throw Exception(
          'Email not verified. Please verify your email before logging in.');
    }

    // Force fresh auth token for Cloud Functions
    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    notifyListeners();
  }

  // -----------------------------
  // REGISTER → Creates Firestore doc using UID
  // -----------------------------
  Future<void> register(String email, String password) async {
    // Domain restriction
    if (!_isAllowedEmail(email)) {
      throw Exception('Only college emails are allowed to register.');
    }

    // Block check
    if (await _isBlocked(email)) {
      throw Exception('This account has been blocked. Contact admin.');
    }

    final cred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);

    final user = cred.user;
    if (user == null) return;

    // Send verification email and sign out to force verification
    try {
      await user.sendEmailVerification();
    } catch (_) {}

    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "role": "student",
      "createdAt": DateTime.now().millisecondsSinceEpoch,
      "email": user.email,
      "emailVerified": false,
    }, SetOptions(merge: true));

    // Sign out so the new user has to verify email before logging in
    await FirebaseAuth.instance.signOut();

    notifyListeners();
  }

  // -----------------------------
  // LOGIN WITH GOOGLE
  // -----------------------------
  Future<void> loginWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      clientId:
          "939511938752-266nokctemq14qe0ph2j3i9v7ttdp3g8.apps.googleusercontent.com",
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return;

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCred =
        await FirebaseAuth.instance.signInWithCredential(credential);

    final user = userCred.user;
    if (user == null) return;

    // Domain restriction for Google accounts
    if (!_isAllowedEmail(user.email)) {
      await FirebaseAuth.instance.signOut();
      throw Exception('Only college emails are allowed to log in.');
    }

    // Block check
    if (await _isBlocked(user.email!)) {
      await FirebaseAuth.instance.signOut();
      throw Exception('This account has been blocked. Contact admin.');
    }

    await user.getIdToken(true);

    // Ensure a user doc exists (UID-based)
    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "role": "student",
      "createdAt": DateTime.now().millisecondsSinceEpoch,
      "email": user.email,
    }, SetOptions(merge: true));

    notifyListeners();
  }

  // Send password reset email
  Future<void> sendPasswordReset(String email) async {
    if (!_isAllowedEmail(email)) {
      throw Exception('Only college emails are allowed.');
    }

    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  // -----------------------------
  // LOGOUT
  // -----------------------------
  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    notifyListeners();
  }
}
