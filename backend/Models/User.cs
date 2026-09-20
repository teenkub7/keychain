namespace SmartKeychainApi.Models
{
    public class User
    {
        public int Id { get; set; }
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
        public string RoutineData { get; set; } = "ยังไม่มีตารางเวลา";
        public string ImageData { get; set; } = "default.jpg";
        public string QrData { get; set; } = "https://google.com";
    }

    public class LoginRequest
    {
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }

    public class RegisterRequest
    {
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }

    public class UpdateDataRequest
    {
        public string Username { get; set; } = string.Empty;
        public string? RoutineData { get; set; }
        public string? ImageData { get; set; }
        public string? QrData { get; set; }
    }
}