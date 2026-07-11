import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'printer_adapter.dart';
import 'mock_printer_adapter.dart';

/// Global printer provider — swap out adapter via overrideWithValue() in tests
/// or when user connects a real device.
final printerAdapterProvider = StateProvider<PrinterAdapter>(
  (ref) => MockPrinterAdapter(),
);
