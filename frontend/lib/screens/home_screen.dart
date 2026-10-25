import 'package:flutter/material.dart';
import 'todo_list_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onConnectPressed;
  final String username;
  final Map<String, dynamic>? userData;
  final Function(int index)? onNavigateToTab;
  final Function(String payload)? onSendBleData;
  final Function(String data)? onSendTodoList;

  const HomeScreen({
    super.key,
    required this.isConnected,
    required this.onConnectPressed,
    this.username = 'User',
    this.userData,
    this.onNavigateToTab,
    this.onSendBleData,
    this.onSendTodoList,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  List<TodoItem> _todoItems = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.94, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _parseRoutineData();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userData?['routineData'] != widget.userData?['routineData']) {
      _parseRoutineData();
    }
  }

  void _parseRoutineData() {
    final routineData = widget.userData?['routineData']?.toString() ?? '';
    if (routineData.isNotEmpty && routineData != 'CLEAR') {
      _todoItems = routineData
          .split('\n')
          .where((item) => item.trim().isNotEmpty)
          .map((item) => TodoItem.fromString(item))
          .toList();
    } else {
      _todoItems = [];
    }
  }

  void _toggleTodoItem(int index) {
    setState(() {
      _todoItems[index].isDone = !_todoItems[index].isDone;
    });

    final formatted = _todoItems.map((item) => item.toFormattedString()).join('\n');
    widget.onSendTodoList?.call(formatted);
  }

  void _addTodoItem(String task, String time) {
    if (task.trim().isEmpty) return;

    final newItem = TodoItem(task: task.trim(), time: time.trim(), isDone: false);
    setState(() {
      _todoItems.add(newItem);
    });

    final formatted = _todoItems.map((item) => item.toFormattedString()).join('\n');
    widget.onSendTodoList?.call(formatted);
  }

  void _deleteTodoItem(int index) {
    setState(() {
      _todoItems.removeAt(index);
    });

    final formatted = _todoItems.isEmpty
        ? 'CLEAR'
        : _todoItems.map((item) => item.toFormattedString()).join('\n');
    widget.onSendTodoList?.call(formatted);
  }

  // เปิด Popup ตารางกิจกรรมประจำวัน
  void _showRoutinePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RoutineBottomSheetModal(
        todoItems: _todoItems,
        onToggle: (index) {
          _toggleTodoItem(index);
        },
        onAdd: (task, time) {
          _addTodoItem(task, time);
        },
        onDelete: (index) {
          _deleteTodoItem(index);
        },
        onOpenFullManager: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TodoListScreen(
                username: widget.username,
                initialTodoList: widget.userData?['routineData'],
                onSendTodoList: (data) {
                  widget.onSendTodoList?.call(data);
                },
              ),
            ),
          );
          if (mounted) {
            _parseRoutineData();
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnline = widget.isConnected;
    final String batteryText = isOnline ? '85%' : '--';
    final String signalText = isOnline ? '-58 dBm' : '--';
    final String tempText = isOnline ? '28.5 °C' : '--';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Top Greeting Header (ลบปุ่มตั้งค่าออกตามต้องการ)
                  _buildGreetingHeader(),
                  const SizedBox(height: 20),

                  // 2. Virtual Smart Keychain Hero Card (ลบไอคอนออก & ลบบรรทัดที่ 3 ของ 3 ช่องออก)
                  _buildKeychainHeroCard(isOnline, batteryText, signalText, tempText),
                  const SizedBox(height: 20),

                  // 3. ตารางกิจกรรมประจำวันแบบ Popup Card
                  _buildDailyRoutineCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. Header ต้อนรับ (ลบปุ่มตั้งค่าออกแล้ว)
  Widget _buildGreetingHeader() {
    final String displayName = widget.username.isNotEmpty ? widget.username : 'User';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'สวัสดีคุณ $displayName 👋',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF14293D),
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        const Text(
          'ภาพรวมพวงกุญแจอัจฉริยะ & กิจกรรมวันนี้',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // 2. การ์ดพวงกุญแจเสมือนจริง (ลบไอคอนเครื่องออก & ลบบรรทัดที่ 3 ใน 3 การ์ดย่อยออก)
  Widget _buildKeychainHeroCard(
    bool isOnline,
    String batteryText,
    String signalText,
    String tempText,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // แถวหัวการ์ด: ไม่มีไอคอนซ้ำซ้อน มีเฉพาะชื่ออุปกรณ์ + ชิปสถานะ
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Keychain',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isConnected
                          ? 'ฮาร์ดแวร์เชื่อมต่อผ่าน BLE แล้ว'
                          : 'ESP32 BLE & NFC (แตะเพื่อเชื่อมต่อ)',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isConnected
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ชิปสถานะออนไลน์ / ออฟไลน์
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOnline ? const Color(0xFF15803D) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3 แถบวัดข้อมูลสถานะ (แบตเตอรี่, บลูทูธ RSSI, อุณหภูมิ) - มีเฉพาะ 2 บรรทัด (ชื่อ + ค่า) ไม่มีบรรทัดที่ 3
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.battery_charging_full_rounded,
                  iconColor: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  title: 'แบตเตอรี่',
                  value: batteryText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.bluetooth_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  bgColor: const Color(0xFFEFF6FF),
                  title: 'สัญญาณ BLE',
                  value: signalText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.thermostat_rounded,
                  iconColor: const Color(0xFFFF6B00),
                  bgColor: const Color(0xFFFFF4EC),
                  title: 'อุณหภูมิ',
                  value: tempText,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 14),

          // แถวสถานะบลูทูธ & ปุ่มสแกนบลูทูธ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: widget.isConnected
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isConnected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        size: 16,
                        color: widget.isConnected
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.isConnected
                            ? 'เชื่อมต่อพร้อมส่งข้อมูล'
                            : 'ยังไม่ได้เชื่อมต่อบลูทูธ',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: widget.isConnected
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ปุ่มสแกนบลูทูธ
              widget.isConnected
                  ? Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: widget.onConnectPressed,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_connected_rounded,
                                size: 18,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'เชื่อมต่อแล้ว',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: widget.onConnectPressed,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF7A00), Color(0xFFFF4800)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF6B00).withValues(
                                      alpha: 0.22 + (_pulseController.value * 0.22),
                                    ),
                                    blurRadius: 8 + (_pulseController.value * 8),
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ScaleTransition(
                                    scale: _pulseScale,
                                    child: const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    'สแกนบลูทูธ (BLE)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ],
      ),
    );
  }

  // วิดเจ็ตกล่องแสดงข้อมูลตัวเลขย่อย (Metric Box) - มีเฉพาะ 2 บรรทัด (ชื่อ + ค่า) ไม่มีบรรทัดที่ 3
  Widget _buildMetricItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF14293D),
            ),
          ),
        ],
      ),
    );
  }

  // 3. การ์ดตารางกิจกรรมประจำวันแบบ Popup Card (แตะแล้วเปิด Popup ทันที)
  Widget _buildDailyRoutineCard() {
    final completedCount = _todoItems.where((i) => i.isDone).length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: _showRoutinePopup,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.access_time_filled_rounded,
                  color: Color(0xFFFF6B00),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ตารางกิจกรรมประจำวัน',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _todoItems.isEmpty
                          ? 'ยังไม่มีตารางเวลาที่ตั้งไว้ • แตะเพื่อเปิด'
                          : '(${_todoItems.length} รายการ, สำเร็จ $completedCount) • แตะเพื่อเปิดดู',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE5D3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'เปิดดู',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFFFF6B00)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// 📋 POPUP MODAL: ตารางกิจกรรมประจำวัน (Daily Routine Bottom Sheet Popup)
