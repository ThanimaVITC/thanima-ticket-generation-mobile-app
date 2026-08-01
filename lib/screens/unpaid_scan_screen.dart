import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../services/api_service.dart';
import '../services/id_card_parser.dart';
import '../services/sound_service.dart';

// Align -> capture -> OCR -> confirm (and correct) -> save.
enum _Step { aligning, reading, confirming, saving, done }

// We frame only the name + registration-number band at the bottom of the card,
// not the whole 5.5 x 8.5 cm card. Getting close to just those two lines fills
// the sensor with the text that matters, so ML Kit sees far more pixels per
// character and none of the institutional boilerplate above it.
//
// Kept as centimetres so the source of the ratio is obvious if the cards are
// ever re-measured. Screens have no fixed physical scale, so only the ratio
// survives: 5.5/1.6 = 3.44.
const double _slotWidthCm = 5.5;
const double _slotHeightCm = 1.6;
const double _slotAspect = _slotWidthCm / _slotHeightCm;

/// How much of the preview width the slot may take up.
const double _slotWidthFraction = 0.86;

/// The preview itself is a band rather than a full-height viewfinder — there
/// is nothing useful to see above or below the two lines being read.
const double _previewHeightFraction = 0.42;

/// Runs on a background isolate — must stay top-level.
///
/// Bakes EXIF orientation first: the crop is expressed in display coordinates,
/// but the JPEG the camera writes is usually stored sideways with a rotation
/// tag, so cropping the raw pixels would take a slice of the wrong edge.
Uint8List? _cropCentred((Uint8List, double, double) request) {
  final (bytes, widthFraction, heightFraction) = request;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);

  final width = (oriented.width * widthFraction).round().clamp(1, oriented.width);
  final height =
      (oriented.height * heightFraction).round().clamp(1, oriented.height);
  final x = ((oriented.width - width) / 2).round();
  final y = ((oriented.height - height) / 2).round();

  final cropped =
      img.copyCrop(oriented, x: x, y: y, width: width, height: height);
  return img.encodeJpg(cropped, quality: 95);
}

class UnpaidScanScreen extends StatefulWidget {
  final String eventId;

  const UnpaidScanScreen({super.key, required this.eventId});

  @override
  State<UnpaidScanScreen> createState() => _UnpaidScanScreenState();
}

class _UnpaidScanScreenState extends State<UnpaidScanScreen> {
  final ApiService _apiService = ApiService();
  final SoundService _soundService = SoundService();
  final TextRecognizer _recognizer = TextRecognizer();

  CameraController? _camera;
  bool _cameraReady = false;
  String? _cameraError;
  bool _torchOn = false;

  _Step _step = _Step.aligning;
  String _message = '';
  bool _success = false;

