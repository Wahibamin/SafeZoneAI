import 'package:flutter/material.dart';
import '../../features/safety/domain/safety_decision.dart';

class StatusBadge extends StatelessWidget {
  final SafetyStatus status;
  final bool large;

  const StatusBadge({
    super.key,
    required this.status,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    final IconData icon;

    switch (status) {
      case SafetyStatus.compliant:
        bg = const Color(0xFF173129);
        fg = const Color(0xFFB8F66A);
        border = const Color(0xFF386047);
        icon = Icons.verified_user_rounded;
        break;
      case SafetyStatus.violation:
        bg = const Color(0xFF3A2330);
        fg = const Color(0xFFFF8699);
        border = const Color(0xFF754654);
        icon = Icons.warning_amber_rounded;
        break;
      case SafetyStatus.review:
        bg = const Color(0xFF362B1F);
        fg = const Color(0xFFF5CA74);
        border = const Color(0xFF78603E);
        icon = Icons.fact_check_outlined;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 10,
        vertical: large ? 10 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: large ? 22 : 15),
          const SizedBox(width: 6),
          Text(
            status.arabicLabel,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: large ? 15 : 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
