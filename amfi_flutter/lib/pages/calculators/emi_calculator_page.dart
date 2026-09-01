import 'package:flutter/material.dart';
import 'dart:math';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class EmiCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const EmiCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<EmiCalculatorPage> createState() => _EmiCalculatorPageState();
}

class _EmiCalculatorPageState extends State<EmiCalculatorPage> {
  double loanAmount = 1000000;
  double interestRate = 8.5;
  double tenure = 20;

  @override
  Widget build(BuildContext context) {
    double r = interestRate / 12 / 100;
    double n = tenure * 12;
    
    double emi = (loanAmount * r * pow(1 + r, n)) / (pow(1 + r, n) - 1);
    double totalPayment = emi * n;
    double totalInterest = totalPayment - loanAmount;

    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt(
          'Loan EMI Calculator',
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
              title: 'Monthly EMI',
              value: '₹${CommonWidgets.formatCurrency(emi)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcInput(
              label: 'Loan Amount',
              value: loanAmount,
              min: 100000,
              max: 100000000,
              prefix: '₹',
              onChanged: (val) => setState(() => loanAmount = val),
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
              label: 'Tenure',
              value: tenure,
              min: 1,
              max: 30,
              suffix: ' Yr',
              onChanged: (val) => setState(() => tenure = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcSummaryRow(
              label: 'Principal Amount',
              value: '₹${CommonWidgets.formatCurrency(loanAmount)}',
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
              label: 'Total Payment',
              value: '₹${CommonWidgets.formatCurrency(totalPayment)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
          ],
        ),
      ),
    );
  }
}