  final _nameController = TextEditingController();
  final _regNoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    _recognizer.close();
    _nameController.dispose();
    _regNoController.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        // 720p leaves too few pixels on a 1.6 cm strip of text once it has
        // been cropped out; small characters end up mush. Text recognition is
        // resolution-hungry, so pay for the bigger frame here.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      // Pin metering to the middle of the frame, which is where the slot is.
      // Otherwise the camera happily focuses on the desk behind the card.
      try {
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } catch (_) {}
      // Laminated cards throw a lot of glare, so leave the flash off until
      // staff ask for it rather than firing it on every shot.
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'Could not start the camera: $e');
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null || !_cameraReady) return;

    final next = !_torchOn;
    try {
      // torch keeps the light on for framing; 'off' rather than 'auto' so the
      // preview matches what the capture will look like.
      await camera.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _torchOn = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This camera has no flash'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !_cameraReady) return;

    setState(() {
      _step = _Step.reading;
      _message = '';
    });

    // Measured before the await, while the preview is still laid out.
    final crop = _slotCropFractions();

    try {
      final file = await camera.takePicture();

      // Hand ML Kit only the strip staff framed. Everything else on the card
      // — the logo, the four institutional lines, the photo, whatever the
      // card is lying on — is noise competing for the recogniser's attention.
      final slotPath = await _writeSlotCrop(file.path, crop);

      final recognized = await _recognizer.processImage(
        InputImage.fromFilePath(slotPath ?? file.path),
      );
      final scan = IdCardParser.parse(_inReadingOrder(recognized));

      // Best effort: clean up the temp photos, but never fail the scan over it.
      for (final path in [file.path, ?slotPath]) {
        try {
          await File(path).delete();
        } catch (_) {}
      }

      if (!mounted) return;

      _nameController.text = scan.name ?? '';
      _regNoController.text = scan.regNo ?? '';

      if (scan.isComplete) {
        _soundService.playSuccess();
      } else {
        _soundService.playError();
      }

      setState(() {
        _step = _Step.confirming;
        _message = scan.isComplete
            ? 'Check both fields before saving.'
            : scan.regNo == null && scan.name == null
                ? 'Nothing readable on that photo. Retake it, or type the details in.'
                : 'Only part of the card was readable — fill in the rest.';
      });
    } catch (e) {
      if (!mounted) return;
      _soundService.playError();
      setState(() {
        _step = _Step.confirming;
        _message = 'Could not read the card: $e';
      });
    }
  }

  /// Where the on-screen slot sits within the captured photo, as centred
  /// width/height fractions.
  ///
  /// The preview is cover-fitted into a short band, so the visible image is
  /// already a crop of the sensor. Work out how much of the photo the band
  /// actually shows, then what share of *that* the slot covers.
  (double, double) _slotCropFractions() {
    const fallback = (0.9, 0.28);

    final preview = _camera?.value.previewSize;
    if (preview == null) return fallback;

    final screen = MediaQuery.sizeOf(context);
    final bandWidth = screen.width;
    final bandHeight = screen.height * _previewHeightFraction;
    if (bandWidth <= 0 || bandHeight <= 0) return fallback;

    // previewSize is reported landscape; portrait width/height are swapped.
    final sensorAspect = preview.height / preview.width;

    // BoxFit.cover: whichever axis needs more scaling wins, the other crops.
    final double shownWidth, shownHeight;
    if (bandWidth / bandHeight > sensorAspect) {
      shownWidth = bandWidth;
      shownHeight = bandWidth / sensorAspect;
    } else {
      shownHeight = bandHeight;
      shownWidth = bandHeight * sensorAspect;
    }

    var slotWidth = bandWidth * _slotWidthFraction;
    var slotHeight = slotWidth / _slotAspect;
    final maxSlotHeight = bandHeight * 0.7;
    if (slotHeight > maxSlotHeight) {
      slotHeight = maxSlotHeight;
      slotWidth = slotHeight * _slotAspect;
    }

    // 12% slack so a slightly misaligned card doesn't get its text sheared off
    // — a clipped character is far worse than a little extra background.
    final widthFraction = (slotWidth / shownWidth * 1.12).clamp(0.1, 1.0);
    final heightFraction = (slotHeight / shownHeight * 1.12).clamp(0.05, 1.0);

    return (widthFraction, heightFraction);
  }

  /// Crops the photo to the slot and writes it beside the original.
  /// Returns null on any failure so the caller falls back to the full frame.
  Future<String?> _writeSlotCrop(String path, (double, double) crop) async {
    try {
      final bytes = await File(path).readAsBytes();
      // Decoding a 1080p JPEG in pure Dart takes a few hundred ms; off the UI
      // isolate so the progress bar keeps animating.
      final cropped = await compute(_cropCentred, (bytes, crop.$1, crop.$2));
      if (cropped == null) return null;

      final out = File('$path.slot.jpg');
      await out.writeAsBytes(cropped);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  /// `recognized.text` concatenates blocks in ML Kit's own emission order,
  /// which is not reliably top-to-bottom — on this card the logo, "VIT" and
  /// the campus line are separate blocks that can come back interleaved.
  ///
  /// The parser's whole strategy is "the name is the line above the reg no",
  /// so sort every line by where it physically sits on the card before
  /// handing the text over. Without this the rule is a coin flip.
  String _inReadingOrder(RecognizedText recognized) {
    final lines = [
      for (final block in recognized.blocks) ...block.lines,
    ];
    if (lines.isEmpty) return recognized.text;

    lines.sort((a, b) {
      final ab = a.boundingBox;
      final bb = b.boundingBox;
      // Treat two lines as the same visual row when they overlap vertically
      // by more than half the shorter one, then read that row left to right.
      final shorter = ab.height < bb.height ? ab.height : bb.height;
      if ((ab.center.dy - bb.center.dy).abs() <= shorter * 0.5) {
        return ab.left.compareTo(bb.left);
      }
      return ab.center.dy.compareTo(bb.center.dy);
    });

    return lines.map((l) => l.text).join('\n');
  }

  Future<void> _retake() async {
    _nameController.clear();
    _regNoController.clear();
    setState(() {
      _step = _Step.aligning;
      _message = '';
    });
  }

  Future<void> _save() async {
    setState(() {
      _step = _Step.saving;
      _message = '';
    });

    final result = await _apiService.addUnpaid(
      widget.eventId,
      _nameController.text,
      _regNoController.text,
      source: 'ocr',
    );
    if (!mounted) return;

    final data = Map<String, dynamic>.from(result['data'] ?? {});
    final status = result['statusCode'] as int? ?? 0;

    if (status == 201 || data['ok'] == true) {
      _soundService.playSuccess();
      setState(() {
        _step = _Step.done;
        _success = true;
        _message =
            '${_nameController.text} (${_regNoController.text}) added to the unpaid list';
      });
      return;
    }

    _soundService.playError();
    setState(() {
      _step = _Step.done;
      _success = false;
      _message = data['error']?.toString() ?? 'Could not add this person';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Scan ID Card',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          if (_step == _Step.aligning && _cameraReady)
            IconButton(
              color: Colors.white,
              iconSize: 30,
              tooltip: _torchOn ? 'Turn flash off' : 'Turn flash on',
              icon: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                color: _torchOn ? Colors.yellow : Colors.grey,
              ),
              onPressed: _toggleTorch,
            ),
        ],
      ),
      body: switch (_step) {
        _Step.aligning => _buildCamera(),
        _Step.reading => _buildReading(),
        _Step.confirming || _Step.saving => _buildConfirm(),
        _Step.done => _buildDone(),
      },
    );
  }

  /// The camera preview is deliberately gone while the photo is processed —
  /// a live preview implies you still need to hold the card steady, when in
  /// fact the shot is already taken.
  Widget _buildReading() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.document_scanner,
                size: 52, color: Colors.amber.shade700),
          ),
          const SizedBox(height: 28),
          const Text(
            'Reading the card…',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Photo captured. You can lower the card.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                style: const TextStyle(color: Colors.grey, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady || _camera == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final previewHeight =
        MediaQuery.sizeOf(context).height * _previewHeightFraction;

    return Column(
      children: [
        SizedBox(
          height: previewHeight,
          width: double.infinity,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // CameraPreview stretches to whatever box it is given, so in a
                // short band it would distort. Cover-fit the sensor's own
                // aspect ratio instead and let the sides crop.
                _coveredPreview(),
                CustomPaint(painter: _SlotFramePainter(), size: Size.infinite),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF1E293B),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                const Text(
                  'Fit just the name and number in the box',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Move in close — the two lines should fill the width',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _capture,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Cover-fit the camera into the short band without squashing it: hand
  /// CameraPreview a box with the sensor's own aspect ratio and let FittedBox
  /// scale it up until the band is filled, cropping the overflow.
  Widget _coveredPreview() {
    final preview = _camera!.value.previewSize;
    if (preview == null) return CameraPreview(_camera!);

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        // previewSize is reported in sensor orientation (landscape), so the
        // sides are swapped for a portrait preview.
        width: preview.height,
        height: preview.width,
        child: CameraPreview(_camera!),
      ),
    );
  }

  // Both fields stay editable: OCR gets it right most of the time, and a
  // two-second correction beats a dead end when it doesn't.
  Widget _buildConfirm() {
    final saving = _step == _Step.saving;
    final canSave = _nameController.text.trim().length >= 2 &&
        IdCardParser.regNoPattern.hasMatch(
          _regNoController.text.replaceAll(RegExp(r'[\s._/-]'), '').toUpperCase(),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.badge, size: 44, color: Colors.amber.shade700),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Confirm the details',
              style: TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                _message,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            enabled: !saving,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: _fieldDecoration('Name', 'Arjun Menon'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _regNoController,
            enabled: !saving,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontFamily: 'monospace'),
            decoration: _fieldDecoration('Registration Number', '23BCE1042'),
          ),
          if (_regNoController.text.isNotEmpty && !canSave) ...[
            const SizedBox(height: 8),
            const Text(
              'Registration number must look like 23BCE1042',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: saving || !canSave ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.check),
            label: Text(saving ? 'Adding…' : 'Add to Unpaid List'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: saving ? null : _retake,
            icon: const Icon(Icons.replay),
            label: const Text('Retake photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDone() {
    final color = _success ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(_success ? Icons.check_circle : Icons.error_outline,
                size: 56, color: color),
          ),
          const SizedBox(height: 24),
          Text(
            _message,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                child: const Text('Done'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _retake,
                icon: const Icon(Icons.document_scanner),
                label: const Text('Scan another'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.grey),
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.amberAccent),
      ),
    );
  }
}

/// Dims the preview except for the name/reg-no slot, with corner brackets.
class _SlotFramePainter extends CustomPainter {
  /// Largest 5.5:1.6 slot that fits the preview band — width-bound in
  /// practice, with a height clamp so it can never overrun a short preview.
  Rect _frame(Size size) {
    var width = size.width * _slotWidthFraction;
    var height = width / _slotAspect;

    final maxHeight = size.height * 0.7;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * _slotAspect;
    }

    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = _frame(size);
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(12));

    // Scrim everywhere except the card window.
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.6));

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.amberAccent.withValues(alpha: 0.9),
    );

    // Corner brackets — the usual "line it up here" affordance.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.amberAccent;
    const len = 26.0;

    for (final (corner, dx, dy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner.translate(len * dx, 0), bracket);
      canvas.drawLine(corner, corner.translate(0, len * dy), bracket);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
