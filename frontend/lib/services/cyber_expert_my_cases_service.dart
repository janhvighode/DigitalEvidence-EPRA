import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_constants.dart';

class CyberExpertMyCasesService {
  Future<Map<String, dynamic>> getMyCases({
    String search = '',
    String status = '',
    String priority = '',
    int page = 1,
    int limit = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      throw Exception('Access token not found');
    }

    final queryParameters = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (search.trim().isNotEmpty) {
      queryParameters['search'] = search.trim();
    }

    if (status.isNotEmpty) {
      queryParameters['status'] = status;
    }

    if (priority.isNotEmpty) {
      queryParameters['priority'] = priority;
    }

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}/cyber-expert/my-cases',
    ).replace(
      queryParameters: queryParameters,
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode >= 200 &&
        response.statusCode < 300) {
      return jsonDecode(response.body)
          as Map<String, dynamic>;
    }

    throw Exception(
      'Failed to load cases (${response.statusCode})',
    );
  }
}