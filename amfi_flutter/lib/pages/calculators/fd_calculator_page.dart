import 'package:flutter/material.dart';
import 'dart:math';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class FdCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const FdCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<FdCalculatorPage> createState() => _FdCalculatorPageState();
}

class _FdCalculatorPageState extends State<FdCalculatorPage> {
  double totalInvestment = 100000;
  double interestRate = 7;
  double timePeriod = 5;

  @override
  Widget build(BuildContext context) {
    // Assuming quarterly compounding
    double maturityValue = totalInvestment * pow(1 + (interestRate / 400), 4 * timePeriod);
    double totalInterest = maturityValue - totalInvestment;

    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt(
          'FD Calculator',
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
              label: 'Total Investment',
              value: totalInvestment,
              min: 1000,
              max: 10000000,
              prefix: '₹',
              onChanged: (val) => setState(() => totalInvestment = val),
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
              label: 'Invested Amount',
              value: '₹${CommonWidgets.formatCurrency(totalInvestment)}',
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
