import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/api_constants.dart';

class ApiService {
  // GET Roles
  Future<http.Response> getRoles() async {
    return await http.get(
      Uri.parse(ApiConstants.roles),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // GET Cities
  Future<http.Response> getLocations() async {
    return await http.get(
      Uri.parse(ApiConstants.locations),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // GET Cyber Cells
  Future<http.Response> getCyberCells(int cityId) async {
    return await http.get(
      Uri.parse(ApiConstants.cyberCells(cityId)),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }

  // POST Register
  Future<http.Response> registerUser(
      Map<String, dynamic> body) async {
    return await http.post(
      Uri.parse(ApiConstants.register),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );
  }
}