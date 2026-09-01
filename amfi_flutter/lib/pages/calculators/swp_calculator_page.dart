import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import 'calculator_widgets.dart';

class SwpCalculatorPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const SwpCalculatorPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<SwpCalculatorPage> createState() => _SwpCalculatorPageState();
}

class _SwpCalculatorPageState extends State<SwpCalculatorPage> {
  double totalInvestment = 500000;
  double monthlyWithdrawal = 5000;
  double returnRate = 8;
  double timePeriod = 10;

  @override
  Widget build(BuildContext context) {
    double i = returnRate / 12 / 100;
    int months = (timePeriod * 12).toInt();
    double balance = totalInvestment;
    double totalWithdrawn = 0;

    for (int m = 0; m < months; m++) {
      if (balance <= 0) {
        balance = 0;
        break;
      }
      totalWithdrawn += monthlyWithdrawal;
      balance = (balance - monthlyWithdrawal) * (1 + i);
    }
    
    if (balance < 0) balance = 0;
    
    double totalReturns = (balance + totalWithdrawn) - totalInvestment;

    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt(
          'SWP Calculator',
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
              title: 'Final Balance',
              value: '₹${CommonWidgets.formatCurrency(balance)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            const SizedBox(height: 24),
            CalcInput(
              label: 'Total Investment',
              value: totalInvestment,
              min: 50000,
              max: 10000000,
              prefix: '₹',
              onChanged: (val) => setState(() => totalInvestment = val),
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcInput(
              label: 'Monthly Withdrawal',
              value: monthlyWithdrawal,
              min: 500,
              max: 100000,
              prefix: '₹',
              onChanged: (val) => setState(() => monthlyWithdrawal = val),
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
              label: 'Total Investment',
              value: '₹${CommonWidgets.formatCurrency(totalInvestment)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcSummaryRow(
              label: 'Total Withdrawal',
              value: '₹${CommonWidgets.formatCurrency(totalWithdrawn)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
            CalcSummaryRow(
              label: 'Total Returns',
              value: '₹${CommonWidgets.formatCurrency(totalReturns)}',
              selectedLanguage: widget.selectedLanguage,
              translate: widget.translate,
            ),
          ],
        ),
      ),
    );
  }
}
