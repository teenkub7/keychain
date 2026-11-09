import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

// Model เรียบง่ายเก็บเฉพาะเวลาและกิจกรรม
class TodoItem {
  String task;
  String time;

  TodoItem({
    required this.task,
    required this.time,
  });

  factory TodoItem.fromString(String raw) {
    String trimmed = raw.trim();

    // กำจัด prefix ซ้ำซ้อนที่อาจติดมาจากการซิงก์ (เช่น T:ADD:, T:, ADD:)
    while (trimmed.startsWith('T:ADD:') ||
        trimmed.startsWith('T:') ||
        trimmed.startsWith('ADD:')) {
      if (trimmed.startsWith('T:ADD:')) {
        trimmed = trimmed.substring(6).trim();
      } else if (trimmed.startsWith('T:')) {
        trimmed = trimmed.substring(2).trim();
      } else if (trimmed.startsWith('ADD:')) {
        trimmed = trimmed.substring(4).trim();
      }
    }

    RegExp timeReg = RegExp(r'^(\d{1,2}:\d{2})\s*(.*)$');
    var match = timeReg.firstMatch(trimmed);

    if (match != null) {
      return TodoItem(
        time: match.group(1) ?? '',
        task: match.group(2) ?? '',
      );
    } else {
      return TodoItem(
        time: '',
        task: trimmed,
      );
    }
  }

  String toFormattedString() {
    return time.isNotEmpty ? '$time $task' : task;
  }
}

