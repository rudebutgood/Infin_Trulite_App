import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import 'calculators/sip_calculator_page.dart';
import 'calculators/swp_calculator_page.dart';
import 'calculators/lumpsum_calculator_page.dart';
import 'calculators/fd_calculator_page.dart';
import 'calculators/rd_calculator_page.dart';
import 'calculators/emi_calculator_page.dart';
import 'calculators/xirr_calculator_page.dart';

class CalculatorsPage extends StatelessWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const CalculatorsPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.calculate, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: CommonWidgets.txt(
                'Calculators',
                style: const TextStyle(fontWeight: FontWeight.bold),
                selectedLanguage: selectedLanguage,
                translate: translate,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildCategoryHeader('Mutual Funds'),
          _buildCalcTile(
            context,
            'SWP',
            Icons.trending_down,
            SwpCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
          _buildCalcTile(
            context,
            'SIP',
            Icons.trending_up,
            SipCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
          _buildCalcTile(
            context,
            'Lumpsum',
            Icons.account_balance_wallet,
            LumpsumCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
          const SizedBox(height: 16),
          _buildCategoryHeader('Interest/EMI'),
          _buildCalcTile(
            context,
            'FD Interest',
            Icons.savings,
            FdCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
          _buildCalcTile(
            context,
            'Loan EMI Calculator',
            Icons.credit_card,
            EmiCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
          _buildCalcTile(
            context,
            'RD Calculator',
            Icons.timer,
            RdCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
          _buildCalcTile(
            context,
            'XIRR Calculator',
            Icons.pie_chart,
            XirrCalculatorPage(selectedLanguage: selectedLanguage, translate: translate),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: CommonWidgets.txt(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.indigo[700],
          letterSpacing: 1.2,
        ),
        selectedLanguage: selectedLanguage,
        translate: translate,
      ),
    );
  }

  Widget _buildCalcTile(BuildContext context, String title, IconData icon, Widget target) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.indigo[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.indigo[900], size: 20),
      ),
      title: CommonWidgets.txt(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
        selectedLanguage: selectedLanguage,
        translate: translate,
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => target));
      },
    );
  }
}
