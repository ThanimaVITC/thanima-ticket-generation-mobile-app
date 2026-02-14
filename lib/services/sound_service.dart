import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _successPlayer = AudioPlayer();
  final AudioPlayer _errorPlayer = AudioPlayer();

  Future<void> playSuccess() async {
    await _successPlayer.play(AssetSource('success.wav'));
  }

  Future<void> playError() async {
    await _errorPlayer.play(AssetSource('error.wav'));
  }

  void dispose() {
    _successPlayer.dispose();
    _errorPlayer.dispose();
  }
}