// =========================================================================
class _RoutineBottomSheetModal extends StatefulWidget {
  final List<TodoItem> todoItems;
  final Function(int index) onToggle;
  final Function(String task, String time) onAdd;
  final Function(int index) onDelete;
  final VoidCallback onOpenFullManager;

  const _RoutineBottomSheetModal({
    required this.todoItems,
    required this.onToggle,
    required this.onAdd,
    required this.onDelete,
    required this.onOpenFullManager,
  });

  @override
  State<_RoutineBottomSheetModal> createState() => _RoutineBottomSheetModalState();
}

class _RoutineBottomSheetModalState extends State<_RoutineBottomSheetModal> {
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _taskController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF6B00),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final hour = picked.hour.toString().padLeft(2, '0');
      final minute = picked.minute.toString().padLeft(2, '0');
      setState(() {
        _timeController.text = '$hour:$minute';
      });
    }
  }

  void _submitNewTask() {
    if (_taskController.text.trim().isEmpty) return;
    widget.onAdd(_taskController.text.trim(), _timeController.text.trim());
    _taskController.clear();
    _timeController.clear();
    setState(() => _isAdding = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.todoItems;
    final completedCount = items.where((i) => i.isDone).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
        maxWidth: 580,
      ),
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Drag Handle ด้านบน
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // 2. Header Popup + ปุ่มปิด
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.access_time_filled_rounded,
                    color: Color(0xFFFF6B00),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ตารางกิจกรรมประจำวัน',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF14293D),
                        ),
                      ),
                      Text(
                        'ซิงก์แจ้งเตือนบนพวงกุญแจฮาร์ดแวร์',
                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 3. แถบสรุปความคืบหน้า
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ความคืบหน้า ($completedCount/${items.length})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _isAdding = !_isAdding);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    foregroundColor: const Color(0xFFFF6B00),
                  ),
                  icon: Icon(_isAdding ? Icons.remove_rounded : Icons.add_rounded, size: 16),
                  label: Text(_isAdding ? 'ซ่อนฟอร์ม' : 'เพิ่มกิจกรรม', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),

          // 4. ฟอร์มเพิ่มกิจกรรมใหม่ (ถ้ากดเพิ่ม)
          if (_isAdding)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFE8D6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _taskController,
                    decoration: InputDecoration(
                      hintText: 'ชื่อกิจกรรม เช่น ประชุมทีม, กินยา',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFFFF6B00)),
                                const SizedBox(width: 8),
                                Text(
                                  _timeController.text.isEmpty ? 'เลือกเวลา (เช่น 08:30)' : _timeController.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _timeController.text.isEmpty ? Colors.grey.shade500 : const Color(0xFF14293D),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _submitNewTask,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('บันทึก', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // 5. รายการกิจกรรม ToDo Items
          Flexible(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    child: Center(
                      child: Text(
                        'ยังไม่มีกิจกรรมที่ตั้งไว้\nกดปุ่ม "เพิ่มกิจกรรม" ด้านบนได้เลยครับ',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: item.isDone ? const Color(0xFFF8FAFC) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: item.isDone ? const Color(0xFFE2E8F0) : const Color(0xFFFFE8D6),
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () {
                                widget.onToggle(index);
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  item.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  size: 20,
                                  color: item.isDone ? const Color(0xFF10B981) : const Color(0xFFFF6B00),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (item.time.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4EC),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.time,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF6B00),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                item.task,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: item.isDone ? const Color(0xFF94A3B8) : const Color(0xFF14293D),
                                  decoration: item.isDone ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.grey.shade400),
                              onPressed: () {
                                widget.onDelete(index);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 6. ปุ่มด้านล่าง (จัดการเต็มรูปแบบ)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${items.length} รายการทั้งหมด',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                ),
                TextButton(
                  onPressed: widget.onOpenFullManager,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                  ),
                  child: const Text('จัดการหน้าเต็ม ->', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
