import 'package:flutter/material.dart';
import 'package:noa/style.dart';

AppBar topTitleBar(
    BuildContext context, String title, bool darkMode, bool accountPage) {
  return AppBar(
    toolbarHeight: 84,
    automaticallyImplyLeading: false,
    backgroundColor: darkMode ? colorDark : colorWhite,
    scrolledUnderElevation: 0,
    title: Text(
      title,
      style: darkMode ? textStyleWhiteTitle : textStyleDarkTitle,
    ),
    centerTitle: false,
    titleSpacing: 42,
  );
}
