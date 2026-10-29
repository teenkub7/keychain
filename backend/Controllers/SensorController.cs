using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmartKeychainApi.Data;
using SmartKeychainApi.Models;

namespace SmartKeychainApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SensorController : ControllerBase
    {
        private readonly AppDbContext _context;

        public SensorController(AppDbContext context)
        {
            _context = context;
        }

        // 1. บันทึกค่าเซนเซอร์ใหม่
        [HttpPost("log")]
        public async Task<IActionResult> LogSensorData([FromBody] CreateSensorLogRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Username))
            {
                return BadRequest(new { Message = "Username ต้องไม่เป็นค่าว่าง" });
            }

            var log = new SensorLog
            {
                Username = request.Username,
                HeartRate = request.HeartRate,
                SpO2 = request.SpO2,
                Temperature = request.Temperature,
                Humidity = request.Humidity,
                MeasurementType = string.IsNullOrWhiteSpace(request.MeasurementType) ? "Manual_Spot" : request.MeasurementType,
                RecordedAt = TimeZoneInfo.ConvertTimeFromUtc(
                    DateTime.UtcNow,
                    TimeZoneInfo.FindSystemTimeZoneById("SE Asia Standard Time")
                )
            };

            _context.SensorLogs.Add(log);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                Message = "บันทึกข้อมูลเซนเซอร์สำเร็จ",
                Data = log
            });
        }

        // 2. ดึงค่าเซนเซอร์ล่าสุด
        [HttpGet("latest")]
        public async Task<IActionResult> GetLatest([FromQuery] string username, [FromQuery] string? type)
        {
            if (string.IsNullOrWhiteSpace(username))
            {
                return BadRequest(new { Message = "กรุณาระบุ Username" });
            }

            var query = _context.SensorLogs.AsNoTracking().Where(s => s.Username == username);
            if (!string.IsNullOrWhiteSpace(type))
            {
                query = query.Where(s => s.MeasurementType.ToLower() == type.ToLower());
            }

            var latest = await query.OrderByDescending(s => s.RecordedAt).FirstOrDefaultAsync();
            if (latest == null)
            {
                return Ok(new { HasData = false, Message = "ยังไม่มีข้อมูลที่บันทึกไว้" });
            }

            return Ok(new { HasData = true, Data = latest });
        }

        // 3. ดึงประวัติข้อมูลย้อนหลังสำหรับทำกราฟและตาราง Timeline
        [HttpGet("history")]
        public async Task<IActionResult> GetHistory([FromQuery] string username, [FromQuery] string? type, [FromQuery] int limit = 30)
        {
            if (string.IsNullOrWhiteSpace(username))
            {
                return BadRequest(new { Message = "กรุณาระบุ Username" });
            }

            var query = _context.SensorLogs.AsNoTracking().Where(s => s.Username == username);
            if (!string.IsNullOrWhiteSpace(type))
            {
                query = query.Where(s => s.MeasurementType.ToLower() == type.ToLower());
            }

            var history = await query
                .OrderByDescending(s => s.RecordedAt)
                .Take(limit)
                .ToListAsync();

            // ส่งคืนแบบเรียงจากอดีตไปหาปัจจุบันเพื่อให้พล็อตบนกราฟได้ง่าย
            var chronological = history.OrderBy(s => s.RecordedAt).ToList();

            return Ok(new
            {
                Total = history.Count,
                History = chronological,
                Latest = history.FirstOrDefault()
            });
        }

        // 4. API จำลองสร้างข้อมูลทดสอบ (Demo Simulator) ให้ดูกราฟและสถานะได้ทันที
        [HttpPost("simulate")]
        public async Task<IActionResult> SimulateData([FromBody] SimulateRequest request)
        {
            var username = string.IsNullOrWhiteSpace(request.Username) ? "user1" : request.Username;
            var type = string.IsNullOrWhiteSpace(request.MeasurementType) ? "Auto_30s" : request.MeasurementType;
            var count = request.Count > 0 ? Math.Min(request.Count, 50) : 15;

            var random = new Random();
            var now = DateTime.UtcNow;
            var createdLogs = new System.Collections.Generic.List<SensorLog>();

            for (int i = count - 1; i >= 0; i--)
            {
                DateTime time;
                double hr, spo2, temp, hum;

                if (type == "Auto_30s")
                {
                    time = now.AddSeconds(-30 * i);
                    // อุณหภูมิประมาณ 26.5 - 31.0 °C, ความชื้น 50 - 68%
                    temp = Math.Round(27.0 + (random.NextDouble() * 3.5), 1);
                    hum = Math.Round(52.0 + (random.NextDouble() * 14.0), 1);
                    hr = Math.Round(70.0 + (random.NextDouble() * 15.0), 0);
                    spo2 = Math.Round(97.0 + (random.NextDouble() * 2.5), 0);
                }
                else
                {
                    time = now.AddMinutes(-10 * i);
                    // Spot check: หัวใจ 65 - 95 BPM, SpO2 96 - 99%
                    hr = Math.Round(68.0 + (random.NextDouble() * 26.0), 0);
                    spo2 = Math.Round(95.0 + (random.NextDouble() * 4.5), 0);
                    temp = Math.Round(28.0 + (random.NextDouble() * 2.0), 1);
                    hum = Math.Round(55.0 + (random.NextDouble() * 10.0), 1);
                }

                var log = new SensorLog
                {
                    Username = username,
                    HeartRate = hr,
                    SpO2 = Math.Min(100.0, spo2),
                    Temperature = temp,
                    Humidity = hum,
                    MeasurementType = type,
                    RecordedAt = time
                };
                createdLogs.Add(log);
            }

            _context.SensorLogs.AddRange(createdLogs);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                Message = $"สร้างข้อมูลจำลอง {count} รายการสำหรับ {username} ({type}) เรียบร้อยแล้ว",
                Count = count
            });
        }

        // 5. ล้างประวัติ (สำหรับทดสอบ)
        [HttpDelete("clear")]
        public async Task<IActionResult> ClearData([FromQuery] string username, [FromQuery] string? type)
        {
            if (string.IsNullOrWhiteSpace(username))
            {
                return BadRequest(new { Message = "กรุณาระบุ Username" });
            }

            var query = _context.SensorLogs.Where(s => s.Username == username);
            if (!string.IsNullOrWhiteSpace(type))
            {
                query = query.Where(s => s.MeasurementType.ToLower() == type.ToLower());
            }

            _context.SensorLogs.RemoveRange(query);
            await _context.SaveChangesAsync();

            return Ok(new { Message = "ล้างข้อมูลเซนเซอร์เรียบร้อยแล้ว" });
        }
    }

    public class SimulateRequest
    {
        public string Username { get; set; } = "user1";
        public string MeasurementType { get; set; } = "Auto_30s";
        public int Count { get; set; } = 15;
    }
}
