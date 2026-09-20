using Microsoft.AspNetCore.Mvc;

namespace DeviceApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class DeviceController : ControllerBase
    {
        // เก็บสถานะไฟ LED (จำลองใน Memory)
        private static bool _ledState = false;

        // API สำหรับ ESP32 และ Flutter ดึงสถานะล่าสุด
        [HttpGet("{deviceId}/status")]
        public IActionResult GetStatus(string deviceId)
        {
            return Ok(new
            {
                deviceId = deviceId,
                isOnline = true,
                led = _ledState,
                lastSeen = DateTime.Now.ToString("HH:mm:ss")
            });
        }

        // API สำหรับ Flutter ยิงสั่งงานเปิด-ปิด LED
        [HttpPost("{deviceId}/control")]
        public IActionResult SetControl(string deviceId, [FromBody] ControlRequest request)
        {
            _ledState = request.Led;
            return Ok(new { status = "Success", led = _ledState });
        }
    }

    public class ControlRequest
    {
        public bool Led { get; set; }
    }
}