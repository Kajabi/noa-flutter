import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/pages/pairing.dart';
import 'package:noa/style.dart';
import 'package:noa/util/switch_page.dart';

class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  late TextEditingController _endpointController;
  late TextEditingController _headerKeyController;
  late TextEditingController _headerValueController;

  @override
  void initState() {
    super.initState();
    final model = ref.read(app.model);
    _endpointController = TextEditingController(text: model.apiEndpoint);
    _headerKeyController = TextEditingController(text: model.apiToken);
    _headerValueController = TextEditingController(text: model.apiHeader);
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _headerKeyController.dispose();
    _headerValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.watch(app.model).state.current != app.State.waitForLogin) {
        switchPage(context, const PairingPage());
      }
    });

    return Scaffold(
      backgroundColor: colorWhite,
      appBar: AppBar(
        backgroundColor: colorWhite,
        title: const Text('NOA SETUP', style: textStyleDarkTitle),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 42),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Configure your AI server', style: textStyleLight),
              const SizedBox(height: 30),
              _buildField('API Endpoint', _endpointController, 'https://your-server.com/api'),
              const SizedBox(height: 20),
              _buildField('Header Key', _headerKeyController, 'Authorization'),
              const SizedBox(height: 20),
              _buildField('Header Value', _headerValueController, 'Bearer your-token'),
              const SizedBox(height: 40),
              Center(
                child: GestureDetector(
                  onTap: _saveAndConnect,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                    decoration: BoxDecoration(
                      color: colorDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Save & Connect', style: textStyleWhite),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: textStyleLightSubHeading),
        ),
        Container(
          decoration: const BoxDecoration(
            color: colorLight,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: TextFormField(
            controller: controller,
            onTapOutside: (event) => FocusScope.of(context).unfocus(),
            style: textStyleDark,
            decoration: InputDecoration.collapsed(
              fillColor: colorLight,
              filled: true,
              hintText: hint,
              hintStyle: textStyleLight,
            ),
          ),
        ),
      ],
    );
  }

  void _saveAndConnect() {
    final endpoint = _endpointController.text.trim();
    final headerKey = _headerKeyController.text.trim();
    final headerValue = _headerValueController.text.trim();

    if (endpoint.isEmpty) return;

    final m = ref.read(app.model);
    m.apiEndpoint = endpoint;
    m.apiToken = headerKey;
    m.apiHeader = headerValue;
    m.customServer = true;
    m.setUserAuthToken('custom-server');
  }
}
