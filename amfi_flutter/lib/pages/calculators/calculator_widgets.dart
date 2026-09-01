import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';

class CalcInput extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String prefix;
  final String suffix;
  final double? step;
  final ValueChanged<double> onChanged;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const CalcInput({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.prefix = '',
    this.suffix = '',
    this.step,
    required this.onChanged,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<CalcInput> createState() => _CalcInputState();
}

class _CalcInputState extends State<CalcInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(CalcInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      String newText = _formatValue(widget.value);
      if (_controller.text != newText) {
        _controller.value = _controller.value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  String _formatValue(double val) {
    if (val == val.toInt().toDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(widget.step != null ? 2 : 1).replaceAll(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int? divisions;
    if (widget.step != null && widget.step! > 0) {
      divisions = ((widget.max - widget.min) / widget.step!).round();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: CommonWidgets.txt(
                widget.label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                selectedLanguage: widget.selectedLanguage,
                translate: widget.translate,
              ),
            ),
            Container(
              width: 100,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.indigo[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  if (widget.prefix.isNotEmpty)
                    Text(widget.prefix, style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.bold, fontSize: 13)),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.indigo[900],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) {
                        double? d = double.tryParse(val);
                        if (d != null) {
                          if (d > widget.max) d = widget.max;
                          widget.onChanged(d);
                        }
                      },
                    ),
                  ),
                  if (widget.suffix.isNotEmpty)
                    Text(widget.suffix, style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.indigo[900],
            inactiveTrackColor: Colors.indigo[50],
            thumbColor: Colors.indigo[900],
            overlayColor: Colors.indigo.withOpacity(0.1),
          ),
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: divisions,
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class CalcResultCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const CalcResultCard({
    super.key,
    required this.title,
    required this.value,
    this.color,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? Colors.indigo[900],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (color ?? Colors.indigo[900]!).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CommonWidgets.txt(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            selectedLanguage: selectedLanguage,
            translate: translate,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class CalcSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const CalcSummaryRow({
    super.key,
    required this.label,
    required this.value,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CommonWidgets.txt(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            selectedLanguage: selectedLanguage,
            translate: translate,
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
