import 'package:asani_core/asani_core.dart';

import '../../core/config/links.dart';
import '../../core/utils/formatters.dart';
import '../../core/web/print.dart';
import '../../data/models.dart';

/// Everything printed on the clinic form (C-07).
class ClinicFormData {
  const ClinicFormData({
    required this.clinic,
    required this.doctor,
    required this.token,
    required this.visitNumber,
    this.lastVisit,
  });

  final Clinic clinic;
  final Doctor doctor;
  final QueueToken token;

  /// This visit's number at this clinic ("4th visit").
  final int visitNumber;
  final String? lastVisit; // yyyy-MM-dd
}

/// W-22 print templates: Thermal 80 mm and A5.
abstract final class ClinicFormTemplate {
  static String html(ClinicFormData d, PrintFormat format) {
    final t = d.token.token;
    final s = t.patientSnapshot;
    final age = s.age(parseDayKey(t.date));
    final a5 = format == PrintFormat.a5;
    final qr = qrSvg(AppLinks.token(t.id), size: a5 ? 96 : 84);
    final rows = <(String, String)>[
      ('Patient', s.name),
      ('Age / Sex', '${age ?? '—'} / ${s.gender.short}'),
      ('Phone', Fmt.phone(s.phone)),
      ('Doctor', d.doctor.name),
      ('Date', Fmt.longDay(t.date)),
      ('Visit', '${WebFmt.ordinal(d.visitNumber)} visit${d.lastVisit == null ? '' : ' · last ${Fmt.shortDay(d.lastVisit!)}'}'),
    ];
    final table = rows.map((r) => '<tr><td class="k">${esc(r.$1)}</td><td class="v">${esc(r.$2)}</td></tr>').join();

    final page = a5 ? '@page { size: A5; margin: 12mm; }' : '@page { size: 80mm auto; margin: 3mm; }';
    final width = a5 ? '100%' : '74mm';
    return '''<!doctype html><html><head><meta charset="utf-8"><title>${esc(t.tokenPrefix)}-${t.number}</title>
<style>
$page
* { box-sizing: border-box; }
body { margin: 0; font-family: Inter, Arial, Helvetica, sans-serif; color: #0F172A; }
.wrap { width: $width; margin: 0 auto; }
.head { text-align: center; border-bottom: 1.5px dashed #94A3B8; padding-bottom: ${a5 ? '10px' : '6px'}; }
.clinic { font-size: ${a5 ? '20px' : '15px'}; font-weight: 800; }
.addr { font-size: ${a5 ? '12px' : '10px'}; color: #475569; }
.tokrow { display: flex; align-items: center; justify-content: space-between; padding: ${a5 ? '12px 0' : '6px 0'}; border-bottom: 1.5px dashed #94A3B8; }
.label { font-size: 10px; letter-spacing: 1.4px; font-weight: 700; color: #475569; }
.token { font-size: ${a5 ? '56px' : '40px'}; font-weight: 900; color: #0F766E; line-height: 1; }
table { width: 100%; border-collapse: collapse; margin: ${a5 ? '10px 0' : '6px 0'}; font-size: ${a5 ? '13px' : '11px'}; }
td { padding: ${a5 ? '4px 0' : '2px 0'}; vertical-align: top; }
td.k { color: #475569; width: 34%; }
td.v { font-weight: 600; }
.rx { border: 1.5px solid #0F172A; border-radius: 8px; height: ${a5 ? '330px' : '120px'}; padding: 8px; position: relative; }
.rx b { font-size: ${a5 ? '24px' : '18px'}; font-family: Georgia, serif; }
.foot { text-align: center; font-size: 9px; color: #94A3B8; margin-top: 6px; }
</style></head><body><div class="wrap">
<div class="head"><div class="clinic">${esc(d.clinic.name)}</div><div class="addr">${esc(d.clinic.address)} · ${esc(d.clinic.phone)}</div></div>
<div class="tokrow"><div><div class="label">TOKEN</div><div class="token">${esc(t.tokenPrefix)}-${t.number}</div>
<div class="addr">${esc(d.token.source.label)} · ${esc(Fmt.clock(d.token.arrivedAt ?? t.createdAt))}</div></div>$qr</div>
<table>$table</table>
<div class="rx"><b>Rx</b></div>
<div class="foot">Asani · smart clinic token &amp; live queue</div>
</div></body></html>''';
  }

  static void print(ClinicFormData d, PrintFormat format) {
    if (format == PrintFormat.none) return;
    printHtml(html(d, format));
  }
}
