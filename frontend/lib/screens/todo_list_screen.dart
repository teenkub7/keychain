import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TodoItem {
  String task;
  String time;
  bool isDone;

  TodoItem({required this.task, this.time = '', this.isDone = false});

  factory TodoItem.fromString(String text) {
    bool done = text.startsWith("[x] ");
    String cleanText = done ? text.substring(4) : text;

    if (cleanText.contains(" - ")) {
      var parts = cleanText.split(" - ");
      return TodoItem(time: parts[0], task: parts.sublist(1).join(" - "), isDone: done);
    }
    return TodoItem(task: cleanText, isDone: done);
  }

  String toFormattedString() {
    String donePrefix = isDone ? "[x] " : "";
    if (time.isNotEmpty) {
      return "$donePrefix$time - $task";
    }
    return "$donePrefix$task";
  }
}

class TodoListScreen extends StatefulWidget {
  final String username;
  final String? initialTodoList;
  final Function(String) onSendTodoList;

  const TodoListScreen({
    super.key,
    required this.username,
    this.initialTodoList,
    required this.onSendTodoList,
  });

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  List<TodoItem> _todoList = [];
  String _selectedFilter = 'all'; // 'all', 'pending', 'done'
  bool _isSaving = false;

  final List<String> _quickTimeChips = ['08:00', '10:00', '12:00', '14:00', '18:00', '20:00'];

  @override
  void initState() {
    super.initState();
    if (widget.initialTodoList != null && widget.initialTodoList!.trim().isNotEmpty) {
      _todoList = widget.initialTodoList!
          .split("\n")
          .where((item) => item.trim().isNotEmpty)
          .map((item) => TodoItem.fromString(item))
          .toList();
    } else {
      _todoList = [];
    }
  }

