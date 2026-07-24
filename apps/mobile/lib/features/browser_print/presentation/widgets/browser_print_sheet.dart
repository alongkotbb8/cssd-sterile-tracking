import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/api/api_client.dart';
import '../../../../core/api/repositories.dart';
import '../../../../core/config/feature_flags.dart';
import '../../../../core/models/models.dart';
import '../../../../core/printer/label_renderer.dart';
import '../../../../core/printer/printer_adapter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/domain_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../print_pdf_seam.dart';
import 'browser_print_history_card.dart';

/// สร้าง [LabelData] จาก payload label ที่ backend ส่งกลับ (**authoritative**)
/// — วันที่มาจาก backend เท่านั้น และเฉพาะเมื่อ backend ยืนยันว่า sterile แล้ว
/// (ห่อที่ยังไม่ผ่านการฆ่าเชื้อ = null ทั้งคู่ → renderer พิมพ์แถบเตือนแทนวันที่)
/// QR บน label = packageId ตรงตาม payload เท่านั้น (กฎโดเมน: QR เก็บแค่ id)
LabelData browserPrintLabelData(BrowserPrintLabel label) => LabelData(
      packageId: label.packageId,
      setName: label.templateName,
      wrapType: wrapTypeLabelText(label.wrapType),
      sterilizeDate: label.isSterilized ? label.sterilizeDate : null,
      expiryDate: label.isSterilized ? label.expiryDate : null,
    );

/// เปิด sheet พิมพ์ผ่านเบราว์เซอร์ (BROWSER_DIALOG) สำหรับห่อเดียว
/// [createdFrom] = CREATE_PACKAGE | PACKAGE_DETAIL | PRINT_JOBS (บันทึกที่ backend)
///
/// Flow (MACOS_BROWSER_PRINT_DIRECTIVE.md §10):
/// สร้างคำขอที่ backend → แสดง preview จาก label payload → ผู้ใช้กดพิมพ์ →
/// บันทึก dialog-opened **ให้สำเร็จก่อน** → เปิด print dialog → ผู้ใช้เลือกผลเอง
/// (ยืนยัน/ไม่ได้พิมพ์/ตรวจสอบภายหลัง) — **ไม่มี** auto-open, auto-confirm,
/// auto-retry ใด ๆ และไม่แตะ printedAt/สถานะ PRINTED เด็ดขาด
Future<void> showBrowserPrintSheet(
  BuildContext context,
  WidgetRef ref, {
  required PackageModel pkg,
  required String createdFrom,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SterelisColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _BrowserPrintSheet(pkg: pkg, createdFrom: createdFrom),
  );
}

enum _Phase {
  /// กรอกเหตุผล reprint / เลือกจำนวนสำเนา ก่อนสร้างคำขอ (หรือ retry เมื่อพลาด)
  setup,

  /// กำลังสร้างคำขอ + render preview
  creating,

  /// แสดง preview + คำแนะนำ + ปุ่ม "พิมพ์ผ่านเครื่องนี้"
  preview,

  /// เปิด dialog แล้ว — ให้ผู้ใช้เลือกผลด้วยตนเอง (3 ตัวเลือก)
  result,
}

class _BrowserPrintSheet extends ConsumerStatefulWidget {
  const _BrowserPrintSheet({required this.pkg, required this.createdFrom});
  final PackageModel pkg;
  final String createdFrom;

  @override
  ConsumerState<_BrowserPrintSheet> createState() => _BrowserPrintSheetState();
}

class _BrowserPrintSheetState extends ConsumerState<_BrowserPrintSheet> {
  _Phase _phase = _Phase.setup;
  int _copies = 1;
  final _reasonCtrl = TextEditingController();
  bool _needReason = false; // ต้องกรอกเหตุผล reprint ก่อนสร้างคำขอ
  BrowserPrintPrior? _prior; // ข้อมูลการพิมพ์ครั้งก่อน (จาก error body/response)
  Object? _createError; // error ล่าสุดตอนสร้างคำขอ (แสดง + ปุ่มลองใหม่)
  BrowserPrintRequest? _request; // คำขอที่สร้างสำเร็จ (มี label payload)
  Uint8List? _png; // bitmap preview จาก label payload
  bool _working = false; // กำลังเรียก dialog-opened/confirm/cancel

