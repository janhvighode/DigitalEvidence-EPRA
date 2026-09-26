class LocationModel {
  final int id;
  final String cityName;

  LocationModel({required this.id, required this.cityName});

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json["city_id"], // <-- CHANGE HERE
      cityName: json["city_name"],
    );
  }
}
