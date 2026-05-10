import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordingStartTime;
  String? _tempMonitorPath;
  bool _isMonitoring = false;
  bool _isStreamRecording = false;
  RandomAccessFile? _streamFile;
  StreamSubscription<Uint8List>? _streamSub;
  int _streamDataLength = 0;
  double _streamAmplitude = -80;

  Future<bool> requestPermissions() async {
    final mic = await Permission.microphone.request();
    return mic.isGranted;
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    if (!await _recorder.hasPermission()) return;

    final tmpDir = await getTemporaryDirectory();
    _tempMonitorPath =
        '${tmpDir.path}/monitor_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        bitRate: 32000,
      ),
      path: _tempMonitorPath!,
    );
    _isMonitoring = true;
  }

  Future<double> getAmplitude() async {
    if (_isStreamRecording) return _streamAmplitude;
    final amp = await _recorder.getAmplitude();
    return amp.current;
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    await _recorder.stop();
    _isMonitoring = false;

    if (_tempMonitorPath != null) {
      final file = File(_tempMonitorPath!);
      if (await file.exists()) await file.delete();
      _tempMonitorPath = null;
    }
  }

  Future<String?> startRecording() async {
    if (!await _recorder.hasPermission()) return null;
    if (_isMonitoring) await stopMonitoring();

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final path = '${dir.path}/recording_$ts.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );

    _recordingStartTime = DateTime.now();
    return path;
  }

  Future<String?> startStreamingRecording({
    required void Function(Uint8List chunk) onAudioChunk,
  }) async {
    if (!await _recorder.hasPermission()) return null;
    if (_isMonitoring) await stopMonitoring();

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final path = '${dir.path}/recording_$ts.wav';
    final file = File(path);
    _streamFile = await file.open(mode: FileMode.write);
    await _streamFile!.writeFrom(_wavHeader(dataLength: 0));
    _streamDataLength = 0;
    _streamAmplitude = -80;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
        streamBufferSize: 4096,
      ),
    );

    _isStreamRecording = true;
    _recordingStartTime = DateTime.now();
    _streamSub = stream.listen((chunk) {
      _streamFile?.writeFromSync(chunk);
      _streamDataLength += chunk.length;
      _streamAmplitude = _pcmAmplitudeDb(chunk);
      onAudioChunk(chunk);
    });

    return path;
  }

  Future<Duration?> stopRecording() async {
    if (!await _recorder.isRecording()) return null;
    if (_isStreamRecording) {
      await _streamSub?.cancel();
      _streamSub = null;
    }
    await _recorder.stop();

    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : null;
    _recordingStartTime = null;
    if (_isStreamRecording) await _finalizeStreamWavFile();
    return duration;
  }

  Future<bool> isRecording() => _recorder.isRecording();
  bool get isMonitoring => _isMonitoring;

  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _finalizeStreamWavFile() async {
    final file = _streamFile;
    _streamFile = null;
    _isStreamRecording = false;
    _streamAmplitude = -80;
    if (file == null) return;
    await file.setPosition(0);
    await file.writeFrom(_wavHeader(dataLength: _streamDataLength));
    await file.close();
  }

  Uint8List _wavHeader({required int dataLength}) {
    final header = ByteData(44);
    const sampleRate = 24000;
    const channels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);
    return header.buffer.asUint8List();
  }

  double _pcmAmplitudeDb(Uint8List bytes) {
    if (bytes.length < 2) return -80;
    var sumSquares = 0.0;
    var count = 0;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768.0;
      sumSquares += sample * sample;
      count++;
    }
    if (count == 0) return -80;
    final rms = math.sqrt(sumSquares / count).clamp(0.0001, 1.0);
    return (20 * math.log(rms) / math.ln10).clamp(-80.0, 0.0);
  }

  void dispose() {
    _streamSub?.cancel();
    _streamFile?.close();
    _recorder.dispose();
  }
}