  // Idempotency-Key **คงเดิมต่อ 1 operation** ตลอดอายุ sheet — กดลองใหม่แล้ว
  // backend replay ของเดิม ไม่สร้างคำขอ/transition ซ้ำ (กัน label ซ้ำ)
  late final String _createKey = newIdempotencyKey();
  late final String _dialogOpenedKey = newIdempotencyKey();
  late final String _confirmKey = newIdempotencyKey();
  late final String _cancelKey = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    if (widget.pkg.printedAt != null) {
      // เคยพิมพ์แล้ว (gateway ACK) → ต้องเตือน + บังคับเหตุผลก่อนสร้างคำขอ (§9)
      _needReason = true;
    } else {
      // ยังไม่เคยพิมพ์ → สร้างคำขอทันทีที่เปิด sheet (backend ตัดสิน reprint ซ้ำ
      // อีกชั้น — ถ้าตอบ 400 ว่าเป็น reprint จะย้อนกลับมาหน้ากรอกเหตุผล)
      scheduleMicrotask(_create);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final reason = _reasonCtrl.text.trim();
    if (_needReason && reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.bpReprintReasonRequired),
        backgroundColor: SterelisColors.danger,
      ));
      return;
    }
    setState(() {
      _phase = _Phase.creating;
      _createError = null;
    });
    try {
      final req = await ref.read(browserPrintRepositoryProvider).create(
            widget.pkg.id,
            copies: _copies,
            createdFrom: widget.createdFrom,
            reprintReason: reason.isEmpty ? null : reason,
            idempotencyKey: _createKey, // คงเดิมเมื่อ retry — กันคำขอซ้ำ
          );
      // preview สร้างจาก label payload ของ backend เท่านั้น (ไม่ใช่ pkg ฝั่ง client)
      final label = req.label;
      final png = label == null
          ? null
          : await ref.read(renderLabelPngProvider)(
              browserPrintLabelData(label),
              widthMm: kLabelWidthMm,
              heightMm: kLabelHeightMm,
            );
      if (!mounted) return;
      setState(() {
        _request = req;
        _prior = req.priorPrints ?? _prior;
        _png = png;
        _phase = _Phase.preview;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      if (data is Map && data['code'] == 'BROWSER_PRINT_REPRINT_REASON_REQUIRED') {
        // backend ตัดสินว่าเป็น reprint → แสดงคำเตือน (พร้อมข้อมูล prior ถ้ามี)
        // + บังคับเหตุผล แล้วให้กดสร้างใหม่ด้วย idempotency key เดิม
        setState(() {
          _needReason = true;
          if (data['prior'] is Map) {
            _prior = BrowserPrintPrior.fromJson(
                (data['prior'] as Map).cast<String, dynamic>());
          }
          _phase = _Phase.setup;
        });
        return;
      }
      setState(() {
        _createError = e;
        _phase = _Phase.setup;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _createError = e;
        _phase = _Phase.setup;
      });
    }
  }

  /// ปุ่ม "พิมพ์ผ่านเครื่องนี้" — บันทึก DIALOG_OPENED ที่ backend **ให้สำเร็จก่อน**
  /// จึงเปิด print dialog (ผลลัพธ์ของ dialog ถูกเพิกเฉยทั้งหมด — ไม่ใช่หลักฐานพิมพ์)
  Future<void> _openPrintDialog() async {
    final req = _request;
    final png = _png;
    if (req == null || png == null || _working) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _working = true);
    try {
      await ref
          .read(browserPrintRepositoryProvider)
          .dialogOpened(req.id, idempotencyKey: _dialogOpenedKey);
    } catch (e) {
      // dialog-opened ไม่สำเร็จ → **ห้าม** เปิด print dialog (ลำดับ §10 ข้อ 3→4)
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
      return;
    }

    // สร้าง PDF ขนาด label จริง (N หน้า = N สำเนา) แล้วเปิด system print dialog
    // ผ่าน seam — ผลลัพธ์ (return/พัง/ timeout) ไม่มีความหมายเชิงสถานะ จึงเพิกเฉย
    try {
      final bytes = await _buildPdf(png, req.copies);
      await ref
          .read(printPdfProvider)(bytes, 'cssd-label-${req.packageId}.pdf')
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // เพิกเฉยโดยตั้งใจ: การพัง/ค้างของ print dialog ไม่ใช่ผลการพิมพ์ —
      // ผู้ใช้เป็นคนเลือกผลจริงในขั้นถัดไป (ห้าม auto-retry กัน label ซ้ำ)
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _phase = _Phase.result; // ไม่ auto-confirm — ผู้ใช้เลือกผลเอง 3 ทาง
    });
  }

  Future<Uint8List> _buildPdf(Uint8List png, int copies) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    for (var i = 0; i < copies; i++) {
      doc.addPage(pw.Page(
        pageFormat: const PdfPageFormat(
          kLabelWidthMm * PdfPageFormat.mm,
          kLabelHeightMm * PdfPageFormat.mm,
        ),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
    }
    return doc.save();
  }

  Future<void> _confirm() => _finish(
        (repo, id) => repo.confirm(id, idempotencyKey: _confirmKey),
        (l10n) => l10n.bpConfirmedSnack,
        SterelisColors.success,
      );

  Future<void> _cancelNotPrinted() => _finish(
        (repo, id) => repo.cancel(id, idempotencyKey: _cancelKey),
        (l10n) => l10n.bpCancelledSnack,
        SterelisColors.textMuted,
      );

  Future<void> _finish(
    Future<BrowserPrintRequest> Function(BrowserPrintRepository, String) call,
    String Function(AppLocalizations) message,
    Color color,
  ) async {
    final req = _request;
    if (req == null || _working) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _working = true);
    try {
      await call(ref.read(browserPrintRepositoryProvider), req.id);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(message(l10n)), backgroundColor: color));
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      messenger.showSnackBar(SnackBar(
        content: Text(apiErrorMessage(l10n, e)),
        backgroundColor: SterelisColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: SterelisColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.bpSheetTitle,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SterelisColors.textStrong)),
          const SizedBox(height: 4),
          Text(widget.pkg.id,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: SterelisColors.textMuted)),
          const SizedBox(height: 16),
          ...switch (_phase) {
            _Phase.setup => _buildSetup(l10n),
            _Phase.creating => _buildCreating(l10n),
            _Phase.preview => _buildPreview(l10n),
            _Phase.result => _buildResult(l10n),
          },
        ],
      ),
    );
  }

  List<Widget> _buildSetup(AppLocalizations l10n) {
    return [
      if (_needReason) ...[
        _reprintWarningBox(l10n),
        const SizedBox(height: 10),
        TextField(
          controller: _reasonCtrl,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: l10n.bpReprintReasonLabel,
            hintText: l10n.bpReprintReasonHint,
          ),
        ),
        const SizedBox(height: 6),
      ],
      _copiesRow(l10n),
      if (_createError != null) ...[
        const SizedBox(height: 10),
        Text(apiErrorMessage(l10n, _createError!),
            style: const TextStyle(color: SterelisColors.danger, fontSize: 13)),
      ],
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _create,
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(
            _createError != null ? l10n.commonRetry : l10n.bpCreateRequest),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    ];
  }

  List<Widget> _buildCreating(AppLocalizations l10n) => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(children: [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Center(
              child: Text(l10n.bpCreating,
                  style: const TextStyle(
                      fontSize: 13, color: SterelisColors.textMuted)),
            ),
          ]),
        ),
      ];

  List<Widget> _buildPreview(AppLocalizations l10n) {
    final req = _request!;
    final label = req.label;
    final fmt = DateFormat('dd/MM/yyyy');
    return [
      // §10: เลขห่อ + ชื่อชุด + สถานะห่อ + จำนวนสำเนา + ตัวอย่าง label
      if (label != null) ...[
        Row(children: [
          Expanded(
            child: Text(label.templateName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: SterelisColors.textStrong)),
          ),
          StatusBadge(label.status),
        ]),
        const SizedBox(height: 10),
      ],
      Text(l10n.bpPreviewTitle,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 8),
      if (_png != null)
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: SterelisColors.white,
              border: Border.all(color: SterelisColors.borderStrong),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AspectRatio(
              aspectRatio: kLabelWidthMm / kLabelHeightMm,
              child: Image.memory(_png!, fit: BoxFit.contain),
            ),
          ),
        ),
      const SizedBox(height: 8),
      if (label != null)
        label.isSterilized &&
                label.sterilizeDate != null &&
                label.expiryDate != null
            ? Text(
                l10n.bpDatesLine(fmt.format(label.sterilizeDate!),
                    fmt.format(label.expiryDate!)),
                style: const TextStyle(
                    fontSize: 13, color: SterelisColors.textMuted))
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SterelisColors.textStrong,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(l10n.bpUnsterileNotice,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
      const SizedBox(height: 6),
      Text(l10n.bpCopiesLine(req.copies),
          style: const TextStyle(fontSize: 13, color: SterelisColors.textMuted)),
      if (req.isReprint) ...[
        const SizedBox(height: 10),
        _reprintWarningBox(l10n),
      ],
      const SizedBox(height: 12),
      _settingsBox(l10n),
      const SizedBox(height: 10),
      _cannotVerifyBox(l10n),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _working ? null : _openPrintDialog,
        icon: _working
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.print_outlined),
        label: Text(l10n.bpPrintViaThisDevice),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    ];
  }

  List<Widget> _buildResult(AppLocalizations l10n) => [
        Text(l10n.bpResultQuestion,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: SterelisColors.textStrong)),
        const SizedBox(height: 8),
        _cannotVerifyBox(l10n),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _working ? null : _confirm,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(l10n.bpResultPrinted),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: SterelisColors.success),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _working ? null : _cancelNotPrinted,
          icon: const Icon(Icons.cancel_outlined),
          label: Text(l10n.bpResultNotPrinted),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: SterelisColors.danger),
        ),
        const SizedBox(height: 10),
        TextButton(
          // คงสถานะ DIALOG_OPENED ไว้ — กลับมายืนยันภายหลังจากหน้าประวัติได้
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.bpResultLater),
        ),
      ];

  Widget _copiesRow(AppLocalizations l10n) {
    return Row(children: [
      Flexible(
        child: Text(l10n.bpCopies,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
      ),
      SizedBox(
        width: 40,
        child: Text('$_copies',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: SterelisColors.textStrong)),
      ),
      IconButton(
        icon: const Icon(Icons.add_circle_outline),
        onPressed: _copies < 10 ? () => setState(() => _copies++) : null,
      ),
    ]);
  }

  Widget _reprintWarningBox(AppLocalizations l10n) {
    final prior = _prior;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final priorAt = prior?.lastAt != null
        ? fmt.format(prior!.lastAt!)
        : widget.pkg.printedAt != null
            ? fmt.format(widget.pkg.printedAt!)
            : null;
    final priorStatus = prior?.lastStatus == null
        ? null
        : BrowserPrintStatusStyle.of(l10n, prior!.lastStatus!).label;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SterelisColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: SterelisColors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.bpReprintWarning,
                style:
                    const TextStyle(fontSize: 13, color: SterelisColors.text)),
            if (priorAt != null)
              Text(
                l10n.bpReprintLast(
                  priorAt,
                  prior?.lastByName ?? '—',
                  priorStatus ?? (prior?.lastStatus ?? '—'),
                ),
                style: const TextStyle(
                    fontSize: 12, color: SterelisColors.textMuted),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _settingsBox(AppLocalizations l10n) {
    final lines = [
      l10n.bpSettingsPrinter,
      l10n.bpSettingsPaper(kLabelWidthMm, kLabelHeightMm),
      l10n.bpSettingsScale,
      l10n.bpSettingsMargins,
      l10n.bpSettingsHeaders,
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SterelisColors.blue50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.bpSettingsTitle,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: SterelisColors.blue600)),
        const SizedBox(height: 6),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('• $line',
                style:
                    const TextStyle(fontSize: 12.5, color: SterelisColors.text)),
          ),
      ]),
    );
  }

  Widget _cannotVerifyBox(AppLocalizations l10n) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SterelisColors.warningBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.visibility_outlined,
              color: SterelisColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.bpCannotVerifyWarning,
                style:
                    const TextStyle(fontSize: 13, color: SterelisColors.text)),
          ),
        ]),
      );
}
