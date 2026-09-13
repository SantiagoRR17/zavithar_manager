import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_providers.dart';
import '../data/backup_repository.dart';
import '../domain/backup_document.dart';

/// Export, on the Settings screen.
///
/// **This is the only backup this app can have.** Firestore's own backups and
/// point-in-time recovery need the Blaze plan, which ADR 0011 rules out. So the
/// card says that plainly rather than presenting export as a convenience: if
/// something damages the data, a file the owner exported is the only way back.
class BackupCard extends ConsumerStatefulWidget {
  const BackupCard({super.key});

  @override
  ConsumerState<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<BackupCard> {
  bool _busy = false;
  String? _error;
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gridline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(
                Icons.backup_outlined,
                size: 18,
                color: AppColors.brandPrimary,
              ),
              SizedBox(width: 8),
              Text(
                'Back up your data',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Firestore has no automatic backups on the free plan, so an export '
            'is the only copy you can restore from. Exports two files: a JSON '
            'with everything, and your transactions as a spreadsheet.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_result != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: AppColors.statusGood,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _result!,
                    style: const TextStyle(
                      color: AppColors.statusGood,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...<Widget>[
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.statusCritical,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share, size: 18),
            label: Text(_busy ? 'Reading everything…' : 'Export and share'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Send it to Drive, email or Files — anywhere that is not this '
            'phone. A backup stored only on the device it backs up is not one.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final User? user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final BackupBundle bundle = await BackupRepository(uid: user.uid).build();

      // Written to the temp directory rather than anywhere permanent: the file
      // is a courier, not storage. Once the share sheet has handed it to Drive
      // or email, a copy kept on the phone would only be a second thing to keep
      // in sync — and a backup that lives on the device it backs up is not a
      // backup at all.
      final Directory dir = await getTemporaryDirectory();
      final File jsonFile = File(
        '${dir.path}/${BackupDocument.fileName('json')}',
      );
      final File csvFile = File(
        '${dir.path}/${BackupDocument.fileName('csv')}',
      );
      await jsonFile.writeAsString(bundle.json);
      await csvFile.writeAsString(bundle.csv);

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(jsonFile.path), XFile(csvFile.path)],
          subject: 'Zavithar Manager backup',
        ),
      );

      if (mounted) {
        setState(() {
          _result =
              'Exported ${bundle.documentCount} documents '
              '(${bundle.transactionCount} transactions).';
        });
      }
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
