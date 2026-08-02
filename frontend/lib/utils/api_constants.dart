class ApiConstants {
  // Render Backend Base URL
  static const String baseUrl =
      "https://digitalevidence-epra.onrender.com";

  // Registration APIs
  static const String roles = "$baseUrl/roles/";
  static const String locations = "$baseUrl/locations/";
  static const String register = "$baseUrl/register/";

  // Cyber Cell API depends on selected city
  static String cyberCells(int cityId) =>
      "$baseUrl/cyber-cells/$cityId";
}