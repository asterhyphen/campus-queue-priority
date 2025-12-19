import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

class QueueModel {
  final String id;
  final String name;
  final String cashierEmail;

  QueueModel({
    required this.id,
    required this.name,
    required this.cashierEmail,
  });

  factory QueueModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QueueModel(
      id: doc.id,
      name: data['name'] ?? '',
      cashierEmail: data['cashierEmail'] ?? '',
    );
  }
}

class QueueProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<QueueModel> queues = [];
  StreamSubscription? _sub;

  QueueProvider() {
    _listen();
  }

  void _listen() {
    _sub = _db
        .collection('queues')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      queues = snap.docs.map((d) => QueueModel.fromFirestore(d)).toList();
      notifyListeners();
    });
  }

  // Get Functions instance - create fresh each time to ensure auth context
  FirebaseFunctions _getFunctions() {
    // Try without app parameter first - use default app binding
    // This sometimes works better on Android
    return FirebaseFunctions.instanceFor(region: 'us-central1');
  }

  // Strong token refresh to avoid "unauthenticated" errors
  Future<String> _refreshToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    // Reload user to ensure latest auth state
    await user.reload();
    
    // Force fresh token and wait for it
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception('Failed to get auth token');
    }
    
    // Small delay to ensure token is fully propagated
    await Future.delayed(const Duration(milliseconds: 100));
    
    return token;
  }

  // ADMIN — create queue
  Future<void> createQueue(String name, String cashierEmail) async {
    // Wait for auth to be fully ready
    await FirebaseAuth.instance.authStateChanges().first;
    
    // Verify user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    print('DEBUG: User UID: ${user.uid}');
    print('DEBUG: User Email: ${user.email}');
    
    // Refresh token before call - this ensures we have a fresh token
    final token = await _refreshToken();
    print('DEBUG: Got token: ${token.substring(0, 20)}...');
    
    // Wait a bit more to ensure token is fully propagated
    await Future.delayed(const Duration(milliseconds: 200));
    
    // IMPORTANT: Create Functions instance AFTER getting fresh token and waiting
    // This ensures the SDK picks up the current auth state
    // Try without app parameter - sometimes works better on Android
    final functions = _getFunctions();
    
    // Verify auth state is still valid
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User became null after token refresh');
    }
    
    print('DEBUG: Creating callable function...');
    final fn = functions.httpsCallable(
      'createQueue',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 30),
      ),
    );
    
    print('DEBUG: Calling createQueue function with user: ${currentUser.uid}');
    print('DEBUG: Functions instance app: ${functions.app.name}');
    
    // On Android, use direct HTTP call since SDK has issues attaching token
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    
    if (isAndroid) {
      print('DEBUG: Android detected - using direct HTTP call with token');
      return await _callFunctionViaHttp('createQueue', token, {
        'name': name,
        'cashierEmail': cashierEmail,
      });
    }
    
    // On other platforms, try SDK first, then fallback to HTTP
    try {
      final result = await fn.call({
        'name': name,
        'cashierEmail': cashierEmail,
      });
      print('DEBUG: SDK call successful: $result');
    } catch (e, stackTrace) {
      print('DEBUG: SDK call failed: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      
      // Fallback to HTTP
      print('DEBUG: Falling back to direct HTTP call...');
      return await _callFunctionViaHttp('createQueue', token, {
        'name': name,
        'cashierEmail': cashierEmail,
      });
    }
  }
  
  // Helper method for direct HTTP calls
  Future<void> _callFunctionViaHttp(String functionName, String token, Map<String, dynamic> data) async {
    // Get current user UID
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    
    final projectId = 'icqs-project';
    // Use HTTP endpoint for bookToken, callable for others
    final endpoint = functionName == 'bookToken' ? functionName : functionName;
    final url = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/$endpoint'
    );
    
    print('DEBUG: HTTP Calling URL: $url');
    print('DEBUG: Token length: ${token.length}');
    print('DEBUG: User UID: ${user.uid}');
    
    // For HTTP functions (bookToken, createQueue, callNext), send data directly
    // For callable functions, wrap in 'data'
    final httpFunctions = ['bookToken', 'createQueue', 'callNext', 'clearCurrent'];
    final isHttpFunction = httpFunctions.contains(functionName);
    final requestBody = isHttpFunction
        ? {
            ...data,
            'uid': user.uid, // Include UID for prototype
            if (functionName != 'createQueue') 'email': user.email ?? 'unknown', // Include email for non-create functions
          }
        : {
            'data': {
              ...data,
              'uid': user.uid, // Include UID for prototype
            },
          };
    
    print('DEBUG: Request body: ${jsonEncode(requestBody)}');
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(requestBody),
    );
    
    print('DEBUG: HTTP response status: ${response.statusCode}');
    print('DEBUG: HTTP response body: ${response.body}');
    
    if (response.statusCode == 200) {
      print('DEBUG: ✅ Direct HTTP call successful!');
      final responseData = jsonDecode(response.body);
      print('DEBUG: Response data: $responseData');
      return;
    } else {
      // Parse error
      try {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? errorData['error'] ?? response.body;
        throw Exception('HTTP Error: $errorMessage');
      } catch (_) {
        throw Exception('HTTP Error ${response.statusCode}: ${response.body}');
      }
    }
  }

  // STUDENT — book token
  Future<void> bookToken(String queueId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final token = await _refreshToken();
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    
    if (isAndroid) {
      return await _callFunctionViaHttp('bookToken', token, {
        'queueId': queueId,
        'uid': user.uid,
        'email': user.email ?? 'unknown',
      });
    }

    // Try SDK first, then fallback
    try {
      final functions = _getFunctions();
      final fn = functions.httpsCallable('bookToken');
      await fn.call({'queueId': queueId});
    } catch (e) {
      return await _callFunctionViaHttp('bookToken', token, {
        'queueId': queueId,
        'uid': user.uid,
        'email': user.email ?? 'unknown',
      });
    }
  }

  // CASHIER — call next
  Future<void> callNext(String queueId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final token = await _refreshToken();
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    
    if (isAndroid) {
      return await _callFunctionViaHttp('callNext', token, {
        'queueId': queueId,
        'uid': user.uid,
        'email': user.email ?? 'unknown',
      });
    }

    // Try SDK first, then fallback
    try {
      final functions = _getFunctions();
      final fn = functions.httpsCallable('callNext');
      await fn.call({'queueId': queueId});
    } catch (e) {
      return await _callFunctionViaHttp('callNext', token, {
        'queueId': queueId,
        'uid': user.uid,
        'email': user.email ?? 'unknown',
      });
    }
  }

  // CASHIER — clear current
  Future<void> clearCurrent(String queueId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final token = await _refreshToken();
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    
    if (isAndroid) {
      return await _callFunctionViaHttp('clearCurrent', token, {
        'queueId': queueId,
        'email': user.email ?? 'unknown',
      });
    }

    // Try SDK first, then fallback
    try {
      final functions = _getFunctions();
      final fn = functions.httpsCallable('clearCurrent');
      await fn.call({'queueId': queueId});
    } catch (e) {
      return await _callFunctionViaHttp('clearCurrent', token, {
        'queueId': queueId,
        'email': user.email ?? 'unknown',
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
