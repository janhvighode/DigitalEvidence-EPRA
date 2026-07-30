class CyberCellModel {
  final int id;
  final String cyberCellName;

  CyberCellModel({
    required this.id,
    required this.cyberCellName,
  });

  factory CyberCellModel.fromJson(Map<String, dynamic> json) {
    return CyberCellModel(
      id: json['id'],
      cyberCellName: json['cyber_cell_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cyber_cell_name': cyberCellName,
    };
  }
}