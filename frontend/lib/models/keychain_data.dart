class RoutineModel {
  final String id;
  final String title;
  final String time; // รูปแบบ "HH:mm" เช่น "08:00"
  final List<String> repeatDays; // ["MON", "TUE", ...]
  final int vibratePattern; // 1 = Short, 2 = Long, 3 = Pulse
  final bool isEnabled;

  RoutineModel({
    required this.id,
    required this.title,
    required this.time,
    required this.repeatDays,
    this.vibratePattern = 1,
    this.isEnabled = true,
  });
}

class DeviceStatusModel {
  final bool isConnected;
  final int batteryLevel; // 0-100%
  final double temperature; // องศาเซลเซียส
  final String currentDisplayType; // "IMAGE", "QR", "ROUTINE"

  DeviceStatusModel({
    this.isConnected = false,
    this.batteryLevel = 85,
    this.temperature = 28.5,
    this.currentDisplayType = "QR",
  });
}