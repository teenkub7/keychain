import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isNfcAvailable = false;
  PermissionStatus _bluetoothStatus = PermissionStatus.denied;
  PermissionStatus _locationStatus = PermissionStatus.denied;
  bool _autoConnectDevice = false;

  @override
  void initState() {
    super.initState();
    _checkDeviceCapabilities();
    _loadSavedPreferences();
  }

  // ตรวจสอบความพร้อมของระบบ NFC และ สิทธิ์ต่างๆ
  Future<void> _checkDeviceCapabilities() async {
    final nfcAvailable = await NfcManager.instance.isAvailable();
    final btStatus = await Permission.bluetoothConnect.status;
    final locStatus = await Permission.location.status;

    setState(() {
      _isNfcAvailable = nfcAvailable;
      _bluetoothStatus = btStatus;
      _locationStatus = locStatus;
    });
  }

  // โหลดค่าตั้งค่าที่เคยเซฟไว้
  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoConnectDevice = prefs.getBool('auto_connect') ?? false;
    });
  }

  // บันทึกการตั้งค่า
  Future<void> _toggleAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_connect', value);
    setState(() {
      _autoConnectDevice = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่า (Settings)'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('ฮาร์ดแวร์และการสิทธิ์การใช้งาน'),
          
          // สภาพการทำงาน NFC
          ListTile(
            leading: Icon(
              Icons.nfc,
              color: _isNfcAvailable ? Colors.green : Colors.grey,
            ),
            title: const Text('สถานะ NFC'),
            subtitle: Text(_isNfcAvailable ? 'พร้อมใช้งาน' : 'ไม่รองรับ หรือ ปิดอยู่'),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkDeviceCapabilities,
            ),
          ),

          // สิทธิ์ Bluetooth
          ListTile(
            leading: Icon(
              Icons.bluetooth,
              color: _bluetoothStatus.isGranted ? Colors.blue : Colors.red,
            ),
            title: const Text('สิทธิ์การเชื่อมต่อ Bluetooth'),
            subtitle: Text(_bluetoothStatus.isGranted ? 'อนุญาตแล้ว' : 'ยังไม่ได้รับอนุญาต'),
            trailing: TextButton(
              onPressed: () async {
                await [
                  Permission.bluetoothScan,
                  Permission.bluetoothConnect,
                ].request();
                _checkDeviceCapabilities();
              },
              child: const Text('ขอสิทธิ์'),
            ),
          ),

          // สิทธิ์ Location
          ListTile(
            leading: Icon(
              Icons.location_on,
              color: _locationStatus.isGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('สิทธิ์การเข้าถึงตำแหน่ง (Location)'),
            subtitle: Text(_locationStatus.isGranted ? 'อนุญาตแล้ว' : 'ยังไม่ได้รับอนุญาต'),
            trailing: TextButton(
              onPressed: () async {
                await Permission.location.request();
                _checkDeviceCapabilities();
              },
              child: const Text('ขอสิทธิ์'),
            ),
          ),

          const Divider(),
          _buildSectionHeader('การทำงานทั่วไป'),

          // เชื่อมต่ออัตโนมัติ
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('เชื่อมต่ออุปกรณ์ล่าสุดอัตโนมัติ'),
            subtitle: const Text('ค้นหาและเชื่อมต่อ Bluetooth ทันทีที่เปิดแอป'),
            value: _autoConnectDevice,
            onChanged: _toggleAutoConnect,
          ),

          const Divider(),
          
          // ปุ่มเปิดหน้า App Settings ของระบบ Android
          ListTile(
            leading: const Icon(Icons.settings_applications),
            title: const Text('เปิดการตั้งค่าแอปในเครื่อง Android'),
            subtitle: const Text('กรณีต้องการแก้ไขสิทธิ์ย่อยในระบบ'),
            onTap: () => openAppSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}