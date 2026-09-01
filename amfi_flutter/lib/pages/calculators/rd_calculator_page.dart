import 'package:flutter/material.dart';
import 'dart:math';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class RdCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const RdCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<RdCalculatorPage> createState() => _RdCalculatorPageState();
}

class _RdCalculatorPageState extends State<RdCalculatorPage> {
  double monthlyInvestment = 5000;
  double interestRate = 7;
  double timePeriod = 5;

  @override
  Widget build(BuildContext context) {
    // Formula for RD with quarterly compounding
    double i = interestRate / 400;
    double n = timePeriod * 12;
    double maturityValue = monthlyInvestment * (pow(1 + i, 4 * timePeriod) - 1) / (1 - pow(1 + i, -1 / 3));
    
    double totalInvested = monthlyInvestment * n;
    double totalInterest = maturityValue - totalInvested;

    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt(
          'RD Calculator',
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
              title: 'Maturity Value',
              value: '₹${CommonWidgets.formatCurrency(maturityValue)}',
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
              label: 'Interest Rate (p.a)',
              value: interestRate,
              min: 1,
              max: 20,
              suffix: '%',
              step: 0.25,
              onChanged: (val) => setState(() => interestRate = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcInput(
              label: 'Time Period',
              value: timePeriod,
              min: 1,
              max: 30,
              suffix: ' Yr',
              onChanged: (val) => setState(() => timePeriod = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcSummaryRow(
              label: 'Total Invested',
              value: '₹${CommonWidgets.formatCurrency(totalInvested)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcSummaryRow(
              label: 'Total Interest',
              value: '₹${CommonWidgets.formatCurrency(totalInterest)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcSummaryRow(
              label: 'Maturity Value',
              value: '₹${CommonWidgets.formatCurrency(maturityValue)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
          ],
        ),
      ),
    );
  }
}
