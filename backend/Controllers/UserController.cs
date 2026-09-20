using Microsoft.AspNetCore.Mvc;
using SmartKeychainApi.Data;
using SmartKeychainApi.Models;

namespace SmartKeychainApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UserController : ControllerBase
    {
        private readonly AppDbContext _context;

        public UserController(AppDbContext context)
        {
            _context = context;
        }

        [HttpPost("register")]
        public IActionResult Register([FromBody] RegisterRequest request)
        {
            if (_context.Users.Any(u => u.Username.ToLower() == request.Username.ToLower()))
            {
                return BadRequest(new { Message = "ชื่อผู้ใช้นี้มีอยู่ในระบบแล้ว" });
            }

            var newUser = new User
            {
                Username = request.Username,
                Password = request.Password,
                RoutineData = "",
                ImageData = "",
                QrData = ""
            };

            _context.Users.Add(newUser);
            _context.SaveChanges(); 

            return Ok(new { Message = "สมัครสมาชิกสำเร็จ", UserId = newUser.Username });
        }

        [HttpPost("login")]
        public IActionResult Login([FromBody] LoginRequest request)
        {
            var user = _context.Users.FirstOrDefault(u => u.Username == request.Username && u.Password == request.Password);

            if (user == null)
            {
                return Unauthorized(new { Message = "Username หรือ Password ไม่ถูกต้อง" });
            }

            return Ok(new
            {
                UserId = user.Username,
                RoutineData = user.RoutineData ?? "",
                ImageData = user.ImageData ?? "",
                QrData = user.QrData ?? ""
            });
        }

        [HttpPost("update-data")]
        public IActionResult UpdateData([FromBody] UpdateDataRequest request)
        {
            var user = _context.Users.FirstOrDefault(u => u.Username == request.Username);
            if (user == null)
            {
                return NotFound(new { Message = "ไม่พบผู้ใช้" });
            }

            if (request.RoutineData != null) user.RoutineData = request.RoutineData;
            if (request.ImageData != null) user.ImageData = request.ImageData;
            if (request.QrData != null) user.QrData = request.QrData;

            _context.SaveChanges(); 

            return Ok(new { Message = "อัปเดตข้อมูลสำเร็จ" });
        }
    }
}