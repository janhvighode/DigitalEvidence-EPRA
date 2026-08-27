import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_constants.dart';

class LoginService {
  Future<Map<String, dynamic>> loginUser({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.login),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "username": username,
        "password": password,
      }),
    );

    final Map<String, dynamic> data =
        jsonDecode(response.body);

    if (response.statusCode >= 200 &&
        response.statusCode < 300) {
      final String? accessToken =
          data["access_token"]?.toString();

      if (accessToken != null && accessToken.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(
          "access_token",
          accessToken,
        );

        await prefs.setString(
          "username",
          username,
        );

        // Save role_id if backend sends it in response
        if (data["role_id"] != null) {
          await prefs.setInt(
            "role_id",
            int.tryParse(
                  data["role_id"].toString(),
                ) ??
                0,
          );
        }
      }
    }

    return data;
  }
}