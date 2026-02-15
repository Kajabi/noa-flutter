import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/style.dart';
import 'package:noa/widgets/bottom_nav_bar.dart';
import 'package:noa/widgets/top_title_bar.dart';

class TunePage extends ConsumerWidget {
  const TunePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alwaysOn = ref.watch(app.model.select((v) => v.alwaysOnListening));
    final chunkDuration =
        ref.watch(app.model.select((v) => v.chunkDurationSeconds));

    String speedLabel;
    if (chunkDuration <= 2) {
      speedLabel = "Fastest";
    } else if (chunkDuration <= 3) {
      speedLabel = "Fast";
    } else {
      speedLabel = "Normal";
    }

    return Scaffold(
      backgroundColor: colorWhite,
      appBar: topTitleBar(context, 'SETTINGS', false, false),
      body: Padding(
        padding: const EdgeInsets.only(left: 42, right: 42),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text("Always-On Listening",
                        style: textStyleLightSubHeading),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text("Off", style: textStyleDark),
                      ),
                      Switch(
                        value: alwaysOn,
                        activeColor: colorDark,
                        inactiveTrackColor: colorWhite,
                        inactiveThumbColor: colorLight,
                        onChanged: (value) {
                          ref.read(app.model.select(
                              (v) => v.alwaysOnListening = value));
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8, left: 8),
                        child: Text("On", style: textStyleDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                        "Transcription Speed — $speedLabel (${chunkDuration}s)",
                        style: textStyleLightSubHeading),
                  ),
                  Row(
                    children: [
                      const Text("Faster", style: textStyleDark),
                      Expanded(
                        child: Slider(
                          value: chunkDuration.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          activeColor: colorDark,
                          inactiveColor: colorLight,
                          onChanged: (value) {
                            ref.read(app.model).chunkDurationSeconds =
                                value.round();
                          },
                        ),
                      ),
                      const Text("Accurate", style: textStyleDark),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomNavBar(context, 1, false),
    );
  }
}
