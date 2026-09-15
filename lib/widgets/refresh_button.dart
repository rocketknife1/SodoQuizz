import 'package:flutter/material.dart';

import '../core/firestore_errors.dart';
import '../core/lang.dart';

/// Butonul mic de reîncărcare — cerut de user în locul gestului de tras în
/// jos. Se învârte cât rulează [onRefresh]; dacă aceasta aruncă, arată motivul
/// real (vezi [firestoreErrorText]), altfel confirmă scurt că e totul ok.
class RefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color color;
  const RefreshButton({super.key, required this.onRefresh, this.color = Colors.white70});

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      await widget.onRefresh();
    } catch (e) {
      error = firestoreErrorText(e);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: Duration(seconds: error == null ? 1 : 4),
        content: Text(error ?? tr('Actualizat ✓', 'Updated ✓')),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Reîncarcă', 'Refresh'),
      onPressed: _busy ? null : _run,
      icon: _busy
          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: widget.color))
          : Icon(Icons.refresh_rounded, color: widget.color),
    );
  }
}
