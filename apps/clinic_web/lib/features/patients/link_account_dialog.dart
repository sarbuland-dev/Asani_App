import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/widgets/desktop.dart';
import '../../data/clinic_repository.dart';
import '../../data/providers.dart';

/// D-52 (S-2, S-3): reception links a walk-in profile to the patient's Asani app account, with the patient in front
/// of them. The app account's phone is NOT verified, so nothing is linked automatically: reception searches the number,
/// the patient confirms which family member they are (or "New member"), then Link. Logged in the activity log.
/// Basic UI for now (functionality first).
Future<void> showLinkAccountDialog(BuildContext context, {required String clinicId, required Patient walkIn}) =>
    showDialog<void>(context: context, builder: (_) => _LinkAccountDialog(clinicId: clinicId, walkIn: walkIn));

class _LinkAccountDialog extends ConsumerStatefulWidget {
  const _LinkAccountDialog({required this.clinicId, required this.walkIn});
  final String clinicId;
  final Patient walkIn;

  @override
  ConsumerState<_LinkAccountDialog> createState() => _LinkAccountDialogState();
}

/// Radio value for "New member of that family".
const _newMember = '__new__';

class _LinkAccountDialogState extends ConsumerState<_LinkAccountDialog> {
  late final _phone = TextEditingController(text: PhoneUtils.formatLocal(PhoneUtils.normalizeLocal(widget.walkIn.phone)));
  String? _searched; // E.164 number searched
  String? _choice; // patient id, or _newMember
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _phoneOk => PhoneUtils.isValidLocal(_phone.text);

  void _search() {
    if (!_phoneOk) return;
    setState(() {
      _searched = PhoneUtils.toE164(_phone.text);
      _choice = null;
      _confirmed = false;
      _error = null;
    });
  }

  Future<void> _link() async {
    final phone = _searched;
    if (phone == null || _choice == null || !_confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await ref.read(repositoryProvider).linkWalkInToAccount(
            widget.clinicId,
            widget.walkIn.id,
            accountPhone: phone,
            targetPatientId: _choice == _newMember ? null : _choice,
          );
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Linked to the app account. $n ${n == 1 ? 'visit' : 'visits'} now show in the patient\'s app.');
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(repoTickProvider);
    final lookup = _searched == null ? null : ref.read(repositoryProvider).lookupPhone(widget.clinicId, _searched!);
    final family = [for (final p in lookup?.profiles ?? const <PhoneProfile>[]) if (p.appAccount) p];

    return AppDialog(
      title: 'Link to app account',
      subtitle: '${widget.walkIn.name} · walk-in profile. The app number is not verified: link only after the patient confirms.',
      width: 560,
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _choice != null && _confirmed && !_busy ? _link : null,
          child: Text(_busy ? 'Linking…' : 'Link to app account'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldLabel(
          'Mobile number of the app account',
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')), LengthLimitingTextInputFormatter(15)],
                decoration: const InputDecoration(hintText: '300 1234567', prefixText: '+92  '),
                onChanged: (_) => setState(() => _searched = null),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: Gap.sm),
            OutlinedButton(onPressed: _phoneOk ? _search : null, child: const Text('Find account')),
          ]),
        ),
        if (lookup != null && lookup.loading) Text('Checking the Asani app for this number…', style: AppText.labelSmall),
        if (lookup?.error != null) Text(lookup!.error!, style: AppText.bodyMedium.copyWith(color: AppColors.danger)),
        if (lookup != null && !lookup.loading && lookup.error == null && family.isEmpty)
          Text('No Asani app account uses this number.', style: AppText.bodyMedium),
        if (family.isNotEmpty) ...[
          Text('App account (number not verified) · who is this patient?', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: Gap.xs),
          RadioGroup<String>(
            groupValue: _choice,
            onChanged: (v) => setState(() => _choice = v),
            child: Column(children: [
              for (final p in family)
                RadioListTile<String>(
                  value: p.id,
                  title: Text(p.name),
                  subtitle: Text('${p.relation.label} · ${p.age ?? '—'} / ${p.gender.short} · the visits move to this person'),
                ),
              const RadioListTile<String>(
                value: _newMember,
                title: Text('New member of this family'),
                subtitle: Text('This walk-in profile joins the family in the app'),
              ),
            ]),
          ),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('The patient confirmed in person that this is their Asani account'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Gap.sm),
          Text(_error!, style: AppText.bodyMedium.copyWith(color: AppColors.danger)),
        ],
      ]),
    );
  }
}
