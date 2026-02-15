import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger("STT API");

class SpeakerSegment {
  final int speaker;
  final String text;

  SpeakerSegment({required this.speaker, required this.text});
}

class SttResult {
  final String transcript;
  final List<SpeakerSegment> speakers;

  SttResult({required this.transcript, required this.speakers});
}

class SttApi {
  static Future<SttResult> transcribe(Uint8List wavData) async {
    final apiKey = dotenv.env['DEEPGRAM_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      _log.warning("DEEPGRAM_API_KEY not set");
      return SttResult(transcript: '', speakers: []);
    }

    try {
      final response = await http.post(
        Uri.parse(
            'https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true&diarize=true&paragraphs=true'),
        headers: {
          'Authorization': 'Token $apiKey',
          'Content-Type': 'audio/wav',
        },
        body: wavData,
      );

      if (response.statusCode != 200) {
        _log.warning(
            "Deepgram API error: ${response.statusCode} ${response.body}");
        return SttResult(transcript: '', speakers: []);
      }

      final body = jsonDecode(response.body);
      final channels = body['results']?['channels'];
      if (channels == null || (channels as List).isEmpty) {
        return SttResult(transcript: '', speakers: []);
      }

      final alternatives = channels[0]['alternatives'];
      if (alternatives == null || (alternatives as List).isEmpty) {
        return SttResult(transcript: '', speakers: []);
      }

      final transcript = alternatives[0]['transcript'] ?? '';
      if (transcript.isEmpty) {
        return SttResult(transcript: '', speakers: []);
      }

      // Parse speaker diarization from paragraphs
      final List<SpeakerSegment> segments = [];
      final paragraphs =
          alternatives[0]['paragraphs']?['paragraphs'] as List?;
      if (paragraphs != null) {
        for (final paragraph in paragraphs) {
          final speaker = paragraph['speaker'] as int? ?? 0;
          final sentences = paragraph['sentences'] as List? ?? [];
          for (final sentence in sentences) {
            final text = sentence['text'] as String? ?? '';
            if (text.isNotEmpty) {
              segments.add(SpeakerSegment(speaker: speaker, text: text));
            }
          }
        }
      }

      _log.info(
          "Transcribed: ${transcript.length} chars, ${segments.length} segments");

      return SttResult(transcript: transcript, speakers: segments);
    } catch (error) {
      _log.warning("STT error: $error");
      return SttResult(transcript: '', speakers: []);
    }
  }
}
