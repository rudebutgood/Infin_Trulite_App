import 'package:flutter/material.dart';
import 'dart:math';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class SipCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const SipCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<SipCalculatorPage> createState() => _SipCalculatorPageState();
}

class _SipCalculatorPageState extends State<SipCalculatorPage> {
  double monthlyInvestment = 5000;
  double returnRate = 12;
  double timePeriod = 10;

  @override
  Widget build(BuildContext context) {
    double i = returnRate / 12 / 100;
    double n = timePeriod * 12;
    double futureValue = monthlyInvestment * ((pow(1 + i, n) - 1) / i) * (1 + i);
    double totalInvested = monthlyInvestment * n;
    double estReturns = futureValue - totalInvested;

    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt(
          'SIP Calculator',
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
              title: 'Estimated Returns',
              value: '₹${CommonWidgets.formatCurrency(futureValue)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcInput(
              label: 'Monthly Investment',
              value: monthlyInvestment,
              min: 500,
              max: 100000,
              prefix: '₹',
              onChanged: (val) => setState(() => monthlyInvestment = val),
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
              value: '₹${CommonWidgets.formatCurrency(totalInvested)}',
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