  @override
  void dispose() {
    _taskController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  // ฟังก์ชันเลือกเวลาด้วย TimePicker
  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFFFF6B00),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Color(0xFF14293D),
              ),
            ),
            child: child!,
          ),
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

  // ฟังก์ชันแสดง SnackBar มินิมอล
  void _showCustomSnackBar({required String message, required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
        content: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.close_rounded : Icons.check_rounded,
                    color: isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF14293D),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ฟังก์ชันเพิ่ม To-Do
  void _addTodo() {
    final taskText = _taskController.text.trim();
    if (taskText.isEmpty) {
      _showCustomSnackBar(message: 'กรุณากรอกสิ่งที่ต้องทำ', isError: true);
      return;
    }

    setState(() {
      _todoList.add(TodoItem(
        task: taskText,
        time: _timeController.text.trim(),
      ));
      _taskController.clear();
      _timeController.clear();
    });

    _saveAndSyncToKeychain(showFeedback: false);
  }

  // ฟังก์ชันบันทึกลง Database และส่ง BLE ไปยังพวงกุญแจ
  Future<void> _saveAndSyncToKeychain({bool showFeedback = false}) async {
    setState(() {
      _isSaving = true;
    });

    String formattedData = _todoList.map((e) => e.toFormattedString()).join("\n");

    // 1. ส่งอัปเดตลง Database ผ่าน C# API
    try {
      final url = Uri.parse('http://localhost:5000/api/User/update-data');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': widget.username,
          'routineData': formattedData,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("อัปเดต DB MySQL สำเร็จ");
      }
    } catch (e) {
      debugPrint("Network Error updating DB: $e");
    }

    // 2. ส่งข้อมูลไป ESP32
    if (_todoList.isEmpty) {
      widget.onSendTodoList("CLEAR");
    } else {
      widget.onSendTodoList(formattedData);
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
      if (showFeedback) {
        _showCustomSnackBar(message: '✨ อัปเดตตารางเวลาไปยังพวงกุญแจเรียบร้อยแล้ว!', isError: false);
      }
    }
  }

  void _deleteItem(int index) {
    setState(() {
      _todoList.removeAt(index);
    });
    _saveAndSyncToKeychain(showFeedback: false);
  }

  void _clearDoneItems() {
    setState(() {
      _todoList.removeWhere((item) => item.isDone);
    });
    _saveAndSyncToKeychain(showFeedback: false);
    _showCustomSnackBar(message: 'ลบรายการที่ทำเสร็จแล้วเรียบร้อย', isError: false);
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _todoList.length;
    final doneCount = _todoList.where((item) => item.isDone).length;
    final pendingCount = totalCount - doneCount;
    final double progress = totalCount == 0 ? 0.0 : (doneCount / totalCount);

    // กรองรายการตาม Tab Filter
    final filteredList = _todoList.where((item) {
      if (_selectedFilter == 'pending') return !item.isDone;
      if (_selectedFilter == 'done') return item.isDone;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. หัวข้อหน้า
                  _buildHeader(),
                  const SizedBox(height: 18),

                  // 2. การ์ดสรุปความคืบหน้า (Progress Card)
                  _buildProgressCard(totalCount, doneCount, pendingCount, progress),
                  const SizedBox(height: 18),

                  // 3. กล่องเพิ่มกิจกรรมใหม่ (Add Task Card)
                  _buildAddTaskCard(),
                  const SizedBox(height: 22),

                  // 4. แถบตัวกรอง (Filter Chips) & ปุ่มล้างรายการ
                  _buildFilterBar(totalCount, doneCount),
                  const SizedBox(height: 12),

                  // 5. รายการ To-Do Cards
                  if (filteredList.isEmpty)
                    _buildEmptyState()
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredList.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filteredList[index];
                        final realIndex = _todoList.indexOf(item);
                        return _buildTodoCard(item, realIndex);
                      },
                    ),

                  const SizedBox(height: 24),

                  // 6. ปุ่มอัปเดตไปยังหน้าจอพวงกุญแจ
                  _buildSyncButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. หัวข้อหน้า
  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ตารางเวลากิจกรรม ⏰',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF14293D),
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'จัดตารางสิ่งที่ต้องทำ เพื่อแสดงผลบนหน้าจอพวงกุญแจแบบเรียลไทม์',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // 2. การ์ดสรุปความคืบหน้า (Redesigned Circular Gauge & Minimal Stats)
  Widget _buildProgressCard(int total, int done, int pending, double progress) {
    final bool isAllDone = total > 0 && progress >= 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          // ด้านซ้าย: ข้อมูลและสถานะ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4EC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.insights_rounded,
                        color: Color(0xFFFF6B00),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'ความคืบหน้าวันนี้',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF14293D),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  total == 0
                      ? 'ยังไม่มีรายการกิจกรรม'
                      : (isAllDone
                          ? 'ทำครบทุกรายการแล้ว'
                          : 'ทำเสร็จแล้ว $done จาก $total รายการ'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),

                // ชิปสถานะ 3 ช่องแบบกระชับ มินิมอล
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildStatPill(
                      label: 'ทั้งหมด',
                      value: '$total',
                      color: const Color(0xFF14293D),
                      bgColor: const Color(0xFFF1F5F9),
                    ),
                    _buildStatPill(
                      label: 'รอทำ',
                      value: '$pending',
                      color: const Color(0xFFFF6B00),
                      bgColor: const Color(0xFFFFF4EC),
                    ),
                    _buildStatPill(
                      label: 'เสร็จแล้ว',
                      value: '$done',
                      color: const Color(0xFF16A34A),
                      bgColor: const Color(0xFFDCFCE7),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ด้านขวา: Circular Progress Ring สไตล์ Apple / Dashboard พร้อมอนิเมชันสมูท
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: total == 0 ? 0.0 : progress),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, animatedProgress, child) {
                final bool isFull = total > 0 && animatedProgress >= 0.999;
                final Color ringColor = isFull ? const Color(0xFF10B981) : const Color(0xFFFF6B00);
                final int percentInt = (animatedProgress * 100).round();

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: animatedProgress,
                        strokeWidth: 6.5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                      ),
                    ),
                    Text(
                      '$percentInt%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: ringColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // 3. กล่องเพิ่มกิจกรรมใหม่ (Add Task Card)
  Widget _buildAddTaskCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เพิ่มกิจกรรมใหม่',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF14293D),
            ),
          ),
          const SizedBox(height: 12),

          // แถวป้อนข้อมูล: เวลา + สิ่งที่ต้องทำ
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ช่องเวลาพร้อมปุ่มนาฬิกา
              SizedBox(
                width: 125,
                child: TextField(
                  controller: _timeController,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'เวลา',
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFFF6B00)),
                      onPressed: _pickTime,
                      tooltip: 'เลือกเวลา',
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ช่องข้อความกิจกรรม
              Expanded(
                child: TextField(
                  controller: _taskController,
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _addTodo(),
                  decoration: InputDecoration(
                    hintText: 'สิ่งที่ต้องทำ เช่น อ่านหนังสือ...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ปุ่มกดเพิ่ม (+)
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B00), Color(0xFFFF8533)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B00).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                  onPressed: _addTodo,
                  tooltip: 'เพิ่มกิจกรรม',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ชิปเวลาด่วน
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                Text(
                  'เวลาด่วน: ',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                ..._quickTimeChips.map((chipTime) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _timeController.text = chipTime;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _timeController.text == chipTime
                              ? const Color(0xFFFF6B00)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          chipTime,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _timeController.text == chipTime
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4. แถบตัวกรอง & ปุ่มล้าง
  Widget _buildFilterBar(int total, int done) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _buildFilterTab(id: 'all', label: 'ทั้งหมด ($total)'),
            const SizedBox(width: 6),
            _buildFilterTab(id: 'pending', label: 'รอทำ (${total - done})'),
            const SizedBox(width: 6),
            _buildFilterTab(id: 'done', label: 'เสร็จแล้ว ($done)'),
          ],
        ),
        if (done > 0)
          InkWell(
            onTap: _clearDoneItems,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const Row(
                children: [
                  Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 16),
                  SizedBox(width: 4),
                  Text(
                    'ลบที่เสร็จแล้ว',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterTab({required String id, required String label}) {
    final bool isSelected = _selectedFilter == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = id;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF14293D) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // 5. การ์ดรายการ To-Do แต่ละรายการ
  Widget _buildTodoCard(TodoItem item, int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: item.isDone ? const Color(0xFFF1F5F9) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Checkbox สไตล์โมเดิร์น
          InkWell(
            onTap: () {
              setState(() {
                item.isDone = !item.isDone;
              });
              _saveAndSyncToKeychain(showFeedback: false);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: item.isDone ? const Color(0xFFFF6B00) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: item.isDone ? const Color(0xFFFF6B00) : const Color(0xFFCBD5E1),
                  width: 1.5,
                ),
              ),
              child: item.isDone
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                  : null,
            ),
          ),
          const SizedBox(width: 12),

          // รายละเอียด: เวลา + ข้อความ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.time.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isDone ? const Color(0xFFF1F5F9) : const Color(0xFFFFF4EC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 11,
                          color: item.isDone ? const Color(0xFF94A3B8) : const Color(0xFFFF6B00),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.time,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: item.isDone ? const Color(0xFF94A3B8) : const Color(0xFFFF6B00),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  item.task,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: item.isDone ? TextDecoration.lineThrough : TextDecoration.none,
                    color: item.isDone ? const Color(0xFF94A3B8) : const Color(0xFF14293D),
                  ),
                ),
              ],
            ),
          ),

          // ปุ่มลบรายการ
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
            onPressed: () => _deleteItem(index),
            tooltip: 'ลบรายการนี้',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // การ์ดเมื่อไม่มีรายการ
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF4EC),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.checklist_rounded,
              size: 40,
              color: Color(0xFFFF6B00),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'ไม่มีรายการกิจกรรม',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF14293D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedFilter != 'all'
                ? 'ไม่มีรายการในหมวดที่เลือก'
                : 'เริ่มต้นเพิ่มตารางเวลาประจำวัน เพื่อส่งข้อมูลไปแสดงบนหน้าจอพวงกุญแจ',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // 6. ปุ่มอัปเดตไปยังหน้าจอพวงกุญแจ
  Widget _buildSyncButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isSaving ? null : () => _saveAndSyncToKeychain(showFeedback: true),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B00),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          shadowColor: const Color(0xFFFF6B00).withValues(alpha: 0.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSaving)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(Icons.sync_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              _isSaving ? 'กำลังบันทึกและส่งข้อมูล...' : 'อัปเดต To-Do List ไปยังพวงกุญแจ',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}