class ApiConstants {
  // Change this to your FastAPI server URL
  static const String baseUrl = "http://YOUR_BACKEND_IP:8000";

  static const String roles = "$baseUrl/roles/";
  static const String locations = "$baseUrl/locations/";
  static const String register = "$baseUrl/register/";

  static String cyberCells(int cityId) =>
      "$baseUrl/cyber-cells/$cityId";
}