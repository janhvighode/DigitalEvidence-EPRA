import 'dart:convert';
import 'api_service.dart';

class RegisterService {
  final ApiService _apiService = ApiService();

  Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String email,
    required String phoneNumber,
    required int roleId,
    required int cityId,
    required int cyberCellId,
  }) async {
    final response = await _apiService.registerUser({
      "full_name": fullName,
      "email": email,
      "phone_number": phoneNumber,
      "requested_role_id": roleId,
      "city_id": cityId,
      "cyber_cell_id": cyberCellId,
    });

    return jsonDecode(response.body);
  }
}
