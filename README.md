# Noa — Always-On Speech-to-Text for Frame AR Glasses

A Flutter app for [Brilliant Labs Frame](https://brilliant.xyz/products/frame) AR glasses that provides real-time, always-on speech-to-text transcription displayed directly on the Frame's heads-up display.

## What it does

Noa continuously listens through the Frame's microphone, transcribes speech in real-time using [Deepgram](https://deepgram.com/), and displays the text on the Frame's AR display with speaker diarization (color-coded by speaker).

The app also supports a tap-to-query mode where tapping the glasses captures audio and a photo, sends them to an AI backend, and displays the response on the Frame.

## Getting started

1. Ensure you have Xcode and/or Android Studio correctly set up for app development

1. Install [Flutter](https://docs.flutter.dev/get-started/install)

1. Clone this repository

    ```sh
    git clone https://github.com/Kajabi/noa-flutter.git
    cd noa-flutter
    ```

1. Get the required packages

    ```sh
    flutter pub get
    ```

1. Copy `.env.template` to `.env` and populate it with your API keys

    ```sh
    cp .env.template .env
    ```

1. Connect your phone and run the app

    ```sh
    flutter run --release
    ```

## Hardware requirements

- [Brilliant Labs Frame](https://brilliant.xyz/products/frame) AR glasses
- iOS or Android device with Bluetooth LE support
