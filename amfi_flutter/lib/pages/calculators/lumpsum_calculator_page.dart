import 'package:flutter/material.dart';
import 'dart:math';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class LumpsumCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const LumpsumCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<LumpsumCalculatorPage> createState() => _LumpsumCalculatorPageState();
}

class _LumpsumCalculatorPageState extends State<LumpsumCalculatorPage> {
  double totalInvestment = 25000;
  double returnRate = 12;
  double timePeriod = 10;

  @override
  Widget build(BuildContext context) {
    double futureValue = totalInvestment * pow(1 + (returnRate / 100), timePeriod);
    double estReturns = futureValue - totalInvestment;

    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt(
          'Lumpsum Calculator',
          selectedLanguage: widget.selectedLanguage,
          translate: widget.translate,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo[900],
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CalcResultCard(
              title: 'Total Value',
              value: '₹${CommonWidgets.formatCurrency(futureValue)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcInput(
              label: 'Total Investment',
              value: totalInvestment,
              min: 500,
              max: 10000000,
              prefix: '₹',
              onChanged: (val) => setState(() => totalInvestment = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcInput(
              label: 'Expected Return Rate (p.a)',
              value: returnRate,
              min: 1,
              max: 30,
              suffix: '%',
              step: 0.25,
              onChanged: (val) => setState(() => returnRate = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcInput(
              label: 'Time Period',
              value: timePeriod,
              min: 1,
              max: 40,
              suffix: ' Yr',
              onChanged: (val) => setState(() => timePeriod = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcSummaryRow(
              label: 'Invested Amount',
              value: '₹${CommonWidgets.formatCurrency(totalInvestment)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcSummaryRow(
              label: 'Est. Returns',
              value: '₹${CommonWidgets.formatCurrency(estReturns)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcSummaryRow(
              label: 'Total Value',
              value: '₹${CommonWidgets.formatCurrency(futureValue)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
          ],
        ),
      ),
    );
  }
}
