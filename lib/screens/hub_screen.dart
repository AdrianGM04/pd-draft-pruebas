import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'die_designer.dart';
import 'pd_draft.dart';
import '../models/globals.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  String _selectedLanguage = "English";
  String _selectedSystem = "Metric";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  /// Cargar preferencias guardadas y abrir menú la primera vez
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    bool firstTime = prefs.getBool('firstTime') ?? false;

    setState(() {
      _selectedLanguage = prefs.getString('language') ?? "English";
      final savedSystem = prefs.getString('system') ?? "metric";
      _selectedSystem =
          savedSystem[0].toUpperCase() + savedSystem.substring(1).toLowerCase();
      globalSelectedSystem = savedSystem;
    });

    if (!firstTime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scaffoldKey.currentState?.openDrawer();
      });

      await prefs.setBool('firstTime', true);
    }
  }

  /// Guardar preferencias seleccionadas
  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('language', _selectedLanguage);
    await prefs.setString('system', _selectedSystem.toLowerCase());

    globalSelectedSystem = _selectedSystem.toLowerCase();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Preferences saved:\nLanguage: $_selectedLanguage\nUnit System: ${_selectedSystem.toLowerCase()}",
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildLanguageButtons() {
    final List<String> languages = ["English", "Español", "Français"];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Language:",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: languages.map((lang) {
            return ChoiceChip(
              label: Text(lang),
              selected: _selectedLanguage == lang,
              selectedColor: Colors.blueGrey,
              backgroundColor: Colors.grey.shade300,
              onSelected: (bool selected) {
                setState(() {
                  _selectedLanguage = lang;
                });
                _savePreferences();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSystemButtons() {
    final List<String> systems = ["Metric", "Imperial"];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Unit System:",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: systems.map((sys) {
            return ChoiceChip(
              label: Text(sys),
              selected: _selectedSystem == sys,
              selectedColor: Colors.blueGrey,
              backgroundColor: Colors.grey.shade300,
              onSelected: (bool selected) {
                setState(() {
                  _selectedSystem = sys;
                });
                _savePreferences();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: const Color(0xFFD3D8DC),
        centerTitle: true,
        toolbarHeight: 140,
        title: Image.asset(
          'assets/images/titulo5-logo.png',
          height: 110,
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFFD3D8DC)),
              child: Center(
                child: Text(
                  "Preferences",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            _buildLanguageButtons(),
            const SizedBox(height: 20),
            _buildSystemButtons(),
          ],
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD3D8DC),
                      ),
                      onPressed: () =>
                          _navigateTo(context, const OtraPantalla()),
                      child: const Text("PD Draft"),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD3D8DC),
                      ),
                      onPressed: () =>
                          _navigateTo(context, DieDesignerScreen()),
                      child: const Text("Die Designer"),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(3, 3),
                  ),
                ],
              ),
              child: const Text(
                "V 1.25.1",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
