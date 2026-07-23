/// Abstract printer adapter — ทุก printer ต้อง implement interface นี้
/// ใช้ Factory / Provider เลือก adapter ตามการตั้งค่าผู้ใช้
abstract class PrinterAdapter {
  /// ชื่อแสดงให้ผู้ใช้เห็น
  String get displayName;

  /// เชื่อมต่อกับเครื่องพิมพ์ — throw [PrinterException] ถ้าล้มเหลว
  Future<void> connect();

  /// ตัดการเชื่อมต่อ
  Future<void> disconnect();

  /// สถานะการเชื่อมต่อปัจจุบัน
  bool get isConnected;

  /// พิมพ์ label 1 ห่อ
  /// [data] คือข้อมูลทั้งหมดที่จะแสดงบน label
  Future<void> printLabel(LabelData data);

  /// พิมพ์ซ้ำ (reprint) — ไม่สร้างเลขรันใหม่
  Future<void> reprint(LabelData data) => printLabel(data);
}

class LabelData {
  final String packageId;      // running number = QR content
  final String setName;        // ชื่อชุด
  final String wrapType;       // 'ห่อซีล' | 'ห่อผ้า'

  /// วันนึ่ง/วันหมดอายุ **จริงจาก backend เท่านั้น** — ห่อที่ยังไม่ผ่านการนึ่ง
  /// ต้องเป็น null แล้ว label จะพิมพ์แถบ "ยังไม่ผ่านการฆ่าเชื้อ" แทนวันที่
  /// (ห้าม fabricate วันที่โดยประมาณเด็ดขาด — ความปลอดภัยผู้ป่วย)
  final DateTime? sterilizeDate;
  final DateTime? expiryDate;

  const LabelData({
    required this.packageId,
    required this.setName,
    required this.wrapType,
    this.sterilizeDate,
    this.expiryDate,
  });

  bool get isSterilized => sterilizeDate != null;
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);
  @override
  String toString() => 'PrinterException: $message';
}