class HomeScreen extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onConnectPressed;
  final String username;
  final Map<String, dynamic>? userData;
  final Function(int index)? onNavigateToTab;
  final Function(String payload)? onSendBleData;
  final Function(String data)? onSendTodoList;
  final Function(String newRoutineData)? onUpdateDatabaseRoutine;
  final Stream<String>? bleNotifyStream;

  const HomeScreen({
    super.key,
    required this.isConnected,
    required this.onConnectPressed,
    this.username = 'User',
    this.userData,
    this.onNavigateToTab,
    this.onSendBleData,
    this.onSendTodoList,
    this.onUpdateDatabaseRoutine,
    this.bleNotifyStream,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  List<TodoItem> _todoItems = [];
  StreamSubscription<String>? _bleSubscription;

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
    _setupBleListener();

    // ซิงก์ทันทีถ้าต่อบลูทูธอยู่แล้วตั้งแต่เปิดหน้า
    if (widget.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncTodoListToESP32();
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userData?['routineData'] != widget.userData?['routineData']) {
      _parseRoutineData();
    }
    if (oldWidget.bleNotifyStream != widget.bleNotifyStream) {
      _setupBleListener();
    }

    // 🟢 ถ้าเพิ่งเชื่อมต่อ BLE สำเร็จ ให้ดึงข้อมูลในแอปส่งไป ESP32 ทันที!
    if (!oldWidget.isConnected && widget.isConnected) {
      _syncTodoListToESP32();
    }
  }

  void _setupBleListener() {
    _bleSubscription?.cancel();
    _bleSubscription = widget.bleNotifyStream?.listen((data) {
      final trimmed = data.trim();
      if (trimmed.startsWith("DEL_T:")) {
        String deletedText = trimmed.substring(6).trim();
        print(">> 📥 ESP32 Auto-Deleted Item: $deletedText");

        // 🔔 เด้งแจ้งเตือนบนมือถือทันทีเมื่อพวงกุญแจร้อง Buzzer ครบกำหนดเวลา!
        NotificationService.instance.showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: '📋 ถึงเวลาทำกิจกรรมแล้ว! (Smart Keychain)',
          body: deletedText,
          payload: 'TODO_DEL_T',
        );

        setState(() {
          _todoItems.removeWhere((item) {
            String fullText = item.toFormattedString();
            return fullText == deletedText || item.task == deletedText;
          });
        });

        _saveRoutineToDatabaseAndSync();
      }
    });
  }

  void _parseRoutineData() {
    final routineData = widget.userData?['routineData']?.toString() ?? '';
    if (routineData.isNotEmpty && routineData != 'CLEAR') {
      _todoItems = routineData
          .split('\n')
          .where((item) => item.trim().isNotEmpty)
          .map((item) => TodoItem.fromString(item))
          .toList();

      // หากข้อมูลเดิมใน Database มี prefix ติดมา ให้บันทึกข้อมูลคลีนทับลง Database ทันที
      if (routineData.contains('T:ADD:') || routineData.startsWith('T:')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _saveRoutineToDatabaseAndSync();
        });
      }

      // ซิงค์การแจ้งเตือนลงเครื่องมือถือ (Local Scheduled Notification)
      for (int i = 0; i < _todoItems.length; i++) {
        final item = _todoItems[i];
        if (item.time.isNotEmpty) {
          NotificationService.instance.scheduleTodoReminder(
            id: 3000 + i,
            task: item.task,
            timeStr: item.time,
          );
        }
      }
    } else {
      _todoItems = [];
    }
  }

  // อัปเดต Database โดยถ้าไม่มีรายการเหลือ จะเซฟเป็นค่าว่าง "" (ไม่ใช้คำว่า CLEAR)
  void _saveRoutineToDatabaseAndSync() {
    String formattedString = _todoItems.map((e) => e.toFormattedString()).join('\n');
    widget.onUpdateDatabaseRoutine?.call(formattedString);
    _syncTodoListToESP32();
  }

  Future<void> _syncTodoListToESP32() async {
    if (!widget.isConnected) return;

    // 1. ส่งเวลาปัจจุบันไปตั้งค่านาฬิกาให้ ESP32
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    widget.onSendBleData?.call("TIME:$timeStr");
    await Future.delayed(const Duration(milliseconds: 100));

    // 2. ล้างรายการเดิมบน ESP32
    widget.onSendTodoList?.call('T:CLEAR');
    await Future.delayed(const Duration(milliseconds: 100));

    // 3. ทยอยส่งรายการทั้งหมดไปยัง ESP32
    for (var item in _todoItems) {
      widget.onSendTodoList?.call('T:ADD:${item.toFormattedString()}');
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _addTodoItem(String task, String time) {
    if (task.trim().isEmpty) return;
    final newItem = TodoItem(task: task.trim(), time: time.trim());
    setState(() {
      _todoItems.add(newItem);
    });
    _saveRoutineToDatabaseAndSync();
  }

  void _deleteTodoItem(int index) {
    setState(() {
      _todoItems.removeAt(index);
    });
    _saveRoutineToDatabaseAndSync();
  }

  void _showRoutinePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RoutineBottomSheetModal(
        todoItems: _todoItems,
        onAdd: _addTodoItem,
        onDelete: _deleteTodoItem,
      ),
    );
  }

  @override
  void dispose() {
    _bleSubscription?.cancel();
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
                  _buildGreetingHeader(),
                  const SizedBox(height: 20),
                  _buildKeychainHeroCard(isOnline, batteryText, signalText, tempText),
                  const SizedBox(height: 20),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Smart Keychain',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14293D),
                ),
              ),
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
              const SizedBox(width: 12),
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

          widget.isConnected
              ? Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: widget.onConnectPressed,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_connected_rounded,
                            size: 18,
                            color: Color(0xFF15803D),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'เชื่อมต่อแล้ว',
                            style: TextStyle(
                              fontSize: 13,
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
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 11),
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                scale: _pulseScale,
                                child: const Icon(
                                  Icons.bluetooth_searching_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'สแกนบลูทูธ (BLE)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
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
    );
  }

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

  Widget _buildDailyRoutineCard() {
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
                          : '(${_todoItems.length} รายการที่ตั้งไว้) • แตะเพื่อเปิดดู',
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

class _RoutineBottomSheetModal extends StatefulWidget {
  final List<TodoItem> todoItems;
  final Function(String task, String time) onAdd;
  final Function(int index) onDelete;

  const _RoutineBottomSheetModal({
    required this.todoItems,
    required this.onAdd,
    required this.onDelete,
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

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'รายการทั้งหมด (${items.length})',
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFFE8D6),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (item.time.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4EC),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item.time,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF6B00),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Text(
                                item.task,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: Color(0xFF14293D),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.grey.shade400),
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

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Center(
              child: Text(
                '${items.length} รายการทั้งหมด',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}