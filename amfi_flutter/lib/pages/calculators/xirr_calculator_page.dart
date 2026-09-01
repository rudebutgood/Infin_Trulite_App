import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class CashFlow {
  DateTime date;
  double amount;

  CashFlow({required this.date, required this.amount});
}

class XirrCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const XirrCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<XirrCalculatorPage> createState() => _XirrCalculatorPageState();
}

class _XirrCalculatorPageState extends State<XirrCalculatorPage> {
  List<CashFlow> flows = [
    CashFlow(date: DateTime.now().subtract(const Duration(days: 365)), amount: -100000),
    CashFlow(date: DateTime.now(), amount: 120000),
  ];

  double calculateXirr() {
    if (flows.length < 2) return 0.0;

    double x0 = 0.1; // Initial guess
    double x1 = 0.0;
    
    for (int i = 0; i < 100; i++) {
      double f = 0.0;
      double df = 0.0;
      
      for (var flow in flows) {
        double t = flow.date.difference(flows[0].date).inDays / 365.0;
        f += flow.amount * pow(1 + x0, -t);
        df -= t * flow.amount * pow(1 + x0, -t - 1);
      }
      
      if (df == 0) return 0.0;
      x1 = x0 - f / df;
      if ((x1 - x0).abs() < 0.0001) return x1 * 100;
      x0 = x1;
    }
    return x1 * 100;
  }

  @override
  Widget build(BuildContext context) {
    double xirr = calculateXirr();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: CommonWidgets.txt(
          'XIRR Calculator',
          selectedLanguage: widget.selectedLanguage,
          translate: widget.translate,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo[900],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              setState(() {
                flows.add(CashFlow(date: DateTime.now(), amount: 0));
              });
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: CalcResultCard(
              title: 'XIRR',
              value: '${xirr.isNaN || xirr.isInfinite ? '0.00' : xirr.toStringAsFixed(2)}%',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: flows.length,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemBuilder: (context, index) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: flows[index].date,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => flows[index].date = picked);
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CommonWidgets.txt(
                                      'Date',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500),
                                      selectedLanguage: widget.selectedLanguage,
                                      translate: widget.translate,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_month, size: 16, color: Colors.indigo[900]),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat('dd MMM yyyy').format(flows[index].date),
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('amt_$index'),
                                initialValue: flows[index].amount.toString(),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Amount',
                                  labelStyle: const TextStyle(fontSize: 12),
                                  prefixText: '₹',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                onChanged: (val) {
                                  setState(() {
                                    flows[index].amount = double.tryParse(val) ?? 0;
                                  });
                                },
                              ),
                            ),
                            if (index > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () {
                                  setState(() => flows.removeAt(index));
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.indigo[900],
                            inactiveTrackColor: Colors.indigo[50],
                            thumbColor: Colors.indigo[900],
                            overlayColor: Colors.indigo.withOpacity(0.1),
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: flows[index].amount.clamp(-10000000, 10000000),
                            min: -10000000,
                            max: 10000000,
                            onChanged: (v) {
                              setState(() {
                                flows[index].amount = v.roundToDouble();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: CommonWidgets.txt(
              'Note: Negative for investments, positive for withdrawals/current value.',
              style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
          ),
        ],
      ),
    );
  }
}
