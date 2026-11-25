import 'package:flutter/material.dart';

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final Color accentColor;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.sublabel,
    this.accentColor = const Color(0xFFB8F66A),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF162337),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF283A50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF96ADC7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(
              sublabel!,
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF80A6AC),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
