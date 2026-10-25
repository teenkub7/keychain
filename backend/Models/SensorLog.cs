using System;

namespace SmartKeychainApi.Models
{
    public class SensorLog
    {
        public int Id { get; set; }
        public string Username { get; set; } = string.Empty;
        public double HeartRate { get; set; } // อัตราการเต้นหัวใจ (BPM)
        public double SpO2 { get; set; } // ออกซิเจนในเลือด (%)
        public double Temperature { get; set; } // อุณหภูมิโดยรอบ (°C)
        public double Humidity { get; set; } // ความชื้นในอากาศ (%)
        public string MeasurementType { get; set; } = "Manual_Spot"; // "Manual_Spot" หรือ "Auto_30s"
        public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
    }

    public class CreateSensorLogRequest
    {
        public string Username { get; set; } = string.Empty;
        public double HeartRate { get; set; }
        public double SpO2 { get; set; }
        public double Temperature { get; set; }
        public double Humidity { get; set; }
        public string MeasurementType { get; set; } = "Manual_Spot";
    }
}
