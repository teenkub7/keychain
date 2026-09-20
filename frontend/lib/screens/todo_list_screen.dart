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

  @override
  void initState() {
    super.initState();
    // 🟢 แก้ไขจุดที่ 1: ถ้า initialTodoList เป็นค่าว่าง หรือ null ให้เอาเป็น List ว่าง ไม่สร้างค่า Dummy Data
    if (widget.initialTodoList != null) {
      if (widget.initialTodoList!.trim().isNotEmpty) {
        _todoList = widget.initialTodoList!
            .split("\n")
            .where((item) => item.trim().isNotEmpty)
            .map((item) => TodoItem.fromString(item))
            .toList();
      } else {
        _todoList = [];
      }
    } else {
      _todoList = []; // 🟢 เอา Dummy Data ออกเพื่อไม่ให้ข้อมูลเก่ากลับมา
    }
  }

  void _addTodo() {
    if (_taskController.text.isNotEmpty) {
      setState(() {
        _todoList.add(TodoItem(
          task: _taskController.text.trim(),
          time: _timeController.text.trim(),
        ));
        _taskController.clear();
        _timeController.clear();
      });
      _saveAndSyncToKeychain(); // อัปเดตทันทีเมื่อเพิ่ม
    }
  }

  // 🟢 ฟังก์ชันส่วนกลางสำหรับสั่ง Save ลง DB และส่ง BLE ไป ESP32
  Future<void> _saveAndSyncToKeychain() async {
    String formattedData = _todoList.map((e) => e.toFormattedString()).join("\n");

    // 1. ส่งอัปเดตลง Database
    try {
      final url = Uri.parse('http://172.20.10.4:5000/api/User/update-data');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': widget.username,
          'routineData': formattedData, // ถ้าลบหมด ตัวนี้จะเป็น String ว่าง ""
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("อัปเดต DB สำเร็จ");
      }
    } catch (e) {
      debugPrint("Network Error: $e");
    }

    // 2. ส่งข้อมูลไป ESP32
    if (_todoList.isEmpty) {
      // 🟢 แก้ไขจุดที่ 2: ถ้าไม่มีรายการเหลือเลย ให้ส่ง "CLEAR" ไปล้างจอ ESP32
      widget.onSendTodoList("CLEAR");
    } else {
      widget.onSendTodoList(formattedData);
    }
  }

  // 🟢 ลบรายการทีละอัน
  void _deleteItem(int index) {
    setState(() {
      _todoList.removeAt(index);
    });
    _saveAndSyncToKeychain(); // ลบแล้วสั่งบันทึก + ส่ง BLE ทันที
  }

  // 🟢 ลบรายการที่ทำเสร็จแล้ว
  void _clearDoneItems() {
    setState(() {
      _todoList.removeWhere((item) => item.isDone);
    });
    _saveAndSyncToKeychain(); // ลบแล้วสั่งบันทึก + ส่ง BLE ทันที
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _timeController,
                  decoration: const InputDecoration(
                    labelText: 'เวลา',
                    hintText: '08:00',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _taskController,
                  decoration: const InputDecoration(
                    labelText: 'สิ่งที่จะต้องทำ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.deepPurple, size: 38),
                onPressed: _addTodo,
              )
            ],
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'รายการทั้งหมด (${_todoList.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_todoList.any((e) => e.isDone))
                TextButton.icon(
                  onPressed: _clearDoneItems,
                  icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                  label: const Text('ลบรายการที่เสร็จแล้ว', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _todoList.isEmpty
                ? const Center(child: Text("ไม่มีรายการ To-Do", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _todoList.length,
                    itemBuilder: (context, index) {
                      final item = _todoList[index];
                      return Card(
                        elevation: 2,
                        child: ListTile(
                          leading: Checkbox(
                            activeColor: Colors.deepPurple,
                            value: item.isDone,
                            onChanged: (bool? value) {
                              setState(() {
                                item.isDone = value ?? false;
                              });
                              _saveAndSyncToKeychain();
                            },
                          ),
                          title: Text(
                            item.time.isNotEmpty ? "${item.time} - ${item.task}" : item.task,
                            style: TextStyle(
                              decoration: item.isDone ? TextDecoration.lineThrough : TextDecoration.none,
                              color: item.isDone ? Colors.grey : Colors.black,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => _deleteItem(index), // 🟢 เรียกใช้ฟังก์ชันลบที่ซิงค์ข้อมูล
                          ),
                        ),
                      );
                    },
                  ),
          ),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              onPressed: () async {
                await _saveAndSyncToKeychain();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('อัปเดต To-Do List เรียบร้อย!')),
                  );
                }
              },
              icon: const Icon(Icons.send, color: Colors.white),
              label: const Text(
                'อัปเดต To-Do List ไปพวงกุญแจ',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}