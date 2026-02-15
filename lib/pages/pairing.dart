import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/pages/noa.dart';
import 'package:noa/style.dart';
import 'package:noa/util/switch_page.dart';
import 'package:url_launcher/url_launcher.dart';

class PairingPage extends ConsumerWidget {
  const PairingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.watch(app.model).state.current == app.State.connected ||
          ref.watch(app.model).state.current == app.State.disconnected) {
        switchPage(context, const NoaPage());
      }
    });

    final currentState = ref.watch(app.model).state.current;
    final isRepairState = currentState == app.State.requiresRepair;

    String pairingBoxText = "";
    String pairingBoxButtonText = "";
    Image pairingBoxImage = Image.asset('assets/images/charge.gif');
    bool pairingBoxButtonEnabled = false;
    int updateProgress = ref.watch(app.model).bluetoothUploadProgress.toInt();
    int scriptProgress = ref.watch(app.model).scriptProgress.toInt();
    String deviceName = ref.watch(app.model).deviceName;

    switch (currentState) {
      case app.State.scanning:
        pairingBoxText = "Bring your device close";
        pairingBoxButtonText = "Searching";
        pairingBoxButtonEnabled = false;
        break;
      case app.State.found:
        pairingBoxText = "$deviceName found";
        pairingBoxButtonText = "Pair";
        pairingBoxButtonEnabled = true;
        break;
      case app.State.connect:
      case app.State.stopLuaApp:
      case app.State.checkFirmwareVersion:
      case app.State.triggerUpdate:
        pairingBoxText = "$deviceName found";
        pairingBoxButtonText = "Connecting";
        pairingBoxButtonEnabled = false;
        break;
      case app.State.updateFirmware:
        pairingBoxText = "Updating software $updateProgress%";
        pairingBoxButtonText = "Keep your device close";
        pairingBoxButtonEnabled = false;
        break;
      case app.State.uploadMainLua:
        pairingBoxText = "Setting up $scriptProgress%";
        pairingBoxButtonText = "Keep your device close";
        pairingBoxButtonEnabled = false;
        break;
      case app.State.requiresRepair:
        pairingBoxText = "Pairing conflict";
        pairingBoxButtonText = "Try again";
        pairingBoxImage = Image.asset('assets/images/repair.gif');
        pairingBoxButtonEnabled = true;
        break;
      default:
        break;
    }

    return Scaffold(
      backgroundColor: colorDark,
      appBar: AppBar(
        backgroundColor: colorDark,
        title: Image.asset('assets/images/brilliant_logo.png'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                isRepairState ? "Unable to connect" : "Setup your device",
                style: textStyleLightHeading,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 22, left: 11, right: 11),
            decoration: const BoxDecoration(
              color: colorWhite,
              borderRadius: BorderRadius.all(Radius.circular(42)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20, right: 20),
                    child: GestureDetector(
                      onTap: () {
                        ref
                            .read(app.model)
                            .triggerEvent(app.Event.cancelPressed);
                        switchPage(context, const NoaPage());
                      },
                      child: const Icon(
                        Icons.cancel,
                        color: colorDark,
                      ),
                    ),
                  ),
                ),
                Text(
                  pairingBoxText,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: colorDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isRepairState)
                  SizedBox(
                    height: 200,
                    child: pairingBoxImage,
                  ),
                if (isRepairState)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 31, vertical: 16),
                    child: Column(
                      children: [
                        const Text(
                          "Frame is paired to another device or has a stale connection. To fix this:",
                          style: textStyleDark,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "1. Open iPhone Settings \u2192 Bluetooth\n"
                            "2. Find \"Frame\" and tap the \u24D8 icon\n"
                            "3. Tap \"Forget This Device\"\n"
                            "4. Come back here and tap Try again",
                            style: textStyleDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            final url = Uri.parse("App-Prefs:Bluetooth");
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: colorDark),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text("Open Bluetooth Settings",
                                style: textStyleDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    ref.read(app.model).triggerEvent(app.Event.buttonPressed);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: pairingBoxButtonEnabled ? colorDark : colorLight,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(20)),
                    ),
                    height: 50,
                    margin: const EdgeInsets.only(
                        left: 31, right: 31, bottom: 28),
                    child: Center(
                      child: Text(
                        pairingBoxButtonText,
                        style: textStyleWhiteWidget,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
