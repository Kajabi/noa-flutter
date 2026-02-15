import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:noa/main.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/noa_api.dart';
import 'package:noa/pages/pairing.dart';
import 'package:noa/style.dart';
import 'package:noa/util/show_toast.dart';
import 'package:noa/util/switch_page.dart';
import 'package:noa/widgets/bottom_nav_bar.dart';
import 'package:noa/widgets/top_title_bar.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:uuid/uuid.dart';

final _log = Logger("NoaPage");

class NoaPage extends ConsumerStatefulWidget {
  const NoaPage({super.key});

  @override
  ConsumerState<NoaPage> createState() => _NoaPageState();
}

class _NoaPageState extends ConsumerState<NoaPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentState = ref.watch(app.model).state.current;
    final isConnected = currentState == app.State.connected;

    _log.info("NoaPage build — state: $currentState, connected: $isConnected");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (currentState) {
        case app.State.scanning:
        case app.State.found:
        case app.State.connect:
        case app.State.stopLuaApp:
        case app.State.checkFirmwareVersion:
        case app.State.uploadMainLua:
        case app.State.uploadGraphicsLua:
        case app.State.uploadStateLua:
        case app.State.triggerUpdate:
        case app.State.updateFirmware:
          _log.info("Redirecting to PairingPage for state: $currentState");
          switchPage(context, const PairingPage());
          break;
        default:
      }
      Timer(const Duration(milliseconds: 100), () {
        if (context.mounted) {
          ref.watch(app.model.select((value) {
            if (value.noaMessages.length > 6) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          }));
        }
      });
    });

    return Scaffold(
      backgroundColor: colorWhite,
      appBar: AppBar(
        toolbarHeight: 84,
        automaticallyImplyLeading: false,
        backgroundColor: colorWhite,
        scrolledUnderElevation: 0,
        title: const Text('CHAT', style: textStyleDarkTitle),
        centerTitle: false,
        titleSpacing: 42,
        actions: [
          if (!isConnected)
            Container(
              margin: const EdgeInsets.only(right: 42),
              child: GestureDetector(
                onTap: () {
                  _log.info("Pair button tapped — current state: $currentState");
                  ref.read(app.model).triggerEvent(app.Event.buttonPressed);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Pair', style: textStyleWhite),
                ),
              ),
            ),
        ],
      ),
      body: PageStorage(
        bucket: globalPageStorageBucket,
        child: ListView.builder(
          key: const PageStorageKey<String>('noaPage'),
          controller: _scrollController,
          itemCount: ref.watch(app.model).noaMessages.length,
          itemBuilder: (context, index) {
            TextStyle style = textStyleLight;
            final msg = ref.watch(app.model).noaMessages[index];
            if (msg.from == NoaRole.noa) {
              style = textStyleDark;
            }

            // Color speaker labels in always-on transcription
            final speakerColors = {
              'S1:': const Color(0xFF555555),
              'S2:': const Color(0xFFD4A017),
              'S3:': const Color(0xFF2E8B57),
              'S4:': const Color(0xFF4682B4),
              'S5:': colorPink,
            };
            Color? speakerColor;
            for (final prefix in speakerColors.keys) {
              if (msg.message.startsWith(prefix)) {
                speakerColor = speakerColors[prefix];
                break;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index == 0 ||
                    ref
                            .watch(app.model)
                            .noaMessages[index]
                            .time
                            .difference(ref
                                .watch(app.model)
                                .noaMessages[index - 1]
                                .time)
                            .inSeconds >
                        1700)
                  Container(
                    margin: const EdgeInsets.only(top: 40, left: 42, right: 42),
                    child: Row(
                      children: [
                        Text(
                          "${ref.watch(app.model).noaMessages[index].time.hour.toString().padLeft(2, '0')}:${ref.watch(app.model).noaMessages[index].time.minute.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: colorLight),
                        ),
                        const Flexible(
                          child: Divider(
                            indent: 10,
                            color: colorLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 10, left: 65, right: 42),
                  child: speakerColor != null
                      ? RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: msg.message.substring(0, 3),
                                style: style.copyWith(
                                    color: speakerColor,
                                    fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: msg.message.substring(3),
                                style: style,
                              ),
                            ],
                          ),
                        )
                      : Text(msg.message, style: style),
                ),
                if (msg.image != null)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorLight,
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(10.5),
                    ),
                    margin: const EdgeInsets.only(
                        top: 10, bottom: 10, left: 65, right: 65),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.fromSize(
                        child: GestureDetector(
                          onLongPress: () async {
                            await SaverGallery.saveImage(
                                msg.image!,
                                name: const Uuid().v1(),
                                androidExistNotSave: false);
                            if (context.mounted) {
                              showToast("Saved to photos", context);
                            }
                          },
                          child: Image.memory(msg.image!),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          padding: const EdgeInsets.only(bottom: 20),
        ),
      ),
      bottomNavigationBar: bottomNavBar(context, 0, false),
    );
  }
}
