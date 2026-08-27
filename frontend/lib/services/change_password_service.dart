import 'dart:convert';
import 'package:http/http.dart' as http;

class ChangePasswordService {
  static const String baseUrl = "https://digitalevidence-epra.onrender.com";

  Future<Map<String, dynamic>> changePassword({
    required String username,
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await http.put(
      Uri.parse("$baseUrl/change-password/"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "username": username,
        "old_password": oldPassword,
        "new_password": newPassword,
        "confirm_password": confirmPassword,
      }),
    );

    print("CHANGE PASSWORD STATUS: ${response.statusCode}");
    print("CHANGE PASSWORD BODY: ${response.body}");

    if (response.body.isEmpty) {
      return {
        "success": false,
        "message":
            "Backend returned an empty response. Status: ${response.statusCode}",
      };
    }

    try {
      return jsonDecode(response.body);
    } catch (e) {
      return {
        "success": false,
        "message":
            "Invalid response from server. Status: ${response.statusCode}",
      };
    }
  }
}