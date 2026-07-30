class LocationModel {
  final int id;
  final String cityName;

  LocationModel({
    required this.id,
    required this.cityName,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'],
      cityName: json['city_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'city_name': cityName,
    };
  }
}