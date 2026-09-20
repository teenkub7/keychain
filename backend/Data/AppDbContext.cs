using Microsoft.EntityFrameworkCore;
using SmartKeychainApi.Models;

namespace SmartKeychainApi.Data
{
    // 🟢 ต้องสืบทอดจาก DbContext
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
        {
        }

        public DbSet<User> Users { get; set; }
    }
}