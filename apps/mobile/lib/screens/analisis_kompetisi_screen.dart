import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// AnalisisKompetisiScreen — Figma node 11:1556 ("Analisis kompetisi").
/// Form input sumber kompetisi (Upload PDF / Masukkan Link) + tujuan analisis.
class AnalisisKompetisiScreen extends StatefulWidget {
  const AnalisisKompetisiScreen({super.key, this.onSubmit});

  final VoidCallback? onSubmit;

  @override
  State<AnalisisKompetisiScreen> createState() =>
      _AnalisisKompetisiScreenState();
}

class _AnalisisKompetisiScreenState extends State<AnalisisKompetisiScreen> {
  int _mode = 0; // 0 = Upload PDF, 1 = Masukkan Link
  PlatformFile? _picked;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _picked = result.files.first);
    }
  }

  String _fmtSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: back + eyebrow + judul
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: C.card,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_left,
                      color: C.accent, size: 22),
                ),
                const SizedBox(height: 12),
                const Text(
                  'KEPUTUSAN BARU',
                  style: TextStyle(
                    color: C.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Analisis kompetisi',
                  style: TextStyle(color: C.white, fontSize: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const HeaderDivider(),
          const SizedBox(height: 16),

          // Sub-heading
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analisis Kompetisi Baru',
                  style: TextStyle(
                    color: C.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Masukkan sumber kompetisi untuk dianalisa',
                  style: TextStyle(color: C.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Segmented: Upload PDF / Masukkan Link
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _segment('Upload PDF', 0)),
                const SizedBox(width: 12),
                Expanded(child: _segment('Masukkan Link', 1)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Dropzone atau input link
          if (_mode == 0) _dropzone() else _linkInput(),
          const SizedBox(height: 14),

          // Tujuan analisis
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tujuan Analisis (opsional)',
                  style: TextStyle(color: C.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: C.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const TextField(
                    style: TextStyle(color: C.white, fontSize: 13),
                    cursorColor: C.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Contoh: Validasi ide dan portofolio...',
                      hintStyle:
                          TextStyle(color: C.navInactive, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Submit
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: widget.onSubmit,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: C.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.auto_awesome, color: C.bg, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Submit & Mulai Analisis',
                      style: TextStyle(
                        color: C.bg,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Analisis membantu pengambilan keputusan. Anda tetap menentukan rencana dan perubahan kalender.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.navInactive, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, int index) {
    final active = index == _mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? C.accent : C.card,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? C.bg : C.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _dropzone() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DottedBorderBox(
        child: _picked == null ? _emptyDropzone() : _pickedPreview(),
      ),
    );
  }

  Widget _emptyDropzone() {
    return Column(
      children: [
        const Icon(Icons.file_upload_outlined, color: C.white, size: 28),
        const SizedBox(height: 10),
        const Text(
          'Seret file PDF atau foto ke sini',
          style: TextStyle(color: C.white, fontSize: 14),
        ),
        const SizedBox(height: 6),
        const Text('atau',
            style: TextStyle(color: C.navInactive, fontSize: 12)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: C.accent),
            ),
            child: const Text('Pilih File',
                style: TextStyle(color: C.accent, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Maks. 10MB · PDF atau Foto',
          style: TextStyle(color: C.navInactive, fontSize: 11),
        ),
      ],
    );
  }

  Widget _pickedPreview() {
    final f = _picked!;
    final ext = (f.extension ?? '').toLowerCase();
    final isImage =
        ['png', 'jpg', 'jpeg', 'webp', 'heic'].contains(ext);
    return Column(
      children: [
        Icon(
          isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
          color: C.accent,
          size: 28,
        ),
        const SizedBox(height: 10),
        Text(
          f.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: C.white, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Text(
          _fmtSize(f.size),
          style: const TextStyle(color: C.navInactive, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: C.accent),
                ),
                child: const Text('Ganti File',
                    style: TextStyle(color: C.accent, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _picked = null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: C.navInactive),
                ),
                child: const Text('Hapus',
                    style: TextStyle(color: C.navInactive, fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _linkInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const TextField(
          style: TextStyle(color: C.white, fontSize: 13),
          cursorColor: C.accent,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: 'https://... link halaman kompetisi',
            hintStyle: TextStyle(color: C.navInactive, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
